{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ World Partition Hierarchical Level-of-Detail (HLOD) spatial cluster baker,
  single-draw-call merged proxy mesh synthesizer, and camera-distance
  hysteresis swapper (Phase 333 — Unreal Engine 6.0+ World Partition HLOD parity). }
unit CastleHlodBaker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Proxy mesh synthesis topology for each spatial HLOD cell. }
  THlodProxyMode = (
    { Bakes every clustered prop's world bounding box into a single shared
      vertex-colored TTriangleSetNode (1 draw call per cell while preserving
      block/rooftop silhouettes). }
    hpmClusteredBoxes,
    { Collapses the entire spatial cell's occupied bounding box into a single
      12-triangle hull (1 draw call + maximum polygon reduction). }
    hpmMergedCellBounds,
    { Synthesizes a 28-triangle octagonal architectural silhouette prism per
      cell (1 draw call with chamfered skyline profile). }
    hpmOctagonalPrism
  );

  { Per-prop snapshot captured inside an HLOD spatial cell. }
  THlodClusterPropItem = record
    PropName: String;
    WorldMin: TVector3;
    WorldMax: TVector3;
    ColorRGB: TVector3;
    EstimatedTris: Integer;
  end;

  { Baked spatial HLOD cell metadata and live camera-swap state. }
  THlodClusterCell = record
    CellX: Integer;
    CellZ: Integer;
    WorldMin: TVector3;
    WorldMax: TVector3;
    WorldCenter: TVector3;
    Props: array of THlodClusterPropItem;
    SourcePropCount: Integer;
    SourceTrianglesEstimate: Integer;
    ProxyTrianglesCount: Integer;
    UsingHlodProxy: Boolean;
    LastCameraDistance: Single;
    AvgColorRGB: TVector3;
  end;
  THlodClusterCellArray = array of THlodClusterCell;

  { Spatial HLOD cluster manager that partitions static props into XZ grid
    cells, synthesizes csTransient single-draw-call proxy meshes, and swaps
    between full-detail source transforms and merged cell proxies with
    hysteresis deadband stability. }
  TCastleHlodClusterManager = class(TCastleTransform)
  private
    FCellSizeMeters: Single;
    FHlodSwitchDistance: Single;
    FHlodHysteresisMargin: Single;
    FMinPropsPerCluster: Integer;
    FIgnoreNamePrefix: String;
    FProxyMode: THlodProxyMode;
    FAutoEvaluateCamera: Boolean;
    FCells: THlodClusterCellArray;
    FProxyScenes: array of TCastleScene;
    FTotalClusteredProps: Integer;
    FActiveHlodCellCount: Integer;
    FBaselineDrawCalls: Integer;
    FEffectiveDrawCalls: Integer;
    FBaselineTriangles: Integer;
    FEffectiveTriangles: Integer;
    procedure SetCellSizeMeters(const AValue: Single);
    procedure SetHlodSwitchDistance(const AValue: Single);
    procedure SetHlodHysteresisMargin(const AValue: Single);
    procedure SetMinPropsPerCluster(const AValue: Integer);
    procedure SetProxyMode(const AValue: THlodProxyMode);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ClearTransientProxyScenes;
    procedure RebuildProxyScenesFromCells;
    function BuildCellProxyRootNode(const ACell: THlodClusterCell;
      out AProxyTriCount: Integer): TX3DRootNode;
    procedure RecalculateTelemetry;
    function FindPropTransform(const ARootTransform: TCastleTransform;
      const ADesignOwner: TComponent; const APropName: String): TCastleTransform;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Scan ARootTransform, partition eligible static props into CellSizeMeters
      XZ grid cells, and build csTransient single-draw-call HLOD proxy meshes.
      Returns the number of baked HLOD cells. }
    function BakeClustersFromHierarchy(const ARootTransform: TCastleTransform;
      const ADesignOwner: TComponent): Integer;

    { Evaluate 3D distance from ACameraWorldPos to each cell's WorldCenter and
      apply hysteresis switching between source props and merged HLOD proxies. }
    procedure EvaluateCameraDistanceSwap(const ACameraWorldPos: TVector3;
      const ARootTransform: TCastleTransform; const ADesignOwner: TComponent);

    { Restore Exists := True on every clustered source prop and hide all
      HLOD proxy meshes (recommended before saving designs or editing props). }
    procedure RestoreAllFullDetailProps(const ARootTransform: TCastleTransform;
      const ADesignOwner: TComponent);

    function CellCount: Integer;
    function GetCell(const AIndex: Integer): THlodClusterCell;
    function ProxySceneForCell(const AIndex: Integer): TCastleScene;
    function DrawCallReductionRatio: Single;
    function HlodSummaryBadge: String;

    property TotalClusteredProps: Integer read FTotalClusteredProps;
    property ActiveHlodCellCount: Integer read FActiveHlodCellCount;
    property BaselineDrawCalls: Integer read FBaselineDrawCalls;
    property EffectiveDrawCalls: Integer read FEffectiveDrawCalls;
    property BaselineTriangles: Integer read FBaselineTriangles;
    property EffectiveTriangles: Integer read FEffectiveTriangles;
  published
    property CellSizeMeters: Single read FCellSizeMeters write SetCellSizeMeters {$ifdef FPC}default 24.0{$endif};
    property HlodSwitchDistance: Single read FHlodSwitchDistance write SetHlodSwitchDistance {$ifdef FPC}default 45.0{$endif};
    property HlodHysteresisMargin: Single read FHlodHysteresisMargin write SetHlodHysteresisMargin {$ifdef FPC}default 5.0{$endif};
    property MinPropsPerCluster: Integer read FMinPropsPerCluster write SetMinPropsPerCluster {$ifdef FPC}default 2{$endif};
    property IgnoreNamePrefix: String read FIgnoreNamePrefix write FIgnoreNamePrefix;
    property ProxyMode: THlodProxyMode read FProxyMode write SetProxyMode default hpmClusteredBoxes;
    property AutoEvaluateCamera: Boolean read FAutoEvaluateCamera write FAutoEvaluateCamera default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

function HlodProxyModeToDisplayName(const AMode: THlodProxyMode): String;
function EvaluateHlodHysteresisState(const ACurrentUsingHlod: Boolean;
  const ADistance, ASwitchDistance, AHysteresisMargin: Single): Boolean;

implementation

uses
  fpjson, jsonparser, StrUtils,
  CastleComponentSerialize;

function HlodProxyModeToDisplayName(const AMode: THlodProxyMode): String;
begin
  case AMode of
    hpmClusteredBoxes: Result := 'Clustered Silhouette Boxes (1 Draw/Cell)';
    hpmMergedCellBounds: Result := 'Merged Cell Enclosing Hull (12 Tris/Cell)';
    hpmOctagonalPrism: Result := 'Octagonal Skyline Prism (28 Tris/Cell)';
  end;
end;

function EvaluateHlodHysteresisState(const ACurrentUsingHlod: Boolean;
  const ADistance, ASwitchDistance, AHysteresisMargin: Single): Boolean;
var
  Margin: Single;
begin
  Margin := Max(0.0, AHysteresisMargin);
  if ACurrentUsingHlod then
  begin
    { Stay in HLOD until camera comes strictly closer than Switch - Margin. }
    if ADistance < (ASwitchDistance - Margin) then
      Result := False
    else
      Result := True;
  end else
  begin
    { Stay in Full Detail until camera moves strictly farther than Switch + Margin. }
    if ADistance > (ASwitchDistance + Margin) then
      Result := True
    else
      Result := False;
  end;
end;

procedure AppendColoredBoxToArrays(const BMin, BMax, ColorRGB: TVector3;
  const Verts: TVector3List; const Colors: TVector3List);
var
  P000, P100, P110, P010, P001, P101, P111, P011: TVector3;
  ShadeTop, ShadeSideX, ShadeSideZ, ShadeBot: TVector3;

  procedure AddQuad(const A, B, C, D, Col: TVector3);
  begin
    Verts.Add(A); Verts.Add(B); Verts.Add(C);
    Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);
    Verts.Add(A); Verts.Add(C); Verts.Add(D);
    Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);
  end;

begin
  P000 := Vector3(BMin.X, BMin.Y, BMin.Z);
  P100 := Vector3(BMax.X, BMin.Y, BMin.Z);
  P110 := Vector3(BMax.X, BMax.Y, BMin.Z);
  P010 := Vector3(BMin.X, BMax.Y, BMin.Z);
  P001 := Vector3(BMin.X, BMin.Y, BMax.Z);
  P101 := Vector3(BMax.X, BMin.Y, BMax.Z);
  P111 := Vector3(BMax.X, BMax.Y, BMax.Z);
  P011 := Vector3(BMin.X, BMax.Y, BMax.Z);

  ShadeTop := ColorRGB * 1.08;
  ShadeTop.X := Min(1.0, ShadeTop.X);
  ShadeTop.Y := Min(1.0, ShadeTop.Y);
  ShadeTop.Z := Min(1.0, ShadeTop.Z);
  ShadeSideZ := ColorRGB * 0.92;
  ShadeSideX := ColorRGB * 0.80;
  ShadeBot := ColorRGB * 0.62;

  { +Z front, -Z back, +X right, -X left, +Y top, -Y bottom (CCW outward) }
  AddQuad(P001, P101, P111, P011, ShadeSideZ);
  AddQuad(P100, P000, P010, P110, ShadeSideZ);
  AddQuad(P101, P100, P110, P111, ShadeSideX);
  AddQuad(P000, P001, P011, P010, ShadeSideX);
  AddQuad(P011, P111, P110, P010, ShadeTop);
  AddQuad(P000, P100, P101, P001, ShadeBot);
end;

procedure AppendOctagonalPrismToArrays(const BMin, BMax, ColorRGB: TVector3;
  const Verts: TVector3List; const Colors: TVector3List);
const
  Sides = 8;
var
  Cx, Cz, Rx, Rz, Ang0, Ang1: Single;
  I: Integer;
  TopCenter, BotCenter, B0, B1, T0, T1, ShadeTop, ShadeWall, ShadeBot: TVector3;
begin
  Cx := 0.5 * (BMin.X + BMax.X);
  Cz := 0.5 * (BMin.Z + BMax.Z);
  Rx := Max(0.25, 0.5 * (BMax.X - BMin.X));
  Rz := Max(0.25, 0.5 * (BMax.Z - BMin.Z));
  TopCenter := Vector3(Cx, BMax.Y, Cz);
  BotCenter := Vector3(Cx, BMin.Y, Cz);

  ShadeTop := Vector3(Min(1.0, ColorRGB.X * 1.08), Min(1.0, ColorRGB.Y * 1.08), Min(1.0, ColorRGB.Z * 1.08));
  ShadeWall := ColorRGB * 0.88;
  ShadeBot := ColorRGB * 0.62;

  { 8*2 wall tris + 8 top tris + 4 bottom tris (or 8 bottom -> let's emit 8 wall quads = 16 + 8 top + 4 octagonal cap = 28 tris!) }
  for I := 0 to Sides - 1 do
  begin
    Ang0 := (2.0 * Pi * I) / Sides;
    Ang1 := (2.0 * Pi * ((I + 1) mod Sides)) / Sides;
    B0 := Vector3(Cx + Cos(Ang0) * Rx, BMin.Y, Cz + Sin(Ang0) * Rz);
    B1 := Vector3(Cx + Cos(Ang1) * Rx, BMin.Y, Cz + Sin(Ang1) * Rz);
    T0 := Vector3(B0.X, BMax.Y, B0.Z);
    T1 := Vector3(B1.X, BMax.Y, B1.Z);

    { Wall quad (2 tris) }
    Verts.Add(B0); Verts.Add(T0); Verts.Add(T1);
    Colors.Add(ShadeWall); Colors.Add(ShadeWall); Colors.Add(ShadeWall);
    Verts.Add(B0); Verts.Add(T1); Verts.Add(B1);
    Colors.Add(ShadeWall); Colors.Add(ShadeWall); Colors.Add(ShadeWall);

    { Top cap fan (1 tri per side = 8 tris) }
    Verts.Add(TopCenter); Verts.Add(T1); Verts.Add(T0);
    Colors.Add(ShadeTop); Colors.Add(ShadeTop); Colors.Add(ShadeTop);
  end;

  { Bottom quad base across axis extrema (4 tris -> 16 + 8 + 4 = 28 tris exact) }
  for I := 0 to 3 do
  begin
    Ang0 := (0.5 * Pi * I);
    Ang1 := (0.5 * Pi * ((I + 1) mod 4));
    B0 := Vector3(Cx + Cos(Ang0) * Rx, BMin.Y, Cz + Sin(Ang0) * Rz);
    B1 := Vector3(Cx + Cos(Ang1) * Rx, BMin.Y, Cz + Sin(Ang1) * Rz);
    Verts.Add(BotCenter); Verts.Add(B0); Verts.Add(B1);
    Colors.Add(ShadeBot); Colors.Add(ShadeBot); Colors.Add(ShadeBot);
  end;
end;

function ExtractPropColorAndTris(const T: TCastleTransform; out AEstimatedTris: Integer): TVector3;
begin
  AEstimatedTris := 64;
  Result := Vector3(0.68, 0.66, 0.62);
  if T is TCastleBox then
  begin
    Result := TCastleBox(T).Color.XYZ;
    AEstimatedTris := 12;
  end else
  if T is TCastleSphere then
  begin
    Result := TCastleSphere(T).Color.XYZ;
    AEstimatedTris := 512;
  end else
  if T is TCastleCylinder then
  begin
    Result := TCastleCylinder(T).Color.XYZ;
    AEstimatedTris := 128;
  end else
  if T is TCastleCone then
  begin
    Result := TCastleCone(T).Color.XYZ;
    AEstimatedTris := 96;
  end else
  if T is TCastleScene then
  begin
    AEstimatedTris := Max(24, Integer(TCastleScene(T).TrianglesCount));
    Result := Vector3(0.62, 0.68, 0.74);
  end;
end;

{ TCastleHlodClusterManager -------------------------------------------------- }

constructor TCastleHlodClusterManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCellSizeMeters := 24.0;
  FHlodSwitchDistance := 45.0;
  FHlodHysteresisMargin := 5.0;
  FMinPropsPerCluster := 2;
  FIgnoreNamePrefix := 'HlodIgnore_';
  FProxyMode := hpmClusteredBoxes;
  FAutoEvaluateCamera := True;
end;

destructor TCastleHlodClusterManager.Destroy;
begin
  ClearTransientProxyScenes;
  SetLength(FCells, 0);
  inherited Destroy;
end;

function TCastleHlodClusterManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'CellSizeMeters', 'HlodSwitchDistance', 'HlodHysteresisMargin',
       'MinPropsPerCluster', 'IgnoreNamePrefix', 'ProxyMode',
       'AutoEvaluateCamera', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleHlodClusterManager.SetCellSizeMeters(const AValue: Single);
begin
  FCellSizeMeters := Max(4.0, AValue);
end;

procedure TCastleHlodClusterManager.SetHlodSwitchDistance(const AValue: Single);
begin
  FHlodSwitchDistance := Max(2.0, AValue);
end;

procedure TCastleHlodClusterManager.SetHlodHysteresisMargin(const AValue: Single);
begin
  FHlodHysteresisMargin := Max(0.0, AValue);
end;

procedure TCastleHlodClusterManager.SetMinPropsPerCluster(const AValue: Integer);
begin
  FMinPropsPerCluster := Max(1, AValue);
end;

procedure TCastleHlodClusterManager.SetProxyMode(const AValue: THlodProxyMode);
begin
  if FProxyMode = AValue then
    Exit;
  FProxyMode := AValue;
  if Length(FCells) > 0 then
    RebuildProxyScenesFromCells;
end;

procedure TCastleHlodClusterManager.ClearTransientProxyScenes;
var
  I: Integer;
begin
  for I := 0 to High(FProxyScenes) do
    FreeAndNil(FProxyScenes[I]);
  SetLength(FProxyScenes, 0);
end;

function TCastleHlodClusterManager.BuildCellProxyRootNode(
  const ACell: THlodClusterCell; out AProxyTriCount: Integer): TX3DRootNode;
var
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  ColorNode: TColorNode;
  Verts, Colors: TVector3List;
  I: Integer;
begin
  Result := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.Roughness := 0.82;
  Mat.Metallic := 0.08;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := True;
  Coord := TCoordinateNode.Create;
  ColorNode := TColorNode.Create;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    case FProxyMode of
      hpmClusteredBoxes:
        for I := 0 to ACell.SourcePropCount - 1 do
          AppendColoredBoxToArrays(ACell.Props[I].WorldMin, ACell.Props[I].WorldMax,
            ACell.Props[I].ColorRGB, Verts, Colors);
      hpmMergedCellBounds:
        AppendColoredBoxToArrays(ACell.WorldMin, ACell.WorldMax, ACell.AvgColorRGB,
          Verts, Colors);
      hpmOctagonalPrism:
        AppendOctagonalPrismToArrays(ACell.WorldMin, ACell.WorldMax, ACell.AvgColorRGB,
          Verts, Colors);
    end;
    Coord.SetPoint(Verts);
    ColorNode.SetColor(Colors);
    AProxyTriCount := Verts.Count div 3;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;

  TriSet.Coord := Coord;
  TriSet.Color := ColorNode;
  Shape.Geometry := TriSet;
  Result.AddChildren(Shape);
end;

procedure TCastleHlodClusterManager.RebuildProxyScenesFromCells;
var
  I, ProxyTris: Integer;
  Sc: TCastleScene;
  RootNode: TX3DRootNode;
begin
  ClearTransientProxyScenes;
  SetLength(FProxyScenes, Length(FCells));
  for I := 0 to High(FCells) do
  begin
    Sc := TCastleScene.Create(nil);
    Sc.SetTransient;
    Sc.Name := Format('HlodCellProxy_%d', [I]);
    Sc.PreciseCollisions := False;
    Sc.Pickable := False;
    RootNode := BuildCellProxyRootNode(FCells[I], ProxyTris);
    FCells[I].ProxyTrianglesCount := ProxyTris;
    Sc.Load(RootNode, True);
    Sc.Exists := FCells[I].UsingHlodProxy;
    Add(Sc);
    FProxyScenes[I] := Sc;
  end;
  RecalculateTelemetry;
end;

procedure TCastleHlodClusterManager.RecalculateTelemetry;
var
  I: Integer;
begin
  FTotalClusteredProps := 0;
  FActiveHlodCellCount := 0;
  FBaselineDrawCalls := 0;
  FEffectiveDrawCalls := 0;
  FBaselineTriangles := 0;
  FEffectiveTriangles := 0;
  for I := 0 to High(FCells) do
  begin
    FTotalClusteredProps := FTotalClusteredProps + FCells[I].SourcePropCount;
    FBaselineDrawCalls := FBaselineDrawCalls + FCells[I].SourcePropCount;
    FBaselineTriangles := FBaselineTriangles + FCells[I].SourceTrianglesEstimate;
    if FCells[I].UsingHlodProxy then
    begin
      Inc(FActiveHlodCellCount);
      Inc(FEffectiveDrawCalls, 1);
      FEffectiveTriangles := FEffectiveTriangles + FCells[I].ProxyTrianglesCount;
    end else
    begin
      FEffectiveDrawCalls := FEffectiveDrawCalls + FCells[I].SourcePropCount;
      FEffectiveTriangles := FEffectiveTriangles + FCells[I].SourceTrianglesEstimate;
    end;
  end;
end;

function TCastleHlodClusterManager.FindPropTransform(
  const ARootTransform: TCastleTransform; const ADesignOwner: TComponent;
  const APropName: String): TCastleTransform;

  function SearchRec(const Node: TCastleTransform): TCastleTransform;
  var
    I: Integer;
  begin
    Result := nil;
    if Node = nil then
      Exit;
    if SameText(Node.Name, APropName) then
      Exit(Node);
    for I := 0 to Node.Count - 1 do
    begin
      Result := SearchRec(Node[I]);
      if Result <> nil then
        Exit;
    end;
  end;

var
  Comp: TComponent;
begin
  Result := nil;
  if APropName = '' then
    Exit;
  if ADesignOwner <> nil then
  begin
    Comp := ADesignOwner.FindComponent(APropName);
    if Comp is TCastleTransform then
      Exit(TCastleTransform(Comp));
  end;
  Result := SearchRec(ARootTransform);
end;

function TCastleHlodClusterManager.BakeClustersFromHierarchy(
  const ARootTransform: TCastleTransform; const ADesignOwner: TComponent): Integer;
type
  TRawBucket = record
    CellX: Integer;
    CellZ: Integer;
    Items: array of THlodClusterPropItem;
    Count: Integer;
  end;
var
  Buckets: array of TRawBucket;

  function FindOrAddBucket(const CX, CZ: Integer): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Buckets) do
      if (Buckets[K].CellX = CX) and (Buckets[K].CellZ = CZ) then
        Exit(K);
    Result := Length(Buckets);
    SetLength(Buckets, Result + 1);
    Buckets[Result] := Default(TRawBucket);
    Buckets[Result].CellX := CX;
    Buckets[Result].CellZ := CZ;
  end;

  function IsEligibleStaticProp(const T: TCastleTransform): Boolean;
  begin
    Result := False;
    if (T = nil) or (T = Self) or (T = ARootTransform) then
      Exit;
    if csTransient in T.ComponentStyle then
      Exit;
    if T.Name = '' then
      Exit;
    if (FIgnoreNamePrefix <> '') and AnsiStartsText(FIgnoreNamePrefix, T.Name) then
      Exit;
    if (T is TCastleAbstractLight) or (T is TCastleCamera) or
       (T is TCastleHlodClusterManager) then
      Exit;
    if (T is TCastleBox) or (T is TCastleSphere) or (T is TCastleCylinder) or
       (T is TCastleCone) or (T is TCastleScene) then
      Result := True;
  end;

  procedure CollectPropsRec(const Node: TCastleTransform);
  var
    I, CX, CZ, BIdx, EstTris: Integer;
    BBox: TBox3D;
    Center, HalfExt, Col: TVector3;
    Item: THlodClusterPropItem;
  begin
    if (Node = nil) or (Node = Self) then
      Exit;
    if (Node <> ARootTransform) and (csTransient in Node.ComponentStyle) then
      Exit;
    if IsEligibleStaticProp(Node) then
    begin
      { Ensure prop is temporarily visible if previously hidden by HLOD so BBox is valid }
      Node.Exists := True;
      BBox := Node.BoundingBox;
      if BBox.IsEmpty then
      begin
        Center := Node.WorldTranslation;
        if Node is TCastleBox then
          HalfExt := 0.5 * TCastleBox(Node).Size
        else if Node is TCastleCylinder then
          HalfExt := Vector3(TCastleCylinder(Node).Radius, 0.5 * TCastleCylinder(Node).Height, TCastleCylinder(Node).Radius)
        else if Node is TCastleSphere then
          HalfExt := Vector3(TCastleSphere(Node).Radius, TCastleSphere(Node).Radius, TCastleSphere(Node).Radius)
        else if Node is TCastleCone then
          HalfExt := Vector3(TCastleCone(Node).BottomRadius, 0.5 * TCastleCone(Node).Height, TCastleCone(Node).BottomRadius)
        else
          HalfExt := Vector3(0.5, 0.5, 0.5);
        BBox := Box3D(Center - HalfExt, Center + HalfExt);
      end;
      Center := BBox.Center;
      CX := Floor(Center.X / FCellSizeMeters);
      CZ := Floor(Center.Z / FCellSizeMeters);
      Col := ExtractPropColorAndTris(Node, EstTris);

      Item := Default(THlodClusterPropItem);
      Item.PropName := Node.Name;
      Item.WorldMin := BBox.Data[0];
      Item.WorldMax := BBox.Data[1];
      Item.ColorRGB := Col;
      Item.EstimatedTris := EstTris;

      BIdx := FindOrAddBucket(CX, CZ);
      SetLength(Buckets[BIdx].Items, Buckets[BIdx].Count + 1);
      Buckets[BIdx].Items[Buckets[BIdx].Count] := Item;
      Inc(Buckets[BIdx].Count);
      { Do not recurse into internal children of a clustered leaf prop }
      Exit;
    end;
    for I := 0 to Node.Count - 1 do
      CollectPropsRec(Node[I]);
  end;

var
  B, P, OutIdx: Integer;
  Cell: THlodClusterCell;
  SumCol: TVector3;
begin
  RestoreAllFullDetailProps(ARootTransform, ADesignOwner);
  ClearTransientProxyScenes;
  SetLength(FCells, 0);
  SetLength(Buckets, 0);

  if ARootTransform = nil then
  begin
    RecalculateTelemetry;
    Exit(0);
  end;

  { Reset manager transform to world identity so world-space proxy vertices align }
  Translation := Vector3(0, 0, 0);
  Rotation := Vector4(0, 1, 0, 0);
  Scale := Vector3(1, 1, 1);

  CollectPropsRec(ARootTransform);

  for B := 0 to High(Buckets) do
  begin
    if Buckets[B].Count < FMinPropsPerCluster then
      Continue;
    Cell := Default(THlodClusterCell);
    Cell.CellX := Buckets[B].CellX;
    Cell.CellZ := Buckets[B].CellZ;
    Cell.SourcePropCount := Buckets[B].Count;
    SetLength(Cell.Props, Cell.SourcePropCount);
    Cell.WorldMin := Buckets[B].Items[0].WorldMin;
    Cell.WorldMax := Buckets[B].Items[0].WorldMax;
    SumCol := TVector3.Zero;
    Cell.SourceTrianglesEstimate := 0;

    for P := 0 to Cell.SourcePropCount - 1 do
    begin
      Cell.Props[P] := Buckets[B].Items[P];
      Cell.WorldMin.X := Min(Cell.WorldMin.X, Cell.Props[P].WorldMin.X);
      Cell.WorldMin.Y := Min(Cell.WorldMin.Y, Cell.Props[P].WorldMin.Y);
      Cell.WorldMin.Z := Min(Cell.WorldMin.Z, Cell.Props[P].WorldMin.Z);
      Cell.WorldMax.X := Max(Cell.WorldMax.X, Cell.Props[P].WorldMax.X);
      Cell.WorldMax.Y := Max(Cell.WorldMax.Y, Cell.Props[P].WorldMax.Y);
      Cell.WorldMax.Z := Max(Cell.WorldMax.Z, Cell.Props[P].WorldMax.Z);
      SumCol := SumCol + Cell.Props[P].ColorRGB;
      Cell.SourceTrianglesEstimate := Cell.SourceTrianglesEstimate + Cell.Props[P].EstimatedTris;
    end;
    Cell.WorldCenter := 0.5 * (Cell.WorldMin + Cell.WorldMax);
    Cell.AvgColorRGB := SumCol / Single(Max(1, Cell.SourcePropCount));
    Cell.UsingHlodProxy := False;
    Cell.LastCameraDistance := 0.0;

    OutIdx := Length(FCells);
    SetLength(FCells, OutIdx + 1);
    FCells[OutIdx] := Cell;
  end;

  RebuildProxyScenesFromCells;
  Result := Length(FCells);
end;

procedure TCastleHlodClusterManager.EvaluateCameraDistanceSwap(
  const ACameraWorldPos: TVector3; const ARootTransform: TCastleTransform;
  const ADesignOwner: TComponent);
var
  I, P: Integer;
  Dist: Single;
  NextHlod: Boolean;
  PropT: TCastleTransform;
begin
  for I := 0 to High(FCells) do
  begin
    Dist := PointsDistance(ACameraWorldPos, FCells[I].WorldCenter);
    FCells[I].LastCameraDistance := Dist;
    NextHlod := EvaluateHlodHysteresisState(FCells[I].UsingHlodProxy,
      Dist, FHlodSwitchDistance, FHlodHysteresisMargin);
    FCells[I].UsingHlodProxy := NextHlod;

    if (I >= 0) and (I <= High(FProxyScenes)) and (FProxyScenes[I] <> nil) then
      FProxyScenes[I].Exists := NextHlod;

    for P := 0 to FCells[I].SourcePropCount - 1 do
    begin
      PropT := FindPropTransform(ARootTransform, ADesignOwner, FCells[I].Props[P].PropName);
      if PropT <> nil then
        PropT.Exists := not NextHlod;
    end;
  end;
  RecalculateTelemetry;
end;

procedure TCastleHlodClusterManager.RestoreAllFullDetailProps(
  const ARootTransform: TCastleTransform; const ADesignOwner: TComponent);
var
  I, P: Integer;
  PropT: TCastleTransform;
begin
  for I := 0 to High(FCells) do
  begin
    FCells[I].UsingHlodProxy := False;
    if (I >= 0) and (I <= High(FProxyScenes)) and (FProxyScenes[I] <> nil) then
      FProxyScenes[I].Exists := False;
    for P := 0 to FCells[I].SourcePropCount - 1 do
    begin
      PropT := FindPropTransform(ARootTransform, ADesignOwner, FCells[I].Props[P].PropName);
      if PropT <> nil then
        PropT.Exists := True;
    end;
  end;
  RecalculateTelemetry;
end;

procedure TCastleHlodClusterManager.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoEvaluateCamera and (World <> nil) and (World.MainCamera <> nil) and
     (Length(FCells) > 0) then
    EvaluateCameraDistanceSwap(World.MainCamera.WorldTranslation, World, Owner);
end;

function TCastleHlodClusterManager.CellCount: Integer;
begin
  Result := Length(FCells);
end;

function TCastleHlodClusterManager.GetCell(const AIndex: Integer): THlodClusterCell;
begin
  if (AIndex >= 0) and (AIndex <= High(FCells)) then
    Result := FCells[AIndex]
  else
    Result := Default(THlodClusterCell);
end;

function TCastleHlodClusterManager.ProxySceneForCell(const AIndex: Integer): TCastleScene;
begin
  if (AIndex >= 0) and (AIndex <= High(FProxyScenes)) then
    Result := FProxyScenes[AIndex]
  else
    Result := nil;
end;

function TCastleHlodClusterManager.DrawCallReductionRatio: Single;
begin
  if FBaselineDrawCalls <= 0 then
    Result := 0.0
  else
    Result := Max(0.0, 1.0 - (Single(FEffectiveDrawCalls) / Single(FBaselineDrawCalls)));
end;

function TCastleHlodClusterManager.HlodSummaryBadge: String;
begin
  Result := Format('[HLOD:%d cells %d props %d/%d draws (-%d%%)]', [
    Length(FCells),
    FTotalClusteredProps,
    FEffectiveDrawCalls,
    Max(1, FBaselineDrawCalls),
    Round(DrawCallReductionRatio * 100.0)
  ]);
end;

function TCastleHlodClusterManager.GetConfigJson: String;
var
  RootObj, CellObj, PropObj: TJSONObject;
  CellsArr, PropsArr: TJSONArray;
  I, P: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    CellsArr := TJSONArray.Create;
    for I := 0 to High(FCells) do
    begin
      CellObj := TJSONObject.Create;
      CellObj.Add('cellX', FCells[I].CellX);
      CellObj.Add('cellZ', FCells[I].CellZ);
      CellObj.Add('minX', FCells[I].WorldMin.X);
      CellObj.Add('minY', FCells[I].WorldMin.Y);
      CellObj.Add('minZ', FCells[I].WorldMin.Z);
      CellObj.Add('maxX', FCells[I].WorldMax.X);
      CellObj.Add('maxY', FCells[I].WorldMax.Y);
      CellObj.Add('maxZ', FCells[I].WorldMax.Z);
      CellObj.Add('avgR', FCells[I].AvgColorRGB.X);
      CellObj.Add('avgG', FCells[I].AvgColorRGB.Y);
      CellObj.Add('avgB', FCells[I].AvgColorRGB.Z);
      CellObj.Add('sourceTris', FCells[I].SourceTrianglesEstimate);
      PropsArr := TJSONArray.Create;
      for P := 0 to FCells[I].SourcePropCount - 1 do
      begin
        PropObj := TJSONObject.Create;
        PropObj.Add('name', FCells[I].Props[P].PropName);
        PropObj.Add('minX', FCells[I].Props[P].WorldMin.X);
        PropObj.Add('minY', FCells[I].Props[P].WorldMin.Y);
        PropObj.Add('minZ', FCells[I].Props[P].WorldMin.Z);
        PropObj.Add('maxX', FCells[I].Props[P].WorldMax.X);
        PropObj.Add('maxY', FCells[I].Props[P].WorldMax.Y);
        PropObj.Add('maxZ', FCells[I].Props[P].WorldMax.Z);
        PropObj.Add('colR', FCells[I].Props[P].ColorRGB.X);
        PropObj.Add('colG', FCells[I].Props[P].ColorRGB.Y);
        PropObj.Add('colB', FCells[I].Props[P].ColorRGB.Z);
        PropObj.Add('tris', FCells[I].Props[P].EstimatedTris);
        PropsArr.Add(PropObj);
      end;
      CellObj.Add('props', PropsArr);
      CellsArr.Add(CellObj);
    end;
    RootObj.Add('cells', CellsArr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleHlodClusterManager.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, CellObj, PropObj: TJSONObject;
  CellsArr, PropsArr: TJSONArray;
  I, P: Integer;
  Cell: THlodClusterCell;
begin
  ClearTransientProxyScenes;
  SetLength(FCells, 0);
  if Trim(AValue) = '' then
  begin
    RecalculateTelemetry;
    Exit;
  end;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);
    CellsArr := RootObj.Find('cells', jtArray) as TJSONArray;
    if CellsArr = nil then
      Exit;
    SetLength(FCells, CellsArr.Count);
    for I := 0 to CellsArr.Count - 1 do
    begin
      Cell := Default(THlodClusterCell);
      if CellsArr.Items[I] is TJSONObject then
      begin
        CellObj := TJSONObject(CellsArr.Items[I]);
        Cell.CellX := CellObj.Get('cellX', 0);
        Cell.CellZ := CellObj.Get('cellZ', 0);
        Cell.WorldMin := Vector3(CellObj.Get('minX', 0.0), CellObj.Get('minY', 0.0), CellObj.Get('minZ', 0.0));
        Cell.WorldMax := Vector3(CellObj.Get('maxX', 1.0), CellObj.Get('maxY', 1.0), CellObj.Get('maxZ', 1.0));
        Cell.WorldCenter := 0.5 * (Cell.WorldMin + Cell.WorldMax);
        Cell.AvgColorRGB := Vector3(CellObj.Get('avgR', 0.65), CellObj.Get('avgG', 0.65), CellObj.Get('avgB', 0.65));
        Cell.SourceTrianglesEstimate := CellObj.Get('sourceTris', 24);
        PropsArr := CellObj.Find('props', jtArray) as TJSONArray;
        if PropsArr <> nil then
        begin
          Cell.SourcePropCount := PropsArr.Count;
          SetLength(Cell.Props, Cell.SourcePropCount);
          for P := 0 to Cell.SourcePropCount - 1 do
          begin
            Cell.Props[P] := Default(THlodClusterPropItem);
            if PropsArr.Items[P] is TJSONObject then
            begin
              PropObj := TJSONObject(PropsArr.Items[P]);
              Cell.Props[P].PropName := PropObj.Get('name', '');
              Cell.Props[P].WorldMin := Vector3(PropObj.Get('minX', 0.0), PropObj.Get('minY', 0.0), PropObj.Get('minZ', 0.0));
              Cell.Props[P].WorldMax := Vector3(PropObj.Get('maxX', 1.0), PropObj.Get('maxY', 1.0), PropObj.Get('maxZ', 1.0));
              Cell.Props[P].ColorRGB := Vector3(PropObj.Get('colR', 0.65), PropObj.Get('colG', 0.65), PropObj.Get('colB', 0.65));
              Cell.Props[P].EstimatedTris := PropObj.Get('tris', 12);
            end;
          end;
        end;
      end;
      FCells[I] := Cell;
    end;
    RebuildProxyScenesFromCells;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleHlodClusterManager,
    ['World & Crowds', 'HLOD Spatial Cluster Manager (TCastleHlodClusterManager)']);

end.
