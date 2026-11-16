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

{ MetaSound-Style Procedural PCM Audio Synthesizer (Oscillator, White Noise,
  ADSR Envelope, 2-Pole Resonant Low-Pass Filter & RIFF/WAVE Export),
  WorldRay Surface-Tagged Footstep Switcher & Quartz Beat/Bar-Quantized
  Adaptive Music Stem Director
  (@link(TCastleMetaSoundSynth), @link(TCastleFootstepSurfaceBehavior),
  @link(TCastleMusicStemDirector), @link(EvaluateAdsrEnvelope))
  (Phase 322 — UE 6.0+ MetaSounds & Quartz Interactive Music Parity). }
unit CastleMetaSound;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleBehaviors;

type
  TSinglePcmArray = array of Single;

  { Procedural oscillator waveform shape. }
  TMetaWaveShape = (
    mwsSine,
    mwsSawtooth,
    mwsSquare,
    mwsTriangle,
    mwsWhiteNoise
  );

  { Built-in procedural SFX synthesis patches. }
  TMetaSoundPreset = (
    mspCustom,
    mspLaserZapDownSweep,
    mspUiCrystalChime,
    mspFootstepStoneCrunch,
    mspExplosionSubBoom,
    mspSwordMetalClang
  );

  { Physical ground surface categories for adaptive footstep audio. }
  TSurfaceMaterialKind = (
    smkStone,
    smkWood,
    smkGrass,
    smkWater,
    smkMetal
  );

  { Musical grid quantization boundary matching UE Quartz. }
  TMusicQuantizeBoundary = (
    mqbImmediate,
    mqbNextBeat,
    mqbNextBar
  );

  { Procedural PCM audio synthesizer generating zero-dependency 16-bit mono
    RIFF/WAVE streams with exponential frequency sweeps, noise mixing, ADSR
    amplitude envelopes, and 2-pole resonant low-pass filtering. }
  TCastleMetaSoundSynth = class(TCastleComponent)
  public
    const
      DefaultSampleRateHz = 22050;
      DefaultDurationSec = 0.35;
      DefaultStartFreqHz = 660.0;
      DefaultEndFreqHz = 220.0;
      DefaultAttackSec = 0.01;
      DefaultDecaySec = 0.08;
      DefaultSustainLevel = 0.45;
      DefaultReleaseSec = 0.12;
      DefaultFilterCutoffHz = 6500.0;
      DefaultFilterResonanceQ = 0.707;
      DefaultMasterGain = 0.85;
  strict private
    FPreset: TMetaSoundPreset;
    FWaveShape: TMetaWaveShape;
    FSampleRateHz: Integer;
    FDurationSec: Single;
    FStartFreqHz: Single;
    FEndFreqHz: Single;
    FNoiseMix: Single;
    FAttackSec: Single;
    FDecaySec: Single;
    FSustainLevel: Single;
    FReleaseSec: Single;
    FFilterCutoffHz: Single;
    FFilterResonanceQ: Single;
    FMasterGain: Single;
    FSeed: Cardinal;

    FLastPeakAmplitude: Single;
    FLastRmsAmplitude: Single;

    procedure SetPreset(const Value: TMetaSoundPreset);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TMetaSoundPreset): String; static;

    procedure ApplyPreset(const APreset: TMetaSoundPreset);
    procedure SynthesizePcmSamples(out OutSamples: TSinglePcmArray);
    function WriteRiffWavToStream(const AStream: TStream): Int64;

    function SynthSummaryBadge: String;

    property LastPeakAmplitude: Single read FLastPeakAmplitude;
    property LastRmsAmplitude: Single read FLastRmsAmplitude;
  published
    property Preset: TMetaSoundPreset read FPreset write SetPreset default mspLaserZapDownSweep;
    property WaveShape: TMetaWaveShape read FWaveShape write FWaveShape default mwsSawtooth;
    property SampleRateHz: Integer read FSampleRateHz write FSampleRateHz default DefaultSampleRateHz;
    property DurationSec: Single read FDurationSec write FDurationSec {$ifdef FPC}default DefaultDurationSec{$endif};
    property StartFreqHz: Single read FStartFreqHz write FStartFreqHz {$ifdef FPC}default DefaultStartFreqHz{$endif};
    property EndFreqHz: Single read FEndFreqHz write FEndFreqHz {$ifdef FPC}default DefaultEndFreqHz{$endif};
    property NoiseMix: Single read FNoiseMix write FNoiseMix {$ifdef FPC}default 0.10{$endif};
    property AttackSec: Single read FAttackSec write FAttackSec {$ifdef FPC}default DefaultAttackSec{$endif};
    property DecaySec: Single read FDecaySec write FDecaySec {$ifdef FPC}default DefaultDecaySec{$endif};
    property SustainLevel: Single read FSustainLevel write FSustainLevel {$ifdef FPC}default DefaultSustainLevel{$endif};
    property ReleaseSec: Single read FReleaseSec write FReleaseSec {$ifdef FPC}default DefaultReleaseSec{$endif};
    property FilterCutoffHz: Single read FFilterCutoffHz write FFilterCutoffHz {$ifdef FPC}default DefaultFilterCutoffHz{$endif};
    property FilterResonanceQ: Single read FFilterResonanceQ write FFilterResonanceQ {$ifdef FPC}default DefaultFilterResonanceQ{$endif};
    property MasterGain: Single read FMasterGain write FMasterGain {$ifdef FPC}default DefaultMasterGain{$endif};
    property Seed: Cardinal read FSeed write FSeed default 2026;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Downward-raycasting physical surface detector & procedural footstep cue
    switcher for characters and creatures. }
  TCastleFootstepSurfaceBehavior = class(TCastleBehavior)
  public
    const
      DefaultStrideMeters = 1.65;
      DefaultProbeHeight = 1.20;
      DefaultPitchJitterPct = 8.0;
  strict private
    FStrideMeters: Single;
    FProbeHeight: Single;
    FPitchJitterPct: Single;
    FDistanceAccumMeters: Single;
    FLastSurface: TSurfaceMaterialKind;
    FTotalFootstepsTriggered: Integer;
    FLastStepFreqHz: Single;
    FLastStepCutoffHz: Single;
    FRngState: Cardinal;

    function NextRandomSigned: Single;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function SurfaceDisplayName(const ASurf: TSurfaceMaterialKind): String; static;
    class function ClassifyTransformSurface(const AHitTransform: TCastleTransform): TSurfaceMaterialKind; static;

    function DetectSurfaceUnderFoot: TSurfaceMaterialKind;
    procedure TriggerFootstepNow(out OutSurface: TSurfaceMaterialKind;
      out OutStepFreqHz, OutStepCutoffHz: Single);
    function AccumulateTravelDistance(const DeltaDistMeters: Single): Boolean;

    function FootstepSummaryBadge: String;

    property LastSurface: TSurfaceMaterialKind read FLastSurface;
    property TotalFootstepsTriggered: Integer read FTotalFootstepsTriggered;
    property LastStepFreqHz: Single read FLastStepFreqHz;
    property LastStepCutoffHz: Single read FLastStepCutoffHz;
  published
    property StrideMeters: Single read FStrideMeters write FStrideMeters {$ifdef FPC}default DefaultStrideMeters{$endif};
    property ProbeHeight: Single read FProbeHeight write FProbeHeight {$ifdef FPC}default DefaultProbeHeight{$endif};
    property PitchJitterPct: Single read FPitchJitterPct write FPitchJitterPct {$ifdef FPC}default DefaultPitchJitterPct{$endif};
  end;

  { Quartz-style BPM bar/beat-quantized 4-stem adaptive music director
    (0 = Explore, 1 = Tension, 2 = Combat, 3 = Boss). }
  TCastleMusicStemDirector = class(TCastleComponent)
  public
    const
      DefaultTempoBpm = 120.0;
      DefaultBeatsPerBar = 4;
      DefaultCrossfadeSec = 0.50;
  strict private
    FTempoBpm: Single;
    FBeatsPerBar: Integer;
    FQuantizeBoundary: TMusicQuantizeBoundary;
    FCrossfadeSec: Single;

    FClockSec: Single;
    FActiveStateIndex: Integer;
    FPendingStateIndex: Integer;
    FStemWeights: array [0..3] of Single;

    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function StemStateName(const AIndex: Integer): String; static;

    procedure ResetClock;
    procedure RequestMusicState(const AStateIndex: Integer);
    procedure StepMusicClock(const Dt: Single);

    function BeatDurationSec: Single;
    function BarDurationSec: Single;
    function CurrentBeatNumber: Integer; // 1-based total beat
    function CurrentBarNumber: Integer;  // 1-based bar number
    function CurrentBeatInBar: Integer;  // 1..BeatsPerBar
    function GetStemWeight(const AStemIndex: Integer): Single;
    function MusicSummaryBadge: String;

    property ClockSec: Single read FClockSec;
    property ActiveStateIndex: Integer read FActiveStateIndex;
    property PendingStateIndex: Integer read FPendingStateIndex;
  published
    property TempoBpm: Single read FTempoBpm write FTempoBpm {$ifdef FPC}default DefaultTempoBpm{$endif};
    property BeatsPerBar: Integer read FBeatsPerBar write FBeatsPerBar default DefaultBeatsPerBar;
    property QuantizeBoundary: TMusicQuantizeBoundary read FQuantizeBoundary write FQuantizeBoundary default mqbNextBar;
    property CrossfadeSec: Single read FCrossfadeSec write FCrossfadeSec {$ifdef FPC}default DefaultCrossfadeSec{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Analytical ADSR amplitude envelope in [0..1] over total note duration @code(TotalDurSec). }
function EvaluateAdsrEnvelope(const TimeSec, TotalDurSec, AttackSec, DecaySec,
  SustainLevel, ReleaseSec: Single): Single;

implementation

uses
  Math, StrUtils, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize, CastleWaterSystem;

function EvaluateAdsrEnvelope(const TimeSec, TotalDurSec, AttackSec, DecaySec,
  SustainLevel, ReleaseSec: Single): Single;
var
  SafeDur, SafeA, SafeD, SafeS, SafeR, RelStart, PreRelVal: Single;
begin
  SafeDur := Max(0.01, TotalDurSec);
  if (TimeSec < 0.0) or (TimeSec >= SafeDur) then
    Exit(0.0);

  SafeA := Max(0.0, AttackSec);
  SafeD := Max(0.0, DecaySec);
  SafeS := Clamped(SustainLevel, 0.0, 1.0);
  SafeR := Clamped(ReleaseSec, 0.0, SafeDur);
  RelStart := Max(0.0, SafeDur - SafeR);

  if (SafeA > 1e-5) and (TimeSec < SafeA) then
    PreRelVal := TimeSec / SafeA
  else if (SafeD > 1e-5) and (TimeSec < SafeA + SafeD) then
    PreRelVal := Lerp((TimeSec - SafeA) / SafeD, 1.0, SafeS)
  else
    PreRelVal := SafeS;

  if (SafeR > 1e-5) and (TimeSec >= RelStart) then
    Result := PreRelVal * Clamped(1.0 - (TimeSec - RelStart) / SafeR, 0.0, 1.0)
  else
    Result := PreRelVal;
  Result := Clamped(Result, 0.0, 1.0);
end;

{ TCastleMetaSoundSynth ------------------------------------------------------ }

constructor TCastleMetaSoundSynth.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSampleRateHz := DefaultSampleRateHz;
  FSeed := 2026;
  ApplyPreset(mspLaserZapDownSweep);
end;

class function TCastleMetaSoundSynth.PresetDisplayName(const APreset: TMetaSoundPreset): String;
begin
  case APreset of
    mspCustom:              Result := 'Custom Patch';
    mspLaserZapDownSweep:   Result := 'Sci-Fi Laser Zap';
    mspUiCrystalChime:      Result := 'UI Crystal Chime';
    mspFootstepStoneCrunch: Result := 'Stone Footstep Crunch';
    mspExplosionSubBoom:    Result := 'Explosion Sub-Boom';
    mspSwordMetalClang:     Result := 'Sword Metal Clang';
  end;
end;

procedure TCastleMetaSoundSynth.ApplyPreset(const APreset: TMetaSoundPreset);
begin
  FPreset := APreset;
  case APreset of
    mspLaserZapDownSweep:
      begin
        FWaveShape := mwsSawtooth;
        FDurationSec := 0.28;
        FStartFreqHz := 980.0;
        FEndFreqHz := 140.0;
        FNoiseMix := 0.06;
        FAttackSec := 0.005;
        FDecaySec := 0.08;
        FSustainLevel := 0.55;
        FReleaseSec := 0.10;
        FFilterCutoffHz := 5200.0;
        FFilterResonanceQ := 1.4;
        FMasterGain := 0.85;
      end;
    mspUiCrystalChime:
      begin
        FWaveShape := mwsSine;
        FDurationSec := 0.42;
        FStartFreqHz := 880.0;
        FEndFreqHz := 1320.0;
        FNoiseMix := 0.0;
        FAttackSec := 0.008;
        FDecaySec := 0.14;
        FSustainLevel := 0.35;
        FReleaseSec := 0.20;
        FFilterCutoffHz := 9000.0;
        FFilterResonanceQ := 0.707;
        FMasterGain := 0.80;
      end;
    mspFootstepStoneCrunch:
      begin
        FWaveShape := mwsTriangle;
        FDurationSec := 0.14;
        FStartFreqHz := 165.0;
        FEndFreqHz := 75.0;
        FNoiseMix := 0.65;
        FAttackSec := 0.003;
        FDecaySec := 0.04;
        FSustainLevel := 0.20;
        FReleaseSec := 0.07;
        FFilterCutoffHz := 1850.0;
        FFilterResonanceQ := 0.9;
        FMasterGain := 0.85;
      end;
    mspExplosionSubBoom:
      begin
        FWaveShape := mwsSawtooth;
        FDurationSec := 0.65;
        FStartFreqHz := 120.0;
        FEndFreqHz := 34.0;
        FNoiseMix := 0.52;
        FAttackSec := 0.006;
        FDecaySec := 0.18;
        FSustainLevel := 0.40;
        FReleaseSec := 0.35;
        FFilterCutoffHz := 480.0;
        FFilterResonanceQ := 1.2;
        FMasterGain := 0.92;
      end;
    mspSwordMetalClang:
      begin
        FWaveShape := mwsSquare;
        FDurationSec := 0.38;
        FStartFreqHz := 1480.0;
        FEndFreqHz := 1420.0;
        FNoiseMix := 0.22;
        FAttackSec := 0.002;
        FDecaySec := 0.12;
        FSustainLevel := 0.25;
        FReleaseSec := 0.22;
        FFilterCutoffHz := 7400.0;
        FFilterResonanceQ := 2.2;
        FMasterGain := 0.82;
      end;
    mspCustom: ;
  end;
end;

procedure TCastleMetaSoundSynth.SynthesizePcmSamples(out OutSamples: TSinglePcmArray);
var
  Rate, NumSamples, I: Integer;
  Dur, Phase, Freq, TNorm, TimeSec, OscVal, NoiseVal, RawSig, Env: Single;
  Rng: Cardinal;
  { RBJ Audio EQ Cookbook 2-pole Biquad Low-Pass coefficients & state }
  W0, CosW0, SinW0, AlphaQ, B0, B1, B2, A0Inv, A1, A2: Single;
  X1, X2, Y1, Y2, FilteredSig, SumSq, Peak: Single;
begin
  Rate := Clamped(FSampleRateHz, 4000, 96000);
  Dur := Clamped(FDurationSec, 0.01, 10.0);
  NumSamples := Max(16, Round(Rate * Dur));
  OutSamples := nil;
  SetLength(OutSamples, NumSamples);

  { Precompute RBJ Biquad Low-Pass coefficients }
  W0 := 2.0 * Pi * Clamped(FFilterCutoffHz, 40.0, Rate * 0.45) / Rate;
  CosW0 := Cos(W0);
  SinW0 := Sin(W0);
  AlphaQ := SinW0 / (2.0 * Clamped(FFilterResonanceQ, 0.25, 8.0));
  A0Inv := 1.0 / (1.0 + AlphaQ);
  B0 := ((1.0 - CosW0) * 0.5) * A0Inv;
  B1 := (1.0 - CosW0) * A0Inv;
  B2 := B0;
  A1 := (-2.0 * CosW0) * A0Inv;
  A2 := (1.0 - AlphaQ) * A0Inv;

  X1 := 0.0; X2 := 0.0;
  Y1 := 0.0; Y2 := 0.0;
  Phase := 0.0;
  Rng := Max(Cardinal(1), FSeed);
  SumSq := 0.0;
  Peak := 0.0;

  for I := 0 to NumSamples - 1 do
  begin
    TimeSec := I / Rate;
    TNorm := I / Max(1, NumSamples - 1);
    { Exponential frequency glide from StartFreqHz to EndFreqHz }
    Freq := Max(10.0, FStartFreqHz) *
      Power(Max(10.0, FEndFreqHz) / Max(10.0, FStartFreqHz), TNorm);

    Phase := Phase + Freq / Rate;
    Phase := Phase - Floor(Phase);

    { Xorshift32 white noise }
    Rng := Rng xor (Rng shl 13);
    Rng := Rng xor (Rng shr 17);
    Rng := Rng xor (Rng shl 5);
    NoiseVal := ((Rng and $00FFFFFF) / 8388608.0) - 1.0;

    case FWaveShape of
      mwsSine:       OscVal := Sin(2.0 * Pi * Phase);
      mwsSawtooth:   OscVal := 2.0 * Phase - 1.0;
      mwsSquare:     if Phase < 0.5 then OscVal := 1.0 else OscVal := -1.0;
      mwsTriangle:   OscVal := 1.0 - 4.0 * Abs(Phase - 0.5);
      mwsWhiteNoise: OscVal := NoiseVal;
    end;

    RawSig := Lerp(Clamped(FNoiseMix, 0.0, 1.0), OscVal, NoiseVal);
    FilteredSig := B0 * RawSig + B1 * X1 + B2 * X2 - A1 * Y1 - A2 * Y2;
    X2 := X1; X1 := RawSig;
    Y2 := Y1; Y1 := FilteredSig;

    Env := EvaluateAdsrEnvelope(TimeSec, Dur, FAttackSec, FDecaySec,
      FSustainLevel, FReleaseSec);
    FilteredSig := Clamped(FilteredSig * Env * Clamped(FMasterGain, 0.0, 2.0), -1.0, 1.0);
    OutSamples[I] := FilteredSig;

    Peak := Max(Peak, Abs(FilteredSig));
    SumSq := SumSq + Sqr(FilteredSig);
  end;

  FLastPeakAmplitude := Peak;
  FLastRmsAmplitude := Sqrt(SumSq / NumSamples);
end;

function TCastleMetaSoundSynth.WriteRiffWavToStream(const AStream: TStream): Int64;
var
  Samples: TSinglePcmArray;
  Pcm16: array of SmallInt;
  NumSamples, I: Integer;
  DataBytes, RiffChunkSize, ByteRate, SampleRateU32, FmtSize: Cardinal;
  AudioFormat, NumChannels, BlockAlign, BitsPerSample: Word;
begin
  if AStream = nil then
    Exit(0);
  SynthesizePcmSamples(Samples);
  NumSamples := Length(Samples);
  SetLength(Pcm16, NumSamples);
  for I := 0 to NumSamples - 1 do
    Pcm16[I] := SmallInt(Round(Clamped(Samples[I], -1.0, 1.0) * 32767.0));

  SampleRateU32 := Cardinal(Clamped(FSampleRateHz, 4000, 96000));
  NumChannels := 1;
  BitsPerSample := 16;
  AudioFormat := 1; // Linear PCM
  BlockAlign := NumChannels * (BitsPerSample div 8);
  ByteRate := SampleRateU32 * BlockAlign;
  FmtSize := 16;
  DataBytes := Cardinal(NumSamples * SizeOf(SmallInt));
  RiffChunkSize := 36 + DataBytes;

  AStream.WriteBuffer('RIFF'[1], 4);
  AStream.WriteBuffer(RiffChunkSize, 4);
  AStream.WriteBuffer('WAVE'[1], 4);
  AStream.WriteBuffer('fmt '[1], 4);
  AStream.WriteBuffer(FmtSize, 4);
  AStream.WriteBuffer(AudioFormat, 2);
  AStream.WriteBuffer(NumChannels, 2);
  AStream.WriteBuffer(SampleRateU32, 4);
  AStream.WriteBuffer(ByteRate, 4);
  AStream.WriteBuffer(BlockAlign, 2);
  AStream.WriteBuffer(BitsPerSample, 2);
  AStream.WriteBuffer('data'[1], 4);
  AStream.WriteBuffer(DataBytes, 4);
  if DataBytes > 0 then
    AStream.WriteBuffer(Pcm16[0], DataBytes);

  Result := 44 + Int64(DataBytes);
end;

function TCastleMetaSoundSynth.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'WaveShape') or
     (PropertyName = 'DurationSec') or
     (PropertyName = 'StartFreqHz') or
     (PropertyName = 'EndFreqHz') or
     (PropertyName = 'NoiseMix') or
     (PropertyName = 'FilterCutoffHz') or
     (PropertyName = 'MasterGain') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleMetaSoundSynth.SynthSummaryBadge: String;
begin
  Result := Format('[MetaSound:%s %.0f->%.0fHz %.2fs]', [
    PresetDisplayName(FPreset), FStartFreqHz, FEndFreqHz, FDurationSec]);
end;

procedure TCastleMetaSoundSynth.SetPreset(const Value: TMetaSoundPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

function TCastleMetaSoundSynth.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('wave', Ord(FWaveShape));
    Root.Add('dur', FDurationSec);
    Root.Add('f0', FStartFreqHz);
    Root.Add('f1', FEndFreqHz);
    Root.Add('noise', FNoiseMix);
    Root.Add('cutoff', FFilterCutoffHz);
    Root.Add('q', FFilterResonanceQ);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMetaSoundSynth.SetConfigJson(const Value: String);
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
      FPreset := TMetaSoundPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TMetaSoundPreset))));
      FWaveShape := TMetaWaveShape(Clamped(Root.Get('wave', Ord(FWaveShape)),
        0, Ord(High(TMetaWaveShape))));
      FDurationSec := Clamped(Root.Get('dur', FDurationSec), 0.01, 10.0);
      FStartFreqHz := Max(10.0, Root.Get('f0', FStartFreqHz));
      FEndFreqHz := Max(10.0, Root.Get('f1', FEndFreqHz));
      FNoiseMix := Clamped(Root.Get('noise', FNoiseMix), 0.0, 1.0);
      FFilterCutoffHz := Max(40.0, Root.Get('cutoff', FFilterCutoffHz));
      FFilterResonanceQ := Clamped(Root.Get('q', FFilterResonanceQ), 0.25, 8.0);
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleFootstepSurfaceBehavior --------------------------------------------- }

constructor TCastleFootstepSurfaceBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStrideMeters := DefaultStrideMeters;
  FProbeHeight := DefaultProbeHeight;
  FPitchJitterPct := DefaultPitchJitterPct;
  FLastSurface := smkStone;
  FRngState := 918273;
end;

function TCastleFootstepSurfaceBehavior.NextRandomSigned: Single;
var
  X: Cardinal;
begin
  X := FRngState;
  if X = 0 then X := 918273;
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  FRngState := X;
  Result := ((X and $00FFFFFF) / 8388608.0) - 1.0;
end;

class function TCastleFootstepSurfaceBehavior.SurfaceDisplayName(
  const ASurf: TSurfaceMaterialKind): String;
begin
  case ASurf of
    smkStone: Result := 'Stone';
    smkWood:  Result := 'Wood';
    smkGrass: Result := 'Grass';
    smkWater: Result := 'Water';
    smkMetal: Result := 'Metal';
  end;
end;

class function TCastleFootstepSurfaceBehavior.ClassifyTransformSurface(
  const AHitTransform: TCastleTransform): TSurfaceMaterialKind;
var
  Cur: TCastleTransform;
  LName: String;
begin
  Result := smkStone;
  Cur := AHitTransform;
  while Cur <> nil do
  begin
    if Cur is TCastleWaterVolume then
      Exit(smkWater);
    case Cur.Tag of
      1: Exit(smkStone);
      2: Exit(smkWood);
      3: Exit(smkGrass);
      4: Exit(smkWater);
      5: Exit(smkMetal);
    end;
    LName := LowerCase(Cur.Name);
    if ContainsText(LName, 'water') or ContainsText(LName, 'puddle') then
      Exit(smkWater);
    if ContainsText(LName, 'wood') or ContainsText(LName, 'plank') or ContainsText(LName, 'bridge') then
      Exit(smkWood);
    if ContainsText(LName, 'grass') or ContainsText(LName, 'meadow') or ContainsText(LName, 'turf') then
      Exit(smkGrass);
    if ContainsText(LName, 'metal') or ContainsText(LName, 'grate') or ContainsText(LName, 'steel') then
      Exit(smkMetal);
    if ContainsText(LName, 'stone') or ContainsText(LName, 'rock') or ContainsText(LName, 'marble') then
      Exit(smkStone);
    Cur := Cur.Parent;
  end;
end;

function TCastleFootstepSurfaceBehavior.DetectSurfaceUnderFoot: TSurfaceMaterialKind;
var
  RayHit: TRayCollision;
  SavedPick: Boolean;
  OriginW: TVector3;
begin
  Result := FLastSurface;
  if (Parent = nil) or (Parent.World = nil) then
    Exit;

  SavedPick := Parent.Pickable;
  Parent.Pickable := False;
  try
    OriginW := Parent.Translation + Vector3(0.0, FProbeHeight, 0.0);
    RayHit := Parent.World.WorldRay(OriginW, Vector3(0.0, -1.0, 0.0));
    if RayHit <> nil then
    try
      if (RayHit.Transform <> nil) and (RayHit.Distance <= FProbeHeight * 3.0) then
        Result := ClassifyTransformSurface(RayHit.Transform);
    finally
      FreeAndNil(RayHit);
    end;
  finally
    Parent.Pickable := SavedPick;
  end;
  FLastSurface := Result;
end;

procedure TCastleFootstepSurfaceBehavior.TriggerFootstepNow(
  out OutSurface: TSurfaceMaterialKind; out OutStepFreqHz, OutStepCutoffHz: Single);
var
  JitterScale: Single;
begin
  OutSurface := DetectSurfaceUnderFoot;
  JitterScale := 1.0 + NextRandomSigned * (FPitchJitterPct * 0.01);
  case OutSurface of
    smkStone: begin OutStepFreqHz := 165.0; OutStepCutoffHz := 2100.0; end;
    smkWood:  begin OutStepFreqHz := 118.0; OutStepCutoffHz := 1150.0; end;
    smkGrass: begin OutStepFreqHz := 240.0; OutStepCutoffHz := 3200.0; end;
    smkWater: begin OutStepFreqHz := 380.0; OutStepCutoffHz := 4600.0; end;
    smkMetal: begin OutStepFreqHz := 520.0; OutStepCutoffHz := 6800.0; end;
  end;
  OutStepFreqHz := OutStepFreqHz * JitterScale;
  FLastStepFreqHz := OutStepFreqHz;
  FLastStepCutoffHz := OutStepCutoffHz;
  Inc(FTotalFootstepsTriggered);
end;

function TCastleFootstepSurfaceBehavior.AccumulateTravelDistance(
  const DeltaDistMeters: Single): Boolean;
var
  Surf: TSurfaceMaterialKind;
  F, Cut: Single;
begin
  Result := False;
  if DeltaDistMeters <= 0.0 then
    Exit;
  FDistanceAccumMeters := FDistanceAccumMeters + DeltaDistMeters;
  while FDistanceAccumMeters >= Max(0.25, FStrideMeters) do
  begin
    FDistanceAccumMeters := FDistanceAccumMeters - Max(0.25, FStrideMeters);
    TriggerFootstepNow(Surf, F, Cut);
    Result := True;
  end;
end;

function TCastleFootstepSurfaceBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'StrideMeters') or
     (PropertyName = 'ProbeHeight') or
     (PropertyName = 'PitchJitterPct') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleFootstepSurfaceBehavior.FootstepSummaryBadge: String;
begin
  Result := Format('[Footsteps:%s %d steps]', [
    SurfaceDisplayName(FLastSurface), FTotalFootstepsTriggered]);
end;

{ TCastleMusicStemDirector --------------------------------------------------- }

constructor TCastleMusicStemDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTempoBpm := DefaultTempoBpm;
  FBeatsPerBar := DefaultBeatsPerBar;
  FQuantizeBoundary := mqbNextBar;
  FCrossfadeSec := DefaultCrossfadeSec;
  ResetClock;
end;

class function TCastleMusicStemDirector.StemStateName(const AIndex: Integer): String;
begin
  case Clamped(AIndex, 0, 3) of
    0: Result := 'Explore';
    1: Result := 'Tension';
    2: Result := 'Combat';
    else Result := 'Boss';
  end;
end;

procedure TCastleMusicStemDirector.ResetClock;
var
  I: Integer;
begin
  FClockSec := 0.0;
  FActiveStateIndex := 0;
  FPendingStateIndex := -1;
  for I := 0 to 3 do
    FStemWeights[I] := 0.0;
  FStemWeights[0] := 1.0;
end;

function TCastleMusicStemDirector.BeatDurationSec: Single;
begin
  Result := 60.0 / Max(20.0, FTempoBpm);
end;

function TCastleMusicStemDirector.BarDurationSec: Single;
begin
  Result := BeatDurationSec * Max(1, FBeatsPerBar);
end;

function TCastleMusicStemDirector.CurrentBeatNumber: Integer;
begin
  Result := Floor(FClockSec / BeatDurationSec) + 1;
end;

function TCastleMusicStemDirector.CurrentBarNumber: Integer;
begin
  Result := Floor(FClockSec / BarDurationSec) + 1;
end;

function TCastleMusicStemDirector.CurrentBeatInBar: Integer;
begin
  Result := ((CurrentBeatNumber - 1) mod Max(1, FBeatsPerBar)) + 1;
end;

function TCastleMusicStemDirector.GetStemWeight(const AStemIndex: Integer): Single;
begin
  Result := FStemWeights[Clamped(AStemIndex, 0, 3)];
end;

procedure TCastleMusicStemDirector.RequestMusicState(const AStateIndex: Integer);
var
  ClampedIdx: Integer;
begin
  ClampedIdx := Clamped(AStateIndex, 0, 3);
  if FQuantizeBoundary = mqbImmediate then
  begin
    FActiveStateIndex := ClampedIdx;
    FPendingStateIndex := -1;
  end else
  if ClampedIdx <> FActiveStateIndex then
    FPendingStateIndex := ClampedIdx
  else
    FPendingStateIndex := -1;
end;

procedure TCastleMusicStemDirector.StepMusicClock(const Dt: Single);
const
  MaxSlice = 0.02;
var
  Remaining, SliceDt, PrevT, NextT, BeatDur, BarDur, FadeRate, TargetW: Single;
  CrossedBoundary: Boolean;
  I: Integer;
begin
  if Dt <= 0.0 then
    Exit;
  BeatDur := BeatDurationSec;
  BarDur := BarDurationSec;
  Remaining := Dt;

  while Remaining > 1e-6 do
  begin
    SliceDt := Min(Remaining, MaxSlice);
    Remaining := Remaining - SliceDt;

    PrevT := FClockSec;
    NextT := PrevT + SliceDt;
    FClockSec := NextT;

    if FPendingStateIndex >= 0 then
    begin
      CrossedBoundary := False;
      case FQuantizeBoundary of
        mqbImmediate: CrossedBoundary := True;
        mqbNextBeat:
          CrossedBoundary := Floor((NextT + 1e-5) / BeatDur) > Floor((PrevT + 1e-5) / BeatDur);
        mqbNextBar:
          CrossedBoundary := Floor((NextT + 1e-5) / BarDur) > Floor((PrevT + 1e-5) / BarDur);
      end;
      if CrossedBoundary then
      begin
        FActiveStateIndex := FPendingStateIndex;
        FPendingStateIndex := -1;
      end;
    end;

    if FCrossfadeSec <= 1e-4 then
      FadeRate := 1000.0
    else
      FadeRate := 1.0 / FCrossfadeSec;

    for I := 0 to 3 do
    begin
      if I = FActiveStateIndex then
        TargetW := 1.0
      else
        TargetW := 0.0;
      if FStemWeights[I] < TargetW then
        FStemWeights[I] := Min(TargetW, FStemWeights[I] + FadeRate * SliceDt)
      else if FStemWeights[I] > TargetW then
        FStemWeights[I] := Max(TargetW, FStemWeights[I] - FadeRate * SliceDt);
    end;
  end;
end;

function TCastleMusicStemDirector.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'TempoBpm') or
     (PropertyName = 'BeatsPerBar') or
     (PropertyName = 'QuantizeBoundary') or
     (PropertyName = 'CrossfadeSec') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleMusicStemDirector.MusicSummaryBadge: String;
begin
  Result := Format('[Quartz:%.0fBPM Bar %d.%d %s]', [
    FTempoBpm, CurrentBarNumber, CurrentBeatInBar, StemStateName(FActiveStateIndex)]);
end;

function TCastleMusicStemDirector.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('bpm', FTempoBpm);
    Root.Add('bpb', FBeatsPerBar);
    Root.Add('quant', Ord(FQuantizeBoundary));
    Root.Add('fade', FCrossfadeSec);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMusicStemDirector.SetConfigJson(const Value: String);
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
      FTempoBpm := Clamped(Root.Get('bpm', FTempoBpm), 20.0, 300.0);
      FBeatsPerBar := Max(1, Root.Get('bpb', FBeatsPerBar));
      FQuantizeBoundary := TMusicQuantizeBoundary(Clamped(
        Root.Get('quant', Ord(FQuantizeBoundary)), 0, Ord(High(TMusicQuantizeBoundary))));
      FCrossfadeSec := Max(0.0, Root.Get('fade', FCrossfadeSec));
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleMetaSoundSynth,
    ['Audio & Music', 'MetaSound Procedural PCM Synth']);
  RegisterSerializableComponent(TCastleFootstepSurfaceBehavior,
    ['Audio & Music', 'Raycast Surface-Tagged Footstep Switcher']);
  RegisterSerializableComponent(TCastleMusicStemDirector,
    ['Audio & Music', 'Quartz Beat-Quantized Music Stem Director']);
end.
