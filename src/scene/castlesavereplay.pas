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

{ SaveGame Slot Manager, Schema-Versioned World-State Checkpoint Snapshotter &
  Deterministic Transform/Event Replay Recorder (@link(TCastleSaveSlotManager),
  @link(TCastleReplayRecorder))
  (Phase 315 — UE 6.0+ SaveGame & Replay System Parity). }
unit CastleSaveReplay;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Generics.Collections, fpjson,
  CastleVectors, CastleClassUtils;

type
  { Persisted SaveGame / Checkpoint slot metadata + world snapshot payload. }
  TSaveSlotRecord = class
  public
    SlotId: String;
    SlotTitle: String;
    SchemaVersion: Integer;
    TimestampIso: String;
    PlaytimeSec: Single;
    SnapshotJson: String;
    constructor Create;
  end;
  TSaveSlotRecordList = {$ifdef FPC}specialize{$endif} TObjectList<TSaveSlotRecord>;

  { Schema-upgrade callback invoked when loading a snapshot saved with
    @code(FromVersion < SchemaVersion). }
  TSaveSchemaMigrateEvent = procedure(Sender: TObject;
    const FromVersion, ToVersion: Integer;
    const WorldVars: TStringList;
    const RootSnapshotObj: TJSONObject) of object;

  { Non-visual SaveGame slot & schema-versioned world-state checkpoint manager
    (@link(TCastleComponent)) capturing and restoring named @link(TCastleTransform)
    poses/visibility, @link(TCastleAbilitySystemBehavior) attributes/tags/cooldowns,
    @link(TCastleQuestTracker) quest progression, and custom world variables. }
  TCastleSaveSlotManager = class(TCastleComponent)
  public
    const
      DefaultSchemaVersion = 2;
  strict private
    FSchemaVersion: Integer;
    FPlaytimeSec: Single;
    FWorldVariables: TStringList;
    FSlots: TSaveSlotRecordList;
    FOnMigrateSchema: TSaveSchemaMigrateEvent;

    procedure SetSchemaVersion(const Value: Integer);
    function GetWorldVarsJson: String;
    procedure SetWorldVarsJson(const Value: String);
    function GetSlotsJson: String;
    procedure SetSlotsJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure SetWorldVar(const AKey, AValue: String);
    function GetWorldVar(const AKey: String; const ADefault: String = ''): String;

    { Capture full world-state snapshot JSON from @code(RootComp) / @code(DesignOwner). }
    function CaptureWorldSnapshotJson(const RootComp: TComponent;
      const DesignOwner: TComponent = nil): String;

    { Restore world-state snapshot JSON onto @code(RootComp) / @code(DesignOwner),
      upgrading legacy schema versions automatically when @code(SavedVersion < SchemaVersion). }
    function RestoreWorldSnapshotJson(const RootComp: TComponent;
      const AJson: String; const DesignOwner: TComponent = nil): Boolean;

    function SaveSlot(const ASlotId, ASlotTitle: String;
      const RootComp: TComponent; const DesignOwner: TComponent = nil): Integer;
    function LoadSlot(const ASlotId: String;
      const RootComp: TComponent; const DesignOwner: TComponent = nil): Boolean;
    function FindSlot(const ASlotId: String): TSaveSlotRecord;
    function DeleteSlot(const ASlotId: String): Boolean;
    procedure ClearSlots;

    function SaveSummaryBadge: String;

    property WorldVariables: TStringList read FWorldVariables;
    property Slots: TSaveSlotRecordList read FSlots;
    property OnMigrateSchema: TSaveSchemaMigrateEvent
      read FOnMigrateSchema write FOnMigrateSchema;
  published
    property SchemaVersion: Integer
      read FSchemaVersion write SetSchemaVersion default DefaultSchemaVersion;
    property PlaytimeSec: Single read FPlaytimeSec write FPlaytimeSec;
    property WorldVarsJson: String read GetWorldVarsJson write SetWorldVarsJson;
    property SlotsJson: String read GetSlotsJson write SetSlotsJson;
  end;

  { Single transform pose sample inside a @link(TReplayKeyframe). }
  TReplayTransformSample = class
  public
    TransformName: String;
    Translation: TVector3;
    Rotation: TVector4;
    Scale: TVector3;
    Exists: Boolean;
    constructor Create;
  end;
  TReplayTransformSampleList = {$ifdef FPC}specialize{$endif} TObjectList<TReplayTransformSample>;

  { Deterministic world keyframe recorded at @code(TimeSec). }
  TReplayKeyframe = class
  public
    TimeSec: Single;
    Samples: TReplayTransformSampleList;
    constructor Create;
    destructor Destroy; override;
    function FindSample(const ATransformName: String): TReplayTransformSample;
  end;
  TReplayKeyframeList = {$ifdef FPC}specialize{$endif} TObjectList<TReplayKeyframe>;

  { Deterministic cue/event marker recorded on the replay timeline. }
  TReplayCueEvent = class
  public
    TimeSec: Single;
    CueId: String;
    Payload: String;
  end;
  TReplayCueEventList = {$ifdef FPC}specialize{$endif} TObjectList<TReplayCueEvent>;

  { Fired when @link(TCastleReplayRecorder.ScrubToTime) crosses a recorded cue marker. }
  TReplayCueFiredEvent = procedure(Sender: TObject;
    const ATimeSec: Single; const ACueId, APayload: String) of object;

  { Deterministic world transform & gameplay cue replay recorder and timeline
    scrubber (@link(TCastleComponent)) supporting linear + quaternion SLerp
    pose interpolation at arbitrary @code(TimeSec). }
  TCastleReplayRecorder = class(TCastleComponent)
  public
    const
      DefaultMaxDurationSec = 60.0;
      DefaultSampleRateHz = 20.0;
  strict private
    FMaxDurationSec: Single;
    FSampleRateHz: Single;
    FKeyframes: TReplayKeyframeList;
    FCueEvents: TReplayCueEventList;
    FCurrentScrubTimeSec: Single;
    FOnCueFired: TReplayCueFiredEvent;

    procedure SetMaxDurationSec(const Value: Single);
    procedure SetSampleRateHz(const Value: Single);
    function GetDurationSec: Single;
    function GetFrameCount: Integer;
    function GetReplayJson: String;
    procedure SetReplayJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearReplay;

    { Record a deterministic keyframe of all named non-transient transforms.
      For the very first keyframe when @code(Dt <= 0), records at @code(t = 0.0);
      otherwise advances timeline timestamp by @code(Max(0, Dt)). }
    procedure RecordFrame(const RootComp: TComponent; const Dt: Single;
      const DesignOwner: TComponent = nil);

    { Record a deterministic gameplay cue marker at current @link(DurationSec). }
    procedure RecordCue(const ACueId: String; const APayload: String = '');

    { Interpolate all recorded transforms to @code(ATimeSec) (linear pos/scale +
      quaternion SLerp rotation) and fire @link(OnCueFired) for crossed cues. }
    procedure ScrubToTime(const RootComp: TComponent; const ATimeSec: Single;
      const DesignOwner: TComponent = nil);

    { Populate @code(OutCues) with @code('CueId:Payload') strings in @code([ATimeStart .. ATimeEnd]). }
    procedure CollectCuesInRange(const ATimeStart, ATimeEnd: Single;
      const OutCues: TStrings);

    function ExportReplayJson: String;
    procedure ImportReplayJson(const AJson: String);

    function ReplaySummaryBadge: String;

    property Keyframes: TReplayKeyframeList read FKeyframes;
    property CueEvents: TReplayCueEventList read FCueEvents;
    property DurationSec: Single read GetDurationSec;
    property FrameCount: Integer read GetFrameCount;
    property CurrentScrubTimeSec: Single read FCurrentScrubTimeSec;
    property OnCueFired: TReplayCueFiredEvent read FOnCueFired write FOnCueFired;
  published
    property MaxDurationSec: Single
      read FMaxDurationSec write SetMaxDurationSec {$ifdef FPC}default DefaultMaxDurationSec{$endif};
    property SampleRateHz: Single
      read FSampleRateHz write SetSampleRateHz {$ifdef FPC}default DefaultSampleRateHz{$endif};
    property ReplayJson: String read GetReplayJson write SetReplayJson;
  end;

implementation

uses
  Math, jsonparser,
  CastleQuaternions, CastleComponentSerialize, CastleUtils,
  CastleTransform, CastleViewport, CastleUIControls,
  CastleGameplayAbility, CastleDialogueQuest;

procedure CollectWorldTargets(const RootComp, DesignOwner: TComponent;
  const Transforms, GasSystems, QuestTrackers: Classes.TList);

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if C = nil then
      Exit;
    if (C is TCastleTransform) and (not (C is TCastleAbstractRootTransform)) and
       (not (csTransient in C.ComponentStyle)) then
    begin
      if (C.Name <> '') and (Transforms.IndexOf(C) < 0) then
        Transforms.Add(C);
    end;
    if (C is TCastleAbilitySystemBehavior) and (GasSystems.IndexOf(C) < 0) then
      GasSystems.Add(C);
    if (C is TCastleQuestTracker) and (QuestTrackers.IndexOf(C) < 0) then
      QuestTrackers.Add(C);

    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if not (csTransient in T.ComponentStyle) then
      begin
        for I := 0 to T.BehaviorsCount - 1 do
          Traverse(T.Behaviors[I]);
        for I := 0 to T.Count - 1 do
          Traverse(T[I]);
      end;
    end;
  end;

var
  I: Integer;
begin
  Traverse(RootComp);
  if DesignOwner <> nil then
    for I := 0 to DesignOwner.ComponentCount - 1 do
      Traverse(DesignOwner.Components[I]);
end;

function SafeAxisAngleForSlerp(const R: TVector4): TVector4;
begin
  if (Abs(R.X) + Abs(R.Y) + Abs(R.Z)) < 1.0e-5 then
    Result := Vector4(0.0, 1.0, 0.0, 0.0)
  else
    Result := R;
end;

function Vec3ToJsonArr(const V: TVector3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(V.X);
  Result.Add(V.Y);
  Result.Add(V.Z);
end;

function JsonArrToVec3(const Arr: TJSONArray; const ADef: TVector3): TVector3;
begin
  if (Arr <> nil) and (Arr.Count >= 3) then
    Result := Vector3(Arr.Floats[0], Arr.Floats[1], Arr.Floats[2])
  else
    Result := ADef;
end;

function Vec4ToJsonArr(const V: TVector4): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(V.X);
  Result.Add(V.Y);
  Result.Add(V.Z);
  Result.Add(V.W);
end;

function JsonArrToVec4(const Arr: TJSONArray; const ADef: TVector4): TVector4;
begin
  if (Arr <> nil) and (Arr.Count >= 4) then
    Result := Vector4(Arr.Floats[0], Arr.Floats[1], Arr.Floats[2], Arr.Floats[3])
  else
    Result := ADef;
end;

{ TSaveSlotRecord ------------------------------------------------------------ }

constructor TSaveSlotRecord.Create;
begin
  inherited Create;
  SlotId := 'Slot0';
  SlotTitle := 'QuickSave';
  SchemaVersion := TCastleSaveSlotManager.DefaultSchemaVersion;
  TimestampIso := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  PlaytimeSec := 0.0;
  SnapshotJson := '';
end;

{ TCastleSaveSlotManager ----------------------------------------------------- }

constructor TCastleSaveSlotManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSchemaVersion := DefaultSchemaVersion;
  FPlaytimeSec := 0.0;
  FWorldVariables := TStringList.Create;
  FWorldVariables.NameValueSeparator := '=';
  FSlots := TSaveSlotRecordList.Create(True);
end;

destructor TCastleSaveSlotManager.Destroy;
begin
  FreeAndNil(FSlots);
  FreeAndNil(FWorldVariables);
  inherited;
end;

function TCastleSaveSlotManager.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'SchemaVersion', 'PlaytimeSec', 'WorldVarsJson', 'SlotsJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSaveSlotManager.SetSchemaVersion(const Value: Integer);
begin
  FSchemaVersion := Max(1, Value);
end;

procedure TCastleSaveSlotManager.SetWorldVar(const AKey, AValue: String);
begin
  if Trim(AKey) <> '' then
    FWorldVariables.Values[Trim(AKey)] := AValue;
end;

function TCastleSaveSlotManager.GetWorldVar(const AKey: String; const ADefault: String): String;
var
  Idx: Integer;
begin
  Idx := FWorldVariables.IndexOfName(Trim(AKey));
  if Idx >= 0 then
    Result := FWorldVariables.ValueFromIndex[Idx]
  else
    Result := ADefault;
end;

function TCastleSaveSlotManager.GetWorldVarsJson: String;
var
  Obj: TJSONObject;
  I: Integer;
  K: String;
begin
  Obj := TJSONObject.Create;
  try
    for I := 0 to FWorldVariables.Count - 1 do
    begin
      K := FWorldVariables.Names[I];
      if K <> '' then
        Obj.Add(K, FWorldVariables.ValueFromIndex[I]);
    end;
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleSaveSlotManager.SetWorldVarsJson(const Value: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  I: Integer;
begin
  FWorldVariables.Clear;
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      for I := 0 to Obj.Count - 1 do
        FWorldVariables.Values[Obj.Names[I]] := Obj.Items[I].AsString;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleSaveSlotManager.GetSlotsJson: String;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  Arr := TJSONArray.Create;
  try
    for I := 0 to FSlots.Count - 1 do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FSlots[I].SlotId);
      Obj.Add('title', FSlots[I].SlotTitle);
      Obj.Add('schema', FSlots[I].SchemaVersion);
      Obj.Add('timeIso', FSlots[I].TimestampIso);
      Obj.Add('playtime', FSlots[I].PlaytimeSec);
      Obj.Add('snapshot', FSlots[I].SnapshotJson);
      Arr.Add(Obj);
    end;
    Result := Arr.AsJSON;
  finally
    FreeAndNil(Arr);
  end;
end;

procedure TCastleSaveSlotManager.SetSlotsJson(const Value: String);
var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Rec: TSaveSlotRecord;
  I: Integer;
begin
  FSlots.Clear;
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONArray then
    begin
      Arr := TJSONArray(Data);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          Rec := TSaveSlotRecord.Create;
          Rec.SlotId := Obj.Get('id', 'Slot0');
          Rec.SlotTitle := Obj.Get('title', 'QuickSave');
          Rec.SchemaVersion := Obj.Get('schema', DefaultSchemaVersion);
          Rec.TimestampIso := Obj.Get('timeIso', '');
          Rec.PlaytimeSec := Obj.Get('playtime', 0.0);
          Rec.SnapshotJson := Obj.Get('snapshot', '');
          FSlots.Add(Rec);
        end;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

function GasIdentifierKey(const AGas: TCastleAbilitySystemBehavior): String;
begin
  if (AGas.Parent <> nil) and (AGas.Parent.Name <> '') then
    Result := AGas.Parent.Name + '.' + AGas.Name
  else
    Result := AGas.Name;
end;

function TCastleSaveSlotManager.CaptureWorldSnapshotJson(
  const RootComp: TComponent; const DesignOwner: TComponent): String;
var
  Transforms, GasSystems, QuestTrackers: Classes.TList;
  RootObj, VarsObj, ItemObj, CdObj: TJSONObject;
  TransArr, GasArr, QuestArr, TagsArr: TJSONArray;
  I, J: Integer;
  K: String;
  T: TCastleTransform;
  Gas: TCastleAbilitySystemBehavior;
  QT: TCastleQuestTracker;
begin
  Transforms := Classes.TList.Create;
  GasSystems := Classes.TList.Create;
  QuestTrackers := Classes.TList.Create;
  RootObj := TJSONObject.Create;
  try
    CollectWorldTargets(RootComp, DesignOwner, Transforms, GasSystems, QuestTrackers);

    RootObj.Add('schemaVersion', FSchemaVersion);
    RootObj.Add('playtimeSec', FPlaytimeSec);

    VarsObj := TJSONObject.Create;
    for I := 0 to FWorldVariables.Count - 1 do
    begin
      K := FWorldVariables.Names[I];
      if K <> '' then
        VarsObj.Add(K, FWorldVariables.ValueFromIndex[I]);
    end;
    RootObj.Add('worldVars', VarsObj);

    TransArr := TJSONArray.Create;
    for I := 0 to Transforms.Count - 1 do
    begin
      T := TCastleTransform(Transforms[I]);
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', T.Name);
      ItemObj.Add('pos', Vec3ToJsonArr(T.Translation));
      ItemObj.Add('rot', Vec4ToJsonArr(T.Rotation));
      ItemObj.Add('scale', Vec3ToJsonArr(T.Scale));
      ItemObj.Add('exists', T.Exists);
      TransArr.Add(ItemObj);
    end;
    RootObj.Add('transforms', TransArr);

    GasArr := TJSONArray.Create;
    for I := 0 to GasSystems.Count - 1 do
    begin
      Gas := TCastleAbilitySystemBehavior(GasSystems[I]);
      ItemObj := TJSONObject.Create;
      ItemObj.Add('key', GasIdentifierKey(Gas));
      ItemObj.Add('configJson', Gas.ConfigJson);

      TagsArr := TJSONArray.Create;
      for J := 0 to Gas.OwnedTags.Count - 1 do
        TagsArr.Add(Gas.OwnedTags[J]);
      ItemObj.Add('ownedTags', TagsArr);

      CdObj := TJSONObject.Create;
      for J := 0 to Gas.Abilities.Count - 1 do
        CdObj.Add(Gas.Abilities[J].AbilityId, Gas.Abilities[J].RemainingCooldownSec);
      ItemObj.Add('cooldowns', CdObj);

      GasArr.Add(ItemObj);
    end;
    RootObj.Add('gasSystems', GasArr);

    QuestArr := TJSONArray.Create;
    for I := 0 to QuestTrackers.Count - 1 do
    begin
      QT := TCastleQuestTracker(QuestTrackers[I]);
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', QT.Name);
      ItemObj.Add('questsJson', QT.QuestsJson);
      ItemObj.Add('activeTagsCsv', QT.ActiveTagsCsv);
      QuestArr.Add(ItemObj);
    end;
    RootObj.Add('questTrackers', QuestArr);

    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
    FreeAndNil(QuestTrackers);
    FreeAndNil(GasSystems);
    FreeAndNil(Transforms);
  end;
end;

function TCastleSaveSlotManager.RestoreWorldSnapshotJson(
  const RootComp: TComponent; const AJson: String;
  const DesignOwner: TComponent): Boolean;
var
  Data: TJSONData;
  RootObj, VarsObj, ItemObj, CdObj: TJSONObject;
  Arr, TagsArr: TJSONArray;
  Transforms, GasSystems, QuestTrackers: Classes.TList;
  SavedVersion, I, J, KIdx: Integer;
  NodeKey: String;
  T: TCastleTransform;
  Gas: TCastleAbilitySystemBehavior;
  AbDef: TGasAbilityDef;
  QT: TCastleQuestTracker;
begin
  Result := False;
  if Trim(AJson) = '' then
    Exit;

  Data := GetJSON(AJson);
  Transforms := Classes.TList.Create;
  GasSystems := Classes.TList.Create;
  QuestTrackers := Classes.TList.Create;
  try
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);
    CollectWorldTargets(RootComp, DesignOwner, Transforms, GasSystems, QuestTrackers);

    SavedVersion := RootObj.Get('schemaVersion', 1);
    FPlaytimeSec := RootObj.Get('playtimeSec', FPlaytimeSec);

    FWorldVariables.Clear;
    VarsObj := RootObj.Find('worldVars', jtObject) as TJSONObject;
    if VarsObj <> nil then
      for I := 0 to VarsObj.Count - 1 do
        FWorldVariables.Values[VarsObj.Names[I]] := VarsObj.Items[I].AsString;

    { Automatic schema migration when loading an older save into current SchemaVersion }
    if SavedVersion < FSchemaVersion then
    begin
      { Built-in v1 -> v2 upgrade: promote legacy 'PlayerGold' to 'Economy.Gold' }
      if (SavedVersion <= 1) and (FSchemaVersion >= 2) and
         (FWorldVariables.IndexOfName('PlayerGold') >= 0) and
         (FWorldVariables.IndexOfName('Economy.Gold') < 0) then
      begin
        FWorldVariables.Values['Economy.Gold'] := FWorldVariables.Values['PlayerGold'];
      end;
      FWorldVariables.Values['__MigratedFromSchema'] := IntToStr(SavedVersion);

      if Assigned(FOnMigrateSchema) then
        FOnMigrateSchema(Self, SavedVersion, FSchemaVersion, FWorldVariables, RootObj);
    end;

    Arr := RootObj.Find('transforms', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          NodeKey := ItemObj.Get('name', '');
          for J := 0 to Transforms.Count - 1 do
          begin
            T := TCastleTransform(Transforms[J]);
            if SameText(T.Name, NodeKey) then
            begin
              T.Translation := JsonArrToVec3(ItemObj.Find('pos', jtArray) as TJSONArray, T.Translation);
              T.Rotation := JsonArrToVec4(ItemObj.Find('rot', jtArray) as TJSONArray, T.Rotation);
              T.Scale := JsonArrToVec3(ItemObj.Find('scale', jtArray) as TJSONArray, T.Scale);
              T.Exists := ItemObj.Get('exists', T.Exists);
              Break;
            end;
          end;
        end;

    Arr := RootObj.Find('gasSystems', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          NodeKey := ItemObj.Get('key', '');
          for J := 0 to GasSystems.Count - 1 do
          begin
            Gas := TCastleAbilitySystemBehavior(GasSystems[J]);
            if SameText(GasIdentifierKey(Gas), NodeKey) then
            begin
              Gas.ClearActiveEffects;
              Gas.ConfigJson := ItemObj.Get('configJson', Gas.ConfigJson);
              Gas.OwnedTags.Clear;
              TagsArr := ItemObj.Find('ownedTags', jtArray) as TJSONArray;
              if TagsArr <> nil then
                for KIdx := 0 to TagsArr.Count - 1 do
                  Gas.GrantTag(TagsArr.Strings[KIdx]);

              CdObj := ItemObj.Find('cooldowns', jtObject) as TJSONObject;
              if CdObj <> nil then
                for KIdx := 0 to Gas.Abilities.Count - 1 do
                begin
                  AbDef := Gas.Abilities[KIdx];
                  AbDef.RemainingCooldownSec := CdObj.Get(AbDef.AbilityId, 0.0);
                  Gas.Abilities[KIdx] := AbDef;
                end;
              Break;
            end;
          end;
        end;

    Arr := RootObj.Find('questTrackers', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          NodeKey := ItemObj.Get('name', '');
          for J := 0 to QuestTrackers.Count - 1 do
          begin
            QT := TCastleQuestTracker(QuestTrackers[J]);
            if SameText(QT.Name, NodeKey) then
            begin
              QT.QuestsJson := ItemObj.Get('questsJson', QT.QuestsJson);
              QT.ActiveTagsCsv := ItemObj.Get('activeTagsCsv', QT.ActiveTagsCsv);
              Break;
            end;
          end;
        end;

    Result := True;
  finally
    FreeAndNil(QuestTrackers);
    FreeAndNil(GasSystems);
    FreeAndNil(Transforms);
    FreeAndNil(Data);
  end;
end;

function TCastleSaveSlotManager.FindSlot(const ASlotId: String): TSaveSlotRecord;
var
  I: Integer;
begin
  for I := 0 to FSlots.Count - 1 do
    if SameText(FSlots[I].SlotId, ASlotId) then
      Exit(FSlots[I]);
  Result := nil;
end;

function TCastleSaveSlotManager.SaveSlot(const ASlotId, ASlotTitle: String;
  const RootComp: TComponent; const DesignOwner: TComponent): Integer;
var
  Rec: TSaveSlotRecord;
  I: Integer;
begin
  Rec := nil;
  Result := -1;
  for I := 0 to FSlots.Count - 1 do
    if SameText(FSlots[I].SlotId, ASlotId) then
    begin
      Rec := FSlots[I];
      Result := I;
      Break;
    end;

  if Rec = nil then
  begin
    Rec := TSaveSlotRecord.Create;
    Rec.SlotId := ASlotId;
    Result := FSlots.Add(Rec);
  end;

  Rec.SlotTitle := ASlotTitle;
  Rec.SchemaVersion := FSchemaVersion;
  Rec.TimestampIso := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
  Rec.PlaytimeSec := FPlaytimeSec;
  Rec.SnapshotJson := CaptureWorldSnapshotJson(RootComp, DesignOwner);
end;

function TCastleSaveSlotManager.LoadSlot(const ASlotId: String;
  const RootComp: TComponent; const DesignOwner: TComponent): Boolean;
var
  Rec: TSaveSlotRecord;
begin
  Rec := FindSlot(ASlotId);
  if Rec = nil then
    Exit(False);
  Result := RestoreWorldSnapshotJson(RootComp, Rec.SnapshotJson, DesignOwner);
end;

function TCastleSaveSlotManager.DeleteSlot(const ASlotId: String): Boolean;
var
  I: Integer;
begin
  for I := 0 to FSlots.Count - 1 do
    if SameText(FSlots[I].SlotId, ASlotId) then
    begin
      FSlots.Delete(I);
      Exit(True);
    end;
  Result := False;
end;

procedure TCastleSaveSlotManager.ClearSlots;
begin
  FSlots.Clear;
end;

function TCastleSaveSlotManager.SaveSummaryBadge: String;
begin
  Result := Format('[SaveMgr:v%d %d slots]', [FSchemaVersion, FSlots.Count]);
end;

{ TReplayTransformSample & TReplayKeyframe ----------------------------------- }

constructor TReplayTransformSample.Create;
begin
  inherited Create;
  Translation := TVector3.Zero;
  Rotation := Vector4(0.0, 1.0, 0.0, 0.0);
  Scale := Vector3(1.0, 1.0, 1.0);
  Exists := True;
end;

constructor TReplayKeyframe.Create;
begin
  inherited Create;
  TimeSec := 0.0;
  Samples := TReplayTransformSampleList.Create(True);
end;

destructor TReplayKeyframe.Destroy;
begin
  FreeAndNil(Samples);
  inherited;
end;

function TReplayKeyframe.FindSample(const ATransformName: String): TReplayTransformSample;
var
  I: Integer;
begin
  for I := 0 to Samples.Count - 1 do
    if SameText(Samples[I].TransformName, ATransformName) then
      Exit(Samples[I]);
  Result := nil;
end;

{ TCastleReplayRecorder ------------------------------------------------------ }

constructor TCastleReplayRecorder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxDurationSec := DefaultMaxDurationSec;
  FSampleRateHz := DefaultSampleRateHz;
  FKeyframes := TReplayKeyframeList.Create(True);
  FCueEvents := TReplayCueEventList.Create(True);
  FCurrentScrubTimeSec := 0.0;
end;

destructor TCastleReplayRecorder.Destroy;
begin
  FreeAndNil(FCueEvents);
  FreeAndNil(FKeyframes);
  inherited;
end;

function TCastleReplayRecorder.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'MaxDurationSec', 'SampleRateHz', 'ReplayJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleReplayRecorder.SetMaxDurationSec(const Value: Single);
begin
  FMaxDurationSec := Clamped(Value, 1.0, 3600.0);
end;

procedure TCastleReplayRecorder.SetSampleRateHz(const Value: Single);
begin
  FSampleRateHz := Clamped(Value, 1.0, 120.0);
end;

function TCastleReplayRecorder.GetDurationSec: Single;
begin
  if FKeyframes.Count > 0 then
    Result := FKeyframes[FKeyframes.Count - 1].TimeSec
  else
    Result := 0.0;
end;

function TCastleReplayRecorder.GetFrameCount: Integer;
begin
  Result := FKeyframes.Count;
end;

procedure TCastleReplayRecorder.ClearReplay;
begin
  FKeyframes.Clear;
  FCueEvents.Clear;
  FCurrentScrubTimeSec := 0.0;
end;

procedure TCastleReplayRecorder.RecordFrame(const RootComp: TComponent;
  const Dt: Single; const DesignOwner: TComponent);
var
  Transforms, GasDummy, QuestDummy: Classes.TList;
  KF: TReplayKeyframe;
  Sample: TReplayTransformSample;
  T: TCastleTransform;
  NextTime, TrimBefore: Single;
  I: Integer;
begin
  Transforms := Classes.TList.Create;
  GasDummy := Classes.TList.Create;
  QuestDummy := Classes.TList.Create;
  try
    CollectWorldTargets(RootComp, DesignOwner, Transforms, GasDummy, QuestDummy);

    if FKeyframes.Count = 0 then
      NextTime := Max(0.0, Dt)
    else
      NextTime := FKeyframes[FKeyframes.Count - 1].TimeSec + Max(0.0, Dt);

    KF := TReplayKeyframe.Create;
    KF.TimeSec := NextTime;
    for I := 0 to Transforms.Count - 1 do
    begin
      T := TCastleTransform(Transforms[I]);
      Sample := TReplayTransformSample.Create;
      Sample.TransformName := T.Name;
      Sample.Translation := T.Translation;
      Sample.Rotation := T.Rotation;
      Sample.Scale := T.Scale;
      Sample.Exists := T.Exists;
      KF.Samples.Add(Sample);
    end;
    FKeyframes.Add(KF);
    FCurrentScrubTimeSec := NextTime;

    { Enforce rolling MaxDurationSec ring window }
    if NextTime > FMaxDurationSec then
    begin
      TrimBefore := NextTime - FMaxDurationSec;
      while (FKeyframes.Count > 2) and (FKeyframes[0].TimeSec < TrimBefore) do
        FKeyframes.Delete(0);
      while (FCueEvents.Count > 0) and (FCueEvents[0].TimeSec < TrimBefore) do
        FCueEvents.Delete(0);
    end;
  finally
    FreeAndNil(QuestDummy);
    FreeAndNil(GasDummy);
    FreeAndNil(Transforms);
  end;
end;

procedure TCastleReplayRecorder.RecordCue(const ACueId: String; const APayload: String);
var
  Cue: TReplayCueEvent;
begin
  Cue := TReplayCueEvent.Create;
  Cue.TimeSec := DurationSec;
  Cue.CueId := ACueId;
  Cue.Payload := APayload;
  FCueEvents.Add(Cue);
end;

procedure TCastleReplayRecorder.CollectCuesInRange(
  const ATimeStart, ATimeEnd: Single; const OutCues: TStrings);
var
  LoT, HiT: Single;
  I: Integer;
begin
  if OutCues = nil then
    Exit;
  LoT := Min(ATimeStart, ATimeEnd) - 1.0e-5;
  HiT := Max(ATimeStart, ATimeEnd) + 1.0e-5;
  for I := 0 to FCueEvents.Count - 1 do
    if (FCueEvents[I].TimeSec >= LoT) and (FCueEvents[I].TimeSec <= HiT) then
      OutCues.Add(FCueEvents[I].CueId + ':' + FCueEvents[I].Payload);
end;

procedure TCastleReplayRecorder.ScrubToTime(const RootComp: TComponent;
  const ATimeSec: Single; const DesignOwner: TComponent);
var
  Transforms, GasDummy, QuestDummy: Classes.TList;
  TargetTime, PrevTime, LoCue, HiCue, Span, Alpha: Single;
  Idx0, Idx1, I: Integer;
  KF0, KF1: TReplayKeyframe;
  S0, S1: TReplayTransformSample;
  T: TCastleTransform;
begin
  if FKeyframes.Count = 0 then
    Exit;

  PrevTime := FCurrentScrubTimeSec;
  TargetTime := Clamped(ATimeSec, FKeyframes[0].TimeSec, DurationSec);
  FCurrentScrubTimeSec := TargetTime;

  Idx0 := 0;
  Idx1 := FKeyframes.Count - 1;
  for I := 0 to FKeyframes.Count - 2 do
    if (TargetTime >= FKeyframes[I].TimeSec) and
       (TargetTime <= FKeyframes[I + 1].TimeSec) then
    begin
      Idx0 := I;
      Idx1 := I + 1;
      Break;
    end;

  KF0 := FKeyframes[Idx0];
  KF1 := FKeyframes[Idx1];
  Span := KF1.TimeSec - KF0.TimeSec;
  if Span > 1.0e-6 then
    Alpha := Clamped((TargetTime - KF0.TimeSec) / Span, 0.0, 1.0)
  else
    Alpha := 0.0;

  Transforms := Classes.TList.Create;
  GasDummy := Classes.TList.Create;
  QuestDummy := Classes.TList.Create;
  try
    CollectWorldTargets(RootComp, DesignOwner, Transforms, GasDummy, QuestDummy);
    for I := 0 to Transforms.Count - 1 do
    begin
      T := TCastleTransform(Transforms[I]);
      S0 := KF0.FindSample(T.Name);
      S1 := KF1.FindSample(T.Name);
      if (S0 <> nil) and (S1 <> nil) then
      begin
        T.Translation := Lerp(Alpha, S0.Translation, S1.Translation);
        T.Scale := Lerp(Alpha, S0.Scale, S1.Scale);
        T.Rotation := SLerp(Alpha,
          SafeAxisAngleForSlerp(S0.Rotation),
          SafeAxisAngleForSlerp(S1.Rotation));
        if Alpha < 0.5 then
          T.Exists := S0.Exists
        else
          T.Exists := S1.Exists;
      end else
      if S0 <> nil then
      begin
        T.Translation := S0.Translation;
        T.Scale := S0.Scale;
        T.Rotation := S0.Rotation;
        T.Exists := S0.Exists;
      end;
    end;
  finally
    FreeAndNil(QuestDummy);
    FreeAndNil(GasDummy);
    FreeAndNil(Transforms);
  end;

  if Assigned(FOnCueFired) and (Abs(TargetTime - PrevTime) > 1.0e-6) then
  begin
    LoCue := Min(PrevTime, TargetTime);
    HiCue := Max(PrevTime, TargetTime);
    for I := 0 to FCueEvents.Count - 1 do
      if (FCueEvents[I].TimeSec >= LoCue - 1.0e-5) and
         (FCueEvents[I].TimeSec <= HiCue + 1.0e-5) then
        FOnCueFired(Self, FCueEvents[I].TimeSec, FCueEvents[I].CueId, FCueEvents[I].Payload);
  end;
end;

function TCastleReplayRecorder.ExportReplayJson: String;
var
  RootObj, KfObj, SampObj, CueObj: TJSONObject;
  KfArr, SampArr, CueArr: TJSONArray;
  I, J: Integer;
  KF: TReplayKeyframe;
  S: TReplayTransformSample;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('maxDurationSec', FMaxDurationSec);
    RootObj.Add('sampleRateHz', FSampleRateHz);

    KfArr := TJSONArray.Create;
    for I := 0 to FKeyframes.Count - 1 do
    begin
      KF := FKeyframes[I];
      KfObj := TJSONObject.Create;
      KfObj.Add('t', KF.TimeSec);
      SampArr := TJSONArray.Create;
      for J := 0 to KF.Samples.Count - 1 do
      begin
        S := KF.Samples[J];
        SampObj := TJSONObject.Create;
        SampObj.Add('n', S.TransformName);
        SampObj.Add('p', Vec3ToJsonArr(S.Translation));
        SampObj.Add('r', Vec4ToJsonArr(S.Rotation));
        SampObj.Add('s', Vec3ToJsonArr(S.Scale));
        SampObj.Add('e', S.Exists);
        SampArr.Add(SampObj);
      end;
      KfObj.Add('samples', SampArr);
      KfArr.Add(KfObj);
    end;
    RootObj.Add('keyframes', KfArr);

    CueArr := TJSONArray.Create;
    for I := 0 to FCueEvents.Count - 1 do
    begin
      CueObj := TJSONObject.Create;
      CueObj.Add('t', FCueEvents[I].TimeSec);
      CueObj.Add('id', FCueEvents[I].CueId);
      CueObj.Add('payload', FCueEvents[I].Payload);
      CueArr.Add(CueObj);
    end;
    RootObj.Add('cues', CueArr);

    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleReplayRecorder.ImportReplayJson(const AJson: String);
var
  Data: TJSONData;
  RootObj, KfObj, SampObj, CueObj: TJSONObject;
  KfArr, SampArr, CueArr: TJSONArray;
  KF: TReplayKeyframe;
  S: TReplayTransformSample;
  Cue: TReplayCueEvent;
  I, J: Integer;
begin
  ClearReplay;
  if Trim(AJson) = '' then
    Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);
    FMaxDurationSec := RootObj.Get('maxDurationSec', FMaxDurationSec);
    FSampleRateHz := RootObj.Get('sampleRateHz', FSampleRateHz);

    KfArr := RootObj.Find('keyframes', jtArray) as TJSONArray;
    if KfArr <> nil then
      for I := 0 to KfArr.Count - 1 do
        if KfArr.Items[I] is TJSONObject then
        begin
          KfObj := TJSONObject(KfArr.Items[I]);
          KF := TReplayKeyframe.Create;
          KF.TimeSec := KfObj.Get('t', 0.0);
          SampArr := KfObj.Find('samples', jtArray) as TJSONArray;
          if SampArr <> nil then
            for J := 0 to SampArr.Count - 1 do
              if SampArr.Items[J] is TJSONObject then
              begin
                SampObj := TJSONObject(SampArr.Items[J]);
                S := TReplayTransformSample.Create;
                S.TransformName := SampObj.Get('n', '');
                S.Translation := JsonArrToVec3(SampObj.Find('p', jtArray) as TJSONArray, TVector3.Zero);
                S.Rotation := JsonArrToVec4(SampObj.Find('r', jtArray) as TJSONArray, Vector4(0, 1, 0, 0));
                S.Scale := JsonArrToVec3(SampObj.Find('s', jtArray) as TJSONArray, Vector3(1, 1, 1));
                S.Exists := SampObj.Get('e', True);
                KF.Samples.Add(S);
              end;
          FKeyframes.Add(KF);
        end;

    CueArr := RootObj.Find('cues', jtArray) as TJSONArray;
    if CueArr <> nil then
      for I := 0 to CueArr.Count - 1 do
        if CueArr.Items[I] is TJSONObject then
        begin
          CueObj := TJSONObject(CueArr.Items[I]);
          Cue := TReplayCueEvent.Create;
          Cue.TimeSec := CueObj.Get('t', 0.0);
          Cue.CueId := CueObj.Get('id', '');
          Cue.Payload := CueObj.Get('payload', '');
          FCueEvents.Add(Cue);
        end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleReplayRecorder.GetReplayJson: String;
begin
  Result := ExportReplayJson;
end;

procedure TCastleReplayRecorder.SetReplayJson(const Value: String);
begin
  ImportReplayJson(Value);
end;

function TCastleReplayRecorder.ReplaySummaryBadge: String;
begin
  Result := Format('[Replay:%d frames %.1fs]', [FKeyframes.Count, DurationSec]);
end;

initialization
  RegisterSerializableComponent(TCastleSaveSlotManager, ['SaveGame & Checkpoint Manager']);
  RegisterSerializableComponent(TCastleReplayRecorder, ['Deterministic Replay Recorder']);
end.
