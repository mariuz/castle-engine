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

{ Design discovery, live-property keyframe capture, camera-cut discovery, and
  Markdown reporting for @link(TCastleSequencePlayer)
  (Phase 287 — UE 5.9 / 6.0 Sequencer Parity). }
unit ToolSequencer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleUIControls,
  CastleViewport, CastleSequencer;

type
  { Stateless helper for authoring and inspecting @link(TCastleSequencePlayer)
    timelines in @code(castle-editor) and automated tests. }
  TSequencerHelper = class
  public
    { Collect all @link(TCastleSequencePlayer) instances in @code(RootComponent). }
    class procedure CollectSequencePlayers(const RootComponent: TComponent;
      const OutList: TList);

    { Create a new uniquely named @link(TCastleSequencePlayer) inside
      @code(RootComponent)'s @code($NonVisualComponents) (and optionally attach
      a @link(TCastleSequenceRunnerBehavior) to the first viewport/transform root
      so 3D scenes auto-advance at runtime). }
    class function CreateSequencePlayerInDesign(
      const RootComponent, AOwner: TComponent;
      const ALabel: String = 'MainSequence';
      const ADuration: Single = 5.0;
      const AttachRunnerIf3D: Boolean = true): TCastleSequencePlayer;

    { Sample the live value of @code(PropPath) on @code(TargetComp) right now
      and insert/update a typed keyframe at @code(TimeSec) in @code(Player). }
    class function CaptureLivePropertyKey(
      const Player: TCastleSequencePlayer;
      const TargetComp: TComponent;
      const PropPath: String;
      const TimeSec: Single;
      const Easing: TSequenceEasing = seSmoothStep): Boolean;

    { Enumerate all non-transient named components in @code(RootComponent). }
    class procedure CollectNamedTargetComponents(const RootComponent: TComponent;
      const OutNames: TStrings);

    { Enumerate all named @code(TCastleCamera) instances in @code(RootComponent). }
    class procedure CollectCamerasInDesign(const RootComponent: TComponent;
      const OutCameraNames: TStrings);

    { Return the first @link(TCastleViewport) in @code(RootComponent), or @nil. }
    class function FindFirstViewport(const RootComponent: TComponent): TCastleViewport;

    { Export a Markdown summary table of tracks, keyframes, and event cues. }
    class function FormatSequenceMarkdown(
      const Player: TCastleSequencePlayer): String;
  end;

implementation

uses
  FpJson,
  CastleCameras, CastlePrefabOverrides, CastleUtils;

function MakeUniqueSeqName(const AOwner: TComponent; const BaseName: String): String;
var
  Idx: Integer;
begin
  Idx := 1;
  repeat
    Result := BaseName + IntToStr(Idx);
    Inc(Idx);
  until (AOwner = nil) or (AOwner.FindComponent(Result) = nil);
end;

{ TSequencerHelper ----------------------------------------------------------- }

class procedure TSequencerHelper.CollectSequencePlayers(
  const RootComponent: TComponent; const OutList: TList);

  procedure Walk(const Node: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
    C: TCastleComponent;
  begin
    if (Node = nil) or (csTransient in Node.ComponentStyle) then
      Exit;
    if (Node is TCastleSequencePlayer) and (OutList.IndexOf(Node) < 0) then
      OutList.Add(Node);

    if (Node is TCastleViewport) and (TCastleViewport(Node).Items <> nil) then
      Walk(TCastleViewport(Node).Items);

    if Node is TCastleUserInterface then
    begin
      U := TCastleUserInterface(Node);
      for I := 0 to U.ControlsCount - 1 do
        Walk(U.Controls[I]);
    end;

    if Node is TCastleTransform then
    begin
      T := TCastleTransform(Node);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;

    if Node is TCastleComponent then
    begin
      C := TCastleComponent(Node);
      for I := 0 to C.NonVisualComponentsCount - 1 do
        Walk(C.NonVisualComponents[I]);
    end;
  end;

begin
  if OutList = nil then
    Exit;
  OutList.Clear;
  Walk(RootComponent);
end;

class function TSequencerHelper.FindFirstViewport(
  const RootComponent: TComponent): TCastleViewport;

  function WalkUi(const U: TCastleUserInterface): TCastleViewport;
  var
    I: Integer;
  begin
    Result := nil;
    if (U = nil) or (csTransient in U.ComponentStyle) then
      Exit;
    if U is TCastleViewport then
      Exit(TCastleViewport(U));
    for I := 0 to U.ControlsCount - 1 do
    begin
      Result := WalkUi(U.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;

begin
  if RootComponent is TCastleUserInterface then
    Result := WalkUi(TCastleUserInterface(RootComponent))
  else
    Result := nil;
end;

class function TSequencerHelper.CreateSequencePlayerInDesign(
  const RootComponent, AOwner: TComponent; const ALabel: String;
  const ADuration: Single; const AttachRunnerIf3D: Boolean): TCastleSequencePlayer;
var
  Vp: TCastleViewport;
  HostT: TCastleTransform;
  Runner: TCastleSequenceRunnerBehavior;
begin
  Result := nil;
  if not (RootComponent is TCastleComponent) then
    Exit;

  Result := TCastleSequencePlayer.Create(AOwner);
  Result.Name := MakeUniqueSeqName(AOwner, 'SequencePlayer');
  Result.SequenceLabel := ALabel;
  Result.Duration := ADuration;
  Result.TargetRoot := TCastleComponent(RootComponent);
  TCastleComponent(RootComponent).AddNonVisualComponent(Result);

  if AttachRunnerIf3D then
  begin
    HostT := nil;
    if RootComponent is TCastleTransform then
      HostT := TCastleTransform(RootComponent)
    else
    begin
      Vp := FindFirstViewport(RootComponent);
      if (Vp <> nil) and (Vp.Items <> nil) then
        HostT := Vp.Items;
    end;

    if HostT <> nil then
    begin
      Runner := TCastleSequenceRunnerBehavior.Create(AOwner);
      Runner.Name := MakeUniqueSeqName(AOwner, 'SequenceRunner');
      Runner.SequencePlayer := Result;
      HostT.AddBehavior(Runner);
    end;
  end;
end;

class function TSequencerHelper.CaptureLivePropertyKey(
  const Player: TCastleSequencePlayer; const TargetComp: TComponent;
  const PropPath: String; const TimeSec: Single;
  const Easing: TSequenceEasing): Boolean;
var
  TrimPath: String;
  JsonVal: TJSONData;
begin
  Result := false;
  if (Player = nil) or (TargetComp = nil) or (Trim(TargetComp.Name) = '') then
    Exit;

  TrimPath := Trim(PropPath);
  if TrimPath = '' then
    Exit;

  if (TargetComp is TCastleTransform) and
     (SameText(TrimPath, 'Translation') or SameText(TrimPath, 'TranslationPersistent')) then
  begin
    Player.AddOrUpdateVector3Key(TargetComp.Name, 'Translation',
      TimeSec, TCastleTransform(TargetComp).Translation, Easing);
    Exit(true);
  end;

  if (TargetComp is TCastleTransform) and
     (SameText(TrimPath, 'Scale') or SameText(TrimPath, 'ScalePersistent')) then
  begin
    Player.AddOrUpdateVector3Key(TargetComp.Name, 'Scale',
      TimeSec, TCastleTransform(TargetComp).Scale, Easing);
    Exit(true);
  end;

  JsonVal := ReadRttiPropertyPathJson(TargetComp, TrimPath);
  if JsonVal = nil then
    Exit;
  try
    case JsonVal.JsonType of
      jtNumber:
        begin
          Player.AddOrUpdateFloatKey(TargetComp.Name, TrimPath,
            TimeSec, JsonVal.AsFloat, Easing);
          Result := true;
        end;
      jtBoolean:
        begin
          Player.AddOrUpdateBoolKey(TargetComp.Name, TrimPath,
            TimeSec, JsonVal.AsBoolean);
          Result := true;
        end;
      jtString:
        begin
          Player.AddOrUpdateStringKey(TargetComp.Name, TrimPath,
            TimeSec, JsonVal.AsString);
          Result := true;
        end;
    end;
  finally
    FreeAndNil(JsonVal);
  end;
end;

class procedure TSequencerHelper.CollectNamedTargetComponents(
  const RootComponent: TComponent; const OutNames: TStrings);

  procedure Walk(const Node: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
    C: TCastleComponent;
  begin
    if (Node = nil) or (csTransient in Node.ComponentStyle) then
      Exit;
    if (Trim(Node.Name) <> '') and (not (Node is TCastleSequencePlayer)) and
       (not (Node is TCastleSequenceRunnerBehavior)) and
       (OutNames.IndexOf(Node.Name) < 0) then
      OutNames.AddObject(Node.Name, Node);

    if (Node is TCastleViewport) and (TCastleViewport(Node).Items <> nil) then
      Walk(TCastleViewport(Node).Items);

    if Node is TCastleUserInterface then
    begin
      U := TCastleUserInterface(Node);
      for I := 0 to U.ControlsCount - 1 do
        Walk(U.Controls[I]);
    end;

    if Node is TCastleTransform then
    begin
      T := TCastleTransform(Node);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;

    if Node is TCastleComponent then
    begin
      C := TCastleComponent(Node);
      for I := 0 to C.NonVisualComponentsCount - 1 do
        Walk(C.NonVisualComponents[I]);
    end;
  end;

begin
  if OutNames = nil then
    Exit;
  OutNames.Clear;
  Walk(RootComponent);
end;

class procedure TSequencerHelper.CollectCamerasInDesign(
  const RootComponent: TComponent; const OutCameraNames: TStrings);
var
  AllComps: TStringList;
  I: Integer;
begin
  if OutCameraNames = nil then
    Exit;
  OutCameraNames.Clear;
  AllComps := TStringList.Create;
  try
    CollectNamedTargetComponents(RootComponent, AllComps);
    for I := 0 to AllComps.Count - 1 do
      if TObject(AllComps.Objects[I]) is TCastleCamera then
        OutCameraNames.AddObject(AllComps[I], AllComps.Objects[I]);
  finally
    FreeAndNil(AllComps);
  end;
end;

class function TSequencerHelper.FormatSequenceMarkdown(
  const Player: TCastleSequencePlayer): String;
var
  SB: TStringBuilder;
  Tracks: TSequenceTrackDataArray;
  Cues: TSequenceCueDataArray;
  I: Integer;
  ModeStr: String;
begin
  if Player = nil then
    Exit('');
  Tracks := Player.GetTracksSnapshot;
  Cues := Player.GetCuesSnapshot;
  case Player.PlaybackMode of
    spmOnce: ModeStr := 'Once';
    spmLoop: ModeStr := 'Loop';
    spmPingPong: ModeStr := 'PingPong';
  end;

  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('### Sequence: `%s` (%s)',
      [Player.Name, Player.SequenceLabel]));
    SB.AppendLine(Format('- **Duration:** `%.2fs`  |  **Mode:** `%s`  |  **Speed:** `%.2fx`  |  **Tracks:** `%d`  |  **Keys:** `%d`  |  **Cues:** `%d`',
      [Player.Duration, ModeStr, Player.TimeScale,
       Length(Tracks), Player.TotalKeyCount, Length(Cues)]));
    SB.AppendLine('');
    if Length(Tracks) > 0 then
    begin
      SB.AppendLine('| Track | Target | Property | Kind | Keys | Muted |');
      SB.AppendLine('| --- | --- | --- | --- | --- | --- |');
      for I := 0 to High(Tracks) do
        SB.AppendLine(Format('| `%d` | `%s` | `%s` | `%s` | `%d` | `%s` |',
          [I, Tracks[I].TargetName, Tracks[I].PropPath,
           SequenceTrackKindToString(Tracks[I].Kind),
           Length(Tracks[I].Keys), BoolToStr(Tracks[I].Muted, true)]));
    end;
    if Length(Cues) > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('| Cue Time (s) | Cue Name | Payload |');
      SB.AppendLine('| --- | --- | --- |');
      for I := 0 to High(Cues) do
        SB.AppendLine(Format('| `%.2f` | `%s` | `%s` |',
          [Cues[I].TimeSec, Cues[I].CueName, Cues[I].Payload]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
