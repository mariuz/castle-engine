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

{ 3D BSP Constructive Solid Geometry (CSG) Greybox Architecture & Procedural
  Room / Arch / Ramp / Stairwell Mesh Modeler (@link(TCastleCsgModeler))
  (Phase 309 — UE 6.0+ Modeling Mode & CubeGrid Parity). }
unit CastleCsgModeler;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Generics.Collections,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleScene, X3DNodes;

type
  { Primitive architectural brush shape inside @link(TCastleCsgModeler). }
  TCsgBrushShape = (
    cbsBox,
    cbsCylinder,
    cbsArchCorridor,
    cbsRampWedge,
    cbsStairwell
  );

  { CSG boolean combination operation applied to the accumulated solid. }
  TCsgBooleanOperation = (
    cboUnion,
    cboSubtract,
    cboIntersect
  );

  { Built-in multi-brush architectural greybox presets. }
  TCsgArchitecturalPreset = (
    capCustom,
    capHollowRoomWithArchDoorway,
    capVaultedCrossHallway,
    capMezzanineRampAndStairs,
    capPillaredCourtyardCloister
  );

  { Single CSG brush entry stored in @link(TCastleCsgModeler.BrushesJson). }
  TCsgBrushItem = record
    BrushId: String;
    Enabled: Boolean;
    Operation: TCsgBooleanOperation;
    Shape: TCsgBrushShape;
    Center: TVector3;
    Size: TVector3;
    YawDeg: Single;
    Segments: Integer;
    TintColor: TCastleColorRGB;
    class function DefaultBox(const AId: String): TCsgBrushItem; static;
  end;

  TCsgBrushList = {$ifdef FPC}specialize{$endif} TList<TCsgBrushItem>;

  { Convex planar polygon used by the 3D BSP boolean evaluator. }
  TCsgPolygon = record
    Vertices: array of TVector3;
    Normal: TVector3;
    PlaneW: Single;
    TintColor: TCastleColorRGB;
  end;

  TCsgPolygonArray = array of TCsgPolygon;

  { Non-destructive 3D CSG boolean greybox modeler component.
    Evaluates an ordered stack of additive, subtractive, and intersective
    architectural brushes (@code(Box), @code(Cylinder), @code(ArchCorridor),
    @code(RampWedge), @code(Stairwell)) via 3D polygon-splitting BSP trees,
    generates real-meter triplanar UVs, and populates a @code(csTransient)
    PBR @link(TCastleScene) with optional triangle-accurate octree collisions. }
  TCastleCsgModeler = class(TCastleTransform)
  public
    const
      DefaultUvTilingScale = 0.5;
      DefaultRoughness = 0.78;
      DefaultMetallic = 0.05;
      DefaultGenerateCollider = True;
  strict private
    FBrushes: TCsgBrushList;
    FPreset: TCsgArchitecturalPreset;
    FUvTilingScale: Single;
    FRoughness: Single;
    FMetallic: Single;
    FGenerateCollider: Boolean;
    FBaseColor: TCastleColorRGB;
    FBaseColorPersistent: TCastleColorRGBPersistent;

    FOutputTriangleCount: Integer;
    FOutputVertexCount: Integer;
    FOutputVolumeCubicMeters: Single;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FMaterialNode: TPhysicalMaterialNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;
    FTexCoordNode: TTextureCoordinateNode;
    FColorNode: TColorNode;

    function GetBrushesJson: String;
    procedure SetBrushesJson(const Value: String);
    procedure SetPreset(const Value: TCsgArchitecturalPreset);
    procedure SetUvTilingScale(const Value: Single);
    procedure SetRoughness(const Value: Single);
    procedure SetMetallic(const Value: Single);
    procedure SetGenerateCollider(const Value: Boolean);
    procedure SetBaseColor(const Value: TCastleColorRGB);
    function GetBaseColorForPersistent: TCastleColorRGB;
    procedure SetBaseColorForPersistent(const AValue: TCastleColorRGB);

    procedure EnsureRenderScene;
    procedure SyncColliderState;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Direct access to the ordered brush stack. Call @link(RebuildMesh) after mutating. }
    property Brushes: TCsgBrushList read FBrushes;

    { Clear all brushes and load one of the built-in architectural presets. }
    procedure ApplyPreset(const APreset: TCsgArchitecturalPreset);

    { Append a brush and immediately rebuild the CSG mesh. Returns new brush index. }
    function AddBrush(const ABrush: TCsgBrushItem): Integer;
    procedure UpdateBrush(const AIndex: Integer; const ABrush: TCsgBrushItem);
    procedure DeleteBrush(const AIndex: Integer);
    procedure MoveBrush(const AFromIndex, AToIndex: Integer);
    procedure ClearBrushes;
    function EnabledBrushCount: Integer;

    { Evaluate the CSG boolean stack, generate triplanar UVs, compute exact
      signed polyhedral volume, and refresh the transient PBR + collision mesh. }
    procedure RebuildMesh;

    { Compute triplanar UV coordinates in real-world meters for a vertex & face normal. }
    function ComputeTriplanarUv(const APoint, ANormal: TVector3): TVector2;

    { Exposed transient render/collision scene for diagnostics and raycast verification. }
    property RenderScene: TCastleScene read FRenderScene;
    property OutputTriangleCount: Integer read FOutputTriangleCount;
    property OutputVertexCount: Integer read FOutputVertexCount;
    property OutputVolumeCubicMeters: Single read FOutputVolumeCubicMeters;

    { Compact Hierarchy tree badge, e.g. @code('[CSG:HollowRoom 3 brushes 68 tris]'). }
    function CsgSummaryBadge: String;

    property BaseColor: TCastleColorRGB read FBaseColor write SetBaseColor;
  published
    { Built-in multi-brush architectural template. }
    property Preset: TCsgArchitecturalPreset
      read FPreset write SetPreset default capHollowRoomWithArchDoorway;

    { JSON-serialized brush stack stored cleanly in @code(.castle-transform) / @code(.castle-user-interface). }
    property BrushesJson: String read GetBrushesJson write SetBrushesJson stored True;

    { Real-meter triplanar UV repeats per meter (0.5 = one texture tile every 2 meters). }
    property UvTilingScale: Single
      read FUvTilingScale write SetUvTilingScale {$ifdef FPC}default DefaultUvTilingScale{$endif};

    { PBR roughness on the generated greybox mesh [0..1]. }
    property Roughness: Single
      read FRoughness write SetRoughness {$ifdef FPC}default DefaultRoughness{$endif};

    { PBR metallic factor on the generated greybox mesh [0..1]. }
    property Metallic: Single
      read FMetallic write SetMetallic {$ifdef FPC}default DefaultMetallic{$endif};

    { Synchronize exact triangle octree collisions (@code(Collides) & @code(PreciseCollisions))
      so walkthrough doorways, arches, ramps, and stairs are immediately walkable & raycastable. }
    property GenerateCollider: Boolean
      read FGenerateCollider write SetGenerateCollider default DefaultGenerateCollider;

    { Overall PBR multiplier tint for the CSG mesh. }
    property BaseColorPersistent: TCastleColorRGBPersistent
      read FBaseColorPersistent;
  end;

function CsgShapeToString(const AShape: TCsgBrushShape): String;
function StringToCsgShape(const S: String): TCsgBrushShape;
function CsgOperationToString(const AOp: TCsgBooleanOperation): String;
function StringToCsgOperation(const S: String): TCsgBooleanOperation;
function CsgPresetDisplayName(const APreset: TCsgArchitecturalPreset): String;

{ Build closed, outward-oriented polyhedral faces for a single brush item. }
function BuildBrushPolygons(const ABrush: TCsgBrushItem): TCsgPolygonArray;

{ Execute a 3D polygon-splitting BSP boolean operation between two solid polygon sets. }
function EvaluateCsgBoolean(const APolysA, APolysB: TCsgPolygonArray;
  const AOp: TCsgBooleanOperation): TCsgPolygonArray;

implementation

uses
  Math, fpjson, jsonparser,
  CastleComponentSerialize, CastleUtils;

const
  BspPlaneEps = 1.0e-4;
  MaxBspDepth = 48;

  cpCoplanar = 0;
  cpFront    = 1;
  cpBack     = 2;
  cpSpanning = 3;

{ Helper conversion routines ------------------------------------------------- }

function CsgShapeToString(const AShape: TCsgBrushShape): String;
begin
  case AShape of
    cbsBox:          Result := 'Box';
    cbsCylinder:     Result := 'Cylinder';
    cbsArchCorridor: Result := 'ArchCorridor';
    cbsRampWedge:    Result := 'RampWedge';
    cbsStairwell:    Result := 'Stairwell';
  end;
end;

function StringToCsgShape(const S: String): TCsgBrushShape;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'cylinder' then
    Result := cbsCylinder
  else if (L = 'archcorridor') or (L = 'arch') then
    Result := cbsArchCorridor
  else if (L = 'rampwedge') or (L = 'ramp') then
    Result := cbsRampWedge
  else if (L = 'stairwell') or (L = 'stairs') then
    Result := cbsStairwell
  else
    Result := cbsBox;
end;

function CsgOperationToString(const AOp: TCsgBooleanOperation): String;
begin
  case AOp of
    cboUnion:     Result := 'Union';
    cboSubtract:  Result := 'Subtract';
    cboIntersect: Result := 'Intersect';
  end;
end;

function StringToCsgOperation(const S: String): TCsgBooleanOperation;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if (L = 'subtract') or (L = 'sub') then
    Result := cboSubtract
  else if (L = 'intersect') or (L = 'and') then
    Result := cboIntersect
  else
    Result := cboUnion;
end;

function CsgPresetDisplayName(const APreset: TCsgArchitecturalPreset): String;
begin
  case APreset of
    capCustom:                    Result := 'Custom';
    capHollowRoomWithArchDoorway: Result := 'HollowRoom';
    capVaultedCrossHallway:       Result := 'VaultedCross';
    capMezzanineRampAndStairs:    Result := 'MezzanineStairs';
    capPillaredCourtyardCloister: Result := 'Cloister';
  end;
end;

{ TCsgBrushItem -------------------------------------------------------------- }

class function TCsgBrushItem.DefaultBox(const AId: String): TCsgBrushItem;
begin
  Result.BrushId := AId;
  Result.Enabled := True;
  Result.Operation := cboUnion;
  Result.Shape := cbsBox;
  Result.Center := Vector3(0.0, 1.5, 0.0);
  Result.Size := Vector3(4.0, 3.0, 4.0);
  Result.YawDeg := 0.0;
  Result.Segments := 8;
  Result.TintColor := Vector3(0.76, 0.78, 0.82);
end;

{ Polygon & Brush Geometry Construction -------------------------------------- }

function TransformBrushVertex(const LocalPt: TVector3;
  const Center: TVector3; const YawRad: Single): TVector3;
var
  S, C: Single;
begin
  SinCos(YawRad, S, C);
  Result := Vector3(
    Center.X + LocalPt.X * C + LocalPt.Z * S,
    Center.Y + LocalPt.Y,
    Center.Z - LocalPt.X * S + LocalPt.Z * C
  );
end;

function TransformBrushDirection(const LocalDir: TVector3; const YawRad: Single): TVector3;
var
  S, C: Single;
begin
  SinCos(YawRad, S, C);
  Result := Vector3(
    LocalDir.X * C + LocalDir.Z * S,
    LocalDir.Y,
    -LocalDir.X * S + LocalDir.Z * C
  );
  if Result.LengthSqr > 1.0e-10 then
    Result := Result.Normalize
  else
    Result := Vector3(0.0, 1.0, 0.0);
end;

procedure AppendOrientedPolygon(var List: TCsgPolygonArray;
  const RawVerts: array of TVector3; const DesiredOutwardNormal: TVector3;
  const ATint: TCastleColorRGB);
var
  N, I, Idx: Integer;
  GeoN: TVector3;
  Poly: TCsgPolygon;
  NeedReverse: Boolean;
begin
  N := Length(RawVerts);
  if N < 3 then
    Exit;

  GeoN := TVector3.CrossProduct(RawVerts[1] - RawVerts[0], RawVerts[2] - RawVerts[0]);
  if GeoN.LengthSqr < 1.0e-12 then
    Exit;

  NeedReverse := TVector3.DotProduct(GeoN, DesiredOutwardNormal) < 0.0;
  SetLength(Poly.Vertices, N);
  if NeedReverse then
  begin
    for I := 0 to N - 1 do
      Poly.Vertices[I] := RawVerts[N - 1 - I];
    GeoN := -GeoN;
  end else
  begin
    for I := 0 to N - 1 do
      Poly.Vertices[I] := RawVerts[I];
  end;

  Poly.Normal := GeoN.Normalize;
  Poly.PlaneW := TVector3.DotProduct(Poly.Normal, Poly.Vertices[0]);
  Poly.TintColor := ATint;

  Idx := Length(List);
  SetLength(List, Idx + 1);
  List[Idx] := Poly;
end;

function BuildBrushPolygons(const ABrush: TCsgBrushItem): TCsgPolygonArray;
var
  SX, SY, SZ, HX, HY, HZ, YawRad: Single;
  Segs, I: Integer;
  CapTop, CapBot: array of TVector3;
  A0, A1, MidA: Single;
  X0, Z0, X1, Z1: Single;
  ArchRadY, SpringY, Y0, Y1, PrevTopY, CurTopY, ZF0, ZF1: Single;
  FrontCap, BackCap: array of TVector3;

  function V(const X, Y, Z: Single): TVector3;
  begin
    Result := TransformBrushVertex(Vector3(X, Y, Z), ABrush.Center, YawRad);
  end;

  function D(const X, Y, Z: Single): TVector3;
  begin
    Result := TransformBrushDirection(Vector3(X, Y, Z), YawRad);
  end;

begin
  Result := nil;
  SX := Max(0.05, ABrush.Size.X);
  SY := Max(0.05, ABrush.Size.Y);
  SZ := Max(0.05, ABrush.Size.Z);
  HX := SX * 0.5;
  HY := SY * 0.5;
  HZ := SZ * 0.5;
  YawRad := DegToRad(ABrush.YawDeg);

  case ABrush.Shape of
    cbsBox:
      begin
        AppendOrientedPolygon(Result, [V( HX, -HY, -HZ), V( HX,  HY, -HZ), V( HX,  HY,  HZ), V( HX, -HY,  HZ)], D( 1,  0,  0), ABrush.TintColor);
        AppendOrientedPolygon(Result, [V(-HX, -HY,  HZ), V(-HX,  HY,  HZ), V(-HX,  HY, -HZ), V(-HX, -HY, -HZ)], D(-1,  0,  0), ABrush.TintColor);
        AppendOrientedPolygon(Result, [V(-HX,  HY, -HZ), V(-HX,  HY,  HZ), V( HX,  HY,  HZ), V( HX,  HY, -HZ)], D( 0,  1,  0), ABrush.TintColor);
        AppendOrientedPolygon(Result, [V(-HX, -HY,  HZ), V(-HX, -HY, -HZ), V( HX, -HY, -HZ), V( HX, -HY,  HZ)], D( 0, -1,  0), ABrush.TintColor);
        AppendOrientedPolygon(Result, [V(-HX, -HY,  HZ), V( HX, -HY,  HZ), V( HX,  HY,  HZ), V(-HX,  HY,  HZ)], D( 0,  0,  1), ABrush.TintColor);
        AppendOrientedPolygon(Result, [V( HX, -HY, -HZ), V(-HX, -HY, -HZ), V(-HX,  HY, -HZ), V( HX,  HY, -HZ)], D( 0,  0, -1), ABrush.TintColor);
      end;

    cbsCylinder:
      begin
        Segs := Clamped(ABrush.Segments, 4, 32);
        SetLength(CapTop, Segs);
        SetLength(CapBot, Segs);
        for I := 0 to Segs - 1 do
        begin
          A0 := (2.0 * Pi * I) / Segs;
          X0 := Cos(A0) * HX;
          Z0 := Sin(A0) * HZ;
          CapTop[I] := V(X0,  HY, Z0);
          CapBot[I] := V(X0, -HY, Z0);
        end;
        AppendOrientedPolygon(Result, CapTop, D(0,  1, 0), ABrush.TintColor);
        AppendOrientedPolygon(Result, CapBot, D(0, -1, 0), ABrush.TintColor);
        for I := 0 to Segs - 1 do
        begin
          A0 := (2.0 * Pi * I) / Segs;
          A1 := (2.0 * Pi * (I + 1)) / Segs;
          MidA := 0.5 * (A0 + A1);
          X0 := Cos(A0) * HX; Z0 := Sin(A0) * HZ;
          X1 := Cos(A1) * HX; Z1 := Sin(A1) * HZ;
          AppendOrientedPolygon(Result,
            [V(X0, -HY, Z0), V(X1, -HY, Z1), V(X1, HY, Z1), V(X0, HY, Z0)],
            D(Cos(MidA) / HX, 0.0, Sin(MidA) / HZ), ABrush.TintColor);
        end;
      end;

    cbsArchCorridor:
      begin
        Segs := Clamped(ABrush.Segments, 4, 24);
        ArchRadY := Min(HX, SY * 0.45);
        SpringY := HY - ArchRadY;
        { Profile has 2 bottom corners + (Segs + 1) semicircular vault vertices }
        SetLength(FrontCap, Segs + 3);
        SetLength(BackCap, Segs + 3);
        FrontCap[0] := V(-HX, -HY,  HZ);
        FrontCap[1] := V( HX, -HY,  HZ);
        BackCap[0]  := V(-HX, -HY, -HZ);
        BackCap[1]  := V( HX, -HY, -HZ);
        for I := 0 to Segs do
        begin
          A0 := (Pi * I) / Segs;
          X0 := Cos(A0) * HX;
          Y0 := SpringY + Sin(A0) * ArchRadY;
          FrontCap[2 + I] := V(X0, Y0,  HZ);
          BackCap[2 + I]  := V(X0, Y0, -HZ);
        end;
        AppendOrientedPolygon(Result, FrontCap, D(0, 0,  1), ABrush.TintColor);
        AppendOrientedPolygon(Result, BackCap,  D(0, 0, -1), ABrush.TintColor);
        { Floor }
        AppendOrientedPolygon(Result,
          [V(-HX, -HY, HZ), V(-HX, -HY, -HZ), V(HX, -HY, -HZ), V(HX, -HY, HZ)],
          D(0, -1, 0), ABrush.TintColor);
        { Right & left vertical jambs }
        if SpringY > -HY + 1.0e-4 then
        begin
          AppendOrientedPolygon(Result,
            [V(HX, -HY, HZ), V(HX, -HY, -HZ), V(HX, SpringY, -HZ), V(HX, SpringY, HZ)],
            D(1, 0, 0), ABrush.TintColor);
          AppendOrientedPolygon(Result,
            [V(-HX, -HY, -HZ), V(-HX, -HY, HZ), V(-HX, SpringY, HZ), V(-HX, SpringY, -HZ)],
            D(-1, 0, 0), ABrush.TintColor);
        end;
        { Vaulted semicircular ceiling segments }
        for I := 0 to Segs - 1 do
        begin
          A0 := (Pi * I) / Segs;
          A1 := (Pi * (I + 1)) / Segs;
          MidA := 0.5 * (A0 + A1);
          X0 := Cos(A0) * HX; Y0 := SpringY + Sin(A0) * ArchRadY;
          X1 := Cos(A1) * HX; Y1 := SpringY + Sin(A1) * ArchRadY;
          AppendOrientedPolygon(Result,
            [V(X0, Y0, HZ), V(X0, Y0, -HZ), V(X1, Y1, -HZ), V(X1, Y1, HZ)],
            D(Cos(MidA) / Max(0.05, HX), Sin(MidA) / Max(0.05, ArchRadY), 0.0),
            ABrush.TintColor);
        end;
      end;

    cbsRampWedge:
      begin
        { Wedge rising from front (+HZ, -HY) up to back (-HZ, +HY) }
        AppendOrientedPolygon(Result,
          [V(-HX, -HY, HZ), V(-HX, -HY, -HZ), V(HX, -HY, -HZ), V(HX, -HY, HZ)],
          D(0, -1, 0), ABrush.TintColor);
        AppendOrientedPolygon(Result,
          [V(HX, -HY, -HZ), V(-HX, -HY, -HZ), V(-HX, HY, -HZ), V(HX, HY, -HZ)],
          D(0, 0, -1), ABrush.TintColor);
        AppendOrientedPolygon(Result,
          [V(-HX, -HY, HZ), V(HX, -HY, HZ), V(HX, HY, -HZ), V(-HX, HY, -HZ)],
          D(0, SZ, SY), ABrush.TintColor);
        AppendOrientedPolygon(Result,
          [V(HX, -HY, HZ), V(HX, -HY, -HZ), V(HX, HY, -HZ)],
          D(1, 0, 0), ABrush.TintColor);
        AppendOrientedPolygon(Result,
          [V(-HX, -HY, -HZ), V(-HX, -HY, HZ), V(-HX, HY, -HZ)],
          D(-1, 0, 0), ABrush.TintColor);
      end;

    cbsStairwell:
      begin
        Segs := Clamped(ABrush.Segments, 2, 24);
        { Closed manifold outer shell made solely of convex rectangles }
        AppendOrientedPolygon(Result,
          [V(-HX, -HY, HZ), V(-HX, -HY, -HZ), V(HX, -HY, -HZ), V(HX, -HY, HZ)],
          D(0, -1, 0), ABrush.TintColor);
        AppendOrientedPolygon(Result,
          [V(HX, -HY, -HZ), V(-HX, -HY, -HZ), V(-HX, HY, -HZ), V(HX, HY, -HZ)],
          D(0, 0, -1), ABrush.TintColor);
        PrevTopY := -HY;
        for I := 0 to Segs - 1 do
        begin
          CurTopY := -HY + SY * ((I + 1) / Segs);
          ZF0 := HZ - SZ * (I / Segs);
          ZF1 := HZ - SZ * ((I + 1) / Segs);
          { Riser (+Z) }
          AppendOrientedPolygon(Result,
            [V(-HX, PrevTopY, ZF0), V(HX, PrevTopY, ZF0), V(HX, CurTopY, ZF0), V(-HX, CurTopY, ZF0)],
            D(0, 0, 1), ABrush.TintColor);
          { Tread (+Y) }
          AppendOrientedPolygon(Result,
            [V(-HX, CurTopY, ZF0), V(HX, CurTopY, ZF0), V(HX, CurTopY, ZF1), V(-HX, CurTopY, ZF1)],
            D(0, 1, 0), ABrush.TintColor);
          { Right & left cheek column slices }
          AppendOrientedPolygon(Result,
            [V(HX, -HY, ZF0), V(HX, -HY, ZF1), V(HX, CurTopY, ZF1), V(HX, CurTopY, ZF0)],
            D(1, 0, 0), ABrush.TintColor);
          AppendOrientedPolygon(Result,
            [V(-HX, -HY, ZF1), V(-HX, -HY, ZF0), V(-HX, CurTopY, ZF0), V(-HX, CurTopY, ZF1)],
            D(-1, 0, 0), ABrush.TintColor);
          PrevTopY := CurTopY;
        end;
      end;
  end;
end;

{ 3D Polygon-Splitting BSP Tree ---------------------------------------------- }

procedure AppendPoly(var Arr: TCsgPolygonArray; const P: TCsgPolygon);
var
  L: Integer;
begin
  if Length(P.Vertices) < 3 then
    Exit;
  L := Length(Arr);
  SetLength(Arr, L + 1);
  Arr[L] := P;
end;

procedure AppendPolys(var Dest: TCsgPolygonArray; const Src: TCsgPolygonArray);
var
  BaseLen, I: Integer;
begin
  if Length(Src) = 0 then
    Exit;
  BaseLen := Length(Dest);
  SetLength(Dest, BaseLen + Length(Src));
  for I := 0 to High(Src) do
    Dest[BaseLen + I] := Src[I];
end;

function ClonePolyInverted(const P: TCsgPolygon): TCsgPolygon;
var
  N, I: Integer;
begin
  N := Length(P.Vertices);
  SetLength(Result.Vertices, N);
  for I := 0 to N - 1 do
    Result.Vertices[I] := P.Vertices[N - 1 - I];
  Result.Normal := -P.Normal;
  Result.PlaneW := -P.PlaneW;
  Result.TintColor := P.TintColor;
end;

function CleanVertices(const Raw: array of TVector3): TCsgPolygon;
var
  Cleaned: array of TVector3;
  I, Count: Integer;
begin
  SetLength(Cleaned, 0);
  Count := 0;
  for I := 0 to High(Raw) do
  begin
    if (Count = 0) or (PointsDistanceSqr(Cleaned[Count - 1], Raw[I]) > 1.0e-10) then
    begin
      SetLength(Cleaned, Count + 1);
      Cleaned[Count] := Raw[I];
      Inc(Count);
    end;
  end;
  if (Count > 1) and (PointsDistanceSqr(Cleaned[0], Cleaned[Count - 1]) <= 1.0e-10) then
  begin
    Dec(Count);
    SetLength(Cleaned, Count);
  end;
  SetLength(Result.Vertices, Count);
  for I := 0 to Count - 1 do
    Result.Vertices[I] := Cleaned[I];
  Result.Normal := Vector3(0, 1, 0);
  Result.PlaneW := 0.0;
  Result.TintColor := Vector3(1, 1, 1);
end;

procedure SplitPolygonByPlane(const PlaneN: TVector3; const PlaneW: Single;
  const Poly: TCsgPolygon;
  var CoplanarFront, CoplanarBack, Front, Back: TCsgPolygonArray);
var
  PolyType, I, J, N: Integer;
  Types: array of Integer;
  D, Denom, T: Single;
  VI, VJ, MidV: TVector3;
  FList, BList: array of TVector3;
  FC, BC: Integer;
  SubPoly: TCsgPolygon;
begin
  N := Length(Poly.Vertices);
  if N < 3 then
    Exit;

  PolyType := 0;
  SetLength(Types, N);
  for I := 0 to N - 1 do
  begin
    D := TVector3.DotProduct(PlaneN, Poly.Vertices[I]) - PlaneW;
    if D < -BspPlaneEps then
      Types[I] := cpBack
    else if D > BspPlaneEps then
      Types[I] := cpFront
    else
      Types[I] := cpCoplanar;
    PolyType := PolyType or Types[I];
  end;

  case PolyType of
    cpCoplanar:
      begin
        if TVector3.DotProduct(PlaneN, Poly.Normal) > 0.0 then
          AppendPoly(CoplanarFront, Poly)
        else
          AppendPoly(CoplanarBack, Poly);
      end;
    cpFront:
      AppendPoly(Front, Poly);
    cpBack:
      AppendPoly(Back, Poly);
    cpSpanning:
      begin
        SetLength(FList, N * 2);
        SetLength(BList, N * 2);
        FC := 0;
        BC := 0;
        for I := 0 to N - 1 do
        begin
          J := (I + 1) mod N;
          VI := Poly.Vertices[I];
          VJ := Poly.Vertices[J];
          if Types[I] <> cpBack then
          begin
            FList[FC] := VI;
            Inc(FC);
          end;
          if Types[I] <> cpFront then
          begin
            BList[BC] := VI;
            Inc(BC);
          end;
          if (Types[I] or Types[J]) = cpSpanning then
          begin
            Denom := TVector3.DotProduct(PlaneN, VJ - VI);
            if Abs(Denom) > 1.0e-12 then
              T := Clamped((PlaneW - TVector3.DotProduct(PlaneN, VI)) / Denom, 0.0, 1.0)
            else
              T := 0.5;
            MidV := Lerp(T, VI, VJ);
            FList[FC] := MidV;
            Inc(FC);
            BList[BC] := MidV;
            Inc(BC);
          end;
        end;
        SetLength(FList, FC);
        SetLength(BList, BC);

        if FC >= 3 then
        begin
          SubPoly := CleanVertices(FList);
          if Length(SubPoly.Vertices) >= 3 then
          begin
            SubPoly.Normal := Poly.Normal;
            SubPoly.PlaneW := Poly.PlaneW;
            SubPoly.TintColor := Poly.TintColor;
            AppendPoly(Front, SubPoly);
          end;
        end;

        if BC >= 3 then
        begin
          SubPoly := CleanVertices(BList);
          if Length(SubPoly.Vertices) >= 3 then
          begin
            SubPoly.Normal := Poly.Normal;
            SubPoly.PlaneW := Poly.PlaneW;
            SubPoly.TintColor := Poly.TintColor;
            AppendPoly(Back, SubPoly);
          end;
        end;
      end;
  end;
end;

type
  TCsgBspNode = class
  strict private
    FHasPlane: Boolean;
    FPlaneNormal: TVector3;
    FPlaneW: Single;
    FPolygons: TCsgPolygonArray;
    FFront: TCsgBspNode;
    FBack: TCsgBspNode;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Build(const APolygons: TCsgPolygonArray; const ADepth: Integer = 0);
    procedure Invert;
    function ClipPolygons(const APolygons: TCsgPolygonArray): TCsgPolygonArray;
    procedure ClipTo(const ABsp: TCsgBspNode);
    function AllPolygons: TCsgPolygonArray;
  end;

constructor TCsgBspNode.Create;
begin
  inherited Create;
  FHasPlane := False;
  FPlaneNormal := Vector3(0, 1, 0);
  FPlaneW := 0.0;
  FPolygons := nil;
  FFront := nil;
  FBack := nil;
end;

destructor TCsgBspNode.Destroy;
begin
  FreeAndNil(FFront);
  FreeAndNil(FBack);
  inherited;
end;

procedure TCsgBspNode.Build(const APolygons: TCsgPolygonArray; const ADepth: Integer);
var
  FrontList, BackList: TCsgPolygonArray;
  StartIdx, I: Integer;
begin
  if Length(APolygons) = 0 then
    Exit;

  if ADepth >= MaxBspDepth then
  begin
    AppendPolys(FPolygons, APolygons);
    Exit;
  end;

  StartIdx := 0;
  if not FHasPlane then
  begin
    FPlaneNormal := APolygons[0].Normal;
    FPlaneW := APolygons[0].PlaneW;
    FHasPlane := True;
    AppendPoly(FPolygons, APolygons[0]);
    StartIdx := 1;
  end;

  FrontList := nil;
  BackList := nil;
  for I := StartIdx to High(APolygons) do
    SplitPolygonByPlane(FPlaneNormal, FPlaneW, APolygons[I],
      FPolygons, FPolygons, FrontList, BackList);

  if Length(FrontList) > 0 then
  begin
    if FFront = nil then
      FFront := TCsgBspNode.Create;
    FFront.Build(FrontList, ADepth + 1);
  end;

  if Length(BackList) > 0 then
  begin
    if FBack = nil then
      FBack := TCsgBspNode.Create;
    FBack.Build(BackList, ADepth + 1);
  end;
end;

procedure TCsgBspNode.Invert;
var
  I: Integer;
  Tmp: TCsgBspNode;
begin
  for I := 0 to High(FPolygons) do
    FPolygons[I] := ClonePolyInverted(FPolygons[I]);
  if FHasPlane then
  begin
    FPlaneNormal := -FPlaneNormal;
    FPlaneW := -FPlaneW;
  end;
  if FFront <> nil then
    FFront.Invert;
  if FBack <> nil then
    FBack.Invert;
  Tmp := FFront;
  FFront := FBack;
  FBack := Tmp;
end;

function TCsgBspNode.ClipPolygons(const APolygons: TCsgPolygonArray): TCsgPolygonArray;
var
  FrontList, BackList: TCsgPolygonArray;
  I: Integer;
begin
  if not FHasPlane then
  begin
    Result := Copy(APolygons, 0, Length(APolygons));
    Exit;
  end;

  FrontList := nil;
  BackList := nil;
  for I := 0 to High(APolygons) do
    SplitPolygonByPlane(FPlaneNormal, FPlaneW, APolygons[I],
      FrontList, BackList, FrontList, BackList);

  if FFront <> nil then
    FrontList := FFront.ClipPolygons(FrontList);
  if FBack <> nil then
    BackList := FBack.ClipPolygons(BackList)
  else
    BackList := nil;

  Result := FrontList;
  AppendPolys(Result, BackList);
end;

procedure TCsgBspNode.ClipTo(const ABsp: TCsgBspNode);
begin
  FPolygons := ABsp.ClipPolygons(FPolygons);
  if FFront <> nil then
    FFront.ClipTo(ABsp);
  if FBack <> nil then
    FBack.ClipTo(ABsp);
end;

function TCsgBspNode.AllPolygons: TCsgPolygonArray;
var
  Sub: TCsgPolygonArray;
begin
  Result := Copy(FPolygons, 0, Length(FPolygons));
  if FFront <> nil then
  begin
    Sub := FFront.AllPolygons;
    AppendPolys(Result, Sub);
  end;
  if FBack <> nil then
  begin
    Sub := FBack.AllPolygons;
    AppendPolys(Result, Sub);
  end;
end;

function EvaluateCsgBoolean(const APolysA, APolysB: TCsgPolygonArray;
  const AOp: TCsgBooleanOperation): TCsgPolygonArray;
var
  NodeA, NodeB: TCsgBspNode;
begin
  if Length(APolysA) = 0 then
  begin
    if AOp = cboUnion then
      Result := Copy(APolysB, 0, Length(APolysB))
    else
      Result := nil;
    Exit;
  end;
  if Length(APolysB) = 0 then
  begin
    if AOp = cboIntersect then
      Result := nil
    else
      Result := Copy(APolysA, 0, Length(APolysA));
    Exit;
  end;

  NodeA := TCsgBspNode.Create;
  NodeB := TCsgBspNode.Create;
  try
    NodeA.Build(APolysA);
    NodeB.Build(APolysB);

    case AOp of
      cboUnion:
        begin
          NodeA.ClipTo(NodeB);
          NodeB.ClipTo(NodeA);
          NodeB.Invert;
          NodeB.ClipTo(NodeA);
          NodeB.Invert;
          NodeA.Build(NodeB.AllPolygons);
          Result := NodeA.AllPolygons;
        end;

      cboSubtract:
        begin
          NodeA.Invert;
          NodeA.ClipTo(NodeB);
          NodeB.ClipTo(NodeA);
          NodeB.Invert;
          NodeB.ClipTo(NodeA);
          NodeB.Invert;
          NodeA.Build(NodeB.AllPolygons);
          NodeA.Invert;
          Result := NodeA.AllPolygons;
        end;

      cboIntersect:
        begin
          NodeA.Invert;
          NodeB.ClipTo(NodeA);
          NodeB.Invert;
          NodeA.ClipTo(NodeB);
          NodeB.ClipTo(NodeA);
          NodeA.Build(NodeB.AllPolygons);
          NodeA.Invert;
          Result := NodeA.AllPolygons;
        end;
    end;
  finally
    FreeAndNil(NodeA);
    FreeAndNil(NodeB);
  end;
end;

{ TCastleCsgModeler ---------------------------------------------------------- }

constructor TCastleCsgModeler.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBrushes := TCsgBrushList.Create;
  FUvTilingScale := DefaultUvTilingScale;
  FRoughness := DefaultRoughness;
  FMetallic := DefaultMetallic;
  FGenerateCollider := DefaultGenerateCollider;
  FBaseColor := Vector3(1.0, 1.0, 1.0);

  FBaseColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FBaseColorPersistent.SetSubComponent(True);
  FBaseColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetBaseColorForPersistent;
  FBaseColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetBaseColorForPersistent;
  FBaseColorPersistent.InternalDefaultValue := FBaseColor;

  EnsureRenderScene;
  ApplyPreset(capHollowRoomWithArchDoorway);
end;

destructor TCastleCsgModeler.Destroy;
begin
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FBaseColorPersistent);
  FreeAndNil(FBrushes);
  inherited;
end;

function TCastleCsgModeler.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'BrushesJson') or
     (PropertyName = 'UvTilingScale') or
     (PropertyName = 'Roughness') or
     (PropertyName = 'Metallic') or
     (PropertyName = 'GenerateCollider') or
     (PropertyName = 'BaseColorPersistent') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleCsgModeler.GetBaseColorForPersistent: TCastleColorRGB;
begin
  Result := FBaseColor;
end;

procedure TCastleCsgModeler.SetBaseColorForPersistent(const AValue: TCastleColorRGB);
begin
  BaseColor := AValue;
end;

procedure TCastleCsgModeler.SetBaseColor(const Value: TCastleColorRGB);
begin
  if not TVector3.PerfectlyEquals(FBaseColor, Value) then
  begin
    FBaseColor := Value;
    if FMaterialNode <> nil then
      FMaterialNode.BaseColor := FBaseColor;
  end;
end;

procedure TCastleCsgModeler.SetPreset(const Value: TCsgArchitecturalPreset);
begin
  if FPreset <> Value then
  begin
    if Value = capCustom then
      FPreset := capCustom
    else
      ApplyPreset(Value);
  end;
end;

procedure TCastleCsgModeler.SetUvTilingScale(const Value: Single);
var
  ClampedVal: Single;
begin
  ClampedVal := Max(0.01, Value);
  if not SameValue(FUvTilingScale, ClampedVal) then
  begin
    FUvTilingScale := ClampedVal;
    RebuildMesh;
  end;
end;

procedure TCastleCsgModeler.SetRoughness(const Value: Single);
var
  ClampedVal: Single;
begin
  ClampedVal := Clamped(Value, 0.0, 1.0);
  if not SameValue(FRoughness, ClampedVal) then
  begin
    FRoughness := ClampedVal;
    if FMaterialNode <> nil then
      FMaterialNode.Roughness := FRoughness;
  end;
end;

procedure TCastleCsgModeler.SetMetallic(const Value: Single);
var
  ClampedVal: Single;
begin
  ClampedVal := Clamped(Value, 0.0, 1.0);
  if not SameValue(FMetallic, ClampedVal) then
  begin
    FMetallic := ClampedVal;
    if FMaterialNode <> nil then
      FMaterialNode.Metallic := FMetallic;
  end;
end;

procedure TCastleCsgModeler.SetGenerateCollider(const Value: Boolean);
begin
  if FGenerateCollider <> Value then
  begin
    FGenerateCollider := Value;
    SyncColliderState;
  end;
end;

procedure TCastleCsgModeler.SyncColliderState;
begin
  if FRenderScene <> nil then
  begin
    FRenderScene.Collides := FGenerateCollider;
    FRenderScene.Pickable := True;
    FRenderScene.PreciseCollisions := FGenerateCollider;
  end;
end;

procedure TCastleCsgModeler.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Name := 'TransientCsgMesh';

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;

  FAppearanceNode := TAppearanceNode.Create;
  FMaterialNode := TPhysicalMaterialNode.Create;
  FMaterialNode.BaseColor := FBaseColor;
  FMaterialNode.Roughness := FRoughness;
  FMaterialNode.Metallic := FMetallic;
  FAppearanceNode.Material := FMaterialNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := True;
  FCoordNode := TCoordinateNode.Create;
  FNormalNode := TNormalNode.Create;
  FTexCoordNode := TTextureCoordinateNode.Create;
  FColorNode := TColorNode.Create;

  FTriSetNode.Coord := FCoordNode;
  FTriSetNode.Normal := FNormalNode;
  FTriSetNode.TexCoord := FTexCoordNode;
  FTriSetNode.Color := FColorNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  FRenderScene.Load(FRootNode, True);
  SyncColliderState;
  Add(FRenderScene);
end;

procedure TCastleCsgModeler.ApplyPreset(const APreset: TCsgArchitecturalPreset);
var
  B: TCsgBrushItem;
begin
  FPreset := APreset;
  if APreset = capCustom then
    Exit;

  FBrushes.Clear;
  case APreset of
    capHollowRoomWithArchDoorway:
      begin
        { 10 x 4 x 10 m outer stone room shell }
        B := TCsgBrushItem.DefaultBox('OuterRoomShell');
        B.Center := Vector3(0.0, 2.0, 0.0);
        B.Size := Vector3(10.0, 4.0, 10.0);
        B.TintColor := Vector3(0.72, 0.75, 0.80);
        FBrushes.Add(B);

        { 8.8 x 3.2 x 8.8 m hollow interior (0.4m floor/ceiling, 0.6m walls) }
        B := TCsgBrushItem.DefaultBox('InteriorRoomCarve');
        B.Operation := cboSubtract;
        B.Center := Vector3(0.0, 2.0, 0.0);
        B.Size := Vector3(8.8, 3.2, 8.8);
        B.TintColor := Vector3(0.84, 0.82, 0.76);
        FBrushes.Add(B);

        { Semicircular Roman arched front doorway carved through +Z wall }
        B := TCsgBrushItem.DefaultBox('FrontArchDoorway');
        B.Operation := cboSubtract;
        B.Shape := cbsArchCorridor;
        B.Center := Vector3(0.0, 1.65, 4.7);
        B.Size := Vector3(2.4, 2.5, 1.4);
        B.Segments := 8;
        B.TintColor := Vector3(0.88, 0.80, 0.66);
        FBrushes.Add(B);
      end;

    capVaultedCrossHallway:
      begin
        B := TCsgBrushItem.DefaultBox('MasonryBlock');
        B.Center := Vector3(0.0, 2.2, 0.0);
        B.Size := Vector3(12.0, 4.4, 12.0);
        B.TintColor := Vector3(0.66, 0.70, 0.76);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('NorthSouthVault');
        B.Operation := cboSubtract;
        B.Shape := cbsArchCorridor;
        B.Center := Vector3(0.0, 1.9, 0.0);
        B.Size := Vector3(3.4, 3.0, 12.6);
        B.Segments := 8;
        B.TintColor := Vector3(0.85, 0.82, 0.75);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('EastWestVault');
        B.Operation := cboSubtract;
        B.Shape := cbsArchCorridor;
        B.Center := Vector3(0.0, 1.9, 0.0);
        B.Size := Vector3(3.4, 3.0, 12.6);
        B.YawDeg := 90.0;
        B.Segments := 8;
        B.TintColor := Vector3(0.85, 0.82, 0.75);
        FBrushes.Add(B);
      end;

    capMezzanineRampAndStairs:
      begin
        B := TCsgBrushItem.DefaultBox('FloorSlab');
        B.Center := Vector3(0.0, 0.2, 0.0);
        B.Size := Vector3(12.0, 0.4, 10.0);
        B.TintColor := Vector3(0.68, 0.70, 0.73);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('MezzanineDeck');
        B.Center := Vector3(0.0, 1.4, -2.5);
        B.Size := Vector3(12.0, 2.0, 5.0);
        B.TintColor := Vector3(0.75, 0.78, 0.84);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('LeftStairwell');
        B.Shape := cbsStairwell;
        B.Center := Vector3(-3.0, 1.4, 2.0);
        B.Size := Vector3(2.6, 2.0, 4.0);
        B.Segments := 8;
        B.TintColor := Vector3(0.88, 0.82, 0.70);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('RightAccessRamp');
        B.Shape := cbsRampWedge;
        B.Center := Vector3(3.0, 1.4, 2.0);
        B.Size := Vector3(2.6, 2.0, 4.0);
        B.TintColor := Vector3(0.72, 0.84, 0.78);
        FBrushes.Add(B);
      end;

    capPillaredCourtyardCloister:
      begin
        B := TCsgBrushItem.DefaultBox('CloisterPlinth');
        B.Center := Vector3(0.0, 0.25, 0.0);
        B.Size := Vector3(12.0, 0.5, 12.0);
        B.TintColor := Vector3(0.74, 0.74, 0.72);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('SunkenBasin');
        B.Operation := cboSubtract;
        B.Shape := cbsCylinder;
        B.Center := Vector3(0.0, 0.40, 0.0);
        B.Size := Vector3(5.0, 0.5, 5.0);
        B.Segments := 12;
        B.TintColor := Vector3(0.54, 0.70, 0.78);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('PillarNW');
        B.Shape := cbsCylinder;
        B.Center := Vector3(-4.2, 2.0, -4.2);
        B.Size := Vector3(1.0, 3.0, 1.0);
        B.Segments := 10;
        B.TintColor := Vector3(0.86, 0.84, 0.79);
        FBrushes.Add(B);

        B := TCsgBrushItem.DefaultBox('PillarNE');
        B.Shape := cbsCylinder;
        B.Center := Vector3(4.2, 2.0, -4.2);
        B.Size := Vector3(1.0, 3.0, 1.0);
        B.Segments := 10;
        B.TintColor := Vector3(0.86, 0.84, 0.79);
        FBrushes.Add(B);
      end;
  end;

  RebuildMesh;
end;

function TCastleCsgModeler.AddBrush(const ABrush: TCsgBrushItem): Integer;
begin
  FPreset := capCustom;
  Result := FBrushes.Add(ABrush);
  RebuildMesh;
end;

procedure TCastleCsgModeler.UpdateBrush(const AIndex: Integer; const ABrush: TCsgBrushItem);
begin
  if (AIndex < 0) or (AIndex >= FBrushes.Count) then
    Exit;
  FPreset := capCustom;
  FBrushes[AIndex] := ABrush;
  RebuildMesh;
end;

procedure TCastleCsgModeler.DeleteBrush(const AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FBrushes.Count) then
    Exit;
  FPreset := capCustom;
  FBrushes.Delete(AIndex);
  RebuildMesh;
end;

procedure TCastleCsgModeler.MoveBrush(const AFromIndex, AToIndex: Integer);
begin
  if (AFromIndex < 0) or (AFromIndex >= FBrushes.Count) or
     (AToIndex < 0) or (AToIndex >= FBrushes.Count) or
     (AFromIndex = AToIndex) then
    Exit;
  FPreset := capCustom;
  FBrushes.Move(AFromIndex, AToIndex);
  RebuildMesh;
end;

procedure TCastleCsgModeler.ClearBrushes;
begin
  FPreset := capCustom;
  FBrushes.Clear;
  RebuildMesh;
end;

function TCastleCsgModeler.EnabledBrushCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FBrushes.Count - 1 do
    if FBrushes[I].Enabled then
      Inc(Result);
end;

function TCastleCsgModeler.ComputeTriplanarUv(const APoint, ANormal: TVector3): TVector2;
var
  AX, AY, AZ: Single;
begin
  AX := Abs(ANormal.X);
  AY := Abs(ANormal.Y);
  AZ := Abs(ANormal.Z);
  if (AY >= AX) and (AY >= AZ) then
    Result := Vector2(APoint.X * FUvTilingScale, APoint.Z * FUvTilingScale)
  else if AX >= AZ then
    Result := Vector2(APoint.Z * FUvTilingScale, APoint.Y * FUvTilingScale)
  else
    Result := Vector2(APoint.X * FUvTilingScale, APoint.Y * FUvTilingScale);
end;

procedure TCastleCsgModeler.RebuildMesh;
var
  Accumulated, BrushPolys: TCsgPolygonArray;
  HasAnySolid: Boolean;
  I, PIdx, VIdx, TriCount, VertCount, OutCursor: Integer;
  Poly: TCsgPolygon;
  V0, V1, V2, N: TVector3;
  SignedVol6: Double;
  PointsArr, NormalsArr, ColorsArr: array of TVector3;
  UvsArr: array of TVector2;
begin
  EnsureRenderScene;

  Accumulated := nil;
  HasAnySolid := False;
  for I := 0 to FBrushes.Count - 1 do
  begin
    if not FBrushes[I].Enabled then
      Continue;
    BrushPolys := BuildBrushPolygons(FBrushes[I]);
    if Length(BrushPolys) = 0 then
      Continue;

    if not HasAnySolid then
    begin
      if FBrushes[I].Operation = cboUnion then
      begin
        Accumulated := BrushPolys;
        HasAnySolid := True;
      end;
    end else
    begin
      Accumulated := EvaluateCsgBoolean(Accumulated, BrushPolys, FBrushes[I].Operation);
    end;
  end;

  TriCount := 0;
  for PIdx := 0 to High(Accumulated) do
    if Length(Accumulated[PIdx].Vertices) >= 3 then
      Inc(TriCount, Length(Accumulated[PIdx].Vertices) - 2);

  VertCount := TriCount * 3;
  SetLength(PointsArr, VertCount);
  SetLength(NormalsArr, VertCount);
  SetLength(UvsArr, VertCount);
  SetLength(ColorsArr, VertCount);

  OutCursor := 0;
  SignedVol6 := 0.0;
  for PIdx := 0 to High(Accumulated) do
  begin
    Poly := Accumulated[PIdx];
    if Length(Poly.Vertices) < 3 then
      Continue;
    V0 := Poly.Vertices[0];
    N := Poly.Normal;
    for VIdx := 1 to High(Poly.Vertices) - 1 do
    begin
      V1 := Poly.Vertices[VIdx];
      V2 := Poly.Vertices[VIdx + 1];

      PointsArr[OutCursor]     := V0;
      PointsArr[OutCursor + 1] := V1;
      PointsArr[OutCursor + 2] := V2;

      NormalsArr[OutCursor]     := N;
      NormalsArr[OutCursor + 1] := N;
      NormalsArr[OutCursor + 2] := N;

      UvsArr[OutCursor]     := ComputeTriplanarUv(V0, N);
      UvsArr[OutCursor + 1] := ComputeTriplanarUv(V1, N);
      UvsArr[OutCursor + 2] := ComputeTriplanarUv(V2, N);

      ColorsArr[OutCursor]     := Poly.TintColor;
      ColorsArr[OutCursor + 1] := Poly.TintColor;
      ColorsArr[OutCursor + 2] := Poly.TintColor;

      SignedVol6 := SignedVol6 +
        TVector3.DotProduct(V0, TVector3.CrossProduct(V1, V2));
      Inc(OutCursor, 3);
    end;
  end;

  FOutputTriangleCount := TriCount;
  FOutputVertexCount := VertCount;
  FOutputVolumeCubicMeters := Max(0.0, Single(SignedVol6 / 6.0));

  FCoordNode.SetPoint(PointsArr);
  FNormalNode.SetVector(NormalsArr);
  FTexCoordNode.SetPoint(UvsArr);
  FColorNode.SetColor(ColorsArr);

  FRenderScene.ChangedAll;
  SyncColliderState;
end;

function TCastleCsgModeler.GetBrushesJson: String;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  B: TCsgBrushItem;
begin
  Arr := TJSONArray.Create;
  try
    for I := 0 to FBrushes.Count - 1 do
    begin
      B := FBrushes[I];
      Obj := TJSONObject.Create;
      Obj.Add('id', B.BrushId);
      Obj.Add('enabled', B.Enabled);
      Obj.Add('op', CsgOperationToString(B.Operation));
      Obj.Add('shape', CsgShapeToString(B.Shape));
      Obj.Add('cx', B.Center.X);
      Obj.Add('cy', B.Center.Y);
      Obj.Add('cz', B.Center.Z);
      Obj.Add('sx', B.Size.X);
      Obj.Add('sy', B.Size.Y);
      Obj.Add('sz', B.Size.Z);
      Obj.Add('yaw', B.YawDeg);
      Obj.Add('segs', B.Segments);
      Obj.Add('r', B.TintColor.X);
      Obj.Add('g', B.TintColor.Y);
      Obj.Add('b', B.TintColor.Z);
      Arr.Add(Obj);
    end;
    Result := Arr.AsJSON;
  finally
    FreeAndNil(Arr);
  end;
end;

procedure TCastleCsgModeler.SetBrushesJson(const Value: String);
var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  B: TCsgBrushItem;
begin
  if Trim(Value) = '' then
  begin
    FBrushes.Clear;
    RebuildMesh;
    Exit;
  end;

  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Exit;
    end;
    if not (Data is TJSONArray) then
      Exit;

    Arr := TJSONArray(Data);
    FBrushes.Clear;
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then
        Continue;
      Obj := TJSONObject(Arr.Items[I]);
      B := TCsgBrushItem.DefaultBox(Obj.Get('id', Format('Brush%d', [I + 1])));
      B.Enabled := Obj.Get('enabled', True);
      B.Operation := StringToCsgOperation(Obj.Get('op', 'Union'));
      B.Shape := StringToCsgShape(Obj.Get('shape', 'Box'));
      B.Center := Vector3(
        Obj.Get('cx', 0.0),
        Obj.Get('cy', 1.5),
        Obj.Get('cz', 0.0));
      B.Size := Vector3(
        Max(0.05, Obj.Get('sx', 4.0)),
        Max(0.05, Obj.Get('sy', 3.0)),
        Max(0.05, Obj.Get('sz', 4.0)));
      B.YawDeg := Obj.Get('yaw', 0.0);
      B.Segments := Clamped(Obj.Get('segs', 8), 2, 32);
      B.TintColor := Vector3(
        Clamped(Obj.Get('r', 0.76), 0.0, 1.0),
        Clamped(Obj.Get('g', 0.78), 0.0, 1.0),
        Clamped(Obj.Get('b', 0.82), 0.0, 1.0));
      FBrushes.Add(B);
    end;
    RebuildMesh;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleCsgModeler.CsgSummaryBadge: String;
begin
  Result := Format('[CSG:%s %d brushes %d tris]', [
    CsgPresetDisplayName(FPreset),
    EnabledBrushCount,
    FOutputTriangleCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleCsgModeler, ['CSG Greybox Modeler']);
end.
