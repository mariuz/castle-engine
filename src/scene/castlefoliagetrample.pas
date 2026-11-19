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

{ Interactive 2D vector bend field for tall grass, wheat, reeds, and alien
  undergrowth with radial character-walk crush, grenade shockwave ring flatten,
  length-preserving stalk kinematics, and damped Hookean elastic spring-back
  recovery (Phase 393). }
unit CastleFoliageTrample;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset botanical stiffness, stalk height, and color profiles. }
  TFoliageTramplePreset = (
    ftpGoldenWheatField,
    ftpSwampCattailReeds,
    ftpAlienBioluminescentFerns
  );

  { Bilinearly sampled stalk bend vector and length-preserving 3D tip offset. }
  TFoliageBendSample = record
    BendXZ: TVector2;
    BendMagnitude01: Single;
    TiltAngleDeg: Single;
    TipLocalOffset: TVector3;
  end;

  { Scene transform managing a 2D (BendX, BendZ) + angular-velocity grid for
    interactive foliage parting, blast flattening, and elastic recovery. }
  TCastleFoliageTrampleField = class(TCastleTransform)
  private
    FPreset: TFoliageTramplePreset;
    FFieldExtentMeters: Single;
    FGridResolution: Integer;
    FStalkHeightMeters: Single;
    FMaxTiltDeg: Single;
    FSpringStiffness: Single;
    FSpringDamping: Single;
    FShowPreview: Boolean;
    FBendGrid: array of TVector2;
    FVelGrid: array of TVector2;
    FTrampledCellCount: Integer;
    FMaxActiveTiltDeg: Single;
    FPreviewRoot: TCastleTransform;
    FPreviewStalksScene: TCastleScene;
    procedure SetPreset(const AValue: TFoliageTramplePreset);
    procedure SetGridResolution(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
    procedure EnsureGridAllocated;
    procedure RecomputeStats;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TFoliageTramplePreset);
    procedure ResetField;

    { Crush and part stalks radially outward around AWorldFootPos. }
    procedure StampCharacterWalkCrush(const AWorldFootPos: TVector3;
      const ARadiusMeters, AStrength01: Single);

    { Flatten an outward radial ring of stalks from an explosion epicenter. }
    procedure TriggerShockwaveBlast(const AWorldEpicenter: TVector3;
      const ABlastRadiusMeters, AImpulseStrength: Single);

    { Step Hookean damped harmonic stalk recovery across the 2D grid. }
    procedure StepElasticSpringBack(const ADtSec: Single);

    { Bilinearly sample stalk tilt and length-preserving 3D tip offset at AWorldPos. }
    function SampleBendAtWorld(const AWorldPos: TVector3): TFoliageBendSample;

    procedure RebuildPreview;
    procedure ClearPreview;
    function TrampleSummaryBadge: String;

    property TrampledCellCount: Integer read FTrampledCellCount;
    property MaxActiveTiltDeg: Single read FMaxActiveTiltDeg;
  published
    property Preset: TFoliageTramplePreset
      read FPreset write SetPreset default ftpGoldenWheatField;
    property FieldExtentMeters: Single
      read FFieldExtentMeters write FFieldExtentMeters;
    property GridResolution: Integer
      read FGridResolution write SetGridResolution default 24;
    property StalkHeightMeters: Single
      read FStalkHeightMeters write FStalkHeightMeters;
    property MaxTiltDeg: Single
      read FMaxTiltDeg write FMaxTiltDeg;
    property SpringStiffness: Single
      read FSpringStiffness write FSpringStiffness;
    property SpringDamping: Single
      read FSpringDamping write FSpringDamping;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function FoliageTramplePresetToString(const APreset: TFoliageTramplePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function FoliageTramplePresetToString(const APreset: TFoliageTramplePreset): String;
begin
  case APreset of
    ftpGoldenWheatField:        Result := 'GoldenWheatField';
    ftpSwampCattailReeds:       Result := 'SwampCattailReeds';
    ftpAlienBioluminescentFerns: Result := 'AlienBioluminescentFerns';
  end;
end;

{ TCastleFoliageTrampleField ------------------------------------------------- }

constructor TCastleFoliageTrampleField.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGridResolution := 24;
  FShowPreview := True;
  FTrampledCellCount := 0;
  FMaxActiveTiltDeg := 0.0;
  ApplyPreset(ftpGoldenWheatField);
end;

destructor TCastleFoliageTrampleField.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleFoliageTrampleField.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'FieldExtentMeters', 'GridResolution',
       'StalkHeightMeters', 'MaxTiltDeg', 'SpringStiffness',
       'SpringDamping', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleFoliageTrampleField.EnsureGridAllocated;
var
  Total: Integer;
begin
  FGridResolution := Clamped(FGridResolution, 8, 64);
  Total := FGridResolution * FGridResolution;
  if Length(FBendGrid) <> Total then
  begin
    SetLength(FBendGrid, Total);
    SetLength(FVelGrid, Total);
    FillChar(FBendGrid[0], Total * SizeOf(TVector2), 0);
    FillChar(FVelGrid[0], Total * SizeOf(TVector2), 0);
  end;
end;

procedure TCastleFoliageTrampleField.SetPreset(const AValue: TFoliageTramplePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleFoliageTrampleField.SetGridResolution(const AValue: Integer);
var
  ClampedRes: Integer;
begin
  ClampedRes := Clamped(AValue, 8, 64);
  if FGridResolution = ClampedRes then Exit;
  FGridResolution := ClampedRes;
  EnsureGridAllocated;
  RecomputeStats;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleFoliageTrampleField.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleFoliageTrampleField.ApplyPreset(const APreset: TFoliageTramplePreset);
begin
  FPreset := APreset;
  case APreset of
    ftpGoldenWheatField:
      begin
        FFieldExtentMeters := 16.0;
        FStalkHeightMeters := 1.25;
        FMaxTiltDeg := 78.0;
        FSpringStiffness := 11.0;
        FSpringDamping := 4.8;
      end;
    ftpSwampCattailReeds:
      begin
        FFieldExtentMeters := 16.0;
        FStalkHeightMeters := 1.85;
        FMaxTiltDeg := 72.0;
        FSpringStiffness := 5.2;
        FSpringDamping := 3.2;
      end;
    ftpAlienBioluminescentFerns:
      begin
        FFieldExtentMeters := 14.0;
        FStalkHeightMeters := 0.95;
        FMaxTiltDeg := 80.0;
        FSpringStiffness := 22.0;
        FSpringDamping := 6.5;
      end;
  end;
  EnsureGridAllocated;
  RecomputeStats;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleFoliageTrampleField.ResetField;
var
  Total: Integer;
begin
  EnsureGridAllocated;
  Total := Length(FBendGrid);
  if Total > 0 then
  begin
    FillChar(FBendGrid[0], Total * SizeOf(TVector2), 0);
    FillChar(FVelGrid[0], Total * SizeOf(TVector2), 0);
  end;
  FTrampledCellCount := 0;
  FMaxActiveTiltDeg := 0.0;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleFoliageTrampleField.RecomputeStats;
var
  I: Integer;
  Mag, Tilt: Single;
begin
  FTrampledCellCount := 0;
  FMaxActiveTiltDeg := 0.0;
  for I := 0 to High(FBendGrid) do
  begin
    Mag := Clamped(FBendGrid[I].Length, 0.0, 1.0);
    if Mag > 0.03 then
      Inc(FTrampledCellCount);
    Tilt := Mag * FMaxTiltDeg;
    if Tilt > FMaxActiveTiltDeg then
      FMaxActiveTiltDeg := Tilt;
  end;
end;

procedure TCastleFoliageTrampleField.StampCharacterWalkCrush(
  const AWorldFootPos: TVector3; const ARadiusMeters, AStrength01: Single);
var
  InvWT, WT: TMatrix4;
  LocalFoot: TVector3;
  HalfExt, RadSafe, StrSafe, CellX, CellZ, DX, DZ, Dist, Weight, LenNow: Single;
  N, IX, IZ, Idx: Integer;
  OutDir, NewBend: TVector2;
begin
  EnsureGridAllocated;
  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;
  LocalFoot := InvWT.MultPoint(AWorldFootPos);

  N := FGridResolution;
  HalfExt := Max(1.0, FFieldExtentMeters) * 0.5;
  RadSafe := Max(0.15, ARadiusMeters);
  StrSafe := Clamped(AStrength01, 0.0, 1.0);

  for IZ := 0 to N - 1 do
    for IX := 0 to N - 1 do
    begin
      CellX := -HalfExt + ((IX + 0.5) / N) * (2.0 * HalfExt);
      CellZ := -HalfExt + ((IZ + 0.5) / N) * (2.0 * HalfExt);
      DX := CellX - LocalFoot.X;
      DZ := CellZ - LocalFoot.Z;
      Dist := Hypot(DX, DZ);
      if Dist > RadSafe then Continue;

      if Dist < 1e-4 then
        OutDir := Vector2(1.0, 0.0)
      else
        OutDir := Vector2(DX / Dist, DZ / Dist);

      Weight := StrSafe * Sqr(1.0 - (Dist / RadSafe));
      Idx := IZ * N + IX;
      NewBend := FBendGrid[Idx] + OutDir * Weight;
      LenNow := NewBend.Length;
      if LenNow > 1.0 then
        NewBend := NewBend / LenNow;
      FBendGrid[Idx] := NewBend;
    end;

  RecomputeStats;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleFoliageTrampleField.TriggerShockwaveBlast(
  const AWorldEpicenter: TVector3;
  const ABlastRadiusMeters, AImpulseStrength: Single);
var
  InvWT, WT: TMatrix4;
  LocalCenter: TVector3;
  HalfExt, RadSafe, ImpSafe, CellX, CellZ, DX, DZ, Dist, Falloff, LenNow: Single;
  N, IX, IZ, Idx: Integer;
  OutDir, NewBend: TVector2;
begin
  EnsureGridAllocated;
  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;
  LocalCenter := InvWT.MultPoint(AWorldEpicenter);

  N := FGridResolution;
  HalfExt := Max(1.0, FFieldExtentMeters) * 0.5;
  RadSafe := Max(0.3, ABlastRadiusMeters);
  ImpSafe := Max(0.1, AImpulseStrength);

  for IZ := 0 to N - 1 do
    for IX := 0 to N - 1 do
    begin
      CellX := -HalfExt + ((IX + 0.5) / N) * (2.0 * HalfExt);
      CellZ := -HalfExt + ((IZ + 0.5) / N) * (2.0 * HalfExt);
      DX := CellX - LocalCenter.X;
      DZ := CellZ - LocalCenter.Z;
      Dist := Hypot(DX, DZ);
      if Dist > RadSafe then Continue;

      if Dist < 1e-4 then
        OutDir := Vector2(0.0, 1.0)
      else
        OutDir := Vector2(DX / Dist, DZ / Dist);

      Falloff := 1.0 - (Dist / RadSafe);
      Idx := IZ * N + IX;
      NewBend := FBendGrid[Idx] + OutDir * Clamped(Falloff * ImpSafe, 0.0, 1.0);
      LenNow := NewBend.Length;
      if LenNow > 1.0 then
        NewBend := NewBend / LenNow;
      FBendGrid[Idx] := NewBend;
      FVelGrid[Idx] := FVelGrid[Idx] + OutDir * (Falloff * ImpSafe * 2.5);
    end;

  RecomputeStats;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleFoliageTrampleField.StepElasticSpringBack(const ADtSec: Single);
var
  SubSteps, S, I: Integer;
  Dt, KSpring, CDamp, LenB: Single;
  Acc: TVector2;
begin
  EnsureGridAllocated;
  if ADtSec <= 0.0 then Exit;

  SubSteps := Clamped(Ceil(ADtSec / 0.02), 1, 64);
  Dt := ADtSec / SubSteps;
  KSpring := Max(0.2, FSpringStiffness);
  CDamp := Max(0.1, FSpringDamping);

  for S := 1 to SubSteps do
    for I := 0 to High(FBendGrid) do
    begin
      Acc := (FBendGrid[I] * (-KSpring)) + (FVelGrid[I] * (-CDamp));
      FVelGrid[I] := FVelGrid[I] + Acc * Dt;
      FBendGrid[I] := FBendGrid[I] + FVelGrid[I] * Dt;
      LenB := FBendGrid[I].Length;
      if LenB > 1.0 then
        FBendGrid[I] := FBendGrid[I] / LenB
      else if (LenB < 1e-4) and (FVelGrid[I].Length < 1e-4) then
      begin
        FBendGrid[I] := TVector2.Zero;
        FVelGrid[I] := TVector2.Zero;
      end;
    end;

  RecomputeStats;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleFoliageTrampleField.SampleBendAtWorld(
  const AWorldPos: TVector3): TFoliageBendSample;
var
  InvWT, WT: TMatrix4;
  LocalP: TVector3;
  HalfExt, GX, GZ, FX, FZ, Mag, TiltRad, StalkLen, HorizReach: Single;
  N, X0, Z0, X1, Z1: Integer;
  B00, B10, B01, B11, BX0, BX1, BInterp, Dir2: TVector2;
begin
  EnsureGridAllocated;
  Result := Default(TFoliageBendSample);
  StalkLen := Max(0.05, FStalkHeightMeters);

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;
  LocalP := InvWT.MultPoint(AWorldPos);
  HalfExt := Max(1.0, FFieldExtentMeters) * 0.5;

  if (Abs(LocalP.X) > HalfExt) or (Abs(LocalP.Z) > HalfExt) then
  begin
    Result.TipLocalOffset := Vector3(0.0, StalkLen, 0.0);
    Exit;
  end;

  N := FGridResolution;
  GX := Clamped(((LocalP.X + HalfExt) / (2.0 * HalfExt)) * N - 0.5, 0.0, N - 1.0001);
  GZ := Clamped(((LocalP.Z + HalfExt) / (2.0 * HalfExt)) * N - 0.5, 0.0, N - 1.0001);
  X0 := Floor(GX);
  Z0 := Floor(GZ);
  X1 := Min(N - 1, X0 + 1);
  Z1 := Min(N - 1, Z0 + 1);
  FX := GX - X0;
  FZ := GZ - Z0;

  B00 := FBendGrid[Z0 * N + X0];
  B10 := FBendGrid[Z0 * N + X1];
  B01 := FBendGrid[Z1 * N + X0];
  B11 := FBendGrid[Z1 * N + X1];
  BX0 := Lerp(FX, B00, B10);
  BX1 := Lerp(FX, B01, B11);
  BInterp := Lerp(FZ, BX0, BX1);

  Mag := Clamped(BInterp.Length, 0.0, 1.0);
  Result.BendXZ := BInterp;
  Result.BendMagnitude01 := Mag;
  Result.TiltAngleDeg := Mag * FMaxTiltDeg;
  TiltRad := DegToRad(Result.TiltAngleDeg);

  if Mag > 1e-5 then
  begin
    Dir2 := BInterp / Mag;
    HorizReach := StalkLen * Sin(TiltRad);
    Result.TipLocalOffset := Vector3(
      Dir2.X * HorizReach,
      StalkLen * Cos(TiltRad),
      Dir2.Y * HorizReach);
  end else
    Result.TipLocalOffset := Vector3(0.0, StalkLen, 0.0);
end;

procedure TCastleFoliageTrampleField.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewStalksScene := nil;
  end;
end;

procedure TCastleFoliageTrampleField.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  Counts: array of Int32;
  N, IX, IZ, Idx: Integer;
  HalfExt, CellX, CellZ, StalkLen, Mag, TiltRad, HorizReach: Single;
  B, Dir2: TVector2;
  BasePt, TipPt: TVector3;
begin
  if csDestroying in ComponentState then Exit;
  EnsureGridAllocated;
  ClearPreview;
  if not FShowPreview then Exit;

  N := FGridResolution;
  HalfExt := Max(1.0, FFieldExtentMeters) * 0.5;
  StalkLen := Max(0.05, FStalkHeightMeters);

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'FoliageTramplePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  FPreviewStalksScene := TCastleScene.Create(FPreviewRoot);
  FPreviewStalksScene.SetTransient;
  FPreviewStalksScene.Pickable := False;
  FPreviewStalksScene.Collides := False;
  FPreviewRoot.Add(FPreviewStalksScene);

  SetLength(Pts, N * N * 2);
  SetLength(Counts, N * N);
  for IZ := 0 to N - 1 do
    for IX := 0 to N - 1 do
    begin
      Idx := IZ * N + IX;
      CellX := -HalfExt + ((IX + 0.5) / N) * (2.0 * HalfExt);
      CellZ := -HalfExt + ((IZ + 0.5) / N) * (2.0 * HalfExt);
      BasePt := Vector3(CellX, 0.0, CellZ);
      B := FBendGrid[Idx];
      Mag := Clamped(B.Length, 0.0, 1.0);
      if Mag > 1e-5 then
      begin
        Dir2 := B / Mag;
        TiltRad := DegToRad(Mag * FMaxTiltDeg);
        HorizReach := StalkLen * Sin(TiltRad);
        TipPt := BasePt + Vector3(Dir2.X * HorizReach, StalkLen * Cos(TiltRad), Dir2.Y * HorizReach);
      end else
        TipPt := BasePt + Vector3(0.0, StalkLen, 0.0);
      Pts[Idx * 2] := BasePt;
      Pts[Idx * 2 + 1] := TipPt;
      Counts[Idx] := 2;
    end;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  case FPreset of
    ftpGoldenWheatField:         MatNode.EmissiveColor := Vector3(0.92, 0.78, 0.28);
    ftpSwampCattailReeds:        MatNode.EmissiveColor := Vector3(0.36, 0.72, 0.34);
    ftpAlienBioluminescentFerns: MatNode.EmissiveColor := Vector3(0.24, 0.94, 0.88);
  end;
  ShapeNode.Material := MatNode;
  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewStalksScene.Load(RootNode, True);

  Add(FPreviewRoot);
end;

function TCastleFoliageTrampleField.TrampleSummaryBadge: String;
begin
  Result := FormatDot('[Trample:%dx%d Bent=%d Max=%.0fdeg]', [
    FGridResolution, FGridResolution, FTrampledCellCount, FMaxActiveTiltDeg]);
end;

initialization
  RegisterSerializableComponent(TCastleFoliageTrampleField, 'Dynamic Foliage Trample Field');

end.
