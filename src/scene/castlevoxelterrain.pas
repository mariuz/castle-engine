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

{ 3D Signed-Distance-Field (SDF) Voxel Volume, Smooth Polynomial CSG Cave/Arch
  Brush Stack & Crack-Free Marching-Tetrahedra Isosurface Extractor
  (@link(TCastleVoxelVolume), @link(SdfSphere3D), @link(SdfCapsule3D),
  @link(SmoothSdfUnion), @link(SmoothSdfSubtract))
  (Phase 329 — UE 6.0+ Nanite Voxel Caves & Volumetric Overhangs Parity). }
unit CastleVoxelTerrain;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform, CastleScene, X3DNodes;

type
  { Built-in 3D Voxel SDF geological presets. }
  TVoxelVolumePreset = (
    vvpCustom,
    vvpWalkthroughCaveTunnel,
    vvpNaturalStoneArchOverhang,
    vvpFloatingSkyIslandPillars
  );

  { Non-destructive 3D SDF brush operation kind. }
  TVoxelBrushKind = (
    vbkSolidGroundStrata,
    vbkUnionSphere,
    vbkCarveSphere,
    vbkUnionCapsule,
    vbkCarveCapsule,
    vbkUnionRoundBox,
    vbkCarveRoundBox
  );

  { Single parametric 3D SDF brush in @link(TCastleVoxelVolume)'s brush stack. }
  TVoxelBrushOp = record
    Kind: TVoxelBrushKind;
    PointA: TVector3;
    PointB: TVector3; // Capsule endpoint B or Box HalfExtents
    Radius: Single;
    SmoothBlendK: Single;
    Enabled: Boolean;
  end;
  TVoxelBrushOpArray = array of TVoxelBrushOp;

  { Volumetric 3D Signed-Distance-Field (SDF) terrain & cave component
    (@link(TCastleTransform)) supporting true 3D overhangs, walkthrough cave
    tunnels, natural arches, smooth Quilez CSG blends, central-difference
    smooth normals, triplanar UVs, and @code(WorldRay)-pickable @code(csTransient)
    isosurface meshes. }
  TCastleVoxelVolume = class(TCastleTransform)
  public
    const
      DefaultGridDimX = 26;
      DefaultGridDimY = 20;
      DefaultGridDimZ = 26;
      DefaultVoxelSize = 0.75;
  strict private
    FPreset: TVoxelVolumePreset;
    FGridDimX: Integer;
    FGridDimY: Integer;
    FGridDimZ: Integer;
    FVoxelSize: Single;
    FRockColor: TCastleColorRGB;
    FRockColorPersistent: TCastleColorRGBPersistent;

    FBrushes: TVoxelBrushOpArray;
    FSdfGrid: array of Single; // Size = GridDimX * GridDimY * GridDimZ
    FSolidVoxelCount: Integer;
    FGeneratedTriangleCount: Integer;

    FMeshScene: TCastleScene;

    procedure SetPreset(const Value: TVoxelVolumePreset);
    procedure SetGridDimX(const Value: Integer);
    procedure SetGridDimY(const Value: Integer);
    procedure SetGridDimZ(const Value: Integer);
    procedure SetVoxelSize(const Value: Single);
    procedure SetRockColor(const Value: TCastleColorRGB);
    function GetRockColorForPersistent: TCastleColorRGB;
    procedure SetRockColorForPersistent(const AValue: TCastleColorRGB);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function GridIndex(const IX, IY, IZ: Integer): Integer; inline;
    function GridCoordToLocalPos(const IX, IY, IZ: Integer): TVector3; inline;
    function EvaluateBrushStackAtLocal(const P: TVector3): Single;
    function SampleSdfClamped(const IX, IY, IZ: Integer): Single; inline;
    function EstimateGradientNormalAtLocal(const P: TVector3): TVector3;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TVoxelVolumePreset): String; static;
    class function BrushKindDisplayName(const AKind: TVoxelBrushKind): String; static;

    procedure ApplyPreset(const APreset: TVoxelVolumePreset);
    procedure ClearBrushes;
    function AddBrush(const AKind: TVoxelBrushKind; const APointA, APointB: TVector3;
      const ARadius: Single; const ASmoothK: Single = 0.65;
      const AEnabled: Boolean = True): Integer;
    function BrushCount: Integer;
    function GetBrush(const Index: Integer): TVoxelBrushOp;
    procedure SetBrushEnabled(const Index: Integer; const AEnabled: Boolean);

    { Re-evaluate the 3D SDF grid across @code(GridDimX x GridDimY x GridDimZ)
      and extract a crack-free watertight Marching-Tetrahedra @code(TTriangleSetNode)
      into @code(csTransient) @code(TCastleScene) with @code(PreciseCollisions = True). }
    procedure RebuildVoxelFieldAndMesh;

    { Query the evaluated SDF value at local 3D position @code(LocalPos)
      (negative = inside solid rock, positive = open air). }
    function SampleSdfAtLocalPos(const LocalPos: TVector3): Single;

    function VolumeWorldExtent: TVector3;
    function VoxelSummaryBadge: String;

    property RockColor: TCastleColorRGB read FRockColor write SetRockColor;
    property SolidVoxelCount: Integer read FSolidVoxelCount;
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
  published
    property Preset: TVoxelVolumePreset
      read FPreset write SetPreset default vvpWalkthroughCaveTunnel;
    property GridDimX: Integer read FGridDimX write SetGridDimX default DefaultGridDimX;
    property GridDimY: Integer read FGridDimY write SetGridDimY default DefaultGridDimY;
    property GridDimZ: Integer read FGridDimZ write SetGridDimZ default DefaultGridDimZ;
    property VoxelSize: Single read FVoxelSize write SetVoxelSize {$ifdef FPC}default DefaultVoxelSize{$endif};
    property RockColorPersistent: TCastleColorRGBPersistent read FRockColorPersistent;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Exact 3D Signed Distance Functions (negative = inside, positive = outside). }
function SdfSphere3D(const P, Center: TVector3; const Radius: Single): Single;
function SdfCapsule3D(const P, SegA, SegB: TVector3; const Radius: Single): Single;
function SdfRoundBox3D(const P, Center, HalfExtents: TVector3; const CornerRadius: Single): Single;

{ C1-continuous polynomial smooth SDF Boolean operators (Inigo Quilez). }
function SmoothSdfUnion(const D1, D2, SmoothK: Single): Single;
function SmoothSdfSubtract(const BaseSdf, CutterSdf, SmoothK: Single): Single;

implementation

uses
  Math, FpJson, JsonParser,
  CastleUtils, CastleComponentSerialize;

function SdfSphere3D(const P, Center: TVector3; const Radius: Single): Single;
begin
  Result := PointsDistance(P, Center) - Radius;
end;

function SdfCapsule3D(const P, SegA, SegB: TVector3; const Radius: Single): Single;
var
  PA, BA: TVector3;
  Denom, H: Single;
begin
  PA := P - SegA;
  BA := SegB - SegA;
  Denom := BA.LengthSqr;
  if Denom <= 1e-8 then
    Exit(PA.Length - Radius);
  H := Clamped(TVector3.DotProduct(PA, BA) / Denom, 0.0, 1.0);
  Result := (PA - BA * H).Length - Radius;
end;

function SdfRoundBox3D(const P, Center, HalfExtents: TVector3;
  const CornerRadius: Single): Single;
var
  Q, PosQ: TVector3;
  OutsideDist, InsideDist: Single;
begin
  Q.X := Abs(P.X - Center.X) - Max(0.01, HalfExtents.X);
  Q.Y := Abs(P.Y - Center.Y) - Max(0.01, HalfExtents.Y);
  Q.Z := Abs(P.Z - Center.Z) - Max(0.01, HalfExtents.Z);
  PosQ := Vector3(Max(Q.X, 0.0), Max(Q.Y, 0.0), Max(Q.Z, 0.0));
  OutsideDist := PosQ.Length;
  InsideDist := Min(Max(Q.X, Max(Q.Y, Q.Z)), 0.0);
  Result := OutsideDist + InsideDist - Max(0.0, CornerRadius);
end;

function SmoothSdfUnion(const D1, D2, SmoothK: Single): Single;
var
  K, H: Single;
begin
  K := Max(0.0, SmoothK);
  if K <= 1e-5 then
    Exit(Min(D1, D2));
  H := Clamped(0.5 + 0.5 * (D2 - D1) / K, 0.0, 1.0);
  Result := Lerp(H, D2, D1) - K * H * (1.0 - H);
end;

function SmoothSdfSubtract(const BaseSdf, CutterSdf, SmoothK: Single): Single;
var
  K, H: Single;
begin
  K := Max(0.0, SmoothK);
  if K <= 1e-5 then
    Exit(Max(BaseSdf, -CutterSdf));
  H := Clamped(0.5 - 0.5 * (BaseSdf + CutterSdf) / K, 0.0, 1.0);
  Result := Lerp(H, BaseSdf, -CutterSdf) + K * H * (1.0 - H);
end;

function ComputeTriplanarUvLocal(const P, N: TVector3; const ScaleMeters: Single): TVector2;
var
  AX, AY, AZ, InvS: Single;
begin
  InvS := 1.0 / Max(0.1, ScaleMeters);
  AX := Abs(N.X);
  AY := Abs(N.Y);
  AZ := Abs(N.Z);
  if (AY >= AX) and (AY >= AZ) then
    Result := Vector2(P.X * InvS, P.Z * InvS)
  else if AX >= AZ then
    Result := Vector2(P.Z * InvS, P.Y * InvS)
  else
    Result := Vector2(P.X * InvS, P.Y * InvS);
end;

{ TCastleVoxelVolume --------------------------------------------------------- }

constructor TCastleVoxelVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGridDimX := DefaultGridDimX;
  FGridDimY := DefaultGridDimY;
  FGridDimZ := DefaultGridDimZ;
  FVoxelSize := DefaultVoxelSize;
  FRockColor := Vector3(0.46, 0.43, 0.39);

  FRockColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FRockColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetRockColorForPersistent;
  FRockColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetRockColorForPersistent;
  FRockColorPersistent.InternalDefaultValue := FRockColor;

  ApplyPreset(vvpWalkthroughCaveTunnel);
end;

destructor TCastleVoxelVolume.Destroy;
begin
  FreeAndNil(FRockColorPersistent);
  inherited;
end;

procedure TCastleVoxelVolume.Loaded;
begin
  inherited;
  RebuildVoxelFieldAndMesh;
end;

function TCastleVoxelVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'GridDimX', 'GridDimY', 'GridDimZ', 'VoxelSize',
       'RockColorPersistent', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleVoxelVolume.PresetDisplayName(
  const APreset: TVoxelVolumePreset): String;
begin
  case APreset of
    vvpCustom:                    Result := 'Custom 3D Voxel Volume';
    vvpWalkthroughCaveTunnel:     Result := 'Walkthrough Cave Tunnel & Ceiling';
    vvpNaturalStoneArchOverhang:  Result := 'Natural Stone Arch & Cliff Overhang';
    vvpFloatingSkyIslandPillars:  Result := 'Floating Sky Island & Hanging Roots';
  end;
end;

class function TCastleVoxelVolume.BrushKindDisplayName(
  const AKind: TVoxelBrushKind): String;
begin
  case AKind of
    vbkSolidGroundStrata: Result := 'Solid Ground Strata';
    vbkUnionSphere:       Result := '+ Union Sphere';
    vbkCarveSphere:       Result := '- Carve Sphere';
    vbkUnionCapsule:      Result := '+ Union Capsule';
    vbkCarveCapsule:      Result := '- Carve Capsule Tunnel';
    vbkUnionRoundBox:     Result := '+ Union Round Box';
    vbkCarveRoundBox:     Result := '- Carve Round Box';
  end;
end;

procedure TCastleVoxelVolume.SetPreset(const Value: TVoxelVolumePreset);
begin
  if FPreset = Value then
    Exit;
  ApplyPreset(Value);
end;

procedure TCastleVoxelVolume.SetGridDimX(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 6, 56);
  if FGridDimX = V then Exit;
  FGridDimX := V;
  RebuildVoxelFieldAndMesh;
end;

procedure TCastleVoxelVolume.SetGridDimY(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 6, 56);
  if FGridDimY = V then Exit;
  FGridDimY := V;
  RebuildVoxelFieldAndMesh;
end;

procedure TCastleVoxelVolume.SetGridDimZ(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 6, 56);
  if FGridDimZ = V then Exit;
  FGridDimZ := V;
  RebuildVoxelFieldAndMesh;
end;

procedure TCastleVoxelVolume.SetVoxelSize(const Value: Single);
var
  V: Single;
begin
  V := Clamped(Value, 0.15, 5.0);
  if SameValue(FVoxelSize, V) then Exit;
  FVoxelSize := V;
  RebuildVoxelFieldAndMesh;
end;

procedure TCastleVoxelVolume.SetRockColor(const Value: TCastleColorRGB);
begin
  if TVector3.Equals(FRockColor, Value) then Exit;
  FRockColor := Value;
  RebuildVoxelFieldAndMesh;
end;

function TCastleVoxelVolume.GetRockColorForPersistent: TCastleColorRGB;
begin
  Result := FRockColor;
end;

procedure TCastleVoxelVolume.SetRockColorForPersistent(const AValue: TCastleColorRGB);
begin
  RockColor := AValue;
end;

procedure TCastleVoxelVolume.ClearBrushes;
begin
  FBrushes := nil;
end;

function TCastleVoxelVolume.AddBrush(const AKind: TVoxelBrushKind;
  const APointA, APointB: TVector3; const ARadius, ASmoothK: Single;
  const AEnabled: Boolean): Integer;
begin
  Result := Length(FBrushes);
  SetLength(FBrushes, Result + 1);
  FBrushes[Result].Kind := AKind;
  FBrushes[Result].PointA := APointA;
  FBrushes[Result].PointB := APointB;
  FBrushes[Result].Radius := Max(0.10, ARadius);
  FBrushes[Result].SmoothBlendK := Max(0.0, ASmoothK);
  FBrushes[Result].Enabled := AEnabled;
end;

function TCastleVoxelVolume.BrushCount: Integer;
begin
  Result := Length(FBrushes);
end;

function TCastleVoxelVolume.GetBrush(const Index: Integer): TVoxelBrushOp;
begin
  if (Index >= 0) and (Index < Length(FBrushes)) then
    Result := FBrushes[Index]
  else
    Result := Default(TVoxelBrushOp);
end;

procedure TCastleVoxelVolume.SetBrushEnabled(const Index: Integer;
  const AEnabled: Boolean);
begin
  if (Index >= 0) and (Index < Length(FBrushes)) and
     (FBrushes[Index].Enabled <> AEnabled) then
  begin
    FBrushes[Index].Enabled := AEnabled;
    RebuildVoxelFieldAndMesh;
  end;
end;

procedure TCastleVoxelVolume.ApplyPreset(const APreset: TVoxelVolumePreset);
begin
  FPreset := APreset;
  if APreset = vvpCustom then
    Exit;

  ClearBrushes;
  case APreset of
    vvpWalkthroughCaveTunnel:
      begin
        FRockColor := Vector3(0.45, 0.42, 0.38);
        { Solid floor slab Y <= 0.4m + huge rock hill mass (R=7.2m at (0, 2.8, 0)) }
        AddBrush(vbkSolidGroundStrata, Vector3(0.0, 0.40, 0.0), TVector3.Zero, 0.40, 0.0);
        AddBrush(vbkUnionRoundBox, Vector3(0.0, 3.60, 0.0), Vector3(6.8, 3.4, 7.2), 0.85, 0.80);
        { Carve walkthrough tunnel straight along Z from (0, 2.3, -10) to (0, 2.3, +10), R=2.1m!
          Floor stays solid around Y=0.2..0.4m, ceiling overhang stays solid at Y=4.4..7.8m! }
        AddBrush(vbkCarveCapsule, Vector3(0.0, 2.35, -10.0), Vector3(0.0, 2.35, 10.0), 2.05, 0.45);
        { Carve central vaulted cavern dome at (0, 2.8, 0) }
        AddBrush(vbkCarveSphere, Vector3(0.0, 2.80, 0.0), TVector3.Zero, 2.85, 0.55);
      end;

    vvpNaturalStoneArchOverhang:
      begin
        FRockColor := Vector3(0.68, 0.44, 0.28);
        AddBrush(vbkSolidGroundStrata, Vector3(0.0, 0.35, 0.0), TVector3.Zero, 0.35, 0.0);
        AddBrush(vbkUnionRoundBox, Vector3(0.0, 3.80, 0.0), Vector3(6.8, 3.4, 2.2), 0.90, 0.70);
        { Carve big arch opening through the sandstone wall }
        AddBrush(vbkCarveCapsule, Vector3(0.0, 2.20, -6.0), Vector3(0.0, 2.20, 6.0), 2.55, 0.50);
      end;

    vvpFloatingSkyIslandPillars:
      begin
        FRockColor := Vector3(0.36, 0.52, 0.44);
        { Floating island deck + hanging stalactite root cone underneath (no ground strata!) }
        AddBrush(vbkUnionRoundBox, Vector3(0.0, 4.60, 0.0), Vector3(5.6, 1.15, 5.6), 0.80, 0.60);
        AddBrush(vbkUnionSphere, Vector3(0.0, 3.20, 0.0), TVector3.Zero, 3.10, 0.90);
        AddBrush(vbkUnionCapsule, Vector3(-2.2, 4.2, -1.5), Vector3(-1.4, 0.8, -1.0), 1.05, 0.65);
        AddBrush(vbkUnionCapsule, Vector3(2.4, 4.2, 1.6), Vector3(1.5, 1.1, 1.2), 0.95, 0.65);
        AddBrush(vbkCarveSphere, Vector3(0.0, 4.90, 0.0), TVector3.Zero, 1.65, 0.35);
      end;
  end;

  RebuildVoxelFieldAndMesh;
end;

function TCastleVoxelVolume.GridIndex(const IX, IY, IZ: Integer): Integer;
begin
  Result := (IZ * FGridDimY + IY) * FGridDimX + IX;
end;

function TCastleVoxelVolume.GridCoordToLocalPos(
  const IX, IY, IZ: Integer): TVector3;
var
  HalfX, HalfZ: Single;
begin
  HalfX := ((FGridDimX - 1) * FVoxelSize) * 0.5;
  HalfZ := ((FGridDimZ - 1) * FVoxelSize) * 0.5;
  Result := Vector3(
    IX * FVoxelSize - HalfX,
    IY * FVoxelSize - 1.0,
    IZ * FVoxelSize - HalfZ);
end;

function TCastleVoxelVolume.EvaluateBrushStackAtLocal(const P: TVector3): Single;
var
  I: Integer;
  PrimD: Single;
begin
  Result := 100.0; // Empty air
  for I := 0 to High(FBrushes) do
  begin
    if not FBrushes[I].Enabled then
      Continue;
    case FBrushes[I].Kind of
      vbkSolidGroundStrata:
        begin
          { Solid ground slab between Y = -0.8m and Y = PointA.Y (closed bottom so watertight) }
          PrimD := Max(P.Y - FBrushes[I].PointA.Y, -0.65 - P.Y);
          Result := SmoothSdfUnion(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
      vbkUnionSphere:
        begin
          PrimD := SdfSphere3D(P, FBrushes[I].PointA, FBrushes[I].Radius);
          Result := SmoothSdfUnion(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
      vbkCarveSphere:
        begin
          PrimD := SdfSphere3D(P, FBrushes[I].PointA, FBrushes[I].Radius);
          Result := SmoothSdfSubtract(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
      vbkUnionCapsule:
        begin
          PrimD := SdfCapsule3D(P, FBrushes[I].PointA, FBrushes[I].PointB, FBrushes[I].Radius);
          Result := SmoothSdfUnion(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
      vbkCarveCapsule:
        begin
          PrimD := SdfCapsule3D(P, FBrushes[I].PointA, FBrushes[I].PointB, FBrushes[I].Radius);
          Result := SmoothSdfSubtract(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
      vbkUnionRoundBox:
        begin
          PrimD := SdfRoundBox3D(P, FBrushes[I].PointA, FBrushes[I].PointB, FBrushes[I].Radius);
          Result := SmoothSdfUnion(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
      vbkCarveRoundBox:
        begin
          PrimD := SdfRoundBox3D(P, FBrushes[I].PointA, FBrushes[I].PointB, FBrushes[I].Radius);
          Result := SmoothSdfSubtract(Result, PrimD, FBrushes[I].SmoothBlendK);
        end;
    end;
  end;
end;

function TCastleVoxelVolume.SampleSdfClamped(
  const IX, IY, IZ: Integer): Single;
var
  CX, CY, CZ: Integer;
begin
  if Length(FSdfGrid) = 0 then
    Exit(100.0);
  CX := Clamped(IX, 0, FGridDimX - 1);
  CY := Clamped(IY, 0, FGridDimY - 1);
  CZ := Clamped(IZ, 0, FGridDimZ - 1);
  Result := FSdfGrid[GridIndex(CX, CY, CZ)];
end;

function TCastleVoxelVolume.SampleSdfAtLocalPos(const LocalPos: TVector3): Single;
begin
  Result := EvaluateBrushStackAtLocal(LocalPos);
end;

function TCastleVoxelVolume.EstimateGradientNormalAtLocal(const P: TVector3): TVector3;
const
  Eps = 0.08;
var
  GX, GY, GZ, Len: Single;
begin
  GX := EvaluateBrushStackAtLocal(Vector3(P.X + Eps, P.Y, P.Z)) -
        EvaluateBrushStackAtLocal(Vector3(P.X - Eps, P.Y, P.Z));
  GY := EvaluateBrushStackAtLocal(Vector3(P.X, P.Y + Eps, P.Z)) -
        EvaluateBrushStackAtLocal(Vector3(P.X, P.Y - Eps, P.Z));
  GZ := EvaluateBrushStackAtLocal(Vector3(P.X, P.Y, P.Z + Eps)) -
        EvaluateBrushStackAtLocal(Vector3(P.X, P.Y, P.Z - Eps));
  Len := Sqrt(GX * GX + GY * GY + GZ * GZ);
  if Len > 1e-6 then
    Result := Vector3(GX / Len, GY / Len, GZ / Len)
  else
    Result := Vector3(0.0, 1.0, 0.0);
end;

procedure TCastleVoxelVolume.RebuildVoxelFieldAndMesh;
const
  CubeCornerOffsets: array [0..7, 0..2] of Integer = (
    (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
    (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)
  );
  { 6 Kuhn body-diagonal tetrahedra partitioning [0,1]^3 crack-free }
  KuhnTetra: array [0..5, 0..3] of Integer = (
    (0, 1, 5, 6),
    (0, 1, 2, 6),
    (0, 3, 2, 6),
    (0, 3, 7, 6),
    (0, 4, 7, 6),
    (0, 4, 5, 6)
  );
var
  TotalVoxels, IX, IY, IZ, CIdx, TIdx, InsideCount, K, OutCap, VertCount: Integer;
  Val: Single;
  CornerP: array [0..7] of TVector3;
  CornerF: array [0..7] of Single;
  InsideIdx, OutsideIdx: array [0..3] of Integer;
  TetV: Integer;
  Verts, Norms: array of TVector3;
  UVs: array of TVector2;
  P0, P1, P2, Q00, Q01, Q11, Q10: TVector3;
  RootNode: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  CoordNode: TCoordinateNode;
  NormNode: TNormalNode;
  TexNode: TTextureCoordinateNode;

  function InterpZeroEdge(const IA, IB: Integer): TVector3;
  var
    FA, FB, Denom, T: Single;
  begin
    FA := CornerF[IA];
    FB := CornerF[IB];
    Denom := FB - FA;
    if Abs(Denom) < 1e-6 then
      T := 0.5
    else
      T := Clamped(-FA / Denom, 0.0, 1.0);
    Result := Lerp(T, CornerP[IA], CornerP[IB]);
  end;

  procedure EmitOrientedTriangle(const A, B, C: TVector3);
  var
    N0, N1, N2, AvgGrad, GeoCross, V1, V2: TVector3;
  begin
    if PointsDistanceSqr(A, B) < 1e-10 then Exit;
    if PointsDistanceSqr(B, C) < 1e-10 then Exit;
    if PointsDistanceSqr(C, A) < 1e-10 then Exit;

    N0 := EstimateGradientNormalAtLocal(A);
    N1 := EstimateGradientNormalAtLocal(B);
    N2 := EstimateGradientNormalAtLocal(C);
    AvgGrad := N0 + N1 + N2;
    GeoCross := TVector3.CrossProduct(B - A, C - A);

    { Orient CCW winding so face normal always points along +Grad(SDF) (outward into air) }
    if TVector3.DotProduct(GeoCross, AvgGrad) >= 0.0 then
    begin
      V1 := B;
      V2 := C;
    end else
    begin
      V1 := C;
      V2 := B;
      AvgGrad := N2;
      N2 := N1;
      N1 := AvgGrad;
    end;

    if VertCount + 3 > OutCap then
    begin
      OutCap := Max(256, OutCap * 2);
      SetLength(Verts, OutCap);
      SetLength(Norms, OutCap);
      SetLength(UVs, OutCap);
    end;

    Verts[VertCount]     := A;
    Verts[VertCount + 1] := V1;
    Verts[VertCount + 2] := V2;
    Norms[VertCount]     := N0;
    Norms[VertCount + 1] := N1;
    Norms[VertCount + 2] := N2;
    UVs[VertCount]       := ComputeTriplanarUvLocal(A, N0, 3.0);
    UVs[VertCount + 1]   := ComputeTriplanarUvLocal(V1, N1, 3.0);
    UVs[VertCount + 2]   := ComputeTriplanarUvLocal(V2, N2, 3.0);
    Inc(VertCount, 3);
  end;

begin
  TotalVoxels := FGridDimX * FGridDimY * FGridDimZ;
  SetLength(FSdfGrid, TotalVoxels);
  FSolidVoxelCount := 0;

  for IZ := 0 to FGridDimZ - 1 do
    for IY := 0 to FGridDimY - 1 do
      for IX := 0 to FGridDimX - 1 do
      begin
        { Clamp outer boundary faces slightly positive if near zero to seal borders }
        if (IX = 0) or (IX = FGridDimX - 1) or
           (IY = 0) or (IY = FGridDimY - 1) or
           (IZ = 0) or (IZ = FGridDimZ - 1) then
          Val := Max(0.05, EvaluateBrushStackAtLocal(GridCoordToLocalPos(IX, IY, IZ)))
        else
          Val := EvaluateBrushStackAtLocal(GridCoordToLocalPos(IX, IY, IZ));
        FSdfGrid[GridIndex(IX, IY, IZ)] := Val;
        if Val < 0.0 then
          Inc(FSolidVoxelCount);
      end;

  Verts := nil;
  Norms := nil;
  UVs := nil;
  OutCap := 0;
  VertCount := 0;

  for IZ := 0 to FGridDimZ - 2 do
    for IY := 0 to FGridDimY - 2 do
      for IX := 0 to FGridDimX - 2 do
      begin
        InsideCount := 0;
        for CIdx := 0 to 7 do
        begin
          CornerF[CIdx] := FSdfGrid[GridIndex(
            IX + CubeCornerOffsets[CIdx, 0],
            IY + CubeCornerOffsets[CIdx, 1],
            IZ + CubeCornerOffsets[CIdx, 2])];
          if CornerF[CIdx] < 0.0 then
            Inc(InsideCount);
        end;

        if (InsideCount = 0) or (InsideCount = 8) then
          Continue;

        for CIdx := 0 to 7 do
          CornerP[CIdx] := GridCoordToLocalPos(
            IX + CubeCornerOffsets[CIdx, 0],
            IY + CubeCornerOffsets[CIdx, 1],
            IZ + CubeCornerOffsets[CIdx, 2]);

        for TIdx := 0 to 5 do
        begin
          InsideCount := 0;
          for K := 0 to 3 do
          begin
            TetV := KuhnTetra[TIdx, K];
            if CornerF[TetV] < 0.0 then
            begin
              InsideIdx[InsideCount] := TetV;
              Inc(InsideCount);
            end else
              OutsideIdx[K - InsideCount] := TetV;
          end;

          case InsideCount of
            1:
              begin
                P0 := InterpZeroEdge(InsideIdx[0], OutsideIdx[0]);
                P1 := InterpZeroEdge(InsideIdx[0], OutsideIdx[1]);
                P2 := InterpZeroEdge(InsideIdx[0], OutsideIdx[2]);
                EmitOrientedTriangle(P0, P1, P2);
              end;
            2:
              begin
                Q00 := InterpZeroEdge(InsideIdx[0], OutsideIdx[0]);
                Q01 := InterpZeroEdge(InsideIdx[0], OutsideIdx[1]);
                Q11 := InterpZeroEdge(InsideIdx[1], OutsideIdx[1]);
                Q10 := InterpZeroEdge(InsideIdx[1], OutsideIdx[0]);
                EmitOrientedTriangle(Q00, Q01, Q11);
                EmitOrientedTriangle(Q00, Q11, Q10);
              end;
            3:
              begin
                P0 := InterpZeroEdge(OutsideIdx[0], InsideIdx[0]);
                P1 := InterpZeroEdge(OutsideIdx[0], InsideIdx[1]);
                P2 := InterpZeroEdge(OutsideIdx[0], InsideIdx[2]);
                EmitOrientedTriangle(P0, P1, P2);
              end;
          end;
        end;
      end;

  SetLength(Verts, VertCount);
  SetLength(Norms, VertCount);
  SetLength(UVs, VertCount);
  FGeneratedTriangleCount := VertCount div 3;

  if FMeshScene = nil then
  begin
    FMeshScene := TCastleScene.Create(Self);
    FMeshScene.SetTransient;
    FMeshScene.PreciseCollisions := True;
    Add(FMeshScene);
  end;

  RootNode := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := FRockColor;
  Mat.Roughness := 0.86;
  Mat.Metallic := 0.04;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Verts);
  NormNode := TNormalNode.Create;
  NormNode.SetVector(Norms);
  TexNode := TTextureCoordinateNode.Create;
  TexNode.SetPoint(UVs);

  TriSet.Coord := CoordNode;
  TriSet.Normal := NormNode;
  TriSet.TexCoord := TexNode;
  Shape.Geometry := TriSet;
  RootNode.AddChildren(Shape);
  FMeshScene.Load(RootNode, True);
end;

function TCastleVoxelVolume.VolumeWorldExtent: TVector3;
begin
  Result := Vector3(
    (FGridDimX - 1) * FVoxelSize,
    (FGridDimY - 1) * FVoxelSize,
    (FGridDimZ - 1) * FVoxelSize);
end;

function TCastleVoxelVolume.GetConfigJson: String;
var
  Root, BObj: TJSONObject;
  BArr, PA, PB: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    BArr := TJSONArray.Create;
    for I := 0 to High(FBrushes) do
    begin
      BObj := TJSONObject.Create;
      BObj.Add('kind', Ord(FBrushes[I].Kind));
      PA := TJSONArray.Create;
      PA.Add(FBrushes[I].PointA.X);
      PA.Add(FBrushes[I].PointA.Y);
      PA.Add(FBrushes[I].PointA.Z);
      BObj.Add('a', PA);
      PB := TJSONArray.Create;
      PB.Add(FBrushes[I].PointB.X);
      PB.Add(FBrushes[I].PointB.Y);
      PB.Add(FBrushes[I].PointB.Z);
      BObj.Add('b', PB);
      BObj.Add('r', FBrushes[I].Radius);
      BObj.Add('k', FBrushes[I].SmoothBlendK);
      BObj.Add('en', FBrushes[I].Enabled);
      BArr.Add(BObj);
    end;
    Root.Add('brushes', BArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleVoxelVolume.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, BObj: TJSONObject;
  BArr, PA, PB: TJSONArray;
  I, KOrd, POrd: Integer;
  VecA, VecB: TVector3;
begin
  if Trim(Value) = '' then
    Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      POrd := Root.Get('preset', Ord(FPreset));
      if (POrd >= Ord(Low(TVoxelVolumePreset))) and
         (POrd <= Ord(High(TVoxelVolumePreset))) then
        FPreset := TVoxelVolumePreset(POrd);

      if Root.Find('brushes') is TJSONArray then
      begin
        ClearBrushes;
        BArr := TJSONArray(Root.Find('brushes'));
        for I := 0 to BArr.Count - 1 do
          if BArr.Items[I] is TJSONObject then
          begin
            BObj := TJSONObject(BArr.Items[I]);
            KOrd := BObj.Get('kind', 0);
            VecA := TVector3.Zero;
            VecB := TVector3.Zero;
            if (BObj.Find('a') is TJSONArray) and (TJSONArray(BObj.Find('a')).Count >= 3) then
            begin
              PA := TJSONArray(BObj.Find('a'));
              VecA := Vector3(PA.Floats[0], PA.Floats[1], PA.Floats[2]);
            end;
            if (BObj.Find('b') is TJSONArray) and (TJSONArray(BObj.Find('b')).Count >= 3) then
            begin
              PB := TJSONArray(BObj.Find('b'));
              VecB := Vector3(PB.Floats[0], PB.Floats[1], PB.Floats[2]);
            end;
            if (KOrd >= Ord(Low(TVoxelBrushKind))) and
               (KOrd <= Ord(High(TVoxelBrushKind))) then
              AddBrush(TVoxelBrushKind(KOrd), VecA, VecB,
                BObj.Get('r', 1.5), BObj.Get('k', 0.5), BObj.Get('en', True));
          end;
        RebuildVoxelFieldAndMesh;
      end;
    end;
  except
    { Keep current volume on malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleVoxelVolume.VoxelSummaryBadge: String;
begin
  Result := Format('[VoxelSDF:%dx%dx%d %d brushes %d tris]',
    [FGridDimX, FGridDimY, FGridDimZ, Length(FBrushes), FGeneratedTriangleCount]);
end;

initialization
  RegisterSerializableComponent(TCastleVoxelVolume,
    ['World & Terrain', '3D Voxel SDF Cave & Overhang Volume']);
end.
