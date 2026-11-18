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

{ Gameplay Messaging Bus with Dot-Boundary Hierarchical GameplayTag Pub/Sub,
  Squad AI Radio Bark Anti-Spam Cooldowns & Priority Preemption
  (Phase 373 — UE 6.0+ UGameplayMessageSubsystem Parity). }
unit CastleGameplayMessenger;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleClassUtils;

type
  { Squad AI radio / dialogue bark priority tiers. }
  TBarkPriority = (
    bpAmbientChatter = 0,
    bpTacticalAlert = 1,
    bpCriticalEmergency = 2
  );

  { Built-in message bus & squad radio configurations. }
  TMessengerPreset = (
    mgpCustom,
    mgpTacticalSquadComms,
    mgpStealthGuardAlertNet,
    mgpArenaAnnouncerFeed
  );

  { Published gameplay message envelope. }
  TGameplayMessageEnvelope = record
    ChannelTag: String;
    SenderName: String;
    MagnitudeValue: Single;
    PayloadText: String;
  end;

  { Registered channel listener entry. }
  TGameplayChannelSubscription = record
    SubscriberId: String;
    ChannelTagFilter: String;
    MatchSubChannels: Boolean;
    DeliveredCount: Integer;
    LastSenderName: String;
    LastPayloadText: String;
    LastMagnitude: Single;
  end;

  { Active squad bark currently occupying the voice radio channel. }
  TActiveSquadBark = record
    BarkTag: String;
    SpeakerName: String;
    SubtitleText: String;
    Priority: TBarkPriority;
    RemainingDurationSec: Single;
  end;

  { Per-bark-tag anti-spam cooldown timer. }
  TBarkTagCooldown = record
    BarkTag: String;
    RemainingCooldownSec: Single;
  end;

  { Decoupled GameplayTag pub/sub router + squad voice bark arbiter. }
  TCastleGameplayMessenger = class(TCastleTransform)
  private
    FPreset: TMessengerPreset;
    FDefaultBarkCooldownSec: Single;
    FMaxHistoryLogCount: Integer;
    FSubscriptions: array of TGameplayChannelSubscription;
    FCooldowns: array of TBarkTagCooldown;
    FMessageLog: TStringList;
    FHasActiveBark: Boolean;
    FActiveBark: TActiveSquadBark;
    FTotalBroadcastCount: Integer;
    FSuppressedSpamCount: Integer;
    FPreemptionCount: Integer;
    procedure SetPreset(const AValue: TMessengerPreset);
    procedure SetDefaultBarkCooldownSec(const AValue: Single);
    procedure SetMaxHistoryLogCount(const AValue: Integer);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetChannels(const APreset: TMessengerPreset);
    class function ChannelMatchesFilter(const APublishedTag, AFilterTag: String;
      const AMatchSubChannels: Boolean): Boolean;
    function FindCooldownRemaining(const ABarkTag: String): Single;
    procedure SetTagCooldown(const ABarkTag: String; const ADurationSec: Single);
    procedure AppendHistoryLine(const ALine: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ClearAllState;
    function RegisterChannelSubscription(const ASubscriberId, AChannelTagFilter: String;
      const AMatchSubChannels: Boolean = True): Integer;
    function BroadcastGameplayMessage(const AChannelTag, ASenderName: String;
      const AMagnitudeValue: Single; const APayloadText: String): Integer;
    function RequestSquadBark(const ABarkTag, ASpeakerName, ASubtitleText: String;
      const APriority: TBarkPriority;
      const ADurationSec, ACooldownSec: Single;
      out OutDropReason: String): Boolean;
    procedure StepMessenger(const Dt: Single);
    function SubscriptionCount: Integer;
    function GetSubscription(const AIndex: Integer): TGameplayChannelSubscription;
    function FindSubscriptionById(const ASubscriberId: String;
      out OutSub: TGameplayChannelSubscription): Boolean;
    function HistoryLineCount: Integer;
    function GetHistoryLine(const AIndex: Integer): String;
    function MessengerSummaryBadge: String;
    property HasActiveBark: Boolean read FHasActiveBark;
    property ActiveBark: TActiveSquadBark read FActiveBark;
    property TotalBroadcastCount: Integer read FTotalBroadcastCount;
    property SuppressedSpamCount: Integer read FSuppressedSpamCount;
    property PreemptionCount: Integer read FPreemptionCount;
  published
    property Preset: TMessengerPreset read FPreset write SetPreset default mgpTacticalSquadComms;
    property DefaultBarkCooldownSec: Single read FDefaultBarkCooldownSec write SetDefaultBarkCooldownSec {$ifdef FPC}default 6.0{$endif};
    property MaxHistoryLogCount: Integer read FMaxHistoryLogCount write SetMaxHistoryLogCount default 32;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function MessengerPresetToString(const APreset: TMessengerPreset): String;
function BarkPriorityToString(const APrio: TBarkPriority): String;

implementation

uses fpjson, jsonparser, CastleComponentSerialize;

function MessengerPresetToString(const APreset: TMessengerPreset): String;
begin
  case APreset of
    mgpCustom: Result := 'Custom Gameplay Message Bus';
    mgpTacticalSquadComms: Result := 'Tactical Squad Comms & Combat Pub/Sub';
    mgpStealthGuardAlertNet: Result := 'Stealth Guard Suspicion & Alarm Net';
    mgpArenaAnnouncerFeed: Result := 'Arena Killstreak Announcer Priority Feed';
  end;
end;

function BarkPriorityToString(const APrio: TBarkPriority): String;
begin
  case APrio of
    bpAmbientChatter: Result := 'Ambient';
    bpTacticalAlert: Result := 'Tactical';
    bpCriticalEmergency: Result := 'EMERGENCY';
  end;
end;

{ TCastleGameplayMessenger ---------------------------------------------------- }

constructor TCastleGameplayMessenger.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMessageLog := TStringList.Create;
  FDefaultBarkCooldownSec := 6.0;
  FMaxHistoryLogCount := 32;
  ApplyPresetChannels(mgpTacticalSquadComms);
end;

destructor TCastleGameplayMessenger.Destroy;
begin
  FreeAndNil(FMessageLog);
  inherited Destroy;
end;

procedure TCastleGameplayMessenger.ClearAllState;
begin
  SetLength(FSubscriptions, 0);
  SetLength(FCooldowns, 0);
  FMessageLog.Clear;
  FHasActiveBark := False;
  FillChar(FActiveBark, SizeOf(FActiveBark), 0);
  FTotalBroadcastCount := 0;
  FSuppressedSpamCount := 0;
  FPreemptionCount := 0;
  FPreset := mgpCustom;
end;

procedure TCastleGameplayMessenger.ApplyPresetChannels(const APreset: TMessengerPreset);
begin
  ClearAllState;
  case APreset of
    mgpTacticalSquadComms, mgpCustom:
      begin
        FDefaultBarkCooldownSec := 6.0;
        RegisterChannelSubscription('HudDamageListener', 'Combat.Damage', True);
        RegisterChannelSubscription('QuestKillTracker', 'Combat.Elimination', True);
        RegisterChannelSubscription('SubtitleOverlay', 'Audio.Bark', True);
        FPreset := APreset;
      end;
    mgpStealthGuardAlertNet:
      begin
        FDefaultBarkCooldownSec := 8.0;
        RegisterChannelSubscription('OverwatchCommander', 'Stealth.Alert', True);
        RegisterChannelSubscription('MusicTensionDirector', 'Stealth.Alert.Siren', False);
        FPreset := mgpStealthGuardAlertNet;
      end;
    mgpArenaAnnouncerFeed:
      begin
        FDefaultBarkCooldownSec := 4.5;
        RegisterChannelSubscription('ScoreboardWidget', 'Arena.Score', True);
        RegisterChannelSubscription('CrowdCheerSystem', 'Arena.Streak', True);
        FPreset := mgpArenaAnnouncerFeed;
      end;
  end;
end;

procedure TCastleGameplayMessenger.SetPreset(const AValue: TMessengerPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> mgpCustom then
    ApplyPresetChannels(AValue);
end;

procedure TCastleGameplayMessenger.SetDefaultBarkCooldownSec(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 120.0);
  if SameValue(FDefaultBarkCooldownSec, V, 1e-4) then Exit;
  FDefaultBarkCooldownSec := V;
  FPreset := mgpCustom;
end;

procedure TCastleGameplayMessenger.SetMaxHistoryLogCount(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 4, 256);
  if FMaxHistoryLogCount = V then Exit;
  FMaxHistoryLogCount := V;
end;

procedure TCastleGameplayMessenger.AppendHistoryLine(const ALine: String);
begin
  FMessageLog.Add(ALine);
  while FMessageLog.Count > FMaxHistoryLogCount do
    FMessageLog.Delete(0);
end;

class function TCastleGameplayMessenger.ChannelMatchesFilter(
  const APublishedTag, AFilterTag: String;
  const AMatchSubChannels: Boolean): Boolean;
var
  PubL, FilL: String;
  FilLen: Integer;
begin
  PubL := LowerCase(Trim(APublishedTag));
  FilL := LowerCase(Trim(AFilterTag));
  if (PubL = '') or (FilL = '') then Exit(False);
  if PubL = FilL then Exit(True);
  if not AMatchSubChannels then Exit(False);
  FilLen := Length(FilL);
  Result := (Length(PubL) > FilLen) and (Copy(PubL, 1, FilLen + 1) = FilL + '.');
end;

function TCastleGameplayMessenger.RegisterChannelSubscription(
  const ASubscriberId, AChannelTagFilter: String;
  const AMatchSubChannels: Boolean): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSubscriptions) do
    if SameText(FSubscriptions[I].SubscriberId, ASubscriberId) then
    begin
      FSubscriptions[I].ChannelTagFilter := Trim(AChannelTagFilter);
      FSubscriptions[I].MatchSubChannels := AMatchSubChannels;
      FPreset := mgpCustom;
      Exit(I);
    end;

  Result := Length(FSubscriptions);
  SetLength(FSubscriptions, Result + 1);
  FSubscriptions[Result].SubscriberId := ASubscriberId;
  FSubscriptions[Result].ChannelTagFilter := Trim(AChannelTagFilter);
  FSubscriptions[Result].MatchSubChannels := AMatchSubChannels;
  FSubscriptions[Result].DeliveredCount := 0;
  FSubscriptions[Result].LastSenderName := '';
  FSubscriptions[Result].LastPayloadText := '';
  FSubscriptions[Result].LastMagnitude := 0.0;
  FPreset := mgpCustom;
end;

function TCastleGameplayMessenger.BroadcastGameplayMessage(
  const AChannelTag, ASenderName: String;
  const AMagnitudeValue: Single; const APayloadText: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  Inc(FTotalBroadcastCount);
  for I := 0 to High(FSubscriptions) do
    if ChannelMatchesFilter(AChannelTag, FSubscriptions[I].ChannelTagFilter,
         FSubscriptions[I].MatchSubChannels) then
    begin
      Inc(FSubscriptions[I].DeliveredCount);
      FSubscriptions[I].LastSenderName := ASenderName;
      FSubscriptions[I].LastPayloadText := APayloadText;
      FSubscriptions[I].LastMagnitude := AMagnitudeValue;
      Inc(Result);
    end;

  AppendHistoryLine(Format('[MSG %s] from %s (%.1f): "%s" -> %d listener(s)', [
    AChannelTag, ASenderName, AMagnitudeValue, APayloadText, Result]));
end;

function TCastleGameplayMessenger.FindCooldownRemaining(const ABarkTag: String): Single;
var
  I: Integer;
begin
  for I := 0 to High(FCooldowns) do
    if SameText(FCooldowns[I].BarkTag, ABarkTag) then
      Exit(FCooldowns[I].RemainingCooldownSec);
  Result := 0.0;
end;

procedure TCastleGameplayMessenger.SetTagCooldown(
  const ABarkTag: String; const ADurationSec: Single);
var
  I, N: Integer;
begin
  if ADurationSec <= 0.001 then Exit;
  for I := 0 to High(FCooldowns) do
    if SameText(FCooldowns[I].BarkTag, ABarkTag) then
    begin
      FCooldowns[I].RemainingCooldownSec := ADurationSec;
      Exit;
    end;
  N := Length(FCooldowns);
  SetLength(FCooldowns, N + 1);
  FCooldowns[N].BarkTag := ABarkTag;
  FCooldowns[N].RemainingCooldownSec := ADurationSec;
end;

function TCastleGameplayMessenger.RequestSquadBark(
  const ABarkTag, ASpeakerName, ASubtitleText: String;
  const APriority: TBarkPriority;
  const ADurationSec, ACooldownSec: Single;
  out OutDropReason: String): Boolean;
var
  EffCd: Single;
begin
  OutDropReason := '';
  if FindCooldownRemaining(ABarkTag) > 0.001 then
  begin
    Inc(FSuppressedSpamCount);
    OutDropReason := 'SUPPRESSED_TAG_COOLDOWN';
    Exit(False);
  end;

  if FHasActiveBark then
  begin
    if Ord(APriority) <= Ord(FActiveBark.Priority) then
    begin
      Inc(FSuppressedSpamCount);
      OutDropReason := 'CHANNEL_BUSY_HIGHER_OR_EQUAL_PRIORITY';
      Exit(False);
    end;
    { Strictly higher priority preempts current speaker! }
    Inc(FPreemptionCount);
  end;

  if ACooldownSec >= 0.0 then
    EffCd := ACooldownSec
  else
    EffCd := FDefaultBarkCooldownSec;

  FHasActiveBark := True;
  FActiveBark.BarkTag := ABarkTag;
  FActiveBark.SpeakerName := ASpeakerName;
  FActiveBark.SubtitleText := ASubtitleText;
  FActiveBark.Priority := APriority;
  FActiveBark.RemainingDurationSec := Max(0.2, ADurationSec);
  SetTagCooldown(ABarkTag, EffCd);

  BroadcastGameplayMessage('Audio.Bark.Started', ASpeakerName, Ord(APriority), ASubtitleText);
  Result := True;
end;

procedure TCastleGameplayMessenger.StepMessenger(const Dt: Single);
var
  I, WriteIdx: Integer;
begin
  if Dt <= 0.0 then Exit;

  if FHasActiveBark then
  begin
    FActiveBark.RemainingDurationSec := FActiveBark.RemainingDurationSec - Dt;
    if FActiveBark.RemainingDurationSec <= 0.0 then
    begin
      FHasActiveBark := False;
      FillChar(FActiveBark, SizeOf(FActiveBark), 0);
    end;
  end;

  WriteIdx := 0;
  for I := 0 to High(FCooldowns) do
  begin
    FCooldowns[I].RemainingCooldownSec := FCooldowns[I].RemainingCooldownSec - Dt;
    if FCooldowns[I].RemainingCooldownSec > 0.001 then
    begin
      FCooldowns[WriteIdx] := FCooldowns[I];
      Inc(WriteIdx);
    end;
  end;
  SetLength(FCooldowns, WriteIdx);
end;

function TCastleGameplayMessenger.SubscriptionCount: Integer;
begin
  Result := Length(FSubscriptions);
end;

function TCastleGameplayMessenger.GetSubscription(
  const AIndex: Integer): TGameplayChannelSubscription;
begin
  if (AIndex >= 0) and (AIndex < Length(FSubscriptions)) then
    Result := FSubscriptions[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleGameplayMessenger.FindSubscriptionById(const ASubscriberId: String;
  out OutSub: TGameplayChannelSubscription): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FSubscriptions) do
    if SameText(FSubscriptions[I].SubscriberId, ASubscriberId) then
    begin
      OutSub := FSubscriptions[I];
      Exit(True);
    end;
  FillChar(OutSub, SizeOf(OutSub), 0);
  Result := False;
end;

function TCastleGameplayMessenger.HistoryLineCount: Integer;
begin
  Result := FMessageLog.Count;
end;

function TCastleGameplayMessenger.GetHistoryLine(const AIndex: Integer): String;
begin
  if (AIndex >= 0) and (AIndex < FMessageLog.Count) then
    Result := FMessageLog[AIndex]
  else
    Result := '';
end;

function TCastleGameplayMessenger.GetConfigJson: String;
var
  RootObj, SObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('defBarkCd', FDefaultBarkCooldownSec);
    RootObj.Add('maxLog', FMaxHistoryLogCount);
    Arr := TJSONArray.Create;
    for I := 0 to High(FSubscriptions) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('id', FSubscriptions[I].SubscriberId);
      SObj.Add('filter', FSubscriptions[I].ChannelTagFilter);
      SObj.Add('sub', FSubscriptions[I].MatchSubChannels);
      Arr.Add(SObj);
    end;
    RootObj.Add('subs', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleGameplayMessenger.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, SObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FDefaultBarkCooldownSec := EnsureRange(RootObj.Get('defBarkCd', FDefaultBarkCooldownSec), 0.0, 120.0);
      FMaxHistoryLogCount := EnsureRange(RootObj.Get('maxLog', FMaxHistoryLogCount), 4, 256);
      Arr := RootObj.Find('subs', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        SetLength(FSubscriptions, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            SObj := TJSONObject(Arr.Items[I]);
            FSubscriptions[I].SubscriberId := SObj.Get('id', '');
            FSubscriptions[I].ChannelTagFilter := SObj.Get('filter', '');
            FSubscriptions[I].MatchSubChannels := SObj.Get('sub', True);
            FSubscriptions[I].DeliveredCount := 0;
          end;
      end;
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TMessengerPreset))) and
         (PresetOrd <= Ord(High(TMessengerPreset))) then
        FPreset := TMessengerPreset(PresetOrd);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleGameplayMessenger.MessengerSummaryBadge: String;
begin
  Result := Format('[MsgBus:%d subs %d sent %d spam-blocked]', [
    SubscriptionCount,
    FTotalBroadcastCount,
    FSuppressedSpamCount]);
end;

initialization
  RegisterSerializableComponent(TCastleGameplayMessenger, ['AI & Gameplay', 'Gameplay Message Bus & Bark Router']);
end.
