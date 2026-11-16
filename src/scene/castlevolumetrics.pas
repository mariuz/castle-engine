{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Volumetric Exponential Height Fog, Henyey-Greenstein Anisotropic Sun
  In-Scattering / God-Rays & Priority-Weighted Box-Parallax Local Reflection
  Probes (@link(TCastleVolumetricAtmosphere), @link(TCastleReflectionProbe),
  @link(EvaluateHenyeyGreensteinPhase), @link(ComputeBoxParallaxReflectionDir))
  (Phase 324 — UE 6.0+ Volumetric Fog & Box Reflection Captures Parity). }
unit CastleVolumetrics;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleScene, X3DNodes;

type
  { Built-in volumetric height fog & god-ray look presets. }
  TVolumetricPreset = (
    vpCustom,
    vpMorningValleyMist,
    vpGoldenHourGodRays,
    vpDenseSwampMiasma,
    vpCyberpunkNeonHaze
  );

  { Exponential height-density volumetric fog & anisotropic Henyey-Greenstein
    solar in-scattering manager. Analytically integrates optical depth along
    arbitrary 3D camera-to-surface segments. }
  TCastleVolumetricAtmosphere = class(TCastleTransform)
  public
    const
      DefaultBaseAltitudeY = 0.0;
      DefaultBaseDensity = 0.035;
      DefaultHeightFalloff = 0.12;
      DefaultScatteringAnisotropyG = 0.72;
      DefaultGodRayIntensity = 1.25;
      DefaultMaxFogOpacity = 0.96;
  strict private
    FPreset: TVolumetricPreset;
    FBaseAltitudeY: Single;
    FBaseDensity: Single;
    FHeightFalloff: Single;
    FScatteringAnisotropyG: Single;
    FGodRayIntensity: Single;
    FMaxFogOpacity: Single;
    FSunDirectionW: TVector3;
    FFogColor: TCastleColorRGB;
    FSunInscatterColor: TCastleColorRGB;
    FFogColorPersistent: TCastleColorRGBPersistent;
    FSunInscatterColorPersistent: TCastleColorRGBPersistent;

    procedure SetPreset(const Value: TVolumetricPreset);
    function GetFogColorForPersistent: TCastleColorRGB;
    procedure SetFogColorForPersistent(const AValue: TCastleColorRGB);
    function GetSunInscatterForPersistent: TCastleColorRGB;
    procedure SetSunInscatterForPersistent(const AValue: TCastleColorRGB);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TVolumetricPreset): String; static;

    procedure ApplyPreset(const APreset: TVolumetricPreset);

    { Local fog density at world elevation @code(WorldY). }
    function DensityAtAltitude(const WorldY: Single): Single;

    { Closed-form line integral of exponential height fog optical depth tau >= 0
      between @code(CameraPosW) and @code(TargetPosW), returning Beer-Lambert
      transmittance @code(exp(-tau)) in [1 - MaxFogOpacity .. 1.0]. }
    function EvaluateSegmentTransmittance(const CameraPosW, TargetPosW: TVector3;
      out OutOpticalDepthTau: Single): Single;

    { Evaluate composite in-scattered fog RGB + opacity (alpha = 1 - Transmittance)
      along view ray @code(CameraPosW -> TargetPosW). }
    function EvaluateAerialPerspective(const CameraPosW, TargetPosW: TVector3): TCastleColor;

    function VolumetricSummaryBadge: String;

    property SunDirectionW: TVector3 read FSunDirectionW write FSunDirectionW;
    property FogColor: TCastleColorRGB read FFogColor write FFogColor;
    property SunInscatterColor: TCastleColorRGB read FSunInscatterColor write FSunInscatterColor;
  published
    property Preset: TVolumetricPreset read FPreset write SetPreset default vpGoldenHourGodRays;
    property BaseAltitudeY: Single read FBaseAltitudeY write FBaseAltitudeY {$ifdef FPC}default DefaultBaseAltitudeY{$endif};
    property BaseDensity: Single read FBaseDensity write FBaseDensity {$ifdef FPC}default DefaultBaseDensity{$endif};
    property HeightFalloff: Single read FHeightFalloff write FHeightFalloff {$ifdef FPC}default DefaultHeightFalloff{$endif};
    property ScatteringAnisotropyG: Single read FScatteringAnisotropyG write FScatteringAnisotropyG {$ifdef FPC}default DefaultScatteringAnisotropyG{$endif};
    property GodRayIntensity: Single read FGodRayIntensity write FGodRayIntensity {$ifdef FPC}default DefaultGodRayIntensity{$endif};
    property MaxFogOpacity: Single read FMaxFogOpacity write FMaxFogOpacity {$ifdef FPC}default DefaultMaxFogOpacity{$endif};
    property FogColorPersistent: TCastleColorRGBPersistent read FFogColorPersistent;
    property SunInscatterColorPersistent: TCastleColorRGBPersistent read FSunInscatterColorPersistent;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Local Box-Parallax Reflection & Irradiance Capture Probe with smooth outer
    feather @link(BlendDistance) and @link(Priority) override ordering. }
  TCastleReflectionProbe = class(TCastleTransform)
  public
    const
      DefaultHalfExtent = 5.0;
      DefaultBlendDistance = 2.0;
      DefaultSpecularIntensity = 1.0;
  strict private
    FPriority: Integer;
    FHalfExtents: TVector3;
    FBlendDistance: Single;
    FSpecularIntensity: Single;
    FBoxParallaxCorrection: Boolean;
    FIrradianceTint: TCastleColorRGB;
    FIrradianceTintPersistent: TCastleColorRGBPersistent;
    FGizmoSphere: TCastleSphere;

    function GetIrradianceForPersistent: TCastleColorRGB;
    procedure SetIrradianceForPersistent(const AValue: TCastleColorRGB);
    procedure SetHalfExtentX(const Value: Single);
    procedure SetHalfExtentY(const Value: Single);
    procedure SetHalfExtentZ(const Value: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure EnsureGizmoSphere;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Smooth Hermite spatial influence weight in [0..1] at @code(WorldPos):
      1.0 inside core box, SmoothStep falloff across @link(BlendDistance), 0.0 outside. }
    function EvaluateInfluenceWeight(const WorldPos: TVector3): Single;

    { Evaluate finite room box-parallax corrected reflection lookup vector from
      this probe's capture origin. }
    function SampleParallaxReflectionDir(const WorldShadingPos, WorldReflectDir: TVector3): TVector3;

    function ProbeSummaryBadge: String;

    property HalfExtents: TVector3 read FHalfExtents write FHalfExtents;
    property IrradianceTint: TCastleColorRGB read FIrradianceTint write FIrradianceTint;
  published
    property Priority: Integer read FPriority write FPriority default 10;
    property HalfExtentX: Single read FHalfExtents.X write SetHalfExtentX {$ifdef FPC}default DefaultHalfExtent{$endif};
    property HalfExtentY: Single read FHalfExtents.Y write SetHalfExtentY {$ifdef FPC}default DefaultHalfExtent{$endif};
    property HalfExtentZ: Single read FHalfExtents.Z write SetHalfExtentZ {$ifdef FPC}default DefaultHalfExtent{$endif};
    property BlendDistance: Single read FBlendDistance write FBlendDistance {$ifdef FPC}default DefaultBlendDistance{$endif};
    property SpecularIntensity: Single read FSpecularIntensity write FSpecularIntensity {$ifdef FPC}default DefaultSpecularIntensity{$endif};
    property BoxParallaxCorrection: Boolean read FBoxParallaxCorrection write FBoxParallaxCorrection default true;
    property IrradianceTintPersistent: TCastleColorRGBPersistent read FIrradianceTintPersistent;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Normalized Henyey-Greenstein phase function P(cosTheta, g):
  (1 - g^2) / (4*Pi * (1 + g^2 - 2*g*cosTheta)^1.5). }
function EvaluateHenyeyGreensteinPhase(const CosTheta, AnisotropyG: Single): Single;

{ Sébastien Lagarde finite AABB Box-Parallax Corrected cubemap reflection lookup
  direction from @code(ProbeOriginW) for ray @code(ShadingPosW + t * ReflectDirW). }
function ComputeBoxParallaxReflectionDir(
  const ShadingPosW, ReflectDirW, ProbeOriginW, BoxMinW, BoxMaxW: TVector3): TVector3;

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize;

function EvaluateHenyeyGreensteinPhase(const CosTheta, AnisotropyG: Single): Single;
var
  G, C, DenomBase: Single;
begin
  G := Clamped(AnisotropyG, -0.95, 0.95);
  C := Clamped(CosTheta, -1.0, 1.0);
  DenomBase := Max(1e-5, 1.0 + G * G - 2.0 * G * C);
  Result := (1.0 - G * G) / (4.0 * Pi * DenomBase * Sqrt(DenomBase));
end;

function ComputeBoxParallaxReflectionDir(
  const ShadingPosW, ReflectDirW, ProbeOriginW, BoxMinW, BoxMaxW: TVector3): TVector3;
var
  Dir, HitPointW, OffsetFromProbe: TVector3;
  TExit, T1, T2, AxisMax: Single;
  Axis: Integer;
begin
  if ReflectDirW.LengthSqr < 1e-10 then
    Exit(Vector3(0.0, 1.0, 0.0));
  Dir := ReflectDirW.Normalize;

  TExit := MaxSingle;
  for Axis := 0 to 2 do
  begin
    if Abs(Dir.Data[Axis]) > 1e-6 then
    begin
      T1 := (BoxMinW.Data[Axis] - ShadingPosW.Data[Axis]) / Dir.Data[Axis];
      T2 := (BoxMaxW.Data[Axis] - ShadingPosW.Data[Axis]) / Dir.Data[Axis];
      AxisMax := Max(T1, T2);
      if AxisMax > 0.0 then
        TExit := Min(TExit, AxisMax);
    end;
  end;

  if (TExit <= 0.0) or (TExit >= MaxSingle * 0.5) then
    Exit(Dir);

  HitPointW := ShadingPosW + Dir * TExit;
  OffsetFromProbe := HitPointW - ProbeOriginW;
  if OffsetFromProbe.LengthSqr < 1e-10 then
    Result := Dir
  else
    Result := OffsetFromProbe.Normalize;
end;

{ TCastleVolumetricAtmosphere ------------------------------------------------ }

constructor TCastleVolumetricAtmosphere.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSunDirectionW := Vector3(0.35, -0.28, -0.89).Normalize;
  FFogColor := Vector3(0.58, 0.68, 0.82);
  FSunInscatterColor := Vector3(1.00, 0.78, 0.44);

  FFogColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FFogColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetFogColorForPersistent;
  FFogColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetFogColorForPersistent;
  FFogColorPersistent.InternalDefaultValue := FFogColor;

  FSunInscatterColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FSunInscatterColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetSunInscatterForPersistent;
  FSunInscatterColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetSunInscatterForPersistent;
  FSunInscatterColorPersistent.InternalDefaultValue := FSunInscatterColor;

  ApplyPreset(vpGoldenHourGodRays);
end;

destructor TCastleVolumetricAtmosphere.Destroy;
begin
  FreeAndNil(FFogColorPersistent);
  FreeAndNil(FSunInscatterColorPersistent);
  inherited;
end;

class function TCastleVolumetricAtmosphere.PresetDisplayName(const APreset: TVolumetricPreset): String;
begin
  case APreset of
    vpCustom:            Result := 'Custom Volumetrics';
    vpMorningValleyMist: Result := 'Morning Valley Mist';
    vpGoldenHourGodRays: Result := 'Golden Hour God-Rays';
    vpDenseSwampMiasma:  Result := 'Dense Swamp Miasma';
    vpCyberpunkNeonHaze: Result := 'Cyberpunk Neon Haze';
  end;
end;

procedure TCastleVolumetricAtmosphere.ApplyPreset(const APreset: TVolumetricPreset);
begin
  FPreset := APreset;
  case APreset of
    vpMorningValleyMist:
      begin
        FBaseAltitudeY := 0.0;
        FBaseDensity := 0.055;
        FHeightFalloff := 0.18;
        FScatteringAnisotropyG := 0.58;
        FGodRayIntensity := 0.85;
        FMaxFogOpacity := 0.95;
        FFogColor := Vector3(0.72, 0.80, 0.90);
        FSunInscatterColor := Vector3(0.98, 0.90, 0.76);
      end;
    vpGoldenHourGodRays:
      begin
        FBaseAltitudeY := 0.0;
        FBaseDensity := 0.035;
        FHeightFalloff := 0.12;
        FScatteringAnisotropyG := 0.76;
        FGodRayIntensity := 1.45;
        FMaxFogOpacity := 0.96;
        FFogColor := Vector3(0.58, 0.66, 0.82);
        FSunInscatterColor := Vector3(1.00, 0.76, 0.38);
      end;
    vpDenseSwampMiasma:
      begin
        FBaseAltitudeY := 0.0;
        FBaseDensity := 0.095;
        FHeightFalloff := 0.28;
        FScatteringAnisotropyG := 0.42;
        FGodRayIntensity := 0.55;
        FMaxFogOpacity := 0.98;
        FFogColor := Vector3(0.32, 0.44, 0.34);
        FSunInscatterColor := Vector3(0.68, 0.82, 0.52);
      end;
    vpCyberpunkNeonHaze:
      begin
        FBaseAltitudeY := 0.0;
        FBaseDensity := 0.045;
        FHeightFalloff := 0.08;
        FScatteringAnisotropyG := 0.68;
        FGodRayIntensity := 1.35;
        FMaxFogOpacity := 0.94;
        FFogColor := Vector3(0.18, 0.22, 0.42);
        FSunInscatterColor := Vector3(0.96, 0.32, 0.78);
      end;
    vpCustom: ;
  end;
end;

function TCastleVolumetricAtmosphere.DensityAtAltitude(const WorldY: Single): Single;
var
  Exponent: Single;
begin
  Exponent := Clamped(-Max(0.0, FHeightFalloff) * (WorldY - FBaseAltitudeY), -40.0, 12.0);
  Result := Max(0.0, FBaseDensity) * Exp(Exponent);
end;

function TCastleVolumetricAtmosphere.EvaluateSegmentTransmittance(
  const CameraPosW, TargetPosW: TVector3; out OutOpticalDepthTau: Single): Single;
var
  Dist, LowY, AbsDeltaY, H, DensityLow, VertFactor, MinTrans: Single;
begin
  Dist := (TargetPosW - CameraPosW).Length;
  if (Dist < 1e-5) or (FBaseDensity <= 0.0) then
  begin
    OutOpticalDepthTau := 0.0;
    Exit(1.0);
  end;

  H := Max(0.0, FHeightFalloff);
  LowY := Min(CameraPosW.Y, TargetPosW.Y);
  AbsDeltaY := Abs(TargetPosW.Y - CameraPosW.Y);
  DensityLow := DensityAtAltitude(LowY);

  if H * AbsDeltaY < 1e-4 then
    VertFactor := 1.0 - 0.5 * H * AbsDeltaY
  else
    VertFactor := (1.0 - Exp(-H * AbsDeltaY)) / (H * AbsDeltaY);

  OutOpticalDepthTau := Max(0.0, Dist * DensityLow * VertFactor);
  MinTrans := 1.0 - Clamped(FMaxFogOpacity, 0.0, 1.0);
  Result := Clamped(Exp(-Min(40.0, OutOpticalDepthTau)), MinTrans, 1.0);
end;

function TCastleVolumetricAtmosphere.EvaluateAerialPerspective(
  const CameraPosW, TargetPosW: TVector3): TCastleColor;
var
  Trans, Opacity, Tau, CosSun, PhaseVal, SunBlend: Single;
  ViewDir, TowardSunDir, FinalRGB: TVector3;
begin
  Trans := EvaluateSegmentTransmittance(CameraPosW, TargetPosW, Tau);
  Opacity := 1.0 - Trans;

  ViewDir := TargetPosW - CameraPosW;
  if ViewDir.LengthSqr < 1e-8 then
    ViewDir := Vector3(0.0, 0.0, -1.0)
  else
    ViewDir := ViewDir.Normalize;

  if FSunDirectionW.LengthSqr < 1e-8 then
    TowardSunDir := Vector3(0.0, 0.6, 0.8).Normalize
  else
    TowardSunDir := (-FSunDirectionW).Normalize;

  CosSun := TVector3.DotProduct(ViewDir, TowardSunDir);
  PhaseVal := EvaluateHenyeyGreensteinPhase(CosSun, FScatteringAnisotropyG);
  SunBlend := Clamped(PhaseVal * FGodRayIntensity * 0.45, 0.0, 1.0);
  FinalRGB := Lerp(SunBlend, FFogColor, FSunInscatterColor);

  Result := Vector4(FinalRGB.X, FinalRGB.Y, FinalRGB.Z, Opacity);
end;

function TCastleVolumetricAtmosphere.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'BaseAltitudeY') or
     (PropertyName = 'BaseDensity') or
     (PropertyName = 'HeightFalloff') or
     (PropertyName = 'ScatteringAnisotropyG') or
     (PropertyName = 'GodRayIntensity') or
     (PropertyName = 'FogColorPersistent') or
     (PropertyName = 'SunInscatterColorPersistent') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleVolumetricAtmosphere.VolumetricSummaryBadge: String;
begin
  Result := Format('[VolFog:%s d=%.3f g=%.2f]', [
    PresetDisplayName(FPreset), FBaseDensity, FScatteringAnisotropyG]);
end;

procedure TCastleVolumetricAtmosphere.SetPreset(const Value: TVolumetricPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

function TCastleVolumetricAtmosphere.GetFogColorForPersistent: TCastleColorRGB;
begin
  Result := FFogColor;
end;

procedure TCastleVolumetricAtmosphere.SetFogColorForPersistent(const AValue: TCastleColorRGB);
begin
  FFogColor := AValue;
end;

function TCastleVolumetricAtmosphere.GetSunInscatterForPersistent: TCastleColorRGB;
begin
  Result := FSunInscatterColor;
end;

procedure TCastleVolumetricAtmosphere.SetSunInscatterForPersistent(const AValue: TCastleColorRGB);
begin
  FSunInscatterColor := AValue;
end;

function TCastleVolumetricAtmosphere.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('baseY', FBaseAltitudeY);
    Root.Add('density', FBaseDensity);
    Root.Add('falloff', FHeightFalloff);
    Root.Add('g', FScatteringAnisotropyG);
    Root.Add('godRay', FGodRayIntensity);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleVolumetricAtmosphere.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TVolumetricPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TVolumetricPreset))));
      FBaseAltitudeY := Root.Get('baseY', FBaseAltitudeY);
      FBaseDensity := Max(0.0, Root.Get('density', FBaseDensity));
      FHeightFalloff := Max(0.0, Root.Get('falloff', FHeightFalloff));
      FScatteringAnisotropyG := Clamped(Root.Get('g', FScatteringAnisotropyG), -0.95, 0.95);
      FGodRayIntensity := Max(0.0, Root.Get('godRay', FGodRayIntensity));
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleReflectionProbe ----------------------------------------------------- }

constructor TCastleReflectionProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPriority := 10;
  FHalfExtents := Vector3(DefaultHalfExtent, DefaultHalfExtent, DefaultHalfExtent);
  FBlendDistance := DefaultBlendDistance;
  FSpecularIntensity := DefaultSpecularIntensity;
  FBoxParallaxCorrection := True;
  FIrradianceTint := Vector3(0.86, 0.91, 1.00);

  FIrradianceTintPersistent := TCastleColorRGBPersistent.Create(nil);
  FIrradianceTintPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetIrradianceForPersistent;
  FIrradianceTintPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetIrradianceForPersistent;
  FIrradianceTintPersistent.InternalDefaultValue := FIrradianceTint;

  EnsureGizmoSphere;
end;

destructor TCastleReflectionProbe.Destroy;
begin
  FreeAndNil(FIrradianceTintPersistent);
  inherited;
end;

procedure TCastleReflectionProbe.Loaded;
begin
  inherited;
  EnsureGizmoSphere;
end;

procedure TCastleReflectionProbe.EnsureGizmoSphere;
begin
  if csLoading in ComponentState then
    Exit;
  if FGizmoSphere = nil then
  begin
    FGizmoSphere := TCastleSphere.Create(Self);
    FGizmoSphere.SetTransient;
    FGizmoSphere.Pickable := False;
    FGizmoSphere.Collides := False;
    FGizmoSphere.Radius := 0.32;
    FGizmoSphere.Color := Vector4(0.82, 0.90, 1.00, 1.0);
    Add(FGizmoSphere);
  end;
end;

function TCastleReflectionProbe.EvaluateInfluenceWeight(const WorldPos: TVector3): Single;
var
  Offset, Excess: TVector3;
  DistOutsideBox, T: Single;
begin
  Offset := Vector3(
    Abs(WorldPos.X - Translation.X),
    Abs(WorldPos.Y - Translation.Y),
    Abs(WorldPos.Z - Translation.Z));
  Excess := Vector3(
    Max(0.0, Offset.X - Max(0.1, FHalfExtents.X)),
    Max(0.0, Offset.Y - Max(0.1, FHalfExtents.Y)),
    Max(0.0, Offset.Z - Max(0.1, FHalfExtents.Z)));
  DistOutsideBox := Excess.Length;
  if DistOutsideBox <= 1e-5 then
    Exit(1.0);
  if FBlendDistance <= 1e-4 then
    Exit(0.0);
  if DistOutsideBox >= FBlendDistance then
    Exit(0.0);
  T := 1.0 - (DistOutsideBox / FBlendDistance);
  Result := T * T * (3.0 - 2.0 * T);
end;

function TCastleReflectionProbe.SampleParallaxReflectionDir(
  const WorldShadingPos, WorldReflectDir: TVector3): TVector3;
var
  BoxMinW, BoxMaxW: TVector3;
begin
  if not FBoxParallaxCorrection then
  begin
    if WorldReflectDir.LengthSqr < 1e-10 then
      Exit(Vector3(0.0, 1.0, 0.0))
    else
      Exit(WorldReflectDir.Normalize);
  end;
  BoxMinW := Translation - FHalfExtents;
  BoxMaxW := Translation + FHalfExtents;
  Result := ComputeBoxParallaxReflectionDir(
    WorldShadingPos, WorldReflectDir, Translation, BoxMinW, BoxMaxW);
end;

function TCastleReflectionProbe.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Priority') or
     (PropertyName = 'HalfExtentX') or
     (PropertyName = 'HalfExtentY') or
     (PropertyName = 'HalfExtentZ') or
     (PropertyName = 'BlendDistance') or
     (PropertyName = 'SpecularIntensity') or
     (PropertyName = 'BoxParallaxCorrection') or
     (PropertyName = 'IrradianceTintPersistent') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleReflectionProbe.ProbeSummaryBadge: String;
begin
  Result := Format('[Probe:Prio %d %.0fx%.0fx%.0fm]', [
    FPriority, FHalfExtents.X * 2.0, FHalfExtents.Y * 2.0, FHalfExtents.Z * 2.0]);
end;

function TCastleReflectionProbe.GetIrradianceForPersistent: TCastleColorRGB;
begin
  Result := FIrradianceTint;
end;

procedure TCastleReflectionProbe.SetIrradianceForPersistent(const AValue: TCastleColorRGB);
begin
  FIrradianceTint := AValue;
end;

procedure TCastleReflectionProbe.SetHalfExtentX(const Value: Single);
begin
  FHalfExtents.X := Max(0.1, Value);
end;

procedure TCastleReflectionProbe.SetHalfExtentY(const Value: Single);
begin
  FHalfExtents.Y := Max(0.1, Value);
end;

procedure TCastleReflectionProbe.SetHalfExtentZ(const Value: Single);
begin
  FHalfExtents.Z := Max(0.1, Value);
end;

function TCastleReflectionProbe.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('prio', FPriority);
    Root.Add('ex', FHalfExtents.X);
    Root.Add('ey', FHalfExtents.Y);
    Root.Add('ez', FHalfExtents.Z);
    Root.Add('blend', FBlendDistance);
    Root.Add('parallax', FBoxParallaxCorrection);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleReflectionProbe.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPriority := Root.Get('prio', FPriority);
      FHalfExtents.X := Max(0.1, Root.Get('ex', FHalfExtents.X));
      FHalfExtents.Y := Max(0.1, Root.Get('ey', FHalfExtents.Y));
      FHalfExtents.Z := Max(0.1, Root.Get('ez', FHalfExtents.Z));
      FBlendDistance := Max(0.0, Root.Get('blend', FBlendDistance));
      FBoxParallaxCorrection := Root.Get('parallax', FBoxParallaxCorrection);
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleVolumetricAtmosphere,
    ['Lighting & Atmosphere', 'Volumetric Height Fog & Henyey-Greenstein God-Rays']);
  RegisterSerializableComponent(TCastleReflectionProbe,
    ['Lighting & Atmosphere', 'Box-Parallax Local Reflection Probe']);
end.
