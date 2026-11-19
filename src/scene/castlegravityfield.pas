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

{ Dynamic gravity wells, spherical planetoid attractors, hollow O'Neill cylinder
  ringworld interiors, directional gravity zones, and smooth Up-vector slerp (Phase 381). }
unit CastleGravityField;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors, CastleRenderOptions;

type
  { Geometric topology of a local gravity field volume. }
  TGravityShapeKind = (
    gskSphericalPlanet,
    gskHollowCylinderInterior,
    gskDirectionalBoxZone
  );

  { Ready-made planetary and sci-fi artificial gravity presets. }
  TGravityPreset = (
    gfpMarioPlanetoidWalk,
    gfpONeillRingworldTube,
    gfpZeroGCorridorInversion
  );

  { Sampled local Up vector and gravitational acceleration at a 3D world point. }
  TGravitySample = record
    InsideInfluence: Boolean;
    BlendWeight: Single;
    UpVector: TVector3;
    GravityAccelVec: TVector3;
    AccelMagnitudeMps2: Single;
    AltitudeAboveSurface: Single;
    SourcePriority: Integer;
  end;

  { Spatial gravity field volume supporting spherical planetoid walking,
    hollow spinning cylinder interiors, and priority-weighted directional zones. }
  TCastleGravityField = class(TCastleTransform)
  private
    FPreset: TGravityPreset;
    FShapeKind: TGravityShapeKind;
    FPriority: Integer;
    FPlanetRadius: Single;
    FOuterInfluenceRadius: Single;
    FTubeHalfLengthZ: Single;
    FBoxHalfExtentX: Single;
    FBoxHalfExtentY: Single;
    FBoxHalfExtentZ: Single;
    FBoxUpX: Single;
    FBoxUpY: Single;
    FBoxUpZ: Single;
    FSurfaceGravityMps2: Single;
    FInverseSquareFalloff: Boolean;
    FUpAlignSpeedRadPerSec: Single;
    FShowPreviewGizmo: Boolean;
    FPreviewRoot: TCastleTransform;
    FLastSampleCount: Integer;
    procedure SetPreset(const AValue: TGravityPreset);
    procedure SetShapeKind(const AValue: TGravityShapeKind);
    procedure SetPlanetRadius(const AValue: Single);
    procedure SetOuterInfluenceRadius(const AValue: Single);
    procedure SetTubeHalfLengthZ(const AValue: Single);
    procedure SetBoxHalfExtentX(const AValue: Single);
    procedure SetBoxHalfExtentY(const AValue: Single);
    procedure SetBoxHalfExtentZ(const AValue: Single);
    procedure SetSurfaceGravityMps2(const AValue: Single);
    procedure SetUpAlignSpeedRadPerSec(const AValue: Single);
    procedure SetShowPreviewGizmo(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure RebuildPreviewGizmo;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Apply one of the built-in planetary, ringworld, or ceiling-inversion presets. }
    procedure ApplyPreset(const APreset: TGravityPreset);

    { Evaluate this gravity field's Up vector, acceleration, and Hermite blend weight at AWorldPos. }
    function SampleFieldAtWorld(const AWorldPos: TVector3): TGravitySample;

    { Evaluate composite priority-blended gravity across all TCastleGravityField nodes under AWorldRoot. }
    class function EvaluateCompositeWorldGravity(const AWorldRoot: TComponent;
      const AWorldPos: TVector3; const ADefaultGravityMps2: Single = 9.81): TGravitySample;

    { Rotate ACurrentUp smoothly toward ATargetUp by at most AMaxRateRadPerSec * ADtSec radians. }
    class function StepSmoothUpVectorSlerp(const ACurrentUp, ATargetUp: TVector3;
      const AMaxRateRadPerSec, ADtSec: Single): TVector3;

    { Concise Hierarchy tree summary badge. }
    function GravitySummaryBadge: String;

    property LastSampleCount: Integer read FLastSampleCount;
  published
    property Preset: TGravityPreset read FPreset write SetPreset default gfpMarioPlanetoidWalk;
    property ShapeKind: TGravityShapeKind read FShapeKind write SetShapeKind default gskSphericalPlanet;
    property Priority: Integer read FPriority write FPriority default 10;
    property PlanetRadius: Single read FPlanetRadius write SetPlanetRadius;
    property OuterInfluenceRadius: Single read FOuterInfluenceRadius write SetOuterInfluenceRadius;
    property TubeHalfLengthZ: Single read FTubeHalfLengthZ write SetTubeHalfLengthZ;
    property BoxHalfExtentX: Single read FBoxHalfExtentX write SetBoxHalfExtentX;
    property BoxHalfExtentY: Single read FBoxHalfExtentY write SetBoxHalfExtentY;
    property BoxHalfExtentZ: Single read FBoxHalfExtentZ write SetBoxHalfExtentZ;
    property BoxUpX: Single read FBoxUpX write FBoxUpX;
    property BoxUpY: Single read FBoxUpY write FBoxUpY;
    property BoxUpZ: Single read FBoxUpZ write FBoxUpZ;
    property SurfaceGravityMps2: Single read FSurfaceGravityMps2 write SetSurfaceGravityMps2;
    property InverseSquareFalloff: Boolean read FInverseSquareFalloff write FInverseSquareFalloff default True;
    property UpAlignSpeedRadPerSec: Single read FUpAlignSpeedRadPerSec write SetUpAlignSpeedRadPerSec;
    property ShowPreviewGizmo: Boolean read FShowPreviewGizmo write SetShowPreviewGizmo default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored False;
  end;

implementation

uses FpJson, JsonParser, CastleUtils, CastleQuaternions;

function SmoothStep01(const T: Single): Single;
var
  C: Single;
begin
  C := EnsureRange(T, 0.0, 1.0);
  Result := C * C * (3.0 - 2.0 * C);
end;

function SafeUnitVec3(const V, Fallback: TVector3): TVector3;
var
  LenSq: Single;
begin
  LenSq := V.LengthSqr;
  if LenSq > 1e-8 then
    Result := V * (1.0 / Sqrt(LenSq))
  else
    Result := Fallback;
end;

{ TCastleGravityField -------------------------------------------------------- }

constructor TCastleGravityField.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPriority := 10;
  FPlanetRadius := 8.0;
  FOuterInfluenceRadius := 20.0;
  FTubeHalfLengthZ := 14.0;
  FBoxHalfExtentX := 6.0;
  FBoxHalfExtentY := 4.0;
  FBoxHalfExtentZ := 8.0;
  FBoxUpX := 0.0;
  FBoxUpY := -1.0;
  FBoxUpZ := 0.0;
  FSurfaceGravityMps2 := 9.80;
  FInverseSquareFalloff := True;
  FUpAlignSpeedRadPerSec := 6.0;
  FShowPreviewGizmo := True;
  ApplyPreset(gfpMarioPlanetoidWalk);
end;

destructor TCastleGravityField.Destroy;
begin
  FreeAndNil(FPreviewRoot);
  inherited Destroy;
end;

function TCastleGravityField.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'ShapeKind', 'Priority', 'PlanetRadius', 'OuterInfluenceRadius',
       'TubeHalfLengthZ', 'BoxHalfExtentX', 'BoxHalfExtentY', 'BoxHalfExtentZ',
       'BoxUpX', 'BoxUpY', 'BoxUpZ', 'SurfaceGravityMps2',
       'InverseSquareFalloff', 'UpAlignSpeedRadPerSec', 'ShowPreviewGizmo'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleGravityField.ApplyPreset(const APreset: TGravityPreset);
begin
  FPreset := APreset;
  case APreset of
    gfpMarioPlanetoidWalk:
      begin
        FShapeKind := gskSphericalPlanet;
        FPriority := 10;
        FPlanetRadius := 8.0;
        FOuterInfluenceRadius := 20.0;
        FSurfaceGravityMps2 := 9.80;
        FInverseSquareFalloff := True;
        FUpAlignSpeedRadPerSec := 6.0;
      end;
    gfpONeillRingworldTube:
      begin
        FShapeKind := gskHollowCylinderInterior;
        FPriority := 20;
        FPlanetRadius := 10.0;
        FOuterInfluenceRadius := 11.5;
        FTubeHalfLengthZ := 16.0;
        FSurfaceGravityMps2 := 9.80;
        FInverseSquareFalloff := False;
        FUpAlignSpeedRadPerSec := 5.5;
      end;
    gfpZeroGCorridorInversion:
      begin
        FShapeKind := gskDirectionalBoxZone;
        FPriority := 50;
        FBoxHalfExtentX := 5.0;
        FBoxHalfExtentY := 4.0;
        FBoxHalfExtentZ := 8.0;
        FBoxUpX := 0.0;
        FBoxUpY := -1.0;
        FBoxUpZ := 0.0;
        FSurfaceGravityMps2 := 9.80;
        FInverseSquareFalloff := False;
        FUpAlignSpeedRadPerSec := 7.5;
      end;
  end;
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetPreset(const AValue: TGravityPreset);
begin
  if FPreset <> AValue then
    ApplyPreset(AValue);
end;

procedure TCastleGravityField.SetShapeKind(const AValue: TGravityShapeKind);
begin
  if FShapeKind <> AValue then
  begin
    FShapeKind := AValue;
    RebuildPreviewGizmo;
  end;
end;

procedure TCastleGravityField.SetPlanetRadius(const AValue: Single);
begin
  FPlanetRadius := Max(0.25, AValue);
  if FOuterInfluenceRadius < FPlanetRadius + 0.25 then
    FOuterInfluenceRadius := FPlanetRadius + 0.25;
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetOuterInfluenceRadius(const AValue: Single);
begin
  FOuterInfluenceRadius := Max(FPlanetRadius + 0.25, AValue);
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetTubeHalfLengthZ(const AValue: Single);
begin
  FTubeHalfLengthZ := Max(0.5, AValue);
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetBoxHalfExtentX(const AValue: Single);
begin
  FBoxHalfExtentX := Max(0.25, AValue);
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetBoxHalfExtentY(const AValue: Single);
begin
  FBoxHalfExtentY := Max(0.25, AValue);
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetBoxHalfExtentZ(const AValue: Single);
begin
  FBoxHalfExtentZ := Max(0.25, AValue);
  RebuildPreviewGizmo;
end;

procedure TCastleGravityField.SetSurfaceGravityMps2(const AValue: Single);
begin
  FSurfaceGravityMps2 := Max(0.0, AValue);
end;

procedure TCastleGravityField.SetUpAlignSpeedRadPerSec(const AValue: Single);
begin
  FUpAlignSpeedRadPerSec := Max(0.1, AValue);
end;

procedure TCastleGravityField.SetShowPreviewGizmo(const AValue: Boolean);
begin
  if FShowPreviewGizmo <> AValue then
  begin
    FShowPreviewGizmo := AValue;
    RebuildPreviewGizmo;
  end;
end;

procedure TCastleGravityField.RebuildPreviewGizmo;
var
  SphereGizmo: TCastleSphere;
  Cyl: TCastleCylinder;
  Box: TCastleBox;
begin
  FreeAndNil(FPreviewRoot);
  if not FShowPreviewGizmo then
    Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  FPreviewRoot.Name := 'TransientGravityPreview';

  case FShapeKind of
    gskSphericalPlanet:
      begin
        SphereGizmo := TCastleSphere.Create(FPreviewRoot);
        SphereGizmo.SetTransient;
        SphereGizmo.Pickable := False;
        SphereGizmo.Collides := False;
        SphereGizmo.Radius := FPlanetRadius;
        SphereGizmo.Color := Vector4(0.22, 0.56, 0.92, 1.0);
        FPreviewRoot.Add(SphereGizmo);
      end;
    gskHollowCylinderInterior:
      begin
        Cyl := TCastleCylinder.Create(FPreviewRoot);
        Cyl.SetTransient;
        Cyl.Pickable := False;
        Cyl.Collides := False;
        Cyl.Radius := FPlanetRadius;
        Cyl.Height := FTubeHalfLengthZ * 2.0;
        Cyl.Rotation := Vector4(1, 0, 0, Pi * 0.5);
        Cyl.Color := Vector4(0.26, 0.78, 0.68, 0.45);
        FPreviewRoot.Add(Cyl);
      end;
    gskDirectionalBoxZone:
      begin
        Box := TCastleBox.Create(FPreviewRoot);
        Box.SetTransient;
        Box.Pickable := False;
        Box.Collides := False;
        Box.Size := Vector3(FBoxHalfExtentX * 2.0, FBoxHalfExtentY * 2.0, FBoxHalfExtentZ * 2.0);
        Box.Color := Vector4(0.76, 0.36, 0.94, 0.38);
        FPreviewRoot.Add(Box);
      end;
  end;

  Add(FPreviewRoot);
end;

function TCastleGravityField.SampleFieldAtWorld(const AWorldPos: TVector3): TGravitySample;
var
  CenterW, Delta, LocalP, LocalUp, WorldUp: TVector3;
  InvWorld, WT: TMatrix4;
  Dist, CorePlateauR, Ratio, RadialXY, FeatherMargin, EdgeMinDist: Single;
begin
  Inc(FLastSampleCount);
  Result := Default(TGravitySample);
  Result.UpVector := Vector3(0, 1, 0);
  Result.SourcePriority := FPriority;

  WT := WorldTransform;
  CenterW := WT.MultPoint(TVector3.Zero);

  case FShapeKind of
    gskSphericalPlanet:
      begin
        Delta := AWorldPos - CenterW;
        Dist := Delta.Length;
        if Dist > FOuterInfluenceRadius then
          Exit;
        Result.InsideInfluence := True;
        Result.UpVector := SafeUnitVec3(Delta, Vector3(0, 1, 0));
        Result.AltitudeAboveSurface := Dist - FPlanetRadius;

        CorePlateauR := FPlanetRadius + 0.35 * (FOuterInfluenceRadius - FPlanetRadius);
        if Dist <= CorePlateauR then
          Result.BlendWeight := 1.0
        else
          Result.BlendWeight := 1.0 - SmoothStep01(
            (Dist - CorePlateauR) / Max(0.01, FOuterInfluenceRadius - CorePlateauR));

        if FInverseSquareFalloff and (Dist > FPlanetRadius) then
        begin
          Ratio := FPlanetRadius / Dist;
          Result.AccelMagnitudeMps2 := FSurfaceGravityMps2 * Ratio * Ratio;
        end else
          Result.AccelMagnitudeMps2 := FSurfaceGravityMps2;

        Result.GravityAccelVec := -Result.UpVector * Result.AccelMagnitudeMps2;
      end;

    gskHollowCylinderInterior:
      begin
        if not WT.TryInverse(InvWorld) then
          InvWorld := TMatrix4.Identity;
        LocalP := InvWorld.MultPoint(AWorldPos);
        RadialXY := Hypot(LocalP.X, LocalP.Y);
        if (Abs(LocalP.Z) > FTubeHalfLengthZ) or (RadialXY > FOuterInfluenceRadius) then
          Exit;

        Result.InsideInfluence := True;
        { Centrifugal hull spin pushes outward (+RadialXY), so local Up points inward toward central Z axis }
        LocalUp := SafeUnitVec3(Vector3(-LocalP.X, -LocalP.Y, 0.0), Vector3(0, 1, 0));
        WorldUp := SafeUnitVec3(WT.MultDirection(LocalUp), Vector3(0, 1, 0));
        Result.UpVector := WorldUp;
        Result.AltitudeAboveSurface := FPlanetRadius - RadialXY;

        FeatherMargin := Min(1.5, FTubeHalfLengthZ * 0.2);
        if Abs(LocalP.Z) <= FTubeHalfLengthZ - FeatherMargin then
          Result.BlendWeight := 1.0
        else
          Result.BlendWeight := SmoothStep01((FTubeHalfLengthZ - Abs(LocalP.Z)) / Max(0.01, FeatherMargin));

        { Spin gravity scales linearly r/R toward hull wall, clamped at SurfaceGravityMps2 }
        if FInverseSquareFalloff then
          Result.AccelMagnitudeMps2 := FSurfaceGravityMps2 * EnsureRange(RadialXY / Max(0.1, FPlanetRadius), 0.15, 1.0)
        else
          Result.AccelMagnitudeMps2 := FSurfaceGravityMps2;

        Result.GravityAccelVec := -Result.UpVector * Result.AccelMagnitudeMps2;
      end;

    gskDirectionalBoxZone:
      begin
        if not WT.TryInverse(InvWorld) then
          InvWorld := TMatrix4.Identity;
        LocalP := InvWorld.MultPoint(AWorldPos);
        if (Abs(LocalP.X) > FBoxHalfExtentX) or
           (Abs(LocalP.Y) > FBoxHalfExtentY) or
           (Abs(LocalP.Z) > FBoxHalfExtentZ) then
          Exit;

        Result.InsideInfluence := True;
        LocalUp := SafeUnitVec3(Vector3(FBoxUpX, FBoxUpY, FBoxUpZ), Vector3(0, -1, 0));
        Result.UpVector := SafeUnitVec3(WT.MultDirection(LocalUp), Vector3(0, -1, 0));
        Result.AltitudeAboveSurface := LocalP.Y + FBoxHalfExtentY;

        EdgeMinDist := Min(FBoxHalfExtentX - Abs(LocalP.X),
          Min(FBoxHalfExtentY - Abs(LocalP.Y), FBoxHalfExtentZ - Abs(LocalP.Z)));
        FeatherMargin := Min(0.75, Min(FBoxHalfExtentX, Min(FBoxHalfExtentY, FBoxHalfExtentZ)) * 0.25);
        if EdgeMinDist >= FeatherMargin then
          Result.BlendWeight := 1.0
        else
          Result.BlendWeight := SmoothStep01(EdgeMinDist / Max(0.01, FeatherMargin));

        Result.AccelMagnitudeMps2 := FSurfaceGravityMps2;
        Result.GravityAccelVec := -Result.UpVector * Result.AccelMagnitudeMps2;
      end;
  end;
end;

class function TCastleGravityField.EvaluateCompositeWorldGravity(
  const AWorldRoot: TComponent; const AWorldPos: TVector3;
  const ADefaultGravityMps2: Single): TGravitySample;
var
  BestSample, CurSample: TGravitySample;
  FoundBest: Boolean;

  procedure ScanNode(const ANode: TComponent);
  var
    I: Integer;
    Field: TCastleGravityField;
    T: TCastleTransform;
  begin
    if ANode = nil then Exit;
    if (ANode is TCastleGravityField) and (not (csTransient in ANode.ComponentStyle)) then
    begin
      Field := TCastleGravityField(ANode);
      if Field.Exists then
      begin
        CurSample := Field.SampleFieldAtWorld(AWorldPos);
        if CurSample.InsideInfluence and (CurSample.BlendWeight > 0.001) then
        begin
          if (not FoundBest) or
             (CurSample.SourcePriority > BestSample.SourcePriority) or
             ((CurSample.SourcePriority = BestSample.SourcePriority) and
              (CurSample.BlendWeight > BestSample.BlendWeight)) then
          begin
            BestSample := CurSample;
            FoundBest := True;
          end;
        end;
      end;
    end;

    if ANode is TCastleTransform then
    begin
      T := TCastleTransform(ANode);
      for I := 0 to T.Count - 1 do
        ScanNode(T[I]);
    end;
    for I := 0 to ANode.ComponentCount - 1 do
      if not (ANode.Components[I] is TCastleTransform) or
         (TCastleTransform(ANode.Components[I]).Parent = nil) then
        ScanNode(ANode.Components[I]);
  end;

var
  BlendedUp: TVector3;
begin
  Result := Default(TGravitySample);
  Result.InsideInfluence := False;
  Result.BlendWeight := 0.0;
  Result.UpVector := Vector3(0, 1, 0);
  Result.AccelMagnitudeMps2 := ADefaultGravityMps2;
  Result.GravityAccelVec := Vector3(0, -ADefaultGravityMps2, 0);
  Result.SourcePriority := 0;

  FoundBest := False;
  BestSample := Default(TGravitySample);
  ScanNode(AWorldRoot);

  if FoundBest then
  begin
    BlendedUp := SafeUnitVec3(
      Lerp(BestSample.BlendWeight, Vector3(0, 1, 0), BestSample.UpVector),
      BestSample.UpVector);
    Result.InsideInfluence := True;
    Result.BlendWeight := BestSample.BlendWeight;
    Result.UpVector := BlendedUp;
    Result.AccelMagnitudeMps2 := Lerp(BestSample.BlendWeight, ADefaultGravityMps2, BestSample.AccelMagnitudeMps2);
    Result.GravityAccelVec := -Result.UpVector * Result.AccelMagnitudeMps2;
    Result.AltitudeAboveSurface := BestSample.AltitudeAboveSurface;
    Result.SourcePriority := BestSample.SourcePriority;
  end;
end;

class function TCastleGravityField.StepSmoothUpVectorSlerp(
  const ACurrentUp, ATargetUp: TVector3;
  const AMaxRateRadPerSec, ADtSec: Single): TVector3;
var
  CurU, TgtU, Axis: TVector3;
  DotVal, TotalAngle, MaxStepAngle: Single;
  Q: TQuaternion;
begin
  CurU := SafeUnitVec3(ACurrentUp, Vector3(0, 1, 0));
  TgtU := SafeUnitVec3(ATargetUp, Vector3(0, 1, 0));
  if (ADtSec <= 0.0) or (AMaxRateRadPerSec <= 0.0) then
    Exit(CurU);

  DotVal := EnsureRange(TVector3.DotProduct(CurU, TgtU), -1.0, 1.0);
  TotalAngle := ArcCos(DotVal);
  if TotalAngle < 1e-5 then
    Exit(TgtU);

  MaxStepAngle := AMaxRateRadPerSec * ADtSec;
  if MaxStepAngle >= TotalAngle then
    Exit(TgtU);

  Axis := TVector3.CrossProduct(CurU, TgtU);
  if Axis.LengthSqr < 1e-7 then
  begin
    { Antipodal 180-degree flip: pick stable orthogonal rotation axis }
    Axis := TVector3.CrossProduct(CurU, Vector3(1, 0, 0));
    if Axis.LengthSqr < 1e-5 then
      Axis := TVector3.CrossProduct(CurU, Vector3(0, 0, 1));
  end;
  Axis := Axis.Normalize;
  Q := QuatFromAxisAngle(Vector4(Axis, MaxStepAngle));
  Result := SafeUnitVec3(Q.Rotate(CurU), TgtU);
end;

function TCastleGravityField.GravitySummaryBadge: String;
var
  KindStr: String;
begin
  case FShapeKind of
    gskSphericalPlanet: KindStr := Format('Planet R=%.1fm', [FPlanetRadius]);
    gskHollowCylinderInterior: KindStr := Format('RingTube R=%.1fm', [FPlanetRadius]);
    gskDirectionalBoxZone: KindStr := Format('ZoneBox P=%d', [FPriority]);
  end;
  Result := Format('[Gravity:%s g=%.1fm/s2 P=%d]', [KindStr, FSurfaceGravityMps2, FPriority]);
end;

function TCastleGravityField.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('shapeKind', Ord(FShapeKind));
    Obj.Add('priority', FPriority);
    Obj.Add('planetRadius', FPlanetRadius);
    Obj.Add('outerInfluenceRadius', FOuterInfluenceRadius);
    Obj.Add('tubeHalfLengthZ', FTubeHalfLengthZ);
    Obj.Add('boxHalfExtentX', FBoxHalfExtentX);
    Obj.Add('boxHalfExtentY', FBoxHalfExtentY);
    Obj.Add('boxHalfExtentZ', FBoxHalfExtentZ);
    Obj.Add('boxUpX', FBoxUpX);
    Obj.Add('boxUpY', FBoxUpY);
    Obj.Add('boxUpZ', FBoxUpZ);
    Obj.Add('surfaceGravityMps2', FSurfaceGravityMps2);
    Obj.Add('inverseSquareFalloff', FInverseSquareFalloff);
    Obj.Add('upAlignSpeedRadPerSec', FUpAlignSpeedRadPerSec);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleGravityField.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      FPreset := TGravityPreset(EnsureRange(Obj.Get('preset', Ord(FPreset)), 0, Ord(High(TGravityPreset))));
      FShapeKind := TGravityShapeKind(EnsureRange(Obj.Get('shapeKind', Ord(FShapeKind)), 0, Ord(High(TGravityShapeKind))));
      FPriority := Obj.Get('priority', FPriority);
      FPlanetRadius := Max(0.25, Obj.Get('planetRadius', FPlanetRadius));
      FOuterInfluenceRadius := Max(FPlanetRadius + 0.25, Obj.Get('outerInfluenceRadius', FOuterInfluenceRadius));
      FTubeHalfLengthZ := Max(0.5, Obj.Get('tubeHalfLengthZ', FTubeHalfLengthZ));
      FBoxHalfExtentX := Max(0.25, Obj.Get('boxHalfExtentX', FBoxHalfExtentX));
      FBoxHalfExtentY := Max(0.25, Obj.Get('boxHalfExtentY', FBoxHalfExtentY));
      FBoxHalfExtentZ := Max(0.25, Obj.Get('boxHalfExtentZ', FBoxHalfExtentZ));
      FBoxUpX := Obj.Get('boxUpX', FBoxUpX);
      FBoxUpY := Obj.Get('boxUpY', FBoxUpY);
      FBoxUpZ := Obj.Get('boxUpZ', FBoxUpZ);
      FSurfaceGravityMps2 := Max(0.0, Obj.Get('surfaceGravityMps2', FSurfaceGravityMps2));
      FInverseSquareFalloff := Obj.Get('inverseSquareFalloff', FInverseSquareFalloff);
      FUpAlignSpeedRadPerSec := Max(0.1, Obj.Get('upAlignSpeedRadPerSec', FUpAlignSpeedRadPerSec));
      RebuildPreviewGizmo;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleGravityField,
    ['Physics & Simulation', 'Gravity Field & Planetoid Attractor (TCastleGravityField)']);

end.
