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

{ Priority-blended 3D post-processing volumes, cinematic color-grading presets,
  and X3D @code(TScreenEffectNode) GLSL post-process stack
  (@link(TCastlePostProcessVolume), @link(TCastlePostProcessStack))
  (Phase 293 — UE 5.9 / 6.0 APostProcessVolume Parity). }
unit CastlePostProcessVolume;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleBoxes, CastleClassUtils, CastleTransform,
  CastleViewport, X3DNodes, X3DFields;

type
  { Built-in cinematic look-development presets. }
  TCastlePostProcessPreset = (
    pppNeutral,
    pppWarmSunset,
    pppSciFiCold,
    pppNoirHighContrast,
    pppHorrorVignette,
    pppVintageSepia
  );

  { Evaluated color-grading & lens post-processing parameter block. }
  TPostProcessSettings = record
    ExposureEV: Single;
    AcesTonemapMix: Single;
    Contrast: Single;
    Saturation: Single;
    VignetteIntensity: Single;
    ChromaticAberrationPx: Single;
    TintRed: Single;
    TintGreen: Single;
    TintBlue: Single;
    class function Neutral: TPostProcessSettings; static;
    class function Lerp(const AWeight: Single;
      const AFrom, ATo: TPostProcessSettings): TPostProcessSettings; static;
    function IsEffectivelyNeutral: Boolean;
  end;

  { Global (@code(IsUnbound = true)) or spatially bounded 3D post-processing
    volume with priority ordering and Hermite @link(BlendRadius) falloff. }
  TCastlePostProcessVolume = class(TCastleTransform)
  public const
    DefaultCoreRadius = 6.0;
    DefaultBlendRadius = 4.0;
    DefaultBlendWeight = 1.0;
    DefaultNeutralOne = 1.0;
  strict private
    FVolumeLabel: String;
    FLookPreset: TCastlePostProcessPreset;
    FIsUnbound: Boolean;
    FCoreRadius: Single;
    FBlendRadius: Single;
    FPriority: Integer;
    FBlendWeight: Single;
    FVolumeEnabled: Boolean;
    FShowVolumeInViewport: Boolean;
    FExposureEV: Single;
    FAcesTonemapMix: Single;
    FContrast: Single;
    FSaturation: Single;
    FVignetteIntensity: Single;
    FChromaticAberrationPx: Single;
    FTintRed: Single;
    FTintGreen: Single;
    FTintBlue: Single;
    procedure SetCoreRadius(const AValue: Single);
    procedure SetBlendRadius(const AValue: Single);
    procedure SetBlendWeight(const AValue: Single);
    procedure SetExposureEV(const AValue: Single);
    procedure SetAcesTonemapMix(const AValue: Single);
    procedure SetContrast(const AValue: Single);
    procedure SetSaturation(const AValue: Single);
    procedure SetVignetteIntensity(const AValue: Single);
    procedure SetChromaticAberrationPx(const AValue: Single);
    procedure SetTintRed(const AValue: Single);
    procedure SetTintGreen(const AValue: Single);
    procedure SetTintBlue(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;

    { Populate color-grading fields from one of the 6 look-dev presets. }
    procedure ApplyLookPreset(const APreset: TCastlePostProcessPreset);

    { Snapshot this volume's grading properties into @link(TPostProcessSettings). }
    function ToSettings: TPostProcessSettings;

    { Evaluate effective blend weight in @code([0..1]) at @code(AObserverWorldPos). }
    function EvaluateObserverWeight(const AObserverWorldPos: TVector3): Single;

    function VolumeSummaryBadge: String;
  published
    property VolumeLabel: String read FVolumeLabel write FVolumeLabel;
    property LookPreset: TCastlePostProcessPreset
      read FLookPreset write FLookPreset default pppNeutral;
    property IsUnbound: Boolean read FIsUnbound write FIsUnbound default true;
    property CoreRadius: Single read FCoreRadius write SetCoreRadius {$ifdef FPC}default DefaultCoreRadius{$endif};
    property BlendRadius: Single read FBlendRadius write SetBlendRadius {$ifdef FPC}default DefaultBlendRadius{$endif};
    property Priority: Integer read FPriority write FPriority default 0;
    property BlendWeight: Single read FBlendWeight write SetBlendWeight {$ifdef FPC}default DefaultBlendWeight{$endif};
    property VolumeEnabled: Boolean read FVolumeEnabled write FVolumeEnabled default true;
    property ShowVolumeInViewport: Boolean read FShowVolumeInViewport write FShowVolumeInViewport default true;

    property ExposureEV: Single read FExposureEV write SetExposureEV {$ifdef FPC}default 0.0{$endif};
    property AcesTonemapMix: Single read FAcesTonemapMix write SetAcesTonemapMix {$ifdef FPC}default 0.0{$endif};
    property Contrast: Single read FContrast write SetContrast {$ifdef FPC}default DefaultNeutralOne{$endif};
    property Saturation: Single read FSaturation write SetSaturation {$ifdef FPC}default DefaultNeutralOne{$endif};
    property VignetteIntensity: Single read FVignetteIntensity write SetVignetteIntensity {$ifdef FPC}default 0.0{$endif};
    property ChromaticAberrationPx: Single read FChromaticAberrationPx write SetChromaticAberrationPx {$ifdef FPC}default 0.0{$endif};
    property TintRed: Single read FTintRed write SetTintRed {$ifdef FPC}default DefaultNeutralOne{$endif};
    property TintGreen: Single read FTintGreen write SetTintGreen {$ifdef FPC}default DefaultNeutralOne{$endif};
    property TintBlue: Single read FTintBlue write SetTintBlue {$ifdef FPC}default DefaultNeutralOne{$endif};
  end;

  { Non-visual controller that evaluates priority-sorted
    @link(TCastlePostProcessVolume) instances and drives a live X3D
    @code(TScreenEffectNode) GLSL post-processing shader on @link(TCastleViewport). }
  TCastlePostProcessStack = class(TCastleComponent)
  public const
    ScreenEffectNodeName = 'CastlePostProcessStackEffect';
  strict private
    FStackEnabled: Boolean;
    FAttachedViewport: TCastleViewport;
    FScreenEffectNode: TScreenEffectNode;
    FShaderNode: TComposedShaderNode;
    FFragPart: TShaderPartNode;
    FFdExposureMul: TSFFloat;
    FFdAcesMix: TSFFloat;
    FFdContrast: TSFFloat;
    FFdSaturation: TSFFloat;
    FFdVignette: TSFFloat;
    FFdChromaticPx: TSFFloat;
    FFdColorTint: TSFVec3f;
    FLastSettings: TPostProcessSettings;
    procedure EnsureScreenEffectBuilt;
    procedure DetachFromViewport;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Generate the CGE @code(screen_effect_library.glsl)-compatible fragment
      shader source for the post-processing pipeline. }
    class function BuildPostProcessFragmentGlsl: String;

    { Evaluate priority-sorted volumes inside @code(ARoot) for observer position
      @code(AObserverWorldPos). }
    class function EvaluateBlendedWorldSettings(const ARoot: TComponent;
      const AObserverWorldPos: TVector3;
      out OutActiveVolumeCount: Integer): TPostProcessSettings;

    { Evaluate volumes in @code(ARoot) and apply/update the live X3D
      @code(TScreenEffectNode) on @code(AViewport). }
    function ApplyToViewport(const ARoot: TComponent;
      const AViewport: TCastleViewport;
      const AObserverWorldPos: TVector3): TPostProcessSettings;

    function StackSummaryBadge: String;

    property AttachedViewport: TCastleViewport read FAttachedViewport;
    property ScreenEffectNode: TScreenEffectNode read FScreenEffectNode;
    property LastSettings: TPostProcessSettings read FLastSettings;
  published
    property StackEnabled: Boolean read FStackEnabled write FStackEnabled default true;
  end;

function PostProcessPresetToDisplayName(const APreset: TCastlePostProcessPreset): String;

implementation

uses
  Math, StrUtils,
  CastleUtils, CastleRenderOptions, CastleComponentSerialize, CastleUIControls;

function PostProcessPresetToDisplayName(
  const APreset: TCastlePostProcessPreset): String;
begin
  case APreset of
    pppNeutral:          Result := 'Neutral';
    pppWarmSunset:       Result := 'Warm Sunset';
    pppSciFiCold:        Result := 'Sci-Fi Cold';
    pppNoirHighContrast: Result := 'Noir High-Contrast';
    pppHorrorVignette:   Result := 'Horror Vignette';
    pppVintageSepia:     Result := 'Vintage Sepia';
  end;
end;

{ TPostProcessSettings ------------------------------------------------------- }

class function TPostProcessSettings.Neutral: TPostProcessSettings;
begin
  Result.ExposureEV := 0.0;
  Result.AcesTonemapMix := 0.0;
  Result.Contrast := 1.0;
  Result.Saturation := 1.0;
  Result.VignetteIntensity := 0.0;
  Result.ChromaticAberrationPx := 0.0;
  Result.TintRed := 1.0;
  Result.TintGreen := 1.0;
  Result.TintBlue := 1.0;
end;

class function TPostProcessSettings.Lerp(const AWeight: Single;
  const AFrom, ATo: TPostProcessSettings): TPostProcessSettings;
var
  W: Single;
begin
  W := Clamped(AWeight, 0.0, 1.0);
  Result.ExposureEV := CastleUtils.Lerp(W, AFrom.ExposureEV, ATo.ExposureEV);
  Result.AcesTonemapMix := CastleUtils.Lerp(W, AFrom.AcesTonemapMix, ATo.AcesTonemapMix);
  Result.Contrast := CastleUtils.Lerp(W, AFrom.Contrast, ATo.Contrast);
  Result.Saturation := CastleUtils.Lerp(W, AFrom.Saturation, ATo.Saturation);
  Result.VignetteIntensity := CastleUtils.Lerp(W, AFrom.VignetteIntensity, ATo.VignetteIntensity);
  Result.ChromaticAberrationPx := CastleUtils.Lerp(W, AFrom.ChromaticAberrationPx, ATo.ChromaticAberrationPx);
  Result.TintRed := CastleUtils.Lerp(W, AFrom.TintRed, ATo.TintRed);
  Result.TintGreen := CastleUtils.Lerp(W, AFrom.TintGreen, ATo.TintGreen);
  Result.TintBlue := CastleUtils.Lerp(W, AFrom.TintBlue, ATo.TintBlue);
end;

function TPostProcessSettings.IsEffectivelyNeutral: Boolean;
const
  Eps = 0.001;
begin
  Result :=
    (Abs(ExposureEV) < Eps) and
    (Abs(AcesTonemapMix) < Eps) and
    (Abs(Contrast - 1.0) < Eps) and
    (Abs(Saturation - 1.0) < Eps) and
    (Abs(VignetteIntensity) < Eps) and
    (Abs(ChromaticAberrationPx) < Eps) and
    (Abs(TintRed - 1.0) < Eps) and
    (Abs(TintGreen - 1.0) < Eps) and
    (Abs(TintBlue - 1.0) < Eps);
end;

{ TCastlePostProcessVolume --------------------------------------------------- }

constructor TCastlePostProcessVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVolumeLabel := '';
  FLookPreset := pppNeutral;
  FIsUnbound := true;
  FCoreRadius := DefaultCoreRadius;
  FBlendRadius := DefaultBlendRadius;
  FPriority := 0;
  FBlendWeight := DefaultBlendWeight;
  FVolumeEnabled := true;
  FShowVolumeInViewport := true;
  ApplyLookPreset(pppNeutral);
end;

function TCastlePostProcessVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'VolumeLabel', 'LookPreset', 'IsUnbound', 'CoreRadius', 'BlendRadius',
       'Priority', 'BlendWeight', 'VolumeEnabled', 'ShowVolumeInViewport',
       'ExposureEV', 'AcesTonemapMix', 'Contrast', 'Saturation',
       'VignetteIntensity', 'ChromaticAberrationPx',
       'TintRed', 'TintGreen', 'TintBlue'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastlePostProcessVolume.LocalBoundingBox: TBox3D;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
    Result.Include(Box3D(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5)));
end;

procedure TCastlePostProcessVolume.ApplyLookPreset(
  const APreset: TCastlePostProcessPreset);
begin
  FLookPreset := APreset;
  case APreset of
    pppNeutral:
      begin
        FExposureEV := 0.0;
        FAcesTonemapMix := 0.0;
        FContrast := 1.0;
        FSaturation := 1.0;
        FVignetteIntensity := 0.0;
        FChromaticAberrationPx := 0.0;
        FTintRed := 1.0;
        FTintGreen := 1.0;
        FTintBlue := 1.0;
      end;
    pppWarmSunset:
      begin
        FExposureEV := 0.35;
        FAcesTonemapMix := 0.75;
        FContrast := 1.12;
        FSaturation := 1.22;
        FVignetteIntensity := 0.25;
        FChromaticAberrationPx := 0.6;
        FTintRed := 1.16;
        FTintGreen := 0.98;
        FTintBlue := 0.82;
      end;
    pppSciFiCold:
      begin
        FExposureEV := 0.15;
        FAcesTonemapMix := 0.85;
        FContrast := 1.20;
        FSaturation := 0.90;
        FVignetteIntensity := 0.30;
        FChromaticAberrationPx := 1.8;
        FTintRed := 0.84;
        FTintGreen := 1.02;
        FTintBlue := 1.20;
      end;
    pppNoirHighContrast:
      begin
        FExposureEV := -0.10;
        FAcesTonemapMix := 1.00;
        FContrast := 1.55;
        FSaturation := 0.05;
        FVignetteIntensity := 0.55;
        FChromaticAberrationPx := 0.4;
        FTintRed := 1.00;
        FTintGreen := 1.00;
        FTintBlue := 1.04;
      end;
    pppHorrorVignette:
      begin
        FExposureEV := -0.65;
        FAcesTonemapMix := 0.90;
        FContrast := 1.35;
        FSaturation := 0.55;
        FVignetteIntensity := 0.85;
        FChromaticAberrationPx := 2.8;
        FTintRed := 0.92;
        FTintGreen := 1.04;
        FTintBlue := 0.88;
      end;
    pppVintageSepia:
      begin
        FExposureEV := 0.10;
        FAcesTonemapMix := 0.60;
        FContrast := 1.08;
        FSaturation := 0.38;
        FVignetteIntensity := 0.42;
        FChromaticAberrationPx := 0.8;
        FTintRed := 1.18;
        FTintGreen := 1.04;
        FTintBlue := 0.80;
      end;
  end;
end;

procedure TCastlePostProcessVolume.SetCoreRadius(const AValue: Single);
begin
  FCoreRadius := Max(0.0, AValue);
end;

procedure TCastlePostProcessVolume.SetBlendRadius(const AValue: Single);
begin
  FBlendRadius := Max(0.0, AValue);
end;

procedure TCastlePostProcessVolume.SetBlendWeight(const AValue: Single);
begin
  FBlendWeight := Clamped(AValue, 0.0, 1.0);
end;

procedure TCastlePostProcessVolume.SetExposureEV(const AValue: Single);
begin
  FExposureEV := Clamped(AValue, -5.0, 5.0);
end;

procedure TCastlePostProcessVolume.SetAcesTonemapMix(const AValue: Single);
begin
  FAcesTonemapMix := Clamped(AValue, 0.0, 1.0);
end;

procedure TCastlePostProcessVolume.SetContrast(const AValue: Single);
begin
  FContrast := Clamped(AValue, 0.1, 3.5);
end;

procedure TCastlePostProcessVolume.SetSaturation(const AValue: Single);
begin
  FSaturation := Clamped(AValue, 0.0, 3.5);
end;

procedure TCastlePostProcessVolume.SetVignetteIntensity(const AValue: Single);
begin
  FVignetteIntensity := Clamped(AValue, 0.0, 2.0);
end;

procedure TCastlePostProcessVolume.SetChromaticAberrationPx(const AValue: Single);
begin
  FChromaticAberrationPx := Clamped(AValue, 0.0, 24.0);
end;

procedure TCastlePostProcessVolume.SetTintRed(const AValue: Single);
begin
  FTintRed := Clamped(AValue, 0.0, 3.0);
end;

procedure TCastlePostProcessVolume.SetTintGreen(const AValue: Single);
begin
  FTintGreen := Clamped(AValue, 0.0, 3.0);
end;

procedure TCastlePostProcessVolume.SetTintBlue(const AValue: Single);
begin
  FTintBlue := Clamped(AValue, 0.0, 3.0);
end;

function TCastlePostProcessVolume.ToSettings: TPostProcessSettings;
begin
  Result.ExposureEV := FExposureEV;
  Result.AcesTonemapMix := FAcesTonemapMix;
  Result.Contrast := FContrast;
  Result.Saturation := FSaturation;
  Result.VignetteIntensity := FVignetteIntensity;
  Result.ChromaticAberrationPx := FChromaticAberrationPx;
  Result.TintRed := FTintRed;
  Result.TintGreen := FTintGreen;
  Result.TintBlue := FTintBlue;
end;

function TCastlePostProcessVolume.EvaluateObserverWeight(
  const AObserverWorldPos: TVector3): Single;
var
  Dist, OuterR, T: Single;
begin
  if (not FVolumeEnabled) or (not Exists) or (FBlendWeight <= 0.0001) then
    Exit(0.0);
  if FIsUnbound then
    Exit(FBlendWeight);

  Dist := PointsDistance(AObserverWorldPos, WorldTranslation);
  if Dist <= FCoreRadius then
    Exit(FBlendWeight);

  OuterR := FCoreRadius + FBlendRadius;
  if (FBlendRadius <= 0.0001) or (Dist >= OuterR) then
    Exit(0.0);

  T := Clamped((Dist - FCoreRadius) / FBlendRadius, 0.0, 1.0);
  Result := FBlendWeight * (1.0 - (T * T * (3.0 - 2.0 * T)));
end;

function TCastlePostProcessVolume.VolumeSummaryBadge: String;
begin
  if FIsUnbound then
    Result := Format('[PP:%s Prio=%d Global]',
      [PostProcessPresetToDisplayName(FLookPreset), FPriority])
  else
    Result := Format('[PP:%s Prio=%d %.0f+%.0fm]',
      [PostProcessPresetToDisplayName(FLookPreset), FPriority,
       FCoreRadius, FBlendRadius]);
end;

{ TCastlePostProcessStack ---------------------------------------------------- }

constructor TCastlePostProcessStack.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStackEnabled := true;
  FLastSettings := TPostProcessSettings.Neutral;
end;

destructor TCastlePostProcessStack.Destroy;
begin
  DetachFromViewport;
  NodeRelease(FScreenEffectNode);
  inherited Destroy;
end;

function TCastlePostProcessStack.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if PropertyName = 'StackEnabled' then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePostProcessStack.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAttachedViewport) then
    FAttachedViewport := nil;
end;

procedure TCastlePostProcessStack.DetachFromViewport;
begin
  if FAttachedViewport <> nil then
  begin
    FAttachedViewport.RemoveFreeNotification(Self);
    if FScreenEffectNode <> nil then
      FAttachedViewport.RemoveScreenEffect(FScreenEffectNode);
    FAttachedViewport := nil;
  end;
end;

class function TCastlePostProcessStack.BuildPostProcessFragmentGlsl: String;
begin
  Result :=
    'uniform float u_pp_exposure_mul;' + LineEnding +
    'uniform float u_pp_aces_mix;' + LineEnding +
    'uniform float u_pp_contrast;' + LineEnding +
    'uniform float u_pp_saturation;' + LineEnding +
    'uniform float u_pp_vignette;' + LineEnding +
    'uniform float u_pp_chromatic_px;' + LineEnding +
    'uniform vec3 u_pp_color_tint;' + LineEnding +
    LineEnding +
    'vec3 cge_aces_filmic(vec3 x)' + LineEnding +
    '{' + LineEnding +
    '  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);' + LineEnding +
    '}' + LineEnding +
    LineEnding +
    'void main(void)' + LineEnding +
    '{' + LineEnding +
    '  ivec2 pos = screen_position();' + LineEnding +
    '  vec2 res = max(vec2(float(screen_width), float(screen_height)), vec2(1.0));' + LineEnding +
    '  vec2 uv = (vec2(pos) + vec2(0.5)) / res;' + LineEnding +
    '  vec2 fromCenter = uv - vec2(0.5);' + LineEnding +
    '  vec4 baseSample = screen_get_color(pos);' + LineEnding +
    '  vec3 col = baseSample.rgb;' + LineEnding +
    '  if (u_pp_chromatic_px > 0.01) {' + LineEnding +
    '    ivec2 shift = ivec2(fromCenter * 2.0 * u_pp_chromatic_px);' + LineEnding +
    '    ivec2 maxCoord = ivec2(max(screen_width - 1, 0), max(screen_height - 1, 0));' + LineEnding +
    '    col.r = screen_get_color(clamp(pos + shift, ivec2(0), maxCoord)).r;' + LineEnding +
    '    col.b = screen_get_color(clamp(pos - shift, ivec2(0), maxCoord)).b;' + LineEnding +
    '  }' + LineEnding +
    '  col *= u_pp_exposure_mul;' + LineEnding +
    '  col *= u_pp_color_tint;' + LineEnding +
    '  float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));' + LineEnding +
    '  col = mix(vec3(luma), col, u_pp_saturation);' + LineEnding +
    '  col = max((col - vec3(0.5)) * u_pp_contrast + vec3(0.5), vec3(0.0));' + LineEnding +
    '  if (u_pp_aces_mix > 0.001) {' + LineEnding +
    '    col = mix(clamp(col, 0.0, 1.0), cge_aces_filmic(col), u_pp_aces_mix);' + LineEnding +
    '  }' + LineEnding +
    '  if (u_pp_vignette > 0.001) {' + LineEnding +
    '    float r2 = dot(fromCenter, fromCenter) * 2.4;' + LineEnding +
    '    float vig = clamp(1.0 - r2 * u_pp_vignette, 0.0, 1.0);' + LineEnding +
    '    col *= vig;' + LineEnding +
    '  }' + LineEnding +
    '  gl_FragColor = vec4(clamp(col, 0.0, 1.0), baseSample.a);' + LineEnding +
    '}';
end;

procedure TCastlePostProcessStack.EnsureScreenEffectBuilt;
begin
  if FScreenEffectNode <> nil then
    Exit;

  FScreenEffectNode := TScreenEffectNode.Create(ScreenEffectNodeName);
  FScreenEffectNode.WaitForRelease;

  FShaderNode := TComposedShaderNode.Create;
  FShaderNode.Language := slGLSL;

  FFdExposureMul := TSFFloat.Create(FShaderNode, true, 'u_pp_exposure_mul', 1.0);
  FShaderNode.AddCustomField(FFdExposureMul);
  FFdAcesMix := TSFFloat.Create(FShaderNode, true, 'u_pp_aces_mix', 0.0);
  FShaderNode.AddCustomField(FFdAcesMix);
  FFdContrast := TSFFloat.Create(FShaderNode, true, 'u_pp_contrast', 1.0);
  FShaderNode.AddCustomField(FFdContrast);
  FFdSaturation := TSFFloat.Create(FShaderNode, true, 'u_pp_saturation', 1.0);
  FShaderNode.AddCustomField(FFdSaturation);
  FFdVignette := TSFFloat.Create(FShaderNode, true, 'u_pp_vignette', 0.0);
  FShaderNode.AddCustomField(FFdVignette);
  FFdChromaticPx := TSFFloat.Create(FShaderNode, true, 'u_pp_chromatic_px', 0.0);
  FShaderNode.AddCustomField(FFdChromaticPx);
  FFdColorTint := TSFVec3f.Create(FShaderNode, true, 'u_pp_color_tint', Vector3(1.0, 1.0, 1.0));
  FShaderNode.AddCustomField(FFdColorTint);

  FFragPart := TShaderPartNode.Create;
  FFragPart.ShaderType := stFragment;
  FFragPart.Contents := BuildPostProcessFragmentGlsl;
  FShaderNode.SetParts([FFragPart]);
  FScreenEffectNode.SetShaders([FShaderNode]);
end;

class function TCastlePostProcessStack.EvaluateBlendedWorldSettings(
  const ARoot: TComponent; const AObserverWorldPos: TVector3;
  out OutActiveVolumeCount: Integer): TPostProcessSettings;
var
  Vols: array of TCastlePostProcessVolume;
  Visited: array of TComponent;

  function MarkSeen(const C: TComponent): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(Visited) do
      if Visited[K] = C then
        Exit(false);
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := C;
    Result := true;
  end;

  procedure CollectVolumes(const C: TComponent);
  var
    I, N: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) or (not MarkSeen(C)) then
      Exit;
    if C is TCastlePostProcessVolume then
    begin
      N := Length(Vols);
      SetLength(Vols, N + 1);
      Vols[N] := TCastlePostProcessVolume(C);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        CollectVolumes(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      if C is TCastleViewport then
      begin
        VP := TCastleViewport(C);
        if VP.Items <> nil then
          CollectVolumes(VP.Items);
      end;
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        CollectVolumes(UI.Controls[I]);
    end;
  end;

var
  I, J: Integer;
  Tmp: TCastlePostProcessVolume;
  W: Single;
begin
  Result := TPostProcessSettings.Neutral;
  OutActiveVolumeCount := 0;
  if ARoot = nil then
    Exit;

  SetLength(Vols, 0);
  SetLength(Visited, 0);
  CollectVolumes(ARoot);

  { Stable ascending insertion sort by Priority so higher Priority overrides lower }
  for I := 1 to High(Vols) do
  begin
    Tmp := Vols[I];
    J := I - 1;
    while (J >= 0) and (Vols[J].Priority > Tmp.Priority) do
    begin
      Vols[J + 1] := Vols[J];
      Dec(J);
    end;
    Vols[J + 1] := Tmp;
  end;

  for I := 0 to High(Vols) do
  begin
    W := Vols[I].EvaluateObserverWeight(AObserverWorldPos);
    if W > 0.0001 then
    begin
      Inc(OutActiveVolumeCount);
      Result := TPostProcessSettings.Lerp(W, Result, Vols[I].ToSettings);
    end;
  end;
end;

function TCastlePostProcessStack.ApplyToViewport(const ARoot: TComponent;
  const AViewport: TCastleViewport;
  const AObserverWorldPos: TVector3): TPostProcessSettings;
var
  ActiveCount: Integer;
begin
  if not FStackEnabled then
  begin
    FLastSettings := TPostProcessSettings.Neutral;
    if FScreenEffectNode <> nil then
      FScreenEffectNode.Enabled := false;
    Exit(FLastSettings);
  end;

  FLastSettings := EvaluateBlendedWorldSettings(ARoot, AObserverWorldPos, ActiveCount);
  Result := FLastSettings;

  if AViewport = nil then
    Exit;

  EnsureScreenEffectBuilt;
  if FAttachedViewport <> AViewport then
  begin
    DetachFromViewport;
    FAttachedViewport := AViewport;
    FAttachedViewport.FreeNotification(Self);
    FAttachedViewport.AddScreenEffect(FScreenEffectNode);
  end;

  FFdExposureMul.Send(Power(2.0, FLastSettings.ExposureEV));
  FFdAcesMix.Send(FLastSettings.AcesTonemapMix);
  FFdContrast.Send(FLastSettings.Contrast);
  FFdSaturation.Send(FLastSettings.Saturation);
  FFdVignette.Send(FLastSettings.VignetteIntensity);
  FFdChromaticPx.Send(FLastSettings.ChromaticAberrationPx);
  FFdColorTint.Send(Vector3(FLastSettings.TintRed, FLastSettings.TintGreen, FLastSettings.TintBlue));
  FScreenEffectNode.Enabled := not FLastSettings.IsEffectivelyNeutral;
end;

function TCastlePostProcessStack.StackSummaryBadge: String;
begin
  Result := Format('[PPStack:%s]', [IfThen(FStackEnabled, 'ON', 'OFF')]);
end;

initialization
  RegisterSerializableComponent(TCastlePostProcessVolume, ['Visual Effects', 'Post-Process Volume']);
  RegisterSerializableComponent(TCastlePostProcessStack, 'Post-Process Stack');
end.
