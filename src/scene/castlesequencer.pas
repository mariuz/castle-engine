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

{ Non-linear multi-track cinematic & UI sequencer (@link(TCastleSequencePlayer))
  with keyframe interpolation, camera cuts, event cues, and deterministic
  timeline scrubbing (Phase 287 — UE 5.9 / 6.0 Sequencer Parity). }
unit CastleSequencer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, FpJson,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Interpolation curve between adjacent keyframes. }
  TSequenceEasing = (
    seLinear,
    seSmoothStep,
    seEaseInCubic,
    seEaseOutCubic,
    seStep
  );

  { Timeline transport wrap mode. }
  TSequencePlaybackMode = (
    spmOnce,
    spmLoop,
    spmPingPong
  );

  { Track channel data type. }
  TSequenceTrackKind = (
    stkFloatProperty,
    stkVector3Property,
    stkBoolProperty,
    stkStringProperty,
    stkCameraCut
  );

  { Fired when @link(TCastleSequencePlayer.Step) crosses an event cue timestamp. }
  TSequenceCueNotifyEvent = procedure (Sender: TObject;
    const CueName, Payload: String; const TimeSec: Single) of object;

  { Single keyframe sample inside a @link(TSequenceTrackData). }
  TSequenceKeyframeData = record
    TimeSec: Single;
    Easing: TSequenceEasing;
    FloatVal: Single;
    Vec3Val: TVector3;
    BoolVal: Boolean;
    StrVal: String;
  end;
  TSequenceKeyframeDataArray = array of TSequenceKeyframeData;

  { Decoded multi-keyframe track targeting a named component & property path. }
  TSequenceTrackData = record
    Kind: TSequenceTrackKind;
    TargetName: String;
    PropPath: String;
    Muted: Boolean;
    Keys: TSequenceKeyframeDataArray;
  end;
  TSequenceTrackDataArray = array of TSequenceTrackData;

  { Timestamped event cue marker along the sequence timeline. }
  TSequenceCueData = record
    TimeSec: Single;
    CueName: String;
    Payload: String;
  end;
  TSequenceCueDataArray = array of TSequenceCueData;

  { Non-linear multi-track keyframe, camera-cut, and event-cue sequence player.
    Stores tracks and cues as diff-friendly JSON in @link(TracksJson) and can
    reside inside @code($NonVisualComponents) of any @code(.castle-user-interface)
    or @code(.castle-transform) design. }
  TCastleSequencePlayer = class(TCastleComponent)
  strict private
    FSequenceLabel: String;
    FDuration: Single;
    FPlaybackMode: TSequencePlaybackMode;
    FTimeScale: Single;
    FAutoPlayInRuntime: Boolean;
    FTracksJson: String;
    FTargetRoot: TCastleComponent;
    FTargetRootObserver: TFreeNotificationObserver;

    FTracks: TSequenceTrackDataArray;
    FCues: TSequenceCueDataArray;
    FTracksDirty: Boolean;

    FCurrentTime: Single;
    FPlaying: Boolean;
    FPingPongDirection: Single;
    FOnCueEvent: TSequenceCueNotifyEvent;

    procedure SetDuration(const Value: Single);
    procedure SetTracksJson(const Value: String);
    procedure SetTargetRoot(const Value: TCastleComponent);
    procedure TargetRootFreeNotification(const Sender: TFreeNotificationObserver);

    procedure EnsureParsed;
    procedure RebuildJsonFromMemory;
    function FindOrAddTrack(const AKind: TSequenceTrackKind;
      const ATargetName, APropPath: String): Integer;
    function ResolveComponentByName(const CompName: String): TComponent;
    function ApplySingleTrackAtTime(const Track: TSequenceTrackData;
      const TimeSec: Single): Boolean;
    procedure FireCuesInRange(const FromTime, ToTime: Single;
      const ForwardDir: Boolean);
  protected
    procedure Loaded; override;
  public
    const
      DefaultDuration = 5.0;
      DefaultTimeScale = 1.0;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Transport controls. }
    procedure Play;
    procedure Pause;
    procedure Stop;
    procedure Rewind;

    { Advance timeline playback by @code(SecondsPassed) (scaled by @link(TimeScale)),
      evaluating all non-muted tracks and firing any crossed event cues. }
    procedure Step(const SecondsPassed: Single);

    { Deterministically evaluate all non-muted tracks at @code(TimeSec) without
      requiring @link(Playing) to be @true. Updates @link(CurrentTime) and
      returns the number of tracks successfully applied. }
    function EvaluateAtTime(const TimeSec: Single): Integer;

    { Track & cue mutation API (automatically keeps keyframes sorted by @code(TimeSec)
      and updates @link(TracksJson)). }
    procedure ClearAllTracksAndCues;
    function AddOrUpdateFloatKey(const TargetName, PropPath: String;
      const TimeSec, Value: Single;
      const Easing: TSequenceEasing = seSmoothStep): Integer;
    function AddOrUpdateVector3Key(const TargetName, PropPath: String;
      const TimeSec: Single; const Value: TVector3;
      const Easing: TSequenceEasing = seSmoothStep): Integer;
    function AddOrUpdateBoolKey(const TargetName, PropPath: String;
      const TimeSec: Single; const Value: Boolean): Integer;
    function AddOrUpdateStringKey(const TargetName, PropPath: String;
      const TimeSec: Single; const Value: String): Integer;
    function AddOrUpdateCameraCutKey(const ViewportName: String;
      const TimeSec: Single; const CameraName: String): Integer;
    procedure AddEventCue(const TimeSec: Single;
      const CueName: String; const Payload: String = '');
    procedure SetTrackMuted(const TrackIndex: Integer; const AMuted: Boolean);
    function RemoveTrack(const TrackIndex: Integer): Boolean;
    function RemoveKeyAt(const TrackIndex, KeyIndex: Integer): Boolean;
    function RemoveCueAt(const CueIndex: Integer): Boolean;

    { Inspection accessors for @code(TSequencerForm) and automated unit tests. }
    function TrackCount: Integer;
    function TotalKeyCount: Integer;
    function CueCount: Integer;
    function GetTracksSnapshot: TSequenceTrackDataArray;
    function GetCuesSnapshot: TSequenceCueDataArray;
    function SequenceSummaryBadge: String;

    property CurrentTime: Single read FCurrentTime write FCurrentTime;
    property Playing: Boolean read FPlaying write FPlaying;
    property OnCueEvent: TSequenceCueNotifyEvent read FOnCueEvent write FOnCueEvent;
  published
    { Human-readable cutscene / UI animation title. }
    property SequenceLabel: String read FSequenceLabel write FSequenceLabel;

    { Sequence length in seconds (>= 0.1). }
    property Duration: Single read FDuration write SetDuration
      {$ifdef FPC}default DefaultDuration{$endif};

    { Wrap behavior when playhead reaches @link(Duration). }
    property PlaybackMode: TSequencePlaybackMode
      read FPlaybackMode write FPlaybackMode default spmOnce;

    { Playback speed multiplier. }
    property TimeScale: Single read FTimeScale write FTimeScale
      {$ifdef FPC}default DefaultTimeScale{$endif};

    { Automatically begin playing when loaded at game runtime
      (@code(not CastleDesignMode)). }
    property AutoPlayInRuntime: Boolean
      read FAutoPlayInRuntime write FAutoPlayInRuntime default true;

    { Optional explicit hierarchy root used to resolve @code(TargetName)
      components when @code(Owner) is not the design owner. }
    property TargetRoot: TCastleComponent read FTargetRoot write SetTargetRoot;

    { Diff-friendly JSON payload storing multi-track keyframes and event cues. }
    property TracksJson: String read FTracksJson write SetTracksJson;
  end;

  { Behavior that automatically advances a @link(TCastleSequencePlayer) every
    frame inside a 3D @link(TCastleViewport) at game runtime. }
  TCastleSequenceRunnerBehavior = class(TCastleBehavior)
  strict private
    FSequencePlayer: TCastleSequencePlayer;
    FPlayerObserver: TFreeNotificationObserver;
    procedure SetSequencePlayer(const Value: TCastleSequencePlayer);
    procedure PlayerFreeNotification(const Sender: TFreeNotificationObserver);
  protected
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
  published
    property SequencePlayer: TCastleSequencePlayer
      read FSequencePlayer write SetSequencePlayer;
  end;

{ Evaluate normalized keyframe interpolation factor @code(Alpha in [0..1]). }
function EvaluateSequenceEasing(const Mode: TSequenceEasing;
  const Alpha: Single): Single;

function SequenceEasingToString(const Mode: TSequenceEasing): String;
function StringToSequenceEasing(const S: String): TSequenceEasing;
function SequenceTrackKindToString(const Kind: TSequenceTrackKind): String;
function StringToSequenceTrackKind(const S: String): TSequenceTrackKind;

implementation

uses
  Math, TypInfo, JsonParser,
  CastleComponentSerialize, CastleViewport, CastleCameras, CastleUIControls,
  CastlePrefabOverrides, CastleLog;

function EvaluateSequenceEasing(const Mode: TSequenceEasing;
  const Alpha: Single): Single;
var
  T, Inv: Single;
begin
  T := Clamped(Alpha, 0.0, 1.0);
  case Mode of
    seLinear:
      Result := T;
    seSmoothStep:
      Result := T * T * (3.0 - 2.0 * T);
    seEaseInCubic:
      Result := T * T * T;
    seEaseOutCubic:
      begin
        Inv := 1.0 - T;
        Result := 1.0 - Inv * Inv * Inv;
      end;
    seStep:
      if T >= 1.0 then
        Result := 1.0
      else
        Result := 0.0;
  end;
end;

function SequenceEasingToString(const Mode: TSequenceEasing): String;
begin
  case Mode of
    seLinear: Result := 'linear';
    seSmoothStep: Result := 'smooth';
    seEaseInCubic: Result := 'ease_in';
    seEaseOutCubic: Result := 'ease_out';
    seStep: Result := 'step';
  end;
end;

function StringToSequenceEasing(const S: String): TSequenceEasing;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'linear' then
    Result := seLinear
  else if L = 'ease_in' then
    Result := seEaseInCubic
  else if L = 'ease_out' then
    Result := seEaseOutCubic
  else if L = 'step' then
    Result := seStep
  else
    Result := seSmoothStep;
end;

function SequenceTrackKindToString(const Kind: TSequenceTrackKind): String;
begin
  case Kind of
    stkFloatProperty: Result := 'float';
    stkVector3Property: Result := 'vec3';
    stkBoolProperty: Result := 'bool';
    stkStringProperty: Result := 'string';
    stkCameraCut: Result := 'camera_cut';
  end;
end;

function StringToSequenceTrackKind(const S: String): TSequenceTrackKind;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'vec3' then
    Result := stkVector3Property
  else if L = 'bool' then
    Result := stkBoolProperty
  else if L = 'string' then
    Result := stkStringProperty
  else if L = 'camera_cut' then
    Result := stkCameraCut
  else
    Result := stkFloatProperty;
end;

procedure InsertOrUpdateKeySorted(var Keys: TSequenceKeyframeDataArray;
  const NewKey: TSequenceKeyframeData; out KeyIdx: Integer);
var
  I, J: Integer;
begin
  for I := 0 to High(Keys) do
    if SameValue(Keys[I].TimeSec, NewKey.TimeSec, 0.0005) then
    begin
      Keys[I] := NewKey;
      KeyIdx := I;
      Exit;
    end;

  KeyIdx := Length(Keys);
  for I := 0 to High(Keys) do
    if NewKey.TimeSec < Keys[I].TimeSec then
    begin
      KeyIdx := I;
      Break;
    end;

  SetLength(Keys, Length(Keys) + 1);
  for J := High(Keys) downto KeyIdx + 1 do
    Keys[J] := Keys[J - 1];
  Keys[KeyIdx] := NewKey;
end;

{ TCastleSequencePlayer ------------------------------------------------------ }

constructor TCastleSequencePlayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDuration := DefaultDuration;
  FPlaybackMode := spmOnce;
  FTimeScale := DefaultTimeScale;
  FAutoPlayInRuntime := true;
  FPingPongDirection := 1.0;

  FTargetRootObserver := TFreeNotificationObserver.Create(Self);
  FTargetRootObserver.OnFreeNotification := {$ifdef FPC}@{$endif}TargetRootFreeNotification;
end;

destructor TCastleSequencePlayer.Destroy;
begin
  inherited;
end;

function TCastleSequencePlayer.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'SequenceLabel', 'Duration', 'PlaybackMode', 'TimeScale',
       'AutoPlayInRuntime', 'TargetRoot', 'TracksJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSequencePlayer.SetDuration(const Value: Single);
begin
  FDuration := Max(0.1, Value);
end;

procedure TCastleSequencePlayer.SetTracksJson(const Value: String);
begin
  if FTracksJson = Value then
    Exit;
  FTracksJson := Value;
  FTracksDirty := true;
end;

procedure TCastleSequencePlayer.SetTargetRoot(const Value: TCastleComponent);
begin
  if FTargetRoot = Value then
    Exit;
  FTargetRoot := Value;
  FTargetRootObserver.Observed := Value;
end;

procedure TCastleSequencePlayer.TargetRootFreeNotification(
  const Sender: TFreeNotificationObserver);
begin
  FTargetRoot := nil;
end;

procedure TCastleSequencePlayer.Loaded;
begin
  inherited;
  EnsureParsed;
  if (not CastleDesignMode) and FAutoPlayInRuntime then
  begin
    FCurrentTime := 0.0;
    FPingPongDirection := 1.0;
    FPlaying := true;
    EvaluateAtTime(0.0);
  end;
end;

procedure TCastleSequencePlayer.EnsureParsed;
var
  Parsed, ItemData, KeyData: TJSONData;
  RootObj, TrackObj, KeyObj, CueObj: TJSONObject;
  TracksArr, KeysArr, CuesArr, VecArr: TJSONArray;
  I, K, OutT: Integer;
  NewKey: TSequenceKeyframeData;
  KeyDummyIdx: Integer;
begin
  if not FTracksDirty then
    Exit;
  FTracksDirty := false;
  FTracks := nil;
  FCues := nil;

  if Trim(FTracksJson) = '' then
    Exit;

  Parsed := nil;
  try
    try
      Parsed := GetJSON(FTracksJson);
    except
      on E: Exception do
      begin
        WritelnWarning('TCastleSequencePlayer',
          'Invalid TracksJson on "%s": %s', [Name, E.Message]);
        Exit;
      end;
    end;

    if not (Parsed is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Parsed);

    TracksArr := RootObj.Find('tracks', jtArray) as TJSONArray;
    if TracksArr <> nil then
    begin
      for I := 0 to TracksArr.Count - 1 do
      begin
        ItemData := TracksArr.Items[I];
        if not (ItemData is TJSONObject) then
          Continue;
        TrackObj := TJSONObject(ItemData);
        OutT := Length(FTracks);
        SetLength(FTracks, OutT + 1);
        FTracks[OutT].Kind := StringToSequenceTrackKind(TrackObj.Get('kind', 'float'));
        FTracks[OutT].TargetName := TrackObj.Get('target', '');
        FTracks[OutT].PropPath := TrackObj.Get('prop', '');
        FTracks[OutT].Muted := TrackObj.Get('muted', false);
        FTracks[OutT].Keys := nil;

        KeysArr := TrackObj.Find('keys', jtArray) as TJSONArray;
        if KeysArr <> nil then
          for K := 0 to KeysArr.Count - 1 do
          begin
            KeyData := KeysArr.Items[K];
            if not (KeyData is TJSONObject) then
              Continue;
            KeyObj := TJSONObject(KeyData);
            NewKey := Default(TSequenceKeyframeData);
            NewKey.TimeSec := Max(0.0, KeyObj.Get('t', 0.0));
            NewKey.Easing := StringToSequenceEasing(KeyObj.Get('ease', 'smooth'));
            case FTracks[OutT].Kind of
              stkFloatProperty:
                NewKey.FloatVal := KeyObj.Get('v', 0.0);
              stkVector3Property:
                begin
                  VecArr := KeyObj.Find('v', jtArray) as TJSONArray;
                  if (VecArr <> nil) and (VecArr.Count >= 3) then
                    NewKey.Vec3Val := Vector3(
                      VecArr.Items[0].AsFloat,
                      VecArr.Items[1].AsFloat,
                      VecArr.Items[2].AsFloat);
                end;
              stkBoolProperty:
                NewKey.BoolVal := KeyObj.Get('v', false);
              stkStringProperty, stkCameraCut:
                NewKey.StrVal := KeyObj.Get('v', '');
            end;
            InsertOrUpdateKeySorted(FTracks[OutT].Keys, NewKey, KeyDummyIdx);
          end;
      end;
    end;

    CuesArr := RootObj.Find('cues', jtArray) as TJSONArray;
    if CuesArr <> nil then
    begin
      for I := 0 to CuesArr.Count - 1 do
      begin
        ItemData := CuesArr.Items[I];
        if not (ItemData is TJSONObject) then
          Continue;
        CueObj := TJSONObject(ItemData);
        OutT := Length(FCues);
        SetLength(FCues, OutT + 1);
        FCues[OutT].TimeSec := Max(0.0, CueObj.Get('t', 0.0));
        FCues[OutT].CueName := CueObj.Get('name', '');
        FCues[OutT].Payload := CueObj.Get('payload', '');
      end;
    end;
  finally
    FreeAndNil(Parsed);
  end;
end;

procedure TCastleSequencePlayer.RebuildJsonFromMemory;
var
  RootObj, TrackObj, KeyObj, CueObj: TJSONObject;
  TracksArr, KeysArr, CuesArr, VecArr: TJSONArray;
  I, K: Integer;
begin
  if (Length(FTracks) = 0) and (Length(FCues) = 0) then
  begin
    FTracksJson := '';
    FTracksDirty := false;
    Exit;
  end;

  RootObj := TJSONObject.Create;
  try
    TracksArr := TJSONArray.Create;
    RootObj.Add('tracks', TracksArr);
    for I := 0 to High(FTracks) do
    begin
      TrackObj := TJSONObject.Create;
      TrackObj.Add('kind', SequenceTrackKindToString(FTracks[I].Kind));
      TrackObj.Add('target', FTracks[I].TargetName);
      TrackObj.Add('prop', FTracks[I].PropPath);
      if FTracks[I].Muted then
        TrackObj.Add('muted', true);

      KeysArr := TJSONArray.Create;
      TrackObj.Add('keys', KeysArr);
      for K := 0 to High(FTracks[I].Keys) do
      begin
        KeyObj := TJSONObject.Create;
        KeyObj.Add('t', FTracks[I].Keys[K].TimeSec);
        if FTracks[I].Keys[K].Easing <> seSmoothStep then
          KeyObj.Add('ease', SequenceEasingToString(FTracks[I].Keys[K].Easing));
        case FTracks[I].Kind of
          stkFloatProperty:
            KeyObj.Add('v', FTracks[I].Keys[K].FloatVal);
          stkVector3Property:
            begin
              VecArr := TJSONArray.Create;
              VecArr.Add(FTracks[I].Keys[K].Vec3Val.X);
              VecArr.Add(FTracks[I].Keys[K].Vec3Val.Y);
              VecArr.Add(FTracks[I].Keys[K].Vec3Val.Z);
              KeyObj.Add('v', VecArr);
            end;
          stkBoolProperty:
            KeyObj.Add('v', FTracks[I].Keys[K].BoolVal);
          stkStringProperty, stkCameraCut:
            KeyObj.Add('v', FTracks[I].Keys[K].StrVal);
        end;
        KeysArr.Add(KeyObj);
      end;
      TracksArr.Add(TrackObj);
    end;

    if Length(FCues) > 0 then
    begin
      CuesArr := TJSONArray.Create;
      RootObj.Add('cues', CuesArr);
      for I := 0 to High(FCues) do
      begin
        CueObj := TJSONObject.Create;
        CueObj.Add('t', FCues[I].TimeSec);
        CueObj.Add('name', FCues[I].CueName);
        if FCues[I].Payload <> '' then
          CueObj.Add('payload', FCues[I].Payload);
        CuesArr.Add(CueObj);
      end;
    end;

    FTracksJson := RootObj.AsJSON;
    FTracksDirty := false;
  finally
    FreeAndNil(RootObj);
  end;
end;

function TCastleSequencePlayer.FindOrAddTrack(const AKind: TSequenceTrackKind;
  const ATargetName, APropPath: String): Integer;
var
  I: Integer;
begin
  EnsureParsed;
  for I := 0 to High(FTracks) do
    if (FTracks[I].Kind = AKind) and
       SameText(FTracks[I].TargetName, ATargetName) and
       SameText(FTracks[I].PropPath, APropPath) then
      Exit(I);

  Result := Length(FTracks);
  SetLength(FTracks, Result + 1);
  FTracks[Result].Kind := AKind;
  FTracks[Result].TargetName := ATargetName;
  FTracks[Result].PropPath := APropPath;
  FTracks[Result].Muted := false;
  FTracks[Result].Keys := nil;
end;

procedure TCastleSequencePlayer.ClearAllTracksAndCues;
begin
  FTracks := nil;
  FCues := nil;
  FTracksJson := '';
  FTracksDirty := false;
end;

function TCastleSequencePlayer.AddOrUpdateFloatKey(
  const TargetName, PropPath: String; const TimeSec, Value: Single;
  const Easing: TSequenceEasing): Integer;
var
  K: TSequenceKeyframeData;
  DummyIdx: Integer;
begin
  Result := FindOrAddTrack(stkFloatProperty, TargetName, PropPath);
  K := Default(TSequenceKeyframeData);
  K.TimeSec := Max(0.0, TimeSec);
  K.Easing := Easing;
  K.FloatVal := Value;
  InsertOrUpdateKeySorted(FTracks[Result].Keys, K, DummyIdx);
  if K.TimeSec > FDuration then
    FDuration := K.TimeSec;
  RebuildJsonFromMemory;
end;

function TCastleSequencePlayer.AddOrUpdateVector3Key(
  const TargetName, PropPath: String; const TimeSec: Single;
  const Value: TVector3; const Easing: TSequenceEasing): Integer;
var
  K: TSequenceKeyframeData;
  DummyIdx: Integer;
begin
  Result := FindOrAddTrack(stkVector3Property, TargetName, PropPath);
  K := Default(TSequenceKeyframeData);
  K.TimeSec := Max(0.0, TimeSec);
  K.Easing := Easing;
  K.Vec3Val := Value;
  InsertOrUpdateKeySorted(FTracks[Result].Keys, K, DummyIdx);
  if K.TimeSec > FDuration then
    FDuration := K.TimeSec;
  RebuildJsonFromMemory;
end;

function TCastleSequencePlayer.AddOrUpdateBoolKey(
  const TargetName, PropPath: String; const TimeSec: Single;
  const Value: Boolean): Integer;
var
  K: TSequenceKeyframeData;
  DummyIdx: Integer;
begin
  Result := FindOrAddTrack(stkBoolProperty, TargetName, PropPath);
  K := Default(TSequenceKeyframeData);
  K.TimeSec := Max(0.0, TimeSec);
  K.Easing := seStep;
  K.BoolVal := Value;
  InsertOrUpdateKeySorted(FTracks[Result].Keys, K, DummyIdx);
  if K.TimeSec > FDuration then
    FDuration := K.TimeSec;
  RebuildJsonFromMemory;
end;

function TCastleSequencePlayer.AddOrUpdateStringKey(
  const TargetName, PropPath: String; const TimeSec: Single;
  const Value: String): Integer;
var
  K: TSequenceKeyframeData;
  DummyIdx: Integer;
begin
  Result := FindOrAddTrack(stkStringProperty, TargetName, PropPath);
  K := Default(TSequenceKeyframeData);
  K.TimeSec := Max(0.0, TimeSec);
  K.Easing := seStep;
  K.StrVal := Value;
  InsertOrUpdateKeySorted(FTracks[Result].Keys, K, DummyIdx);
  if K.TimeSec > FDuration then
    FDuration := K.TimeSec;
  RebuildJsonFromMemory;
end;

function TCastleSequencePlayer.AddOrUpdateCameraCutKey(
  const ViewportName: String; const TimeSec: Single;
  const CameraName: String): Integer;
var
  K: TSequenceKeyframeData;
  DummyIdx: Integer;
begin
  Result := FindOrAddTrack(stkCameraCut, ViewportName, '$CameraCut');
  K := Default(TSequenceKeyframeData);
  K.TimeSec := Max(0.0, TimeSec);
  K.Easing := seStep;
  K.StrVal := CameraName;
  InsertOrUpdateKeySorted(FTracks[Result].Keys, K, DummyIdx);
  if K.TimeSec > FDuration then
    FDuration := K.TimeSec;
  RebuildJsonFromMemory;
end;

procedure TCastleSequencePlayer.AddEventCue(const TimeSec: Single;
  const CueName, Payload: String);
var
  Idx, I: Integer;
begin
  EnsureParsed;
  for I := 0 to High(FCues) do
    if SameValue(FCues[I].TimeSec, TimeSec, 0.0005) and
       SameText(FCues[I].CueName, CueName) then
    begin
      FCues[I].Payload := Payload;
      RebuildJsonFromMemory;
      Exit;
    end;

  Idx := Length(FCues);
  SetLength(FCues, Idx + 1);
  FCues[Idx].TimeSec := Max(0.0, TimeSec);
  FCues[Idx].CueName := CueName;
  FCues[Idx].Payload := Payload;
  if FCues[Idx].TimeSec > FDuration then
    FDuration := FCues[Idx].TimeSec;
  RebuildJsonFromMemory;
end;

procedure TCastleSequencePlayer.SetTrackMuted(const TrackIndex: Integer;
  const AMuted: Boolean);
begin
  EnsureParsed;
  if (TrackIndex < 0) or (TrackIndex > High(FTracks)) then
    Exit;
  FTracks[TrackIndex].Muted := AMuted;
  RebuildJsonFromMemory;
end;

function TCastleSequencePlayer.RemoveTrack(const TrackIndex: Integer): Boolean;
var
  I: Integer;
begin
  EnsureParsed;
  if (TrackIndex < 0) or (TrackIndex > High(FTracks)) then
    Exit(false);
  for I := TrackIndex to High(FTracks) - 1 do
    FTracks[I] := FTracks[I + 1];
  SetLength(FTracks, Length(FTracks) - 1);
  RebuildJsonFromMemory;
  Result := true;
end;

function TCastleSequencePlayer.RemoveKeyAt(
  const TrackIndex, KeyIndex: Integer): Boolean;
var
  I: Integer;
begin
  EnsureParsed;
  if (TrackIndex < 0) or (TrackIndex > High(FTracks)) then
    Exit(false);
  if (KeyIndex < 0) or (KeyIndex > High(FTracks[TrackIndex].Keys)) then
    Exit(false);
  for I := KeyIndex to High(FTracks[TrackIndex].Keys) - 1 do
    FTracks[TrackIndex].Keys[I] := FTracks[TrackIndex].Keys[I + 1];
  SetLength(FTracks[TrackIndex].Keys, Length(FTracks[TrackIndex].Keys) - 1);
  if Length(FTracks[TrackIndex].Keys) = 0 then
    RemoveTrack(TrackIndex)
  else
    RebuildJsonFromMemory;
  Result := true;
end;

function TCastleSequencePlayer.RemoveCueAt(const CueIndex: Integer): Boolean;
var
  I: Integer;
begin
  EnsureParsed;
  if (CueIndex < 0) or (CueIndex > High(FCues)) then
    Exit(false);
  for I := CueIndex to High(FCues) - 1 do
    FCues[I] := FCues[I + 1];
  SetLength(FCues, Length(FCues) - 1);
  RebuildJsonFromMemory;
  Result := true;
end;

function TCastleSequencePlayer.ResolveComponentByName(
  const CompName: String): TComponent;

  function WalkHierarchy(const Node: TComponent): TComponent;
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
    C: TCastleComponent;
  begin
    Result := nil;
    if Node = nil then
      Exit;
    if SameText(Node.Name, CompName) then
      Exit(Node);

    if Node is TCastleViewport then
    begin
      if TCastleViewport(Node).Items <> nil then
      begin
        Result := WalkHierarchy(TCastleViewport(Node).Items);
        if Result <> nil then
          Exit;
      end;
    end;

    if Node is TCastleUserInterface then
    begin
      U := TCastleUserInterface(Node);
      for I := 0 to U.ControlsCount - 1 do
      begin
        Result := WalkHierarchy(U.Controls[I]);
        if Result <> nil then
          Exit;
      end;
    end;

    if Node is TCastleTransform then
    begin
      T := TCastleTransform(Node);
      for I := 0 to T.BehaviorsCount - 1 do
      begin
        Result := WalkHierarchy(T.Behaviors[I]);
        if Result <> nil then
          Exit;
      end;
      for I := 0 to T.Count - 1 do
      begin
        Result := WalkHierarchy(T[I]);
        if Result <> nil then
          Exit;
      end;
    end;

    if Node is TCastleComponent then
    begin
      C := TCastleComponent(Node);
      for I := 0 to C.NonVisualComponentsCount - 1 do
      begin
        Result := WalkHierarchy(C.NonVisualComponents[I]);
        if Result <> nil then
          Exit;
      end;
    end;
  end;

begin
  Result := nil;
  if Trim(CompName) = '' then
    Exit;

  if Owner <> nil then
  begin
    Result := Owner.FindComponent(CompName);
    if Result <> nil then
      Exit;
  end;

  if FTargetRoot <> nil then
  begin
    if (FTargetRoot.Owner <> nil) and (FTargetRoot.Owner <> Owner) then
    begin
      Result := FTargetRoot.Owner.FindComponent(CompName);
      if Result <> nil then
        Exit;
    end;
    Result := WalkHierarchy(FTargetRoot);
  end;
end;

function ApplyFloatToRttiPath(const TargetComp: TComponent;
  const PropPath: String; const Value: Single): Boolean;
var
  JNum: TJSONFloatNumber;
begin
  JNum := TJSONFloatNumber.Create(Value);
  try
    Result := ApplyRttiPropertyPathJson(TargetComp, PropPath, JNum);
  finally
    FreeAndNil(JNum);
  end;
end;

function ApplyBoolToRttiPath(const TargetComp: TComponent;
  const PropPath: String; const Value: Boolean): Boolean;
var
  JBool: TJSONBoolean;
begin
  JBool := TJSONBoolean.Create(Value);
  try
    Result := ApplyRttiPropertyPathJson(TargetComp, PropPath, JBool);
  finally
    FreeAndNil(JBool);
  end;
end;

function ApplyStringToRttiPath(const TargetComp: TComponent;
  const PropPath, Value: String): Boolean;
var
  JStr: TJSONString;
begin
  JStr := TJSONString.Create(Value);
  try
    Result := ApplyRttiPropertyPathJson(TargetComp, PropPath, JStr);
  finally
    FreeAndNil(JStr);
  end;
end;

function ApplyVec3ToTarget(const TargetComp: TComponent;
  const PropPath: String; const Value: TVector3): Boolean;
var
  P: String;
begin
  Result := false;
  if TargetComp = nil then
    Exit;
  P := Trim(PropPath);
  if (TargetComp is TCastleTransform) and
     (SameText(P, 'Translation') or SameText(P, 'TranslationPersistent')) then
  begin
    TCastleTransform(TargetComp).Translation := Value;
    Exit(true);
  end;
  if (TargetComp is TCastleTransform) and
     (SameText(P, 'Scale') or SameText(P, 'ScalePersistent')) then
  begin
    TCastleTransform(TargetComp).Scale := Value;
    Exit(true);
  end;

  { Generic Persistent X/Y/Z or Red/Green/Blue subcomponent fallback }
  if ApplyFloatToRttiPath(TargetComp, P + '.X', Value.X) and
     ApplyFloatToRttiPath(TargetComp, P + '.Y', Value.Y) and
     ApplyFloatToRttiPath(TargetComp, P + '.Z', Value.Z) then
    Exit(true);

  if ApplyFloatToRttiPath(TargetComp, P + '.Red', Value.X) and
     ApplyFloatToRttiPath(TargetComp, P + '.Green', Value.Y) and
     ApplyFloatToRttiPath(TargetComp, P + '.Blue', Value.Z) then
    Exit(true);
end;

function TCastleSequencePlayer.ApplySingleTrackAtTime(
  const Track: TSequenceTrackData; const TimeSec: Single): Boolean;
var
  TargetComp, CamComp: TComponent;
  N, IdxA, IdxB, I: Integer;
  Span, RawAlpha, Alpha, EvalFloat: Single;
  EvalVec: TVector3;
  EvalBool: Boolean;
  EvalStr: String;
begin
  Result := false;
  N := Length(Track.Keys);
  if Track.Muted or (N = 0) then
    Exit;

  TargetComp := ResolveComponentByName(Track.TargetName);
  if TargetComp = nil then
    Exit;

  { Locate surrounding keyframe pair [IdxA .. IdxB] }
  if TimeSec <= Track.Keys[0].TimeSec then
  begin
    IdxA := 0;
    IdxB := 0;
    Alpha := 0.0;
  end else
  if TimeSec >= Track.Keys[N - 1].TimeSec then
  begin
    IdxA := N - 1;
    IdxB := N - 1;
    Alpha := 0.0;
  end else
  begin
    IdxA := 0;
    for I := 0 to N - 2 do
      if (TimeSec >= Track.Keys[I].TimeSec) and
         (TimeSec <= Track.Keys[I + 1].TimeSec) then
      begin
        IdxA := I;
        Break;
      end;
    IdxB := IdxA + 1;
    Span := Track.Keys[IdxB].TimeSec - Track.Keys[IdxA].TimeSec;
    if Span > 1e-6 then
      RawAlpha := (TimeSec - Track.Keys[IdxA].TimeSec) / Span
    else
      RawAlpha := 1.0;
    Alpha := EvaluateSequenceEasing(Track.Keys[IdxA].Easing, RawAlpha);
  end;

  case Track.Kind of
    stkFloatProperty:
      begin
        EvalFloat := Lerp(Alpha, Track.Keys[IdxA].FloatVal, Track.Keys[IdxB].FloatVal);
        Result := ApplyFloatToRttiPath(TargetComp, Track.PropPath, EvalFloat);
      end;
    stkVector3Property:
      begin
        EvalVec := Lerp(Alpha, Track.Keys[IdxA].Vec3Val, Track.Keys[IdxB].Vec3Val);
        Result := ApplyVec3ToTarget(TargetComp, Track.PropPath, EvalVec);
      end;
    stkBoolProperty:
      begin
        if Alpha >= 1.0 then
          EvalBool := Track.Keys[IdxB].BoolVal
        else
          EvalBool := Track.Keys[IdxA].BoolVal;
        Result := ApplyBoolToRttiPath(TargetComp, Track.PropPath, EvalBool);
      end;
    stkStringProperty:
      begin
        if Alpha >= 1.0 then
          EvalStr := Track.Keys[IdxB].StrVal
        else
          EvalStr := Track.Keys[IdxA].StrVal;
        Result := ApplyStringToRttiPath(TargetComp, Track.PropPath, EvalStr);
      end;
    stkCameraCut:
      begin
        if not (TargetComp is TCastleViewport) then
          Exit;
        if Alpha >= 1.0 then
          EvalStr := Track.Keys[IdxB].StrVal
        else
          EvalStr := Track.Keys[IdxA].StrVal;
        CamComp := ResolveComponentByName(EvalStr);
        if CamComp is TCastleCamera then
        begin
          TCastleViewport(TargetComp).Camera := TCastleCamera(CamComp);
          Result := true;
        end;
      end;
  end;
end;

function TCastleSequencePlayer.EvaluateAtTime(const TimeSec: Single): Integer;
var
  I: Integer;
begin
  EnsureParsed;
  FCurrentTime := Clamped(TimeSec, 0.0, FDuration);
  Result := 0;
  for I := 0 to High(FTracks) do
    if ApplySingleTrackAtTime(FTracks[I], FCurrentTime) then
      Inc(Result);
end;

procedure TCastleSequencePlayer.FireCuesInRange(
  const FromTime, ToTime: Single; const ForwardDir: Boolean);
var
  I: Integer;
  T: Single;
begin
  if not Assigned(FOnCueEvent) then
    Exit;
  for I := 0 to High(FCues) do
  begin
    T := FCues[I].TimeSec;
    if ForwardDir then
    begin
      if (T > FromTime) and (T <= ToTime + 1e-6) then
        FOnCueEvent(Self, FCues[I].CueName, FCues[I].Payload, T);
    end else
    begin
      if (T < FromTime) and (T >= ToTime - 1e-6) then
        FOnCueEvent(Self, FCues[I].CueName, FCues[I].Payload, T);
    end;
  end;
end;

procedure TCastleSequencePlayer.Play;
begin
  EnsureParsed;
  if (FPlaybackMode = spmOnce) and (FCurrentTime >= FDuration - 1e-5) then
    FCurrentTime := 0.0;
  FPlaying := true;
  EvaluateAtTime(FCurrentTime);
end;

procedure TCastleSequencePlayer.Pause;
begin
  FPlaying := false;
end;

procedure TCastleSequencePlayer.Stop;
begin
  FPlaying := false;
  FCurrentTime := 0.0;
  FPingPongDirection := 1.0;
  EvaluateAtTime(0.0);
end;

procedure TCastleSequencePlayer.Rewind;
begin
  FCurrentTime := 0.0;
  FPingPongDirection := 1.0;
  EvaluateAtTime(0.0);
end;

procedure TCastleSequencePlayer.Step(const SecondsPassed: Single);
var
  OldTime, Delta, NewTime: Single;
begin
  if (not FPlaying) or (SecondsPassed <= 0) then
    Exit;
  EnsureParsed;
  OldTime := FCurrentTime;
  Delta := SecondsPassed * FTimeScale;

  case FPlaybackMode of
    spmOnce:
      begin
        NewTime := OldTime + Delta;
        if NewTime >= FDuration then
        begin
          NewTime := FDuration;
          FPlaying := false;
        end;
        FireCuesInRange(OldTime, NewTime, true);
        EvaluateAtTime(NewTime);
      end;

    spmLoop:
      begin
        NewTime := OldTime + Delta;
        if NewTime >= FDuration then
        begin
          FireCuesInRange(OldTime, FDuration, true);
          NewTime := Frac(NewTime / FDuration) * FDuration;
          FireCuesInRange(-0.0001, NewTime, true);
        end else
          FireCuesInRange(OldTime, NewTime, true);
        EvaluateAtTime(NewTime);
      end;

    spmPingPong:
      begin
        NewTime := OldTime + Delta * FPingPongDirection;
        if NewTime >= FDuration then
        begin
          FireCuesInRange(OldTime, FDuration, true);
          NewTime := FDuration - (NewTime - FDuration);
          NewTime := Clamped(NewTime, 0.0, FDuration);
          FPingPongDirection := -1.0;
        end else
        if NewTime <= 0.0 then
        begin
          FireCuesInRange(OldTime, 0.0, false);
          NewTime := Abs(NewTime);
          NewTime := Clamped(NewTime, 0.0, FDuration);
          FPingPongDirection := 1.0;
        end else
          FireCuesInRange(OldTime, NewTime, FPingPongDirection >= 0);
        EvaluateAtTime(NewTime);
      end;
  end;
end;

function TCastleSequencePlayer.TrackCount: Integer;
begin
  EnsureParsed;
  Result := Length(FTracks);
end;

function TCastleSequencePlayer.TotalKeyCount: Integer;
var
  I: Integer;
begin
  EnsureParsed;
  Result := 0;
  for I := 0 to High(FTracks) do
    Inc(Result, Length(FTracks[I].Keys));
end;

function TCastleSequencePlayer.CueCount: Integer;
begin
  EnsureParsed;
  Result := Length(FCues);
end;

function TCastleSequencePlayer.GetTracksSnapshot: TSequenceTrackDataArray;
var
  I: Integer;
begin
  EnsureParsed;
  SetLength(Result, Length(FTracks));
  for I := 0 to High(FTracks) do
  begin
    Result[I] := FTracks[I];
    Result[I].Keys := Copy(FTracks[I].Keys, 0, Length(FTracks[I].Keys));
  end;
end;

function TCastleSequencePlayer.GetCuesSnapshot: TSequenceCueDataArray;
begin
  EnsureParsed;
  Result := Copy(FCues, 0, Length(FCues));
end;

function TCastleSequencePlayer.SequenceSummaryBadge: String;
var
  TitlePart: String;
begin
  EnsureParsed;
  if Trim(FSequenceLabel) <> '' then
    TitlePart := Trim(FSequenceLabel) + ' '
  else
    TitlePart := '';
  Result := Format('[Seq:%s%dT/%dK %.1fs]',
    [TitlePart, Length(FTracks), TotalKeyCount, FDuration]);
end;

{ TCastleSequenceRunnerBehavior ---------------------------------------------- }

constructor TCastleSequenceRunnerBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPlayerObserver := TFreeNotificationObserver.Create(Self);
  FPlayerObserver.OnFreeNotification := {$ifdef FPC}@{$endif}PlayerFreeNotification;
end;

destructor TCastleSequenceRunnerBehavior.Destroy;
begin
  inherited;
end;

function TCastleSequenceRunnerBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if PropertyName = 'SequencePlayer' then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSequenceRunnerBehavior.SetSequencePlayer(
  const Value: TCastleSequencePlayer);
begin
  if FSequencePlayer = Value then
    Exit;
  FSequencePlayer := Value;
  FPlayerObserver.Observed := Value;
end;

procedure TCastleSequenceRunnerBehavior.PlayerFreeNotification(
  const Sender: TFreeNotificationObserver);
begin
  FSequencePlayer := nil;
end;

procedure TCastleSequenceRunnerBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited;
  if (not CastleDesignMode) and (FSequencePlayer <> nil) then
    FSequencePlayer.Step(SecondsPassed);
end;

initialization
  RegisterSerializableComponent(TCastleSequencePlayer,
    ['Non-Visual', 'Sequence Player (Cinematic Timeline)']);
  RegisterSerializableComponent(TCastleSequenceRunnerBehavior,
    ['Behavior', 'Sequence Runner (Auto-Advance Timeline)']);
end.
