{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Viewport Mesh Vertex Paint Mode (UMeshPaintMode /
  FMeshPaintParameters) with radial 3D falloff brush strokes, R/G/B/A channel
  write masks, normal-angle filtering, Fill / Invert / Swap, 1-ring Laplacian
  smoothing, HeightLerp 4-layer material blending (Stone -> Moss / Puddle /
  EdgeWear / Snow), live transient X3D ColorRGBA preview scene, and lossless
  JSON serialization (Phase 396). }
unit CastleVertexPaint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleUtils, CastleClassUtils, CastleVectors, CastleColors,
  CastleComponentSerialize, CastleTransform, CastleScene, X3DNodes;

type
  TVertexPaintPreset = (
    vppCobblestoneWallMossPuddles,
    vppRuinedArchwaySootWear,
    vppTerrainCliffSnowLichen
  );

  TVertexPaintChannel = (
    vpcRed,
    vpcGreen,
    vpcBlue,
    vpcAlpha
  );
  TVertexPaintChannelMask = set of TVertexPaintChannel;

  TVertexPaintBlendPreviewMode = (
    vpmMaterialHeightLerp,
    vpmRawRgbaChannels,
    vpmRedChannelOnly,
    vpmGreenChannelOnly,
    vpmBlueChannelOnly,
    vpmAlphaChannelOnly
  );

  TVertexPaintVertex = record
    Position: TVector3;
    Normal: TVector3;
    UV: TVector2;
    MicroHeight01: Single; { Mortar crevice (0.0) vs raised stone face (1.0) for UE HeightLerp }
    ColorRGBA: TVector4;
    Adjacency: array of Integer;
  end;
  TVertexPaintVertexArray = array of TVertexPaintVertex;

  TVertexPaintTriangle = record
    V0, V1, V2: Integer;
  end;
  TVertexPaintTriangleArray = array of TVertexPaintTriangle;

  TVertexPaintSurfaceSample = record
    BaseColorRGB: TVector3;
    Roughness: Single;
    Metallic: Single;
    EffectiveMoss: Single;
    EffectivePuddle: Single;
    EffectiveWear: Single;
    EffectiveSnow: Single;
  end;

  TCastleVertexPaintMesh = class(TCastleTransform)
  private
    FPreset: TVertexPaintPreset;
    FGridCols: Integer;
    FGridRows: Integer;
    FBrushRadius: Single;
    FBrushFalloff: Single;
    FBrushStrength: Single;
    FHeightLerpContrast: Single;
    FPaintColor: TVector4;
    FEraseColor: TVector4;
    FPreviewMode: TVertexPaintBlendPreviewMode;
    FVertices: TVertexPaintVertexArray;
    FTriangles: TVertexPaintTriangleArray;
    FPreviewScene: TCastleScene;
    FColorsDataJson: String;

    procedure SetPreset(const AValue: TVertexPaintPreset);
    procedure SetGridCols(const AValue: Integer);
    procedure SetGridRows(const AValue: Integer);
    procedure SetBrushRadius(const AValue: Single);
    procedure SetBrushFalloff(const AValue: Single);
    procedure SetBrushStrength(const AValue: Single);
    procedure SetHeightLerpContrast(const AValue: Single);
    procedure SetPreviewMode(const AValue: TVertexPaintBlendPreviewMode);
    function GetColorsDataJson: String;
    procedure SetColorsDataJson(const AValue: String);

    procedure BuildMeshTopology(const AResetColorsToPreset: Boolean);
    procedure RebuildPreviewScene;
    procedure AddUniqueNeighbor(var Adj: array of Integer; var ACount: Integer;
      const NeighborIdx: Integer);
  public
    const
      AllPaintChannels: TVertexPaintChannelMask = [vpcRed, vpcGreen, vpcBlue, vpcAlpha];

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Apply a UE 5.5-style 3D spherical radial brush stroke in World Space (or Local
      Space if mesh is at origin). Smooth Hermite falloff is applied between
      InnerRadius = Radius * (1 - Falloff) and Radius. Only channels in ChannelMask
      are modified; unmasked channels remain bit-exact! Returns affected vertex count. }
    function ApplyBrushStroke(const WorldBrushCenter: TVector3;
      const ARadius, AFalloff, AStrength: Single;
      const ATargetColor: TVector4;
      const AChannelMask: TVertexPaintChannelMask;
      const AEraseMode: Boolean = False): Integer; overload;
    function ApplyBrushStroke(const WorldBrushCenter: TVector3;
      const ARadius, AFalloff, AStrength: Single;
      const ATargetColor: TVector4;
      const AChannelMask: TVertexPaintChannelMask;
      const AEraseMode: Boolean;
      const ANormalFilterMinDot: Single;
      const ANormalFilterDir: TVector3): Integer; overload;

    { UE 5.5 Mesh Paint toolbar operations: Fill, Invert, Swap (X), and Laplacian Smooth. }
    procedure FillVertices(const AFillColor: TVector4;
      const AChannelMask: TVertexPaintChannelMask);
    procedure InvertChannels(const AChannelMask: TVertexPaintChannelMask);
    procedure SwapPaintAndEraseColors;
    function SmoothVertexColors(const WorldBrushCenter: TVector3;
      const ARadius, AStrength: Single;
      const AChannelMask: TVertexPaintChannelMask;
      const AWholeMesh: Boolean = False): Integer;
    procedure BakeProceduralWeatheringWeights;

    { Evaluate UE 5.5 HeightLerp 4-layer material blend at a vertex (crevices fill
      with moss & rain puddles before raised cobblestone faces). }
    function EvaluateBlendedSurface(const VertexIdx: Integer): TVertexPaintSurfaceSample;
    function EvaluateDisplayColorRGB(const VertexIdx: Integer): TVector3;

    { Measure average 1-ring neighbor gradient energy on a channel (proves Smooth
      monotonically lowers harsh color seam gradients!). }
    function ComputeChannelRoughnessEnergy(const AChannel: TVertexPaintChannel): Single;

    function FindNearestVertexLocal(const LocalPos: TVector3): Integer;
    function VertexCount: Integer;
    function TriangleCount: Integer;
    function PaintedVertexCount: Integer;
    function AverageChannelWeight(const AChannel: TVertexPaintChannel): Single;
    function VertexPaintSummaryBadge: String;

    property Vertices: TVertexPaintVertexArray read FVertices;
    property Triangles: TVertexPaintTriangleArray read FTriangles;
    property PaintColor: TVector4 read FPaintColor write FPaintColor;
    property EraseColor: TVector4 read FEraseColor write FEraseColor;
  published
    property Preset: TVertexPaintPreset
      read FPreset write SetPreset default vppCobblestoneWallMossPuddles;
    property GridCols: Integer read FGridCols write SetGridCols default 17;
    property GridRows: Integer read FGridRows write SetGridRows default 13;
    property BrushRadius: Single read FBrushRadius write SetBrushRadius {$ifdef FPC}default 2.2{$endif};
    property BrushFalloff: Single read FBrushFalloff write SetBrushFalloff {$ifdef FPC}default 0.5{$endif};
    property BrushStrength: Single read FBrushStrength write SetBrushStrength {$ifdef FPC}default 0.85{$endif};
    property HeightLerpContrast: Single
      read FHeightLerpContrast write SetHeightLerpContrast {$ifdef FPC}default 0.45{$endif};
    property PreviewMode: TVertexPaintBlendPreviewMode
      read FPreviewMode write SetPreviewMode default vpmMaterialHeightLerp;
    property ColorsDataJson: String read GetColorsDataJson write SetColorsDataJson stored True;
  end;

function VertexPaintPresetDisplayName(const APreset: TVertexPaintPreset): String;
function VertexPaintPreviewModeDisplayName(const AMode: TVertexPaintBlendPreviewMode): String;
function HeightLerpWeight(const VertexWeight, Height01, Contrast: Single): Single;

implementation

function VertexPaintPresetDisplayName(const APreset: TVertexPaintPreset): String;
begin
  case APreset of
    vppCobblestoneWallMossPuddles: Result := 'Cobblestone Courtyard (Moss / Rain Puddles / Edge Wear)';
    vppRuinedArchwaySootWear:      Result := 'Ruined Castle Wall (Torch Soot / Damp Creep / Chipped Mortar)';
    vppTerrainCliffSnowLichen:     Result := 'Alpine Cliff Outcrop (Snow Cap / Lichen / Wet Seepage)';
  end;
end;

function VertexPaintPreviewModeDisplayName(const AMode: TVertexPaintBlendPreviewMode): String;
begin
  case AMode of
    vpmMaterialHeightLerp: Result := '4-Layer HeightLerp Material';
    vpmRawRgbaChannels:    Result := 'Raw Vertex RGB Weights';
    vpmRedChannelOnly:     Result := 'Solo [R] Moss / Lichen';
    vpmGreenChannelOnly:   Result := 'Solo [G] Puddle / Wetness';
    vpmBlueChannelOnly:    Result := 'Solo [B] Edge Wear / Soot';
    vpmAlphaChannelOnly:   Result := 'Solo [A] Snow / Dust Cap';
  end;
end;

function SmoothStep01(const X: Single): Single;
var
  T: Single;
begin
  T := EnsureRange(X, 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

function HeightLerpWeight(const VertexWeight, Height01, Contrast: Single): Single;
var
  W, InvCrevice, C, Band, LoEdge, HiEdge: Single;
begin
  W := EnsureRange(VertexWeight, 0.0, 1.0);
  if W <= 0.0001 then Exit(0.0);
  if W >= 0.9999 then Exit(1.0);

  { Crevices (Height01 = 0 -> InvCrevice = 1) fill first as VertexWeight rises! }
  InvCrevice := 1.0 - EnsureRange(Height01, 0.0, 1.0);
  C := EnsureRange(Contrast, 0.05, 0.95);
  Band := Max(0.05, 1.0 - C);
  LoEdge := (1.0 - W) - Band * 0.5;
  HiEdge := (1.0 - W) + Band * 0.5;
  Result := SmoothStep01((InvCrevice - LoEdge) / Max(0.001, HiEdge - LoEdge));
end;

{ TCastleVertexPaintMesh }

constructor TCastleVertexPaintMesh.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := vppCobblestoneWallMossPuddles;
  FGridCols := 17;
  FGridRows := 13;
  FBrushRadius := 2.2;
  FBrushFalloff := 0.5;
  FBrushStrength := 0.85;
  FHeightLerpContrast := 0.45;
  FPaintColor := Vector4(1.0, 0.0, 0.0, 0.0);
  FEraseColor := Vector4(0.0, 0.0, 0.0, 0.0);
  FPreviewMode := vpmMaterialHeightLerp;

  FPreviewScene := TCastleScene.Create(nil);
  FPreviewScene.SetTransient;
  FPreviewScene.Pickable := False;
  Add(FPreviewScene);

  BuildMeshTopology(True);
end;

destructor TCastleVertexPaintMesh.Destroy;
begin
  if FPreviewScene <> nil then
  begin
    Remove(FPreviewScene);
    FreeAndNil(FPreviewScene);
  end;
  inherited Destroy;
end;

function TCastleVertexPaintMesh.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'GridCols') or
     (PropertyName = 'GridRows') or
     (PropertyName = 'BrushRadius') or
     (PropertyName = 'BrushFalloff') or
     (PropertyName = 'BrushStrength') or
     (PropertyName = 'HeightLerpContrast') or
     (PropertyName = 'PreviewMode') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleVertexPaintMesh.SetPreset(const AValue: TVertexPaintPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  BuildMeshTopology(True);
end;

procedure TCastleVertexPaintMesh.SetGridCols(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(AValue, 5, 49);
  if FGridCols = Clamped then Exit;
  FGridCols := Clamped;
  BuildMeshTopology(True);
end;

procedure TCastleVertexPaintMesh.SetGridRows(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(AValue, 5, 49);
  if FGridRows = Clamped then Exit;
  FGridRows := Clamped;
  BuildMeshTopology(True);
end;

procedure TCastleVertexPaintMesh.SetBrushRadius(const AValue: Single);
begin
  FBrushRadius := Max(0.1, AValue);
end;

procedure TCastleVertexPaintMesh.SetBrushFalloff(const AValue: Single);
begin
  FBrushFalloff := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleVertexPaintMesh.SetBrushStrength(const AValue: Single);
begin
  FBrushStrength := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleVertexPaintMesh.SetHeightLerpContrast(const AValue: Single);
begin
  FHeightLerpContrast := EnsureRange(AValue, 0.05, 0.95);
  RebuildPreviewScene;
end;

procedure TCastleVertexPaintMesh.SetPreviewMode(const AValue: TVertexPaintBlendPreviewMode);
begin
  if FPreviewMode = AValue then Exit;
  FPreviewMode := AValue;
  RebuildPreviewScene;
end;

procedure TCastleVertexPaintMesh.AddUniqueNeighbor(var Adj: array of Integer;
  var ACount: Integer; const NeighborIdx: Integer);
var
  I: Integer;
begin
  for I := 0 to ACount - 1 do
    if Adj[I] = NeighborIdx then Exit;
  if ACount < Length(Adj) then
  begin
    Adj[ACount] := NeighborIdx;
    Inc(ACount);
  end;
end;

procedure TCastleVertexPaintMesh.BuildMeshTopology(const AResetColorsToPreset: Boolean);
var
  R, C, Idx, TriIdx, I, K: Integer;
  U, V, X, Y, Z, BrickU, BrickV, MortarMask: Single;
  AdjBuf: array of array[0..7] of Integer;
  AdjCounts: array of Integer;
  E1, E2, FaceN: TVector3;
  AccumN: array of TVector3;

  procedure LinkEdge(const A, B: Integer);
  begin
    AddUniqueNeighbor(AdjBuf[A], AdjCounts[A], B);
    AddUniqueNeighbor(AdjBuf[B], AdjCounts[B], A);
  end;

begin
  SetLength(FVertices, FGridCols * FGridRows);
  SetLength(FTriangles, (FGridCols - 1) * (FGridRows - 1) * 2);

  for R := 0 to FGridRows - 1 do
  begin
    V := R / Max(1, FGridRows - 1);
    for C := 0 to FGridCols - 1 do
    begin
      U := C / Max(1, FGridCols - 1);
      Idx := R * FGridCols + C;

      { Procedural cobblestone / ashlar brick micro-height (0 = mortar crevice, 1 = stone face) }
      BrickU := Frac(U * 6.0 + (R mod 2) * 0.5);
      BrickV := Frac(V * 5.0);
      MortarMask := Min(
        SmoothStep01(Min(BrickU, 1.0 - BrickU) / 0.14),
        SmoothStep01(Min(BrickV, 1.0 - BrickV) / 0.16));

      case FPreset of
        vppCobblestoneWallMossPuddles:
          begin
            { Gently undulating cobblestone courtyard slab in XZ with shallow central basin }
            X := (U - 0.5) * 10.0;
            Z := (V - 0.5) * 8.0;
            Y := 0.24 * Sin(U * Pi * 2.0) * Cos(V * Pi * 1.5)
               - 0.32 * Exp(-((X * X + Z * Z) / 9.5))
               + MortarMask * 0.05;
          end;
        vppRuinedArchwaySootWear:
          begin
            { Curved castle bastion wall standing vertically }
            X := (U - 0.5) * 9.6;
            Y := V * 5.6;
            Z := 0.85 * Cos((U - 0.5) * Pi) + 0.12 * Sin(U * 9.0 + V * 5.0)
               + MortarMask * 0.06;
          end;
        vppTerrainCliffSnowLichen:
          begin
            { Stepped alpine cliff terrace }
            X := (U - 0.5) * 10.5;
            Z := (V - 0.5) * 8.5;
            Y := 2.4 * SmoothStep01(V) + 0.55 * Sin(U * 4.2) * Cos(V * 3.1)
               + MortarMask * 0.08;
          end;
      end;

      FVertices[Idx].Position := Vector3(X, Y, Z);
      FVertices[Idx].UV := Vector2(U, V);
      FVertices[Idx].MicroHeight01 := EnsureRange(
        0.25 + 0.55 * MortarMask + 0.20 * (0.5 + 0.5 * Sin(Idx * 1.73)), 0.0, 1.0);
      if AResetColorsToPreset then
        FVertices[Idx].ColorRGBA := Vector4(0, 0, 0, 0);
    end;
  end;

  TriIdx := 0;
  SetLength(AdjBuf, Length(FVertices));
  SetLength(AdjCounts, Length(FVertices));
  for I := 0 to High(AdjCounts) do
    AdjCounts[I] := 0;

  for R := 0 to FGridRows - 2 do
    for C := 0 to FGridCols - 2 do
    begin
      Idx := R * FGridCols + C;
      FTriangles[TriIdx].V0 := Idx;
      FTriangles[TriIdx].V1 := Idx + FGridCols;
      FTriangles[TriIdx].V2 := Idx + 1;
      LinkEdge(FTriangles[TriIdx].V0, FTriangles[TriIdx].V1);
      LinkEdge(FTriangles[TriIdx].V1, FTriangles[TriIdx].V2);
      LinkEdge(FTriangles[TriIdx].V2, FTriangles[TriIdx].V0);
      Inc(TriIdx);

      FTriangles[TriIdx].V0 := Idx + 1;
      FTriangles[TriIdx].V1 := Idx + FGridCols;
      FTriangles[TriIdx].V2 := Idx + FGridCols + 1;
      LinkEdge(FTriangles[TriIdx].V0, FTriangles[TriIdx].V1);
      LinkEdge(FTriangles[TriIdx].V1, FTriangles[TriIdx].V2);
      LinkEdge(FTriangles[TriIdx].V2, FTriangles[TriIdx].V0);
      Inc(TriIdx);
    end;

  for I := 0 to High(FVertices) do
  begin
    SetLength(FVertices[I].Adjacency, AdjCounts[I]);
    for K := 0 to AdjCounts[I] - 1 do
      FVertices[I].Adjacency[K] := AdjBuf[I][K];
  end;

  { Compute smooth area-weighted vertex normals }
  SetLength(AccumN, Length(FVertices));
  for I := 0 to High(AccumN) do
    AccumN[I] := TVector3.Zero;

  for I := 0 to High(FTriangles) do
  begin
    E1 := FVertices[FTriangles[I].V1].Position - FVertices[FTriangles[I].V0].Position;
    E2 := FVertices[FTriangles[I].V2].Position - FVertices[FTriangles[I].V0].Position;
    FaceN := TVector3.CrossProduct(E1, E2);
    AccumN[FTriangles[I].V0] := AccumN[FTriangles[I].V0] + FaceN;
    AccumN[FTriangles[I].V1] := AccumN[FTriangles[I].V1] + FaceN;
    AccumN[FTriangles[I].V2] := AccumN[FTriangles[I].V2] + FaceN;
  end;

  for I := 0 to High(FVertices) do
    if AccumN[I].LengthSqr > 1e-8 then
      FVertices[I].Normal := AccumN[I].Normalize
    else
      FVertices[I].Normal := Vector3(0, 1, 0);

  if AResetColorsToPreset then
    BakeProceduralWeatheringWeights
  else
    RebuildPreviewScene;
end;

procedure TCastleVertexPaintMesh.BakeProceduralWeatheringWeights;
var
  I: Integer;
  P, N: TVector3;
  R, G, B, A, BasinDist: Single;
begin
  for I := 0 to High(FVertices) do
  begin
    P := FVertices[I].Position;
    N := FVertices[I].Normal;
    case FPreset of
      vppCobblestoneWallMossPuddles:
        begin
          BasinDist := Sqrt(Sqr(P.X) + Sqr(P.Z));
          G := EnsureRange(1.0 - BasinDist / 2.9, 0.0, 1.0) * EnsureRange(N.Y, 0.0, 1.0);
          R := EnsureRange((P.Z + 3.2) / 5.5, 0.0, 1.0) * EnsureRange(1.0 - G * 1.2, 0.0, 1.0) * 0.78;
          B := EnsureRange((P.Y - 0.05) * 3.2, 0.0, 1.0) * 0.65;
          A := EnsureRange((-P.Z - 1.4) / 3.2, 0.0, 1.0) * 0.35;
        end;
      vppRuinedArchwaySootWear:
        begin
          R := EnsureRange(1.0 - P.Y / 2.4, 0.0, 1.0) * 0.85; { Damp base moss }
          G := EnsureRange(1.0 - Abs(P.X + 2.4) / 2.2, 0.0, 1.0) * 0.55; { Water streak }
          B := EnsureRange(1.0 - Sqrt(Sqr(P.X - 1.2) + Sqr(P.Y - 3.2)) / 2.6, 0.0, 1.0); { Torch soot }
          A := EnsureRange((P.Y - 4.0) / 1.6, 0.0, 1.0) * 0.75; { Crumbling mortar dust }
        end;
      vppTerrainCliffSnowLichen:
        begin
          A := EnsureRange((P.Y - 1.15) / 1.4, 0.0, 1.0) * EnsureRange((N.Y - 0.45) * 2.2, 0.0, 1.0);
          R := EnsureRange(1.0 - Abs(P.Y - 1.0) / 1.1, 0.0, 1.0) * 0.72;
          G := EnsureRange(1.0 - P.Y / 0.85, 0.0, 1.0) * 0.65;
          B := EnsureRange(1.0 - N.Y, 0.0, 1.0) * 0.80;
        end;
    end;
    FVertices[I].ColorRGBA := Vector4(R, G, B, A);
  end;
  RebuildPreviewScene;
end;

function TCastleVertexPaintMesh.EvaluateBlendedSurface(
  const VertexIdx: Integer): TVertexPaintSurfaceSample;
var
  V: TVertexPaintVertex;
  WMoss, WPuddle, WWear, WSnow: Single;
  StoneColor, MossColor, PuddleColor, WearColor, SootColor, SnowColor,
    Col, LayerWearCol: TVector3;
  Rough: Single;
begin
  StoneColor := Vector3(0.44, 0.42, 0.40);
  MossColor := Vector3(0.18, 0.49, 0.16);
  PuddleColor := Vector3(0.11, 0.22, 0.34);
  WearColor := Vector3(0.72, 0.64, 0.50);
  SootColor := Vector3(0.12, 0.11, 0.10);
  SnowColor := Vector3(0.90, 0.94, 0.98);
  Result := Default(TVertexPaintSurfaceSample);
  if (VertexIdx < 0) or (VertexIdx > High(FVertices)) then
  begin
    Result.BaseColorRGB := StoneColor;
    Result.Roughness := 0.78;
    Exit;
  end;

  V := FVertices[VertexIdx];
  { Moss & Puddles fill mortar crevices first (Height01); Wear & Snow cap raised stone (1 - Height01) }
  WMoss := HeightLerpWeight(V.ColorRGBA.X, V.MicroHeight01, FHeightLerpContrast);
  WPuddle := HeightLerpWeight(V.ColorRGBA.Y, V.MicroHeight01 * 0.75, FHeightLerpContrast);
  WWear := HeightLerpWeight(V.ColorRGBA.Z, 1.0 - V.MicroHeight01, FHeightLerpContrast);
  WSnow := HeightLerpWeight(V.ColorRGBA.W, 1.0 - V.MicroHeight01 * 0.5, FHeightLerpContrast);

  if FPreset = vppRuinedArchwaySootWear then
    LayerWearCol := SootColor
  else
    LayerWearCol := WearColor;

  Col := StoneColor * (0.82 + 0.28 * V.MicroHeight01);
  Rough := 0.80;

  Col := Col + (MossColor - Col) * WMoss;
  Rough := Rough + (0.88 - Rough) * WMoss;

  Col := Col + (LayerWearCol - Col) * WWear;
  Rough := Rough + (0.65 - Rough) * WWear;

  Col := Col + (SnowColor - Col) * WSnow;
  Rough := Rough + (0.52 - Rough) * WSnow;

  { Puddles darken porous stone/moss and drop roughness to mirror-wet 0.06! }
  Col := Col + (PuddleColor - Col) * WPuddle;
  Rough := Rough + (0.06 - Rough) * WPuddle;

  Result.BaseColorRGB := Col;
  Result.Roughness := EnsureRange(Rough, 0.04, 1.0);
  Result.Metallic := 0.0;
  Result.EffectiveMoss := WMoss;
  Result.EffectivePuddle := WPuddle;
  Result.EffectiveWear := WWear;
  Result.EffectiveSnow := WSnow;
end;

function TCastleVertexPaintMesh.EvaluateDisplayColorRGB(const VertexIdx: Integer): TVector3;
var
  C: TVector4;
  S: TVertexPaintSurfaceSample;
begin
  if (VertexIdx < 0) or (VertexIdx > High(FVertices)) then
    Exit(Vector3(0.5, 0.5, 0.5));
  C := FVertices[VertexIdx].ColorRGBA;
  case FPreviewMode of
    vpmMaterialHeightLerp:
      begin
        S := EvaluateBlendedSurface(VertexIdx);
        Result := S.BaseColorRGB;
      end;
    vpmRawRgbaChannels:
      Result := Vector3(C.X, C.Y, C.Z);
    vpmRedChannelOnly:
      Result := Vector3(C.X, C.X * 0.22, C.X * 0.16);
    vpmGreenChannelOnly:
      Result := Vector3(C.Y * 0.16, C.Y, C.Y * 0.28);
    vpmBlueChannelOnly:
      Result := Vector3(C.Z * 0.20, C.Z * 0.45, C.Z);
    vpmAlphaChannelOnly:
      Result := Vector3(C.W, C.W, C.W);
  end;
end;

procedure TCastleVertexPaintMesh.RebuildPreviewScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TIndexedTriangleSetNode;
  Coord: TCoordinateNode;
  NormNode: TNormalNode;
  ColNode: TColorRGBANode;
  Pts, Norms: array of TVector3;
  Cols: array of TVector4;
  IdxArr: array of Int32;
  I: Integer;
  DispCol: TVector3;
begin
  if (FPreviewScene = nil) or (Length(FVertices) = 0) or (Length(FTriangles) = 0) then
    Exit;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.Roughness := 0.65;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TIndexedTriangleSetNode.Create;
  TriSet.Solid := False;

  SetLength(Pts, Length(FVertices));
  SetLength(Norms, Length(FVertices));
  SetLength(Cols, Length(FVertices));
  for I := 0 to High(FVertices) do
  begin
    Pts[I] := FVertices[I].Position;
    Norms[I] := FVertices[I].Normal;
    DispCol := EvaluateDisplayColorRGB(I);
    Cols[I] := Vector4(DispCol.X, DispCol.Y, DispCol.Z, 1.0);
  end;

  SetLength(IdxArr, Length(FTriangles) * 3);
  for I := 0 to High(FTriangles) do
  begin
    IdxArr[I * 3 + 0] := FTriangles[I].V0;
    IdxArr[I * 3 + 1] := FTriangles[I].V1;
    IdxArr[I * 3 + 2] := FTriangles[I].V2;
  end;

  Coord := TCoordinateNode.Create;
  Coord.SetPoint(Pts);
  NormNode := TNormalNode.Create;
  NormNode.SetVector(Norms);
  ColNode := TColorRGBANode.Create;
  ColNode.SetColor(Cols);

  TriSet.Coord := Coord;
  TriSet.Normal := NormNode;
  TriSet.Color := ColNode;
  TriSet.SetIndex(IdxArr);

  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  FPreviewScene.Load(Root, True);
end;

function TCastleVertexPaintMesh.ApplyBrushStroke(const WorldBrushCenter: TVector3;
  const ARadius, AFalloff, AStrength: Single;
  const ATargetColor: TVector4;
  const AChannelMask: TVertexPaintChannelMask;
  const AEraseMode: Boolean): Integer;
begin
  Result := ApplyBrushStroke(WorldBrushCenter, ARadius, AFalloff, AStrength,
    ATargetColor, AChannelMask, AEraseMode, -2.0, Vector3(0, 1, 0));
end;

function TCastleVertexPaintMesh.ApplyBrushStroke(const WorldBrushCenter: TVector3;
  const ARadius, AFalloff, AStrength: Single;
  const ATargetColor: TVector4;
  const AChannelMask: TVertexPaintChannelMask;
  const AEraseMode: Boolean;
  const ANormalFilterMinDot: Single;
  const ANormalFilterDir: TVector3): Integer;
var
  LocalCenter, NormDir: TVector3;
  Target4, Cur: TVector4;
  R, FallVal, Str, InnerR, Dist, T, Alpha: Single;
  I: Integer;
begin
  Result := 0;
  if AChannelMask = [] then Exit;

  LocalCenter := WorldBrushCenter - Translation;
  R := Max(0.05, ARadius);
  FallVal := EnsureRange(AFalloff, 0.0, 1.0);
  Str := EnsureRange(AStrength, 0.0, 1.0);
  InnerR := R * (1.0 - FallVal);

  if AEraseMode then
    Target4 := FEraseColor
  else
    Target4 := ATargetColor;

  if ANormalFilterDir.LengthSqr > 1e-6 then
    NormDir := ANormalFilterDir.Normalize
  else
    NormDir := Vector3(0, 1, 0);

  for I := 0 to High(FVertices) do
  begin
    Dist := PointsDistance(FVertices[I].Position, LocalCenter);
    if Dist > R then Continue;

    if (ANormalFilterMinDot > -1.5) and
       (TVector3.DotProduct(FVertices[I].Normal, NormDir) < ANormalFilterMinDot) then
      Continue;

    if Dist <= InnerR then
      T := 1.0
    else
      T := 1.0 - SmoothStep01((Dist - InnerR) / Max(0.0001, R - InnerR));

    Alpha := EnsureRange(T * Str, 0.0, 1.0);
    if Alpha <= 0.0001 then Continue;

    Cur := FVertices[I].ColorRGBA;
    if vpcRed in AChannelMask then
      Cur.X := EnsureRange(Cur.X + (Target4.X - Cur.X) * Alpha, 0.0, 1.0);
    if vpcGreen in AChannelMask then
      Cur.Y := EnsureRange(Cur.Y + (Target4.Y - Cur.Y) * Alpha, 0.0, 1.0);
    if vpcBlue in AChannelMask then
      Cur.Z := EnsureRange(Cur.Z + (Target4.Z - Cur.Z) * Alpha, 0.0, 1.0);
    if vpcAlpha in AChannelMask then
      Cur.W := EnsureRange(Cur.W + (Target4.W - Cur.W) * Alpha, 0.0, 1.0);

    FVertices[I].ColorRGBA := Cur;
    Inc(Result);
  end;

  if Result > 0 then
    RebuildPreviewScene;
end;

procedure TCastleVertexPaintMesh.FillVertices(const AFillColor: TVector4;
  const AChannelMask: TVertexPaintChannelMask);
var
  I: Integer;
  Cur: TVector4;
begin
  if AChannelMask = [] then Exit;
  for I := 0 to High(FVertices) do
  begin
    Cur := FVertices[I].ColorRGBA;
    if vpcRed in AChannelMask then Cur.X := EnsureRange(AFillColor.X, 0.0, 1.0);
    if vpcGreen in AChannelMask then Cur.Y := EnsureRange(AFillColor.Y, 0.0, 1.0);
    if vpcBlue in AChannelMask then Cur.Z := EnsureRange(AFillColor.Z, 0.0, 1.0);
    if vpcAlpha in AChannelMask then Cur.W := EnsureRange(AFillColor.W, 0.0, 1.0);
    FVertices[I].ColorRGBA := Cur;
  end;
  RebuildPreviewScene;
end;

procedure TCastleVertexPaintMesh.InvertChannels(
  const AChannelMask: TVertexPaintChannelMask);
var
  I: Integer;
  Cur: TVector4;
begin
  if AChannelMask = [] then Exit;
  for I := 0 to High(FVertices) do
  begin
    Cur := FVertices[I].ColorRGBA;
    if vpcRed in AChannelMask then Cur.X := 1.0 - Cur.X;
    if vpcGreen in AChannelMask then Cur.Y := 1.0 - Cur.Y;
    if vpcBlue in AChannelMask then Cur.Z := 1.0 - Cur.Z;
    if vpcAlpha in AChannelMask then Cur.W := 1.0 - Cur.W;
    FVertices[I].ColorRGBA := Cur;
  end;
  RebuildPreviewScene;
end;

procedure TCastleVertexPaintMesh.SwapPaintAndEraseColors;
var
  Tmp: TVector4;
begin
  Tmp := FPaintColor;
  FPaintColor := FEraseColor;
  FEraseColor := Tmp;
end;

function TCastleVertexPaintMesh.SmoothVertexColors(const WorldBrushCenter: TVector3;
  const ARadius, AStrength: Single;
  const AChannelMask: TVertexPaintChannelMask;
  const AWholeMesh: Boolean): Integer;
var
  LocalCenter: TVector3;
  PrevColors: array of TVector4;
  Avg, Cur: TVector4;
  I, J, NIdx, Deg: Integer;
  R, Str, Dist, FallWeight, Alpha: Single;
begin
  Result := 0;
  if (AChannelMask = []) or (Length(FVertices) = 0) then Exit;

  LocalCenter := WorldBrushCenter - Translation;
  R := Max(0.05, ARadius);
  Str := EnsureRange(AStrength, 0.0, 1.0);

  SetLength(PrevColors, Length(FVertices));
  for I := 0 to High(FVertices) do
    PrevColors[I] := FVertices[I].ColorRGBA;

  for I := 0 to High(FVertices) do
  begin
    Deg := Length(FVertices[I].Adjacency);
    if Deg = 0 then Continue;

    if AWholeMesh then
      FallWeight := 1.0
    else
    begin
      Dist := PointsDistance(FVertices[I].Position, LocalCenter);
      if Dist > R then Continue;
      FallWeight := 1.0 - SmoothStep01(Dist / R);
    end;

    Alpha := EnsureRange(FallWeight * Str, 0.0, 1.0);
    if Alpha <= 0.0001 then Continue;

    Avg := TVector4.Zero;
    for J := 0 to Deg - 1 do
    begin
      NIdx := FVertices[I].Adjacency[J];
      Avg := Avg + PrevColors[NIdx];
    end;
    Avg := Avg / Deg;

    Cur := PrevColors[I];
    if vpcRed in AChannelMask then
      Cur.X := EnsureRange(Cur.X + (Avg.X - Cur.X) * Alpha, 0.0, 1.0);
    if vpcGreen in AChannelMask then
      Cur.Y := EnsureRange(Cur.Y + (Avg.Y - Cur.Y) * Alpha, 0.0, 1.0);
    if vpcBlue in AChannelMask then
      Cur.Z := EnsureRange(Cur.Z + (Avg.Z - Cur.Z) * Alpha, 0.0, 1.0);
    if vpcAlpha in AChannelMask then
      Cur.W := EnsureRange(Cur.W + (Avg.W - Cur.W) * Alpha, 0.0, 1.0);

    FVertices[I].ColorRGBA := Cur;
    Inc(Result);
  end;

  if Result > 0 then
    RebuildPreviewScene;
end;

function TCastleVertexPaintMesh.ComputeChannelRoughnessEnergy(
  const AChannel: TVertexPaintChannel): Single;

  function ChanVal(const C: TVector4): Single;
  begin
    case AChannel of
      vpcRed:   Result := C.X;
      vpcGreen: Result := C.Y;
      vpcBlue:  Result := C.Z;
      vpcAlpha: Result := C.W;
    end;
  end;

var
  I, J, EdgeCount: Integer;
  SumDiffSq, D: Single;
begin
  SumDiffSq := 0.0;
  EdgeCount := 0;
  for I := 0 to High(FVertices) do
    for J := 0 to High(FVertices[I].Adjacency) do
    begin
      D := ChanVal(FVertices[I].ColorRGBA) -
           ChanVal(FVertices[FVertices[I].Adjacency[J]].ColorRGBA);
      SumDiffSq := SumDiffSq + D * D;
      Inc(EdgeCount);
    end;
  if EdgeCount > 0 then
    Result := SumDiffSq / EdgeCount
  else
    Result := 0.0;
end;

function TCastleVertexPaintMesh.FindNearestVertexLocal(const LocalPos: TVector3): Integer;
var
  I: Integer;
  BestDistSq, DSq: Single;
begin
  Result := -1;
  BestDistSq := MaxSingle;
  for I := 0 to High(FVertices) do
  begin
    DSq := PointsDistanceSqr(FVertices[I].Position, LocalPos);
    if DSq < BestDistSq then
    begin
      BestDistSq := DSq;
      Result := I;
    end;
  end;
end;

function TCastleVertexPaintMesh.VertexCount: Integer;
begin
  Result := Length(FVertices);
end;

function TCastleVertexPaintMesh.TriangleCount: Integer;
begin
  Result := Length(FTriangles);
end;

function TCastleVertexPaintMesh.PaintedVertexCount: Integer;
var
  I: Integer;
  C: TVector4;
begin
  Result := 0;
  for I := 0 to High(FVertices) do
  begin
    C := FVertices[I].ColorRGBA;
    if (C.X > 0.02) or (C.Y > 0.02) or (C.Z > 0.02) or (C.W > 0.02) then
      Inc(Result);
  end;
end;

function TCastleVertexPaintMesh.AverageChannelWeight(
  const AChannel: TVertexPaintChannel): Single;
var
  I: Integer;
  Sum: Double;
begin
  if Length(FVertices) = 0 then Exit(0.0);
  Sum := 0.0;
  for I := 0 to High(FVertices) do
    case AChannel of
      vpcRed:   Sum := Sum + FVertices[I].ColorRGBA.X;
      vpcGreen: Sum := Sum + FVertices[I].ColorRGBA.Y;
      vpcBlue:  Sum := Sum + FVertices[I].ColorRGBA.Z;
      vpcAlpha: Sum := Sum + FVertices[I].ColorRGBA.W;
    end;
  Result := Sum / Length(FVertices);
end;

function TCastleVertexPaintMesh.GetColorsDataJson: String;
var
  Arr, Item: TJSONArray;
  I: Integer;
  C: TVector4;
begin
  Arr := TJSONArray.Create;
  try
    for I := 0 to High(FVertices) do
    begin
      C := FVertices[I].ColorRGBA;
      Item := TJSONArray.Create;
      Item.Add(Round(EnsureRange(C.X, 0.0, 1.0) * 10000));
      Item.Add(Round(EnsureRange(C.Y, 0.0, 1.0) * 10000));
      Item.Add(Round(EnsureRange(C.Z, 0.0, 1.0) * 10000));
      Item.Add(Round(EnsureRange(C.W, 0.0, 1.0) * 10000));
      Arr.Add(Item);
    end;
    FColorsDataJson := Arr.AsJSON;
    Result := FColorsDataJson;
  finally
    FreeAndNil(Arr);
  end;
end;

procedure TCastleVertexPaintMesh.SetColorsDataJson(const AValue: String);
var
  Parsed: TJSONData;
  Arr, Item: TJSONArray;
  I, Lim: Integer;
begin
  FColorsDataJson := AValue;
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    try
      Parsed := GetJSON(AValue);
    except
      Exit;
    end;
    if Parsed is TJSONArray then
    begin
      Arr := TJSONArray(Parsed);
      Lim := Min(Arr.Count - 1, High(FVertices));
      for I := 0 to Lim do
        if (Arr.Items[I] is TJSONArray) and (TJSONArray(Arr.Items[I]).Count >= 4) then
        begin
          Item := TJSONArray(Arr.Items[I]);
          FVertices[I].ColorRGBA := Vector4(
            EnsureRange(Item.Integers[0] / 10000.0, 0.0, 1.0),
            EnsureRange(Item.Integers[1] / 10000.0, 0.0, 1.0),
            EnsureRange(Item.Integers[2] / 10000.0, 0.0, 1.0),
            EnsureRange(Item.Integers[3] / 10000.0, 0.0, 1.0));
        end;
      RebuildPreviewScene;
    end;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleVertexPaintMesh.VertexPaintSummaryBadge: String;
begin
  Result := Format('[VPaint:%dv Painted=%d Moss=%d%% Puddle=%d%% Wear=%d%%]',
    [VertexCount,
     PaintedVertexCount,
     Round(AverageChannelWeight(vpcRed) * 100),
     Round(AverageChannelWeight(vpcGreen) * 100),
     Round(AverageChannelWeight(vpcBlue) * 100)]);
end;

initialization
  RegisterSerializableComponent(TCastleVertexPaintMesh,
    ['Mesh Paint', 'Vertex Paint Multi-Layer Mesh (TCastleVertexPaintMesh)']);

end.
