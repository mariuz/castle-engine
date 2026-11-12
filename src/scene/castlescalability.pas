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

{ 5-tier hardware quality scalability manager (@link(TCastleScalabilityManager))
  and platform frame-budget specifications (`Mobile 60Hz`, `Handheld 60Hz`,
  `Desktop 60Hz`, `WebAssembly 60Hz`) scaling shadows, dynamic batching, LOD
  distances, particle budgets, decals, and post-processing non-destructively
  (Phase 306 — UE 6.0 Scalability & Insights Parity). }
unit CastleScalability;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Generics.Collections,
  CastleClassUtils, CastleUtils, CastleTransform;

type
  { Five-tier engine quality scalability preset matching UE `sg.*` tiers. }
  TScalabilityTier = (
    stLow,
    stMedium,
    stHigh,
    stEpic,
    stCinematic
  );

  { Target hardware 60 Hz frame-budget envelope for scene auditing. }
  TPlatformBudgetProfile = (
    pbpMobile60Hz,
    pbpHandheld60Hz,
    pbpDesktop60Hz,
    pbpWebAssembly60Hz
  );

  { Concrete multipliers and feature toggles for a @link(TScalabilityTier). }
  TScalabilityTierSpec = record
    ShadowsEnabled: Boolean;
    MaxShadowCastingLights: Integer;
    DynamicBatching: Boolean;
    LodDistanceScale: Single;
    ParticleBudgetScale: Single;
    DecalGridCap: Integer;
    PostProcessEnabled: Boolean;
    ChromaticAberrationAllowed: Boolean;
  end;

  { Per-platform 60 Hz hardware budget ceilings. }
  TPlatformFrameBudgetSpec = record
    MaxDrawCalls: Integer;
    MaxTriangles: Int64;
    MaxTextureVramMB: Single;
    MaxShadowLights: Integer;
    MaxActiveParticles: Integer;
    MaxAudioSources: Integer;
    TargetFrameTimeMs: Single;
  end;

  TScalabilityBaselineEntry = record
    ComponentKey: Pointer;
    IntVal1: Integer;
    FloatVal1: Single;
    FloatVal2: Single;
    FloatVal3: Single;
    BoolVal1: Boolean;
  end;

  { Non-visual scene scalability controller serializable in CGE designs.
    Remembers baseline (`stHigh` = 1.0x) component settings so switching across
    @code(Low .. Cinematic) tiers repeatedly is idempotent and reversible. }
  TCastleScalabilityManager = class(TCastleComponent)
  public const
    DefaultCustomMultiplier = Single(1.0);
  strict private
    FActiveTier: TScalabilityTier;
    FTargetPlatform: TPlatformBudgetProfile;
    FCustomLodBiasMultiplier: Single;
    FCustomParticleMultiplier: Single;
    FBaselines: array of TScalabilityBaselineEntry;

    procedure SetCustomLodBiasMultiplier(const Value: Single);
    procedure SetCustomParticleMultiplier(const Value: Single);
    function FindOrAddBaseline(const AComp: TObject;
      const AInt1: Integer; const AF1, AF2, AF3: Single;
      const ABool1: Boolean): TScalabilityBaselineEntry;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Apply @code(ATier) across all viewports, punctual lights, LOD proxies,
      particle emitters, decals, and post-process volumes under @code(ARoot).
      Returns total number of scene components adjusted. }
    function ApplyTierToHierarchy(const ARoot: TComponent;
      const ATier: TScalabilityTier): Integer;

    procedure ClearBaselines;
    function ScalabilitySummaryBadge: String;
  published
    property ActiveTier: TScalabilityTier
      read FActiveTier write FActiveTier default stHigh;
    property TargetPlatform: TPlatformBudgetProfile
      read FTargetPlatform write FTargetPlatform default pbpDesktop60Hz;
    property CustomLodBiasMultiplier: Single
      read FCustomLodBiasMultiplier write SetCustomLodBiasMultiplier
      {$ifdef FPC}default DefaultCustomMultiplier{$endif};
    property CustomParticleMultiplier: Single
      read FCustomParticleMultiplier write SetCustomParticleMultiplier
      {$ifdef FPC}default DefaultCustomMultiplier{$endif};
  end;

function ScalabilityTierDisplayName(const ATier: TScalabilityTier): String;
function PlatformBudgetDisplayName(const AProfile: TPlatformBudgetProfile): String;
function GetScalabilityTierSpec(const ATier: TScalabilityTier): TScalabilityTierSpec;
function GetPlatformFrameBudgetSpec(const AProfile: TPlatformBudgetProfile): TPlatformFrameBudgetSpec;

implementation

uses
  CastleComponentSerialize, CastleUiControls, CastleViewport, CastleScene,
  CastleParticles, CastleFoliageBiome, CastlePostProcessVolume, CastleDecalProjector;

function ScalabilityTierDisplayName(const ATier: TScalabilityTier): String;
begin
  case ATier of
    stLow: Result := 'Low';
    stMedium: Result := 'Medium';
    stHigh: Result := 'High';
    stEpic: Result := 'Epic';
    stCinematic: Result := 'Cinematic';
  end;
end;

function PlatformBudgetDisplayName(const AProfile: TPlatformBudgetProfile): String;
begin
  case AProfile of
    pbpMobile60Hz: Result := 'Mobile 60Hz';
    pbpHandheld60Hz: Result := 'Handheld 60Hz';
    pbpDesktop60Hz: Result := 'Desktop 60Hz';
    pbpWebAssembly60Hz: Result := 'WebAssembly 60Hz';
  end;
end;

function GetScalabilityTierSpec(const ATier: TScalabilityTier): TScalabilityTierSpec;
begin
  case ATier of
    stLow:
      begin
        Result.ShadowsEnabled := false;
        Result.MaxShadowCastingLights := 0;
        Result.DynamicBatching := true;
        Result.LodDistanceScale := 0.50;
        Result.ParticleBudgetScale := 0.25;
        Result.DecalGridCap := 4;
        Result.PostProcessEnabled := false;
        Result.ChromaticAberrationAllowed := false;
      end;
    stMedium:
      begin
        Result.ShadowsEnabled := true;
        Result.MaxShadowCastingLights := 1;
        Result.DynamicBatching := true;
        Result.LodDistanceScale := 0.75;
        Result.ParticleBudgetScale := 0.50;
        Result.DecalGridCap := 6;
        Result.PostProcessEnabled := true;
        Result.ChromaticAberrationAllowed := false;
      end;
    stHigh:
      begin
        Result.ShadowsEnabled := true;
        Result.MaxShadowCastingLights := 2;
        Result.DynamicBatching := true;
        Result.LodDistanceScale := 1.00;
        Result.ParticleBudgetScale := 1.00;
        Result.DecalGridCap := 8;
        Result.PostProcessEnabled := true;
        Result.ChromaticAberrationAllowed := true;
      end;
    stEpic:
      begin
        Result.ShadowsEnabled := true;
        Result.MaxShadowCastingLights := 4;
        Result.DynamicBatching := false;
        Result.LodDistanceScale := 1.35;
        Result.ParticleBudgetScale := 1.50;
        Result.DecalGridCap := 12;
        Result.PostProcessEnabled := true;
        Result.ChromaticAberrationAllowed := true;
      end;
    stCinematic:
      begin
        Result.ShadowsEnabled := true;
        Result.MaxShadowCastingLights := 8;
        Result.DynamicBatching := false;
        Result.LodDistanceScale := 2.00;
        Result.ParticleBudgetScale := 2.00;
        Result.DecalGridCap := 16;
        Result.PostProcessEnabled := true;
        Result.ChromaticAberrationAllowed := true;
      end;
  end;
end;

function GetPlatformFrameBudgetSpec(
  const AProfile: TPlatformBudgetProfile): TPlatformFrameBudgetSpec;
begin
  Result.TargetFrameTimeMs := 16.67;
  case AProfile of
    pbpMobile60Hz:
      begin
        Result.MaxDrawCalls := 120;
        Result.MaxTriangles := 150000;
        Result.MaxTextureVramMB := 128.0;
        Result.MaxShadowLights := 1;
        Result.MaxActiveParticles := 250;
        Result.MaxAudioSources := 16;
      end;
    pbpHandheld60Hz:
      begin
        Result.MaxDrawCalls := 350;
        Result.MaxTriangles := 500000;
        Result.MaxTextureVramMB := 384.0;
        Result.MaxShadowLights := 2;
        Result.MaxActiveParticles := 800;
        Result.MaxAudioSources := 32;
      end;
    pbpDesktop60Hz:
      begin
        Result.MaxDrawCalls := 1200;
        Result.MaxTriangles := 2000000;
        Result.MaxTextureVramMB := 1536.0;
        Result.MaxShadowLights := 4;
        Result.MaxActiveParticles := 3000;
        Result.MaxAudioSources := 64;
      end;
    pbpWebAssembly60Hz:
      begin
        Result.MaxDrawCalls := 180;
        Result.MaxTriangles := 250000;
        Result.MaxTextureVramMB := 192.0;
        Result.MaxShadowLights := 1;
        Result.MaxActiveParticles := 400;
        Result.MaxAudioSources := 24;
      end;
  end;
end;

{ TCastleScalabilityManager -------------------------------------------------- }

constructor TCastleScalabilityManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActiveTier := stHigh;
  FTargetPlatform := pbpDesktop60Hz;
  FCustomLodBiasMultiplier := DefaultCustomMultiplier;
  FCustomParticleMultiplier := DefaultCustomMultiplier;
  FBaselines := nil;
end;

procedure TCastleScalabilityManager.SetCustomLodBiasMultiplier(const Value: Single);
begin
  FCustomLodBiasMultiplier := Clamped(Value, 0.20, 4.0);
end;

procedure TCastleScalabilityManager.SetCustomParticleMultiplier(const Value: Single);
begin
  FCustomParticleMultiplier := Clamped(Value, 0.10, 4.0);
end;

function TCastleScalabilityManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ActiveTier', 'TargetPlatform',
       'CustomLodBiasMultiplier', 'CustomParticleMultiplier'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleScalabilityManager.FindOrAddBaseline(const AComp: TObject;
  const AInt1: Integer; const AF1, AF2, AF3: Single;
  const ABool1: Boolean): TScalabilityBaselineEntry;
var
  I, N: Integer;
begin
  for I := 0 to High(FBaselines) do
    if FBaselines[I].ComponentKey = Pointer(AComp) then
      Exit(FBaselines[I]);

  Result.ComponentKey := Pointer(AComp);
  Result.IntVal1 := AInt1;
  Result.FloatVal1 := AF1;
  Result.FloatVal2 := AF2;
  Result.FloatVal3 := AF3;
  Result.BoolVal1 := ABool1;

  N := Length(FBaselines);
  SetLength(FBaselines, N + 1);
  FBaselines[N] := Result;
end;

procedure TCastleScalabilityManager.ClearBaselines;
begin
  FBaselines := nil;
end;

function TCastleScalabilityManager.ApplyTierToHierarchy(
  const ARoot: TComponent; const ATier: TScalabilityTier): Integer;
var
  Spec: TScalabilityTierSpec;
  LodScale, PartScale: Single;
  ShadowLightsAssigned, TouchedCount: Integer;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    Vp: TCastleViewport;
    Light: TCastlePunctualLight;
    Part: TCastleParticleEmitter;
    PpVol: TCastlePostProcessVolume;
    Decal: TCastleDecalProjector;
    LodBeh: TCastleLodProxyBehavior;
    Base: TScalabilityBaselineEntry;
  begin
    if C = nil then
      Exit;

    if C is TCastleViewport then
    begin
      Vp := TCastleViewport(C);
      Vp.ShadowVolumes := Spec.ShadowsEnabled;
      Vp.DynamicBatching := Spec.DynamicBatching;
      Inc(TouchedCount);
      Visit(Vp.Items);
      for I := 0 to Vp.ControlsCount - 1 do
        Visit(Vp.Controls[I]);
      Exit;
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if csTransient in T.ComponentStyle then
        Exit;

      if T is TCastlePunctualLight then
      begin
        Light := TCastlePunctualLight(T);
        Base := FindOrAddBaseline(Light, 0, 0.0, 0.0, 0.0, Light.Shadows);
        if Base.BoolVal1 and Spec.ShadowsEnabled and
           (ShadowLightsAssigned < Spec.MaxShadowCastingLights) then
        begin
          Light.Shadows := true;
          Inc(ShadowLightsAssigned);
        end else
          Light.Shadows := false;
        Inc(TouchedCount);
      end else
      if T is TCastleParticleEmitter then
      begin
        Part := TCastleParticleEmitter(T);
        Base := FindOrAddBaseline(Part, Part.MaxParticles, Part.SpawnRate, 0, 0, Part.Emitting);
        Part.MaxParticles := Max(4, Round(Base.IntVal1 * PartScale));
        Part.SpawnRate := Max(0.5, Base.FloatVal1 * PartScale);
        Inc(TouchedCount);
      end else
      if T is TCastlePostProcessVolume then
      begin
        PpVol := TCastlePostProcessVolume(T);
        Base := FindOrAddBaseline(PpVol, 0, PpVol.ChromaticAberrationPx, 0, 0, PpVol.VolumeEnabled);
        PpVol.VolumeEnabled := Base.BoolVal1 and Spec.PostProcessEnabled;
        if Spec.ChromaticAberrationAllowed then
          PpVol.ChromaticAberrationPx := Base.FloatVal1
        else
          PpVol.ChromaticAberrationPx := 0.0;
        Inc(TouchedCount);
      end else
      if T is TCastleDecalProjector then
      begin
        Decal := TCastleDecalProjector(T);
        Base := FindOrAddBaseline(Decal, Decal.GridResolution, 0, 0, 0, true);
        Decal.GridResolution := Min(Base.IntVal1, Spec.DecalGridCap);
        Inc(TouchedCount);
      end;

      for I := 0 to T.BehaviorsCount - 1 do
        if T.Behaviors[I] is TCastleLodProxyBehavior then
        begin
          LodBeh := TCastleLodProxyBehavior(T.Behaviors[I]);
          Base := FindOrAddBaseline(LodBeh, 0,
            LodBeh.MediumDistance, LodBeh.LowDistance, LodBeh.CullDistance, true);
          { Assign in order preserving Medium < Low < Cull constraints }
          if LodScale >= 1.0 then
          begin
            LodBeh.CullDistance := Base.FloatVal3 * LodScale;
            LodBeh.LowDistance := Base.FloatVal2 * LodScale;
            LodBeh.MediumDistance := Base.FloatVal1 * LodScale;
          end else
          begin
            LodBeh.MediumDistance := Base.FloatVal1 * LodScale;
            LodBeh.LowDistance := Base.FloatVal2 * LodScale;
            LodBeh.CullDistance := Base.FloatVal3 * LodScale;
          end;
          Inc(TouchedCount);
        end;

      for I := 0 to T.Count - 1 do
        Visit(T[I]);
      Exit;
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;
  end;

begin
  FActiveTier := ATier;
  Spec := GetScalabilityTierSpec(ATier);
  LodScale := Spec.LodDistanceScale * FCustomLodBiasMultiplier;
  PartScale := Spec.ParticleBudgetScale * FCustomParticleMultiplier;
  ShadowLightsAssigned := 0;
  TouchedCount := 0;
  Visit(ARoot);
  Result := TouchedCount;
end;

function TCastleScalabilityManager.ScalabilitySummaryBadge: String;
begin
  Result := Format('[Scalability:%s %s]', [
    ScalabilityTierDisplayName(FActiveTier),
    PlatformBudgetDisplayName(FTargetPlatform)]);
end;

initialization
  RegisterSerializableComponent(TCastleScalabilityManager,
    ['Performance & Scalability', 'Scalability Quality Manager']);
end.
