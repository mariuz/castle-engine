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

{ Automated tests for @link(TCastleAudioBusMixer),
  @link(TCastleAudioBusRouterBehavior), @link(TCastleAudioZone), and
  @link(TAudioMixerHelper) (Phase 291 — UE 5.9 / 6.0 MetaSounds & Submix Parity). }
unit TestToolAudioMixer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolAudioMixer = class(TCastleTestCase)
  published
    procedure TestBusRoutingMuteSoloVoiceDuckingAndJsonRoundtrip;
    procedure TestSpatialAudioZoneHermiteCrossfadeAndHelperWorkflow;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize,
  CastleTransform, CastleBehaviors, CastleViewport,
  CastleAudioMixer, ToolAudioMixer;

procedure TTestToolAudioMixer.TestBusRoutingMuteSoloVoiceDuckingAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  VP: TCastleViewport;
  Mixer, ReloadedMixer: TCastleAudioBusMixer;
  MusicEnt, SfxEnt, VoiceEnt, AmbientEnt: TCastleTransform;
  MusicSrc, SfxSrc, VoiceSrc, AmbientSrc: TCastleSoundSource;
  MusicRtr, VoiceRtr: TCastleAudioBusRouterBehavior;
  DomPreset: TCastleAudioAcousticPreset;
  DomWeight: Single;
  JsonStr: String;
  ReloadedComp: TComponent;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(DesignOwner);
    VP.Name := 'ViewportMain';

    Mixer := TAudioMixerHelper.EnsureMixerInDesign(VP, DesignOwner);
    AssertTrue(Mixer <> nil);
    Mixer.MasterGain := 0.80;
    Mixer.MusicGain := 1.00;
    Mixer.SfxGain := 1.25;
    Mixer.VoiceGain := 1.10;
    Mixer.AmbientGain := 0.60;
    Mixer.DuckMusicOnVoice := true;
    Mixer.VoiceDuckFactor := 0.25;

    MusicEnt := TCastleTransform.Create(DesignOwner);
    MusicEnt.Name := 'BgmEmitter';
    MusicSrc := TCastleSoundSource.Create(DesignOwner);
    MusicSrc.SoundPlaying := false;
    MusicEnt.AddBehavior(MusicSrc);
    VP.Items.Add(MusicEnt);
    MusicRtr := TAudioMixerHelper.AttachBusRouter(MusicEnt, DesignOwner, abkMusic, Mixer.Name);
    MusicRtr.BaseVolume := 1.0;

    SfxEnt := TCastleTransform.Create(DesignOwner);
    SfxEnt.Name := 'ExplosionEmitter';
    SfxSrc := TCastleSoundSource.Create(DesignOwner);
    SfxSrc.SoundPlaying := false;
    SfxEnt.AddBehavior(SfxSrc);
    VP.Items.Add(SfxEnt);
    TAudioMixerHelper.AttachBusRouter(SfxEnt, DesignOwner, abkSFX, Mixer.Name);

    VoiceEnt := TCastleTransform.Create(DesignOwner);
    VoiceEnt.Name := 'NpcDialogue';
    VoiceSrc := TCastleSoundSource.Create(DesignOwner);
    VoiceSrc.SoundPlaying := false;
    VoiceEnt.AddBehavior(VoiceSrc);
    VP.Items.Add(VoiceEnt);
    VoiceRtr := TAudioMixerHelper.AttachBusRouter(VoiceEnt, DesignOwner, abkVoice, Mixer.Name);

    AmbientEnt := TCastleTransform.Create(DesignOwner);
    AmbientEnt.Name := 'ForestWind';
    AmbientSrc := TCastleSoundSource.Create(DesignOwner);
    AmbientSrc.SoundPlaying := false;
    AmbientEnt.AddBehavior(AmbientSrc);
    VP.Items.Add(AmbientEnt);
    TAudioMixerHelper.AttachBusRouter(AmbientEnt, DesignOwner, abkAmbient, Mixer.Name);

    { 1. Baseline mix without active voice }
    Mixer.EvaluateWorldSoundscape(VP, TVector3.Zero, 0.0, DomPreset, DomWeight);
    AssertSameValue(0.80, MusicSrc.Volume, 0.001);
    AssertSameValue(1.00, SfxSrc.Volume, 0.001);     // 0.80 * 1.25
    AssertSameValue(0.88, VoiceSrc.Volume, 0.001);   // 0.80 * 1.10
    AssertSameValue(0.48, AmbientSrc.Volume, 0.001); // 0.80 * 0.60

    { 2. Sidechain voice ducking when Voice router becomes audible }
    VoiceRtr.SimulatedPlaying := true;
    Mixer.EvaluateWorldSoundscape(VP, TVector3.Zero, 0.0, DomPreset, DomWeight);
    AssertSameValue(0.20, MusicSrc.Volume, 0.001);   // 0.80 * 0.25 duck
    AssertSameValue(1.00, SfxSrc.Volume, 0.001);     // SFX unducked
    AssertSameValue(0.30, AmbientSrc.Volume, 0.001); // 50% duck -> Lerp(0.5, 1.0, 0.25)=0.625 * 0.48 = 0.30

    { 3. Solo SFX isolates SFX and silences Music / Voice / Ambient }
    VoiceRtr.SimulatedPlaying := false;
    Mixer.SfxSolo := true;
    Mixer.EvaluateWorldSoundscape(VP, TVector3.Zero, 0.0, DomPreset, DomWeight);
    AssertSameValue(0.0, MusicSrc.Volume, 0.001);
    AssertSameValue(1.00, SfxSrc.Volume, 0.001);
    AssertSameValue(0.0, VoiceSrc.Volume, 0.001);
    AssertSameValue(0.0, AmbientSrc.Volume, 0.001);
    Mixer.SfxSolo := false;

    { 4. Master Mute silences all buses }
    Mixer.MasterMuted := true;
    Mixer.EvaluateWorldSoundscape(VP, TVector3.Zero, 0.0, DomPreset, DomWeight);
    AssertSameValue(0.0, SfxSrc.Volume, 0.001);
    Mixer.MasterMuted := false;

    { 5. JSON serialization roundtrip }
    JsonStr := ComponentToString(Mixer);
    ReloadedComp := StringToComponent(JsonStr, ReloadOwner);
    AssertTrue(ReloadedComp is TCastleAudioBusMixer);
    ReloadedMixer := TCastleAudioBusMixer(ReloadedComp);
    AssertSameValue(0.80, ReloadedMixer.MasterGain, 0.001);
    AssertSameValue(1.25, ReloadedMixer.SfxGain, 0.001);
    AssertSameValue(0.25, ReloadedMixer.VoiceDuckFactor, 0.001);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolAudioMixer.TestSpatialAudioZoneHermiteCrossfadeAndHelperWorkflow;
var
  DesignOwner: TComponent;
  VP: TCastleViewport;
  Mixer: TCastleAudioBusMixer;
  WaterZone: TCastleAudioZone;
  AmbEnt, UnroutedEnt: TCastleTransform;
  AmbSrc, UnroutedSrc: TCastleSoundSource;
  DomPreset: TCastleAudioAcousticPreset;
  DomWeight: Single;
  Sum: TAudioMixerSummary;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(DesignOwner);
    VP.Name := 'ViewportMain';

    Mixer := TAudioMixerHelper.EnsureMixerInDesign(VP, DesignOwner);
    WaterZone := TAudioMixerHelper.CreateAudioZoneInDesign(
      VP, DesignOwner, Vector3(0, 0, 0), aapUnderwaterMuffled);
    AssertTrue(WaterZone <> nil);
    WaterZone.InnerRadius := 4.0;
    WaterZone.OuterRadius := 12.0;
    WaterZone.AmbientGainMultiplier := 2.0;
    WaterZone.MusicGainMultiplier := 0.5;

    { Hermite SmoothStep weight checks: 1.0 inside, 0.5 at midpoint 8m, 0.0 outside }
    AssertSameValue(1.0, WaterZone.EvaluateBlendWeight(Vector3(2, 0, 0)), 0.001);
    AssertSameValue(0.5, WaterZone.EvaluateBlendWeight(Vector3(8, 0, 0)), 0.001);
    AssertSameValue(0.0, WaterZone.EvaluateBlendWeight(Vector3(15, 0, 0)), 0.001);

    AmbEnt := TCastleTransform.Create(DesignOwner);
    AmbEnt.Name := 'BubbleBed';
    AmbSrc := TCastleSoundSource.Create(DesignOwner);
    AmbSrc.SoundPlaying := false;
    AmbEnt.AddBehavior(AmbSrc);
    VP.Items.Add(AmbEnt);
    TAudioMixerHelper.AttachBusRouter(AmbEnt, DesignOwner, abkAmbient, Mixer.Name);

    { Unrouted sound source to verify diagnostic warning }
    UnroutedEnt := TCastleTransform.Create(DesignOwner);
    UnroutedEnt.Name := 'LooseTorchAudio';
    UnroutedSrc := TCastleSoundSource.Create(DesignOwner);
    UnroutedSrc.SoundPlaying := false;
    UnroutedEnt.AddBehavior(UnroutedSrc);
    VP.Items.Add(UnroutedEnt);

    { Inside underwater core (d = 1m): Ambient doubled, Pitch muffled to 0.85 }
    Mixer.EvaluateWorldSoundscape(VP, Vector3(1, 0, 0), 0.0, DomPreset, DomWeight);
    AssertTrue(DomPreset = aapUnderwaterMuffled);
    AssertSameValue(1.0, DomWeight, 0.001);
    AssertSameValue(2.0, AmbSrc.Volume, 0.001);
    AssertSameValue(0.85, AmbSrc.Pitch, 0.001);

    { At midpoint (d = 8m, weight = 0.5): Ambient Lerp(0.5, 1.0, 2.0) = 1.5, Pitch Lerp(0.5, 1.0, 0.85) = 0.925 }
    Mixer.EvaluateWorldSoundscape(VP, Vector3(8, 0, 0), 0.0, DomPreset, DomWeight);
    AssertSameValue(0.5, DomWeight, 0.001);
    AssertSameValue(1.5, AmbSrc.Volume, 0.001);
    AssertSameValue(0.925, AmbSrc.Pitch, 0.001);

    { Scan diagnostics & Markdown }
    Sum := TAudioMixerHelper.ScanAudioSoundscape(VP, Vector3(1, 0, 0));
    AssertEquals(1, Length(Sum.Mixers));
    AssertEquals(1, Length(Sum.Zones));
    AssertEquals(2, Sum.TotalSoundSources);
    AssertEquals(1, Sum.UnroutedSoundSources);
    AssertTrue(Length(Sum.Warnings) >= 1);

    TAudioMixerHelper.ApplySoundscapeMixPreset(Mixer, 1); // Dialogue Focus
    AssertSameValue(1.35, Mixer.VoiceGain, 0.001);

    Md := TAudioMixerHelper.FormatAudioSoundscapeMarkdown(VP, Vector3(1, 0, 0));
    AssertTrue(Pos('Castle Spatial Audio Soundscape Report', Md) > 0);
    AssertTrue(Pos('Underwater Muffled', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolAudioMixer);
end.
