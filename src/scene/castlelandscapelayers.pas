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

{ Unreal Engine 5.5-style Non-Destructive Landscape Edit Layers & Terrain-Carving
  Landscape Splines runtime (@link(TCastleLandscapeLayerTerrain)) featuring a
  composable stack of Additive / AlphaBlend / MinCarve / MaxRaise Edit Layers,
  ULandscapeSplinesComponent corridor heightmap Cut/Fill deformation with Hermite
  smoothstep embankment falloff, earthwork volume metering, and automatic
  4-channel splatmap weight painting (Grass / Rock / CobbleRoad / RiverGravel)
  (Phase 394 — UE 5.5 Landscape Edit Layers & ULandscapeSplinesComponent Parity). }
unit CastleLandscapeLayers;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Compositing blend mode of a @link(TLandscapeEditLayer) (UE 5.5 parity). }
  TLandscapeLayerBlendMode = (
    llbmAdditive,
    llbmAlphaBlend,
    llbmMinCarveOnly,
    llbmMaxRaiseOnly
  );

  { Height deformation constraint along a @link(TLandscapeCarveSpline). }
  TLandscapeSplineDeformMode = (
    lsdmBothRaiseAndLower,
    lsdmLowerOnlyTrench,
    lsdmRaiseOnlyCauseway
  );

  { 4-channel normalized terrain material splatmap channels. }
  TLandscapeSplatChannel = (
    lscGrassMeadow,
    lscCliffRock,
    lscCobbleRoad,
    lscRiverGravel
  );

  { Starter presets for @link(TCastleLandscapeLayerTerrain). }
  TLandscapeLayerPreset = (
    llpCustom,
    llpAlpinePassSwitchbackRoadAndRiver,
    llpDesertCanyonHighwayCauseway,
    llpMedievalMoatAndCastleApproach
  );

  { Single non-destructive Landscape Edit Layer in the compositing stack. }
  TLandscapeEditLayer = record
    LayerName: String;
    BlendMode: TLandscapeLayerBlendMode;
    Opacity: Single;
    Visible: Boolean;
    Locked: Boolean;
    ReservedForSplines: Boolean;
    HeightField: array of Single; { Target height (AlphaBlend/Min/Max) or Delta (Additive) }
    AlphaMask: array of Single;   { Per-vertex coverage alpha 0..1 for AlphaBlend }
    RoadWeight: array of Single;
    RiverWeight: array of Single;
  end;
  TLandscapeEditLayerArray = array of TLandscapeEditLayer;

  { Multi-point 3D terrain-carving spline (ULandscapeSplinesComponent parity). }
  TLandscapeCarveSpline = record
    SplineName: String;
    ControlPoints: array of TVector3;
    HalfWidthM: Single;
    SideFalloffM: Single;
    DeformMode: TLandscapeSplineDeformMode;
    PaintChannel: TLandscapeSplatChannel;
    Enabled: Boolean;
  end;
  TLandscapeCarveSplineArray = array of TLandscapeCarveSpline;

  { Earthwork & splatmap summary computed during stack evaluation. }
  TLandscapeEarthworkMetrics = record
    MinElevationM: Single;
    MaxElevationM: Single;
    CutExcavatedVolumeM3: Single;
    FillEmbankmentVolumeM3: Single;
    RoadPaintedAreaM2: Single;
    RiverPaintedAreaM2: Single;
    ActiveLayerCount: Integer;
    ActiveSplineCount: Integer;
  end;

  { Unreal Engine 5.5-style Non-Destructive Landscape Edit Layers & Splines component. }
  TCastleLandscapeLayerTerrain = class(TCastleTransform)
  private
    FPreset: TLandscapeLayerPreset;
    FLandscapeKey: String;
    FGridRes: Integer;
    FTerrainSizeM: Single;
    FShowPreviewTiles: Boolean;

    FLayers: TLandscapeEditLayerArray;
    FSplines: TLandscapeCarveSplineArray;
    FBaseBeforeSplinesHeights: array of Single;
    FFinalHeights: array of Single;
    FFinalSplatRGBA: array of TVector4; { X=Grass, Y=Rock, Z=Road, W=River }
    FMetrics: TLandscapeEarthworkMetrics;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TLandscapeLayerPreset);
    procedure SetShowPreviewTiles(const AValue: Boolean);
    function GetLandscapeJson: String;
    procedure SetLandscapeJson(const AValue: String);

    procedure ClearPreviewContainer;
    procedure SyncPreviewVisuals;
    procedure BakeSplinesIntoReservedLayer;
    class function ClosestPointOnSegmentXZ(const P: TVector2;
      const A, B: TVector3; out OutTargetY, OutDistXZ: Single): Single; static;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TLandscapeLayerPreset);

    { Non-Destructive Edit Layer Management }
    function FindLayerIndex(const ALayerName: String): Integer;
    function AddEditLayer(const ALayerName: String;
      const ABlendMode: TLandscapeLayerBlendMode;
      const AOpacity: Single = 1.0;
      const AReservedForSplines: Boolean = False): Integer;
    function SetLayerVisible(const ALayerName: String; const AVisible: Boolean): Boolean;
    function SetLayerOpacity(const ALayerName: String; const AOpacity: Single): Boolean;
    function MoveLayerOrder(const AFromIdx, AToIdx: Integer): Boolean;

    { Terrain-Carving Landscape Spline Management }
    function FindSplineIndex(const ASplineName: String): Integer;
    function AddOrUpdateSpline(const ASplineName: String;
      const APoints: array of TVector3;
      const AHalfWidthM, ASideFalloffM: Single;
      const ADeformMode: TLandscapeSplineDeformMode;
      const APaintChannel: TLandscapeSplatChannel): Integer;

    { Full Stack Evaluation & Sampling }
    procedure RecomposeLandscapeStack;
    function GridVertexWorldXZ(const GX, GZ: Integer): TVector2;
    function SampleHeightAtGrid(const GX, GZ: Integer): Single;
    function SampleBaseBeforeSplinesAtGrid(const GX, GZ: Integer): Single;
    function SampleSplatAtGrid(const GX, GZ: Integer): TVector4;
    function SampleHeightBilinear(const AWorldX, AWorldZ: Single): Single;
    function SampleSplatNearest(const AWorldX, AWorldZ: Single): TVector4;

    function LandscapeSummaryBadge: String;

    property GridRes: Integer read FGridRes;
    property TerrainSizeM: Single read FTerrainSizeM;
    property Layers: TLandscapeEditLayerArray read FLayers;
    property Splines: TLandscapeCarveSplineArray read FSplines;
    property Metrics: TLandscapeEarthworkMetrics read FMetrics;
  published
    property LandscapeKey: String read FLandscapeKey write FLandscapeKey;
    property ShowPreviewTiles: Boolean
      read FShowPreviewTiles write SetShowPreviewTiles default True;
    property LandscapeJson: String read GetLandscapeJson write SetLandscapeJson;
    property Preset: TLandscapeLayerPreset
      read FPreset write SetPreset default llpAlpinePassSwitchbackRoadAndRiver;
  end;

implementation

uses
  fpjson, jsonparser;

function SmoothStep01(const T: Single): Single;
var
  U: Single;
begin
  U := EnsureRange(T, 0.0, 1.0);
  Result := U * U * (3.0 - 2.0 * U);
end;

{ TCastleLandscapeLayerTerrain ----------------------------------------------- }

constructor TCastleLandscapeLayerTerrain.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLandscapeKey := 'LS_AlpineSwitchbackPass';
  FGridRes := 33;
  FTerrainSizeM := 64.0;
  FShowPreviewTiles := True;
  ApplyPreset(llpAlpinePassSwitchbackRoadAndRiver);
end;

destructor TCastleLandscapeLayerTerrain.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleLandscapeLayerTerrain.Loaded;
begin
  inherited;
  RecomposeLandscapeStack;
  SyncPreviewVisuals;
end;

function TCastleLandscapeLayerTerrain.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'LandscapeKey') or
     (PropertyName = 'ShowPreviewTiles') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLandscapeLayerTerrain.SetPreset(const AValue: TLandscapeLayerPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleLandscapeLayerTerrain.SetShowPreviewTiles(const AValue: Boolean);
begin
  if FShowPreviewTiles <> AValue then
  begin
    FShowPreviewTiles := AValue;
    SyncPreviewVisuals;
  end;
end;

function TCastleLandscapeLayerTerrain.GridVertexWorldXZ(
  const GX, GZ: Integer): TVector2;
var
  HalfS: Single;
begin
  HalfS := FTerrainSizeM * 0.5;
  Result.X := -HalfS + (GX / Max(1, FGridRes - 1)) * FTerrainSizeM;
  Result.Y := -HalfS + (GZ / Max(1, FGridRes - 1)) * FTerrainSizeM;
end;

function TCastleLandscapeLayerTerrain.FindLayerIndex(const ALayerName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FLayers) do
    if SameText(FLayers[I].LayerName, ALayerName) then
      Exit(I);
  Result := -1;
end;

function TCastleLandscapeLayerTerrain.AddEditLayer(const ALayerName: String;
  const ABlendMode: TLandscapeLayerBlendMode; const AOpacity: Single;
  const AReservedForSplines: Boolean): Integer;
var
  VertCnt, I: Integer;
begin
  Result := FindLayerIndex(ALayerName);
  if Result < 0 then
  begin
    Result := Length(FLayers);
    SetLength(FLayers, Result + 1);
  end;
  VertCnt := FGridRes * FGridRes;
  FLayers[Result].LayerName := ALayerName;
  FLayers[Result].BlendMode := ABlendMode;
  FLayers[Result].Opacity := EnsureRange(AOpacity, 0.0, 1.0);
  FLayers[Result].Visible := True;
  FLayers[Result].Locked := False;
  FLayers[Result].ReservedForSplines := AReservedForSplines;
  SetLength(FLayers[Result].HeightField, VertCnt);
  SetLength(FLayers[Result].AlphaMask, VertCnt);
  SetLength(FLayers[Result].RoadWeight, VertCnt);
  SetLength(FLayers[Result].RiverWeight, VertCnt);
  for I := 0 to VertCnt - 1 do
  begin
    FLayers[Result].HeightField[I] := 0.0;
    if ABlendMode = llbmAlphaBlend then
      FLayers[Result].AlphaMask[I] := 0.0
    else
      FLayers[Result].AlphaMask[I] := 1.0;
    FLayers[Result].RoadWeight[I] := 0.0;
    FLayers[Result].RiverWeight[I] := 0.0;
  end;
end;

function TCastleLandscapeLayerTerrain.SetLayerVisible(
  const ALayerName: String; const AVisible: Boolean): Boolean;
var
  Idx: Integer;
begin
  Idx := FindLayerIndex(ALayerName);
  if Idx < 0 then Exit(False);
  FLayers[Idx].Visible := AVisible;
  RecomposeLandscapeStack;
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleLandscapeLayerTerrain.SetLayerOpacity(
  const ALayerName: String; const AOpacity: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindLayerIndex(ALayerName);
  if Idx < 0 then Exit(False);
  FLayers[Idx].Opacity := EnsureRange(AOpacity, 0.0, 1.0);
  RecomposeLandscapeStack;
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleLandscapeLayerTerrain.MoveLayerOrder(
  const AFromIdx, AToIdx: Integer): Boolean;
var
  Tmp: TLandscapeEditLayer;
  I: Integer;
begin
  if (AFromIdx < 0) or (AFromIdx > High(FLayers)) or
     (AToIdx < 0) or (AToIdx > High(FLayers)) or (AFromIdx = AToIdx) then
    Exit(False);
  Tmp := FLayers[AFromIdx];
  if AFromIdx < AToIdx then
    for I := AFromIdx to AToIdx - 1 do
      FLayers[I] := FLayers[I + 1]
  else
    for I := AFromIdx downto AToIdx + 1 do
      FLayers[I] := FLayers[I - 1];
  FLayers[AToIdx] := Tmp;
  RecomposeLandscapeStack;
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleLandscapeLayerTerrain.FindSplineIndex(
  const ASplineName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSplines) do
    if SameText(FSplines[I].SplineName, ASplineName) then
      Exit(I);
  Result := -1;
end;

function TCastleLandscapeLayerTerrain.AddOrUpdateSpline(
  const ASplineName: String; const APoints: array of TVector3;
  const AHalfWidthM, ASideFalloffM: Single;
  const ADeformMode: TLandscapeSplineDeformMode;
  const APaintChannel: TLandscapeSplatChannel): Integer;
var
  I: Integer;
begin
  Result := FindSplineIndex(ASplineName);
  if Result < 0 then
  begin
    Result := Length(FSplines);
    SetLength(FSplines, Result + 1);
    FSplines[Result].SplineName := ASplineName;
  end;
  SetLength(FSplines[Result].ControlPoints, Length(APoints));
  for I := 0 to High(APoints) do
    FSplines[Result].ControlPoints[I] := APoints[I];
  FSplines[Result].HalfWidthM := Max(0.5, AHalfWidthM);
  FSplines[Result].SideFalloffM := Max(0.5, ASideFalloffM);
  FSplines[Result].DeformMode := ADeformMode;
  FSplines[Result].PaintChannel := APaintChannel;
  FSplines[Result].Enabled := True;
end;

class function TCastleLandscapeLayerTerrain.ClosestPointOnSegmentXZ(
  const P: TVector2; const A, B: TVector3;
  out OutTargetY, OutDistXZ: Single): Single;
var
  AB, AP, ClosestXZ: TVector2;
  LenSq, T: Single;
begin
  AB := Vector2(B.X - A.X, B.Z - A.Z);
  AP := Vector2(P.X - A.X, P.Y - A.Z);
  LenSq := AB.X * AB.X + AB.Y * AB.Y;
  if LenSq < 1e-6 then
    T := 0.0
  else
    T := EnsureRange((AP.X * AB.X + AP.Y * AB.Y) / LenSq, 0.0, 1.0);
  ClosestXZ := Vector2(A.X + AB.X * T, A.Z + AB.Y * T);
  OutDistXZ := Sqrt(Sqr(P.X - ClosestXZ.X) + Sqr(P.Y - ClosestXZ.Y));
  OutTargetY := A.Y + (B.Y - A.Y) * T;
  Result := T;
end;

procedure TCastleLandscapeLayerTerrain.ApplyPreset(const APreset: TLandscapeLayerPreset);
var
  LBase, L2, GX, GZ, Idx: Integer;
  PosXZ: TVector2;
  RDist, RidgeH, TerraceH: Single;
begin
  FPreset := APreset;
  if APreset = llpCustom then Exit;

  FLayers := nil;
  FSplines := nil;
  FGridRes := 33;
  FTerrainSizeM := 64.0;

  { Layer 0: Procedural Base Mountain / Canyon Topography (Additive) }
  LBase := AddEditLayer('00_BaseTopography', llbmAdditive, 1.0, False);
  { Layer 1: Secondary Sculpted Plateau / Butte (Additive) }
  L2 := AddEditLayer('01_SculptedPlateaus', llbmAdditive, 1.0, False);
  { Layer 2: Non-Destructive Spline Corridors (Reserved for Splines, AlphaBlend) }
  AddEditLayer('02_LandscapeSplines', llbmAlphaBlend, 1.0, True);

  for GZ := 0 to FGridRes - 1 do
    for GX := 0 to FGridRes - 1 do
    begin
      Idx := GZ * FGridRes + GX;
      PosXZ := GridVertexWorldXZ(GX, GZ);

      case APreset of
        llpDesertCanyonHighwayCauseway:
          begin
            FLandscapeKey := 'LS_DesertCanyonCauseway';
            RidgeH := 6.5 + 4.5 * Sin(PosXZ.X * 0.11) * Cos(PosXZ.Y * 0.08);
            TerraceH := -3.8 * Exp(-Sqr(PosXZ.X * 0.10));
            FLayers[LBase].HeightField[Idx] := RidgeH;
            FLayers[L2].HeightField[Idx] := TerraceH;
          end;

        llpMedievalMoatAndCastleApproach:
          begin
            FLandscapeKey := 'LS_CitadelMoatApproach';
            RDist := Sqrt(Sqr(PosXZ.X) + Sqr(PosXZ.Y));
            RidgeH := 2.0 + 7.5 * Exp(-Sqr(RDist / 16.0));
            FLayers[LBase].HeightField[Idx] := RidgeH;
            FLayers[L2].HeightField[Idx] := 1.5 * Cos(PosXZ.X * 0.15);
          end;
      else
        begin
          { Alpine Pass: High mountain ridge on West (X=-12, H=+12.5m) & East valley dip (X=+10, H=+1.5m) }
          FPreset := llpAlpinePassSwitchbackRoadAndRiver;
          FLandscapeKey := 'LS_AlpineSwitchbackPass';
          RidgeH := 5.2 + 6.8 * Exp(-Sqr((PosXZ.X + 12.0) / 11.5))
                    - 4.8 * Exp(-Sqr((PosXZ.X - 11.0) / 13.0))
                    + 1.2 * Sin(PosXZ.Y * 0.14);
          TerraceH := 2.2 * Exp(-Sqr((PosXZ.X + 2.0) / 8.0) - Sqr((PosXZ.Y - 12.0) / 9.0));
          FLayers[LBase].HeightField[Idx] := RidgeH;
          FLayers[L2].HeightField[Idx] := TerraceH;
        end;
      end;
    end;

  case APreset of
    llpDesertCanyonHighwayCauseway:
      AddOrUpdateSpline('Spline_RaisedCausewayHighway',
        [Vector3(-28, 7.2, -16), Vector3(-6, 7.2, -2), Vector3(12, 7.2, 6), Vector3(28, 7.2, 18)],
        3.6, 5.0, lsdmRaiseOnlyCauseway, lscCobbleRoad);

    llpMedievalMoatAndCastleApproach:
      begin
        AddOrUpdateSpline('Spline_OuterMoatTrench',
          [Vector3(-18, 0.4, -10), Vector3(-12, 0.4, 14), Vector3(14, 0.4, 14), Vector3(18, 0.4, -10)],
          3.2, 3.8, lsdmLowerOnlyTrench, lscRiverGravel);
        AddOrUpdateSpline('Spline_KingCauseway',
          [Vector3(0, 6.0, -28), Vector3(0, 7.5, -8), Vector3(0, 9.2, 4)],
          3.0, 4.0, lsdmBothRaiseAndLower, lscCobbleRoad);
      end;
  else
    begin
      { 1. Royal Cobble Switchback Road: cuts into the +12m West mountain ridge down to 6.5m
           AND fills a raised embankment causeway up to 6.5m across the +2.1m East valley! }
      AddOrUpdateSpline('Spline_AlpineCobbleRoad',
        [Vector3(-26.0, 6.5, -18.0),
         Vector3(-12.0, 6.5, 0.0),
         Vector3(2.0, 6.5, 4.0),
         Vector3(10.0, 6.5, 0.0),
         Vector3(25.0, 6.5, 14.0)],
        3.5, 5.2, lsdmBothRaiseAndLower, lscCobbleRoad);

      { 2. Glacial River Trench: carves a lower-only gravel riverbed in the South basin }
      AddOrUpdateSpline('Spline_GlacialRiverBed',
        [Vector3(-24.0, 1.8, -24.0),
         Vector3(-6.0, 1.5, -20.0),
         Vector3(12.0, 1.0, -18.0),
         Vector3(26.0, 0.6, -22.0)],
        2.8, 4.2, lsdmLowerOnlyTrench, lscRiverGravel);
    end;
  end;

  RecomposeLandscapeStack;
  SyncPreviewVisuals;
end;

procedure TCastleLandscapeLayerTerrain.BakeSplinesIntoReservedLayer;
var
  SplineLayerIdx, VertCnt, GX, GZ, VIdx, SIdx, K: Integer;
  PosXZ: TVector2;
  BaseH, SegTargetY, SegDist, BestDist, BestTargetY, CoreW, FallW, Alpha, PaintAlpha, DesiredH: Single;
begin
  SplineLayerIdx := -1;
  for SIdx := 0 to High(FLayers) do
    if FLayers[SIdx].ReservedForSplines then
    begin
      SplineLayerIdx := SIdx;
      Break;
    end;
  if SplineLayerIdx < 0 then Exit;

  VertCnt := FGridRes * FGridRes;
  for VIdx := 0 to VertCnt - 1 do
  begin
    FLayers[SplineLayerIdx].HeightField[VIdx] := FBaseBeforeSplinesHeights[VIdx];
    FLayers[SplineLayerIdx].AlphaMask[VIdx] := 0.0;
    FLayers[SplineLayerIdx].RoadWeight[VIdx] := 0.0;
    FLayers[SplineLayerIdx].RiverWeight[VIdx] := 0.0;
  end;

  for SIdx := 0 to High(FSplines) do
  begin
    if (not FSplines[SIdx].Enabled) or (Length(FSplines[SIdx].ControlPoints) < 2) then
      Continue;

    CoreW := FSplines[SIdx].HalfWidthM;
    FallW := FSplines[SIdx].SideFalloffM;

    for GZ := 0 to FGridRes - 1 do
      for GX := 0 to FGridRes - 1 do
      begin
        VIdx := GZ * FGridRes + GX;
        PosXZ := GridVertexWorldXZ(GX, GZ);

        BestDist := 1e30;
        BestTargetY := 0.0;
        for K := 0 to High(FSplines[SIdx].ControlPoints) - 1 do
        begin
          ClosestPointOnSegmentXZ(PosXZ,
            FSplines[SIdx].ControlPoints[K],
            FSplines[SIdx].ControlPoints[K + 1],
            SegTargetY, SegDist);
          if SegDist < BestDist then
          begin
            BestDist := SegDist;
            BestTargetY := SegTargetY;
          end;
        end;

        if BestDist > CoreW + FallW then Continue;

        if BestDist <= CoreW then
          Alpha := 1.0
        else
          Alpha := SmoothStep01(1.0 - (BestDist - CoreW) / FallW);

        { Tighter paint mask so road/river surface stays crisp inside the graded embankment }
        if BestDist <= CoreW then
          PaintAlpha := 1.0
        else
          PaintAlpha := SmoothStep01(Max(0.0, 1.0 - (BestDist - CoreW) / (FallW * 0.45)));

        BaseH := FLayers[SplineLayerIdx].HeightField[VIdx];
        DesiredH := BestTargetY;
        case FSplines[SIdx].DeformMode of
          lsdmLowerOnlyTrench:
            if DesiredH > BaseH then Continue;
          lsdmRaiseOnlyCauseway:
            if DesiredH < BaseH then Continue;
        else
          ; { lsdmBothRaiseAndLower: both Cut & Fill }
        end;

        FLayers[SplineLayerIdx].HeightField[VIdx] :=
          BaseH + (DesiredH - BaseH) * Alpha;
        FLayers[SplineLayerIdx].AlphaMask[VIdx] :=
          Max(FLayers[SplineLayerIdx].AlphaMask[VIdx], Alpha);

        if FSplines[SIdx].PaintChannel = lscCobbleRoad then
          FLayers[SplineLayerIdx].RoadWeight[VIdx] :=
            Max(FLayers[SplineLayerIdx].RoadWeight[VIdx], PaintAlpha)
        else if FSplines[SIdx].PaintChannel = lscRiverGravel then
          FLayers[SplineLayerIdx].RiverWeight[VIdx] :=
            Max(FLayers[SplineLayerIdx].RiverWeight[VIdx], PaintAlpha);
      end;
  end;
end;

procedure TCastleLandscapeLayerTerrain.RecomposeLandscapeStack;
var
  VertCnt, LIdx, GX, GZ, VIdx: Integer;
  CellSpacing, CellAreaM2, Op, EffA, CurH, LayerVal, DeltaH,
    RoadW, RiverW, RemW, DHX, DHZ, SlopeNorm: Single;
  ReachedSplineLayer: Boolean;
begin
  VertCnt := FGridRes * FGridRes;
  SetLength(FBaseBeforeSplinesHeights, VertCnt);
  SetLength(FFinalHeights, VertCnt);
  SetLength(FFinalSplatRGBA, VertCnt);

  for VIdx := 0 to VertCnt - 1 do
  begin
    FBaseBeforeSplinesHeights[VIdx] := 0.0;
    FFinalHeights[VIdx] := 0.0;
  end;

  FMetrics := Default(TLandscapeEarthworkMetrics);
  for LIdx := 0 to High(FSplines) do
    if FSplines[LIdx].Enabled then
      Inc(FMetrics.ActiveSplineCount);

  { Pass 1: Evaluate non-spline base sculpt layers so ReservedForSplines knows exact underlying ground }
  for LIdx := 0 to High(FLayers) do
  begin
    if FLayers[LIdx].ReservedForSplines then Break;
    if (not FLayers[LIdx].Visible) or (FLayers[LIdx].Opacity <= 0.0001) then Continue;
    Op := FLayers[LIdx].Opacity;
    for VIdx := 0 to VertCnt - 1 do
    begin
      CurH := FBaseBeforeSplinesHeights[VIdx];
      LayerVal := FLayers[LIdx].HeightField[VIdx];
      case FLayers[LIdx].BlendMode of
        llbmAdditive:
          CurH := CurH + LayerVal * Op;
        llbmAlphaBlend:
          begin
            EffA := FLayers[LIdx].AlphaMask[VIdx] * Op;
            CurH := CurH + (LayerVal - CurH) * EffA;
          end;
        llbmMinCarveOnly:
          CurH := CurH + (Min(CurH, LayerVal) - CurH) * Op;
        llbmMaxRaiseOnly:
          CurH := CurH + (Max(CurH, LayerVal) - CurH) * Op;
      end;
      FBaseBeforeSplinesHeights[VIdx] := CurH;
    end;
  end;

  { Pass 2: Bake active splines non-destructively into ReservedForSplines layer }
  BakeSplinesIntoReservedLayer;

  { Pass 3: Composite entire visible layer stack bottom-to-top + accumulate Road/River weights }
  CellSpacing := FTerrainSizeM / Max(1, FGridRes - 1);
  CellAreaM2 := CellSpacing * CellSpacing;
  ReachedSplineLayer := False;

  for VIdx := 0 to VertCnt - 1 do
    FFinalSplatRGBA[VIdx] := Vector4(1, 0, 0, 0);

  for LIdx := 0 to High(FLayers) do
  begin
    if (not FLayers[LIdx].Visible) or (FLayers[LIdx].Opacity <= 0.0001) then Continue;
    Inc(FMetrics.ActiveLayerCount);
    Op := FLayers[LIdx].Opacity;
    if FLayers[LIdx].ReservedForSplines then
      ReachedSplineLayer := True;

    for VIdx := 0 to VertCnt - 1 do
    begin
      CurH := FFinalHeights[VIdx];
      LayerVal := FLayers[LIdx].HeightField[VIdx];
      case FLayers[LIdx].BlendMode of
        llbmAdditive:
          CurH := CurH + LayerVal * Op;
        llbmAlphaBlend:
          begin
            EffA := FLayers[LIdx].AlphaMask[VIdx] * Op;
            CurH := CurH + (LayerVal - CurH) * EffA;
          end;
        llbmMinCarveOnly:
          CurH := CurH + (Min(CurH, LayerVal) - CurH) * Op;
        llbmMaxRaiseOnly:
          CurH := CurH + (Max(CurH, LayerVal) - CurH) * Op;
      end;
      FFinalHeights[VIdx] := CurH;

      FFinalSplatRGBA[VIdx].Z := Max(FFinalSplatRGBA[VIdx].Z,
        FLayers[LIdx].RoadWeight[VIdx] * Op);
      FFinalSplatRGBA[VIdx].W := Max(FFinalSplatRGBA[VIdx].W,
        FLayers[LIdx].RiverWeight[VIdx] * Op);
    end;
  end;

  { Pass 4: Normalize 4-channel Splatmap (Grass / Slope Rock / Cobble Road / River Gravel) + Earthwork }
  FMetrics.MinElevationM := 1e30;
  FMetrics.MaxElevationM := -1e30;
  for GZ := 0 to FGridRes - 1 do
    for GX := 0 to FGridRes - 1 do
    begin
      VIdx := GZ * FGridRes + GX;
      CurH := FFinalHeights[VIdx];
      FMetrics.MinElevationM := Min(FMetrics.MinElevationM, CurH);
      FMetrics.MaxElevationM := Max(FMetrics.MaxElevationM, CurH);

      if ReachedSplineLayer then
      begin
        DeltaH := CurH - FBaseBeforeSplinesHeights[VIdx];
        if DeltaH < -1e-3 then
          FMetrics.CutExcavatedVolumeM3 := FMetrics.CutExcavatedVolumeM3 + (-DeltaH) * CellAreaM2
        else if DeltaH > 1e-3 then
          FMetrics.FillEmbankmentVolumeM3 := FMetrics.FillEmbankmentVolumeM3 + DeltaH * CellAreaM2;
      end;

      RoadW := EnsureRange(FFinalSplatRGBA[VIdx].Z, 0.0, 1.0);
      RiverW := EnsureRange(FFinalSplatRGBA[VIdx].W * (1.0 - RoadW), 0.0, 1.0);
      if RoadW > 0.35 then
        FMetrics.RoadPaintedAreaM2 := FMetrics.RoadPaintedAreaM2 + CellAreaM2;
      if RiverW > 0.35 then
        FMetrics.RiverPaintedAreaM2 := FMetrics.RiverPaintedAreaM2 + CellAreaM2;

      { Auto-slope cliff rock vs meadow grass on remaining weight }
      DHX := SampleHeightAtGrid(Min(FGridRes - 1, GX + 1), GZ) -
             SampleHeightAtGrid(Max(0, GX - 1), GZ);
      DHZ := SampleHeightAtGrid(GX, Min(FGridRes - 1, GZ + 1)) -
             SampleHeightAtGrid(GX, Max(0, GZ - 1));
      SlopeNorm := EnsureRange(Sqrt(DHX * DHX + DHZ * DHZ) / (2.0 * CellSpacing), 0.0, 1.0);

      RemW := Max(0.0, 1.0 - RoadW - RiverW);
      FFinalSplatRGBA[VIdx] := Vector4(
        RemW * (1.0 - SlopeNorm),
        RemW * SlopeNorm,
        RoadW,
        RiverW);
    end;
end;

function TCastleLandscapeLayerTerrain.SampleHeightAtGrid(
  const GX, GZ: Integer): Single;
var
  CX, CZ: Integer;
begin
  if Length(FFinalHeights) = 0 then Exit(0.0);
  CX := EnsureRange(GX, 0, FGridRes - 1);
  CZ := EnsureRange(GZ, 0, FGridRes - 1);
  Result := FFinalHeights[CZ * FGridRes + CX];
end;

function TCastleLandscapeLayerTerrain.SampleBaseBeforeSplinesAtGrid(
  const GX, GZ: Integer): Single;
var
  CX, CZ: Integer;
begin
  if Length(FBaseBeforeSplinesHeights) = 0 then Exit(0.0);
  CX := EnsureRange(GX, 0, FGridRes - 1);
  CZ := EnsureRange(GZ, 0, FGridRes - 1);
  Result := FBaseBeforeSplinesHeights[CZ * FGridRes + CX];
end;

function TCastleLandscapeLayerTerrain.SampleSplatAtGrid(
  const GX, GZ: Integer): TVector4;
var
  CX, CZ: Integer;
begin
  if Length(FFinalSplatRGBA) = 0 then Exit(Vector4(1, 0, 0, 0));
  CX := EnsureRange(GX, 0, FGridRes - 1);
  CZ := EnsureRange(GZ, 0, FGridRes - 1);
  Result := FFinalSplatRGBA[CZ * FGridRes + CX];
end;

function TCastleLandscapeLayerTerrain.SampleHeightBilinear(
  const AWorldX, AWorldZ: Single): Single;
var
  HalfS, FX, FZ, TX, TZ, H00, H10, H01, H11: Single;
  X0, Z0, X1, Z1: Integer;
begin
  HalfS := FTerrainSizeM * 0.5;
  FX := EnsureRange((AWorldX + HalfS) / FTerrainSizeM, 0.0, 1.0) * (FGridRes - 1);
  FZ := EnsureRange((AWorldZ + HalfS) / FTerrainSizeM, 0.0, 1.0) * (FGridRes - 1);
  X0 := Floor(FX);
  Z0 := Floor(FZ);
  X1 := Min(FGridRes - 1, X0 + 1);
  Z1 := Min(FGridRes - 1, Z0 + 1);
  TX := FX - X0;
  TZ := FZ - Z0;
  H00 := SampleHeightAtGrid(X0, Z0);
  H10 := SampleHeightAtGrid(X1, Z0);
  H01 := SampleHeightAtGrid(X0, Z1);
  H11 := SampleHeightAtGrid(X1, Z1);
  Result := (H00 + (H10 - H00) * TX) * (1.0 - TZ) +
            (H01 + (H11 - H01) * TX) * TZ;
end;

function TCastleLandscapeLayerTerrain.SampleSplatNearest(
  const AWorldX, AWorldZ: Single): TVector4;
var
  HalfS: Single;
  GX, GZ: Integer;
begin
  HalfS := FTerrainSizeM * 0.5;
  GX := Round(EnsureRange((AWorldX + HalfS) / FTerrainSizeM, 0.0, 1.0) * (FGridRes - 1));
  GZ := Round(EnsureRange((AWorldZ + HalfS) / FTerrainSizeM, 0.0, 1.0) * (FGridRes - 1));
  Result := SampleSplatAtGrid(GX, GZ);
end;

procedure TCastleLandscapeLayerTerrain.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
  begin
    Remove(FPreviewContainer);
    FreeAndNil(FPreviewContainer);
  end;
end;

procedure TCastleLandscapeLayerTerrain.SyncPreviewVisuals;
var
  GX, GZ: Integer;
  PosXZ: TVector2;
  H: Single;
  Sp: TVector4;
  B: TCastleBox;
  TileW: Single;
begin
  ClearPreviewContainer;
  if (not FShowPreviewTiles) or (csDestroying in ComponentState) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  Add(FPreviewContainer);

  TileW := (FTerrainSizeM / 8.0) * 0.96;
  GZ := 2;
  while GZ < FGridRes do
  begin
    GX := 2;
    while GX < FGridRes do
    begin
      PosXZ := GridVertexWorldXZ(GX, GZ);
      H := SampleHeightAtGrid(GX, GZ);
      Sp := SampleSplatAtGrid(GX, GZ);

      B := TCastleBox.Create(FPreviewContainer);
      B.SetTransient;
      B.Size := Vector3(TileW, Max(0.3, H + 4.0), TileW);
      B.Translation := Vector3(PosXZ.X, (H - 4.0) * 0.5, PosXZ.Y);
      B.Color := Vector4(
        0.26 * Sp.X + 0.48 * Sp.Y + 0.68 * Sp.Z + 0.22 * Sp.W,
        0.56 * Sp.X + 0.46 * Sp.Y + 0.62 * Sp.Z + 0.48 * Sp.W,
        0.24 * Sp.X + 0.44 * Sp.Y + 0.52 * Sp.Z + 0.72 * Sp.W,
        1.0);
      FPreviewContainer.Add(B);
      Inc(GX, 4);
    end;
    Inc(GZ, 4);
  end;
end;

function TCastleLandscapeLayerTerrain.GetLandscapeJson: String;
var
  Root, LayerObj: TJSONObject;
  LayerArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('landscapeKey', FLandscapeKey);
    LayerArr := TJSONArray.Create;
    Root.Add('layers', LayerArr);
    for I := 0 to High(FLayers) do
    begin
      LayerObj := TJSONObject.Create;
      LayerObj.Add('name', FLayers[I].LayerName);
      LayerObj.Add('visible', FLayers[I].Visible);
      LayerObj.Add('opacity', FLayers[I].Opacity);
      LayerArr.Add(LayerObj);
    end;
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleLandscapeLayerTerrain.SetLandscapeJson(const AValue: String);
var
  Data: TJSONData;
  Root, LayerObj: TJSONObject;
  LayerArr: TJSONArray;
  I, Idx: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    FLandscapeKey := Root.Get('landscapeKey', FLandscapeKey);
    LayerArr := Root.Find('layers', jtArray) as TJSONArray;
    if LayerArr <> nil then
      for I := 0 to LayerArr.Count - 1 do
        if LayerArr.Items[I] is TJSONObject then
        begin
          LayerObj := TJSONObject(LayerArr.Items[I]);
          Idx := FindLayerIndex(LayerObj.Get('name', ''));
          if Idx >= 0 then
          begin
            FLayers[Idx].Visible := LayerObj.Get('visible', True);
            FLayers[Idx].Opacity := EnsureRange(LayerObj.Get('opacity', 1.0), 0.0, 1.0);
          end;
        end;
    RecomposeLandscapeStack;
    SyncPreviewVisuals;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleLandscapeLayerTerrain.LandscapeSummaryBadge: String;
begin
  Result := Format('[Landscape:%s Layers=%d/%d Splines=%d Cut=%.0fm^3 Fill=%.0fm^3]',
    [FLandscapeKey, FMetrics.ActiveLayerCount, Length(FLayers),
     FMetrics.ActiveSplineCount, FMetrics.CutExcavatedVolumeM3,
     FMetrics.FillEmbankmentVolumeM3]);
end;

initialization
  RegisterSerializableComponent(TCastleLandscapeLayerTerrain,
    ['World & Environment', 'Landscape Edit Layers & Terrain-Carving Splines']);
end.
