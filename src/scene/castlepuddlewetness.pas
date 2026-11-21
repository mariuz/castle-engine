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

{ Procedural rain puddle micro-basin pooling, upward WorldRay roof/awning
  rain-shelter occlusion, capillary porous albedo darkening, mirror specular
  roughness collapse, and ring-buffered footstep/raindrop splash ripples
  (Phase 407). }
unit CastlePuddleWetness;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

const
  MaxPooledPuddleRipples = 24;

type
  { Preset rain puddle & surface wetness material profiles. }
  TPuddleWetnessPreset = (
    pwpCobblestoneAlleyStorm,
    pwpMuddyTrenchDownpour,
    pwpMarbleCourtyardAfterRain
  );

  { Single expanding circular splash ripple ring in the puddle field. }
  TPuddleSplashRipple = record
    Active: Boolean;
    WorldXZ: TVector2;
    AgeSec: Single;
    LifetimeSec: Single;
    AmplitudeMm: Single;
  end;

  { Evaluated puddle depth, roof shelter, PBR wetness & ripple displacement. }
  TPuddleSurfaceSample = record
    InsideField: Boolean;
    RoofSheltered: Boolean;
    BasinDepressionMeters: Single;
    StandingWaterDepthMeters: Single;
    PorousAlbedoScale: Single;
    EffectiveRoughness: Single;
    RippleDisplacementMm: Single;
  end;

  { Procedural rain puddle, roof shelter & splash ripple field component. }
  TCastlePuddleWetnessField = class(TCastleTransform)
  private
    FPreset: TPuddleWetnessPreset;
    FFieldWidthMeters: Single;
    FFieldDepthMeters: Single;
    FMaxBasinDepthMeters: Single;
    FWaterFillLevel01: Single;
    FRainWetness01: Single;
    FDryRoughness: Single;
    FPorousDarkeningStrength01: Single;
    FRoofCheckHeightMeters: Single;
    FRippleWaveSpeedMps: Single;
    FShowPreview: Boolean;
    FRipples: array[0..MaxPooledPuddleRipples - 1] of TPuddleSplashRipple;
    FNextRippleSlot: Integer;
    FActiveRippleCount: Integer;
    FPreviewRoot: TCastleTransform;
    FPreviewRimScene: TCastleScene;
    procedure SetPreset(const AValue: TPuddleWetnessPreset);
    procedure SetShowPreview(const AValue: Boolean);
    procedure RecountActiveRipples;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TPuddleWetnessPreset);
    procedure ClearRipples;

    { Spawn a circular splash ripple at AWorldPoint (FIFO ring-buffer capped). }
    procedure TriggerSplashAtWorld(const AWorldPoint: TVector3;
      const AAmplitudeMm: Single = 4.5; const ALifetimeSec: Single = 1.8);

    { Advance splash ripple rings and optional drying evaporation. }
    procedure StepRipplesAndEvaporation(const ADtSec: Single;
      const ADryingRatePerSec: Single = 0.0);

    { Sample roof shelter via upward WorldRay, micro-basin standing water depth,
      porous capillary darkening, roughness collapse, and splash ripple height. }
    function SampleSurfaceWetnessAtWorld(
      const AWorldRoot: TCastleAbstractRootTransform;
      const AWorldPoint: TVector3): TPuddleSurfaceSample;

    procedure RebuildPreview;
    procedure ClearPreview;
    function PuddleSummaryBadge: String;

    property ActiveRippleCount: Integer read FActiveRippleCount;
  published
    property Preset: TPuddleWetnessPreset
      read FPreset write SetPreset default pwpCobblestoneAlleyStorm;
    property FieldWidthMeters: Single read FFieldWidthMeters write FFieldWidthMeters;
    property FieldDepthMeters: Single read FFieldDepthMeters write FFieldDepthMeters;
    property MaxBasinDepthMeters: Single read FMaxBasinDepthMeters write FMaxBasinDepthMeters;
    property WaterFillLevel01: Single read FWaterFillLevel01 write FWaterFillLevel01;
    property RainWetness01: Single read FRainWetness01 write FRainWetness01;
    property DryRoughness: Single read FDryRoughness write FDryRoughness;
    property PorousDarkeningStrength01: Single
      read FPorousDarkeningStrength01 write FPorousDarkeningStrength01;
    property RoofCheckHeightMeters: Single
      read FRoofCheckHeightMeters write FRoofCheckHeightMeters;
    property RippleWaveSpeedMps: Single
      read FRippleWaveSpeedMps write FRippleWaveSpeedMps;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function PuddleWetnessPresetToString(const APreset: TPuddleWetnessPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function PuddleWetnessPresetToString(const APreset: TPuddleWetnessPreset): String;
begin
  case APreset of
    pwpCobblestoneAlleyStorm:    Result := 'CobblestoneAlleyStorm';
    pwpMuddyTrenchDownpour:      Result := 'MuddyTrenchDownpour';
    pwpMarbleCourtyardAfterRain: Result := 'MarbleCourtyardAfterRain';
  end;
end;

constructor TCastlePuddleWetnessField.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  ClearRipples;
  ApplyPreset(pwpCobblestoneAlleyStorm);
end;

destructor TCastlePuddleWetnessField.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastlePuddleWetnessField.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'FieldWidthMeters', 'FieldDepthMeters', 'MaxBasinDepthMeters',
       'WaterFillLevel01', 'RainWetness01', 'DryRoughness',
       'PorousDarkeningStrength01', 'RoofCheckHeightMeters',
       'RippleWaveSpeedMps', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePuddleWetnessField.SetPreset(const AValue: TPuddleWetnessPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastlePuddleWetnessField.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastlePuddleWetnessField.ApplyPreset(const APreset: TPuddleWetnessPreset);
begin
  FPreset := APreset;
  case APreset of
    pwpCobblestoneAlleyStorm:
      begin
        FFieldWidthMeters := 18.0;
        FFieldDepthMeters := 18.0;
        FMaxBasinDepthMeters := 0.045;
        FWaterFillLevel01 := 0.72;
        FRainWetness01 := 0.90;
        FDryRoughness := 0.78;
        FPorousDarkeningStrength01 := 0.42;
        FRoofCheckHeightMeters := 16.0;
        FRippleWaveSpeedMps := 1.45;
      end;
    pwpMuddyTrenchDownpour:
      begin
        FFieldWidthMeters := 22.0;
        FFieldDepthMeters := 14.0;
        FMaxBasinDepthMeters := 0.120;
        FWaterFillLevel01 := 0.85;
        FRainWetness01 := 1.00;
        FDryRoughness := 0.88;
        FPorousDarkeningStrength01 := 0.55;
        FRoofCheckHeightMeters := 20.0;
        FRippleWaveSpeedMps := 1.15;
      end;
    pwpMarbleCourtyardAfterRain:
      begin
        FFieldWidthMeters := 24.0;
        FFieldDepthMeters := 24.0;
        FMaxBasinDepthMeters := 0.018;
        FWaterFillLevel01 := 0.48;
        FRainWetness01 := 0.65;
        FDryRoughness := 0.36;
        FPorousDarkeningStrength01 := 0.16;
        FRoofCheckHeightMeters := 18.0;
        FRippleWaveSpeedMps := 1.65;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastlePuddleWetnessField.ClearRipples;
var
  I: Integer;
begin
  for I := 0 to MaxPooledPuddleRipples - 1 do
    FRipples[I] := Default(TPuddleSplashRipple);
  FNextRippleSlot := 0;
  FActiveRippleCount := 0;
end;

procedure TCastlePuddleWetnessField.RecountActiveRipples;
var
  I, C: Integer;
begin
  C := 0;
  for I := 0 to MaxPooledPuddleRipples - 1 do
    if FRipples[I].Active then
      Inc(C);
  FActiveRippleCount := C;
end;

procedure TCastlePuddleWetnessField.TriggerSplashAtWorld(
  const AWorldPoint: TVector3; const AAmplitudeMm, ALifetimeSec: Single);
begin
  FRipples[FNextRippleSlot].Active := True;
  FRipples[FNextRippleSlot].WorldXZ := Vector2(AWorldPoint.X, AWorldPoint.Z);
  FRipples[FNextRippleSlot].AgeSec := 0.0;
  FRipples[FNextRippleSlot].AmplitudeMm := Max(0.1, AAmplitudeMm);
  FRipples[FNextRippleSlot].LifetimeSec := Max(0.15, ALifetimeSec);
  FNextRippleSlot := (FNextRippleSlot + 1) mod MaxPooledPuddleRipples;
  RecountActiveRipples;
end;

procedure TCastlePuddleWetnessField.StepRipplesAndEvaporation(
  const ADtSec, ADryingRatePerSec: Single);
var
  I: Integer;
begin
  if ADtSec <= 0.0 then Exit;
  for I := 0 to MaxPooledPuddleRipples - 1 do
    if FRipples[I].Active then
    begin
      FRipples[I].AgeSec := FRipples[I].AgeSec + ADtSec;
      if FRipples[I].AgeSec >= FRipples[I].LifetimeSec then
        FRipples[I].Active := False;
    end;
  RecountActiveRipples;

  if ADryingRatePerSec > 0.0 then
  begin
    FWaterFillLevel01 := Max(0.0, FWaterFillLevel01 - ADryingRatePerSec * ADtSec);
    FRainWetness01 := Max(0.0, FRainWetness01 - ADryingRatePerSec * 0.65 * ADtSec);
  end;
end;

function TCastlePuddleWetnessField.SampleSurfaceWetnessAtWorld(
  const AWorldRoot: TCastleAbstractRootTransform;
  const AWorldPoint: TVector3): TPuddleSurfaceSample;
var
  ActiveRoot: TCastleAbstractRootTransform;

  function BlockedByOverheadRoof: Boolean;
  var
    Orig: TVector3;
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
    D: Single;
  begin
    Result := False;
    if ActiveRoot = nil then Exit;
    Orig := AWorldPoint + Vector3(0.0, 0.08, 0.0);
    RH := ActiveRoot.WorldRay(Orig, Vector3(0.0, 1.0, 0.0));
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        D := PointsDistance(Orig, RH[K].Point);
        if (D >= 0.15) and (D <= Max(0.5, FRoofCheckHeightMeters)) then
          Exit(True);
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  InvWT, WT: TMatrix4;
  LocalP: TVector3;
  HX, HZ, MaxD, BasinNorm, WaterTableDepth, Wet01, DarkStr: Single;
  I: Integer;
  DistR, FrontR, Env, Decay01: Single;
begin
  Result := Default(TPuddleSurfaceSample);
  Result.PorousAlbedoScale := 1.0;
  Result.EffectiveRoughness := Clamped(FDryRoughness, 0.02, 1.0);

  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;
  LocalP := InvWT.MultPoint(AWorldPoint);

  HX := Max(0.5, FFieldWidthMeters) * 0.5;
  HZ := Max(0.5, FFieldDepthMeters) * 0.5;
  if (Abs(LocalP.X) > HX) or (Abs(LocalP.Z) > HZ) then
    Exit;

  Result.InsideField := True;
  if BlockedByOverheadRoof then
  begin
    Result.RoofSheltered := True;
    Exit;
  end;

  { Periodic cobblestone/wheel-rut depression basin (deepest at (0,0) and 2*Pi/k grid) }
  MaxD := Max(0.002, FMaxBasinDepthMeters);
  BasinNorm := (0.5 + 0.5 * Cos(LocalP.X * 0.95)) *
               (0.5 + 0.5 * Cos(LocalP.Z * 0.85));
  Result.BasinDepressionMeters := MaxD * BasinNorm;

  { Water fills depressions from the bottom up to WaterFillLevel01 * MaxD }
  WaterTableDepth := MaxD * (1.0 - Clamped(FWaterFillLevel01, 0.0, 1.0));
  Result.StandingWaterDepthMeters := Max(0.0,
    Result.BasinDepressionMeters - WaterTableDepth);

  Wet01 := Clamped(FRainWetness01, 0.0, 1.0);
  DarkStr := Clamped(FPorousDarkeningStrength01, 0.0, 0.85);
  Result.PorousAlbedoScale := 1.0 - Wet01 * DarkStr;

  if Result.StandingWaterDepthMeters > 0.0015 then
  begin
    { Mirror-smooth standing puddle surface + capillary darkened bed underneath }
    Result.EffectiveRoughness := 0.025;
    for I := 0 to MaxPooledPuddleRipples - 1 do
      if FRipples[I].Active then
      begin
        DistR := Hypot(AWorldPoint.X - FRipples[I].WorldXZ.X,
                       AWorldPoint.Z - FRipples[I].WorldXZ.Y);
        FrontR := Max(0.1, FRippleWaveSpeedMps) * FRipples[I].AgeSec;
        Decay01 := Clamped(1.0 - (FRipples[I].AgeSec / FRipples[I].LifetimeSec), 0.0, 1.0);
        Env := Exp(-5.0 * Sqr(DistR - FrontR));
        Result.RippleDisplacementMm := Result.RippleDisplacementMm +
          FRipples[I].AmplitudeMm * Decay01 * Env * Cos(20.0 * (DistR - FrontR));
      end;
  end else
  begin
    { Damp un-submerged rim: partial specular gloss boost }
    Result.EffectiveRoughness := Max(0.08,
      Result.EffectiveRoughness * (1.0 - 0.58 * Wet01));
  end;
end;

procedure TCastlePuddleWetnessField.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewRimScene := nil;
  end;
end;

procedure TCastlePuddleWetnessField.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  HX, HZ: Single;
  Pts: array[0..4] of TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  HX := Max(0.5, FFieldWidthMeters) * 0.5;
  HZ := Max(0.5, FFieldDepthMeters) * 0.5;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'PuddleWetnessPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewRimScene := TCastleScene.Create(FPreviewRoot);
  FPreviewRimScene.SetTransient;
  FPreviewRimScene.Name := 'PuddleWetnessPreviewRim';
  FPreviewRimScene.Pickable := False;
  FPreviewRimScene.Collides := False;
  FPreviewRoot.Add(FPreviewRimScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.28, 0.68, 0.98);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  CoordNode := TCoordinateNode.Create;
  Pts[0] := Vector3(-HX, 0.03, -HZ);
  Pts[1] := Vector3( HX, 0.03, -HZ);
  Pts[2] := Vector3( HX, 0.03,  HZ);
  Pts[3] := Vector3(-HX, 0.03,  HZ);
  Pts[4] := Vector3(-HX, 0.03, -HZ);
  CoordNode.SetPoint(Pts);

  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([5]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewRimScene.Load(RootNode, True);
end;

function TCastlePuddleWetnessField.PuddleSummaryBadge: String;
begin
  Result := FormatDot('[Puddles:Fill=%.0f%% Wet=%.0f%% Ripples=%d]', [
    FWaterFillLevel01 * 100.0,
    FRainWetness01 * 100.0,
    FActiveRippleCount]);
end;

initialization
  RegisterSerializableComponent(TCastlePuddleWetnessField, 'Rain Puddle & Wetness Field');

end.
