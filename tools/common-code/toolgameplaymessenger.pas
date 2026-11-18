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

{ Stateless helper for Gameplay Message Bus & Squad Bark Queue Studio (Phase 373). }
unit ToolGameplayMessenger;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleTransform, CastleViewport,
  CastleGameplayMessenger;

type
  TGameplayMessengerHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindMessengerInHierarchy(const Root: TComponent): TCastleGameplayMessenger;
    class function SpawnSquadCommsBusDemo(const Root, DesignOwner: TComponent;
      out Messenger: TCastleGameplayMessenger): Boolean;
    class function GenerateMessengerReport(const Messenger: TCastleGameplayMessenger): String;
  end;

implementation

class function TGameplayMessengerHelper.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TGameplayMessengerHelper.FindMessengerInHierarchy(
  const Root: TComponent): TCastleGameplayMessenger;

  function WalkTransform(const T: TCastleTransform): TCastleGameplayMessenger;
  var
    I: Integer;
  begin
    if T is TCastleGameplayMessenger then
      Exit(TCastleGameplayMessenger(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleGameplayMessenger then Exit(TCastleGameplayMessenger(Root));
  if Root is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(Root));
    if Result <> nil then Exit;
  end;
  Vp := FindViewport(Root);
  if (Vp <> nil) and (Vp.Items <> nil) then
  begin
    Result := WalkTransform(Vp.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to Root.ComponentCount - 1 do
    if Root.Components[I] is TCastleGameplayMessenger then
      Exit(TCastleGameplayMessenger(Root.Components[I]));
end;

class function TGameplayMessengerHelper.SpawnSquadCommsBusDemo(
  const Root, DesignOwner: TComponent;
  out Messenger: TCastleGameplayMessenger): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
begin
  Result := False;
  Messenger := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  Messenger := FindMessengerInHierarchy(Root);
  if Messenger = nil then
  begin
    Messenger := TCastleGameplayMessenger.Create(OwnerComp);
    Messenger.Name := 'GameplayMessenger1';
    Messenger.Preset := mgpTacticalSquadComms;
    Vp.Items.Add(Messenger);
  end;
  Result := True;
end;

class function TGameplayMessengerHelper.GenerateMessengerReport(
  const Messenger: TCastleGameplayMessenger): String;
var
  I: Integer;
  Sub: TGameplayChannelSubscription;
  ActiveStr: String;
begin
  if Messenger = nil then
    Exit('# Gameplay Message Bus & Squad Bark Report' + LineEnding + LineEnding +
         '_No `TCastleGameplayMessenger` found in design._');

  if Messenger.HasActiveBark then
    ActiveStr := Format('`%s` [%s]: "%s" (`%.1fs` left)', [
      Messenger.ActiveBark.SpeakerName,
      BarkPriorityToString(Messenger.ActiveBark.Priority),
      Messenger.ActiveBark.SubtitleText,
      Messenger.ActiveBark.RemainingDurationSec])
  else
    ActiveStr := '_(Radio channel clear)_';

  Result :=
    '# Gameplay Message Bus & Squad Radio Bark Report (Phase 373)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Messenger.Name, MessengerPresetToString(Messenger.Preset)]) + LineEnding +
    Format('| **Broadcasts / Anti-Spam** | `%d` broadcasts / **`%d` spam-suppressed** / `%d` preemptions |', [
      Messenger.TotalBroadcastCount, Messenger.SuppressedSpamCount, Messenger.PreemptionCount]) + LineEnding +
    Format('| **Active Squad Radio Bark** | %s |', [ActiveStr]) + LineEnding + LineEnding +
    '## Registered Channel Subscribers' + LineEnding +
    '| Subscriber ID | Channel Filter | Sub-Channels | Delivered | Last Payload |' + LineEnding +
    '| :--- | :--- | :--- | :--- | :--- |' + LineEnding;

  for I := 0 to Messenger.SubscriptionCount - 1 do
  begin
    Sub := Messenger.GetSubscription(I);
    Result := Result + Format('| `%s` | `%s` | `%s` | **`%d`** | `%s` |', [
      Sub.SubscriberId, Sub.ChannelTagFilter,
      BoolToStr(Sub.MatchSubChannels, 'YES', 'EXACT'),
      Sub.DeliveredCount, Sub.LastPayloadText]) + LineEnding;
  end;
end;

end.
