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

{ Design-time soundscape discovery, 1-click bus mixer & acoustic zone
  creation, submix presets, and Markdown reporting for
  @link(TCastleAudioBusMixer), @link(TCastleAudioBusRouterBehavior), and
  @link(TCastleAudioZone) (Phase 291). }
unit ToolAudioMixer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleAudioMixer;

type
  TAudioMixerArray = array of TCastleAudioBusMixer;
  TAudioZoneArray = array of TCastleAudioZone;
  TAudioRouterArray = array of TCastleAudioBusRouterBehavior;

  { Snapshot of the design's audio buses, zones, routed sources, and active
    listener soundscape blend. }
  TAudioMixerSummary = record
    Mixers: TAudioMixerArray;
    Zones: TAudioZoneArray;
    Routers: TAudioRouterArray;
    DominantPreset: TCastleAudioAcousticPreset;
    DominantWeight: Single;
    TotalSoundSources: Integer;
    UnroutedSoundSources: Integer;
    Warnings: array of String;
  end;

  TAudioMixerHelper = class
  public
    { Discover all mixers, audio zones, routed behaviors, and unrouted
      @code(TCastleSoundSource) instances in @code(ARoot). }
    class function ScanAudioSoundscape(const ARoot: TComponent;
      const AListenerWorldPos: TVector3): TAudioMixerSummary;

    { Return existing @link(TCastleAudioBusMixer) or create a new one inside
      the design's non-visual components / @code(ARoot). }
    class function EnsureMixerInDesign(const ARoot, ADesignOwner: TComponent): TCastleAudioBusMixer;

    { Spawn a @link(TCastleAudioZone) inside @code(ARoot)'s 3D world. }
    class function CreateAudioZoneInDesign(const ARoot, ADesignOwner: TComponent;
      const AWorldPos: TVector3;
      const APreset: TCastleAudioAcousticPreset = aapCaveReverb): TCastleAudioZone;

    { Attach (or update) a @link(TCastleAudioBusRouterBehavior) on
      @code(ATarget) routed to @code(ABus). }
    class function AttachBusRouter(const ATarget: TCastleTransform;
      const ADesignOwner: TComponent; const ABus: TCastleAudioBusKind;
      const AMixerName: String = ''): TCastleAudioBusRouterBehavior;

    { Pick the first suitable non-camera gameplay @link(TCastleTransform) in
      @code(ARoot) when no transform is explicitly selected. }
    class function FindFirstRoutableTransform(const ARoot: TComponent): TCastleTransform;

    { Apply one of 4 curated mix presets:
      0 = Balanced Gameplay, 1 = Cutscene Dialogue Focus,
      2 = Combat Action Boost, 3 = Exploration Ambient. }
    class procedure ApplySoundscapeMixPreset(const AMixer: TCastleAudioBusMixer;
      const APresetIndex: Integer);

    { Generate a Markdown audio routing & acoustic zone audit report. }
    class function FormatAudioSoundscapeMarkdown(const ARoot: TComponent;
      const AListenerWorldPos: TVector3): String;
  end;

implementation

uses
  StrUtils,
  CastleClassUtils, CastleBehaviors, CastleUIControls, CastleViewport;

function ProposeUniqueAudioName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindWorldItemsContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindWorldItemsContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ TAudioMixerHelper ---------------------------------------------------------- }

class function TAudioMixerHelper.ScanAudioSoundscape(const ARoot: TComponent;
  const AListenerWorldPos: TVector3): TAudioMixerSummary;

  procedure AppendWarning(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(Result.Warnings);
    SetLength(Result.Warnings, N + 1);
    Result.Warnings[N] := Msg;
  end;

  procedure AddUniqueMixer(const M: TCastleAudioBusMixer);
  var
    I: Integer;
  begin
    for I := 0 to High(Result.Mixers) do
      if Result.Mixers[I] = M then
        Exit;
    SetLength(Result.Mixers, Length(Result.Mixers) + 1);
    Result.Mixers[High(Result.Mixers)] := M;
  end;

  procedure AddUniqueZone(const Z: TCastleAudioZone);
  var
    I: Integer;
  begin
    for I := 0 to High(Result.Zones) do
      if Result.Zones[I] = Z then
        Exit;
    SetLength(Result.Zones, Length(Result.Zones) + 1);
    Result.Zones[High(Result.Zones)] := Z;
  end;

  procedure AddUniqueRouter(const R: TCastleAudioBusRouterBehavior);
  var
    I: Integer;
  begin
    for I := 0 to High(Result.Routers) do
      if Result.Routers[I] = R then
        Exit;
    SetLength(Result.Routers, Length(Result.Routers) + 1);
    Result.Routers[High(Result.Routers)] := R;
  end;

var
  Visited: array of TComponent;

  function MarkVisited(const C: TComponent): Boolean;
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

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
    HasSoundSrc, HasRouter: Boolean;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) or (not MarkVisited(C)) then
      Exit;

    if C is TCastleAudioBusMixer then
      AddUniqueMixer(TCastleAudioBusMixer(C))
    else if C is TCastleAudioZone then
      AddUniqueZone(TCastleAudioZone(C))
    else if C is TCastleAudioBusRouterBehavior then
      AddUniqueRouter(TCastleAudioBusRouterBehavior(C));

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      HasSoundSrc := false;
      HasRouter := false;
      for I := 0 to T.BehaviorsCount - 1 do
      begin
        if T.Behaviors[I] is TCastleSoundSource then
        begin
          HasSoundSrc := true;
          Inc(Result.TotalSoundSources);
        end else
        if T.Behaviors[I] is TCastleAudioBusRouterBehavior then
        begin
          HasRouter := true;
          AddUniqueRouter(TCastleAudioBusRouterBehavior(T.Behaviors[I]));
        end;
      end;
      if HasSoundSrc and (not HasRouter) then
        Inc(Result.UnroutedSoundSources);

      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      if C is TCastleViewport then
      begin
        VP := TCastleViewport(C);
        if VP.Items <> nil then
          Visit(VP.Items);
      end;
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Visit(TCastleComponent(C).NonVisualComponents[I]);

    for I := 0 to C.ComponentCount - 1 do
      if (C.Components[I] is TCastleAudioBusMixer) or
         (C.Components[I] is TCastleComponent) then
        Visit(C.Components[I]);
  end;

var
  I, BestPrio: Integer;
  W: Single;
begin
  Result := Default(TAudioMixerSummary);
  Result.DominantPreset := aapNeutral;
  Result.DominantWeight := 0.0;
  if ARoot = nil then
    Exit;

  Visit(ARoot);
  if ARoot.Owner <> nil then
    for I := 0 to ARoot.Owner.ComponentCount - 1 do
      if ARoot.Owner.Components[I] is TCastleAudioBusMixer then
        AddUniqueMixer(TCastleAudioBusMixer(ARoot.Owner.Components[I]));

  BestPrio := Low(Integer);
  for I := 0 to High(Result.Zones) do
  begin
    W := Result.Zones[I].EvaluateBlendWeight(AListenerWorldPos);
    if (W > 0.0001) and
       ((Result.Zones[I].Priority > BestPrio) or
        ((Result.Zones[I].Priority = BestPrio) and (W > Result.DominantWeight))) then
    begin
      BestPrio := Result.Zones[I].Priority;
      Result.DominantPreset := Result.Zones[I].AcousticPreset;
      Result.DominantWeight := W;
    end;
  end;

  if (Length(Result.Routers) > 0) and (Length(Result.Mixers) = 0) then
    AppendWarning('Audio Bus Routers exist, but no TCastleAudioBusMixer was found in the design.');
  if Result.UnroutedSoundSources > 0 then
    AppendWarning(Format('%d TCastleSoundSource transform(s) have no TCastleAudioBusRouterBehavior attached.',
      [Result.UnroutedSoundSources]));
end;

class function TAudioMixerHelper.EnsureMixerInDesign(
  const ARoot, ADesignOwner: TComponent): TCastleAudioBusMixer;
var
  Sum: TAudioMixerSummary;
  OwnerToUse: TComponent;
  CompRoot: TCastleComponent;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  Sum := ScanAudioSoundscape(ARoot, TVector3.Zero);
  if Length(Sum.Mixers) > 0 then
    Exit(Sum.Mixers[0]);

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastleAudioBusMixer.Create(OwnerToUse);
  Result.Name := ProposeUniqueAudioName(OwnerToUse, 'AudioBusMixer');

  if ARoot is TCastleComponent then
  begin
    CompRoot := TCastleComponent(ARoot);
    CompRoot.AddNonVisualComponent(Result);
  end;
end;

class function TAudioMixerHelper.CreateAudioZoneInDesign(
  const ARoot, ADesignOwner: TComponent; const AWorldPos: TVector3;
  const APreset: TCastleAudioAcousticPreset): TCastleAudioZone;
var
  Container: TCastleTransform;
  OwnerToUse: TComponent;
begin
  Result := nil;
  Container := FindWorldItemsContainer(ARoot);
  if Container = nil then
    Exit;

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastleAudioZone.Create(OwnerToUse);
  Result.Name := ProposeUniqueAudioName(OwnerToUse, 'AudioZone');
  Result.AcousticPreset := APreset;
  Result.ZoneLabel := AudioAcousticPresetToDisplayName(APreset);
  Result.Translation := AWorldPos;
  Container.Add(Result);
end;

class function TAudioMixerHelper.AttachBusRouter(const ATarget: TCastleTransform;
  const ADesignOwner: TComponent; const ABus: TCastleAudioBusKind;
  const AMixerName: String): TCastleAudioBusRouterBehavior;
var
  OwnerToUse: TComponent;
  Existing: TCastleBehavior;
begin
  Result := nil;
  if ATarget = nil then
    Exit;

  Existing := ATarget.FindBehavior(TCastleAudioBusRouterBehavior);
  if Existing is TCastleAudioBusRouterBehavior then
  begin
    Result := TCastleAudioBusRouterBehavior(Existing);
    Result.Bus := ABus;
    if AMixerName <> '' then
      Result.MixerName := AMixerName;
    Exit;
  end;

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else if ATarget.Owner <> nil then
    OwnerToUse := ATarget.Owner
  else
    OwnerToUse := ATarget;

  Result := TCastleAudioBusRouterBehavior.Create(OwnerToUse);
  Result.Name := ProposeUniqueAudioName(OwnerToUse, 'AudioBusRouter');
  Result.Bus := ABus;
  Result.MixerName := AMixerName;
  ATarget.AddBehavior(Result);
end;

class function TAudioMixerHelper.FindFirstRoutableTransform(
  const ARoot: TComponent): TCastleTransform;

  function SearchPass(const Node: TCastleTransform;
    const PreferWithSoundSource: Boolean): TCastleTransform;
  var
    I: Integer;
  begin
    Result := nil;
    if (Node = nil) or (csTransient in Node.ComponentStyle) then
      Exit;
    if (not (Node is TCastleCamera)) and
       (not (Node is TCastleAudioZone)) and
       (Node.Name <> '') then
    begin
      if (not PreferWithSoundSource) or
         (Node.FindBehavior(TCastleSoundSource) <> nil) then
        Exit(Node);
    end;
    for I := 0 to Node.Count - 1 do
    begin
      Result := SearchPass(Node[I], PreferWithSoundSource);
      if Result <> nil then
        Exit;
    end;
  end;

var
  Container: TCastleTransform;
  I: Integer;
begin
  Result := nil;
  Container := FindWorldItemsContainer(ARoot);
  if Container = nil then
    Exit;

  for I := 0 to Container.Count - 1 do
  begin
    Result := SearchPass(Container[I], true);
    if Result <> nil then
      Exit;
  end;
  for I := 0 to Container.Count - 1 do
  begin
    Result := SearchPass(Container[I], false);
    if Result <> nil then
      Exit;
  end;
end;

class procedure TAudioMixerHelper.ApplySoundscapeMixPreset(
  const AMixer: TCastleAudioBusMixer; const APresetIndex: Integer);
begin
  if AMixer = nil then
    Exit;
  AMixer.MasterMuted := false;
  AMixer.MusicMuted := false;
  AMixer.SfxMuted := false;
  AMixer.VoiceMuted := false;
  AMixer.AmbientMuted := false;
  AMixer.MusicSolo := false;
  AMixer.SfxSolo := false;
  AMixer.VoiceSolo := false;
  AMixer.AmbientSolo := false;

  case APresetIndex of
    0: { Balanced Gameplay }
      begin
        AMixer.MasterGain := 1.00;
        AMixer.MusicGain := 0.80;
        AMixer.SfxGain := 1.00;
        AMixer.VoiceGain := 1.10;
        AMixer.AmbientGain := 0.75;
        AMixer.DuckMusicOnVoice := true;
        AMixer.VoiceDuckFactor := 0.30;
      end;
    1: { Cutscene Dialogue Focus }
      begin
        AMixer.MasterGain := 1.00;
        AMixer.MusicGain := 0.65;
        AMixer.SfxGain := 0.60;
        AMixer.VoiceGain := 1.35;
        AMixer.AmbientGain := 0.50;
        AMixer.DuckMusicOnVoice := true;
        AMixer.VoiceDuckFactor := 0.20;
      end;
    2: { Combat Action Boost }
      begin
        AMixer.MasterGain := 1.05;
        AMixer.MusicGain := 1.10;
        AMixer.SfxGain := 1.30;
        AMixer.VoiceGain := 1.15;
        AMixer.AmbientGain := 0.45;
        AMixer.DuckMusicOnVoice := true;
        AMixer.VoiceDuckFactor := 0.45;
      end;
    3: { Exploration Ambient }
      begin
        AMixer.MasterGain := 1.00;
        AMixer.MusicGain := 0.55;
        AMixer.SfxGain := 0.85;
        AMixer.VoiceGain := 1.00;
        AMixer.AmbientGain := 1.25;
        AMixer.DuckMusicOnVoice := true;
        AMixer.VoiceDuckFactor := 0.35;
      end;
  end;
end;

class function TAudioMixerHelper.FormatAudioSoundscapeMarkdown(
  const ARoot: TComponent; const AListenerWorldPos: TVector3): String;
var
  Sum: TAudioMixerSummary;
  SB: TStringBuilder;
  M: TCastleAudioBusMixer;
  Bus: TCastleAudioBusKind;
  I: Integer;
begin
  Sum := ScanAudioSoundscape(ARoot, AListenerWorldPos);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Spatial Audio Soundscape Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Mixers**: `%d` | **Audio Zones**: `%d` | **Routed Sources**: `%d` | **Unrouted Sources**: `%d`',
      [Length(Sum.Mixers), Length(Sum.Zones), Length(Sum.Routers), Sum.UnroutedSoundSources]));
    SB.AppendLine(Format('- **Dominant Acoustic Zone @ Listener**: `%s` (`%.0f%%` weight)',
      [AudioAcousticPresetToDisplayName(Sum.DominantPreset), Sum.DominantWeight * 100.0]));
    SB.AppendLine;

    if Length(Sum.Mixers) > 0 then
    begin
      M := Sum.Mixers[0];
      SB.AppendLine('## Submix Bus Gains (`' + M.Name + '`)');
      SB.AppendLine;
      SB.AppendLine('| Bus | Fader | dB | Mute | Solo | Effective Gain |');
      SB.AppendLine('| :--- | :---: | :---: | :---: | :---: | :---: |');
      for Bus := Low(TCastleAudioBusKind) to High(TCastleAudioBusKind) do
        SB.AppendLine(Format('| **%s** | `%.0f%%` | `%s` | `%s` | `%s` | `%.2f` |',
          [AudioBusKindToDisplayName(Bus),
           M.GetBusGain(Bus) * 100.0,
           LinearGainToDecibelsStr(M.GetBusGain(Bus)),
           IfThen(M.GetBusMuted(Bus), 'MUTE', '-'),
           IfThen(M.GetBusSolo(Bus), 'SOLO', '-'),
           M.EffectiveBusGain(Bus)]));
      SB.AppendLine;
    end;

    if Length(Sum.Zones) > 0 then
    begin
      SB.AppendLine('## Spatial Acoustic Zones');
      SB.AppendLine;
      for I := 0 to High(Sum.Zones) do
        SB.AppendLine(Format('- **`%s`** (`%s`): Inner `%.1fm` / Outer `%.1fm` | Listener Weight `%.0f%%`',
          [Sum.Zones[I].Name,
           AudioAcousticPresetToDisplayName(Sum.Zones[I].AcousticPreset),
           Sum.Zones[I].InnerRadius,
           Sum.Zones[I].OuterRadius,
           Sum.Zones[I].EvaluateBlendWeight(AListenerWorldPos) * 100.0]));
      SB.AppendLine;
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Diagnostics');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- **Warning**: ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
