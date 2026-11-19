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

{ Directional WorldRay cone splatter & explosion scorch burst emitter with
  grazing-angle elliptical streak elongation (1 / |d . n|), surface-tangent
  alignment, fixed-capacity LRU ring capping, evaporation fade, and transient
  3D decal mark visualization (Phase 395). }
unit CastleSplatterBurst;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors;

type
  { Preset splatter fluid & scorch burst profiles. }
  TSplatterBurstPreset = (
    sbpPaintballNeonSplash,
    sbpGrenadeSootScorch,
    sbpSlimeAcidBurst
  );

  { Individual surface-projected splatter decal mark. }
  TSplatDecalMark = record
    WorldPos: TVector3;
    SurfaceNormal: TVector3;
    StreakTangent: TVector3;
    WidthMeters: Single;
    LengthMeters: Single;
    StreakAspectRatio: Single;
    IncidenceDot: Single;
    RemainingLifetimeSec: Single;
    Alpha01: Single;
  end;

  { Scene transform firing seeded directional WorldRay droplet cones and
    maintaining a bounded ring of surface-stretched splatter decals. }
  TCastleSplatterBurst = class(TCastleTransform)
  private
    FPreset: TSplatterBurstPreset;
    FDropletRayCount: Integer;
    FConeHalfAngleDeg: Single;
    FMaxSprayRangeMeters: Single;
    FBaseDropletRadiusMeters: Single;
    FMaxStreakAspectRatio: Single;
    FMaxActiveSplats: Integer;
    FDecalLifetimeSec: Single;
    FRandomSeed: Integer;
    FShowPreview: Boolean;
    FBurstCounter: Integer;
    FSplats: array of TSplatDecalMark;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TSplatterBurstPreset);
    procedure SetDropletRayCount(const AValue: Integer);
    procedure SetMaxActiveSplats(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TSplatterBurstPreset);
    procedure ClearSplats;

    { Emit a seeded cone of DropletRayCount WorldRay droplets from AOrigin
      around ADirection, stamping grazing-elongated decals onto AWorldRoot. }
    function EmitDirectionalBurst(
      const AWorldRoot: TCastleAbstractRootTransform;
      const AOrigin, ADirection: TVector3): Integer;

    { Decay decal lifetimes by ADtSec and evict fully evaporated splats. }
    procedure StepEvaporationFade(const ADtSec: Single);

    function ActiveSplatCount: Integer;
    function GetSplatMark(const AIndex: Integer): TSplatDecalMark;
    function MeanStreakAspectRatio: Single;
    procedure RebuildPreview;
    procedure ClearPreview;
    function SplatterSummaryBadge: String;
  published
    property Preset: TSplatterBurstPreset
      read FPreset write SetPreset default sbpPaintballNeonSplash;
    property DropletRayCount: Integer
      read FDropletRayCount write SetDropletRayCount default 24;
    property ConeHalfAngleDeg: Single
      read FConeHalfAngleDeg write FConeHalfAngleDeg;
    property MaxSprayRangeMeters: Single
      read FMaxSprayRangeMeters write FMaxSprayRangeMeters;
    property BaseDropletRadiusMeters: Single
      read FBaseDropletRadiusMeters write FBaseDropletRadiusMeters;
    property MaxStreakAspectRatio: Single
      read FMaxStreakAspectRatio write FMaxStreakAspectRatio;
    property MaxActiveSplats: Integer
      read FMaxActiveSplats write SetMaxActiveSplats default 64;
    property DecalLifetimeSec: Single
      read FDecalLifetimeSec write FDecalLifetimeSec;
    property RandomSeed: Integer
      read FRandomSeed write FRandomSeed default 2026;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function SplatterPresetToString(const APreset: TSplatterBurstPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function SplatterPresetToString(const APreset: TSplatterBurstPreset): String;
begin
  case APreset of
    sbpPaintballNeonSplash: Result := 'PaintballNeonSplash';
    sbpGrenadeSootScorch:   Result := 'GrenadeSootScorch';
    sbpSlimeAcidBurst:      Result := 'SlimeAcidBurst';
  end;
end;

{$PUSH}{$Q-}{$R-}
function SplatHash01(const ASeed, ASalt: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(ASeed) * Cardinal(747796405) +
       Cardinal(ASalt + 31) * Cardinal(2891336453) + Cardinal(1013904223);
  H := ((H shr ((H shr 28) + 4)) xor H) * Cardinal(277803737);
  H := (H shr 22) xor H;
  Result := (H and $00FFFFFF) / 16777216.0;
end;
{$POP}

function ExtractSplatSurfaceNormal(const ARayNode: TRayCollisionNode;
  const ARayDirNorm: TVector3): TVector3;
var
  HitItem: TCastleTransform;
  LocalPt, LocalMin, LocalMax, LocalCenter, HalfExt, Rel: TVector3;
  NX, NY, NZ: Single;
  InvWT: TMatrix4;
begin
  Result := -ARayDirNorm;
  HitItem := ARayNode.Item;
  if HitItem = nil then Exit;

  if (ARayNode.Triangle <> nil) and HitItem.HasWorldTransform then
  begin
    Result := HitItem.LocalToWorldDirection(ARayNode.Triangle^.SceneSpace.Normal);
    if Result.LengthSqr > 1e-8 then
    begin
      Result := Result.Normalize;
      if TVector3.DotProduct(Result, ARayDirNorm) > 0.0 then
        Result := -Result;
      Exit;
    end;
  end;

  if not HitItem.LocalBoundingBox.IsEmpty then
  begin
    if HitItem.HasWorldTransform then
      InvWT := HitItem.WorldInverseTransform
    else if not HitItem.Transform.TryInverse(InvWT) then
      InvWT := TMatrix4.Identity;
    LocalPt := InvWT.MultPoint(ARayNode.Point);
    LocalMin := HitItem.LocalBoundingBox.Data[0];
    LocalMax := HitItem.LocalBoundingBox.Data[1];
    LocalCenter := (LocalMin + LocalMax) * 0.5;
    HalfExt := (LocalMax - LocalMin) * 0.5;
    Rel := LocalPt - LocalCenter;
    NX := Abs(Rel.X) / Max(0.0001, HalfExt.X);
    NY := Abs(Rel.Y) / Max(0.0001, HalfExt.Y);
    NZ := Abs(Rel.Z) / Max(0.0001, HalfExt.Z);
    if (NX >= NY) and (NX >= NZ) then
      Result := Vector3(Sign(Rel.X), 0.0, 0.0)
    else if (NY >= NX) and (NY >= NZ) then
      Result := Vector3(0.0, Sign(Rel.Y), 0.0)
    else
      Result := Vector3(0.0, 0.0, Sign(Rel.Z));
    if HitItem.HasWorldTransform then
      Result := HitItem.LocalToWorldDirection(Result)
    else
      Result := HitItem.Transform.MultDirection(Result);
    if Result.LengthSqr > 1e-8 then
      Result := Result.Normalize
    else
      Result := -ARayDirNorm;
    if TVector3.DotProduct(Result, ARayDirNorm) > 0.0 then
      Result := -Result;
  end;
end;

{ TCastleSplatterBurst ------------------------------------------------------- }

constructor TCastleSplatterBurst.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDropletRayCount := 24;
  FMaxActiveSplats := 64;
  FRandomSeed := 2026;
  FShowPreview := True;
  FBurstCounter := 0;
  ApplyPreset(sbpPaintballNeonSplash);
end;

destructor TCastleSplatterBurst.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleSplatterBurst.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'DropletRayCount', 'ConeHalfAngleDeg',
       'MaxSprayRangeMeters', 'BaseDropletRadiusMeters',
       'MaxStreakAspectRatio', 'MaxActiveSplats',
       'DecalLifetimeSec', 'RandomSeed', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSplatterBurst.SetPreset(const AValue: TSplatterBurstPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleSplatterBurst.SetDropletRayCount(const AValue: Integer);
begin
  FDropletRayCount := Clamped(AValue, 1, 128);
end;

procedure TCastleSplatterBurst.SetMaxActiveSplats(const AValue: Integer);
var
  Keep, Shift, I: Integer;
begin
  FMaxActiveSplats := Clamped(AValue, 4, 256);
  if Length(FSplats) > FMaxActiveSplats then
  begin
    Keep := FMaxActiveSplats;
    Shift := Length(FSplats) - Keep;
    for I := 0 to Keep - 1 do
      FSplats[I] := FSplats[I + Shift];
    SetLength(FSplats, Keep);
    if FShowPreview then
      RebuildPreview;
  end;
end;

procedure TCastleSplatterBurst.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleSplatterBurst.ApplyPreset(const APreset: TSplatterBurstPreset);
begin
  FPreset := APreset;
  case APreset of
    sbpPaintballNeonSplash:
      begin
        FDropletRayCount := 24;
        FConeHalfAngleDeg := 26.0;
        FMaxSprayRangeMeters := 10.0;
        FBaseDropletRadiusMeters := 0.16;
        FMaxStreakAspectRatio := 4.2;
        FMaxActiveSplats := 64;
        FDecalLifetimeSec := 14.0;
      end;
    sbpGrenadeSootScorch:
      begin
        FDropletRayCount := 36;
        FConeHalfAngleDeg := 75.0;
        FMaxSprayRangeMeters := 7.5;
        FBaseDropletRadiusMeters := 0.28;
        FMaxStreakAspectRatio := 3.6;
        FMaxActiveSplats := 96;
        FDecalLifetimeSec := 25.0;
      end;
    sbpSlimeAcidBurst:
      begin
        FDropletRayCount := 28;
        FConeHalfAngleDeg := 42.0;
        FMaxSprayRangeMeters := 8.5;
        FBaseDropletRadiusMeters := 0.20;
        FMaxStreakAspectRatio := 4.5;
        FMaxActiveSplats := 72;
        FDecalLifetimeSec := 10.0;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleSplatterBurst.ClearSplats;
begin
  SetLength(FSplats, 0);
  FBurstCounter := 0;
  ClearPreview;
end;

function TCastleSplatterBurst.EmitDirectionalBurst(
  const AWorldRoot: TCastleAbstractRootTransform;
  const AOrigin, ADirection: TVector3): Integer;
var
  AxisFwd, AxisRight, AxisUp, HelperUp, RayDir, SurfNorm, TangProj: TVector3;
  NRays, I, K, CapMax, CurLen, J: Integer;
  MaxRange, ConeRad, Theta, Phi, BestDist, D, IncDot, Aspect, Wd: Single;
  RH: TRayCollision;
  HitItem: TCastleTransform;
  BestNode: TRayCollisionNode;
  FoundHit: Boolean;
  Mark: TSplatDecalMark;
begin
  Result := 0;
  if AWorldRoot = nil then Exit;

  if ADirection.LengthSqr < 1e-8 then
    AxisFwd := Vector3(0.0, 0.0, -1.0)
  else
    AxisFwd := ADirection.Normalize;

  if Abs(AxisFwd.Y) < 0.92 then
    HelperUp := Vector3(0.0, 1.0, 0.0)
  else
    HelperUp := Vector3(1.0, 0.0, 0.0);
  AxisRight := TVector3.CrossProduct(AxisFwd, HelperUp).Normalize;
  AxisUp := TVector3.CrossProduct(AxisRight, AxisFwd).Normalize;

  NRays := Clamped(FDropletRayCount, 1, 128);
  ConeRad := DegToRad(Clamped(FConeHalfAngleDeg, 0.0, 89.0));
  MaxRange := Max(0.2, FMaxSprayRangeMeters);
  CapMax := Clamped(FMaxActiveSplats, 4, 256);
  Inc(FBurstCounter);

  for I := 0 to NRays - 1 do
  begin
    { Ray 0 fires along exact center axis; Rays 1..N-1 sample seeded cone }
    if (I = 0) or (ConeRad < 1e-4) then
      RayDir := AxisFwd
    else
    begin
      Theta := Sqrt(SplatHash01(FRandomSeed + FBurstCounter * 37, I * 2)) * ConeRad;
      Phi := 2.0 * Pi * SplatHash01(FRandomSeed + FBurstCounter * 53, I * 2 + 1);
      RayDir := (AxisFwd * Cos(Theta) +
        (AxisRight * Cos(Phi) + AxisUp * Sin(Phi)) * Sin(Theta)).Normalize;
    end;

    FoundHit := False;
    BestDist := MaxRange + 1.0;
    BestNode := Default(TRayCollisionNode);

    RH := AWorldRoot.WorldRay(AOrigin, RayDir);
    try
      if RH <> nil then
        for K := 0 to RH.Count - 1 do
        begin
          HitItem := RH[K].Item;
          if (HitItem = nil) or (HitItem = AWorldRoot) or (HitItem = Self) then
            Continue;
          if csTransient in HitItem.ComponentStyle then
            Continue;
          D := PointsDistance(AOrigin, RH[K].Point);
          if (D >= 0.02) and (D <= MaxRange) and (D < BestDist) then
          begin
            BestDist := D;
            BestNode := RH[K];
            FoundHit := True;
          end;
        end;
    finally
      FreeAndNil(RH);
    end;

    if not FoundHit then Continue;

    SurfNorm := ExtractSplatSurfaceNormal(BestNode, RayDir);
    IncDot := Clamped(Abs(TVector3.DotProduct(RayDir, SurfNorm)), 0.05, 1.0);
    Aspect := Clamped(1.0 / Max(0.18, IncDot), 1.0, Max(1.0, FMaxStreakAspectRatio));

    TangProj := RayDir - SurfNorm * TVector3.DotProduct(RayDir, SurfNorm);
    if TangProj.LengthSqr < 1e-6 then
    begin
      if Abs(SurfNorm.Y) < 0.9 then
        TangProj := TVector3.CrossProduct(SurfNorm, Vector3(0.0, 1.0, 0.0)).Normalize
      else
        TangProj := TVector3.CrossProduct(SurfNorm, Vector3(1.0, 0.0, 0.0)).Normalize;
    end else
      TangProj := TangProj.Normalize;

    Wd := Max(0.04, FBaseDropletRadiusMeters * 2.0 *
      (0.75 + 0.50 * SplatHash01(FRandomSeed, I + FBurstCounter * 11)));

    Mark.WorldPos := BestNode.Point + SurfNorm * 0.015;
    Mark.SurfaceNormal := SurfNorm;
    Mark.StreakTangent := TangProj;
    Mark.WidthMeters := Wd;
    Mark.LengthMeters := Wd * Aspect;
    Mark.StreakAspectRatio := Aspect;
    Mark.IncidenceDot := IncDot;
    Mark.RemainingLifetimeSec := Max(0.5, FDecalLifetimeSec);
    Mark.Alpha01 := 1.0;

    CurLen := Length(FSplats);
    if CurLen >= CapMax then
    begin
      { Evict oldest splat (LRU index 0) to respect MaxActiveSplats cap }
      for J := 0 to CapMax - 2 do
        FSplats[J] := FSplats[J + 1];
      FSplats[CapMax - 1] := Mark;
    end else
    begin
      SetLength(FSplats, CurLen + 1);
      FSplats[CurLen] := Mark;
    end;
    Inc(Result);
  end;

  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleSplatterBurst.StepEvaporationFade(const ADtSec: Single);
var
  I, WriteIdx: Integer;
  LifeTotal: Single;
begin
  if ADtSec <= 0.0 then Exit;
  LifeTotal := Max(0.5, FDecalLifetimeSec);
  WriteIdx := 0;
  for I := 0 to High(FSplats) do
  begin
    FSplats[I].RemainingLifetimeSec := FSplats[I].RemainingLifetimeSec - ADtSec;
    if FSplats[I].RemainingLifetimeSec > 0.001 then
    begin
      FSplats[I].Alpha01 := Clamped(FSplats[I].RemainingLifetimeSec / LifeTotal, 0.0, 1.0);
      if WriteIdx <> I then
        FSplats[WriteIdx] := FSplats[I];
      Inc(WriteIdx);
    end;
  end;
  SetLength(FSplats, WriteIdx);
  if FShowPreview then
    RebuildPreview;
end;

function TCastleSplatterBurst.ActiveSplatCount: Integer;
begin
  Result := Length(FSplats);
end;

function TCastleSplatterBurst.GetSplatMark(const AIndex: Integer): TSplatDecalMark;
begin
  if (AIndex >= 0) and (AIndex < Length(FSplats)) then
    Result := FSplats[AIndex]
  else
    Result := Default(TSplatDecalMark);
end;

function TCastleSplatterBurst.MeanStreakAspectRatio: Single;
var
  I: Integer;
  Sum: Single;
begin
  if Length(FSplats) = 0 then Exit(1.0);
  Sum := 0.0;
  for I := 0 to High(FSplats) do
    Sum := Sum + FSplats[I].StreakAspectRatio;
  Result := Sum / Length(FSplats);
end;

procedure TCastleSplatterBurst.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
  end;
end;

procedure TCastleSplatterBurst.RebuildPreview;
var
  InvWT, WT: TMatrix4;
  SplatBox: TCastleBox;
  I: Integer;
  M: TSplatDecalMark;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if (not FShowPreview) or (Length(FSplats) = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'SplatterBurstPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  for I := 0 to High(FSplats) do
  begin
    M := FSplats[I];
    SplatBox := TCastleBox.Create(FPreviewRoot);
    SplatBox.SetTransient;
    SplatBox.Pickable := False;
    SplatBox.Collides := False;
    SplatBox.Size := Vector3(M.WidthMeters, 0.015, M.LengthMeters);
    SplatBox.Translation := InvWT.MultPoint(M.WorldPos);
    SplatBox.Direction := InvWT.MultDirection(M.StreakTangent);
    SplatBox.Up := InvWT.MultDirection(M.SurfaceNormal);
    case FPreset of
      sbpPaintballNeonSplash: SplatBox.Color := Vector4(1.0, 0.22, 0.68, M.Alpha01);
      sbpGrenadeSootScorch:   SplatBox.Color := Vector4(0.14, 0.13, 0.12, M.Alpha01);
      sbpSlimeAcidBurst:      SplatBox.Color := Vector4(0.38, 0.98, 0.18, M.Alpha01);
    end;
    FPreviewRoot.Add(SplatBox);
  end;

  Add(FPreviewRoot);
end;

function TCastleSplatterBurst.SplatterSummaryBadge: String;
begin
  Result := FormatDot('[Splatter:%d/%d Streak=%.2fx]', [
    Length(FSplats), FMaxActiveSplats, MeanStreakAspectRatio]);
end;

initialization
  RegisterSerializableComponent(TCastleSplatterBurst, 'Procedural Decal Splatter Burst');

end.
