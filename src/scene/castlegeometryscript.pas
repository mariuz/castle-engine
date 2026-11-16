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

{ Geometry Script Non-Destructive Procedural Mesh Operator Stack (Revolve
  Lathe, Box Grid, UV Sphere, 4x Linear Subdivide, Twist, Taper, 3D Noise
  Displacement & Solidify Shell) and Parametric 3D Turtle L-System Botanical
  Tree / Vine Generator
  (@link(TCastleGeometryScriptMesh), @link(TCastleLSystemBotanical),
  @link(ExpandLSystemString))
  (Phase 325 — UE 6.0+ Geometry Script & PCG Vegetation Parity). }
unit CastleGeometryScript;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleScene, X3DNodes;

type
  { Base parametric mesh generator feeding the Geometry Script stack. }
  TGeoBaseShape = (
    gbsRevolveAmphora,
    gbsSubdividedBox,
    gbsUvSphere
  );

  { Built-in Geometry Script stack presets. }
  TGeoScriptPreset = (
    gspCustom,
    gspTwistedThickAmphora,
    gspDisplacedAsteroidBoulder,
    gspTaperedObeliskColumn
  );

  { Non-destructive mesh modifier operator kind. }
  TGeoModifierKind = (
    gmkLinearSubdivide4x,
    gmkTwistAroundY,
    gmkTaperAlongY,
    gmkPerlinNormalDisplace,
    gmkSolidifyShell
  );

  { Single modifier stage in a @link(TCastleGeometryScriptMesh) pipeline. }
  TGeoModifierStage = record
    Enabled: Boolean;
    Kind: TGeoModifierKind;
    ParamA: Single;
    ParamB: Single;
  end;
  TGeoModifierStageArray = array of TGeoModifierStage;

  { Built-in 3D L-System botanical presets. }
  TLSystemPreset = (
    lspCustom,
    lspBroadleafOakTree,
    lspAlpineConiferPine,
    lspWeepingWillowTree
  );

  { Recorded 3D branch segment for 2D/3D studio preview & bounds analytics. }
  TLSystemBranchSeg = record
    StartPos: TVector3;
    EndPos: TVector3;
    Radius: Single;
  end;
  TLSystemBranchSegArray = array of TLSystemBranchSeg;

  { Non-destructive procedural mesh generator & ordered modifier stack
    compiling into a @code(csTransient) PBR @link(TTriangleSetNode) scene. }
  TCastleGeometryScriptMesh = class(TCastleTransform)
  public
    const
      DefaultRadialSegments = 16;
      DefaultHeightRings = 8;
      DefaultBaseScale = 1.0;
  strict private
    FPreset: TGeoScriptPreset;
    FBaseShape: TGeoBaseShape;
    FRadialSegments: Integer;
    FHeightRings: Integer;
    FBaseScale: Single;
    FModifiers: TGeoModifierStageArray;
    FBaseColor: TCastleColorRGB;
    FBaseColorPersistent: TCastleColorRGBPersistent;

    FMeshScene: TCastleScene;
    FLastVertexCount: Integer;
    FLastTriangleCount: Integer;
    FLastSurfaceArea: Single;
    FPreviewVerts: array of TVector3;

    procedure SetPreset(const Value: TGeoScriptPreset);
    procedure SetBaseShape(const Value: TGeoBaseShape);
    function GetBaseColorForPersistent: TCastleColorRGB;
    procedure SetBaseColorForPersistent(const AValue: TCastleColorRGB);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TGeoScriptPreset): String; static;
    class function ModifierDisplayName(const AKind: TGeoModifierKind): String; static;

    procedure ApplyPreset(const APreset: TGeoScriptPreset);
    procedure ClearModifiers;
    function AddModifier(const AKind: TGeoModifierKind;
      const AParamA: Single = 1.0; const AParamB: Single = 1.0;
      const AEnabled: Boolean = True): Integer;
    procedure SetModifierEnabled(const Index: Integer; const AEnabled: Boolean);
    function ModifierCount: Integer;
    function GetModifier(const Index: Integer): TGeoModifierStage;

    procedure RebuildProceduralMesh;

    function PreviewVertexCount: Integer;
    function GetPreviewVertex(const Index: Integer): TVector3;
    function GeoSummaryBadge: String;

    property BaseColor: TCastleColorRGB read FBaseColor write FBaseColor;
    property VertexCount: Integer read FLastVertexCount;
    property TriangleCount: Integer read FLastTriangleCount;
    property ComputedSurfaceArea: Single read FLastSurfaceArea;
  published
    property Preset: TGeoScriptPreset read FPreset write SetPreset default gspTwistedThickAmphora;
    property BaseShape: TGeoBaseShape read FBaseShape write SetBaseShape default gbsRevolveAmphora;
    property RadialSegments: Integer read FRadialSegments write FRadialSegments default DefaultRadialSegments;
    property HeightRings: Integer read FHeightRings write FHeightRings default DefaultHeightRings;
    property BaseScale: Single read FBaseScale write FBaseScale {$ifdef FPC}default DefaultBaseScale{$endif};
    property BaseColorPersistent: TCastleColorRGBPersistent read FBaseColorPersistent;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Parametric 3D Turtle L-System botanical generator rewriting @code(Axiom)
    with @code(RuleF) / @code(RuleX) over @code(Iterations), interpreting
    full 3D yaw/pitch/roll/branch-stack commands with gravitropism bending
    and canopy leaf cards. }
  TCastleLSystemBotanical = class(TCastleTransform)
  public
    const
      DefaultIterations = 3;
      DefaultStepLength = 0.85;
      DefaultBranchAngleDeg = 28.0;
      DefaultRollAngleDeg = 112.0;
      DefaultBaseRadius = 0.14;
      DefaultLengthDecay = 0.78;
      DefaultRadiusDecay = 0.70;
  strict private
    FPreset: TLSystemPreset;
    FAxiom: String;
    FRuleF: String;
    FRuleX: String;
    FIterations: Integer;
    FStepLength: Single;
    FBranchAngleDeg: Single;
    FRollAngleDeg: Single;
    FBaseRadius: Single;
    FLengthDecay: Single;
    FRadiusDecay: Single;
    FTropismY: Single;

    FTreeScene: TCastleScene;
    FBranches: TLSystemBranchSegArray;
    FLeafCardCount: Integer;
    FBoundsMin: TVector3;
    FBoundsMax: TVector3;

    procedure SetPreset(const Value: TLSystemPreset);
    procedure SetTropismY(const Value: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TLSystemPreset): String; static;

    procedure ApplyPreset(const APreset: TLSystemPreset);
    procedure RebuildBotanicalTree;

    function BranchSegmentCount: Integer;
    function GetBranchSegment(const Index: Integer): TLSystemBranchSeg;
    function BoundsSpanX: Single;
    function BoundsSpanZ: Single;
    function CrownBoundsMaxY: Single;
    function BotanicalSummaryBadge: String;

    property Axiom: String read FAxiom write FAxiom;
    property RuleF: String read FRuleF write FRuleF;
    property RuleX: String read FRuleX write FRuleX;
    property LeafCardCount: Integer read FLeafCardCount;
  published
    property Preset: TLSystemPreset read FPreset write SetPreset default lspBroadleafOakTree;
    property Iterations: Integer read FIterations write FIterations default DefaultIterations;
    property StepLength: Single read FStepLength write FStepLength {$ifdef FPC}default DefaultStepLength{$endif};
    property BranchAngleDeg: Single read FBranchAngleDeg write FBranchAngleDeg {$ifdef FPC}default DefaultBranchAngleDeg{$endif};
    property RollAngleDeg: Single read FRollAngleDeg write FRollAngleDeg {$ifdef FPC}default DefaultRollAngleDeg{$endif};
    property BaseRadius: Single read FBaseRadius write FBaseRadius {$ifdef FPC}default DefaultBaseRadius{$endif};
    property LengthDecay: Single read FLengthDecay write FLengthDecay {$ifdef FPC}default DefaultLengthDecay{$endif};
    property RadiusDecay: Single read FRadiusDecay write FRadiusDecay {$ifdef FPC}default DefaultRadiusDecay{$endif};
    property TropismY: Single read FTropismY write SetTropismY {$ifdef FPC}default 0.08{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Deterministic L-System string rewriter capped at @code(MaxExpandedChars) for editor safety. }
function ExpandLSystemString(const AAxiom, ARuleF, ARuleX: String;
  const AIterations: Integer; const MaxExpandedChars: Integer = 16384): String;

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize;

type
  TWorkMesh = record
    Verts: array of TVector3;
    Norms: array of TVector3;
    Tris: array of Integer; // 3 vertex indices per triangle
  end;

function HashNoise3D(const P: TVector3): Single;
var
  S: Single;
begin
  S := Sin(P.X * 12.9898 + P.Y * 78.233 + P.Z * 37.719) * 43758.5453;
  Result := (S - Floor(S)) * 2.0 - 1.0;
end;

function SmoothValueNoise3D(const P: TVector3): Single;
var
  Ix, Iy, Iz: Integer;
  Fx, Fy, Fz, Ux, Uy, Uz: Single;
  C000, C100, C010, C110, C001, C101, C011, C111: Single;
begin
  Ix := Floor(P.X); Iy := Floor(P.Y); Iz := Floor(P.Z);
  Fx := P.X - Ix;   Fy := P.Y - Iy;   Fz := P.Z - Iz;
  Ux := Fx * Fx * (3.0 - 2.0 * Fx);
  Uy := Fy * Fy * (3.0 - 2.0 * Fy);
  Uz := Fz * Fz * (3.0 - 2.0 * Fz);

  C000 := HashNoise3D(Vector3(Ix,     Iy,     Iz));
  C100 := HashNoise3D(Vector3(Ix + 1, Iy,     Iz));
  C010 := HashNoise3D(Vector3(Ix,     Iy + 1, Iz));
  C110 := HashNoise3D(Vector3(Ix + 1, Iy + 1, Iz));
  C001 := HashNoise3D(Vector3(Ix,     Iy,     Iz + 1));
  C101 := HashNoise3D(Vector3(Ix + 1, Iy,     Iz + 1));
  C011 := HashNoise3D(Vector3(Ix,     Iy + 1, Iz + 1));
  C111 := HashNoise3D(Vector3(Ix + 1, Iy + 1, Iz + 1));

  Result := Lerp(Uz,
    Lerp(Uy, Lerp(Ux, C000, C100), Lerp(Ux, C010, C110)),
    Lerp(Uy, Lerp(Ux, C001, C101), Lerp(Ux, C011, C111)));
end;

procedure RecomputeSmoothNormalsAndArea(var M: TWorkMesh; out OutArea: Single);
var
  I, I0, I1, I2, TriCount: Integer;
  CrossVec: TVector3;
begin
  OutArea := 0.0;
  SetLength(M.Norms, Length(M.Verts));
  for I := 0 to High(M.Norms) do
    M.Norms[I] := TVector3.Zero;

  TriCount := Length(M.Tris) div 3;
  for I := 0 to TriCount - 1 do
  begin
    I0 := M.Tris[I * 3];
    I1 := M.Tris[I * 3 + 1];
    I2 := M.Tris[I * 3 + 2];
    CrossVec := TVector3.CrossProduct(
      M.Verts[I1] - M.Verts[I0],
      M.Verts[I2] - M.Verts[I0]);
    OutArea := OutArea + CrossVec.Length * 0.5;
    M.Norms[I0] := M.Norms[I0] + CrossVec;
    M.Norms[I1] := M.Norms[I1] + CrossVec;
    M.Norms[I2] := M.Norms[I2] + CrossVec;
  end;

  for I := 0 to High(M.Norms) do
    if M.Norms[I].LengthSqr < 1e-10 then
      M.Norms[I] := Vector3(0.0, 1.0, 0.0)
    else
      M.Norms[I] := M.Norms[I].Normalize;
end;

procedure AddTri(var M: TWorkMesh; const A, B, C: Integer);
var
  N: Integer;
begin
  N := Length(M.Tris);
  SetLength(M.Tris, N + 3);
  M.Tris[N] := A;
  M.Tris[N + 1] := B;
  M.Tris[N + 2] := C;
end;

procedure BuildBaseMesh(const Shape: TGeoBaseShape;
  const RadialSegs, HeightRings: Integer; const ScaleVal: Single;
  out M: TWorkMesh);
var
  Segs, Rings, R, S, V00, V10, V01, V11, Face, U, V, BaseIdx: Integer;
  T, Ang, Rad, YPos, Phi: Single;
  Nrm, AxisU, AxisV, Pt: TVector3;
begin
  M.Verts := nil;
  M.Norms := nil;
  M.Tris := nil;
  Segs := Clamped(RadialSegs, 6, 64);
  Rings := Clamped(HeightRings, 2, 32);

  case Shape of
    gbsRevolveAmphora:
      begin
        SetLength(M.Verts, (Rings + 1) * Segs);
        for R := 0 to Rings do
        begin
          T := R / Rings;
          YPos := T * 2.2 * ScaleVal;
          { Classical amphora radial profile }
          Rad := (0.38 + 0.34 * Sin(T * Pi * 1.15) - 0.12 * Sin(T * Pi * 2.6)) * ScaleVal;
          Rad := Max(0.12 * ScaleVal, Rad);
          for S := 0 to Segs - 1 do
          begin
            Ang := (2.0 * Pi * S) / Segs;
            M.Verts[R * Segs + S] := Vector3(Cos(Ang) * Rad, YPos, Sin(Ang) * Rad);
          end;
        end;
        for R := 0 to Rings - 1 do
          for S := 0 to Segs - 1 do
          begin
            V00 := R * Segs + S;
            V10 := R * Segs + ((S + 1) mod Segs);
            V01 := (R + 1) * Segs + S;
            V11 := (R + 1) * Segs + ((S + 1) mod Segs);
            AddTri(M, V00, V10, V11);
            AddTri(M, V00, V11, V01);
          end;
      end;

    gbsUvSphere:
      begin
        SetLength(M.Verts, (Rings + 1) * Segs);
        for R := 0 to Rings do
        begin
          Phi := -Pi * 0.5 + (R / Rings) * Pi;
          YPos := Sin(Phi) * ScaleVal;
          Rad := Max(0.02 * ScaleVal, Cos(Phi) * ScaleVal);
          for S := 0 to Segs - 1 do
          begin
            Ang := (2.0 * Pi * S) / Segs;
            M.Verts[R * Segs + S] := Vector3(Cos(Ang) * Rad, YPos + ScaleVal, Sin(Ang) * Rad);
          end;
        end;
        for R := 0 to Rings - 1 do
          for S := 0 to Segs - 1 do
          begin
            V00 := R * Segs + S;
            V10 := R * Segs + ((S + 1) mod Segs);
            V01 := (R + 1) * Segs + S;
            V11 := (R + 1) * Segs + ((S + 1) mod Segs);
            AddTri(M, V00, V10, V11);
            AddTri(M, V00, V11, V01);
          end;
      end;

    gbsSubdividedBox:
      begin
        Rings := Clamped(HeightRings, 1, 12);
        for Face := 0 to 5 do
        begin
          case Face of
            0: begin Nrm := Vector3( 0,  0,  1); AxisU := Vector3( 1, 0, 0); AxisV := Vector3(0, 1,  0); end;
            1: begin Nrm := Vector3( 0,  0, -1); AxisU := Vector3(-1, 0, 0); AxisV := Vector3(0, 1,  0); end;
            2: begin Nrm := Vector3( 1,  0,  0); AxisU := Vector3( 0, 0,-1); AxisV := Vector3(0, 1,  0); end;
            3: begin Nrm := Vector3(-1,  0,  0); AxisU := Vector3( 0, 0, 1); AxisV := Vector3(0, 1,  0); end;
            4: begin Nrm := Vector3( 0,  1,  0); AxisU := Vector3( 1, 0, 0); AxisV := Vector3(0, 0, -1); end;
            else begin Nrm := Vector3(0, -1, 0); AxisU := Vector3( 1, 0, 0); AxisV := Vector3(0, 0,  1); end;
          end;
          BaseIdx := Length(M.Verts);
          SetLength(M.Verts, BaseIdx + (Rings + 1) * (Rings + 1));
          for V := 0 to Rings do
            for U := 0 to Rings do
            begin
              Pt := (Nrm + AxisU * ((U / Rings) * 2.0 - 1.0) +
                     AxisV * ((V / Rings) * 2.0 - 1.0)) * (0.75 * ScaleVal);
              Pt.Y := Pt.Y + 0.75 * ScaleVal;
              M.Verts[BaseIdx + V * (Rings + 1) + U] := Pt;
            end;
          for V := 0 to Rings - 1 do
            for U := 0 to Rings - 1 do
            begin
              V00 := BaseIdx + V * (Rings + 1) + U;
              V10 := V00 + 1;
              V01 := V00 + (Rings + 1);
              V11 := V01 + 1;
              AddTri(M, V00, V10, V11);
              AddTri(M, V00, V11, V01);
            end;
        end;
      end;
  end;
end;

procedure ApplyModifierLinearSubdivide4x(var M: TWorkMesh);
var
  OldTris: array of Integer;
  TriCount, I, A, B, C, M01, M12, M20: Integer;
begin
  TriCount := Length(M.Tris) div 3;
  if (TriCount = 0) or (TriCount > 16000) then
    Exit;
  OldTris := Copy(M.Tris, 0, Length(M.Tris));
  M.Tris := nil;

  for I := 0 to TriCount - 1 do
  begin
    A := OldTris[I * 3];
    B := OldTris[I * 3 + 1];
    C := OldTris[I * 3 + 2];

    M01 := Length(M.Verts);
    SetLength(M.Verts, M01 + 3);
    M12 := M01 + 1;
    M20 := M01 + 2;
    M.Verts[M01] := (M.Verts[A] + M.Verts[B]) * 0.5;
    M.Verts[M12] := (M.Verts[B] + M.Verts[C]) * 0.5;
    M.Verts[M20] := (M.Verts[C] + M.Verts[A]) * 0.5;

    AddTri(M, A, M01, M20);
    AddTri(M, M01, B, M12);
    AddTri(M, M20, M12, C);
    AddTri(M, M01, M12, M20);
  end;
end;

procedure ApplyModifierTwistY(var M: TWorkMesh; const DegPerMeter: Single);
var
  I: Integer;
  Ang, C, S, X, Z: Single;
begin
  for I := 0 to High(M.Verts) do
  begin
    Ang := DegToRad(DegPerMeter * M.Verts[I].Y);
    C := Cos(Ang);
    S := Sin(Ang);
    X := M.Verts[I].X;
    Z := M.Verts[I].Z;
    M.Verts[I].X := X * C - Z * S;
    M.Verts[I].Z := X * S + Z * C;
  end;
end;

procedure ApplyModifierTaperY(var M: TWorkMesh; const TopScale: Single);
var
  I: Integer;
  MinY, MaxY, T, S: Single;
begin
  if Length(M.Verts) = 0 then Exit;
  MinY := M.Verts[0].Y;
  MaxY := M.Verts[0].Y;
  for I := 1 to High(M.Verts) do
  begin
    MinY := Min(MinY, M.Verts[I].Y);
    MaxY := Max(MaxY, M.Verts[I].Y);
  end;
  if MaxY - MinY < 1e-5 then Exit;
  for I := 0 to High(M.Verts) do
  begin
    T := (M.Verts[I].Y - MinY) / (MaxY - MinY);
    S := Lerp(T, 1.0, TopScale);
    M.Verts[I].X := M.Verts[I].X * S;
    M.Verts[I].Z := M.Verts[I].Z * S;
  end;
end;

procedure ApplyModifierPerlinDisplace(var M: TWorkMesh;
  const Amplitude, Frequency: Single);
var
  DummyArea, Freq, Disp: Single;
  I: Integer;
begin
  RecomputeSmoothNormalsAndArea(M, DummyArea);
  Freq := Max(0.05, Frequency);
  for I := 0 to High(M.Verts) do
  begin
    Disp := Amplitude * SmoothValueNoise3D(M.Verts[I] * Freq);
    M.Verts[I] := M.Verts[I] + M.Norms[I] * Disp;
  end;
end;

procedure ApplyModifierSolidifyShell(var M: TWorkMesh; const Thickness: Single);
var
  DummyArea: Single;
  OrigVertCount, OrigTriCount, I: Integer;
begin
  if Abs(Thickness) < 1e-5 then Exit;
  RecomputeSmoothNormalsAndArea(M, DummyArea);
  OrigVertCount := Length(M.Verts);
  OrigTriCount := Length(M.Tris) div 3;

  SetLength(M.Verts, OrigVertCount * 2);
  for I := 0 to OrigVertCount - 1 do
    M.Verts[OrigVertCount + I] := M.Verts[I] - M.Norms[I] * Thickness;

  { Append flipped inner shell triangles }
  for I := 0 to OrigTriCount - 1 do
    AddTri(M,
      OrigVertCount + M.Tris[I * 3],
      OrigVertCount + M.Tris[I * 3 + 2],
      OrigVertCount + M.Tris[I * 3 + 1]);
end;

function ExpandLSystemString(const AAxiom, ARuleF, ARuleX: String;
  const AIterations: Integer; const MaxExpandedChars: Integer): String;
var
  Cur, NextStr: String;
  SB: TStringBuilder;
  Iter, I: Integer;
  Ch: Char;
begin
  Cur := AAxiom;
  for Iter := 1 to Clamped(AIterations, 0, 7) do
  begin
    SB := TStringBuilder.Create;
    try
      for I := 1 to Length(Cur) do
      begin
        Ch := Cur[I];
        if (Ch = 'F') and (ARuleF <> '') then
          SB.Append(ARuleF)
        else if (Ch = 'X') and (ARuleX <> '') then
          SB.Append(ARuleX)
        else
          SB.Append(Ch);
        if SB.Length >= MaxExpandedChars then
          Break;
      end;
      NextStr := SB.ToString;
    finally
      FreeAndNil(SB);
    end;
    Cur := NextStr;
    if Length(Cur) >= MaxExpandedChars then
      Break;
  end;
  Result := Cur;
end;

{ TCastleGeometryScriptMesh -------------------------------------------------- }

constructor TCastleGeometryScriptMesh.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRadialSegments := DefaultRadialSegments;
  FHeightRings := DefaultHeightRings;
  FBaseScale := DefaultBaseScale;
  FBaseColor := Vector3(0.82, 0.56, 0.36);

  FBaseColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FBaseColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetBaseColorForPersistent;
  FBaseColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetBaseColorForPersistent;
  FBaseColorPersistent.InternalDefaultValue := FBaseColor;

  ApplyPreset(gspTwistedThickAmphora);
end;

destructor TCastleGeometryScriptMesh.Destroy;
begin
  FreeAndNil(FBaseColorPersistent);
  inherited;
end;

procedure TCastleGeometryScriptMesh.Loaded;
begin
  inherited;
  RebuildProceduralMesh;
end;

class function TCastleGeometryScriptMesh.PresetDisplayName(
  const APreset: TGeoScriptPreset): String;
begin
  case APreset of
    gspCustom:                   Result := 'Custom Stack';
    gspTwistedThickAmphora:      Result := 'Twisted Solidified Amphora';
    gspDisplacedAsteroidBoulder: Result := 'Perlin Displaced Asteroid';
    gspTaperedObeliskColumn:     Result := 'Tapered Obelisk Column';
  end;
end;

class function TCastleGeometryScriptMesh.ModifierDisplayName(
  const AKind: TGeoModifierKind): String;
begin
  case AKind of
    gmkLinearSubdivide4x:    Result := 'Linear Subdivide (4x)';
    gmkTwistAroundY:         Result := 'Twist Around +Y';
    gmkTaperAlongY:          Result := 'Taper Along +Y';
    gmkPerlinNormalDisplace: Result := '3D Noise Normal Displace';
    gmkSolidifyShell:        Result := 'Solidify Shell Thickness';
  end;
end;

procedure TCastleGeometryScriptMesh.ClearModifiers;
begin
  FModifiers := nil;
end;

function TCastleGeometryScriptMesh.AddModifier(const AKind: TGeoModifierKind;
  const AParamA, AParamB: Single; const AEnabled: Boolean): Integer;
begin
  Result := Length(FModifiers);
  SetLength(FModifiers, Result + 1);
  FModifiers[Result].Enabled := AEnabled;
  FModifiers[Result].Kind := AKind;
  FModifiers[Result].ParamA := AParamA;
  FModifiers[Result].ParamB := AParamB;
  RebuildProceduralMesh;
end;

procedure TCastleGeometryScriptMesh.SetModifierEnabled(
  const Index: Integer; const AEnabled: Boolean);
begin
  if (Index < 0) or (Index > High(FModifiers)) then
    Exit;
  FModifiers[Index].Enabled := AEnabled;
  RebuildProceduralMesh;
end;

function TCastleGeometryScriptMesh.ModifierCount: Integer;
begin
  Result := Length(FModifiers);
end;

function TCastleGeometryScriptMesh.GetModifier(const Index: Integer): TGeoModifierStage;
begin
  Result := FModifiers[Clamped(Index, 0, Max(0, High(FModifiers)))];
end;

procedure TCastleGeometryScriptMesh.ApplyPreset(const APreset: TGeoScriptPreset);
begin
  FPreset := APreset;
  case APreset of
    gspTwistedThickAmphora:
      begin
        ClearModifiers;
        FBaseShape := gbsRevolveAmphora;
        FRadialSegments := 18;
        FHeightRings := 10;
        FBaseColor := Vector3(0.84, 0.54, 0.34);
        AddModifier(gmkTwistAroundY, 38.0, 0.0, True);
        AddModifier(gmkSolidifyShell, 0.06, 0.0, True);
      end;
    gspDisplacedAsteroidBoulder:
      begin
        ClearModifiers;
        FBaseShape := gbsUvSphere;
        FRadialSegments := 16;
        FHeightRings := 10;
        FBaseColor := Vector3(0.48, 0.46, 0.44);
        AddModifier(gmkLinearSubdivide4x, 1.0, 0.0, True);
        AddModifier(gmkPerlinNormalDisplace, 0.22, 2.4, True);
      end;
    gspTaperedObeliskColumn:
      begin
        ClearModifiers;
        FBaseShape := gbsSubdividedBox;
        FHeightRings := 4;
        FBaseColor := Vector3(0.76, 0.78, 0.82);
        AddModifier(gmkTaperAlongY, 0.42, 0.0, True);
        AddModifier(gmkTwistAroundY, 22.0, 0.0, True);
      end;
    gspCustom: ;
  end;
  RebuildProceduralMesh;
end;

procedure TCastleGeometryScriptMesh.RebuildProceduralMesh;
var
  Work: TWorkMesh;
  I, TriCount: Integer;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  NormNode: TNormalNode;
  SoupPts, SoupNorms: array of TVector3;
begin
  if csLoading in ComponentState then
    Exit;

  BuildBaseMesh(FBaseShape, FRadialSegments, FHeightRings, FBaseScale, Work);

  for I := 0 to High(FModifiers) do
    if FModifiers[I].Enabled then
      case FModifiers[I].Kind of
        gmkLinearSubdivide4x:    ApplyModifierLinearSubdivide4x(Work);
        gmkTwistAroundY:         ApplyModifierTwistY(Work, FModifiers[I].ParamA);
        gmkTaperAlongY:          ApplyModifierTaperY(Work, FModifiers[I].ParamA);
        gmkPerlinNormalDisplace: ApplyModifierPerlinDisplace(Work, FModifiers[I].ParamA, FModifiers[I].ParamB);
        gmkSolidifyShell:        ApplyModifierSolidifyShell(Work, FModifiers[I].ParamA);
      end;

  RecomputeSmoothNormalsAndArea(Work, FLastSurfaceArea);
  FLastVertexCount := Length(Work.Verts);
  TriCount := Length(Work.Tris) div 3;
  FLastTriangleCount := TriCount;
  FPreviewVerts := Copy(Work.Verts, 0, Min(256, Length(Work.Verts)));

  FreeAndNil(FMeshScene);
  if TriCount = 0 then
    Exit;

  SetLength(SoupPts, TriCount * 3);
  SetLength(SoupNorms, TriCount * 3);
  for I := 0 to TriCount * 3 - 1 do
  begin
    SoupPts[I] := Work.Verts[Work.Tris[I]];
    SoupNorms[I] := Work.Norms[Work.Tris[I]];
  end;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := FBaseColor;
  Mat.Roughness := 0.45;
  Mat.Metallic := 0.12;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  Coord := TCoordinateNode.Create;
  Coord.SetPoint(SoupPts);
  NormNode := TNormalNode.Create;
  NormNode.SetVector(SoupNorms);
  TriSet.Coord := Coord;
  TriSet.Normal := NormNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);

  FMeshScene := TCastleScene.Create(Self);
  FMeshScene.SetTransient;
  FMeshScene.Load(Root, True);
  Add(FMeshScene);
end;

function TCastleGeometryScriptMesh.PreviewVertexCount: Integer;
begin
  Result := Length(FPreviewVerts);
end;

function TCastleGeometryScriptMesh.GetPreviewVertex(const Index: Integer): TVector3;
begin
  Result := FPreviewVerts[Clamped(Index, 0, Max(0, High(FPreviewVerts)))];
end;

function TCastleGeometryScriptMesh.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'BaseShape') or
     (PropertyName = 'RadialSegments') or
     (PropertyName = 'HeightRings') or
     (PropertyName = 'BaseScale') or
     (PropertyName = 'BaseColorPersistent') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleGeometryScriptMesh.GeoSummaryBadge: String;
begin
  Result := Format('[GeoScript:%s %d mods %d tris]', [
    PresetDisplayName(FPreset), Length(FModifiers), FLastTriangleCount]);
end;

procedure TCastleGeometryScriptMesh.SetPreset(const Value: TGeoScriptPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleGeometryScriptMesh.SetBaseShape(const Value: TGeoBaseShape);
begin
  if FBaseShape <> Value then
  begin
    FBaseShape := Value;
    RebuildProceduralMesh;
  end;
end;

function TCastleGeometryScriptMesh.GetBaseColorForPersistent: TCastleColorRGB;
begin
  Result := FBaseColor;
end;

procedure TCastleGeometryScriptMesh.SetBaseColorForPersistent(const AValue: TCastleColorRGB);
begin
  FBaseColor := AValue;
  RebuildProceduralMesh;
end;

function TCastleGeometryScriptMesh.GetConfigJson: String;
var
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('baseShape', Ord(FBaseShape));
    Root.Add('segs', FRadialSegments);
    Root.Add('rings', FHeightRings);
    Root.Add('scale', FBaseScale);
    Arr := TJSONArray.Create;
    for I := 0 to High(FModifiers) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('on', FModifiers[I].Enabled);
      Obj.Add('kind', Ord(FModifiers[I].Kind));
      Obj.Add('a', FModifiers[I].ParamA);
      Obj.Add('b', FModifiers[I].ParamB);
      Arr.Add(Obj);
    end;
    Root.Add('mods', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleGeometryScriptMesh.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TGeoScriptPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TGeoScriptPreset))));
      FBaseShape := TGeoBaseShape(Clamped(Root.Get('baseShape', Ord(FBaseShape)),
        0, Ord(High(TGeoBaseShape))));
      FRadialSegments := Clamped(Root.Get('segs', FRadialSegments), 6, 64);
      FHeightRings := Clamped(Root.Get('rings', FHeightRings), 1, 32);
      FBaseScale := Max(0.05, Root.Get('scale', FBaseScale));
      Arr := Root.Find('mods', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        ClearModifiers;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            Obj := TJSONObject(Arr.Items[I]);
            SetLength(FModifiers, Length(FModifiers) + 1);
            FModifiers[High(FModifiers)].Enabled := Obj.Get('on', True);
            FModifiers[High(FModifiers)].Kind := TGeoModifierKind(
              Clamped(Obj.Get('kind', 0), 0, Ord(High(TGeoModifierKind))));
            FModifiers[High(FModifiers)].ParamA := Obj.Get('a', 1.0);
            FModifiers[High(FModifiers)].ParamB := Obj.Get('b', 1.0);
          end;
      end;
      RebuildProceduralMesh;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleLSystemBotanical ---------------------------------------------------- }

constructor TCastleLSystemBotanical.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ApplyPreset(lspBroadleafOakTree);
end;

procedure TCastleLSystemBotanical.Loaded;
begin
  inherited;
  RebuildBotanicalTree;
end;

class function TCastleLSystemBotanical.PresetDisplayName(const APreset: TLSystemPreset): String;
begin
  case APreset of
    lspCustom:            Result := 'Custom L-System';
    lspBroadleafOakTree:  Result := 'Broadleaf Oak Tree';
    lspAlpineConiferPine: Result := 'Alpine Conifer Pine';
    lspWeepingWillowTree: Result := 'Weeping Willow Tree';
  end;
end;

procedure TCastleLSystemBotanical.ApplyPreset(const APreset: TLSystemPreset);
begin
  FPreset := APreset;
  case APreset of
    lspBroadleafOakTree:
      begin
        FAxiom := 'FX';
        FRuleF := 'F';
        FRuleX := 'F[+X][/&X][\-X]^FX';
        FIterations := 3;
        FStepLength := 0.85;
        FBranchAngleDeg := 29.0;
        FRollAngleDeg := 118.0;
        FBaseRadius := 0.14;
        FLengthDecay := 0.82;
        FRadiusDecay := 0.72;
        FTropismY := 0.10;
      end;
    lspAlpineConiferPine:
      begin
        FAxiom := 'FX';
        FRuleF := 'F';
        FRuleX := 'F[&+X][\-X][/&X]FX';
        FIterations := 3;
        FStepLength := 0.72;
        FBranchAngleDeg := 42.0;
        FRollAngleDeg := 120.0;
        FBaseRadius := 0.12;
        FLengthDecay := 0.86;
        FRadiusDecay := 0.74;
        FTropismY := 0.16;
      end;
    lspWeepingWillowTree:
      begin
        FAxiom := 'FX';
        FRuleF := 'F';
        FRuleX := 'F[+X][/-X][\&X]FX';
        FIterations := 3;
        FStepLength := 0.80;
        FBranchAngleDeg := 34.0;
        FRollAngleDeg := 115.0;
        FBaseRadius := 0.13;
        FLengthDecay := 0.84;
        FRadiusDecay := 0.70;
        FTropismY := -0.22;
      end;
    lspCustom: ;
  end;
  RebuildBotanicalTree;
end;

procedure TCastleLSystemBotanical.RebuildBotanicalTree;
type
  TTurtleState = record
    Pos: TVector3;
    Heading: TVector3;
    LeftVec: TVector3;
    UpVec: TVector3;
    Depth: Integer;
  end;
var
  Expanded: String;
  Cur: TTurtleState;
  Stack: array of TTurtleState;
  StackTop, I, S: Integer;
  Ch: Char;
  AngRad, RollRad, StepLen, Rad0, Rad1, Ang0, Ang1: Single;
  NextPos, PerpA, PerpB, P00, P10, P01, P11, LeafR, LeafU: TVector3;
  BarkPts, LeafPts: array of TVector3;
  BarkIdx, LeafIdx, SegIdx: Integer;
  Root: TX3DRootNode;
  BarkShape, LeafShape: TShapeNode;
  BarkApp, LeafApp: TAppearanceNode;
  BarkMat, LeafMat: TPhysicalMaterialNode;
  BarkTri, LeafTri: TTriangleSetNode;
  BarkCoord, LeafCoord: TCoordinateNode;

  procedure UpdateBounds(const P: TVector3);
  begin
    FBoundsMin.X := Min(FBoundsMin.X, P.X);
    FBoundsMin.Y := Min(FBoundsMin.Y, P.Y);
    FBoundsMin.Z := Min(FBoundsMin.Z, P.Z);
    FBoundsMax.X := Max(FBoundsMax.X, P.X);
    FBoundsMax.Y := Max(FBoundsMax.Y, P.Y);
    FBoundsMax.Z := Max(FBoundsMax.Z, P.Z);
  end;

  procedure OrthonormalizeFrame(var St: TTurtleState);
  begin
    if St.Heading.LengthSqr < 1e-8 then
      St.Heading := Vector3(0.0, 1.0, 0.0)
    else
      St.Heading := St.Heading.Normalize;
    St.LeftVec := St.LeftVec - St.Heading * TVector3.DotProduct(St.LeftVec, St.Heading);
    if St.LeftVec.LengthSqr < 1e-8 then
    begin
      if Abs(St.Heading.X) < 0.85 then
        St.LeftVec := TVector3.CrossProduct(St.Heading, Vector3(1.0, 0.0, 0.0))
      else
        St.LeftVec := TVector3.CrossProduct(St.Heading, Vector3(0.0, 0.0, 1.0));
    end;
    St.LeftVec := St.LeftVec.Normalize;
    St.UpVec := TVector3.CrossProduct(St.Heading, St.LeftVec).Normalize;
  end;

  procedure EmitLeafCard(const AtPos, DirHint: TVector3);
  const
    LeafHalf = 0.24;
  begin
    if Abs(DirHint.X) < 0.85 then
      LeafR := TVector3.CrossProduct(DirHint, Vector3(1.0, 0.0, 0.0)).Normalize
    else
      LeafR := TVector3.CrossProduct(DirHint, Vector3(0.0, 0.0, 1.0)).Normalize;
    LeafU := TVector3.CrossProduct(LeafR, DirHint).Normalize;

    LeafIdx := Length(LeafPts);
    SetLength(LeafPts, LeafIdx + 6);
    LeafPts[LeafIdx + 0] := AtPos - LeafR * LeafHalf;
    LeafPts[LeafIdx + 1] := AtPos + LeafR * LeafHalf;
    LeafPts[LeafIdx + 2] := AtPos + DirHint * (LeafHalf * 1.6) + LeafU * 0.06;
    LeafPts[LeafIdx + 3] := AtPos - LeafR * LeafHalf;
    LeafPts[LeafIdx + 4] := AtPos + DirHint * (LeafHalf * 1.6) + LeafU * 0.06;
    LeafPts[LeafIdx + 5] := AtPos - DirHint * (LeafHalf * 0.5);
    Inc(FLeafCardCount);
    UpdateBounds(LeafPts[LeafIdx + 2]);
  end;

begin
  if csLoading in ComponentState then
    Exit;

  FBranches := nil;
  FLeafCardCount := 0;
  FBoundsMin := TVector3.Zero;
  FBoundsMax := TVector3.Zero;
  BarkPts := nil;
  LeafPts := nil;

  Expanded := ExpandLSystemString(FAxiom, FRuleF, FRuleX, FIterations, 8192);

  Cur.Pos := TVector3.Zero;
  Cur.Heading := Vector3(0.0, 1.0, 0.0);
  Cur.LeftVec := Vector3(-1.0, 0.0, 0.0);
  Cur.UpVec := Vector3(0.0, 0.0, 1.0);
  Cur.Depth := 0;
  Stack := nil;
  StackTop := 0;

  AngRad := DegToRad(FBranchAngleDeg);
  RollRad := DegToRad(FRollAngleDeg);

  for I := 1 to Length(Expanded) do
  begin
    Ch := Expanded[I];
    case Ch of
      'F':
        begin
          StepLen := Max(0.05, FStepLength * Power(Clamped(FLengthDecay, 0.3, 1.05), Cur.Depth));
          Rad0 := Max(0.012, FBaseRadius * Power(Clamped(FRadiusDecay, 0.3, 1.0), Cur.Depth));
          Rad1 := Max(0.008, Rad0 * Clamped(FRadiusDecay, 0.3, 1.0));

          { Apply gravitropism / phototropism bend toward +Y / -Y }
          Cur.Heading := (Cur.Heading + Vector3(0.0, FTropismY, 0.0)).Normalize;
          OrthonormalizeFrame(Cur);

          NextPos := Cur.Pos + Cur.Heading * StepLen;
          UpdateBounds(NextPos);

          SegIdx := Length(FBranches);
          SetLength(FBranches, SegIdx + 1);
          FBranches[SegIdx].StartPos := Cur.Pos;
          FBranches[SegIdx].EndPos := NextPos;
          FBranches[SegIdx].Radius := Rad0;

          { 5-sided tapered bark cylinder }
          PerpA := Cur.LeftVec;
          PerpB := Cur.UpVec;
          BarkIdx := Length(BarkPts);
          SetLength(BarkPts, BarkIdx + 5 * 6);
          for S := 0 to 4 do
          begin
            Ang0 := (2.0 * Pi * S) / 5.0;
            Ang1 := (2.0 * Pi * (S + 1)) / 5.0;
            P00 := Cur.Pos + (PerpA * Cos(Ang0) + PerpB * Sin(Ang0)) * Rad0;
            P10 := Cur.Pos + (PerpA * Cos(Ang1) + PerpB * Sin(Ang1)) * Rad0;
            P01 := NextPos + (PerpA * Cos(Ang0) + PerpB * Sin(Ang0)) * Rad1;
            P11 := NextPos + (PerpA * Cos(Ang1) + PerpB * Sin(Ang1)) * Rad1;

            BarkPts[BarkIdx + S * 6 + 0] := P00;
            BarkPts[BarkIdx + S * 6 + 1] := P10;
            BarkPts[BarkIdx + S * 6 + 2] := P11;
            BarkPts[BarkIdx + S * 6 + 3] := P00;
            BarkPts[BarkIdx + S * 6 + 4] := P11;
            BarkPts[BarkIdx + S * 6 + 5] := P01;
          end;

          Cur.Pos := NextPos;
        end;
      '+':
        begin
          Cur.Heading := RotatePointAroundAxis(Vector4(Cur.UpVec, AngRad), Cur.Heading);
          OrthonormalizeFrame(Cur);
        end;
      '-':
        begin
          Cur.Heading := RotatePointAroundAxis(Vector4(Cur.UpVec, -AngRad), Cur.Heading);
          OrthonormalizeFrame(Cur);
        end;
      '&':
        begin
          Cur.Heading := RotatePointAroundAxis(Vector4(Cur.LeftVec, AngRad), Cur.Heading);
          OrthonormalizeFrame(Cur);
        end;
      '^':
        begin
          Cur.Heading := RotatePointAroundAxis(Vector4(Cur.LeftVec, -AngRad), Cur.Heading);
          OrthonormalizeFrame(Cur);
        end;
      '\':
        begin
          Cur.LeftVec := RotatePointAroundAxis(Vector4(Cur.Heading, RollRad), Cur.LeftVec);
          OrthonormalizeFrame(Cur);
        end;
      '/':
        begin
          Cur.LeftVec := RotatePointAroundAxis(Vector4(Cur.Heading, -RollRad), Cur.LeftVec);
          OrthonormalizeFrame(Cur);
        end;
      '[':
        begin
          if StackTop >= Length(Stack) then
            SetLength(Stack, StackTop + 16);
          Stack[StackTop] := Cur;
          Inc(StackTop);
          Inc(Cur.Depth);
        end;
      ']':
        begin
          EmitLeafCard(Cur.Pos, Cur.Heading);
          if StackTop > 0 then
          begin
            Dec(StackTop);
            Cur := Stack[StackTop];
          end;
        end;
    end;
  end;
  EmitLeafCard(Cur.Pos, Cur.Heading);

  FreeAndNil(FTreeScene);
  Root := TX3DRootNode.Create;

  if Length(BarkPts) > 0 then
  begin
    BarkShape := TShapeNode.Create;
    BarkApp := TAppearanceNode.Create;
    BarkMat := TPhysicalMaterialNode.Create;
    BarkMat.BaseColor := Vector3(0.36, 0.24, 0.14);
    BarkMat.Roughness := 0.88;
    BarkApp.Material := BarkMat;
    BarkShape.Appearance := BarkApp;
    BarkTri := TTriangleSetNode.Create;
    BarkTri.Solid := False;
    BarkCoord := TCoordinateNode.Create;
    BarkCoord.SetPoint(BarkPts);
    BarkTri.Coord := BarkCoord;
    BarkShape.Geometry := BarkTri;
    Root.AddChildren(BarkShape);
  end;

  if Length(LeafPts) > 0 then
  begin
    LeafShape := TShapeNode.Create;
    LeafApp := TAppearanceNode.Create;
    LeafMat := TPhysicalMaterialNode.Create;
    LeafMat.BaseColor := Vector3(0.22, 0.64, 0.26);
    LeafMat.Roughness := 0.62;
    LeafApp.Material := LeafMat;
    LeafShape.Appearance := LeafApp;
    LeafTri := TTriangleSetNode.Create;
    LeafTri.Solid := False;
    LeafCoord := TCoordinateNode.Create;
    LeafCoord.SetPoint(LeafPts);
    LeafTri.Coord := LeafCoord;
    LeafShape.Geometry := LeafTri;
    Root.AddChildren(LeafShape);
  end;

  FTreeScene := TCastleScene.Create(Self);
  FTreeScene.SetTransient;
  FTreeScene.Load(Root, True);
  Add(FTreeScene);
end;

function TCastleLSystemBotanical.BranchSegmentCount: Integer;
begin
  Result := Length(FBranches);
end;

function TCastleLSystemBotanical.GetBranchSegment(const Index: Integer): TLSystemBranchSeg;
begin
  Result := FBranches[Clamped(Index, 0, Max(0, High(FBranches)))];
end;

function TCastleLSystemBotanical.BoundsSpanX: Single;
begin
  Result := FBoundsMax.X - FBoundsMin.X;
end;

function TCastleLSystemBotanical.BoundsSpanZ: Single;
begin
  Result := FBoundsMax.Z - FBoundsMin.Z;
end;

function TCastleLSystemBotanical.CrownBoundsMaxY: Single;
begin
  Result := FBoundsMax.Y;
end;

function TCastleLSystemBotanical.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'Iterations') or
     (PropertyName = 'StepLength') or
     (PropertyName = 'BranchAngleDeg') or
     (PropertyName = 'RollAngleDeg') or
     (PropertyName = 'TropismY') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleLSystemBotanical.BotanicalSummaryBadge: String;
begin
  Result := Format('[LSystem:%s %d br %d leaves]', [
    PresetDisplayName(FPreset), Length(FBranches), FLeafCardCount]);
end;

procedure TCastleLSystemBotanical.SetPreset(const Value: TLSystemPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleLSystemBotanical.SetTropismY(const Value: Single);
begin
  FTropismY := Clamped(Value, -0.85, 0.85);
  RebuildBotanicalTree;
end;

function TCastleLSystemBotanical.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('axiom', FAxiom);
    Root.Add('ruleF', FRuleF);
    Root.Add('ruleX', FRuleX);
    Root.Add('iter', FIterations);
    Root.Add('step', FStepLength);
    Root.Add('ang', FBranchAngleDeg);
    Root.Add('roll', FRollAngleDeg);
    Root.Add('tropism', FTropismY);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleLSystemBotanical.SetConfigJson(const Value: String);
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
      FPreset := TLSystemPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TLSystemPreset))));
      FAxiom := Root.Get('axiom', FAxiom);
      FRuleF := Root.Get('ruleF', FRuleF);
      FRuleX := Root.Get('ruleX', FRuleX);
      FIterations := Clamped(Root.Get('iter', FIterations), 1, 6);
      FStepLength := Max(0.05, Root.Get('step', FStepLength));
      FBranchAngleDeg := Clamped(Root.Get('ang', FBranchAngleDeg), 1.0, 120.0);
      FRollAngleDeg := Root.Get('roll', FRollAngleDeg);
      FTropismY := Clamped(Root.Get('tropism', FTropismY), -0.85, 0.85);
      RebuildBotanicalTree;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleGeometryScriptMesh,
    ['Architecture & Procedural', 'Geometry Script Procedural Mesh Stack']);
  RegisterSerializableComponent(TCastleLSystemBotanical,
    ['Architecture & Procedural', '3D L-System Botanical Tree / Vine']);
end.
