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

{ Spatial audio soundscape mixer, named bus routing, sidechain voice ducking,
  and Hermite-crossfaded 3D acoustic zones (@link(TCastleAudioBusMixer),
  @link(TCastleAudioBusRouterBehavior), @link(TCastleAudioZone))
  (Phase 291 — UE 5.9 / 6.0 MetaSounds & Submix Bus Parity). }
unit CastleAudioMixer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleBoxes, CastleClassUtils, CastleTransform;

type
  { Named submix buses supported by @link(TCastleAudioBusMixer). }
  TCastleAudioBusKind = (
    abkMaster,
    abkMusic,
    abkSFX,
    abkVoice,
    abkAmbient
  );

  { Acoustic soundscape presets applied by @link(TCastleAudioZone). }
  TCastleAudioAcousticPreset = (
    aapNeutral,
    aapCaveReverb,
    aapCathedralHall,
    aapUnderwaterMuffled,
    aapIndoorRoom,
    aapOutdoorWindy
  );

  { Non-visual component providing 5-bus submix routing (@code(Master),
    @code(Music), @code(SFX), @code(Voice), @code(Ambient)) with per-bus gain,
    mute, solo, smooth sidechain voice ducking of @code(Music)/@code(Ambient),
    and 3D @link(TCastleAudioZone) crossfade evaluation. }
  TCastleAudioBusMixer = class(TCastleComponent)
  public const
    DefaultGain = 1.0;
    DefaultVoiceDuckFactor = 0.30;
    DefaultDuckSmoothingSpeed = 8.0;
  strict private
    FMasterGain: Single;
    FMusicGain: Single;
    FSfxGain: Single;
    FVoiceGain: Single;
    FAmbientGain: Single;
    FMasterMuted: Boolean;
    FMusicMuted: Boolean;
    FSfxMuted: Boolean;
    FVoiceMuted: Boolean;
    FAmbientMuted: Boolean;
    FMusicSolo: Boolean;
    FSfxSolo: Boolean;
    FVoiceSolo: Boolean;
    FAmbientSolo: Boolean;
    FDuckMusicOnVoice: Boolean;
    FVoiceActive: Boolean;
    FVoiceDuckFactor: Single;
    FDuckSmoothingSpeed: Single;
    FDuckAmount: Single;
    procedure SetMasterGain(const AValue: Single);
    procedure SetMusicGain(const AValue: Single);
    procedure SetSfxGain(const AValue: Single);
    procedure SetVoiceGain(const AValue: Single);
    procedure SetAmbientGain(const AValue: Single);
    procedure SetVoiceDuckFactor(const AValue: Single);
    procedure SetDuckSmoothingSpeed(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    function GetBusGain(const ABus: TCastleAudioBusKind): Single;
    procedure SetBusGain(const ABus: TCastleAudioBusKind; const AValue: Single);
    function GetBusMuted(const ABus: TCastleAudioBusKind): Boolean;
    procedure SetBusMuted(const ABus: TCastleAudioBusKind; const AValue: Boolean);
    function GetBusSolo(const ABus: TCastleAudioBusKind): Boolean;
    procedure SetBusSolo(const ABus: TCastleAudioBusKind; const AValue: Boolean);
    function AnySubBusSoloed: Boolean;

    { Advance sidechain ducking envelope (@code(0.0 = unducked, 1.0 = full duck)). }
    procedure StepDucking(const ASecondsPassed: Single;
      const AHasActiveVoice: Boolean);

    { Effective linear output gain for @code(ABus), honoring @code(MasterGain),
      mute, solo, sidechain @code(Voice) -> @code(Music) ducking, and spatial
      zone boost multipliers. }
    function EffectiveBusGain(const ABus: TCastleAudioBusKind;
      const AZoneMusicBoost: Single = 1.0;
      const AZoneAmbientBoost: Single = 1.0;
      const AZoneSfxBoost: Single = 1.0): Single;

    { Subtle acoustic pitch modulation for environmental presets
      (e.g. underwater muffling or cavern resonance). }
    class function EffectivePitchMultiplier(
      const APreset: TCastleAudioAcousticPreset;
      const ABlendWeight: Single): Single;

    { Evaluate all @link(TCastleAudioZone) and @link(TCastleAudioBusRouterBehavior)
      instances inside @code(AWorldRoot) for listener position
      @code(AListenerWorldPos), updating routed @code(TCastleSoundSource)
      volumes and pitches in place. }
    procedure EvaluateWorldSoundscape(const AWorldRoot: TComponent;
      const AListenerWorldPos: TVector3; const ASecondsPassed: Single;
      out OutDominantPreset: TCastleAudioAcousticPreset;
      out OutDominantWeight: Single);

    { Current sidechain duck envelope in @code([0..1]). }
    property DuckAmount: Single read FDuckAmount;

    { Short Hierarchy badge string (e.g. @code([Mixer:M=100% Duck=ON])). }
    function MixerSummaryBadge: String;
  published
    property MasterGain: Single read FMasterGain write SetMasterGain {$ifdef FPC}default DefaultGain{$endif};
    property MusicGain: Single read FMusicGain write SetMusicGain {$ifdef FPC}default DefaultGain{$endif};
    property SfxGain: Single read FSfxGain write SetSfxGain {$ifdef FPC}default DefaultGain{$endif};
    property VoiceGain: Single read FVoiceGain write SetVoiceGain {$ifdef FPC}default DefaultGain{$endif};
    property AmbientGain: Single read FAmbientGain write SetAmbientGain {$ifdef FPC}default DefaultGain{$endif};

    property MasterMuted: Boolean read FMasterMuted write FMasterMuted default false;
    property MusicMuted: Boolean read FMusicMuted write FMusicMuted default false;
    property SfxMuted: Boolean read FSfxMuted write FSfxMuted default false;
    property VoiceMuted: Boolean read FVoiceMuted write FVoiceMuted default false;
    property AmbientMuted: Boolean read FAmbientMuted write FAmbientMuted default false;

    property MusicSolo: Boolean read FMusicSolo write FMusicSolo default false;
    property SfxSolo: Boolean read FSfxSolo write FSfxSolo default false;
    property VoiceSolo: Boolean read FVoiceSolo write FVoiceSolo default false;
    property AmbientSolo: Boolean read FAmbientSolo write FAmbientSolo default false;

    property DuckMusicOnVoice: Boolean read FDuckMusicOnVoice write FDuckMusicOnVoice default true;
    property VoiceActive: Boolean read FVoiceActive write FVoiceActive default false;
    property VoiceDuckFactor: Single read FVoiceDuckFactor write SetVoiceDuckFactor {$ifdef FPC}default DefaultVoiceDuckFactor{$endif};
    property DuckSmoothingSpeed: Single read FDuckSmoothingSpeed write SetDuckSmoothingSpeed {$ifdef FPC}default DefaultDuckSmoothingSpeed{$endif};
  end;

  { Behavior attached to a @link(TCastleTransform) to route any sibling
    @code(TCastleSoundSource) behaviors onto a named @link(TCastleAudioBusKind)
    controlled by @link(TCastleAudioBusMixer). }
  TCastleAudioBusRouterBehavior = class(TCastleBehavior)
  public const
    DefaultBaseVolume = 1.0;
    DefaultBasePitch = 1.0;
  strict private
    FBus: TCastleAudioBusKind;
    FBaseVolume: Single;
    FBasePitch: Single;
    FMixerName: String;
    FSimulatedPlaying: Boolean;
    FLastAppliedVolume: Single;
    FLastAppliedPitch: Single;
    procedure SetBaseVolume(const AValue: Single);
    procedure SetBasePitch(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Resolve target @link(TCastleAudioBusMixer) by @link(MixerName) or first
      mixer found in @code(ASearchRoot) / @code(Owner). }
    function ResolveMixer(const ASearchRoot: TComponent = nil): TCastleAudioBusMixer;

    { True when @link(SimulatedPlaying) is set or a sibling
      @code(TCastleSoundSource) on @code(Parent) has @code(SoundPlaying) with
      a non-nil @code(Sound). }
    function IsCurrentlyAudibleSource: Boolean;

    { Apply bus gain & acoustic pitch multiplier to sibling @code(TCastleSoundSource)
      behaviors and update @link(LastAppliedVolume) / @link(LastAppliedPitch). }
    procedure ApplyRoutedMix(const AEffectiveBusGain, APitchMul: Single);

    function RouterSummaryBadge: String;

    property LastAppliedVolume: Single read FLastAppliedVolume;
    property LastAppliedPitch: Single read FLastAppliedPitch;
  published
    property Bus: TCastleAudioBusKind read FBus write FBus default abkSFX;
    property BaseVolume: Single read FBaseVolume write SetBaseVolume {$ifdef FPC}default DefaultBaseVolume{$endif};
    property BasePitch: Single read FBasePitch write SetBasePitch {$ifdef FPC}default DefaultBasePitch{$endif};
    property MixerName: String read FMixerName write FMixerName;
    property SimulatedPlaying: Boolean read FSimulatedPlaying write FSimulatedPlaying default false;
  end;

  { Spatial 3D acoustic zone with smooth Hermite crossfade between
    @link(InnerRadius) (100% weight) and @link(OuterRadius) (0% weight). }
  TCastleAudioZone = class(TCastleTransform)
  public const
    DefaultInnerRadius = 5.0;
    DefaultOuterRadius = 12.0;
    DefaultMusicMult = 1.0;
    DefaultAmbientMult = 1.25;
    DefaultSfxMult = 1.0;
  strict private
    FZoneLabel: String;
    FAcousticPreset: TCastleAudioAcousticPreset;
    FInnerRadius: Single;
    FOuterRadius: Single;
    FPriority: Integer;
    FMusicGainMultiplier: Single;
    FAmbientGainMultiplier: Single;
    FSfxGainMultiplier: Single;
    FZoneEnabled: Boolean;
    FShowZoneInViewport: Boolean;
    procedure SetInnerRadius(const AValue: Single);
    procedure SetOuterRadius(const AValue: Single);
    procedure SetMusicGainMultiplier(const AValue: Single);
    procedure SetAmbientGainMultiplier(const AValue: Single);
    procedure SetSfxGainMultiplier(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;

    { Smooth Hermite blend weight in @code([0..1]) at @code(AListenerWorldPos). }
    function EvaluateBlendWeight(const AListenerWorldPos: TVector3): Single;

    function ZoneSummaryBadge: String;
  published
    property ZoneLabel: String read FZoneLabel write FZoneLabel;
    property AcousticPreset: TCastleAudioAcousticPreset
      read FAcousticPreset write FAcousticPreset default aapCaveReverb;
    property InnerRadius: Single read FInnerRadius write SetInnerRadius {$ifdef FPC}default DefaultInnerRadius{$endif};
    property OuterRadius: Single read FOuterRadius write SetOuterRadius {$ifdef FPC}default DefaultOuterRadius{$endif};
    property Priority: Integer read FPriority write FPriority default 0;
    property MusicGainMultiplier: Single read FMusicGainMultiplier write SetMusicGainMultiplier {$ifdef FPC}default DefaultMusicMult{$endif};
    property AmbientGainMultiplier: Single read FAmbientGainMultiplier write SetAmbientGainMultiplier {$ifdef FPC}default DefaultAmbientMult{$endif};
    property SfxGainMultiplier: Single read FSfxGainMultiplier write SetSfxGainMultiplier {$ifdef FPC}default DefaultSfxMult{$endif};
    property ZoneEnabled: Boolean read FZoneEnabled write FZoneEnabled default true;
    property ShowZoneInViewport: Boolean read FShowZoneInViewport write FShowZoneInViewport default true;
  end;

function AudioBusKindToDisplayName(const ABus: TCastleAudioBusKind): String;
function AudioAcousticPresetToDisplayName(const APreset: TCastleAudioAcousticPreset): String;
function LinearGainToDecibelsStr(const AGain: Single): String;

implementation

uses
  Math, StrUtils,
  CastleUtils, CastleComponentSerialize, CastleBehaviors, CastleUIControls,
  CastleViewport;

function AudioBusKindToDisplayName(const ABus: TCastleAudioBusKind): String;
begin
  case ABus of
    abkMaster:  Result := 'Master';
    abkMusic:   Result := 'Music';
    abkSFX:     Result := 'SFX';
    abkVoice:   Result := 'Voice';
    abkAmbient: Result := 'Ambient';
  end;
end;

function AudioAcousticPresetToDisplayName(
  const APreset: TCastleAudioAcousticPreset): String;
begin
  case APreset of
    aapNeutral:           Result := 'Neutral';
    aapCaveReverb:        Result := 'Cave Reverb';
    aapCathedralHall:     Result := 'Cathedral Hall';
    aapUnderwaterMuffled: Result := 'Underwater Muffled';
    aapIndoorRoom:        Result := 'Indoor Room';
    aapOutdoorWindy:      Result := 'Outdoor Windy';
  end;
end;

function LinearGainToDecibelsStr(const AGain: Single): String;
var
  Db: Single;
begin
  if AGain <= 0.0001 then
    Result := '-inf dB'
  else
  begin
    Db := 20.0 * Log10(AGain);
    if Db >= 0.0 then
      Result := Format('+%.1f dB', [Db])
    else
      Result := Format('%.1f dB', [Db]);
  end;
end;

procedure CollectSoundscapeNodes(const ANode: TComponent;
  var Zones: array of TCastleAudioZone; var ZoneCount: Integer;
  var Routers: array of TCastleAudioBusRouterBehavior; var RouterCount: Integer;
  var FirstMixer: TCastleAudioBusMixer; const AWantedMixerName: String);

  procedure VisitComponent(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    B: TCastleBehavior;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if C = nil then
      Exit;
    if csTransient in C.ComponentStyle then
      Exit;

    if C is TCastleAudioBusMixer then
    begin
      if (FirstMixer = nil) or
         ((AWantedMixerName <> '') and SameText(C.Name, AWantedMixerName)) then
        FirstMixer := TCastleAudioBusMixer(C);
    end;

    if (C is TCastleAudioZone) and (ZoneCount < Length(Zones)) then
    begin
      Zones[ZoneCount] := TCastleAudioZone(C);
      Inc(ZoneCount);
    end;

    if (C is TCastleAudioBusRouterBehavior) and (RouterCount < Length(Routers)) then
    begin
      Routers[RouterCount] := TCastleAudioBusRouterBehavior(C);
      Inc(RouterCount);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
      begin
        B := T.Behaviors[I];
        if (B is TCastleAudioBusRouterBehavior) and (RouterCount < Length(Routers)) then
        begin
          { Avoid duplicate if also owned by C }
          if B.Owner <> C then
          begin
            Routers[RouterCount] := TCastleAudioBusRouterBehavior(B);
            Inc(RouterCount);
          end;
        end;
      end;
      for I := 0 to T.Count - 1 do
        VisitComponent(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      if C is TCastleViewport then
      begin
        VP := TCastleViewport(C);
        if VP.Items <> nil then
          VisitComponent(VP.Items);
      end;
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        VisitComponent(UI.Controls[I]);
    end;

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        VisitComponent(TCastleComponent(C).NonVisualComponents[I]);

    for I := 0 to C.ComponentCount - 1 do
    begin
      if (C.Components[I] is TCastleAudioBusMixer) or
         (C.Components[I] is TCastleAudioBusRouterBehavior) then
        VisitComponent(C.Components[I]);
    end;
  end;

  procedure Deduplicate;
  var
    I, J, WriteIdx: Integer;
    Dup: Boolean;
  begin
    WriteIdx := 0;
    for I := 0 to ZoneCount - 1 do
    begin
      Dup := false;
      for J := 0 to WriteIdx - 1 do
        if Zones[J] = Zones[I] then
        begin
          Dup := true;
          Break;
        end;
      if not Dup then
      begin
        Zones[WriteIdx] := Zones[I];
        Inc(WriteIdx);
      end;
    end;
    ZoneCount := WriteIdx;

    WriteIdx := 0;
    for I := 0 to RouterCount - 1 do
    begin
      Dup := false;
      for J := 0 to WriteIdx - 1 do
        if Routers[J] = Routers[I] then
        begin
          Dup := true;
          Break;
        end;
      if not Dup then
      begin
        Routers[WriteIdx] := Routers[I];
        Inc(WriteIdx);
      end;
    end;
    RouterCount := WriteIdx;
  end;

begin
  ZoneCount := 0;
  RouterCount := 0;
  FirstMixer := nil;
  if ANode = nil then
    Exit;
  VisitComponent(ANode);
  if (ANode.Owner <> nil) and (FirstMixer = nil) then
    VisitComponent(ANode.Owner);
  Deduplicate;
end;

{ TCastleAudioBusMixer ------------------------------------------------------- }

constructor TCastleAudioBusMixer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMasterGain := DefaultGain;
  FMusicGain := DefaultGain;
  FSfxGain := DefaultGain;
  FVoiceGain := DefaultGain;
  FAmbientGain := DefaultGain;
  FMasterMuted := false;
  FMusicMuted := false;
  FSfxMuted := false;
  FVoiceMuted := false;
  FAmbientMuted := false;
  FMusicSolo := false;
  FSfxSolo := false;
  FVoiceSolo := false;
  FAmbientSolo := false;
  FDuckMusicOnVoice := true;
  FVoiceActive := false;
  FVoiceDuckFactor := DefaultVoiceDuckFactor;
  FDuckSmoothingSpeed := DefaultDuckSmoothingSpeed;
  FDuckAmount := 0.0;
end;

function TCastleAudioBusMixer.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'MasterGain', 'MusicGain', 'SfxGain', 'VoiceGain', 'AmbientGain',
       'MasterMuted', 'MusicMuted', 'SfxMuted', 'VoiceMuted', 'AmbientMuted',
       'MusicSolo', 'SfxSolo', 'VoiceSolo', 'AmbientSolo',
       'DuckMusicOnVoice', 'VoiceActive', 'VoiceDuckFactor', 'DuckSmoothingSpeed'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleAudioBusMixer.SetMasterGain(const AValue: Single);
begin
  FMasterGain := Clamped(AValue, 0.0, 2.0);
end;

procedure TCastleAudioBusMixer.SetMusicGain(const AValue: Single);
begin
  FMusicGain := Clamped(AValue, 0.0, 2.0);
end;

procedure TCastleAudioBusMixer.SetSfxGain(const AValue: Single);
begin
  FSfxGain := Clamped(AValue, 0.0, 2.0);
end;

procedure TCastleAudioBusMixer.SetVoiceGain(const AValue: Single);
begin
  FVoiceGain := Clamped(AValue, 0.0, 2.0);
end;

procedure TCastleAudioBusMixer.SetAmbientGain(const AValue: Single);
begin
  FAmbientGain := Clamped(AValue, 0.0, 2.0);
end;

procedure TCastleAudioBusMixer.SetVoiceDuckFactor(const AValue: Single);
begin
  FVoiceDuckFactor := Clamped(AValue, 0.0, 1.0);
end;

procedure TCastleAudioBusMixer.SetDuckSmoothingSpeed(const AValue: Single);
begin
  FDuckSmoothingSpeed := Clamped(AValue, 0.5, 50.0);
end;

function TCastleAudioBusMixer.GetBusGain(
  const ABus: TCastleAudioBusKind): Single;
begin
  case ABus of
    abkMaster:  Result := FMasterGain;
    abkMusic:   Result := FMusicGain;
    abkSFX:     Result := FSfxGain;
    abkVoice:   Result := FVoiceGain;
    abkAmbient: Result := FAmbientGain;
  end;
end;

procedure TCastleAudioBusMixer.SetBusGain(
  const ABus: TCastleAudioBusKind; const AValue: Single);
begin
  case ABus of
    abkMaster:  MasterGain := AValue;
    abkMusic:   MusicGain := AValue;
    abkSFX:     SfxGain := AValue;
    abkVoice:   VoiceGain := AValue;
    abkAmbient: AmbientGain := AValue;
  end;
end;

function TCastleAudioBusMixer.GetBusMuted(
  const ABus: TCastleAudioBusKind): Boolean;
begin
  case ABus of
    abkMaster:  Result := FMasterMuted;
    abkMusic:   Result := FMusicMuted;
    abkSFX:     Result := FSfxMuted;
    abkVoice:   Result := FVoiceMuted;
    abkAmbient: Result := FAmbientMuted;
  end;
end;

procedure TCastleAudioBusMixer.SetBusMuted(
  const ABus: TCastleAudioBusKind; const AValue: Boolean);
begin
  case ABus of
    abkMaster:  FMasterMuted := AValue;
    abkMusic:   FMusicMuted := AValue;
    abkSFX:     FSfxMuted := AValue;
    abkVoice:   FVoiceMuted := AValue;
    abkAmbient: FAmbientMuted := AValue;
  end;
end;

function TCastleAudioBusMixer.GetBusSolo(
  const ABus: TCastleAudioBusKind): Boolean;
begin
  case ABus of
    abkMaster:  Result := false;
    abkMusic:   Result := FMusicSolo;
    abkSFX:     Result := FSfxSolo;
    abkVoice:   Result := FVoiceSolo;
    abkAmbient: Result := FAmbientSolo;
  end;
end;

procedure TCastleAudioBusMixer.SetBusSolo(
  const ABus: TCastleAudioBusKind; const AValue: Boolean);
begin
  case ABus of
    abkMaster:  ;
    abkMusic:   FMusicSolo := AValue;
    abkSFX:     FSfxSolo := AValue;
    abkVoice:   FVoiceSolo := AValue;
    abkAmbient: FAmbientSolo := AValue;
  end;
end;

function TCastleAudioBusMixer.AnySubBusSoloed: Boolean;
begin
  Result := FMusicSolo or FSfxSolo or FVoiceSolo or FAmbientSolo;
end;

procedure TCastleAudioBusMixer.StepDucking(const ASecondsPassed: Single;
  const AHasActiveVoice: Boolean);
var
  TargetDuck, StepAlpha: Single;
begin
  if FDuckMusicOnVoice and (FVoiceActive or AHasActiveVoice) and
     (not FVoiceMuted) and (not FMasterMuted) then
    TargetDuck := 1.0
  else
    TargetDuck := 0.0;

  if ASecondsPassed <= 0.0 then
    FDuckAmount := TargetDuck
  else
  begin
    StepAlpha := Clamped(ASecondsPassed * FDuckSmoothingSpeed, 0.0, 1.0);
    FDuckAmount := Lerp(StepAlpha, FDuckAmount, TargetDuck);
  end;
end;

function TCastleAudioBusMixer.EffectiveBusGain(
  const ABus: TCastleAudioBusKind;
  const AZoneMusicBoost: Single;
  const AZoneAmbientBoost: Single;
  const AZoneSfxBoost: Single): Single;
var
  DuckMul, EffectiveDuckAmt: Single;
begin
  if FMasterMuted or GetBusMuted(ABus) then
    Exit(0.0);

  if ABus = abkMaster then
    Exit(FMasterGain);

  if AnySubBusSoloed and (not GetBusSolo(ABus)) then
    Exit(0.0);

  Result := FMasterGain * GetBusGain(ABus);

  if FDuckMusicOnVoice and FVoiceActive and (FDuckAmount <= 0.0001) and
     (not FVoiceMuted) then
    EffectiveDuckAmt := 1.0
  else
    EffectiveDuckAmt := FDuckAmount;

  if (ABus = abkMusic) and FDuckMusicOnVoice then
  begin
    DuckMul := Lerp(EffectiveDuckAmt, 1.0, FVoiceDuckFactor);
    Result := Result * DuckMul;
  end else
  if (ABus = abkAmbient) and FDuckMusicOnVoice then
  begin
    { Gentle 50%-strength sidechain ducking on Ambient bed during dialogue }
    DuckMul := Lerp(EffectiveDuckAmt * 0.5, 1.0, FVoiceDuckFactor);
    Result := Result * DuckMul;
  end;

  case ABus of
    abkMusic:   Result := Result * Max(0.0, AZoneMusicBoost);
    abkAmbient: Result := Result * Max(0.0, AZoneAmbientBoost);
    abkSFX:     Result := Result * Max(0.0, AZoneSfxBoost);
    else ;
  end;

  Result := Clamped(Result, 0.0, 4.0);
end;

class function TCastleAudioBusMixer.EffectivePitchMultiplier(
  const APreset: TCastleAudioAcousticPreset;
  const ABlendWeight: Single): Single;
var
  PresetPitch, W: Single;
begin
  W := Clamped(ABlendWeight, 0.0, 1.0);
  case APreset of
    aapNeutral:           PresetPitch := 1.00;
    aapCaveReverb:        PresetPitch := 0.97;
    aapCathedralHall:     PresetPitch := 0.98;
    aapUnderwaterMuffled: PresetPitch := 0.85;
    aapIndoorRoom:        PresetPitch := 1.00;
    aapOutdoorWindy:      PresetPitch := 1.02;
  end;
  Result := Lerp(W, 1.0, PresetPitch);
end;

procedure TCastleAudioBusMixer.EvaluateWorldSoundscape(
  const AWorldRoot: TComponent; const AListenerWorldPos: TVector3;
  const ASecondsPassed: Single;
  out OutDominantPreset: TCastleAudioAcousticPreset;
  out OutDominantWeight: Single);
var
  Zones: array [0..255] of TCastleAudioZone;
  Routers: array [0..511] of TCastleAudioBusRouterBehavior;
  DummyMixer: TCastleAudioBusMixer;
  ZoneCount, RouterCount, I, BestPriority: Integer;
  HasVoice: Boolean;
  W, MusicBoost, AmbientBoost, SfxBoost, PitchMul, BusGainVal: Single;
begin
  OutDominantPreset := aapNeutral;
  OutDominantWeight := 0.0;
  CollectSoundscapeNodes(AWorldRoot, Zones, ZoneCount, Routers, RouterCount,
    DummyMixer, Name);

  HasVoice := false;
  for I := 0 to RouterCount - 1 do
    if (Routers[I].Bus = abkVoice) and Routers[I].IsCurrentlyAudibleSource then
    begin
      HasVoice := true;
      Break;
    end;

  StepDucking(ASecondsPassed, HasVoice);

  MusicBoost := 1.0;
  AmbientBoost := 1.0;
  SfxBoost := 1.0;
  BestPriority := Low(Integer);

  for I := 0 to ZoneCount - 1 do
  begin
    W := Zones[I].EvaluateBlendWeight(AListenerWorldPos);
    if W <= 0.0001 then
      Continue;
    MusicBoost := Lerp(W, MusicBoost, Zones[I].MusicGainMultiplier);
    AmbientBoost := Lerp(W, AmbientBoost, Zones[I].AmbientGainMultiplier);
    SfxBoost := Lerp(W, SfxBoost, Zones[I].SfxGainMultiplier);

    if (Zones[I].Priority > BestPriority) or
       ((Zones[I].Priority = BestPriority) and (W > OutDominantWeight)) then
    begin
      BestPriority := Zones[I].Priority;
      OutDominantPreset := Zones[I].AcousticPreset;
      OutDominantWeight := W;
    end;
  end;

  PitchMul := EffectivePitchMultiplier(OutDominantPreset, OutDominantWeight);

  for I := 0 to RouterCount - 1 do
  begin
    BusGainVal := EffectiveBusGain(Routers[I].Bus,
      MusicBoost, AmbientBoost, SfxBoost);
    { Voice dialogue stays crisp unless underwater }
    if (Routers[I].Bus = abkVoice) and
       (OutDominantPreset <> aapUnderwaterMuffled) then
      Routers[I].ApplyRoutedMix(BusGainVal, 1.0)
    else
      Routers[I].ApplyRoutedMix(BusGainVal, PitchMul);
  end;
end;

function TCastleAudioBusMixer.MixerSummaryBadge: String;
begin
  Result := Format('[Mixer:M=%d%% Duck=%s]',
    [Round(FMasterGain * 100.0),
     IfThen(FDuckMusicOnVoice, 'ON', 'OFF')]);
end;

{ TCastleAudioBusRouterBehavior ---------------------------------------------- }

constructor TCastleAudioBusRouterBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBus := abkSFX;
  FBaseVolume := DefaultBaseVolume;
  FBasePitch := DefaultBasePitch;
  FMixerName := '';
  FSimulatedPlaying := false;
  FLastAppliedVolume := DefaultBaseVolume;
  FLastAppliedPitch := DefaultBasePitch;
end;

function TCastleAudioBusRouterBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Bus', 'BaseVolume', 'BasePitch', 'MixerName', 'SimulatedPlaying'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleAudioBusRouterBehavior.SetBaseVolume(const AValue: Single);
begin
  FBaseVolume := Clamped(AValue, 0.0, 4.0);
end;

procedure TCastleAudioBusRouterBehavior.SetBasePitch(const AValue: Single);
begin
  FBasePitch := Clamped(AValue, 0.1, 4.0);
end;

function TCastleAudioBusRouterBehavior.ResolveMixer(
  const ASearchRoot: TComponent): TCastleAudioBusMixer;
var
  Zones: array [0..15] of TCastleAudioZone;
  Routers: array [0..15] of TCastleAudioBusRouterBehavior;
  ZC, RC: Integer;
  Root: TComponent;
begin
  Result := nil;
  if ASearchRoot <> nil then
    Root := ASearchRoot
  else if Owner <> nil then
    Root := Owner
  else
    Root := Parent;
  CollectSoundscapeNodes(Root, Zones, ZC, Routers, RC, Result, Trim(FMixerName));
end;

function TCastleAudioBusRouterBehavior.IsCurrentlyAudibleSource: Boolean;
var
  I: Integer;
  Src: TCastleSoundSource;
begin
  if FSimulatedPlaying then
    Exit(true);
  Result := false;
  if Parent = nil then
    Exit;
  for I := 0 to Parent.BehaviorsCount - 1 do
    if Parent.Behaviors[I] is TCastleSoundSource then
    begin
      Src := TCastleSoundSource(Parent.Behaviors[I]);
      if Src.SoundPlaying and (Src.Sound <> nil) then
        Exit(true);
    end;
end;

procedure TCastleAudioBusRouterBehavior.ApplyRoutedMix(
  const AEffectiveBusGain, APitchMul: Single);
var
  I: Integer;
  Src: TCastleSoundSource;
begin
  FLastAppliedVolume := Clamped(FBaseVolume * AEffectiveBusGain, 0.0, 4.0);
  FLastAppliedPitch := Clamped(FBasePitch * APitchMul, 0.05, 4.0);
  if Parent = nil then
    Exit;
  for I := 0 to Parent.BehaviorsCount - 1 do
    if Parent.Behaviors[I] is TCastleSoundSource then
    begin
      Src := TCastleSoundSource(Parent.Behaviors[I]);
      Src.Volume := FLastAppliedVolume;
      Src.Pitch := FLastAppliedPitch;
    end;
end;

procedure TCastleAudioBusRouterBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
var
  Mix: TCastleAudioBusMixer;
begin
  inherited Update(SecondsPassed, RemoveMe);
  if CastleDesignMode or (Parent = nil) then
    Exit;
  Mix := ResolveMixer(nil);
  if Mix <> nil then
    ApplyRoutedMix(Mix.EffectiveBusGain(FBus), 1.0);
end;

function TCastleAudioBusRouterBehavior.RouterSummaryBadge: String;
begin
  Result := Format('[Bus:%s]', [AudioBusKindToDisplayName(FBus)]);
end;

{ TCastleAudioZone ----------------------------------------------------------- }

constructor TCastleAudioZone.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FZoneLabel := '';
  FAcousticPreset := aapCaveReverb;
  FInnerRadius := DefaultInnerRadius;
  FOuterRadius := DefaultOuterRadius;
  FPriority := 0;
  FMusicGainMultiplier := DefaultMusicMult;
  FAmbientGainMultiplier := DefaultAmbientMult;
  FSfxGainMultiplier := DefaultSfxMult;
  FZoneEnabled := true;
  FShowZoneInViewport := true;
end;

function TCastleAudioZone.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ZoneLabel', 'AcousticPreset', 'InnerRadius', 'OuterRadius',
       'Priority', 'MusicGainMultiplier', 'AmbientGainMultiplier',
       'SfxGainMultiplier', 'ZoneEnabled', 'ShowZoneInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleAudioZone.LocalBoundingBox: TBox3D;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
    Result.Include(Box3D(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5)));
end;

procedure TCastleAudioZone.SetInnerRadius(const AValue: Single);
begin
  FInnerRadius := Max(0.0, AValue);
  if FOuterRadius < FInnerRadius then
    FOuterRadius := FInnerRadius;
end;

procedure TCastleAudioZone.SetOuterRadius(const AValue: Single);
begin
  FOuterRadius := Max(FInnerRadius, AValue);
end;

procedure TCastleAudioZone.SetMusicGainMultiplier(const AValue: Single);
begin
  FMusicGainMultiplier := Clamped(AValue, 0.0, 4.0);
end;

procedure TCastleAudioZone.SetAmbientGainMultiplier(const AValue: Single);
begin
  FAmbientGainMultiplier := Clamped(AValue, 0.0, 4.0);
end;

procedure TCastleAudioZone.SetSfxGainMultiplier(const AValue: Single);
begin
  FSfxGainMultiplier := Clamped(AValue, 0.0, 4.0);
end;

function TCastleAudioZone.EvaluateBlendWeight(
  const AListenerWorldPos: TVector3): Single;
var
  Dist, Span, T: Single;
begin
  if (not FZoneEnabled) or (not Exists) then
    Exit(0.0);

  Dist := PointsDistance(AListenerWorldPos, WorldTranslation);
  if Dist <= FInnerRadius then
    Exit(1.0);
  if Dist >= FOuterRadius then
    Exit(0.0);

  Span := FOuterRadius - FInnerRadius;
  if Span <= 0.0001 then
    Exit(0.0);

  T := Clamped((Dist - FInnerRadius) / Span, 0.0, 1.0);
  { Smooth Hermite falloff: 1 at InnerRadius -> 0 at OuterRadius }
  Result := 1.0 - (T * T * (3.0 - 2.0 * T));
end;

function TCastleAudioZone.ZoneSummaryBadge: String;
begin
  Result := Format('[AudioZone:%s %.0f..%.0fm]',
    [AudioAcousticPresetToDisplayName(FAcousticPreset),
     FInnerRadius, FOuterRadius]);
end;

initialization
  RegisterSerializableComponent(TCastleAudioBusMixer, 'Audio Bus Mixer');
  RegisterSerializableComponent(TCastleAudioBusRouterBehavior, 'Audio Bus Router');
  RegisterSerializableComponent(TCastleAudioZone, ['Audio', 'Audio Zone (Reverb / Soundscape)']);
end.
