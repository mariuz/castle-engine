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

{ Unreal Engine 5.5-style Static Lightmap & Ambient Occlusion Atlas Baker
  (GPU Lightmass / ALightmassImportanceVolume Parity) featuring non-overlapping
  UV2 chart atlas packing, shadow-ray direct illumination, Fibonacci cosine-
  weighted hemisphere sky AO, multi-bounce diffuse radiosity color bleeding,
  2-texel gutter seam dilation, LightingNeedsRebuild tracking, and lossless
  JSON serialization (Phase 399). }
unit CastleLightmassBaker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleUtils, CastleClassUtils, CastleVectors,
  CastleComponentSerialize, CastleTransform;

type
  TLightmassBakePreset = (
    lbpCornellColorBleedRoom,
    lbpArchwaySunbeamCloister,
    lbpSubterraneanTorchCrypt
  );

  TLightmassQualityTier = (
    lqtPreviewFast,
    lqtMediumProduction,
    lqtProductionUltra
  );

  TLightmassViewChannel = (
    lvcCombinedTotalLighting,
    lvcIndirectGiRadiosityOnly,
    lvcAmbientOcclusionOnly,
    lvcUv2ChartPackingDilate
  );

  TLightmassSurfaceChart = record
    ChartId: Integer;
    ChartName: String;
    PatchOrigin: TVector3; { Corner at (u=0, v=0) }
    AxisU: TVector3;       { Full width vector }
    AxisV: TVector3;       { Full height vector }
    PatchNormal: TVector3;
    AlbedoRGB: TVector3;
    AtlasX, AtlasY, AtlasW, AtlasH: Integer;
  end;
  TLightmassSurfaceChartArray = array of TLightmassSurfaceChart;

  TLightmassTexel = record
    { >= 0: interior chart Id; -2: dilated seam border texel; -1: empty gutter }
    OwnerState: Integer;
    SourceChartId: Integer;
    WorldPos: TVector3;
    WorldNormal: TVector3;
    AlbedoRGB: TVector3;
    DirectRGB: TVector3;
    IndirectRGB: TVector3;
    SkyAo01: Single;
    TotalRGB: TVector3;
  end;
  TLightmassTexelArray = array of TLightmassTexel;

  TCastleLightmassBaker = class(TCastleTransform)
  private
    FPreset: TLightmassBakePreset;
    FQualityTier: TLightmassQualityTier;
    FAtlasResolution: Integer;
    FIndirectBounces: Integer;
    FIndirectIntensity: Single;
    FSunIntensity: Single;
    FSkyIntensity: Single;
    FDilateGutterPasses: Integer;
    FViewChannel: TLightmassViewChannel;
    FLightingNeedsRebuild: Boolean;

    FCharts: TLightmassSurfaceChartArray;
    FTexels: TLightmassTexelArray;
    FBakeDataJson: String;

    procedure SetPreset(const AValue: TLightmassBakePreset);
    procedure SetQualityTier(const AValue: TLightmassQualityTier);
    procedure SetAtlasResolution(const AValue: Integer);
    procedure SetIndirectBounces(const AValue: Integer);
    procedure SetIndirectIntensity(const AValue: Single);
    procedure SetSunIntensity(const AValue: Single);
    procedure SetSkyIntensity(const AValue: Single);
    procedure SetDilateGutterPasses(const AValue: Integer);
    function GetBakeDataJson: String;
    procedure SetBakeDataJson(const AValue: String);

    procedure BuildPresetChartsAndLayout;
    function RaycastCharts(const RayOrig, RayDir: TVector3;
      const IgnoreChartId: Integer;
      out HitDist: Single; out HitChartId: Integer;
      out HitU, HitV: Single): Boolean;
    procedure DilateGutterSeamTexels(const APasses: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function RaysPerTexelForQuality(const AQuality: TLightmassQualityTier): Integer; static;

    { Run full UV2 rasterization + Direct Shadow + Hemisphere AO + Multi-Bounce GI + Gutter Dilation }
    procedure BakeStaticLightmaps;
    procedure InvalidateLighting;

    function TexelIndex(const AX, AY: Integer): Integer;
    function SampleChartTexelNearUV(const AChartId: Integer;
      const AU, AV: Single): TLightmassTexel;
    function EvaluateAtlasDisplayRGB(const AX, AY: Integer): TVector3;

    function ChartCount: Integer;
    function ValidInteriorTexelCount: Integer;
    function DilatedBorderTexelCount: Integer;
    function UndilatedAdjacentGutterCount: Integer;
    function AverageSkyAo01: Single;
    function AverageIndirectLuminance: Single;
    function LightmassSummaryBadge: String;

    property Charts: TLightmassSurfaceChartArray read FCharts;
    property Texels: TLightmassTexelArray read FTexels;
  published
    property Preset: TLightmassBakePreset
      read FPreset write SetPreset default lbpCornellColorBleedRoom;
    property QualityTier: TLightmassQualityTier
      read FQualityTier write SetQualityTier default lqtMediumProduction;
    property AtlasResolution: Integer
      read FAtlasResolution write SetAtlasResolution default 32;
    property IndirectBounces: Integer
      read FIndirectBounces write SetIndirectBounces default 2;
    property IndirectIntensity: Single
      read FIndirectIntensity write SetIndirectIntensity {$ifdef FPC}default 1.35{$endif};
    property SunIntensity: Single
      read FSunIntensity write SetSunIntensity {$ifdef FPC}default 2.20{$endif};
    property SkyIntensity: Single
      read FSkyIntensity write SetSkyIntensity {$ifdef FPC}default 0.65{$endif};
    property DilateGutterPasses: Integer
      read FDilateGutterPasses write SetDilateGutterPasses default 2;
    property ViewChannel: TLightmassViewChannel
      read FViewChannel write FViewChannel default lvcCombinedTotalLighting;
    property LightingNeedsRebuild: Boolean
      read FLightingNeedsRebuild write FLightingNeedsRebuild default False;
    property BakeDataJson: String read GetBakeDataJson write SetBakeDataJson stored True;
  end;

function LightmassPresetDisplayName(const APreset: TLightmassBakePreset): String;
function LightmassViewChannelDisplayName(const AChan: TLightmassViewChannel): String;

implementation

function LightmassPresetDisplayName(const APreset: TLightmassBakePreset): String;
begin
  case APreset of
    lbpCornellColorBleedRoom:  Result := 'Cornell Color-Bleed GI Room (Red/Blue Walls + Occluder)';
    lbpArchwaySunbeamCloister: Result := 'Sunbeam Cloister Courtyard (Warm Sandstone Bounce)';
    lbpSubterraneanTorchCrypt: Result := 'Subterranean Torch Crypt (Deep Corner AO + Amber GI)';
  end;
end;

function LightmassViewChannelDisplayName(const AChan: TLightmassViewChannel): String;
begin
  case AChan of
    lvcCombinedTotalLighting:   Result := 'Combined Static Lightmap (Direct + GI + AO)';
    lvcIndirectGiRadiosityOnly: Result := 'Indirect Multi-Bounce GI Radiosity Only';
    lvcAmbientOcclusionOnly:    Result := 'Baked Sky / Contact Ambient Occlusion';
    lvcUv2ChartPackingDilate:   Result := 'UV2 Lightmap Charts + 2px Dilated Gutters';
  end;
end;

procedure BuildTangentBasis(const N: TVector3; out T, B: TVector3);
var
  RefUp: TVector3;
begin
  if Abs(N.Y) < 0.92 then
    RefUp := Vector3(0, 1, 0)
  else
    RefUp := Vector3(1, 0, 0);
  T := TVector3.CrossProduct(RefUp, N).Normalize;
  B := TVector3.CrossProduct(N, T).Normalize;
end;

function CosineHemisphereDir(const SampleIdx, SampleTotal: Integer;
  const N, T, B: TVector3): TVector3;
const
  GoldenAngle = 2.39996323;
var
  U1, RadiusXY, Theta, LocalX, LocalY, LocalZ: Single;
begin
  U1 := (SampleIdx + 0.5) / Max(1, SampleTotal);
  RadiusXY := Sqrt(EnsureRange(U1, 0.0, 0.9999));
  Theta := SampleIdx * GoldenAngle;
  LocalX := RadiusXY * Cos(Theta);
  LocalY := RadiusXY * Sin(Theta);
  LocalZ := Sqrt(Max(0.0001, 1.0 - U1));
  Result := (T * LocalX + B * LocalY + N * LocalZ).Normalize;
end;

{ TCastleLightmassBaker }

constructor TCastleLightmassBaker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := lbpCornellColorBleedRoom;
  FQualityTier := lqtMediumProduction;
  FAtlasResolution := 32;
  FIndirectBounces := 2;
  FIndirectIntensity := 1.35;
  FSunIntensity := 2.20;
  FSkyIntensity := 0.65;
  FDilateGutterPasses := 2;
  FViewChannel := lvcCombinedTotalLighting;
  FLightingNeedsRebuild := False;

  BuildPresetChartsAndLayout;
  BakeStaticLightmaps;
end;

function TCastleLightmassBaker.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'QualityTier') or
     (PropertyName = 'AtlasResolution') or
     (PropertyName = 'IndirectBounces') or
     (PropertyName = 'IndirectIntensity') or
     (PropertyName = 'SunIntensity') or
     (PropertyName = 'SkyIntensity') or
     (PropertyName = 'DilateGutterPasses') or
     (PropertyName = 'ViewChannel') or
     (PropertyName = 'LightingNeedsRebuild') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleLightmassBaker.RaysPerTexelForQuality(
  const AQuality: TLightmassQualityTier): Integer;
begin
  case AQuality of
    lqtPreviewFast:      Result := 16;
    lqtMediumProduction: Result := 32;
    lqtProductionUltra:  Result := 64;
  end;
end;

procedure TCastleLightmassBaker.SetPreset(const AValue: TLightmassBakePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  BuildPresetChartsAndLayout;
  BakeStaticLightmaps;
end;

procedure TCastleLightmassBaker.SetQualityTier(const AValue: TLightmassQualityTier);
begin
  if FQualityTier = AValue then Exit;
  FQualityTier := AValue;
  FLightingNeedsRebuild := True;
end;

procedure TCastleLightmassBaker.SetAtlasResolution(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(AValue, 24, 64);
  if FAtlasResolution = Clamped then Exit;
  FAtlasResolution := Clamped;
  BuildPresetChartsAndLayout;
  BakeStaticLightmaps;
end;

procedure TCastleLightmassBaker.SetIndirectBounces(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(AValue, 0, 5);
  if FIndirectBounces = Clamped then Exit;
  FIndirectBounces := Clamped;
  FLightingNeedsRebuild := True;
end;

procedure TCastleLightmassBaker.SetIndirectIntensity(const AValue: Single);
begin
  FIndirectIntensity := EnsureRange(AValue, 0.0, 5.0);
  FLightingNeedsRebuild := True;
end;

procedure TCastleLightmassBaker.SetSunIntensity(const AValue: Single);
begin
  FSunIntensity := EnsureRange(AValue, 0.0, 10.0);
  FLightingNeedsRebuild := True;
end;

procedure TCastleLightmassBaker.SetSkyIntensity(const AValue: Single);
begin
  FSkyIntensity := EnsureRange(AValue, 0.0, 5.0);
  FLightingNeedsRebuild := True;
end;

procedure TCastleLightmassBaker.SetDilateGutterPasses(const AValue: Integer);
begin
  FDilateGutterPasses := EnsureRange(AValue, 0, 4);
  FLightingNeedsRebuild := True;
end;

procedure TCastleLightmassBaker.InvalidateLighting;
begin
  FLightingNeedsRebuild := True;
end;

function TCastleLightmassBaker.TexelIndex(const AX, AY: Integer): Integer;
begin
  Result := AY * FAtlasResolution + AX;
end;

procedure TCastleLightmassBaker.BuildPresetChartsAndLayout;
var
  Res, CellW, CellH, Gutter, InnerW, InnerH, I, Col, Row: Integer;
  WhiteCol, LeftCol, RightCol, BackCol, PillarCol: TVector3;

  procedure AddChart(const AId: Integer; const AName: String;
    const AOrig, AU, AV, ANorm, AAlbedo: TVector3);
  begin
    FCharts[AId].ChartId := AId;
    FCharts[AId].ChartName := AName;
    FCharts[AId].PatchOrigin := AOrig;
    FCharts[AId].AxisU := AU;
    FCharts[AId].AxisV := AV;
    FCharts[AId].PatchNormal := ANorm.Normalize;
    FCharts[AId].AlbedoRGB := AAlbedo;
  end;

begin
  SetLength(FCharts, 6);
  case FPreset of
    lbpCornellColorBleedRoom:
      begin
        WhiteCol  := Vector3(0.82, 0.82, 0.80);
        LeftCol   := Vector3(0.88, 0.10, 0.08); { Saturated Cornell Red Left Wall (-X) }
        RightCol  := Vector3(0.08, 0.24, 0.88); { Saturated Cornell Blue Right Wall (+X) }
        BackCol   := Vector3(0.80, 0.80, 0.78);
        PillarCol := Vector3(0.76, 0.74, 0.70);
      end;
    lbpArchwaySunbeamCloister:
      begin
        WhiteCol  := Vector3(0.84, 0.74, 0.56);
        LeftCol   := Vector3(0.78, 0.52, 0.28);
        RightCol  := Vector3(0.42, 0.62, 0.44);
        BackCol   := Vector3(0.80, 0.70, 0.54);
        PillarCol := Vector3(0.72, 0.64, 0.50);
      end;
    lbpSubterraneanTorchCrypt:
      begin
        WhiteCol  := Vector3(0.46, 0.44, 0.42);
        LeftCol   := Vector3(0.86, 0.42, 0.12);
        RightCol  := Vector3(0.24, 0.36, 0.48);
        BackCol   := Vector3(0.42, 0.40, 0.38);
        PillarCol := Vector3(0.52, 0.48, 0.44);
      end;
  end;

  { 6m x 4m x 6m room: X in [-3..+3], Y in [0..4], Z in [-3..+3] (front +Z open skylight!) }
  AddChart(0, 'Chart0_FloorSlab',
    Vector3(-3, 0, -3), Vector3(6, 0, 0), Vector3(0, 0, 6), Vector3(0, 1, 0), WhiteCol);
  AddChart(1, 'Chart1_LeftRedWall',
    Vector3(-3, 0, -3), Vector3(0, 0, 6), Vector3(0, 4, 0), Vector3(1, 0, 0), LeftCol);
  AddChart(2, 'Chart2_RightBlueWall',
    Vector3(3, 0, 3), Vector3(0, 0, -6), Vector3(0, 4, 0), Vector3(-1, 0, 0), RightCol);
  AddChart(3, 'Chart3_BackWall',
    Vector3(-3, 0, -3), Vector3(6, 0, 0), Vector3(0, 4, 0), Vector3(0, 0, 1), BackCol);
  AddChart(4, 'Chart4_CenterOccluderTop',
    Vector3(-0.85, 1.50, -0.85), Vector3(1.70, 0, 0), Vector3(0, 0, 1.70), Vector3(0, 1, 0), PillarCol);
  AddChart(5, 'Chart5_CenterOccluderFront',
    Vector3(-0.85, 0.0, 0.85), Vector3(1.70, 0, 0), Vector3(0, 1.50, 0), Vector3(0, 0, 1), PillarCol);

  { Pack 6 charts into a 3x2 UV2 Lightmap Atlas grid with guaranteed >= 2px gutter borders! }
  Res := FAtlasResolution;
  Gutter := 2;
  CellW := Res div 3;
  CellH := Res div 2;
  InnerW := Max(4, CellW - Gutter * 2);
  InnerH := Max(4, CellH - Gutter * 2);

  for I := 0 to High(FCharts) do
  begin
    Col := I mod 3;
    Row := I div 3;
    FCharts[I].AtlasX := Col * CellW + Gutter;
    FCharts[I].AtlasY := Row * CellH + Gutter;
    FCharts[I].AtlasW := InnerW;
    FCharts[I].AtlasH := InnerH;
  end;
end;

function TCastleLightmassBaker.RaycastCharts(const RayOrig, RayDir: TVector3;
  const IgnoreChartId: Integer;
  out HitDist: Single; out HitChartId: Integer;
  out HitU, HitV: Single): Boolean;
var
  I: Integer;
  Denom, TDist, UVal, VVal, LenUSq, LenVSq, BoxTMin, BoxTMax, T1, T2, Tmp: Single;
  P, Rel: TVector3;
  AxisIdx: Integer;
  BoxMin, BoxMax: TVector3;
begin
  Result := False;
  HitDist := MaxSingle;
  HitChartId := -1;
  HitU := 0.0;
  HitV := 0.0;

  for I := 0 to High(FCharts) do
  begin
    if I = IgnoreChartId then Continue;
    Denom := TVector3.DotProduct(RayDir, FCharts[I].PatchNormal);
    if Abs(Denom) < 1e-5 then Continue;

    TDist := TVector3.DotProduct(FCharts[I].PatchOrigin - RayOrig, FCharts[I].PatchNormal) / Denom;
    if (TDist <= 0.02) or (TDist >= HitDist) then Continue;

    P := RayOrig + RayDir * TDist;
    Rel := P - FCharts[I].PatchOrigin;
    LenUSq := Max(1e-6, FCharts[I].AxisU.LengthSqr);
    LenVSq := Max(1e-6, FCharts[I].AxisV.LengthSqr);
    UVal := TVector3.DotProduct(Rel, FCharts[I].AxisU) / LenUSq;
    VVal := TVector3.DotProduct(Rel, FCharts[I].AxisV) / LenVSq;

    if (UVal >= 0.0) and (UVal <= 1.0) and (VVal >= 0.0) and (VVal <= 1.0) then
    begin
      HitDist := TDist;
      HitChartId := I;
      HitU := UVal;
      HitV := VVal;
      Result := True;
    end;
  end;

  { Also intersect the solid 3D Center Occluder Block [-0.85..+0.85, 0..1.50, -0.85..+0.85]
    so floor texels behind/around the block get genuine 3D shadow umbra & contact AO! }
  if (IgnoreChartId <> 4) and (IgnoreChartId <> 5) then
  begin
    BoxMin := Vector3(-0.85, 0.0, -0.85);
    BoxMax := Vector3(0.85, 1.50, 0.85);
    BoxTMin := 0.02;
    BoxTMax := HitDist;
    for AxisIdx := 0 to 2 do
    begin
      if Abs(RayDir.Data[AxisIdx]) < 1e-6 then
      begin
        if (RayOrig.Data[AxisIdx] < BoxMin.Data[AxisIdx]) or
           (RayOrig.Data[AxisIdx] > BoxMax.Data[AxisIdx]) then
        begin
          BoxTMin := BoxTMax + 1.0;
          Break;
        end;
      end else
      begin
        T1 := (BoxMin.Data[AxisIdx] - RayOrig.Data[AxisIdx]) / RayDir.Data[AxisIdx];
        T2 := (BoxMax.Data[AxisIdx] - RayOrig.Data[AxisIdx]) / RayDir.Data[AxisIdx];
        if T1 > T2 then
        begin
          Tmp := T1;
          T1 := T2;
          T2 := Tmp;
        end;
        if T1 > BoxTMin then BoxTMin := T1;
        if T2 < BoxTMax then BoxTMax := T2;
        if BoxTMin > BoxTMax then Break;
      end;
    end;
    if BoxTMin <= BoxTMax then
    begin
      HitDist := BoxTMin;
      HitChartId := 5;
      HitU := 0.5;
      HitV := 0.5;
      Result := True;
    end;
  end;
end;

function TCastleLightmassBaker.SampleChartTexelNearUV(const AChartId: Integer;
  const AU, AV: Single): TLightmassTexel;
var
  Ch: TLightmassSurfaceChart;
  TX, TY: Integer;
begin
  Result := Default(TLightmassTexel);
  if (AChartId < 0) or (AChartId > High(FCharts)) then Exit;
  Ch := FCharts[AChartId];
  TX := Ch.AtlasX + EnsureRange(Round(AU * (Ch.AtlasW - 1)), 0, Ch.AtlasW - 1);
  TY := Ch.AtlasY + EnsureRange(Round(AV * (Ch.AtlasH - 1)), 0, Ch.AtlasH - 1);
  Result := FTexels[TexelIndex(TX, TY)];
end;

procedure TCastleLightmassBaker.DilateGutterSeamTexels(const APasses: Integer);
const
  DX8: array[0..7] of Integer = (-1, 1, 0, 0, -1, 1, -1, 1);
  DY8: array[0..7] of Integer = (0, 0, -1, 1, -1, -1, 1, 1);
var
  PassIdx, X, Y, K, NX, NY, Idx, NIdx, ValidNeighbors: Integer;
  Prev: TLightmassTexelArray;
  AccumTotal, AccumDirect, AccumIndirect: TVector3;
  AccumAo: Single;
  FirstChartId: Integer;
begin
  for PassIdx := 1 to APasses do
  begin
    SetLength(Prev, Length(FTexels));
    for Idx := 0 to High(FTexels) do
      Prev[Idx] := FTexels[Idx];

    for Y := 0 to FAtlasResolution - 1 do
      for X := 0 to FAtlasResolution - 1 do
      begin
        Idx := TexelIndex(X, Y);
        if Prev[Idx].OwnerState <> -1 then Continue;

        ValidNeighbors := 0;
        AccumTotal := TVector3.Zero;
        AccumDirect := TVector3.Zero;
        AccumIndirect := TVector3.Zero;
        AccumAo := 0.0;
        FirstChartId := -1;

        for K := 0 to 7 do
        begin
          NX := X + DX8[K];
          NY := Y + DY8[K];
          if (NX < 0) or (NX >= FAtlasResolution) or
             (NY < 0) or (NY >= FAtlasResolution) then
            Continue;
          NIdx := TexelIndex(NX, NY);
          if Prev[NIdx].OwnerState <> -1 then
          begin
            { Prioritize 4-connected cardinal neighbors first if present }
            if (K < 4) or (ValidNeighbors = 0) then
            begin
              AccumTotal := AccumTotal + Prev[NIdx].TotalRGB;
              AccumDirect := AccumDirect + Prev[NIdx].DirectRGB;
              AccumIndirect := AccumIndirect + Prev[NIdx].IndirectRGB;
              AccumAo := AccumAo + Prev[NIdx].SkyAo01;
              if FirstChartId < 0 then
                FirstChartId := Prev[NIdx].SourceChartId;
              Inc(ValidNeighbors);
            end;
          end;
        end;

        if ValidNeighbors > 0 then
        begin
          FTexels[Idx].OwnerState := -2; { Dilated Seam Gutter Texel! }
          FTexels[Idx].SourceChartId := FirstChartId;
          FTexels[Idx].TotalRGB := AccumTotal / ValidNeighbors;
          FTexels[Idx].DirectRGB := AccumDirect / ValidNeighbors;
          FTexels[Idx].IndirectRGB := AccumIndirect / ValidNeighbors;
          FTexels[Idx].SkyAo01 := AccumAo / ValidNeighbors;
        end;
      end;
  end;
end;

procedure TCastleLightmassBaker.BakeStaticLightmaps;
var
  TotalCount, CIdx, LX, LY, Idx, RIdx, RayTotal, BounceIdx, HitChart: Integer;
  U, V, NdotL, HitDist, HitU, HitV, UnoccludedSkyCount: Single;
  SunDir, SunColor, SkyColor, RayOrig, RayDir, TanT, TanB, BounceAccum: TVector3;
  Ch: TLightmassSurfaceChart;
  PrevBounce: array of TVector3;
  HitTex: TLightmassTexel;
begin
  BuildPresetChartsAndLayout;

  TotalCount := FAtlasResolution * FAtlasResolution;
  SetLength(FTexels, TotalCount);
  for Idx := 0 to TotalCount - 1 do
  begin
    FTexels[Idx] := Default(TLightmassTexel);
    FTexels[Idx].OwnerState := -1;
    FTexels[Idx].SourceChartId := -1;
  end;

  { Pass 1: Rasterize UV2 Chart Interior Texels }
  for CIdx := 0 to High(FCharts) do
  begin
    Ch := FCharts[CIdx];
    for LY := 0 to Ch.AtlasH - 1 do
      for LX := 0 to Ch.AtlasW - 1 do
      begin
        U := (LX + 0.5) / Ch.AtlasW;
        V := (LY + 0.5) / Ch.AtlasH;
        Idx := TexelIndex(Ch.AtlasX + LX, Ch.AtlasY + LY);
        FTexels[Idx].OwnerState := CIdx;
        FTexels[Idx].SourceChartId := CIdx;
        FTexels[Idx].WorldPos := Ch.PatchOrigin + Ch.AxisU * U + Ch.AxisV * V;
        FTexels[Idx].WorldNormal := Ch.PatchNormal;
        FTexels[Idx].AlbedoRGB := Ch.AlbedoRGB;
      end;
  end;

  { Pass 2: Direct Shadowed Sun Illumination + Cosine-Hemisphere Sky AO }
  { Angled sun shining into room hitting Left & Right walls + Floor while casting
    a crisp shadow behind CenterOccluderBlock }
  SunDir := Vector3(0.0, 0.76, 0.65).Normalize;
  SunColor := Vector3(1.00, 0.96, 0.90) * FSunIntensity;
  SkyColor := Vector3(0.68, 0.78, 0.96) * FSkyIntensity;
  RayTotal := RaysPerTexelForQuality(FQualityTier);

  for Idx := 0 to TotalCount - 1 do
  begin
    if FTexels[Idx].OwnerState < 0 then Continue;
    RayOrig := FTexels[Idx].WorldPos + FTexels[Idx].WorldNormal * 0.03;

    { Direct Sun + Side-Wall Fill so Red & Blue walls receive rich energy to bounce! }
    NdotL := Max(0.0, TVector3.DotProduct(FTexels[Idx].WorldNormal, SunDir));
    if (NdotL > 0.001) and
       (not RaycastCharts(RayOrig, SunDir, FTexels[Idx].SourceChartId,
          HitDist, HitChart, HitU, HitV)) then
      FTexels[Idx].DirectRGB := SunColor * NdotL
    else
      FTexels[Idx].DirectRGB := TVector3.Zero;

    { Overhead area skylight contribution on vertical side walls inside Cornell box }
    if Abs(FTexels[Idx].WorldNormal.X) > 0.5 then
      FTexels[Idx].DirectRGB := FTexels[Idx].DirectRGB + Vector3(0.95, 0.95, 0.95) * (FSunIntensity * 0.55);

    { Hemisphere Ray-Cast Ambient Occlusion (AO) }
    BuildTangentBasis(FTexels[Idx].WorldNormal, TanT, TanB);
    UnoccludedSkyCount := 0.0;
    for RIdx := 0 to RayTotal - 1 do
    begin
      RayDir := CosineHemisphereDir(RIdx, RayTotal, FTexels[Idx].WorldNormal, TanT, TanB);
      if (not RaycastCharts(RayOrig, RayDir, FTexels[Idx].SourceChartId,
           HitDist, HitChart, HitU, HitV)) or (HitDist > 3.2) then
        UnoccludedSkyCount := UnoccludedSkyCount + 1.0
      else
        { Nearby occluder (< 3.2m) attenuates AO proportionally to proximity }
        UnoccludedSkyCount := UnoccludedSkyCount + EnsureRange(HitDist / 3.2, 0.0, 1.0) * 0.35;
    end;
    FTexels[Idx].SkyAo01 := EnsureRange(UnoccludedSkyCount / RayTotal, 0.0, 1.0);
    FTexels[Idx].IndirectRGB := TVector3.Zero;
  end;

  { Pass 3: Multi-Bounce Diffuse Radiosity Color Bleeding (1..FIndirectBounces) }
  SetLength(PrevBounce, TotalCount);
  for BounceIdx := 1 to FIndirectBounces do
  begin
    for Idx := 0 to TotalCount - 1 do
      if FTexels[Idx].OwnerState >= 0 then
        PrevBounce[Idx] := (FTexels[Idx].DirectRGB + FTexels[Idx].IndirectRGB) * FTexels[Idx].AlbedoRGB
      else
        PrevBounce[Idx] := TVector3.Zero;

    for Idx := 0 to TotalCount - 1 do
    begin
      if FTexels[Idx].OwnerState < 0 then Continue;
      RayOrig := FTexels[Idx].WorldPos + FTexels[Idx].WorldNormal * 0.03;
      BuildTangentBasis(FTexels[Idx].WorldNormal, TanT, TanB);
      BounceAccum := TVector3.Zero;

      for RIdx := 0 to RayTotal - 1 do
      begin
        RayDir := CosineHemisphereDir(RIdx, RayTotal, FTexels[Idx].WorldNormal, TanT, TanB);
        if RaycastCharts(RayOrig, RayDir, FTexels[Idx].SourceChartId,
             HitDist, HitChart, HitU, HitV) then
        begin
          HitTex := SampleChartTexelNearUV(HitChart, HitU, HitV);
          BounceAccum := BounceAccum +
            (HitTex.DirectRGB + HitTex.IndirectRGB) * HitTex.AlbedoRGB;
        end;
      end;

      if BounceIdx = 1 then
        FTexels[Idx].IndirectRGB := (BounceAccum / RayTotal) * FIndirectIntensity
      else
        FTexels[Idx].IndirectRGB := FTexels[Idx].IndirectRGB +
          (BounceAccum / RayTotal) * (FIndirectIntensity * Power(0.55, BounceIdx - 1));
    end;
  end;

  { Combine Direct + Indirect GI + Sky * AO }
  for Idx := 0 to TotalCount - 1 do
    if FTexels[Idx].OwnerState >= 0 then
      FTexels[Idx].TotalRGB :=
        (FTexels[Idx].DirectRGB + FTexels[Idx].IndirectRGB +
         SkyColor * FTexels[Idx].SkyAo01) * FTexels[Idx].AlbedoRGB;

  { Pass 4: Gutter Seam Dilation }
  if FDilateGutterPasses > 0 then
    DilateGutterSeamTexels(FDilateGutterPasses);

  FLightingNeedsRebuild := False;
end;

function TCastleLightmassBaker.EvaluateAtlasDisplayRGB(const AX, AY: Integer): TVector3;
var
  T: TLightmassTexel;
  Tone: TVector3;
begin
  if (AX < 0) or (AX >= FAtlasResolution) or
     (AY < 0) or (AY >= FAtlasResolution) then
    Exit(TVector3.Zero);

  T := FTexels[TexelIndex(AX, AY)];
  if T.OwnerState = -1 then
    Exit(Vector3(0.06, 0.07, 0.09));

  case FViewChannel of
    lvcCombinedTotalLighting:
      begin
        { Reinhard tone-map for crisp LDR viewport display }
        Tone.X := T.TotalRGB.X / (1.0 + T.TotalRGB.X * 0.55);
        Tone.Y := T.TotalRGB.Y / (1.0 + T.TotalRGB.Y * 0.55);
        Tone.Z := T.TotalRGB.Z / (1.0 + T.TotalRGB.Z * 0.55);
        Result := Tone;
      end;
    lvcIndirectGiRadiosityOnly:
      begin
        Tone := T.IndirectRGB * 1.35;
        Result := Vector3(
          EnsureRange(Tone.X, 0.0, 1.0),
          EnsureRange(Tone.Y, 0.0, 1.0),
          EnsureRange(Tone.Z, 0.0, 1.0));
      end;
    lvcAmbientOcclusionOnly:
      Result := Vector3(T.SkyAo01, T.SkyAo01, T.SkyAo01);
    lvcUv2ChartPackingDilate:
      begin
        case EnsureRange(T.SourceChartId, 0, 5) of
          0: Tone := Vector3(0.35, 0.78, 0.98);
          1: Tone := Vector3(0.95, 0.36, 0.36);
          2: Tone := Vector3(0.38, 0.54, 0.98);
          3: Tone := Vector3(0.48, 0.90, 0.56);
          4: Tone := Vector3(0.98, 0.80, 0.34);
        else
          Tone := Vector3(0.82, 0.52, 0.96);
        end;
        if T.OwnerState = -2 then
          Result := Tone * 0.45 { Darker ring shows 2px dilated gutter border! }
        else
          Result := Tone;
      end;
  end;
end;

function TCastleLightmassBaker.ChartCount: Integer;
begin
  Result := Length(FCharts);
end;

function TCastleLightmassBaker.ValidInteriorTexelCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FTexels) do
    if FTexels[I].OwnerState >= 0 then
      Inc(Result);
end;

function TCastleLightmassBaker.DilatedBorderTexelCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FTexels) do
    if FTexels[I].OwnerState = -2 then
      Inc(Result);
end;

function TCastleLightmassBaker.UndilatedAdjacentGutterCount: Integer;
const
  DX4: array[0..3] of Integer = (-1, 1, 0, 0);
  DY4: array[0..3] of Integer = (0, 0, -1, 1);
var
  X, Y, K, NX, NY: Integer;
begin
  Result := 0;
  for Y := 0 to FAtlasResolution - 1 do
    for X := 0 to FAtlasResolution - 1 do
      if FTexels[TexelIndex(X, Y)].OwnerState >= 0 then
        for K := 0 to 3 do
        begin
          NX := X + DX4[K];
          NY := Y + DY4[K];
          if (NX >= 0) and (NX < FAtlasResolution) and
             (NY >= 0) and (NY < FAtlasResolution) and
             (FTexels[TexelIndex(NX, NY)].OwnerState = -1) then
            Inc(Result);
        end;
end;

function TCastleLightmassBaker.AverageSkyAo01: Single;
var
  I, Cnt: Integer;
  Sum: Double;
begin
  Sum := 0.0;
  Cnt := 0;
  for I := 0 to High(FTexels) do
    if FTexels[I].OwnerState >= 0 then
    begin
      Sum := Sum + FTexels[I].SkyAo01;
      Inc(Cnt);
    end;
  if Cnt > 0 then
    Result := Sum / Cnt
  else
    Result := 1.0;
end;

function TCastleLightmassBaker.AverageIndirectLuminance: Single;
var
  I, Cnt: Integer;
  Sum: Double;
  C: TVector3;
begin
  Sum := 0.0;
  Cnt := 0;
  for I := 0 to High(FTexels) do
    if FTexels[I].OwnerState >= 0 then
    begin
      C := FTexels[I].IndirectRGB;
      Sum := Sum + (0.2126 * C.X + 0.7152 * C.Y + 0.0722 * C.Z);
      Inc(Cnt);
    end;
  if Cnt > 0 then
    Result := Sum / Cnt
  else
    Result := 0.0;
end;

function TCastleLightmassBaker.GetBakeDataJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('wasBaked', not FLightingNeedsRebuild);
    RootObj.Add('avgAo', AverageSkyAo01);
    RootObj.Add('avgGiLum', AverageIndirectLuminance);
    FBakeDataJson := RootObj.AsJSON;
    Result := FBakeDataJson;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleLightmassBaker.SetBakeDataJson(const AValue: String);
var
  Parsed: TJSONData;
  WasBaked: Boolean;
begin
  FBakeDataJson := AValue;
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    try
      Parsed := GetJSON(AValue);
    except
      Exit;
    end;
    if Parsed is TJSONObject then
    begin
      WasBaked := TJSONObject(Parsed).Get('wasBaked', True);
      if WasBaked then
        BakeStaticLightmaps
      else
        FLightingNeedsRebuild := True;
    end;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleLightmassBaker.LightmassSummaryBadge: String;
begin
  if FLightingNeedsRebuild then
    Result := Format('[Lightmass:UNBUILT %dx%d %dBounces]',
      [FAtlasResolution, FAtlasResolution, FIndirectBounces])
  else
    Result := Format('[Lightmass:%dx%d %dCharts AO=%d%% GI=%.2f]',
      [FAtlasResolution, FAtlasResolution, ChartCount,
       Round(AverageSkyAo01 * 100.0), AverageIndirectLuminance]);
end;

initialization
  RegisterSerializableComponent(TCastleLightmassBaker,
    ['Lighting & Rendering', 'GPU Lightmass Static Lightmap & AO Baker (TCastleLightmassBaker)']);

end.
