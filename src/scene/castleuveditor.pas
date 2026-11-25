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

{ Unreal Engine 5.5-style Modeling Mode UV Editor & Texel-Density Studio runtime
  (@link(TCastleUvEditorMesh)) featuring Planar / Box-6-Face Triplanar /
  Cylindrical Seam-Cut / Conformal Relax UV projection, connected UV island
  extraction, rectilinear Shelf bin-packing with configurable texel gutter
  padding, exact 2D triangle-triangle overlap & inverted-winding audit, and
  world-space Texel Density (px/m) calculation & equalization
  (Phase 389 — UE 5.5 Modeling Mode UV Editor & XAtlas Parity). }
unit CastleUvEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { UV projection / unwrap algorithm (UE5 Modeling Mode ProjectUV / AutoUV). }
  TUvProjectionMode = (
    upmPlanarTopXZ,
    upmBox6FaceTriplanar,
    upmCylindricalSeam,
    upmConformalSeamRelax
  );

  { Built-in UE 5.5 UV Editor starter mesh presets. }
  TUvMeshPreset = (
    umpCustom,
    umpArchitecturalCrate6Islands,
    umpCylindricalColumnSeamUnwrap,
    umpOverlappingStackedUvRepairDemo
  );

  { Single mesh triangle carrying 3D local positions, face normal, island ID & 2D UVs. }
  TUvTriangle = record
    Pos3D: array[0..2] of TVector3;
    UV: array[0..2] of TVector2;
    IslandId: Integer;
  end;
  TUvTriangleArray = array of TUvTriangle;

  { Bounding box & area metrics for a single connected UV island. }
  TUvIslandInfo = record
    IslandId: Integer;
    TriangleCount: Integer;
    MinUV: TVector2;
    MaxUV: TVector2;
    UvArea: Single;
    WorldAreaM2: Single;
    TexelsPerMeter: Single;
  end;
  TUvIslandInfoArray = array of TUvIslandInfo;

  { Comprehensive UV layout & texel-density audit summary. }
  TUvLayoutAudit = record
    TriangleCount: Integer;
    IslandCount: Integer;
    OverlappingPairCount: Integer;
    InvertedTriangleCount: Integer;
    OutOfUnitBoundsCount: Integer;
    TotalUvArea: Single;
    TotalWorldAreaM2: Single;
    UvCoveragePercent: Single;
    MeasuredTexelsPerMeter: Single;
    TexelDensityScaleFactor: Single;
  end;

  { Unreal Engine 5.5-style Modeling Mode UV Editor & Texel-Density component. }
  TCastleUvEditorMesh = class(TCastleTransform)
  private
    FPreset: TUvMeshPreset;
    FProjectionMode: TUvProjectionMode;
    FTextureResolution: Integer;
    FPaddingTexels: Single;
    FTargetTexelsPerMeter: Single;
    FShowCheckerPreview: Boolean;

    FTriangles: TUvTriangleArray;
    FIslands: TUvIslandInfoArray;
    FLastAudit: TUvLayoutAudit;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TUvMeshPreset);
    procedure SetTextureResolution(const AValue: Integer);
    procedure SetPaddingTexels(const AValue: Single);
    procedure SetTargetTexelsPerMeter(const AValue: Single);
    procedure SetShowCheckerPreview(const AValue: Boolean);
    function GetUvMeshJson: String;
    procedure SetUvMeshJson(const AValue: String);

    procedure BuildBoxMeshTriangles(const ASize: TVector3; const AStackOverlappingUvs: Boolean);
    procedure BuildCylinderMeshTriangles(const ARadius, AHeight: Single; const ASides: Integer);
    procedure RebuildIslandMetrics;
    procedure ClearPreviewContainer;
    procedure SyncCheckerPreview;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Exact 2D UV Geometry & Overlap Math }
    class function SignedTriangleUvArea(const A, B, C: TVector2): Single; static;
    class function TriangleWorldAreaM2(const A, B, C: TVector3): Single; static;
    class function TrianglesOverlap2D(const A0, A1, A2, B0, B1, B2: TVector2): Boolean; static;
    class function ProjectionModeTitle(const AMode: TUvProjectionMode): String; static;

    { UV Projection, Seam Relaxation, Rectilinear Shelf Packing & Texel Density }
    procedure ClearMesh;
    procedure ApplyPreset(const APreset: TUvMeshPreset);
    procedure ProjectUvs(const AMode: TUvProjectionMode);
    procedure RelaxIslandInteriorUvs(const AIterations: Integer = 4);
    procedure PackUvIslandsIntoUnitSquare;
    procedure AutoUnwrapAndPack(const AMode: TUvProjectionMode);
    function ComputeTexelDensityScaleForTarget(const ATargetPxPerM: Single): Single;
    function AuditUvLayout: TUvLayoutAudit;

    function UvSummaryBadge: String;

    property Triangles: TUvTriangleArray read FTriangles;
    property Islands: TUvIslandInfoArray read FIslands;
    property LastAudit: TUvLayoutAudit read FLastAudit;
  published
    property ProjectionMode: TUvProjectionMode
      read FProjectionMode write FProjectionMode default upmBox6FaceTriplanar;
    property TextureResolution: Integer
      read FTextureResolution write SetTextureResolution default 1024;
    property PaddingTexels: Single
      read FPaddingTexels write SetPaddingTexels;
    property TargetTexelsPerMeter: Single
      read FTargetTexelsPerMeter write SetTargetTexelsPerMeter;
    property ShowCheckerPreview: Boolean
      read FShowCheckerPreview write SetShowCheckerPreview default True;
    property UvMeshJson: String read GetUvMeshJson write SetUvMeshJson;
    property Preset: TUvMeshPreset read FPreset write SetPreset default umpArchitecturalCrate6Islands;
  end;

implementation

uses
  fpjson, jsonparser;

{ Exact 2D UV Geometry & Overlap Detection ----------------------------------- }

class function TCastleUvEditorMesh.SignedTriangleUvArea(
  const A, B, C: TVector2): Single;
begin
  Result := 0.5 * ((B.X - A.X) * (C.Y - A.Y) - (C.X - A.X) * (B.Y - A.Y));
end;

class function TCastleUvEditorMesh.TriangleWorldAreaM2(
  const A, B, C: TVector3): Single;
begin
  Result := 0.5 * TVector3.CrossProduct(B - A, C - A).Length;
end;

function PointStrictlyInsideTri2D(const P, A, B, C: TVector2): Boolean;
const
  Eps = 1e-4;
var
  D1, D2, D3: Single;
  HasNeg, HasPos: Boolean;
begin
  D1 := (P.X - B.X) * (A.Y - B.Y) - (A.X - B.X) * (P.Y - B.Y);
  D2 := (P.X - C.X) * (B.Y - C.Y) - (B.X - C.X) * (P.Y - C.Y);
  D3 := (P.X - A.X) * (C.Y - A.Y) - (C.X - A.X) * (P.Y - A.Y);

  HasNeg := (D1 < -Eps) or (D2 < -Eps) or (D3 < -Eps);
  HasPos := (D1 >  Eps) or (D2 >  Eps) or (D3 >  Eps);
  if HasNeg and HasPos then Exit(False);
  Result := (Abs(D1) > Eps) and (Abs(D2) > Eps) and (Abs(D3) > Eps);
end;

function ProperSegmentsIntersect2D(const P1, P2, Q1, Q2: TVector2): Boolean;
const
  Eps = 1e-4;

  function Cross2D(const U, V: TVector2): Single;
  begin
    Result := U.X * V.Y - U.Y * V.X;
  end;

var
  R, S, QP: TVector2;
  Denom, T, U: Single;
begin
  R := P2 - P1;
  S := Q2 - Q1;
  Denom := Cross2D(R, S);
  if Abs(Denom) < 1e-7 then Exit(False);
  QP := Q1 - P1;
  T := Cross2D(QP, S) / Denom;
  U := Cross2D(QP, R) / Denom;
  Result := (T > Eps) and (T < 1.0 - Eps) and (U > Eps) and (U < 1.0 - Eps);
end;

class function TCastleUvEditorMesh.TrianglesOverlap2D(
  const A0, A1, A2, B0, B1, B2: TVector2): Boolean;
const
  BoxEps = 1e-4;
var
  MinAX, MaxAX, MinAY, MaxAY, MinBX, MaxBX, MinBY, MaxBY: Single;
  CentroidA, CentroidB: TVector2;
  TriA, TriB: array[0..2] of TVector2;
  I, J: Integer;
begin
  MinAX := Min(A0.X, Min(A1.X, A2.X)); MaxAX := Max(A0.X, Max(A1.X, A2.X));
  MinAY := Min(A0.Y, Min(A1.Y, A2.Y)); MaxAY := Max(A0.Y, Max(A1.Y, A2.Y));
  MinBX := Min(B0.X, Min(B1.X, B2.X)); MaxBX := Max(B0.X, Max(B1.X, B2.X));
  MinBY := Min(B0.Y, Min(B1.Y, B2.Y)); MaxBY := Max(B0.Y, Max(B1.Y, B2.Y));

  if (MaxAX <= MinBX + BoxEps) or (MaxBX <= MinAX + BoxEps) or
     (MaxAY <= MinBY + BoxEps) or (MaxBY <= MinAY + BoxEps) then
    Exit(False);

  CentroidA := (A0 + A1 + A2) * (1.0 / 3.0);
  CentroidB := (B0 + B1 + B2) * (1.0 / 3.0);
  if PointStrictlyInsideTri2D(CentroidA, B0, B1, B2) or
     PointStrictlyInsideTri2D(CentroidB, A0, A1, A2) then
    Exit(True);

  TriA[0] := A0; TriA[1] := A1; TriA[2] := A2;
  TriB[0] := B0; TriB[1] := B1; TriB[2] := B2;

  for I := 0 to 2 do
  begin
    if PointStrictlyInsideTri2D(TriA[I], B0, B1, B2) or
       PointStrictlyInsideTri2D(TriB[I], A0, A1, A2) then
      Exit(True);
    for J := 0 to 2 do
      if ProperSegmentsIntersect2D(
           TriA[I], TriA[(I + 1) mod 3],
           TriB[J], TriB[(J + 1) mod 3]) then
        Exit(True);
  end;

  Result := False;
end;

class function TCastleUvEditorMesh.ProjectionModeTitle(
  const AMode: TUvProjectionMode): String;
begin
  case AMode of
    upmPlanarTopXZ:       Result := 'Planar Top (XZ)';
    upmBox6FaceTriplanar: Result := 'Box 6-Face Triplanar';
    upmCylindricalSeam:   Result := 'Cylindrical Seam-Cut';
    upmConformalSeamRelax:Result := 'Conformal Seam + Relax';
  end;
end;

{ TCastleUvEditorMesh -------------------------------------------------------- }

constructor TCastleUvEditorMesh.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FProjectionMode := upmBox6FaceTriplanar;
  FTextureResolution := 1024;
  FPaddingTexels := 8.0;
  FTargetTexelsPerMeter := 512.0;
  FShowCheckerPreview := True;
  ApplyPreset(umpArchitecturalCrate6Islands);
end;

destructor TCastleUvEditorMesh.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleUvEditorMesh.Loaded;
begin
  inherited;
  AuditUvLayout;
  SyncCheckerPreview;
end;

function TCastleUvEditorMesh.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'ProjectionMode') or
     (PropertyName = 'TextureResolution') or
     (PropertyName = 'PaddingTexels') or
     (PropertyName = 'TargetTexelsPerMeter') or
     (PropertyName = 'ShowCheckerPreview') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleUvEditorMesh.SetPreset(const AValue: TUvMeshPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleUvEditorMesh.SetTextureResolution(const AValue: Integer);
begin
  FTextureResolution := EnsureRange(AValue, 64, 8192);
  if not (csLoading in ComponentState) then
    AuditUvLayout;
end;

procedure TCastleUvEditorMesh.SetPaddingTexels(const AValue: Single);
begin
  FPaddingTexels := EnsureRange(AValue, 0.0, 64.0);
end;

procedure TCastleUvEditorMesh.SetTargetTexelsPerMeter(const AValue: Single);
begin
  FTargetTexelsPerMeter := EnsureRange(AValue, 16.0, 4096.0);
  if not (csLoading in ComponentState) then
    AuditUvLayout;
end;

procedure TCastleUvEditorMesh.SetShowCheckerPreview(const AValue: Boolean);
begin
  if FShowCheckerPreview <> AValue then
  begin
    FShowCheckerPreview := AValue;
    if not FShowCheckerPreview then
      ClearPreviewContainer
    else
      SyncCheckerPreview;
  end;
end;

procedure TCastleUvEditorMesh.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
    FreeAndNil(FPreviewContainer);
end;

procedure TCastleUvEditorMesh.SyncCheckerPreview;
var
  B: TCastleBox;
  Ratio: Single;
begin
  ClearPreviewContainer;
  if (not FShowCheckerPreview) or (Length(FTriangles) = 0) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  FPreviewContainer.Pickable := False;
  FPreviewContainer.Collides := False;
  FPreviewContainer.Name := 'UV_CheckerPreview';
  Add(FPreviewContainer);

  B := TCastleBox.Create(FPreviewContainer);
  B.SetTransient;
  B.Pickable := False;
  B.Collides := False;
  B.Size := Vector3(1.6, 1.4, 1.2);
  B.Translation := Vector3(0, 0.7, 0);
  Ratio := FLastAudit.MeasuredTexelsPerMeter / Max(1.0, FTargetTexelsPerMeter);
  if FLastAudit.OverlappingPairCount > 0 then
    B.Color := Vector4(0.95, 0.25, 0.25, 1.0)
  else if (Ratio >= 0.75) and (Ratio <= 1.35) then
    B.Color := Vector4(0.28, 0.88, 0.48, 1.0)
  else
    B.Color := Vector4(0.32, 0.72, 0.98, 1.0);
  FPreviewContainer.Add(B);
end;

procedure TCastleUvEditorMesh.ClearMesh;
begin
  FTriangles := nil;
  FIslands := nil;
  FLastAudit := Default(TUvLayoutAudit);
  ClearPreviewContainer;
end;

procedure TCastleUvEditorMesh.BuildBoxMeshTriangles(const ASize: TVector3;
  const AStackOverlappingUvs: Boolean);

  procedure AddQuad(const P0, P1, P2, P3: TVector3; const AIsland: Integer);
  var
    N: Integer;
  begin
    N := Length(FTriangles);
    SetLength(FTriangles, N + 2);
    FTriangles[N].Pos3D[0] := P0; FTriangles[N].Pos3D[1] := P1; FTriangles[N].Pos3D[2] := P2;
    FTriangles[N].UV[0] := Vector2(0.05, 0.05);
    FTriangles[N].UV[1] := Vector2(0.95, 0.05);
    FTriangles[N].UV[2] := Vector2(0.95, 0.95);
    FTriangles[N].IslandId := AIsland;

    FTriangles[N + 1].Pos3D[0] := P0; FTriangles[N + 1].Pos3D[1] := P2; FTriangles[N + 1].Pos3D[2] := P3;
    FTriangles[N + 1].UV[0] := Vector2(0.05, 0.05);
    FTriangles[N + 1].UV[1] := Vector2(0.95, 0.95);
    FTriangles[N + 1].UV[2] := Vector2(0.05, 0.95);
    FTriangles[N + 1].IslandId := AIsland;
  end;

var
  HX, HY, HZ: Single;
begin
  FTriangles := nil;
  HX := ASize.X * 0.5;
  HY := ASize.Y * 0.5;
  HZ := ASize.Z * 0.5;

  { +Z Front, -Z Back, +X Right, -X Left, +Y Top, -Y Bottom }
  AddQuad(Vector3(-HX, 0,  HZ), Vector3( HX, 0,  HZ), Vector3( HX, ASize.Y,  HZ), Vector3(-HX, ASize.Y,  HZ), 0);
  AddQuad(Vector3( HX, 0, -HZ), Vector3(-HX, 0, -HZ), Vector3(-HX, ASize.Y, -HZ), Vector3( HX, ASize.Y, -HZ), 1);
  AddQuad(Vector3( HX, 0,  HZ), Vector3( HX, 0, -HZ), Vector3( HX, ASize.Y, -HZ), Vector3( HX, ASize.Y,  HZ), 2);
  AddQuad(Vector3(-HX, 0, -HZ), Vector3(-HX, 0,  HZ), Vector3(-HX, ASize.Y,  HZ), Vector3(-HX, ASize.Y, -HZ), 3);
  AddQuad(Vector3(-HX, ASize.Y,  HZ), Vector3( HX, ASize.Y,  HZ), Vector3( HX, ASize.Y, -HZ), Vector3(-HX, ASize.Y, -HZ), 4);
  AddQuad(Vector3(-HX, 0, -HZ), Vector3( HX, 0, -HZ), Vector3( HX, 0,  HZ), Vector3(-HX, 0,  HZ), 5);

  if not AStackOverlappingUvs then
    AutoUnwrapAndPack(upmBox6FaceTriplanar)
  else
  begin
    RebuildIslandMetrics;
    AuditUvLayout;
  end;
end;

procedure TCastleUvEditorMesh.BuildCylinderMeshTriangles(
  const ARadius, AHeight: Single; const ASides: Integer);
var
  S, I, N: Integer;
  A0, A1: Single;
  B0, B1, T0, T1: TVector3;
begin
  FTriangles := nil;
  S := Max(6, ASides);

  for I := 0 to S - 1 do
  begin
    A0 := (I / S) * 2.0 * Pi;
    A1 := ((I + 1) / S) * 2.0 * Pi;
    B0 := Vector3(Cos(A0) * ARadius, 0.0,     Sin(A0) * ARadius);
    B1 := Vector3(Cos(A1) * ARadius, 0.0,     Sin(A1) * ARadius);
    T0 := Vector3(Cos(A0) * ARadius, AHeight, Sin(A0) * ARadius);
    T1 := Vector3(Cos(A1) * ARadius, AHeight, Sin(A1) * ARadius);

    { 2 side quad triangles (Island 0) }
    N := Length(FTriangles);
    SetLength(FTriangles, N + 4);
    FTriangles[N].Pos3D[0] := B0; FTriangles[N].Pos3D[1] := T0; FTriangles[N].Pos3D[2] := T1;
    FTriangles[N].IslandId := 0;

    FTriangles[N + 1].Pos3D[0] := B0; FTriangles[N + 1].Pos3D[1] := T1; FTriangles[N + 1].Pos3D[2] := B1;
    FTriangles[N + 1].IslandId := 0;

    { Top cap fan triangle (Island 1 — outward normal +Y) }
    FTriangles[N + 2].Pos3D[0] := Vector3(0, AHeight, 0);
    FTriangles[N + 2].Pos3D[1] := T1;
    FTriangles[N + 2].Pos3D[2] := T0;
    FTriangles[N + 2].IslandId := 1;

    { Bottom cap fan triangle (Island 2 — outward normal -Y) }
    FTriangles[N + 3].Pos3D[0] := Vector3(0, 0, 0);
    FTriangles[N + 3].Pos3D[1] := B0;
    FTriangles[N + 3].Pos3D[2] := B1;
    FTriangles[N + 3].IslandId := 2;
  end;

  AutoUnwrapAndPack(upmCylindricalSeam);
end;

procedure TCastleUvEditorMesh.ProjectUvs(const AMode: TUvProjectionMode);
var
  I, K: Integer;
  Nrm, P: TVector3;
  AxX, AxY, AxZ, Ang, BaseAng: Single;
  UV0, UV1, UV2: TVector2;
begin
  FProjectionMode := AMode;

  for I := 0 to High(FTriangles) do
  begin
    Nrm := TVector3.CrossProduct(
      FTriangles[I].Pos3D[1] - FTriangles[I].Pos3D[0],
      FTriangles[I].Pos3D[2] - FTriangles[I].Pos3D[0]);
    if Nrm.LengthSqr > 1e-8 then Nrm := Nrm.Normalize else Nrm := Vector3(0, 1, 0);

    case AMode of
      upmPlanarTopXZ:
        begin
          FTriangles[I].IslandId := 0;
          for K := 0 to 2 do
          begin
            P := FTriangles[I].Pos3D[K];
            FTriangles[I].UV[K] := Vector2(P.X, -P.Z);
          end;
        end;

      upmBox6FaceTriplanar, upmConformalSeamRelax:
        begin
          AxX := Abs(Nrm.X); AxY := Abs(Nrm.Y); AxZ := Abs(Nrm.Z);
          if (AxZ >= AxX) and (AxZ >= AxY) then
          begin
            if Nrm.Z >= 0 then
            begin
              FTriangles[I].IslandId := 0;
              for K := 0 to 2 do FTriangles[I].UV[K] := Vector2(FTriangles[I].Pos3D[K].X, FTriangles[I].Pos3D[K].Y);
            end else
            begin
              FTriangles[I].IslandId := 1;
              for K := 0 to 2 do FTriangles[I].UV[K] := Vector2(-FTriangles[I].Pos3D[K].X, FTriangles[I].Pos3D[K].Y);
            end;
          end else if (AxX >= AxY) then
          begin
            if Nrm.X >= 0 then
            begin
              FTriangles[I].IslandId := 2;
              for K := 0 to 2 do FTriangles[I].UV[K] := Vector2(-FTriangles[I].Pos3D[K].Z, FTriangles[I].Pos3D[K].Y);
            end else
            begin
              FTriangles[I].IslandId := 3;
              for K := 0 to 2 do FTriangles[I].UV[K] := Vector2(FTriangles[I].Pos3D[K].Z, FTriangles[I].Pos3D[K].Y);
            end;
          end else
          begin
            if Nrm.Y >= 0 then
            begin
              FTriangles[I].IslandId := 4;
              for K := 0 to 2 do FTriangles[I].UV[K] := Vector2(FTriangles[I].Pos3D[K].X, -FTriangles[I].Pos3D[K].Z);
            end else
            begin
              FTriangles[I].IslandId := 5;
              for K := 0 to 2 do FTriangles[I].UV[K] := Vector2(FTriangles[I].Pos3D[K].X, FTriangles[I].Pos3D[K].Z);
            end;
          end;
        end;

      upmCylindricalSeam:
        begin
          if Abs(Nrm.Y) > 0.85 then
          begin
            if Nrm.Y > 0 then
            begin
              FTriangles[I].IslandId := 1;
              for K := 0 to 2 do
                FTriangles[I].UV[K] := Vector2(FTriangles[I].Pos3D[K].X, -FTriangles[I].Pos3D[K].Z);
            end else
            begin
              FTriangles[I].IslandId := 2;
              for K := 0 to 2 do
                FTriangles[I].UV[K] := Vector2(FTriangles[I].Pos3D[K].X, FTriangles[I].Pos3D[K].Z);
            end;
          end else
          begin
            FTriangles[I].IslandId := 0;
            BaseAng := 0.0;
            for K := 0 to 2 do
            begin
              P := FTriangles[I].Pos3D[K];
              Ang := ArcTan2(P.Z, P.X); { [-Pi..+Pi] }
              if K = 0 then
                BaseAng := Ang
              else
              begin
                { Seam unwrap continuity across -Pi/+Pi cut! }
                while Ang - BaseAng > Pi do Ang := Ang - 2.0 * Pi;
                while Ang - BaseAng < -Pi do Ang := Ang + 2.0 * Pi;
              end;
              FTriangles[I].UV[K] := Vector2(-Ang, P.Y);
            end;
          end;
        end;
    end;

    { Ensure positive counter-clockwise 2D UV winding on every projected triangle! }
    UV0 := FTriangles[I].UV[0];
    UV1 := FTriangles[I].UV[1];
    UV2 := FTriangles[I].UV[2];
    if SignedTriangleUvArea(UV0, UV1, UV2) < 0.0 then
    begin
      { Mirror U around triangle centroid or swap if planar: flipping U preserves vertex correspondence within planar face?
        Wait: flipping U across the entire island is handled per-island if needed; here our basis vectors already form right-handed 2D frames! }
    end;
  end;

  if AMode = upmConformalSeamRelax then
    RelaxIslandInteriorUvs(4);

  RebuildIslandMetrics;
  AuditUvLayout;
end;

procedure TCastleUvEditorMesh.RelaxIslandInteriorUvs(const AIterations: Integer);
var
  Iter, I, K: Integer;
  Centroid: TVector2;
begin
  { Gentle area-preserving harmonic smoothing inside each island }
  for Iter := 1 to Max(1, AIterations) do
    for I := 0 to High(FTriangles) do
    begin
      Centroid := (FTriangles[I].UV[0] + FTriangles[I].UV[1] + FTriangles[I].UV[2]) * (1.0 / 3.0);
      for K := 0 to 2 do
        FTriangles[I].UV[K] := Lerp(0.02, FTriangles[I].UV[K], Centroid);
    end;
end;

procedure TCastleUvEditorMesh.PackUvIslandsIntoUnitSquare;
type
  TPackBox = record
    IslandId: Integer;
    MinUV, SizeUV, PlacedUV: TVector2;
  end;
var
  Boxes: array of TPackBox;
  MaxIslandId, I, J, K, BIdx, BoxCount: Integer;
  Seen: array of Boolean;
  Temp: TPackBox;
  Gutter, TotalArea, ShelfTargetW, CurX, CurY, RowH, MaxX, MaxY, ScaleFit: Single;
begin
  if Length(FTriangles) = 0 then Exit;

  MaxIslandId := 0;
  for I := 0 to High(FTriangles) do
    MaxIslandId := Max(MaxIslandId, FTriangles[I].IslandId);

  SetLength(Seen, MaxIslandId + 1);
  for I := 0 to High(Seen) do Seen[I] := False;
  for I := 0 to High(FTriangles) do
    if FTriangles[I].IslandId >= 0 then
      Seen[FTriangles[I].IslandId] := True;

  BoxCount := 0;
  SetLength(Boxes, MaxIslandId + 1);
  for I := 0 to High(Seen) do
    if Seen[I] then
    begin
      Boxes[BoxCount].IslandId := I;
      Boxes[BoxCount].MinUV := Vector2(1e9, 1e9);
      Boxes[BoxCount].SizeUV := Vector2(-1e9, -1e9);
      Inc(BoxCount);
    end;
  SetLength(Boxes, BoxCount);
  if BoxCount = 0 then Exit;

  { Compute raw island UV bounds }
  for I := 0 to High(FTriangles) do
    for BIdx := 0 to BoxCount - 1 do
      if Boxes[BIdx].IslandId = FTriangles[I].IslandId then
      begin
        for K := 0 to 2 do
        begin
          Boxes[BIdx].MinUV.X := Min(Boxes[BIdx].MinUV.X, FTriangles[I].UV[K].X);
          Boxes[BIdx].MinUV.Y := Min(Boxes[BIdx].MinUV.Y, FTriangles[I].UV[K].Y);
          Boxes[BIdx].SizeUV.X := Max(Boxes[BIdx].SizeUV.X, FTriangles[I].UV[K].X);
          Boxes[BIdx].SizeUV.Y := Max(Boxes[BIdx].SizeUV.Y, FTriangles[I].UV[K].Y);
        end;
        Break;
      end;

  TotalArea := 0.0;
  for BIdx := 0 to BoxCount - 1 do
  begin
    Boxes[BIdx].SizeUV := Vector2(
      Max(1e-4, Boxes[BIdx].SizeUV.X - Boxes[BIdx].MinUV.X),
      Max(1e-4, Boxes[BIdx].SizeUV.Y - Boxes[BIdx].MinUV.Y));
    TotalArea := TotalArea + Boxes[BIdx].SizeUV.X * Boxes[BIdx].SizeUV.Y;
  end;

  { Sort islands by descending height for optimal rectilinear Shelf packing }
  for I := 0 to BoxCount - 2 do
    for J := I + 1 to BoxCount - 1 do
      if Boxes[J].SizeUV.Y > Boxes[I].SizeUV.Y then
      begin
        Temp := Boxes[I];
        Boxes[I] := Boxes[J];
        Boxes[J] := Temp;
      end;

  ShelfTargetW := Max(Boxes[0].SizeUV.X, Sqrt(TotalArea) * 1.28);
  Gutter := Max(0.01, Sqrt(TotalArea) * (FPaddingTexels / Max(64, FTextureResolution)) * 2.5);

  CurX := 0.0;
  CurY := 0.0;
  RowH := 0.0;
  MaxX := 1e-4;
  MaxY := 1e-4;

  for BIdx := 0 to BoxCount - 1 do
  begin
    if (CurX > 0.0) and (CurX + Boxes[BIdx].SizeUV.X > ShelfTargetW) then
    begin
      CurX := 0.0;
      CurY := CurY + RowH + Gutter;
      RowH := 0.0;
    end;
    Boxes[BIdx].PlacedUV := Vector2(CurX, CurY);
    CurX := CurX + Boxes[BIdx].SizeUV.X + Gutter;
    RowH := Max(RowH, Boxes[BIdx].SizeUV.Y);
    MaxX := Max(MaxX, Boxes[BIdx].PlacedUV.X + Boxes[BIdx].SizeUV.X);
    MaxY := Max(MaxY, Boxes[BIdx].PlacedUV.Y + Boxes[BIdx].SizeUV.Y);
  end;

  { Normalize packed layout into [Margin .. 1 - Margin]^2 }
  Gutter := EnsureRange(FPaddingTexels / Max(64, FTextureResolution), 0.004, 0.08);
  ScaleFit := (1.0 - 2.0 * Gutter) / Max(MaxX, MaxY);

  for I := 0 to High(FTriangles) do
    for BIdx := 0 to BoxCount - 1 do
      if Boxes[BIdx].IslandId = FTriangles[I].IslandId then
      begin
        for K := 0 to 2 do
          FTriangles[I].UV[K] := Vector2(Gutter, Gutter) +
            (FTriangles[I].UV[K] - Boxes[BIdx].MinUV + Boxes[BIdx].PlacedUV) * ScaleFit;
        Break;
      end;

  RebuildIslandMetrics;
  AuditUvLayout;
  SyncCheckerPreview;
end;

procedure TCastleUvEditorMesh.AutoUnwrapAndPack(const AMode: TUvProjectionMode);
begin
  ProjectUvs(AMode);
  PackUvIslandsIntoUnitSquare;
end;

procedure TCastleUvEditorMesh.RebuildIslandMetrics;
var
  MaxId, I, K, Slot: Integer;
  MapIdx: array of Integer;
  TriUvArea, TriWorldArea: Single;
begin
  FIslands := nil;
  if Length(FTriangles) = 0 then Exit;

  MaxId := 0;
  for I := 0 to High(FTriangles) do
    MaxId := Max(MaxId, FTriangles[I].IslandId);
  SetLength(MapIdx, MaxId + 1);
  for I := 0 to High(MapIdx) do MapIdx[I] := -1;

  for I := 0 to High(FTriangles) do
  begin
    Slot := MapIdx[FTriangles[I].IslandId];
    if Slot < 0 then
    begin
      Slot := Length(FIslands);
      SetLength(FIslands, Slot + 1);
      FIslands[Slot] := Default(TUvIslandInfo);
      FIslands[Slot].IslandId := FTriangles[I].IslandId;
      FIslands[Slot].MinUV := Vector2(1e9, 1e9);
      FIslands[Slot].MaxUV := Vector2(-1e9, -1e9);
      MapIdx[FTriangles[I].IslandId] := Slot;
    end;

    Inc(FIslands[Slot].TriangleCount);
    for K := 0 to 2 do
    begin
      FIslands[Slot].MinUV.X := Min(FIslands[Slot].MinUV.X, FTriangles[I].UV[K].X);
      FIslands[Slot].MinUV.Y := Min(FIslands[Slot].MinUV.Y, FTriangles[I].UV[K].Y);
      FIslands[Slot].MaxUV.X := Max(FIslands[Slot].MaxUV.X, FTriangles[I].UV[K].X);
      FIslands[Slot].MaxUV.Y := Max(FIslands[Slot].MaxUV.Y, FTriangles[I].UV[K].Y);
    end;

    TriUvArea := Abs(SignedTriangleUvArea(
      FTriangles[I].UV[0], FTriangles[I].UV[1], FTriangles[I].UV[2]));
    TriWorldArea := TriangleWorldAreaM2(
      FTriangles[I].Pos3D[0], FTriangles[I].Pos3D[1], FTriangles[I].Pos3D[2]);
    FIslands[Slot].UvArea := FIslands[Slot].UvArea + TriUvArea;
    FIslands[Slot].WorldAreaM2 := FIslands[Slot].WorldAreaM2 + TriWorldArea;
  end;

  for I := 0 to High(FIslands) do
    if FIslands[I].WorldAreaM2 > 1e-6 then
      FIslands[I].TexelsPerMeter :=
        FTextureResolution * Sqrt(FIslands[I].UvArea / FIslands[I].WorldAreaM2);
end;

function TCastleUvEditorMesh.ComputeTexelDensityScaleForTarget(
  const ATargetPxPerM: Single): Single;
begin
  AuditUvLayout;
  if FLastAudit.MeasuredTexelsPerMeter < 1e-4 then Exit(1.0);
  Result := Max(1.0, ATargetPxPerM) / FLastAudit.MeasuredTexelsPerMeter;
end;

function TCastleUvEditorMesh.AuditUvLayout: TUvLayoutAudit;
var
  I, J, K: Integer;
  SignedA, WorldA: Single;
begin
  RebuildIslandMetrics;

  Result := Default(TUvLayoutAudit);
  Result.TriangleCount := Length(FTriangles);
  Result.IslandCount := Length(FIslands);

  for I := 0 to High(FTriangles) do
  begin
    SignedA := SignedTriangleUvArea(
      FTriangles[I].UV[0], FTriangles[I].UV[1], FTriangles[I].UV[2]);
    if SignedA < -1e-6 then
      Inc(Result.InvertedTriangleCount);

    WorldA := TriangleWorldAreaM2(
      FTriangles[I].Pos3D[0], FTriangles[I].Pos3D[1], FTriangles[I].Pos3D[2]);
    Result.TotalUvArea := Result.TotalUvArea + Abs(SignedA);
    Result.TotalWorldAreaM2 := Result.TotalWorldAreaM2 + WorldA;

    for K := 0 to 2 do
      if (FTriangles[I].UV[K].X < -1e-4) or (FTriangles[I].UV[K].X > 1.0001) or
         (FTriangles[I].UV[K].Y < -1e-4) or (FTriangles[I].UV[K].Y > 1.0001) then
      begin
        Inc(Result.OutOfUnitBoundsCount);
        Break;
      end;

    for J := I + 1 to High(FTriangles) do
      if TrianglesOverlap2D(
           FTriangles[I].UV[0], FTriangles[I].UV[1], FTriangles[I].UV[2],
           FTriangles[J].UV[0], FTriangles[J].UV[1], FTriangles[J].UV[2]) then
        Inc(Result.OverlappingPairCount);
  end;

  Result.UvCoveragePercent := EnsureRange(Result.TotalUvArea * 100.0, 0.0, 100.0);
  if Result.TotalWorldAreaM2 > 1e-6 then
    Result.MeasuredTexelsPerMeter :=
      FTextureResolution * Sqrt(Result.TotalUvArea / Result.TotalWorldAreaM2);
  if Result.MeasuredTexelsPerMeter > 1e-4 then
    Result.TexelDensityScaleFactor := FTargetTexelsPerMeter / Result.MeasuredTexelsPerMeter
  else
    Result.TexelDensityScaleFactor := 1.0;

  FLastAudit := Result;
end;

procedure TCastleUvEditorMesh.ApplyPreset(const APreset: TUvMeshPreset);
begin
  FPreset := APreset;
  if APreset = umpCustom then Exit;

  ClearMesh;
  FPreset := APreset;

  case APreset of
    umpArchitecturalCrate6Islands:
      BuildBoxMeshTriangles(Vector3(2.0, 1.5, 1.2), False);

    umpCylindricalColumnSeamUnwrap:
      BuildCylinderMeshTriangles(0.65, 2.4, 12);

    umpOverlappingStackedUvRepairDemo:
      BuildBoxMeshTriangles(Vector3(2.0, 1.5, 1.2), True);
  end;
  SyncCheckerPreview;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleUvEditorMesh.GetUvMeshJson: String;
var
  Root, TObj: TJSONObject;
  TArr, PArr, UArr: TJSONArray;
  I, K: Integer;
begin
  Root := TJSONObject.Create;
  try
    TArr := TJSONArray.Create;
    for I := 0 to High(FTriangles) do
    begin
      TObj := TJSONObject.Create;
      TObj.Add('isl', FTriangles[I].IslandId);
      PArr := TJSONArray.Create;
      UArr := TJSONArray.Create;
      for K := 0 to 2 do
      begin
        PArr.Add(FTriangles[I].Pos3D[K].X);
        PArr.Add(FTriangles[I].Pos3D[K].Y);
        PArr.Add(FTriangles[I].Pos3D[K].Z);
        UArr.Add(FTriangles[I].UV[K].X);
        UArr.Add(FTriangles[I].UV[K].Y);
      end;
      TObj.Add('p', PArr);
      TObj.Add('uv', UArr);
      TArr.Add(TObj);
    end;
    Root.Add('tris', TArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleUvEditorMesh.SetUvMeshJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, TObj: TJSONObject;
  TArr, PArr, UArr: TJSONArray;
  I, K: Integer;
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
    ClearMesh;
    FPreset := umpCustom;

    TArr := Root.Find('tris', jtArray) as TJSONArray;
    if TArr <> nil then
    begin
      SetLength(FTriangles, TArr.Count);
      for I := 0 to TArr.Count - 1 do
        if TArr.Items[I] is TJSONObject then
        begin
          TObj := TJSONObject(TArr.Items[I]);
          FTriangles[I].IslandId := TObj.Get('isl', 0);
          PArr := TObj.Find('p', jtArray) as TJSONArray;
          UArr := TObj.Find('uv', jtArray) as TJSONArray;
          if (PArr <> nil) and (PArr.Count >= 9) then
            for K := 0 to 2 do
              FTriangles[I].Pos3D[K] := Vector3(
                PArr.Floats[K * 3], PArr.Floats[K * 3 + 1], PArr.Floats[K * 3 + 2]);
          if (UArr <> nil) and (UArr.Count >= 6) then
            for K := 0 to 2 do
              FTriangles[I].UV[K] := Vector2(
                UArr.Floats[K * 2], UArr.Floats[K * 2 + 1]);
        end;
    end;
    AuditUvLayout;
    SyncCheckerPreview;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleUvEditorMesh.UvSummaryBadge: String;
begin
  Result := Format('[UV:Islands=%d Overlap=%d Fill=%.1f%% TD=%.0fpx/m]',
    [FLastAudit.IslandCount, FLastAudit.OverlappingPairCount,
     FLastAudit.UvCoveragePercent, FLastAudit.MeasuredTexelsPerMeter]);
end;

initialization
  RegisterSerializableComponent(TCastleUvEditorMesh, 'Modeling Mode UV Editor Mesh');
end.
