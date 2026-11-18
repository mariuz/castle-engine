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

{ Cinematic Camera Shake Envelope, Directional Weapon Recoil, Distance-Attenuated
  Blast Source & FOV Kickback Director (Phase 371 — UE 6.0+ UCameraShakeBase Parity). }
unit CastleCameraShake;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleClassUtils;

type
  { Built-in camera shake & recoil profiles. }
  TCameraShakePreset = (
    cspCustom,
    cspHeavyShotgunKickback,
    cspArtilleryConcussionBlast,
    cspHandheldSprintBreathing
  );

  { Active additive camera shake / recoil envelope instance. }
  TCameraShakeLayer = record
    LayerTag: String;
    TraumaIntensity: Single;
    DurationSec: Single;
    ElapsedSec: Single;
    FrequencyHz: Single;
    DirectionalKickPitchDeg: Single;
    DirectionalKickYawDeg: Single;
    FovKickDegrees: Single;
    PhaseSeed: Single;
  end;

  { Evaluated composite camera offset for the current frame. }
  TCameraShakeFrameOffset = record
    PositionOffsetLocal: TVector3;
    PitchYawRollDeg: TVector3;
    FovDeltaDegrees: Single;
    CombinedTrauma: Single;
    ActiveLayerCount: Integer;
  end;

  { Multi-layer additive camera shake director with Trauma^2 Perlin harmonics,
    directional weapon muzzle recoil, FOV punch, distance falloff, and
    accessibility GlobalShakeScale gating. }
  TCastleCameraShakeDirector = class(TCastleTransform)
  private
    FPreset: TCameraShakePreset;
    FGlobalShakeScale: Single;
    FMaxPitchRollCapDeg: Single;
    FInnerFullBlastRadiusMeters: Single;
    FOuterZeroBlastRadiusMeters: Single;
    FLayers: array of TCameraShakeLayer;
    FLastFrame: TCameraShakeFrameOffset;
    FSeedCounter: Integer;
    procedure SetPreset(const AValue: TCameraShakePreset);
    procedure SetGlobalShakeScale(const AValue: Single);
    procedure SetMaxPitchRollCapDeg(const AValue: Single);
    procedure SetInnerFullBlastRadiusMeters(const AValue: Single);
    procedure SetOuterZeroBlastRadiusMeters(const AValue: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetDefaults(const APreset: TCameraShakePreset);
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearAllShakes;
    procedure TriggerPresetShake(const APreset: TCameraShakePreset;
      const AScale: Single = 1.0);
    procedure TriggerDirectionalRecoil(
      const APitchUpDeg, AYawSideDeg, AFovPunchDeg, ADurationSec: Single);
    function TriggerWorldExplosionShake(
      const AExplosionWorldPos, AListenerCameraWorldPos: TVector3;
      const APeakTrauma: Single = 1.0): Single;
    function StepCameraShakes(const Dt: Single): TCameraShakeFrameOffset;
    function ActiveLayerCount: Integer;
    function ShakeSummaryBadge: String;
    property LastFrame: TCameraShakeFrameOffset read FLastFrame;
  published
    property Preset: TCameraShakePreset read FPreset write SetPreset default cspHeavyShotgunKickback;
    property GlobalShakeScale: Single read FGlobalShakeScale write SetGlobalShakeScale {$ifdef FPC}default 1.0{$endif};
    property MaxPitchRollCapDeg: Single read FMaxPitchRollCapDeg write SetMaxPitchRollCapDeg {$ifdef FPC}default 12.0{$endif};
    property InnerFullBlastRadiusMeters: Single read FInnerFullBlastRadiusMeters write SetInnerFullBlastRadiusMeters {$ifdef FPC}default 4.0{$endif};
    property OuterZeroBlastRadiusMeters: Single read FOuterZeroBlastRadiusMeters write SetOuterZeroBlastRadiusMeters {$ifdef FPC}default 28.0{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function CameraShakePresetToString(const APreset: TCameraShakePreset): String;

implementation

uses fpjson, jsonparser, CastleComponentSerialize;

function CameraShakePresetToString(const APreset: TCameraShakePreset): String;
begin
  case APreset of
    cspCustom: Result := 'Custom Shake & Recoil Profile';
    cspHeavyShotgunKickback: Result := 'Heavy Shotgun Recoil & +5.5 deg FOV Kick';
    cspArtilleryConcussionBlast: Result := 'Artillery Concussive Trauma Shockwave';
    cspHandheldSprintBreathing: Result := 'Low-Frequency Handheld Sprint Sway';
  end;
end;

function SmoothHarmonicNoise(const T, Seed: Single): Single;
begin
  Result := 0.62 * Sin(T + Seed) + 0.38 * Sin(T * 2.17 + Seed * 1.73 + 1.1);
end;

{ TCastleCameraShakeDirector -------------------------------------------------- }

constructor TCastleCameraShakeDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGlobalShakeScale := 1.0;
  FSeedCounter := 1;
  FillChar(FLastFrame, SizeOf(FLastFrame), 0);
  ApplyPresetDefaults(cspHeavyShotgunKickback);
end;

procedure TCastleCameraShakeDirector.ApplyPresetDefaults(const APreset: TCameraShakePreset);
begin
  FPreset := APreset;
  case APreset of
    cspHeavyShotgunKickback, cspCustom:
      begin
        FMaxPitchRollCapDeg := 12.0;
        FInnerFullBlastRadiusMeters := 4.0;
        FOuterZeroBlastRadiusMeters := 28.0;
      end;
    cspArtilleryConcussionBlast:
      begin
        FMaxPitchRollCapDeg := 16.0;
        FInnerFullBlastRadiusMeters := 6.0;
        FOuterZeroBlastRadiusMeters := 40.0;
      end;
    cspHandheldSprintBreathing:
      begin
        FMaxPitchRollCapDeg := 6.0;
        FInnerFullBlastRadiusMeters := 3.0;
        FOuterZeroBlastRadiusMeters := 20.0;
      end;
  end;
end;

procedure TCastleCameraShakeDirector.SetPreset(const AValue: TCameraShakePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> cspCustom then
    ApplyPresetDefaults(AValue);
end;

procedure TCastleCameraShakeDirector.SetGlobalShakeScale(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 2.5);
  if SameValue(FGlobalShakeScale, V, 1e-4) then Exit;
  FGlobalShakeScale := V;
end;

procedure TCastleCameraShakeDirector.SetMaxPitchRollCapDeg(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 1.0, 45.0);
  if SameValue(FMaxPitchRollCapDeg, V, 1e-4) then Exit;
  FMaxPitchRollCapDeg := V;
  FPreset := cspCustom;
end;

procedure TCastleCameraShakeDirector.SetInnerFullBlastRadiusMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.5, 100.0);
  if SameValue(FInnerFullBlastRadiusMeters, V, 1e-4) then Exit;
  FInnerFullBlastRadiusMeters := V;
  if FOuterZeroBlastRadiusMeters <= FInnerFullBlastRadiusMeters + 0.5 then
    FOuterZeroBlastRadiusMeters := FInnerFullBlastRadiusMeters + 1.0;
  FPreset := cspCustom;
end;

procedure TCastleCameraShakeDirector.SetOuterZeroBlastRadiusMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, FInnerFullBlastRadiusMeters + 0.5, 500.0);
  if SameValue(FOuterZeroBlastRadiusMeters, V, 1e-4) then Exit;
  FOuterZeroBlastRadiusMeters := V;
  FPreset := cspCustom;
end;

procedure TCastleCameraShakeDirector.ClearAllShakes;
begin
  SetLength(FLayers, 0);
  FillChar(FLastFrame, SizeOf(FLastFrame), 0);
end;

procedure TCastleCameraShakeDirector.TriggerPresetShake(
  const APreset: TCameraShakePreset; const AScale: Single);
var
  EffScale: Single;
  N: Integer;
begin
  EffScale := Max(0.05, AScale);
  N := Length(FLayers);
  SetLength(FLayers, N + 1);
  Inc(FSeedCounter);
  FLayers[N].ElapsedSec := 0.0;
  FLayers[N].PhaseSeed := FSeedCounter * 1.618;
  case APreset of
    cspHeavyShotgunKickback, cspCustom:
      begin
        FLayers[N].LayerTag := 'ShotgunKick';
        FLayers[N].TraumaIntensity := 0.55 * EffScale;
        FLayers[N].DurationSec := 0.36;
        FLayers[N].FrequencyHz := 18.0;
        FLayers[N].DirectionalKickPitchDeg := 5.8 * EffScale;
        FLayers[N].DirectionalKickYawDeg := -1.2 * EffScale;
        FLayers[N].FovKickDegrees := 5.5 * EffScale;
      end;
    cspArtilleryConcussionBlast:
      begin
        FLayers[N].LayerTag := 'ArtilleryBlast';
        FLayers[N].TraumaIntensity := 0.95 * EffScale;
        FLayers[N].DurationSec := 1.15;
        FLayers[N].FrequencyHz := 22.0;
        FLayers[N].DirectionalKickPitchDeg := 2.5 * EffScale;
        FLayers[N].DirectionalKickYawDeg := 0.0;
        FLayers[N].FovKickDegrees := 3.5 * EffScale;
      end;
    cspHandheldSprintBreathing:
      begin
        FLayers[N].LayerTag := 'SprintSway';
        FLayers[N].TraumaIntensity := 0.30 * EffScale;
        FLayers[N].DurationSec := 1.80;
        FLayers[N].FrequencyHz := 3.4;
        FLayers[N].DirectionalKickPitchDeg := 0.0;
        FLayers[N].DirectionalKickYawDeg := 0.0;
        FLayers[N].FovKickDegrees := 1.2 * EffScale;
      end;
  end;
end;

procedure TCastleCameraShakeDirector.TriggerDirectionalRecoil(
  const APitchUpDeg, AYawSideDeg, AFovPunchDeg, ADurationSec: Single);
var
  N: Integer;
begin
  N := Length(FLayers);
  SetLength(FLayers, N + 1);
  Inc(FSeedCounter);
  FLayers[N].LayerTag := 'DirectionalRecoil';
  FLayers[N].TraumaIntensity := 0.25;
  FLayers[N].DurationSec := Max(0.05, ADurationSec);
  FLayers[N].ElapsedSec := 0.0;
  FLayers[N].FrequencyHz := 16.0;
  FLayers[N].DirectionalKickPitchDeg := APitchUpDeg;
  FLayers[N].DirectionalKickYawDeg := AYawSideDeg;
  FLayers[N].FovKickDegrees := AFovPunchDeg;
  FLayers[N].PhaseSeed := FSeedCounter * 2.414;
end;

function TCastleCameraShakeDirector.TriggerWorldExplosionShake(
  const AExplosionWorldPos, AListenerCameraWorldPos: TVector3;
  const APeakTrauma: Single): Single;
var
  Dist, Span, NormU, SmoothFalloff: Single;
  N: Integer;
begin
  Dist := (AExplosionWorldPos - AListenerCameraWorldPos).Length;
  if Dist >= FOuterZeroBlastRadiusMeters then
    Exit(0.0);

  if Dist <= FInnerFullBlastRadiusMeters then
    SmoothFalloff := 1.0
  else
  begin
    Span := Max(0.5, FOuterZeroBlastRadiusMeters - FInnerFullBlastRadiusMeters);
    NormU := EnsureRange((Dist - FInnerFullBlastRadiusMeters) / Span, 0.0, 1.0);
    { Hermite C1 smoothstep attenuation }
    SmoothFalloff := 1.0 - (NormU * NormU * (3.0 - 2.0 * NormU));
  end;

  Result := Max(0.0, APeakTrauma) * SmoothFalloff;
  if Result <= 0.005 then
    Exit(0.0);

  N := Length(FLayers);
  SetLength(FLayers, N + 1);
  Inc(FSeedCounter);
  FLayers[N].LayerTag := 'WorldExplosion';
  FLayers[N].TraumaIntensity := Result;
  FLayers[N].DurationSec := 0.95;
  FLayers[N].ElapsedSec := 0.0;
  FLayers[N].FrequencyHz := 20.0;
  FLayers[N].DirectionalKickPitchDeg := 2.2 * Result;
  FLayers[N].DirectionalKickYawDeg := 0.0;
  FLayers[N].FovKickDegrees := 4.0 * Result;
  FLayers[N].PhaseSeed := FSeedCounter * 1.732;
end;

function TCastleCameraShakeDirector.StepCameraShakes(
  const Dt: Single): TCameraShakeFrameOffset;
var
  I, WriteIdx: Integer;
  NormT, DecayEnv, TraumaSq, Omega: Single;
  PosSum, RotSum: TVector3;
  FovSum, TraumaAccum: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  PosSum := TVector3.Zero;
  RotSum := TVector3.Zero;
  FovSum := 0.0;
  TraumaAccum := 0.0;

  WriteIdx := 0;
  for I := 0 to High(FLayers) do
  begin
    if Dt > 0.0 then
      FLayers[I].ElapsedSec := FLayers[I].ElapsedSec + Dt;
    if FLayers[I].ElapsedSec >= FLayers[I].DurationSec then
      Continue;

    NormT := EnsureRange(FLayers[I].ElapsedSec / Max(0.02, FLayers[I].DurationSec), 0.0, 1.0);
    DecayEnv := Sqr(1.0 - NormT);
    TraumaAccum := TraumaAccum + FLayers[I].TraumaIntensity * (1.0 - NormT);
    TraumaSq := Sqr(FLayers[I].TraumaIntensity * (1.0 - NormT));
    Omega := FLayers[I].ElapsedSec * FLayers[I].FrequencyHz * 2.0 * Pi;

    PosSum := PosSum + Vector3(
      SmoothHarmonicNoise(Omega, FLayers[I].PhaseSeed) * 0.14 * TraumaSq,
      SmoothHarmonicNoise(Omega * 1.13, FLayers[I].PhaseSeed + 3.1) * 0.14 * TraumaSq,
      -0.08 * DecayEnv * FLayers[I].TraumaIntensity);

    RotSum := RotSum + Vector3(
      FLayers[I].DirectionalKickPitchDeg * DecayEnv +
        SmoothHarmonicNoise(Omega, FLayers[I].PhaseSeed + 5.7) * 6.5 * TraumaSq,
      FLayers[I].DirectionalKickYawDeg * DecayEnv +
        SmoothHarmonicNoise(Omega * 0.93, FLayers[I].PhaseSeed + 8.3) * 5.0 * TraumaSq,
      SmoothHarmonicNoise(Omega * 1.27, FLayers[I].PhaseSeed + 11.9) * 4.5 * TraumaSq);

    FovSum := FovSum + FLayers[I].FovKickDegrees * DecayEnv;

    FLayers[WriteIdx] := FLayers[I];
    Inc(WriteIdx);
  end;
  SetLength(FLayers, WriteIdx);

  Result.ActiveLayerCount := WriteIdx;
  Result.CombinedTrauma := EnsureRange(TraumaAccum * FGlobalShakeScale, 0.0, 2.0);
  if FGlobalShakeScale <= 1e-5 then
  begin
    FLastFrame := Result;
    Exit;
  end;

  PosSum := PosSum * FGlobalShakeScale;
  RotSum := RotSum * FGlobalShakeScale;
  Result.PositionOffsetLocal := PosSum;
  Result.PitchYawRollDeg := Vector3(
    EnsureRange(RotSum.X, -FMaxPitchRollCapDeg, FMaxPitchRollCapDeg),
    EnsureRange(RotSum.Y, -FMaxPitchRollCapDeg, FMaxPitchRollCapDeg),
    EnsureRange(RotSum.Z, -FMaxPitchRollCapDeg, FMaxPitchRollCapDeg));
  Result.FovDeltaDegrees := EnsureRange(FovSum * FGlobalShakeScale, -18.0, 18.0);
  FLastFrame := Result;
end;

function TCastleCameraShakeDirector.ActiveLayerCount: Integer;
begin
  Result := Length(FLayers);
end;

function TCastleCameraShakeDirector.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('scale', FGlobalShakeScale);
    RootObj.Add('maxDeg', FMaxPitchRollCapDeg);
    RootObj.Add('innerR', FInnerFullBlastRadiusMeters);
    RootObj.Add('outerR', FOuterZeroBlastRadiusMeters);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleCameraShakeDirector.SetConfigJson(const AValue: String);
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
      FGlobalShakeScale := EnsureRange(RootObj.Get('scale', FGlobalShakeScale), 0.0, 2.5);
      FMaxPitchRollCapDeg := EnsureRange(RootObj.Get('maxDeg', FMaxPitchRollCapDeg), 1.0, 45.0);
      FInnerFullBlastRadiusMeters := EnsureRange(RootObj.Get('innerR', FInnerFullBlastRadiusMeters), 0.5, 100.0);
      FOuterZeroBlastRadiusMeters := EnsureRange(RootObj.Get('outerR', FOuterZeroBlastRadiusMeters),
        FInnerFullBlastRadiusMeters + 0.5, 500.0);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TCameraShakePreset))) and
         (PresetOrd <= Ord(High(TCameraShakePreset))) then
        FPreset := TCameraShakePreset(PresetOrd);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleCameraShakeDirector.ShakeSummaryBadge: String;
begin
  Result := Format('[CamShake:%d layers Scale=%.0f%% FOV=%+.1fd]', [
    Length(FLayers),
    FGlobalShakeScale * 100.0,
    FLastFrame.FovDeltaDegrees]);
end;

initialization
  RegisterSerializableComponent(TCastleCameraShakeDirector, ['Camera & Cinematics', 'Camera Shake, Recoil & FOV Kick']);
end.
