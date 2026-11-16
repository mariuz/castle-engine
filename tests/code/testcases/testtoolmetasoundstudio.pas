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

{ Automated unit tests for Phase 322 MetaSound Procedural PCM Synth,
  Surface-Tagged Footstep Switcher & Quartz Beat-Quantized Music Stem Studio
  (@link(TCastleMetaSoundSynth), @link(TCastleFootstepSurfaceBehavior),
  @link(TCastleMusicStemDirector), @link(TMetaSoundStudioHelper)). }
unit TestToolMetaSoundStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolMetaSoundStudio = class(TCastleTestCase)
  published
    procedure TestProceduralSynthAdsrLowPassRiffWavHeaderAndSurfaceFootstepRaycast;
    procedure TestQuartzBarQuantizedMusicStemTransitionCrossfadeAndJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleMetaSound, ToolMetaSoundStudio;

procedure TTestToolMetaSoundStudio.TestProceduralSynthAdsrLowPassRiffWavHeaderAndSurfaceFootstepRaycast;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Synth: TCastleMetaSoundSynth;
  Walker: TCastleTransform;
  Foot: TCastleFootstepSurfaceBehavior;
  Dir: TCastleMusicStemDirector;
  Samples: TSinglePcmArray;
  RmsBright, RmsMuffled: Single;
  Mem: TMemoryStream;
  HeaderTag: array [0..3] of AnsiChar;
  WrittenBytes: Int64;
begin
  { 1. ADSR envelope boundary & sustain exactness }
  AssertSameValue(0.0, EvaluateAdsrEnvelope(0.0, 1.0, 0.1, 0.2, 0.5, 0.2), 1e-4);
  AssertSameValue(0.5, EvaluateAdsrEnvelope(0.05, 1.0, 0.1, 0.2, 0.5, 0.2), 1e-3); // mid-attack
  AssertSameValue(0.5, EvaluateAdsrEnvelope(0.50, 1.0, 0.1, 0.2, 0.5, 0.2), 1e-3); // sustain plateau
  AssertSameValue(0.25, EvaluateAdsrEnvelope(0.90, 1.0, 0.1, 0.2, 0.5, 0.2), 1e-3); // mid-release

  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TMetaSoundStudioHelper.SpawnAudioPlaygroundDemo(
      Vp, OwnerComp, Synth, Walker, Foot, Dir);

    { 2. 2-Pole Biquad Low-Pass attenuation on high-frequency 4000 Hz sawtooth }
    Synth.WaveShape := mwsSawtooth;
    Synth.StartFreqHz := 4000.0;
    Synth.EndFreqHz := 4000.0;
    Synth.NoiseMix := 0.0;
    Synth.FilterCutoffHz := 9500.0;
    Synth.SynthesizePcmSamples(Samples);
    RmsBright := Synth.LastRmsAmplitude;

    Synth.FilterCutoffHz := 240.0;
    Synth.SynthesizePcmSamples(Samples);
    RmsMuffled := Synth.LastRmsAmplitude;
    AssertTrue(RmsMuffled < RmsBright * 0.25);

    { 3. Valid 44-byte RIFF/WAVE 16-bit PCM header + sample payload }
    Synth.ApplyPreset(mspUiCrystalChime);
    Mem := TMemoryStream.Create;
    try
      WrittenBytes := Synth.WriteRiffWavToStream(Mem);
      AssertEquals(Mem.Size, WrittenBytes);
      AssertTrue(Mem.Size > 44);
      Mem.Position := 0;
      Mem.ReadBuffer(HeaderTag[0], 4);
      AssertEquals('RIFF', String(HeaderTag));
      Mem.Position := 8;
      Mem.ReadBuffer(HeaderTag[0], 4);
      AssertEquals('WAVE', String(HeaderTag));
    finally
      FreeAndNil(Mem);
    end;

    { 4. Downward WorldRay surface detection across Stone (-5), Wood (0), Metal (+5) pads }
    Walker.Translation := Vector3(-5.0, 0.90, 0.0);
    AssertEquals(Ord(smkStone), Ord(Foot.DetectSurfaceUnderFoot));

    Walker.Translation := Vector3(0.0, 0.90, 0.0);
    AssertEquals(Ord(smkWood), Ord(Foot.DetectSurfaceUnderFoot));

    Walker.Translation := Vector3(5.0, 0.90, 0.0);
    AssertEquals(Ord(smkMetal), Ord(Foot.DetectSurfaceUnderFoot));
    AssertTrue(Foot.AccumulateTravelDistance(2.0));
    AssertEquals(1, Foot.TotalFootstepsTriggered);
    AssertTrue(Foot.LastStepCutoffHz > 5000.0); // Bright metallic footstep cutoff!
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolMetaSoundStudio.TestQuartzBarQuantizedMusicStemTransitionCrossfadeAndJsonRoundtrip;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Synth: TCastleMetaSoundSynth;
  Walker: TCastleTransform;
  Foot: TCastleFootstepSurfaceBehavior;
  Dir, LoadedDir: TCastleMusicStemDirector;
  Rep: TMetaSoundAuditReport;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TMetaSoundStudioHelper.SpawnAudioPlaygroundDemo(
      Vp, OwnerComp, Synth, Walker, Foot, Dir);

    { 120 BPM, 4/4 -> 0.50s per beat, 2.00s per bar! }
    Dir.ResetClock;
    Dir.TempoBpm := 120.0;
    Dir.BeatsPerBar := 4;
    Dir.QuantizeBoundary := mqbNextBar;
    Dir.CrossfadeSec := 0.40;
    AssertSameValue(0.50, Dir.BeatDurationSec, 1e-4);
    AssertSameValue(2.00, Dir.BarDurationSec, 1e-4);

    { Advance to t = 0.60s (Bar 1, Beat 2) and request Combat stem (index 2) }
    Dir.StepMusicClock(0.60);
    AssertEquals(1, Dir.CurrentBarNumber);
    AssertEquals(2, Dir.CurrentBeatInBar);
    Dir.RequestMusicState(2);

    { At t = 1.60s (still inside Bar 1 before 2.00s bar line!), Combat weight MUST remain 0.0! }
    Dir.StepMusicClock(1.00);
    AssertEquals(0, Dir.ActiveStateIndex);
    AssertSameValue(1.0, Dir.GetStemWeight(0), 1e-4);
    AssertSameValue(0.0, Dir.GetStemWeight(2), 1e-4);

    { Cross the 2.00s Bar 2 downbeat + complete 0.40s crossfade (advance to t = 2.50s) }
    Dir.StepMusicClock(0.90);
    AssertEquals(2, Dir.ActiveStateIndex);
    AssertEquals(2, Dir.CurrentBarNumber);
    AssertSameValue(0.0, Dir.GetStemWeight(0), 1e-3);
    AssertSameValue(1.0, Dir.GetStemWeight(2), 1e-3);

    JsonStr := ComponentToString(Dir);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleMusicStemDirector);
    LoadedDir := TCastleMusicStemDirector(LoadedComp);
    AssertSameValue(120.0, LoadedDir.TempoBpm, 1e-2);

    Rep := TMetaSoundStudioHelper.AuditMetaSound(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.SynthCount);
      AssertEquals(1, Rep.FootstepCount);
      AssertEquals(2, Rep.MusicDirectorCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolMetaSoundStudio);
end.
