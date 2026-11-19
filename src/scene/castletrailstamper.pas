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

{ Interactive snow, mud, and sand persistent 2D deformation grid stamper with
  volume-conserving raised rim berms and snowfall/wind refill recovery (Phase 383). }
unit CastleTrailStamper;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, X3DNodes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Deformable ground medium presets. }
  TTrailMediumPreset = (
    tmpDeepAlpineSnow,
    tmpRainSoakedMud,
    tmpDesertDuneSand
  );

  { Bilinearly sampled deformation state at a 3D world query position. }
  TTrailStampSample = record
    InsideGrid: Boolean;
    DisplacementMeters: Single;
    Compaction01: Single;
    SurfaceNormal: TVector3;
  end;

  { Persistent 2D deformable snow, mud, and sand surface patch supporting
    point boot/hoof stamps, swept wheel/sled furrows, raised side berms,
    and gradual weather refill. }
  TCastleTrailStamper = class(TCastleTransform)
  private
    FPreset: TTrailMediumPreset;
    FGridResolution: Integer;
    FPatchSizeMeters: Single;
    FMaxSinkDepthMeters: Single;
    FRimBermRatio01: Single;
    FRefillRateMetersPerSec: Single;
    FShowPreviewMesh: Boolean;
    FHeights: array of Single;
    FCompaction: array of Single;
    FTotalStampsApplied: Integer;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TTrailMediumPreset);
    procedure SetGridResolution(const AValue: Integer);
    procedure SetPatchSizeMeters(const AValue: Single);
    procedure SetMaxSinkDepthMeters(const AValue: Single);
    procedure SetRimBermRatio01(const AValue: Single);
    procedure SetRefillRateMetersPerSec(const AValue: Single);
    procedure SetShowPreviewMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure AllocateGridArrays;
    procedure EnsurePreviewScene;
    procedure RebuildPreviewMesh;
    function BaseMediumColor: TVector3;
    function TroughMediumColor: TVector3;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TTrailMediumPreset);
    procedure ClearDeformation;

    { Carve a circular boot/wheel depression with raised outer collar berm. }
    function StampBootOrWheelAtWorld(const AWorldPos: TVector3;
      const ARadiusMeters, ASinkDepthMeters: Single): Integer;

    { Sweep a continuous sled, ski, or tire furrow from AStartWorld to AEndWorld. }
    function StampFurrowSegmentWorld(const AStartWorld, AEndWorld: TVector3;
      const ARadiusMeters, ASinkDepthMeters: Single): Integer;

    { Relax depressions and raised berms back toward undisturbed 0.0m level. }
    procedure StepWeatherRefill(const ADtSec: Single);

    { Bilinearly sample displacement, compaction, and central-difference normal. }
    function SampleDeformationAtWorld(const AWorldPos: TVector3): TTrailStampSample;

    function MinDisplacementMeters: Single;
    function MaxBermHeightMeters: Single;
    function ActiveDeformedCellCount: Integer;
    function TrailSummaryBadge: String;

    property TotalStampsApplied: Integer read FTotalStampsApplied;
  published
    property Preset: TTrailMediumPreset read FPreset write SetPreset default tmpDeepAlpineSnow;
    property GridResolution: Integer read FGridResolution write SetGridResolution default 48;
    property PatchSizeMeters: Single read FPatchSizeMeters write SetPatchSizeMeters;
    property MaxSinkDepthMeters: Single read FMaxSinkDepthMeters write SetMaxSinkDepthMeters;
    property RimBermRatio01: Single read FRimBermRatio01 write SetRimBermRatio01;
    property RefillRateMetersPerSec: Single read FRefillRateMetersPerSec write SetRefillRateMetersPerSec;
    property ShowPreviewMesh: Boolean read FShowPreviewMesh write SetShowPreviewMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored False;
  end;

implementation

uses FpJson, JsonParser, CastleUtils;

{ TCastleTrailStamper -------------------------------------------------------- }

constructor TCastleTrailStamper.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGridResolution := 48;
  FPatchSizeMeters := 24.0;
  FMaxSinkDepthMeters := 0.38;
  FRimBermRatio01 := 0.34;
  FRefillRateMetersPerSec := 0.04;
  FShowPreviewMesh := True;
  AllocateGridArrays;
  ApplyPreset(tmpDeepAlpineSnow);
end;

destructor TCastleTrailStamper.Destroy;
begin
  FreeAndNil(FTransientScene);
  SetLength(FHeights, 0);
  SetLength(FCompaction, 0);
  inherited Destroy;
end;

function TCastleTrailStamper.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'GridResolution', 'PatchSizeMeters', 'MaxSinkDepthMeters',
       'RimBermRatio01', 'RefillRateMetersPerSec', 'ShowPreviewMesh'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleTrailStamper.AllocateGridArrays;
var
  Total: Integer;
begin
  Total := FGridResolution * FGridResolution;
  SetLength(FHeights, Total);
  SetLength(FCompaction, Total);
  if Total > 0 then
  begin
    FillChar(FHeights[0], Total * SizeOf(Single), 0);
    FillChar(FCompaction[0], Total * SizeOf(Single), 0);
  end;
end;

function TCastleTrailStamper.BaseMediumColor: TVector3;
begin
  case FPreset of
    tmpDeepAlpineSnow: Result := Vector3(0.93, 0.96, 1.00);
    tmpRainSoakedMud:  Result := Vector3(0.36, 0.25, 0.16);
    tmpDesertDuneSand: Result := Vector3(0.86, 0.74, 0.48);
  end;
end;

function TCastleTrailStamper.TroughMediumColor: TVector3;
begin
  case FPreset of
    tmpDeepAlpineSnow: Result := Vector3(0.62, 0.76, 0.94);
    tmpRainSoakedMud:  Result := Vector3(0.18, 0.12, 0.08);
    tmpDesertDuneSand: Result := Vector3(0.64, 0.50, 0.28);
  end;
end;

procedure TCastleTrailStamper.ApplyPreset(const APreset: TTrailMediumPreset);
begin
  FPreset := APreset;
  case APreset of
    tmpDeepAlpineSnow:
      begin
        FMaxSinkDepthMeters := 0.38;
        FRimBermRatio01 := 0.34;
        FRefillRateMetersPerSec := 0.045;
      end;
    tmpRainSoakedMud:
      begin
        FMaxSinkDepthMeters := 0.24;
        FRimBermRatio01 := 0.42;
        FRefillRateMetersPerSec := 0.008;
      end;
    tmpDesertDuneSand:
      begin
        FMaxSinkDepthMeters := 0.20;
        FRimBermRatio01 := 0.48;
        FRefillRateMetersPerSec := 0.065;
      end;
  end;
  RebuildPreviewMesh;
end;

procedure TCastleTrailStamper.SetPreset(const AValue: TTrailMediumPreset);
begin
  if FPreset <> AValue then
    ApplyPreset(AValue);
end;

procedure TCastleTrailStamper.SetGridResolution(const AValue: Integer);
var
  ClampedRes: Integer;
begin
  ClampedRes := EnsureRange(AValue, 16, 96);
  if FGridResolution <> ClampedRes then
  begin
    FGridResolution := ClampedRes;
    AllocateGridArrays;
    RebuildPreviewMesh;
  end;
end;

procedure TCastleTrailStamper.SetPatchSizeMeters(const AValue: Single);
begin
  FPatchSizeMeters := Max(2.0, AValue);
  RebuildPreviewMesh;
end;

procedure TCastleTrailStamper.SetMaxSinkDepthMeters(const AValue: Single);
begin
  FMaxSinkDepthMeters := Max(0.02, AValue);
end;

procedure TCastleTrailStamper.SetRimBermRatio01(const AValue: Single);
begin
  FRimBermRatio01 := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleTrailStamper.SetRefillRateMetersPerSec(const AValue: Single);
begin
  FRefillRateMetersPerSec := Max(0.0, AValue);
end;

procedure TCastleTrailStamper.SetShowPreviewMesh(const AValue: Boolean);
begin
  if FShowPreviewMesh <> AValue then
  begin
    FShowPreviewMesh := AValue;
    if not FShowPreviewMesh then
      FreeAndNil(FTransientScene)
    else
      RebuildPreviewMesh;
  end;
end;

procedure TCastleTrailStamper.ClearDeformation;
begin
  AllocateGridArrays;
  FTotalStampsApplied := 0;
  RebuildPreviewMesh;
end;

procedure TCastleTrailStamper.EnsurePreviewScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.PreciseCollisions := False;
  FTransientScene.Name := 'TransientTrailSurfaceMesh';

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(1, 1, 1);
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);

  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleTrailStamper.RebuildPreviewMesh;
var
  N, IX, IZ: Integer;
  HalfSpan, StepSz: Single;
  Verts, Colors: TVector3List;
  BaseC, TroughC: TVector3;

  function CellPos(const GX, GZ: Integer): TVector3;
  begin
    Result := Vector3(
      -HalfSpan + GX * StepSz,
      FHeights[GZ * N + GX],
      -HalfSpan + GZ * StepSz);
  end;

  function CellCol(const GX, GZ: Integer): TVector3;
  var
    H, Comp: Single;
  begin
    H := FHeights[GZ * N + GX];
    Comp := FCompaction[GZ * N + GX];
    if H >= 0.005 then
      Result := Vector3(
        Min(1.0, BaseC.X * 1.06),
        Min(1.0, BaseC.Y * 1.06),
        Min(1.0, BaseC.Z * 1.06))
    else
      Result := Lerp(Comp, BaseC, TroughC);
  end;

var
  P00, P10, P01, P11, C00, C10, C01, C11: TVector3;
begin
  if not FShowPreviewMesh then Exit;
  EnsurePreviewScene;
  N := FGridResolution;
  if (N < 2) or (Length(FHeights) < N * N) then Exit;

  HalfSpan := FPatchSizeMeters * 0.5;
  StepSz := FPatchSizeMeters / Single(N - 1);
  BaseC := BaseMediumColor;
  TroughC := TroughMediumColor;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    Verts.Capacity := (N - 1) * (N - 1) * 6;
    Colors.Capacity := (N - 1) * (N - 1) * 6;
    for IZ := 0 to N - 2 do
      for IX := 0 to N - 2 do
      begin
        P00 := CellPos(IX, IZ);
        P10 := CellPos(IX + 1, IZ);
        P01 := CellPos(IX, IZ + 1);
        P11 := CellPos(IX + 1, IZ + 1);
        C00 := CellCol(IX, IZ);
        C10 := CellCol(IX + 1, IZ);
        C01 := CellCol(IX, IZ + 1);
        C11 := CellCol(IX + 1, IZ + 1);

        Verts.Add(P00); Verts.Add(P01); Verts.Add(P11);
        Colors.Add(C00); Colors.Add(C01); Colors.Add(C11);

        Verts.Add(P00); Verts.Add(P11); Verts.Add(P10);
        Colors.Add(C00); Colors.Add(C11); Colors.Add(C10);
      end;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

function TCastleTrailStamper.StampBootOrWheelAtWorld(
  const AWorldPos: TVector3; const ARadiusMeters, ASinkDepthMeters: Single): Integer;
var
  InvWorld: TMatrix4;
  LocalP: TVector3;
  N, IX, IZ, Idx: Integer;
  HalfSpan, StepSz, UseR, OuterBermR, UseDepth, CellX, CellZ, Dist, NormR, TargetSink, BermT, BermH: Single;
begin
  Result := 0;
  N := FGridResolution;
  if (N < 2) or (ARadiusMeters <= 0.01) or (ASinkDepthMeters <= 0.001) then Exit;

  if not WorldTransform.TryInverse(InvWorld) then
    InvWorld := TMatrix4.Identity;
  LocalP := InvWorld.MultPoint(AWorldPos);

  HalfSpan := FPatchSizeMeters * 0.5;
  StepSz := FPatchSizeMeters / Single(N - 1);
  UseR := ARadiusMeters;
  OuterBermR := UseR * 1.55;
  UseDepth := Min(FMaxSinkDepthMeters, ASinkDepthMeters);

  for IZ := 0 to N - 1 do
  begin
    CellZ := -HalfSpan + IZ * StepSz;
    if Abs(CellZ - LocalP.Z) > OuterBermR then Continue;
    for IX := 0 to N - 1 do
    begin
      CellX := -HalfSpan + IX * StepSz;
      if Abs(CellX - LocalP.X) > OuterBermR then Continue;
      Dist := Hypot(CellX - LocalP.X, CellZ - LocalP.Z);
      Idx := IZ * N + IX;

      if Dist <= UseR then
      begin
        NormR := Dist / UseR;
        TargetSink := -UseDepth * Sqr(1.0 - NormR * NormR);
        if TargetSink < FHeights[Idx] then
        begin
          FHeights[Idx] := TargetSink;
          FCompaction[Idx] := Max(FCompaction[Idx], EnsureRange(1.0 - NormR * NormR, 0.0, 1.0));
          Inc(Result);
        end;
      end else
      if (Dist < OuterBermR) and (FRimBermRatio01 > 0.0) and (FHeights[Idx] >= -0.002) then
      begin
        BermT := (Dist - UseR) / (OuterBermR - UseR);
        BermH := UseDepth * FRimBermRatio01 * Sin(Pi * BermT);
        if BermH > FHeights[Idx] then
        begin
          FHeights[Idx] := Min(FMaxSinkDepthMeters * 0.55, BermH);
          Inc(Result);
        end;
      end;
    end;
  end;

  if Result > 0 then
  begin
    Inc(FTotalStampsApplied);
    RebuildPreviewMesh;
  end;
end;

function TCastleTrailStamper.StampFurrowSegmentWorld(
  const AStartWorld, AEndWorld: TVector3;
  const ARadiusMeters, ASinkDepthMeters: Single): Integer;
var
  SegLen, StepDist: Single;
  Steps, I: Integer;
  P: TVector3;
begin
  Result := 0;
  SegLen := PointsDistance(AStartWorld, AEndWorld);
  StepDist := Max(0.08, ARadiusMeters * 0.35);
  Steps := Max(1, Ceil(SegLen / StepDist));
  for I := 0 to Steps do
  begin
    P := Lerp(I / Single(Steps), AStartWorld, AEndWorld);
    Result := Result + StampBootOrWheelAtWorld(P, ARadiusMeters, ASinkDepthMeters);
  end;
end;

procedure TCastleTrailStamper.StepWeatherRefill(const ADtSec: Single);
var
  Delta, CompDecay: Single;
  I: Integer;
  AnyChanged: Boolean;
begin
  if (ADtSec <= 0.0) or (FRefillRateMetersPerSec <= 0.0) then Exit;
  Delta := FRefillRateMetersPerSec * ADtSec;
  CompDecay := ADtSec * (FRefillRateMetersPerSec / Max(0.05, FMaxSinkDepthMeters));
  AnyChanged := False;
  for I := 0 to High(FHeights) do
  begin
    if Abs(FHeights[I]) > 1e-6 then
    begin
      AnyChanged := True;
      if FHeights[I] < 0.0 then
        FHeights[I] := Min(0.0, FHeights[I] + Delta)
      else
        FHeights[I] := Max(0.0, FHeights[I] - Delta);
    end;
    if FCompaction[I] > 0.0 then
      FCompaction[I] := Max(0.0, FCompaction[I] - CompDecay);
  end;
  if AnyChanged then
    RebuildPreviewMesh;
end;

procedure TCastleTrailStamper.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  StepWeatherRefill(Min(SecondsPassed, 0.1));
end;

function TCastleTrailStamper.SampleDeformationAtWorld(
  const AWorldPos: TVector3): TTrailStampSample;
var
  InvWorld, WT: TMatrix4;
  LocalP, LocalNorm: TVector3;
  N, IX0, IZ0, IX1, IZ1, IXM, IXP, IZM, IZP: Integer;
  HalfSpan, StepSz, GX, GZ, FX, FZ, H00, H10, H01, H11, C00, C10, C01, C11, dHdX, dHdZ: Single;
begin
  Result := Default(TTrailStampSample);
  Result.SurfaceNormal := Vector3(0, 1, 0);
  N := FGridResolution;
  if (N < 2) or (Length(FHeights) < N * N) then Exit;

  WT := WorldTransform;
  if not WT.TryInverse(InvWorld) then
    InvWorld := TMatrix4.Identity;
  LocalP := InvWorld.MultPoint(AWorldPos);
  HalfSpan := FPatchSizeMeters * 0.5;
  if (Abs(LocalP.X) > HalfSpan) or (Abs(LocalP.Z) > HalfSpan) then
    Exit;

  Result.InsideGrid := True;
  StepSz := FPatchSizeMeters / Single(N - 1);
  GX := EnsureRange((LocalP.X + HalfSpan) / StepSz, 0.0, N - 1.0001);
  GZ := EnsureRange((LocalP.Z + HalfSpan) / StepSz, 0.0, N - 1.0001);
  IX0 := Floor(GX);
  IZ0 := Floor(GZ);
  IX1 := Min(N - 1, IX0 + 1);
  IZ1 := Min(N - 1, IZ0 + 1);
  FX := GX - IX0;
  FZ := GZ - IZ0;

  H00 := FHeights[IZ0 * N + IX0];
  H10 := FHeights[IZ0 * N + IX1];
  H01 := FHeights[IZ1 * N + IX0];
  H11 := FHeights[IZ1 * N + IX1];
  Result.DisplacementMeters := Lerp(FZ, Lerp(FX, H00, H10), Lerp(FX, H01, H11));

  C00 := FCompaction[IZ0 * N + IX0];
  C10 := FCompaction[IZ0 * N + IX1];
  C01 := FCompaction[IZ1 * N + IX0];
  C11 := FCompaction[IZ1 * N + IX1];
  Result.Compaction01 := Lerp(FZ, Lerp(FX, C00, C10), Lerp(FX, C01, C11));

  IXM := Max(0, Round(GX) - 1);
  IXP := Min(N - 1, Round(GX) + 1);
  IZM := Max(0, Round(GZ) - 1);
  IZP := Min(N - 1, Round(GZ) + 1);
  dHdX := (FHeights[Round(GZ) * N + IXP] - FHeights[Round(GZ) * N + IXM]) /
          Max(0.01, (IXP - IXM) * StepSz);
  dHdZ := (FHeights[IZP * N + Round(GX)] - FHeights[IZM * N + Round(GX)]) /
          Max(0.01, (IZP - IZM) * StepSz);
  LocalNorm := Vector3(-dHdX, 1.0, -dHdZ).Normalize;
  Result.SurfaceNormal := WT.MultDirection(LocalNorm).Normalize;
end;

function TCastleTrailStamper.MinDisplacementMeters: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FHeights) do
    if FHeights[I] < Result then
      Result := FHeights[I];
end;

function TCastleTrailStamper.MaxBermHeightMeters: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FHeights) do
    if FHeights[I] > Result then
      Result := FHeights[I];
end;

function TCastleTrailStamper.ActiveDeformedCellCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FHeights) do
    if Abs(FHeights[I]) > 0.001 then
      Inc(Result);
end;

function TCastleTrailStamper.TrailSummaryBadge: String;
begin
  Result := FormatDot('[SnowTrk:%dx%d Min=%.2fm Berm=+%.2fm]', [
    FGridResolution, FGridResolution, MinDisplacementMeters, MaxBermHeightMeters]);
end;

function TCastleTrailStamper.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('gridResolution', FGridResolution);
    Obj.Add('patchSizeMeters', FPatchSizeMeters);
    Obj.Add('maxSinkDepthMeters', FMaxSinkDepthMeters);
    Obj.Add('rimBermRatio01', FRimBermRatio01);
    Obj.Add('refillRateMetersPerSec', FRefillRateMetersPerSec);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleTrailStamper.SetConfigJson(const AValue: String);
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
      FPreset := TTrailMediumPreset(EnsureRange(Obj.Get('preset', Ord(FPreset)), 0, Ord(High(TTrailMediumPreset))));
      SetGridResolution(Obj.Get('gridResolution', FGridResolution));
      FPatchSizeMeters := Max(2.0, Obj.Get('patchSizeMeters', FPatchSizeMeters));
      FMaxSinkDepthMeters := Max(0.02, Obj.Get('maxSinkDepthMeters', FMaxSinkDepthMeters));
      FRimBermRatio01 := EnsureRange(Obj.Get('rimBermRatio01', FRimBermRatio01), 0.0, 1.0);
      FRefillRateMetersPerSec := Max(0.0, Obj.Get('refillRateMetersPerSec', FRefillRateMetersPerSec));
      RebuildPreviewMesh;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleTrailStamper,
    ['Environment & Weather', 'Snow, Mud & Sand Trail Stamper (TCastleTrailStamper)']);

end.
