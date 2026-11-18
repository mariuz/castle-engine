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

{ Substrate-Style Multi-Slab Layered Material Mixer with Clear-Coat Beer-Lambert
  Transmittance, Thin-Film Iridescence, Velvet Fuzz & Strict Energy Conservation
  (Phase 367 — UE 6.0+ Substrate USubstrateMaterial Parity). }
unit CastleSubstrateMaterial;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Built-in Substrate multi-slab material presets. }
  TSubstratePreset = (
    subpCustom,
    subpAutomotiveCandyClearCoat,
    subpIridescentScarabCarapace,
    subpRoyalVelvetGoldTrim,
    subpWetMossyCobblestone
  );

  { Evaluated Substrate multi-slab reflectance & energy breakdown at CosThetaV. }
  TSubstrateEvalSample = record
    CosThetaV: Single;
    TopCoatFresnel: Single;
    BeerLambertTransmittance: TVector3;
    ThinFilmTint: TVector3;
    FuzzRimFactor: Single;
    BaseSlabContribution: TVector3;
    TotalReflectanceRgb: TVector3;
    MaxChannelAlbedo: Single;
    EnergyConserved: Boolean;
  end;

  { Energy-conserving multi-slab Substrate material component with vertical
    clear-coat Beer-Lambert absorption, Airy thin-film interference, microfiber
    velvet fuzz, and a csTransient shaded preview sphere. }
  TCastleSubstrateMaterial = class(TCastleTransform)
  private
    FPreset: TSubstratePreset;
    FBaseAlbedoRgb: TVector3;
    FBaseMetallic: Single;
    FBaseRoughness: Single;
    FTopCoatCoverage: Single;
    FTopCoatIor: Single;
    FTopCoatRoughness: Single;
    FTopCoatThicknessMicrons: Single;
    FTopCoatTintRgb: TVector3;
    FThinFilmNanometers: Single;
    FFuzzCoverage: Single;
    FFuzzColorRgb: TVector3;
    FShowPreviewSphere: Boolean;
    FPeakDirectionalAlbedo: Single;
    FEnergyConservedAcrossAngles: Boolean;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TSubstratePreset);
    procedure SetBaseMetallic(const AValue: Single);
    procedure SetBaseRoughness(const AValue: Single);
    procedure SetTopCoatCoverage(const AValue: Single);
    procedure SetTopCoatIor(const AValue: Single);
    procedure SetTopCoatRoughness(const AValue: Single);
    procedure SetTopCoatThicknessMicrons(const AValue: Single);
    procedure SetThinFilmNanometers(const AValue: Single);
    procedure SetFuzzCoverage(const AValue: Single);
    procedure SetShowPreviewSphere(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParams(const APreset: TSubstratePreset);
    procedure UpdateEnergyAudit;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetBaseAlbedoRgb(const ARgb: TVector3);
    procedure SetTopCoatTintRgb(const ARgb: TVector3);
    procedure SetFuzzColorRgb(const ARgb: TVector3);
    function EvaluateSlabAtCosTheta(const ACosThetaV: Single): TSubstrateEvalSample;
    procedure RebuildPreviewSphereMesh;
    function SubstrateSummaryBadge: String;
    property BaseAlbedoRgb: TVector3 read FBaseAlbedoRgb;
    property TopCoatTintRgb: TVector3 read FTopCoatTintRgb;
    property FuzzColorRgb: TVector3 read FFuzzColorRgb;
    property PeakDirectionalAlbedo: Single read FPeakDirectionalAlbedo;
    property EnergyConservedAcrossAngles: Boolean read FEnergyConservedAcrossAngles;
  published
    property Preset: TSubstratePreset read FPreset write SetPreset default subpAutomotiveCandyClearCoat;
    property BaseMetallic: Single read FBaseMetallic write SetBaseMetallic {$ifdef FPC}default 0.85{$endif};
    property BaseRoughness: Single read FBaseRoughness write SetBaseRoughness {$ifdef FPC}default 0.28{$endif};
    property TopCoatCoverage: Single read FTopCoatCoverage write SetTopCoatCoverage {$ifdef FPC}default 1.0{$endif};
    property TopCoatIor: Single read FTopCoatIor write SetTopCoatIor {$ifdef FPC}default 1.52{$endif};
    property TopCoatRoughness: Single read FTopCoatRoughness write SetTopCoatRoughness {$ifdef FPC}default 0.04{$endif};
    property TopCoatThicknessMicrons: Single read FTopCoatThicknessMicrons write SetTopCoatThicknessMicrons {$ifdef FPC}default 35.0{$endif};
    property ThinFilmNanometers: Single read FThinFilmNanometers write SetThinFilmNanometers {$ifdef FPC}default 0.0{$endif};
    property FuzzCoverage: Single read FFuzzCoverage write SetFuzzCoverage {$ifdef FPC}default 0.0{$endif};
    property ShowPreviewSphere: Boolean read FShowPreviewSphere write SetShowPreviewSphere default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function SubstratePresetToString(const APreset: TSubstratePreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function SubstratePresetToString(const APreset: TSubstratePreset): String;
begin
  case APreset of
    subpCustom: Result := 'Custom Substrate Slab Stack';
    subpAutomotiveCandyClearCoat: Result := 'Automotive Candy Crimson Clear-Coat (35 um)';
    subpIridescentScarabCarapace: Result := 'Iridescent Scarab Thin-Film Carapace (520 nm)';
    subpRoyalVelvetGoldTrim: Result := 'Royal Purple Microfiber Fuzz Velvet';
    subpWetMossyCobblestone: Result := 'Porous Wet Water-Film Cobblestone (IOR 1.33)';
  end;
end;

function ClampRgb01(const V: TVector3): TVector3;
begin
  Result := Vector3(
    EnsureRange(V.X, 0.0, 1.0),
    EnsureRange(V.Y, 0.0, 1.0),
    EnsureRange(V.Z, 0.0, 1.0));
end;

{ TCastleSubstrateMaterial ---------------------------------------------------- }

constructor TCastleSubstrateMaterial.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreviewSphere := True;
  ApplyPresetParams(subpAutomotiveCandyClearCoat);
  RebuildPreviewSphereMesh;
end;

destructor TCastleSubstrateMaterial.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleSubstrateMaterial.ApplyPresetParams(const APreset: TSubstratePreset);
begin
  FPreset := APreset;
  case APreset of
    subpAutomotiveCandyClearCoat, subpCustom:
      begin
        FBaseAlbedoRgb := Vector3(0.88, 0.08, 0.14);
        FBaseMetallic := 0.85;
        FBaseRoughness := 0.28;
        FTopCoatCoverage := 1.0;
        FTopCoatIor := 1.52;
        FTopCoatRoughness := 0.04;
        FTopCoatThicknessMicrons := 35.0;
        FTopCoatTintRgb := Vector3(0.95, 0.22, 0.28);
        FThinFilmNanometers := 0.0;
        FFuzzCoverage := 0.0;
        FFuzzColorRgb := Vector3(1.0, 1.0, 1.0);
      end;
    subpIridescentScarabCarapace:
      begin
        FBaseAlbedoRgb := Vector3(0.14, 0.32, 0.24);
        FBaseMetallic := 0.92;
        FBaseRoughness := 0.16;
        FTopCoatCoverage := 1.0;
        FTopCoatIor := 1.68;
        FTopCoatRoughness := 0.05;
        FTopCoatThicknessMicrons := 8.0;
        FTopCoatTintRgb := Vector3(0.92, 0.98, 0.95);
        FThinFilmNanometers := 520.0;
        FFuzzCoverage := 0.0;
        FFuzzColorRgb := Vector3(0.4, 1.0, 0.8);
      end;
    subpRoyalVelvetGoldTrim:
      begin
        FBaseAlbedoRgb := Vector3(0.26, 0.07, 0.42);
        FBaseMetallic := 0.10;
        FBaseRoughness := 0.72;
        FTopCoatCoverage := 0.15;
        FTopCoatIor := 1.46;
        FTopCoatRoughness := 0.35;
        FTopCoatThicknessMicrons := 4.0;
        FTopCoatTintRgb := Vector3(1.0, 0.95, 1.0);
        FThinFilmNanometers := 0.0;
        FFuzzCoverage := 0.88;
        FFuzzColorRgb := Vector3(0.86, 0.58, 0.98);
      end;
    subpWetMossyCobblestone:
      begin
        FBaseAlbedoRgb := Vector3(0.24, 0.34, 0.20);
        FBaseMetallic := 0.0;
        FBaseRoughness := 0.82;
        FTopCoatCoverage := 0.95;
        FTopCoatIor := 1.333;
        FTopCoatRoughness := 0.03;
        FTopCoatThicknessMicrons := 18.0;
        FTopCoatTintRgb := Vector3(0.86, 0.94, 0.88);
        FThinFilmNanometers := 0.0;
        FFuzzCoverage := 0.12;
        FFuzzColorRgb := Vector3(0.38, 0.58, 0.28);
      end;
  end;
  UpdateEnergyAudit;
end;

procedure TCastleSubstrateMaterial.SetPreset(const AValue: TSubstratePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> subpCustom then
  begin
    ApplyPresetParams(AValue);
    RebuildPreviewSphereMesh;
  end;
end;

procedure TCastleSubstrateMaterial.SetBaseMetallic(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FBaseMetallic, V, 1e-4) then Exit;
  FBaseMetallic := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetBaseRoughness(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.02, 1.0);
  if SameValue(FBaseRoughness, V, 1e-4) then Exit;
  FBaseRoughness := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetTopCoatCoverage(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FTopCoatCoverage, V, 1e-4) then Exit;
  FTopCoatCoverage := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetTopCoatIor(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 1.05, 2.60);
  if SameValue(FTopCoatIor, V, 1e-4) then Exit;
  FTopCoatIor := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetTopCoatRoughness(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.01, 1.0);
  if SameValue(FTopCoatRoughness, V, 1e-4) then Exit;
  FTopCoatRoughness := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetTopCoatThicknessMicrons(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 200.0);
  if SameValue(FTopCoatThicknessMicrons, V, 1e-4) then Exit;
  FTopCoatThicknessMicrons := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetThinFilmNanometers(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1600.0);
  if SameValue(FThinFilmNanometers, V, 1e-4) then Exit;
  FThinFilmNanometers := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetFuzzCoverage(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FFuzzCoverage, V, 1e-4) then Exit;
  FFuzzCoverage := V;
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetShowPreviewSphere(const AValue: Boolean);
begin
  if FShowPreviewSphere = AValue then Exit;
  FShowPreviewSphere := AValue;
  if not FShowPreviewSphere then
    ClearTransientScene
  else
    RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetBaseAlbedoRgb(const ARgb: TVector3);
begin
  FBaseAlbedoRgb := ClampRgb01(ARgb);
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetTopCoatTintRgb(const ARgb: TVector3);
begin
  FTopCoatTintRgb := ClampRgb01(ARgb);
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

procedure TCastleSubstrateMaterial.SetFuzzColorRgb(const ARgb: TVector3);
begin
  FFuzzColorRgb := ClampRgb01(ARgb);
  FPreset := subpCustom;
  UpdateEnergyAudit;
  RebuildPreviewSphereMesh;
end;

function TCastleSubstrateMaterial.EvaluateSlabAtCosTheta(
  const ACosThetaV: Single): TSubstrateEvalSample;
var
  CosV, OneMinusCos, F0Coat, OptDepth, OpdNm, BaseGloss: Single;
  RemainingAfterFuzz, RemainingAfterCoat, BaseResponse: TVector3;
begin
  CosV := EnsureRange(ACosThetaV, 0.02, 1.0);
  Result.CosThetaV := CosV;
  OneMinusCos := 1.0 - CosV;

  { 1. Outer Velvet / Fuzz microfiber sheen layer (Charlie-style grazing lobe) }
  Result.FuzzRimFactor := EnsureRange(FFuzzCoverage * Power(OneMinusCos, 3.0), 0.0, 0.92);
  RemainingAfterFuzz := Vector3(1.0, 1.0, 1.0) - (FFuzzColorRgb * Result.FuzzRimFactor);

  { 2. Clear-Coat Schlick Fresnel + Airy Thin-Film Interference }
  F0Coat := Sqr((FTopCoatIor - 1.0) / (FTopCoatIor + 1.0));
  Result.TopCoatFresnel := EnsureRange(
    (F0Coat + (1.0 - F0Coat) * Power(OneMinusCos, 5.0)) *
    FTopCoatCoverage * (1.0 - FTopCoatRoughness * 0.35),
    0.0, 0.96);

  if FThinFilmNanometers > 1.0 then
  begin
    OpdNm := 2.0 * FTopCoatIor * FThinFilmNanometers * CosV;
    Result.ThinFilmTint := Vector3(
      0.5 + 0.5 * Cos(2.0 * Pi * OpdNm / 650.0),
      0.5 + 0.5 * Cos(2.0 * Pi * OpdNm / 532.0),
      0.5 + 0.5 * Cos(2.0 * Pi * OpdNm / 460.0));
  end else
    Result.ThinFilmTint := Vector3(1.0, 1.0, 1.0);

  { 3. Beer-Lambert optical absorption along clear-coat two-way ray path }
  OptDepth := (FTopCoatThicknessMicrons * 0.022 * FTopCoatCoverage) / Max(0.18, CosV);
  Result.BeerLambertTransmittance := Vector3(
    Exp(-(1.0 - FTopCoatTintRgb.X) * OptDepth),
    Exp(-(1.0 - FTopCoatTintRgb.Y) * OptDepth),
    Exp(-(1.0 - FTopCoatTintRgb.Z) * OptDepth));

  { 4. Energy-conserving bottom slab response: receives only (1 - Fuzz) * (1 - F_coat) * T_beer }
  RemainingAfterCoat := Vector3(
    RemainingAfterFuzz.X * (1.0 - Result.TopCoatFresnel) * Result.BeerLambertTransmittance.X,
    RemainingAfterFuzz.Y * (1.0 - Result.TopCoatFresnel) * Result.BeerLambertTransmittance.Y,
    RemainingAfterFuzz.Z * (1.0 - Result.TopCoatFresnel) * Result.BeerLambertTransmittance.Z);

  BaseGloss := Lerp(FBaseMetallic, 1.0 - FBaseRoughness * 0.25, 0.96 - FBaseRoughness * 0.30);
  BaseResponse := ClampRgb01(FBaseAlbedoRgb * BaseGloss);
  Result.BaseSlabContribution := Vector3(
    RemainingAfterCoat.X * BaseResponse.X,
    RemainingAfterCoat.Y * BaseResponse.Y,
    RemainingAfterCoat.Z * BaseResponse.Z);

  { 5. Total vertical slab stack sum: Fuzz + TopCoat*ThinFilm + TransmittedBase <= 1.0! }
  Result.TotalReflectanceRgb :=
    (FFuzzColorRgb * Result.FuzzRimFactor) +
    Vector3(
      RemainingAfterFuzz.X * Result.TopCoatFresnel * Result.ThinFilmTint.X,
      RemainingAfterFuzz.Y * Result.TopCoatFresnel * Result.ThinFilmTint.Y,
      RemainingAfterFuzz.Z * Result.TopCoatFresnel * Result.ThinFilmTint.Z) +
    Result.BaseSlabContribution;

  Result.MaxChannelAlbedo := Max(Result.TotalReflectanceRgb.X,
    Max(Result.TotalReflectanceRgb.Y, Result.TotalReflectanceRgb.Z));
  Result.EnergyConserved := Result.MaxChannelAlbedo <= 1.0001;
end;

procedure TCastleSubstrateMaterial.UpdateEnergyAudit;
var
  I: Integer;
  S: TSubstrateEvalSample;
begin
  FPeakDirectionalAlbedo := 0.0;
  FEnergyConservedAcrossAngles := True;
  for I := 1 to 20 do
  begin
    S := EvaluateSlabAtCosTheta(I / 20.0);
    if S.MaxChannelAlbedo > FPeakDirectionalAlbedo then
      FPeakDirectionalAlbedo := S.MaxChannelAlbedo;
    if not S.EnergyConserved then
      FEnergyConservedAcrossAngles := False;
  end;
end;

procedure TCastleSubstrateMaterial.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientSubstrateSphereMesh';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.RenderOptions.Lighting := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
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

procedure TCastleSubstrateMaterial.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleSubstrateMaterial.RebuildPreviewSphereMesh;
const
  Rings = 12;
  Slices = 20;
  Radius = 1.25;
var
  Verts, Cols: TVector3List;
  R, S: Integer;
  LightDir, ViewDir: TVector3;

  function SphereNormal(const RingIdx, SliceIdx: Integer): TVector3;
  var
    Phi, Theta: Single;
  begin
    Phi := (RingIdx / Rings) * Pi;
    Theta := (SliceIdx / Slices) * 2.0 * Pi;
    Result := Vector3(Sin(Phi) * Cos(Theta), Cos(Phi), Sin(Phi) * Sin(Theta));
  end;

  function ShadeNormal(const N: TVector3): TVector3;
  var
    Eval: TSubstrateEvalSample;
    NdotL: Single;
  begin
    Eval := EvaluateSlabAtCosTheta(Max(0.03, TVector3.DotProduct(N, ViewDir)));
    NdotL := 0.22 + 0.78 * Max(0.0, TVector3.DotProduct(N, LightDir));
    Result := ClampRgb01(Eval.TotalReflectanceRgb * NdotL);
  end;

var
  N00, N10, N11, N01, C00, C10, C11, C01: TVector3;
begin
  if not FShowPreviewSphere then Exit;
  LightDir := Vector3(0.45, 0.75, 0.50).Normalize;
  ViewDir := Vector3(0.0, 0.18, 0.98).Normalize;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for R := 0 to Rings - 1 do
      for S := 0 to Slices - 1 do
      begin
        N00 := SphereNormal(R, S);
        N10 := SphereNormal(R + 1, S);
        N11 := SphereNormal(R + 1, S + 1);
        N01 := SphereNormal(R, S + 1);
        C00 := ShadeNormal(N00);
        C10 := ShadeNormal(N10);
        C11 := ShadeNormal(N11);
        C01 := ShadeNormal(N01);

        Verts.Add(N00 * Radius); Verts.Add(N10 * Radius); Verts.Add(N11 * Radius);
        Cols.Add(C00); Cols.Add(C10); Cols.Add(C11);
        Verts.Add(N00 * Radius); Verts.Add(N11 * Radius); Verts.Add(N01 * Radius);
        Cols.Add(C00); Cols.Add(C11); Cols.Add(C01);
      end;

    EnsureTransientScene;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleSubstrateMaterial.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('albedoR', FBaseAlbedoRgb.X);
    RootObj.Add('albedoG', FBaseAlbedoRgb.Y);
    RootObj.Add('albedoB', FBaseAlbedoRgb.Z);
    RootObj.Add('metallic', FBaseMetallic);
    RootObj.Add('roughness', FBaseRoughness);
    RootObj.Add('coatCov', FTopCoatCoverage);
    RootObj.Add('coatIor', FTopCoatIor);
    RootObj.Add('coatRough', FTopCoatRoughness);
    RootObj.Add('coatUm', FTopCoatThicknessMicrons);
    RootObj.Add('thinFilmNm', FThinFilmNanometers);
    RootObj.Add('fuzzCov', FFuzzCoverage);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleSubstrateMaterial.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FBaseAlbedoRgb := ClampRgb01(Vector3(
        RootObj.Get('albedoR', FBaseAlbedoRgb.X),
        RootObj.Get('albedoG', FBaseAlbedoRgb.Y),
        RootObj.Get('albedoB', FBaseAlbedoRgb.Z)));
      FBaseMetallic := EnsureRange(RootObj.Get('metallic', FBaseMetallic), 0.0, 1.0);
      FBaseRoughness := EnsureRange(RootObj.Get('roughness', FBaseRoughness), 0.02, 1.0);
      FTopCoatCoverage := EnsureRange(RootObj.Get('coatCov', FTopCoatCoverage), 0.0, 1.0);
      FTopCoatIor := EnsureRange(RootObj.Get('coatIor', FTopCoatIor), 1.05, 2.60);
      FTopCoatRoughness := EnsureRange(RootObj.Get('coatRough', FTopCoatRoughness), 0.01, 1.0);
      FTopCoatThicknessMicrons := EnsureRange(RootObj.Get('coatUm', FTopCoatThicknessMicrons), 0.0, 200.0);
      FThinFilmNanometers := EnsureRange(RootObj.Get('thinFilmNm', FThinFilmNanometers), 0.0, 1600.0);
      FFuzzCoverage := EnsureRange(RootObj.Get('fuzzCov', FFuzzCoverage), 0.0, 1.0);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TSubstratePreset))) and
         (PresetOrd <= Ord(High(TSubstratePreset))) then
        FPreset := TSubstratePreset(PresetOrd);
      UpdateEnergyAudit;
      RebuildPreviewSphereMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleSubstrateMaterial.SubstrateSummaryBadge: String;
begin
  Result := Format('[Substrate:Coat=%.0fum Film=%.0fnm Peak=%.2f %s]', [
    FTopCoatThicknessMicrons,
    FThinFilmNanometers,
    FPeakDirectionalAlbedo,
    BoolToStr(FEnergyConservedAcrossAngles, 'ENERGY_OK', 'OVER_1')]);
end;

initialization
  RegisterSerializableComponent(TCastleSubstrateMaterial, ['Materials & Shaders', 'Substrate Multi-Slab Material']);
end.
