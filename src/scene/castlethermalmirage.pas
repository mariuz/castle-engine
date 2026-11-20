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

{ Optical refraction, desert inferior mirage, Boussinesq thermal convection
  shimmer, and sunlit underwater caustic focal-cusp volume solver (Phase 401). }
unit CastleThermalMirage;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset atmospheric heat-haze vs. volcanic vent vs. underwater caustic modes. }
  TThermalMiragePreset = (
    tmpDesertAsphaltMirage,
    tmpVolcanicLavaVentShimmer,
    tmpSunlitCoralReefCaustics
  );

  { Optical distortion, inferior mirage reflection, updraft, and caustic sample. }
  TThermalOpticalSample = record
    InsideVolume: Boolean;
    RefractionUvOffset: TVector2;
    InferiorMirageReflectivity01: Single;
    UpdraftVelocityMps: Single;
    CausticLuminanceBoost: Single;
  end;

  { Bounded 3D optical refraction & caustic field volume. }
  TCastleThermalMirageVolume = class(TCastleTransform)
  private
    FPreset: TThermalMiragePreset;
    FVolumeExtents: TVector3;
    FVolumeExtentsPersistent: TCastleVector3Persistent;
    FSurfaceDeltaTempCelsius: Single;
    FShimmerDistortionAmplitude: Single;
    FPlumeRiseSpeedMps: Single;
    FMirageCriticalGrazingDeg: Single;
    FCausticContrast: Single;
    FWaterDepthMeters: Single;
    FShowPreview: Boolean;
    FPhaseTimeSec: Single;
    FPreviewRoot: TCastleTransform;
    FPreviewWireScene: TCastleScene;
    procedure SetPreset(const AValue: TThermalMiragePreset);
    procedure SetShowPreview(const AValue: Boolean);
    function GetExtentsForPersistent: TVector3;
    procedure SetExtentsForPersistent(const AValue: TVector3);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TThermalMiragePreset);
    procedure StepOpticalPhase(const ADtSec: Single);

    { Evaluate refractive shimmer UV offset, grazing-angle inferior mirage
      sky reflection, Boussinesq updraft, and underwater caustic luminance. }
    function SampleOpticalFieldAtWorld(
      const AWorldPoint, ACameraWorldPos: TVector3): TThermalOpticalSample;

    procedure RebuildPreview;
    procedure ClearPreview;
    function MirageSummaryBadge: String;

    property VolumeExtents: TVector3 read FVolumeExtents write FVolumeExtents;
    property PhaseTimeSec: Single read FPhaseTimeSec write FPhaseTimeSec;
  published
    property Preset: TThermalMiragePreset
      read FPreset write SetPreset default tmpDesertAsphaltMirage;
    property VolumeExtentsPersistent: TCastleVector3Persistent
      read FVolumeExtentsPersistent;
    property SurfaceDeltaTempCelsius: Single
      read FSurfaceDeltaTempCelsius write FSurfaceDeltaTempCelsius;
    property ShimmerDistortionAmplitude: Single
      read FShimmerDistortionAmplitude write FShimmerDistortionAmplitude;
    property PlumeRiseSpeedMps: Single
      read FPlumeRiseSpeedMps write FPlumeRiseSpeedMps;
    property MirageCriticalGrazingDeg: Single
      read FMirageCriticalGrazingDeg write FMirageCriticalGrazingDeg;
    property CausticContrast: Single
      read FCausticContrast write FCausticContrast;
    property WaterDepthMeters: Single
      read FWaterDepthMeters write FWaterDepthMeters;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function ThermalMiragePresetToString(const APreset: TThermalMiragePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function ThermalMiragePresetToString(const APreset: TThermalMiragePreset): String;
begin
  case APreset of
    tmpDesertAsphaltMirage:     Result := 'DesertAsphaltMirage';
    tmpVolcanicLavaVentShimmer: Result := 'VolcanicLavaVentShimmer';
    tmpSunlitCoralReefCaustics: Result := 'SunlitCoralReefCaustics';
  end;
end;

function SmoothStep01(const X: Single): Single;
var
  T: Single;
begin
  T := Clamped(X, 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

{ TCastleThermalMirageVolume ------------------------------------------------- }

constructor TCastleThermalMirageVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVolumeExtents := Vector3(24.0, 6.0, 24.0);
  FVolumeExtentsPersistent := TCastleVector3Persistent.Create(nil);
  FVolumeExtentsPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetExtentsForPersistent;
  FVolumeExtentsPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetExtentsForPersistent;
  FVolumeExtentsPersistent.InternalDefaultValue := Vector3(24.0, 6.0, 24.0);
  FShowPreview := True;
  FPhaseTimeSec := 0.0;
  ApplyPreset(tmpDesertAsphaltMirage);
end;

destructor TCastleThermalMirageVolume.Destroy;
begin
  ClearPreview;
  FreeAndNil(FVolumeExtentsPersistent);
  inherited Destroy;
end;

function TCastleThermalMirageVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'VolumeExtentsPersistent', 'SurfaceDeltaTempCelsius',
       'ShimmerDistortionAmplitude', 'PlumeRiseSpeedMps',
       'MirageCriticalGrazingDeg', 'CausticContrast',
       'WaterDepthMeters', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleThermalMirageVolume.GetExtentsForPersistent: TVector3;
begin
  Result := FVolumeExtents;
end;

procedure TCastleThermalMirageVolume.SetExtentsForPersistent(
  const AValue: TVector3);
begin
  FVolumeExtents := AValue;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleThermalMirageVolume.SetPreset(
  const AValue: TThermalMiragePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleThermalMirageVolume.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleThermalMirageVolume.ApplyPreset(
  const APreset: TThermalMiragePreset);
begin
  FPreset := APreset;
  case APreset of
    tmpDesertAsphaltMirage:
      begin
        FVolumeExtents := Vector3(32.0, 5.0, 32.0);
        FSurfaceDeltaTempCelsius := 32.0;
        FShimmerDistortionAmplitude := 0.012;
        FPlumeRiseSpeedMps := 1.9;
        FMirageCriticalGrazingDeg := 7.0;
        FCausticContrast := 0.0;
        FWaterDepthMeters := 0.0;
      end;
    tmpVolcanicLavaVentShimmer:
      begin
        FVolumeExtents := Vector3(12.0, 10.0, 12.0);
        FSurfaceDeltaTempCelsius := 180.0;
        FShimmerDistortionAmplitude := 0.038;
        FPlumeRiseSpeedMps := 5.8;
        FMirageCriticalGrazingDeg := 11.0;
        FCausticContrast := 0.0;
        FWaterDepthMeters := 0.0;
      end;
    tmpSunlitCoralReefCaustics:
      begin
        FVolumeExtents := Vector3(24.0, 8.0, 24.0);
        FSurfaceDeltaTempCelsius := 0.0;
        FShimmerDistortionAmplitude := 0.016;
        FPlumeRiseSpeedMps := 0.85;
        FMirageCriticalGrazingDeg := 0.0;
        FCausticContrast := 2.4;
        FWaterDepthMeters := 4.5;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleThermalMirageVolume.StepOpticalPhase(const ADtSec: Single);
begin
  if ADtSec <= 0.0 then Exit;
  FPhaseTimeSec := FPhaseTimeSec + ADtSec;
end;

function TCastleThermalMirageVolume.SampleOpticalFieldAtWorld(
  const AWorldPoint, ACameraWorldPos: TVector3): TThermalOpticalSample;
var
  InvWT, WT: TMatrix4;
  LocalP, ViewVec: TVector3;
  HalfX, HalfY, HalfZ, Height01, ThermalFalloff, WaveU, WaveV: Single;
  ViewLen, GrazingDeg, CritDeg, GroundProx, BetaAir: Single;
  W1, W2, CuspRaw, DepthAtten: Single;
begin
  Result := Default(TThermalOpticalSample);
  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;
  LocalP := InvWT.MultPoint(AWorldPoint);

  HalfX := Max(0.25, FVolumeExtents.X) * 0.5;
  HalfY := Max(0.25, FVolumeExtents.Y);
  HalfZ := Max(0.25, FVolumeExtents.Z) * 0.5;

  if (Abs(LocalP.X) > HalfX) or (LocalP.Y < -0.05) or (LocalP.Y > HalfY) or
     (Abs(LocalP.Z) > HalfZ) then
    Exit;

  Result.InsideVolume := True;
  Height01 := Clamped(LocalP.Y / HalfY, 0.0, 1.0);
  ThermalFalloff := 1.0 - SmoothStep01(Height01);

  { Rising turbulent optical shimmer UV vector }
  WaveU := Sin(LocalP.X * 2.3 + (LocalP.Y - FPlumeRiseSpeedMps * FPhaseTimeSec) * 3.7) *
           Cos(LocalP.Z * 1.9 + FPhaseTimeSec * 2.1);
  WaveV := Cos(LocalP.Z * 2.7 + (LocalP.Y - FPlumeRiseSpeedMps * FPhaseTimeSec) * 4.3);
  Result.RefractionUvOffset := Vector2(WaveU, WaveV) *
    (FShimmerDistortionAmplitude * (0.25 + 0.75 * ThermalFalloff));

  { Boussinesq buoyant thermal plume updraft velocity: sqrt(2 * g * beta * dT * z) }
  if FSurfaceDeltaTempCelsius > 0.1 then
  begin
    BetaAir := 1.0 / 300.0;
    Result.UpdraftVelocityMps := Sqrt(
      2.0 * 9.81 * BetaAir * FSurfaceDeltaTempCelsius * Max(0.15, LocalP.Y)) *
      ThermalFalloff;
  end;

  { Inferior desert mirage total-internal-reflection grazing factor }
  CritDeg := Max(0.0, FMirageCriticalGrazingDeg);
  if (CritDeg > 0.05) and (FSurfaceDeltaTempCelsius > 1.0) then
  begin
    ViewVec := AWorldPoint - ACameraWorldPos;
    ViewLen := ViewVec.Length;
    if ViewLen > 0.25 then
    begin
      GrazingDeg := RadToDeg(ArcSin(Clamped(Abs(ViewVec.Y / ViewLen), 0.0, 1.0)));
      GroundProx := Clamped(1.0 - (LocalP.Y / Max(0.4, HalfY * 0.35)), 0.0, 1.0);
      if GrazingDeg < CritDeg * 1.6 then
        Result.InferiorMirageReflectivity01 :=
          (1.0 - SmoothStep01(GrazingDeg / (CritDeg * 1.6))) * GroundProx;
    end;
  end;

  { Crossed dual-wave optical focal-cusp underwater caustics }
  if FCausticContrast > 0.01 then
  begin
    W1 := Abs(Sin(LocalP.X * 1.85 + FPhaseTimeSec * 1.6 + 0.6 * Sin(LocalP.Z * 1.3)));
    W2 := Abs(Sin(LocalP.Z * 2.05 - FPhaseTimeSec * 1.3 + 0.6 * Cos(LocalP.X * 1.5)));
    { Interconnected caustic ridge network (bright along W1->0 or W2->0 filaments
      with constructive focal cusps where crossed wave crests intersect) }
    CuspRaw := Max(
      Power(Clamped(1.0 - W1, 0.0, 1.0), 3.0),
      Power(Clamped(1.0 - W2, 0.0, 1.0), 3.0)) +
      0.45 * Power(Clamped(1.0 - 0.5 * (W1 + W2), 0.0, 1.0), 2.2);
    DepthAtten := Exp(-0.14 * Max(0.0, FWaterDepthMeters - LocalP.Y));
    Result.CausticLuminanceBoost := FCausticContrast * CuspRaw * DepthAtten;
  end;
end;

procedure TCastleThermalMirageVolume.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewWireScene := nil;
  end;
end;

procedure TCastleThermalMirageVolume.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  HX, HY, HZ: Single;
  Pts: array[0..9] of TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  HX := Max(0.25, FVolumeExtents.X) * 0.5;
  HY := Max(0.25, FVolumeExtents.Y);
  HZ := Max(0.25, FVolumeExtents.Z) * 0.5;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'ThermalMiragePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  FPreviewWireScene := TCastleScene.Create(FPreviewRoot);
  FPreviewWireScene.SetTransient;
  FPreviewWireScene.Pickable := False;
  FPreviewWireScene.Collides := False;
  FPreviewRoot.Add(FPreviewWireScene);

  Pts[0] := Vector3(-HX, 0.0, -HZ);
  Pts[1] := Vector3( HX, 0.0, -HZ);
  Pts[2] := Vector3( HX, 0.0,  HZ);
  Pts[3] := Vector3(-HX, 0.0,  HZ);
  Pts[4] := Pts[0];
  Pts[5] := Vector3(-HX, HY, -HZ);
  Pts[6] := Vector3( HX, HY, -HZ);
  Pts[7] := Vector3( HX, HY,  HZ);
  Pts[8] := Vector3(-HX, HY,  HZ);
  Pts[9] := Pts[5];

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  case FPreset of
    tmpDesertAsphaltMirage:     MatNode.EmissiveColor := Vector3(1.0, 0.72, 0.24);
    tmpVolcanicLavaVentShimmer: MatNode.EmissiveColor := Vector3(1.0, 0.34, 0.16);
    tmpSunlitCoralReefCaustics: MatNode.EmissiveColor := Vector3(0.24, 0.90, 1.0);
  end;
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([5, 5]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewWireScene.Load(RootNode, True);

  Add(FPreviewRoot);
end;

function TCastleThermalMirageVolume.MirageSummaryBadge: String;
begin
  if FCausticContrast > 0.01 then
    Result := FormatDot('[Caustics:Contrast=%.1fx Depth=%.1fm]', [
      FCausticContrast, FWaterDepthMeters])
  else
    Result := FormatDot('[Mirage:+%.0fC Shimmer=%.3f]', [
      FSurfaceDeltaTempCelsius, FShimmerDistortionAmplitude]);
end;

initialization
  RegisterSerializableComponent(TCastleThermalMirageVolume, 'Thermal Mirage & Caustic Refraction Volume');

end.
