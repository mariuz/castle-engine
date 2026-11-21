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

{ Multi-bounce optical laser beam solver with WorldRay specular Mirror_*
  reflection, exact vector Snell's-law refraction & total internal reflection
  (TIR), Receiver_* power gating, and solid crate beam-break cutoff (Phase 411). }
unit CastleLaserBeam;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTriangles, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset optical laser emitter configurations. }
  TLaserBeamPreset = (
    lbpRubyPuzzleRelayLaser,
    lbpHighPowerIndustrialCutter,
    lbpCrownGlassPrismLab
  );

  { Single traced ray segment along a multi-bounce optical path. }
  TLaserBeamSegment = record
    StartWorld: TVector3;
    EndWorld: TVector3;
    PowerWatts: Single;
    HitComponentName: String;
    ReflectedOrRefracted: Boolean;
  end;

  { Multi-bounce optical laser rig component. }
  TCastleLaserBeamRig = class(TCastleTransform)
  private
    FPreset: TLaserBeamPreset;
    FEmitterPowerWatts: Single;
    FMaxBounces: Integer;
    FMaxSegmentRangeMeters: Single;
    FMirrorReflectance01: Single;
    FPrismRefractiveIndex: Single;
    FAttenuationPerMeter: Single;
    FShowPreview: Boolean;
    FSegments: array of TLaserBeamSegment;
    FReceiverPowered: Boolean;
    FPoweredReceiverName: String;
    FLastHitObjectName: String;
    FDeliveredPowerWatts: Single;
    FPreviewRoot: TCastleTransform;
    FPreviewBeamScene: TCastleScene;
    procedure SetPreset(const AValue: TLaserBeamPreset);
    procedure SetMaxBounces(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TLaserBeamPreset);

    { Exact vector Snell's-law refraction or Total Internal Reflection (TIR).
      AIncidentUnit must be normalized; ASurfaceNormalUnit must oppose AIncidentUnit;
      AEtaRatio = n1 / n2. }
    class function ComputeSnellRefractionOrTIR(
      const AIncidentUnit, ASurfaceNormalUnit: TVector3;
      const AEtaRatio: Single; out ATotalInternalReflection: Boolean): TVector3;

    { Trace the laser from local (0,0,0) along local -Z across Mirror_*,
      Prism_*, Receiver_*, and opaque blockers in AWorldRoot. }
    function TraceLaserBeam(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;

    function SegmentCount: Integer;
    function GetSegment(const AIndex: Integer): TLaserBeamSegment;

    procedure RebuildPreview;
    procedure ClearPreview;
    function LaserSummaryBadge: String;

    property ReceiverPowered: Boolean read FReceiverPowered;
    property PoweredReceiverName: String read FPoweredReceiverName;
    property LastHitObjectName: String read FLastHitObjectName;
    property DeliveredPowerWatts: Single read FDeliveredPowerWatts;
  published
    property Preset: TLaserBeamPreset
      read FPreset write SetPreset default lbpRubyPuzzleRelayLaser;
    property EmitterPowerWatts: Single
      read FEmitterPowerWatts write FEmitterPowerWatts;
    property MaxBounces: Integer
      read FMaxBounces write SetMaxBounces default 12;
    property MaxSegmentRangeMeters: Single
      read FMaxSegmentRangeMeters write FMaxSegmentRangeMeters;
    property MirrorReflectance01: Single
      read FMirrorReflectance01 write FMirrorReflectance01;
    property PrismRefractiveIndex: Single
      read FPrismRefractiveIndex write FPrismRefractiveIndex;
    property AttenuationPerMeter: Single
      read FAttenuationPerMeter write FAttenuationPerMeter;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function LaserBeamPresetToString(const APreset: TLaserBeamPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function LaserBeamPresetToString(const APreset: TLaserBeamPreset): String;
begin
  case APreset of
    lbpRubyPuzzleRelayLaser:      Result := 'RubyPuzzleRelayLaser';
    lbpHighPowerIndustrialCutter: Result := 'HighPowerIndustrialCutter';
    lbpCrownGlassPrismLab:        Result := 'CrownGlassPrismLab';
  end;
end;

function ExtractOpticalWorldNormal(const ANode: TRayCollisionNode;
  const AIncidentDir: TVector3): TVector3;
var
  HitItem: TCastleTransform;
  InvWT: TMatrix4;
  LocalPt, LocalMin, LocalMax, LocalCenter, HalfExt, Rel: TVector3;
  NX, NY, NZ: Single;
begin
  Result := -AIncidentDir;
  HitItem := ANode.Item;
  if HitItem = nil then Exit;

  if (ANode.Triangle <> nil) and HitItem.HasWorldTransform then
  begin
    Result := HitItem.LocalToWorldDirection(ANode.Triangle^.SceneSpace.Normal);
    if Result.LengthSqr > 1e-8 then
    begin
      Result := Result.Normalize;
      if TVector3.DotProduct(Result, AIncidentDir) > 0.0 then
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
    LocalPt := InvWT.MultPoint(ANode.Point);
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
      Result := -AIncidentDir;
  end;

  if TVector3.DotProduct(Result, AIncidentDir) > 0.0 then
    Result := -Result;
end;

class function TCastleLaserBeamRig.ComputeSnellRefractionOrTIR(
  const AIncidentUnit, ASurfaceNormalUnit: TVector3;
  const AEtaRatio: Single; out ATotalInternalReflection: Boolean): TVector3;
var
  I, N: TVector3;
  CosI, K: Single;
begin
  I := AIncidentUnit.Normalize;
  N := ASurfaceNormalUnit.Normalize;
  if TVector3.DotProduct(I, N) > 0.0 then
    N := -N;
  CosI := Clamped(-TVector3.DotProduct(I, N), 0.0, 1.0);
  K := 1.0 - Sqr(AEtaRatio) * (1.0 - Sqr(CosI));
  if K < 0.0 then
  begin
    ATotalInternalReflection := True;
    Result := (I + N * (2.0 * CosI)).Normalize;
  end else
  begin
    ATotalInternalReflection := False;
    Result := (I * AEtaRatio + N * (AEtaRatio * CosI - Sqrt(K))).Normalize;
  end;
end;

constructor TCastleLaserBeamRig.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FMaxBounces := 12;
  ApplyPreset(lbpRubyPuzzleRelayLaser);
end;

destructor TCastleLaserBeamRig.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleLaserBeamRig.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'EmitterPowerWatts', 'MaxBounces', 'MaxSegmentRangeMeters',
       'MirrorReflectance01', 'PrismRefractiveIndex',
       'AttenuationPerMeter', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLaserBeamRig.SetPreset(const AValue: TLaserBeamPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleLaserBeamRig.SetMaxBounces(const AValue: Integer);
begin
  FMaxBounces := Clamped(AValue, 1, 32);
end;

procedure TCastleLaserBeamRig.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleLaserBeamRig.ApplyPreset(const APreset: TLaserBeamPreset);
begin
  FPreset := APreset;
  case APreset of
    lbpRubyPuzzleRelayLaser:
      begin
        FEmitterPowerWatts := 50.0;
        FMaxBounces := 12;
        FMaxSegmentRangeMeters := 40.0;
        FMirrorReflectance01 := 0.96;
        FPrismRefractiveIndex := 1.52;
        FAttenuationPerMeter := 0.005;
      end;
    lbpHighPowerIndustrialCutter:
      begin
        FEmitterPowerWatts := 2500.0;
        FMaxBounces := 6;
        FMaxSegmentRangeMeters := 25.0;
        FMirrorReflectance01 := 0.99;
        FPrismRefractiveIndex := 1.46;
        FAttenuationPerMeter := 0.012;
      end;
    lbpCrownGlassPrismLab:
      begin
        FEmitterPowerWatts := 15.0;
        FMaxBounces := 16;
        FMaxSegmentRangeMeters := 35.0;
        FMirrorReflectance01 := 0.98;
        FPrismRefractiveIndex := 1.62;
        FAttenuationPerMeter := 0.002;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleLaserBeamRig.TraceLaserBeam(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;
var
  ActiveRoot: TCastleAbstractRootTransform;
  WT: TMatrix4;
  RayOrig, RayDir, SurfNorm, NextDir: TVector3;
  CurPower, MaxSegLen, BestDist, D, Eta: Single;
  StepIdx, K, SegIdx: Integer;
  RH: TRayCollision;
  BestNode: TRayCollisionNode;
  HitItem, LastSurfaceItem: TCastleTransform;
  FoundHit, WasTIR, InsideGlass: Boolean;
begin
  SetLength(FSegments, 0);
  FReceiverPowered := False;
  FPoweredReceiverName := '';
  FLastHitObjectName := '';
  FDeliveredPowerWatts := 0.0;

  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  RayOrig := WT.MultPoint(TVector3.Zero);
  RayDir := WT.MultDirection(Vector3(0.0, 0.0, -1.0));
  if RayDir.LengthSqr > 1e-6 then
    RayDir := RayDir.Normalize
  else
    RayDir := Vector3(0.0, 0.0, -1.0);

  CurPower := Max(0.1, FEmitterPowerWatts);
  MaxSegLen := Max(1.0, FMaxSegmentRangeMeters);
  InsideGlass := False;
  LastSurfaceItem := Self;

  if ActiveRoot = nil then
  begin
    SetLength(FSegments, 1);
    FSegments[0].StartWorld := RayOrig;
    FSegments[0].EndWorld := RayOrig + RayDir * 6.0;
    FSegments[0].PowerWatts := CurPower;
    if FShowPreview then RebuildPreview;
    Exit(1);
  end;

  for StepIdx := 0 to Clamped(FMaxBounces, 1, 32) do
  begin
    FoundHit := False;
    BestDist := MaxSegLen + 1.0;
    BestNode := Default(TRayCollisionNode);

    RH := ActiveRoot.WorldRay(RayOrig, RayDir);
    try
      if RH <> nil then
        for K := 0 to RH.Count - 1 do
        begin
          HitItem := RH[K].Item;
          if (HitItem = nil) or (HitItem = ActiveRoot) or (HitItem = Self) then
            Continue;
          if csTransient in HitItem.ComponentStyle then Continue;
          D := PointsDistance(RayOrig, RH[K].Point);
          if (HitItem = LastSurfaceItem) and (D < 0.06) then Continue;
          if (D >= 0.02) and (D <= MaxSegLen) and (D < BestDist) then
          begin
            BestDist := D;
            BestNode := RH[K];
            FoundHit := True;
          end;
        end;
    finally
      FreeAndNil(RH);
    end;

    SegIdx := Length(FSegments);
    SetLength(FSegments, SegIdx + 1);
    FSegments[SegIdx].StartWorld := RayOrig;
    FSegments[SegIdx].PowerWatts := CurPower;

    if not FoundHit then
    begin
      FSegments[SegIdx].EndWorld := RayOrig + RayDir * MaxSegLen;
      FSegments[SegIdx].HitComponentName := '';
      FSegments[SegIdx].ReflectedOrRefracted := False;
      Break;
    end;

    HitItem := BestNode.Item;
    FSegments[SegIdx].EndWorld := BestNode.Point;
    FSegments[SegIdx].HitComponentName := HitItem.Name;
    FLastHitObjectName := HitItem.Name;
    CurPower := CurPower * Exp(-Max(0.0, FAttenuationPerMeter) * BestDist);

    if Pos('Receiver', HitItem.Name) > 0 then
    begin
      FReceiverPowered := True;
      FPoweredReceiverName := HitItem.Name;
      FDeliveredPowerWatts := CurPower;
      Break;
    end else
    if (Pos('Mirror', HitItem.Name) > 0) and (StepIdx < FMaxBounces) then
    begin
      SurfNorm := ExtractOpticalWorldNormal(BestNode, RayDir);
      NextDir := (RayDir - SurfNorm * (2.0 * TVector3.DotProduct(RayDir, SurfNorm))).Normalize;
      FSegments[SegIdx].ReflectedOrRefracted := True;
      CurPower := CurPower * Clamped(FMirrorReflectance01, 0.05, 1.0);
      RayOrig := BestNode.Point + NextDir * 0.025;
      RayDir := NextDir;
      LastSurfaceItem := HitItem;
    end else
    if (Pos('Prism', HitItem.Name) > 0) and (StepIdx < FMaxBounces) then
    begin
      SurfNorm := ExtractOpticalWorldNormal(BestNode, RayDir);
      if InsideGlass then
        Eta := Max(1.01, FPrismRefractiveIndex) / 1.0
      else
        Eta := 1.0 / Max(1.01, FPrismRefractiveIndex);
      NextDir := ComputeSnellRefractionOrTIR(RayDir, SurfNorm, Eta, WasTIR);
      if not WasTIR then
        InsideGlass := not InsideGlass;
      FSegments[SegIdx].ReflectedOrRefracted := True;
      RayOrig := BestNode.Point + NextDir * 0.025;
      RayDir := NextDir;
      LastSurfaceItem := nil;
    end else
    begin
      { Solid crate, player, or wall absorbs and terminates the beam! }
      FSegments[SegIdx].ReflectedOrRefracted := False;
      Break;
    end;
  end;

  if FShowPreview then
    RebuildPreview;
  Result := Length(FSegments);
end;

function TCastleLaserBeamRig.SegmentCount: Integer;
begin
  Result := Length(FSegments);
end;

function TCastleLaserBeamRig.GetSegment(const AIndex: Integer): TLaserBeamSegment;
begin
  if (AIndex >= 0) and (AIndex < Length(FSegments)) then
    Result := FSegments[AIndex]
  else
    Result := Default(TLaserBeamSegment);
end;

procedure TCastleLaserBeamRig.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewBeamScene := nil;
  end;
end;

procedure TCastleLaserBeamRig.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  InvWT, WT: TMatrix4;
  Pts: array of TVector3;
  Counts: array of Int32;
  I, N: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  N := Length(FSegments);
  if (not FShowPreview) or (N = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'LaserBeamPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewBeamScene := TCastleScene.Create(FPreviewRoot);
  FPreviewBeamScene.SetTransient;
  FPreviewBeamScene.Name := 'LaserBeamPreviewRays';
  FPreviewBeamScene.Pickable := False;
  FPreviewBeamScene.Collides := False;
  FPreviewRoot.Add(FPreviewBeamScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FReceiverPowered then
    MatNode.EmissiveColor := Vector3(0.25, 1.0, 0.48)
  else
    MatNode.EmissiveColor := Vector3(1.0, 0.22, 0.28);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  SetLength(Pts, N * 2);
  SetLength(Counts, N);
  for I := 0 to N - 1 do
  begin
    Pts[I * 2] := InvWT.MultPoint(FSegments[I].StartWorld);
    Pts[I * 2 + 1] := InvWT.MultPoint(FSegments[I].EndWorld);
    Counts[I] := 2;
  end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewBeamScene.Load(RootNode, True);
end;

function TCastleLaserBeamRig.LaserSummaryBadge: String;
begin
  if FReceiverPowered then
    Result := FormatDot('[Laser:POWERED %d segs %.1fW]', [
      Length(FSegments), FDeliveredPowerWatts])
  else
    Result := Format('[Laser:CUTOFF %d segs]', [Length(FSegments)]);
end;

initialization
  RegisterSerializableComponent(TCastleLaserBeamRig, 'Optical Multi-Bounce Laser');

end.
