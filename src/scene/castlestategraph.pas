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

{ Data-driven Visual State Machine & StateTree behavior
  (@link(TCastleStateGraphBehavior)) with typed blackboard variables,
  comparison & elapsed-timer transitions, wildcard @code('*') priority
  interrupts, and entry/exit RTTI/animation/cue actions
  (Phase 288 — UE 5.9 / 6.0 StateTree Parity). }
unit CastleStateGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, FpJson,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Typed blackboard variable kind inside @link(TCastleStateGraphBehavior). }
  TStateBlackboardVarKind = (
    sbkFloat,
    sbkInt,
    sbkBool,
    sbkString
  );

  { Condition operator evaluated on a transition rule. }
  TStateConditionOp = (
    scoAlways,
    scoEqual,
    scoNotEqual,
    scoLess,
    scoLessOrEqual,
    scoGreater,
    scoGreaterOrEqual
  );

  { Action executed when entering or exiting a state node. }
  TStateActionKind = (
    sakSetProperty,
    sakSetBlackboardVar,
    sakPlayAnimation,
    sakFireCue
  );

  { Fired whenever @link(TCastleStateGraphBehavior) transitions between states. }
  TStateTransitionNotifyEvent = procedure (Sender: TObject;
    const FromStateId, ToStateId: String) of object;

  { Fired whenever a @code(sakFireCue) action executes on state entry/exit. }
  TStateCueNotifyEvent = procedure (Sender: TObject;
    const CueName, Payload: String) of object;

  { Blackboard variable definition + current value. }
  TStateBlackboardVarData = record
    VarName: String;
    Kind: TStateBlackboardVarKind;
    DefaultStr: String;
    FloatVal: Single;
    IntVal: Integer;
    BoolVal: Boolean;
    StrVal: String;
  end;
  TStateBlackboardVarDataArray = array of TStateBlackboardVarData;

  { Single state entry or exit action item. }
  TStateActionData = record
    Kind: TStateActionKind;
    TargetName: String;
    KeyOrProp: String;
    ValueStr: String;
    LoopAnim: Boolean;
  end;
  TStateActionDataArray = array of TStateActionData;

  { Visual state node stored inside @link(TCastleStateGraphBehavior). }
  TStateNodeData = record
    StateId: String;
    DisplayName: String;
    CanvasX: Single;
    CanvasY: Single;
    Comment: String;
    EntryActions: TStateActionDataArray;
    ExitActions: TStateActionDataArray;
  end;
  TStateNodeDataArray = array of TStateNodeData;

  { Directed transition rule between states (or @code('*') wildcard Any-State). }
  TStateTransitionData = record
    FromStateId: String;
    ToStateId: String;
    Priority: Integer;
    MinStateElapsedSec: Single;
    VarName: String;
    Op: TStateConditionOp;
    CompareValue: String;
  end;
  TStateTransitionDataArray = array of TStateTransitionData;

  { Data-driven Hierarchical/FSM StateGraph behavior attachable to any
    @link(TCastleTransform). Persists its states, blackboard defaults,
    2D canvas coordinates, actions, and transition rules inside
    diff-friendly @link(GraphJson). }
  TCastleStateGraphBehavior = class(TCastleBehavior)
  strict private
    FGraphLabel: String;
    FInitialStateId: String;
    FAutoRunInRuntime: Boolean;
    FMaxTransitionsPerStep: Integer;
    FGraphJson: String;

    FTargetRoot: TCastleComponent;
    FTargetRootObserver: TFreeNotificationObserver;

    FVariables: TStateBlackboardVarDataArray;
    FStates: TStateNodeDataArray;
    FTransitions: TStateTransitionDataArray;
    FGraphDirty: Boolean;

    FRunning: Boolean;
    FActiveStateId: String;
    FActiveStateElapsed: Single;
    FTotalTransitionCount: Integer;
    FLastPlayedAnimation: String;
    FLastPlayedAnimationTarget: String;

    FOnStateTransition: TStateTransitionNotifyEvent;
    FOnStateCue: TStateCueNotifyEvent;

    procedure SetGraphJson(const Value: String);
    procedure SetMaxTransitionsPerStep(const Value: Integer);
    procedure SetTargetRoot(const Value: TCastleComponent);
    procedure TargetRootFreeNotification(const Sender: TFreeNotificationObserver);

    procedure EnsureParsed;
    procedure RebuildJsonFromMemory;
    function IsNonEmptyGraphJson: Boolean;
    function ResolveActionRoot: TComponent;
    function FindTargetComponent(const ATargetName: String): TComponent;
    procedure ApplyVarFromString(var V: TStateBlackboardVarData; const S: String);
    procedure ExecuteActionList(const Actions: TStateActionDataArray);
    procedure ExecuteSingleAction(const Act: TStateActionData);
    procedure PerformTransitionTo(const NextStateId: String; const FireEvents: Boolean);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Optional explicit root component used to resolve named sibling/child
      components in @code(sakSetProperty) and @code(sakPlayAnimation) actions.
      Falls back to @code(Owner) or @code(Parent) when @nil. }
    property TargetRoot: TCastleComponent read FTargetRoot write SetTargetRoot;

    { Runtime execution controls & live telemetry. }
    property Running: Boolean read FRunning;
    property ActiveStateId: String read FActiveStateId;
    property ActiveStateElapsed: Single read FActiveStateElapsed;
    property TotalTransitionCount: Integer read FTotalTransitionCount;
    property LastPlayedAnimation: String read FLastPlayedAnimation;
    property LastPlayedAnimationTarget: String read FLastPlayedAnimationTarget;

    procedure StartGraph;
    procedure StopGraph;
    procedure ResetGraph;
    procedure StepGraph(const DeltaSec: Single);
    function ForceEnterState(const AStateId: String): Boolean;

    { Blackboard variable authoring & runtime accessors. }
    procedure ClearGraph;
    function FindVariableIndex(const AVarName: String): Integer;
    function VariableCount: Integer;
    function GetVariable(const Index: Integer): TStateBlackboardVarData;
    procedure AddOrUpdateVariable(const AVarName: String;
      const AKind: TStateBlackboardVarKind; const ADefaultValueStr: String);
    function RemoveVariable(const AVarName: String): Boolean;
    procedure ResetBlackboardToDefaults;
    procedure CommitLiveBlackboardToDefaults;

    procedure SetFloat(const AVarName: String; const AValue: Single);
    function GetFloat(const AVarName: String; const ADefault: Single = 0.0): Single;
    procedure SetInt(const AVarName: String; const AValue: Integer);
    function GetInt(const AVarName: String; const ADefault: Integer = 0): Integer;
    procedure SetBool(const AVarName: String; const AValue: Boolean);
    function GetBool(const AVarName: String; const ADefault: Boolean = false): Boolean;
    procedure SetString(const AVarName: String; const AValue: String);
    function GetString(const AVarName: String; const ADefault: String = ''): String;
    function SetBlackboardFromString(const AVarName, AValueStr: String): Boolean;
    function FormatBlackboardValue(const AVarName: String): String;

    { State node authoring & canvas coordinates. }
    function FindStateIndex(const AStateId: String): Integer;
    function StateCount: Integer;
    function GetState(const Index: Integer): TStateNodeData;
    function AddOrUpdateState(const AStateId, ADisplayName: String;
      const AX, AY: Single; const AComment: String = ''): Integer;
    function MoveStateCanvas(const AStateId: String; const AX, AY: Single): Boolean;
    function RemoveState(const AStateId: String): Boolean;
    function AddEntryAction(const AStateId: String; const AKind: TStateActionKind;
      const ATargetName, AKeyOrProp, AValueStr: String;
      const ALoopAnim: Boolean = true): Boolean;
    function AddExitAction(const AStateId: String; const AKind: TStateActionKind;
      const ATargetName, AKeyOrProp, AValueStr: String;
      const ALoopAnim: Boolean = false): Boolean;
    function ClearStateActions(const AStateId: String): Boolean;

    { Transition rule authoring & condition evaluator. }
    function TransitionCount: Integer;
    function GetTransition(const Index: Integer): TStateTransitionData;
    function AddTransition(const AFromStateId, AToStateId: String;
      const AOp: TStateConditionOp; const AVarName, ACompareValue: String;
      const AMinElapsedSec: Single = 0.0; const APriority: Integer = 0): Integer;
    function RemoveTransition(const Index: Integer): Boolean;
    function EvaluateTransitionCondition(const Trans: TStateTransitionData): Boolean;

    { Compact Hierarchy & Inspector card summary badge. }
    function GraphSummaryBadge: String;

    property OnStateTransition: TStateTransitionNotifyEvent
      read FOnStateTransition write FOnStateTransition;
    property OnStateCue: TStateCueNotifyEvent
      read FOnStateCue write FOnStateCue;
  published
    property GraphLabel: String read FGraphLabel write FGraphLabel;
    property InitialStateId: String read FInitialStateId write FInitialStateId;
    property AutoRunInRuntime: Boolean
      read FAutoRunInRuntime write FAutoRunInRuntime default true;
    property MaxTransitionsPerStep: Integer
      read FMaxTransitionsPerStep write SetMaxTransitionsPerStep default 8;
    property GraphJson: String
      read FGraphJson write SetGraphJson stored IsNonEmptyGraphJson;
  end;

function StateVarKindToString(const K: TStateBlackboardVarKind): String;
function StringToStateVarKind(const S: String): TStateBlackboardVarKind;
function StateConditionOpToString(const Op: TStateConditionOp): String;
function StateConditionOpSymbol(const Op: TStateConditionOp): String;
function StringToStateConditionOp(const S: String): TStateConditionOp;
function StateActionKindToString(const K: TStateActionKind): String;
function StringToStateActionKind(const S: String): TStateActionKind;
function FormatTransitionSummary(const Trans: TStateTransitionData): String;

implementation

uses
  Math, StrUtils, TypInfo, JsonParser,
  CastleComponentSerialize, CastleStringUtils,
  CastleSceneCore, CastleScene, CastleUIControls, CastleControls;

function StateVarKindToString(const K: TStateBlackboardVarKind): String;
begin
  case K of
    sbkFloat:  Result := 'float';
    sbkInt:    Result := 'int';
    sbkBool:   Result := 'bool';
    sbkString: Result := 'string';
  end;
end;

function StringToStateVarKind(const S: String): TStateBlackboardVarKind;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'int' then
    Result := sbkInt
  else if (L = 'bool') or (L = 'boolean') then
    Result := sbkBool
  else if L = 'string' then
    Result := sbkString
  else
    Result := sbkFloat;
end;

function StateConditionOpToString(const Op: TStateConditionOp): String;
begin
  case Op of
    scoAlways:         Result := 'always';
    scoEqual:          Result := 'eq';
    scoNotEqual:       Result := 'neq';
    scoLess:           Result := 'lt';
    scoLessOrEqual:    Result := 'lte';
    scoGreater:        Result := 'gt';
    scoGreaterOrEqual: Result := 'gte';
  end;
end;

function StateConditionOpSymbol(const Op: TStateConditionOp): String;
begin
  case Op of
    scoAlways:         Result := 'Always';
    scoEqual:          Result := '==';
    scoNotEqual:       Result := '!=';
    scoLess:           Result := '<';
    scoLessOrEqual:    Result := '<=';
    scoGreater:        Result := '>';
    scoGreaterOrEqual: Result := '>=';
  end;
end;

function StringToStateConditionOp(const S: String): TStateConditionOp;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if (L = 'eq') or (L = '==') or (L = '=') then
    Result := scoEqual
  else if (L = 'neq') or (L = '!=') or (L = '<>') then
    Result := scoNotEqual
  else if (L = 'lt') or (L = '<') then
    Result := scoLess
  else if (L = 'lte') or (L = '<=') then
    Result := scoLessOrEqual
  else if (L = 'gt') or (L = '>') then
    Result := scoGreater
  else if (L = 'gte') or (L = '>=') then
    Result := scoGreaterOrEqual
  else
    Result := scoAlways;
end;

function StateActionKindToString(const K: TStateActionKind): String;
begin
  case K of
    sakSetProperty:      Result := 'set_property';
    sakSetBlackboardVar: Result := 'set_var';
    sakPlayAnimation:    Result := 'play_anim';
    sakFireCue:          Result := 'fire_cue';
  end;
end;

function StringToStateActionKind(const S: String): TStateActionKind;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'set_var' then
    Result := sakSetBlackboardVar
  else if L = 'play_anim' then
    Result := sakPlayAnimation
  else if L = 'fire_cue' then
    Result := sakFireCue
  else
    Result := sakSetProperty;
end;

function FormatTransitionSummary(const Trans: TStateTransitionData): String;
begin
  if Trans.Op = scoAlways then
    Result := 'Always'
  else
    Result := Format('%s %s %s',
      [Trans.VarName, StateConditionOpSymbol(Trans.Op), Trans.CompareValue]);

  if Trans.MinStateElapsedSec > 0.0001 then
    Result := Result + Format(' (t>=%.2fs)', [Trans.MinStateElapsedSec]);
  if Trans.Priority <> 0 then
    Result := Result + Format(' [P%d]', [Trans.Priority]);
end;

function ParseBoolFlexible(const S: String; const ADefault: Boolean = false): Boolean;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if (L = 'true') or (L = '1') or (L = 'yes') or (L = 'on') then
    Result := true
  else if (L = 'false') or (L = '0') or (L = 'no') or (L = 'off') then
    Result := false
  else
    Result := ADefault;
end;

function ParseVec3Flexible(const S: String; out V: TVector3): Boolean;
var
  Tokens: TCastleStringList;
  X, Y, Z: Single;
begin
  Result := false;
  V := TVector3.Zero;
  Tokens := CreateTokens(S, [' ', ',', ';', #9]);
  try
    if (Tokens.Count >= 3) and
       TryStrToFloatDot(Tokens[0], X) and
       TryStrToFloatDot(Tokens[1], Y) and
       TryStrToFloatDot(Tokens[2], Z) then
    begin
      V := Vector3(X, Y, Z);
      Result := true;
    end;
  finally
    FreeAndNil(Tokens);
  end;
end;

function ActionsToJsonArray(const Actions: TStateActionDataArray): TJSONArray;
var
  I: Integer;
  Obj: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(Actions) do
  begin
    Obj := TJSONObject.Create;
    Obj.Add('kind', StateActionKindToString(Actions[I].Kind));
    if Actions[I].TargetName <> '' then
      Obj.Add('target', Actions[I].TargetName);
    Obj.Add('key', Actions[I].KeyOrProp);
    if Actions[I].ValueStr <> '' then
      Obj.Add('value', Actions[I].ValueStr);
    if Actions[I].Kind = sakPlayAnimation then
      Obj.Add('loop', Actions[I].LoopAnim);
    Result.Add(Obj);
  end;
end;

function JsonArrayToActions(const Arr: TJSONArray): TStateActionDataArray;
var
  I: Integer;
  Obj: TJSONObject;
  Act: TStateActionData;
begin
  Result := nil;
  if Arr = nil then
    Exit;
  SetLength(Result, Arr.Count);
  for I := 0 to Arr.Count - 1 do
  begin
    Act := Default(TStateActionData);
    if Arr.Items[I] is TJSONObject then
    begin
      Obj := TJSONObject(Arr.Items[I]);
      Act.Kind := StringToStateActionKind(Obj.Get('kind', 'set_property'));
      Act.TargetName := Obj.Get('target', '');
      Act.KeyOrProp := Obj.Get('key', '');
      Act.ValueStr := Obj.Get('value', '');
      Act.LoopAnim := Obj.Get('loop', true);
    end;
    Result[I] := Act;
  end;
end;

{ TCastleStateGraphBehavior -------------------------------------------------- }

constructor TCastleStateGraphBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGraphLabel := 'StateTree';
  FInitialStateId := '';
  FAutoRunInRuntime := true;
  FMaxTransitionsPerStep := 8;
  FGraphJson := '';
  FGraphDirty := false;
  FRunning := false;
  FActiveStateId := '';
  FActiveStateElapsed := 0.0;
  FTotalTransitionCount := 0;

  FTargetRootObserver := TFreeNotificationObserver.Create(Self);
  FTargetRootObserver.OnFreeNotification := @TargetRootFreeNotification;
end;

destructor TCastleStateGraphBehavior.Destroy;
begin
  inherited Destroy;
end;

function TCastleStateGraphBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'GraphLabel') or
     (PropertyName = 'InitialStateId') or
     (PropertyName = 'AutoRunInRuntime') or
     (PropertyName = 'MaxTransitionsPerStep') or
     (PropertyName = 'GraphJson') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleStateGraphBehavior.Loaded;
begin
  inherited Loaded;
  EnsureParsed;
  if (not CastleDesignMode) and FAutoRunInRuntime then
    StartGraph;
end;

procedure TCastleStateGraphBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if CastleDesignMode then
    Exit;
  if FAutoRunInRuntime and (not FRunning) and (FActiveStateId = '') then
    StartGraph;
  if FRunning then
    StepGraph(SecondsPassed);
end;

procedure TCastleStateGraphBehavior.SetGraphJson(const Value: String);
begin
  if FGraphJson = Value then
    Exit;
  FGraphJson := Value;
  FGraphDirty := true;
  EnsureParsed;
end;

procedure TCastleStateGraphBehavior.SetMaxTransitionsPerStep(const Value: Integer);
begin
  FMaxTransitionsPerStep := Clamped(Value, 1, 64);
end;

procedure TCastleStateGraphBehavior.SetTargetRoot(const Value: TCastleComponent);
begin
  if FTargetRoot = Value then
    Exit;
  FTargetRoot := Value;
  FTargetRootObserver.Observed := Value;
end;

procedure TCastleStateGraphBehavior.TargetRootFreeNotification(
  const Sender: TFreeNotificationObserver);
begin
  FTargetRoot := nil;
end;

function TCastleStateGraphBehavior.IsNonEmptyGraphJson: Boolean;
begin
  Result := Trim(FGraphJson) <> '';
end;

procedure TCastleStateGraphBehavior.ApplyVarFromString(
  var V: TStateBlackboardVarData; const S: String);
var
  F: Single;
  N: Integer;
begin
  case V.Kind of
    sbkFloat:
      begin
        if TryStrToFloatDot(Trim(S), F) then
          V.FloatVal := F
        else
          V.FloatVal := 0.0;
        V.StrVal := FloatToStrDot(V.FloatVal);
      end;
    sbkInt:
      begin
        if TryStrToInt(Trim(S), N) then
          V.IntVal := N
        else
          V.IntVal := 0;
        V.StrVal := IntToStr(V.IntVal);
      end;
    sbkBool:
      begin
        V.BoolVal := ParseBoolFlexible(S, false);
        V.StrVal := BoolToStr(V.BoolVal, 'true', 'false');
      end;
    sbkString:
      V.StrVal := S;
  end;
end;

procedure TCastleStateGraphBehavior.EnsureParsed;
var
  RootData: TJSONData;
  RootObj, ItemObj: TJSONObject;
  VarsArr, StatesArr, TransArr: TJSONArray;
  I: Integer;
  NewVar: TStateBlackboardVarData;
  NewState: TStateNodeData;
  NewTrans: TStateTransitionData;
begin
  if not FGraphDirty then
    Exit;
  FGraphDirty := false;

  SetLength(FVariables, 0);
  SetLength(FStates, 0);
  SetLength(FTransitions, 0);

  if Trim(FGraphJson) = '' then
    Exit;

  RootData := nil;
  try
    try
      RootData := GetJSON(FGraphJson);
    except
      RootData := nil;
    end;

    if not (RootData is TJSONObject) then
      Exit;
    RootObj := TJSONObject(RootData);

    VarsArr := RootObj.Find('variables', jtArray) as TJSONArray;
    if VarsArr <> nil then
    begin
      SetLength(FVariables, VarsArr.Count);
      for I := 0 to VarsArr.Count - 1 do
      begin
        NewVar := Default(TStateBlackboardVarData);
        if VarsArr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(VarsArr.Items[I]);
          NewVar.VarName := ItemObj.Get('name', '');
          NewVar.Kind := StringToStateVarKind(ItemObj.Get('kind', 'float'));
          NewVar.DefaultStr := ItemObj.Get('default', '');
          ApplyVarFromString(NewVar, NewVar.DefaultStr);
        end;
        FVariables[I] := NewVar;
      end;
    end;

    StatesArr := RootObj.Find('states', jtArray) as TJSONArray;
    if StatesArr <> nil then
    begin
      SetLength(FStates, StatesArr.Count);
      for I := 0 to StatesArr.Count - 1 do
      begin
        NewState := Default(TStateNodeData);
        if StatesArr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(StatesArr.Items[I]);
          NewState.StateId := ItemObj.Get('id', '');
          NewState.DisplayName := ItemObj.Get('title', NewState.StateId);
          NewState.CanvasX := ItemObj.Get('x', 80.0 + I * 200.0);
          NewState.CanvasY := ItemObj.Get('y', 140.0);
          NewState.Comment := ItemObj.Get('comment', '');
          NewState.EntryActions := JsonArrayToActions(
            ItemObj.Find('entryActions', jtArray) as TJSONArray);
          NewState.ExitActions := JsonArrayToActions(
            ItemObj.Find('exitActions', jtArray) as TJSONArray);
        end;
        FStates[I] := NewState;
      end;
    end;

    TransArr := RootObj.Find('transitions', jtArray) as TJSONArray;
    if TransArr <> nil then
    begin
      SetLength(FTransitions, TransArr.Count);
      for I := 0 to TransArr.Count - 1 do
      begin
        NewTrans := Default(TStateTransitionData);
        if TransArr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(TransArr.Items[I]);
          NewTrans.FromStateId := ItemObj.Get('from', '');
          NewTrans.ToStateId := ItemObj.Get('to', '');
          NewTrans.Priority := ItemObj.Get('priority', 0);
          NewTrans.MinStateElapsedSec := ItemObj.Get('minElapsed', 0.0);
          NewTrans.VarName := ItemObj.Get('var', '');
          NewTrans.Op := StringToStateConditionOp(ItemObj.Get('op', 'always'));
          NewTrans.CompareValue := ItemObj.Get('value', '');
        end;
        FTransitions[I] := NewTrans;
      end;
    end;
  finally
    FreeAndNil(RootData);
  end;
end;

procedure TCastleStateGraphBehavior.RebuildJsonFromMemory;
var
  RootObj, ItemObj: TJSONObject;
  VarsArr, StatesArr, TransArr: TJSONArray;
  I: Integer;
begin
  if (Length(FVariables) = 0) and (Length(FStates) = 0) and
     (Length(FTransitions) = 0) then
  begin
    FGraphJson := '';
    FGraphDirty := false;
    Exit;
  end;

  RootObj := TJSONObject.Create;
  try
    VarsArr := TJSONArray.Create;
    for I := 0 to High(FVariables) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', FVariables[I].VarName);
      ItemObj.Add('kind', StateVarKindToString(FVariables[I].Kind));
      ItemObj.Add('default', FVariables[I].DefaultStr);
      VarsArr.Add(ItemObj);
    end;
    RootObj.Add('variables', VarsArr);

    StatesArr := TJSONArray.Create;
    for I := 0 to High(FStates) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('id', FStates[I].StateId);
      ItemObj.Add('title', FStates[I].DisplayName);
      ItemObj.Add('x', FStates[I].CanvasX);
      ItemObj.Add('y', FStates[I].CanvasY);
      if FStates[I].Comment <> '' then
        ItemObj.Add('comment', FStates[I].Comment);
      if Length(FStates[I].EntryActions) > 0 then
        ItemObj.Add('entryActions', ActionsToJsonArray(FStates[I].EntryActions));
      if Length(FStates[I].ExitActions) > 0 then
        ItemObj.Add('exitActions', ActionsToJsonArray(FStates[I].ExitActions));
      StatesArr.Add(ItemObj);
    end;
    RootObj.Add('states', StatesArr);

    TransArr := TJSONArray.Create;
    for I := 0 to High(FTransitions) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('from', FTransitions[I].FromStateId);
      ItemObj.Add('to', FTransitions[I].ToStateId);
      if FTransitions[I].Priority <> 0 then
        ItemObj.Add('priority', FTransitions[I].Priority);
      if FTransitions[I].MinStateElapsedSec > 0.0001 then
        ItemObj.Add('minElapsed', FTransitions[I].MinStateElapsedSec);
      if FTransitions[I].VarName <> '' then
        ItemObj.Add('var', FTransitions[I].VarName);
      ItemObj.Add('op', StateConditionOpToString(FTransitions[I].Op));
      if FTransitions[I].CompareValue <> '' then
        ItemObj.Add('value', FTransitions[I].CompareValue);
      TransArr.Add(ItemObj);
    end;
    RootObj.Add('transitions', TransArr);

    FGraphJson := RootObj.AsJSON;
    FGraphDirty := false;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleStateGraphBehavior.ClearGraph;
begin
  SetLength(FVariables, 0);
  SetLength(FStates, 0);
  SetLength(FTransitions, 0);
  FInitialStateId := '';
  FActiveStateId := '';
  FActiveStateElapsed := 0.0;
  FTotalTransitionCount := 0;
  FRunning := false;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.FindVariableIndex(const AVarName: String): Integer;
var
  I: Integer;
begin
  EnsureParsed;
  for I := 0 to High(FVariables) do
    if SameText(FVariables[I].VarName, AVarName) then
      Exit(I);
  Result := -1;
end;

function TCastleStateGraphBehavior.VariableCount: Integer;
begin
  EnsureParsed;
  Result := Length(FVariables);
end;

function TCastleStateGraphBehavior.GetVariable(const Index: Integer): TStateBlackboardVarData;
begin
  EnsureParsed;
  if (Index >= 0) and (Index < Length(FVariables)) then
    Result := FVariables[Index]
  else
    Result := Default(TStateBlackboardVarData);
end;

procedure TCastleStateGraphBehavior.AddOrUpdateVariable(const AVarName: String;
  const AKind: TStateBlackboardVarKind; const ADefaultValueStr: String);
var
  Idx: Integer;
  NewVar: TStateBlackboardVarData;
begin
  if Trim(AVarName) = '' then
    Exit;
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
  begin
    Idx := Length(FVariables);
    SetLength(FVariables, Idx + 1);
  end;
  NewVar := Default(TStateBlackboardVarData);
  NewVar.VarName := Trim(AVarName);
  NewVar.Kind := AKind;
  NewVar.DefaultStr := ADefaultValueStr;
  ApplyVarFromString(NewVar, ADefaultValueStr);
  FVariables[Idx] := NewVar;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.RemoveVariable(const AVarName: String): Boolean;
var
  Idx, I: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  Result := Idx >= 0;
  if not Result then
    Exit;
  for I := Idx to High(FVariables) - 1 do
    FVariables[I] := FVariables[I + 1];
  SetLength(FVariables, Length(FVariables) - 1);
  RebuildJsonFromMemory;
end;

procedure TCastleStateGraphBehavior.ResetBlackboardToDefaults;
var
  I: Integer;
begin
  EnsureParsed;
  for I := 0 to High(FVariables) do
    ApplyVarFromString(FVariables[I], FVariables[I].DefaultStr);
end;

procedure TCastleStateGraphBehavior.CommitLiveBlackboardToDefaults;
var
  I: Integer;
begin
  EnsureParsed;
  for I := 0 to High(FVariables) do
    FVariables[I].DefaultStr := FormatBlackboardValue(FVariables[I].VarName);
  RebuildJsonFromMemory;
end;

procedure TCastleStateGraphBehavior.SetFloat(const AVarName: String;
  const AValue: Single);
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
  begin
    AddOrUpdateVariable(AVarName, sbkFloat, FloatToStrDot(AValue));
    Exit;
  end;
  FVariables[Idx].FloatVal := AValue;
  FVariables[Idx].IntVal := Round(AValue);
  FVariables[Idx].BoolVal := not IsZero(AValue);
  FVariables[Idx].StrVal := FloatToStrDot(AValue);
end;

function TCastleStateGraphBehavior.GetFloat(const AVarName: String;
  const ADefault: Single): Single;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
    Exit(ADefault);
  case FVariables[Idx].Kind of
    sbkFloat: Result := FVariables[Idx].FloatVal;
    sbkInt:   Result := FVariables[Idx].IntVal;
    sbkBool:  Result := IfThen(FVariables[Idx].BoolVal, 1.0, 0.0);
    sbkString:
      if not TryStrToFloatDot(FVariables[Idx].StrVal, Result) then
        Result := ADefault;
  end;
end;

procedure TCastleStateGraphBehavior.SetInt(const AVarName: String;
  const AValue: Integer);
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
  begin
    AddOrUpdateVariable(AVarName, sbkInt, IntToStr(AValue));
    Exit;
  end;
  FVariables[Idx].IntVal := AValue;
  FVariables[Idx].FloatVal := AValue;
  FVariables[Idx].BoolVal := AValue <> 0;
  FVariables[Idx].StrVal := IntToStr(AValue);
end;

function TCastleStateGraphBehavior.GetInt(const AVarName: String;
  const ADefault: Integer): Integer;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
    Exit(ADefault);
  case FVariables[Idx].Kind of
    sbkInt:   Result := FVariables[Idx].IntVal;
    sbkFloat: Result := Round(FVariables[Idx].FloatVal);
    sbkBool:  Result := IfThen(FVariables[Idx].BoolVal, 1, 0);
    sbkString:
      if not TryStrToInt(FVariables[Idx].StrVal, Result) then
        Result := ADefault;
  end;
end;

procedure TCastleStateGraphBehavior.SetBool(const AVarName: String;
  const AValue: Boolean);
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
  begin
    AddOrUpdateVariable(AVarName, sbkBool, BoolToStr(AValue, 'true', 'false'));
    Exit;
  end;
  FVariables[Idx].BoolVal := AValue;
  FVariables[Idx].IntVal := IfThen(AValue, 1, 0);
  FVariables[Idx].FloatVal := IfThen(AValue, 1.0, 0.0);
  FVariables[Idx].StrVal := BoolToStr(AValue, 'true', 'false');
end;

function TCastleStateGraphBehavior.GetBool(const AVarName: String;
  const ADefault: Boolean): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
    Exit(ADefault);
  case FVariables[Idx].Kind of
    sbkBool:   Result := FVariables[Idx].BoolVal;
    sbkInt:    Result := FVariables[Idx].IntVal <> 0;
    sbkFloat:  Result := not IsZero(FVariables[Idx].FloatVal);
    sbkString: Result := ParseBoolFlexible(FVariables[Idx].StrVal, ADefault);
  end;
end;

procedure TCastleStateGraphBehavior.SetString(const AVarName: String;
  const AValue: String);
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
  begin
    AddOrUpdateVariable(AVarName, sbkString, AValue);
    Exit;
  end;
  ApplyVarFromString(FVariables[Idx], AValue);
  FVariables[Idx].StrVal := AValue;
end;

function TCastleStateGraphBehavior.GetString(const AVarName: String;
  const ADefault: String): String;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
    Exit(ADefault);
  Result := FormatBlackboardValue(AVarName);
end;

function TCastleStateGraphBehavior.SetBlackboardFromString(
  const AVarName, AValueStr: String): Boolean;
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  Result := Idx >= 0;
  if not Result then
    Exit;
  ApplyVarFromString(FVariables[Idx], AValueStr);
end;

function TCastleStateGraphBehavior.FormatBlackboardValue(
  const AVarName: String): String;
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindVariableIndex(AVarName);
  if Idx < 0 then
    Exit('');
  case FVariables[Idx].Kind of
    sbkFloat:  Result := FormatDot('%.2f', [FVariables[Idx].FloatVal]);
    sbkInt:    Result := IntToStr(FVariables[Idx].IntVal);
    sbkBool:   Result := BoolToStr(FVariables[Idx].BoolVal, 'true', 'false');
    sbkString: Result := FVariables[Idx].StrVal;
  end;
end;

function TCastleStateGraphBehavior.FindStateIndex(const AStateId: String): Integer;
var
  I: Integer;
begin
  EnsureParsed;
  for I := 0 to High(FStates) do
    if SameText(FStates[I].StateId, AStateId) then
      Exit(I);
  Result := -1;
end;

function TCastleStateGraphBehavior.StateCount: Integer;
begin
  EnsureParsed;
  Result := Length(FStates);
end;

function TCastleStateGraphBehavior.GetState(const Index: Integer): TStateNodeData;
begin
  EnsureParsed;
  if (Index >= 0) and (Index < Length(FStates)) then
    Result := FStates[Index]
  else
    Result := Default(TStateNodeData);
end;

function TCastleStateGraphBehavior.AddOrUpdateState(
  const AStateId, ADisplayName: String; const AX, AY: Single;
  const AComment: String): Integer;
var
  CleanId: String;
  NewState: TStateNodeData;
begin
  CleanId := Trim(AStateId);
  if CleanId = '' then
    Exit(-1);
  EnsureParsed;
  Result := FindStateIndex(CleanId);
  if Result < 0 then
  begin
    Result := Length(FStates);
    SetLength(FStates, Result + 1);
    NewState := Default(TStateNodeData);
    NewState.StateId := CleanId;
    NewState.DisplayName := IfThen(Trim(ADisplayName) <> '', ADisplayName, CleanId);
    NewState.CanvasX := AX;
    NewState.CanvasY := AY;
    NewState.Comment := AComment;
    FStates[Result] := NewState;
    if FInitialStateId = '' then
      FInitialStateId := CleanId;
  end else
  begin
    if Trim(ADisplayName) <> '' then
      FStates[Result].DisplayName := ADisplayName;
    FStates[Result].CanvasX := AX;
    FStates[Result].CanvasY := AY;
    if AComment <> '' then
      FStates[Result].Comment := AComment;
  end;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.MoveStateCanvas(const AStateId: String;
  const AX, AY: Single): Boolean;
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindStateIndex(AStateId);
  Result := Idx >= 0;
  if not Result then
    Exit;
  FStates[Idx].CanvasX := AX;
  FStates[Idx].CanvasY := AY;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.RemoveState(const AStateId: String): Boolean;
var
  Idx, I, WriteIdx: Integer;
begin
  EnsureParsed;
  Idx := FindStateIndex(AStateId);
  Result := Idx >= 0;
  if not Result then
    Exit;
  for I := Idx to High(FStates) - 1 do
    FStates[I] := FStates[I + 1];
  SetLength(FStates, Length(FStates) - 1);

  { Remove incident transitions referencing the deleted state }
  WriteIdx := 0;
  for I := 0 to High(FTransitions) do
    if (not SameText(FTransitions[I].FromStateId, AStateId)) and
       (not SameText(FTransitions[I].ToStateId, AStateId)) then
    begin
      if WriteIdx <> I then
        FTransitions[WriteIdx] := FTransitions[I];
      Inc(WriteIdx);
    end;
  SetLength(FTransitions, WriteIdx);

  if SameText(FInitialStateId, AStateId) then
  begin
    if Length(FStates) > 0 then
      FInitialStateId := FStates[0].StateId
    else
      FInitialStateId := '';
  end;
  if SameText(FActiveStateId, AStateId) then
    FActiveStateId := '';

  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.AddEntryAction(const AStateId: String;
  const AKind: TStateActionKind; const ATargetName, AKeyOrProp, AValueStr: String;
  const ALoopAnim: Boolean): Boolean;
var
  Idx, N: Integer;
  Act: TStateActionData;
begin
  EnsureParsed;
  Idx := FindStateIndex(AStateId);
  Result := Idx >= 0;
  if not Result then
    Exit;
  Act := Default(TStateActionData);
  Act.Kind := AKind;
  Act.TargetName := Trim(ATargetName);
  Act.KeyOrProp := Trim(AKeyOrProp);
  Act.ValueStr := AValueStr;
  Act.LoopAnim := ALoopAnim;
  N := Length(FStates[Idx].EntryActions);
  SetLength(FStates[Idx].EntryActions, N + 1);
  FStates[Idx].EntryActions[N] := Act;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.AddExitAction(const AStateId: String;
  const AKind: TStateActionKind; const ATargetName, AKeyOrProp, AValueStr: String;
  const ALoopAnim: Boolean): Boolean;
var
  Idx, N: Integer;
  Act: TStateActionData;
begin
  EnsureParsed;
  Idx := FindStateIndex(AStateId);
  Result := Idx >= 0;
  if not Result then
    Exit;
  Act := Default(TStateActionData);
  Act.Kind := AKind;
  Act.TargetName := Trim(ATargetName);
  Act.KeyOrProp := Trim(AKeyOrProp);
  Act.ValueStr := AValueStr;
  Act.LoopAnim := ALoopAnim;
  N := Length(FStates[Idx].ExitActions);
  SetLength(FStates[Idx].ExitActions, N + 1);
  FStates[Idx].ExitActions[N] := Act;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.ClearStateActions(const AStateId: String): Boolean;
var
  Idx: Integer;
begin
  EnsureParsed;
  Idx := FindStateIndex(AStateId);
  Result := Idx >= 0;
  if not Result then
    Exit;
  SetLength(FStates[Idx].EntryActions, 0);
  SetLength(FStates[Idx].ExitActions, 0);
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.TransitionCount: Integer;
begin
  EnsureParsed;
  Result := Length(FTransitions);
end;

function TCastleStateGraphBehavior.GetTransition(const Index: Integer): TStateTransitionData;
begin
  EnsureParsed;
  if (Index >= 0) and (Index < Length(FTransitions)) then
    Result := FTransitions[Index]
  else
    Result := Default(TStateTransitionData);
end;

function TCastleStateGraphBehavior.AddTransition(
  const AFromStateId, AToStateId: String;
  const AOp: TStateConditionOp; const AVarName, ACompareValue: String;
  const AMinElapsedSec: Single; const APriority: Integer): Integer;
var
  NewTrans: TStateTransitionData;
begin
  if (Trim(AFromStateId) = '') or (Trim(AToStateId) = '') then
    Exit(-1);
  EnsureParsed;
  NewTrans := Default(TStateTransitionData);
  NewTrans.FromStateId := Trim(AFromStateId);
  NewTrans.ToStateId := Trim(AToStateId);
  NewTrans.Priority := APriority;
  NewTrans.MinStateElapsedSec := Max(0.0, AMinElapsedSec);
  NewTrans.VarName := Trim(AVarName);
  NewTrans.Op := AOp;
  NewTrans.CompareValue := ACompareValue;

  Result := Length(FTransitions);
  SetLength(FTransitions, Result + 1);
  FTransitions[Result] := NewTrans;
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.RemoveTransition(const Index: Integer): Boolean;
var
  I: Integer;
begin
  EnsureParsed;
  Result := (Index >= 0) and (Index < Length(FTransitions));
  if not Result then
    Exit;
  for I := Index to High(FTransitions) - 1 do
    FTransitions[I] := FTransitions[I + 1];
  SetLength(FTransitions, Length(FTransitions) - 1);
  RebuildJsonFromMemory;
end;

function TCastleStateGraphBehavior.EvaluateTransitionCondition(
  const Trans: TStateTransitionData): Boolean;
const
  Eps = 1e-4;
var
  VarIdx: Integer;
  V: TStateBlackboardVarData;
  RhsFloat, LhsFloat: Single;
  RhsInt: Integer;
  RhsBool: Boolean;
begin
  EnsureParsed;
  if FActiveStateElapsed + 1e-5 < Trans.MinStateElapsedSec then
    Exit(false);

  if Trans.Op = scoAlways then
    Exit(true);

  VarIdx := FindVariableIndex(Trans.VarName);
  if VarIdx < 0 then
    Exit(false);

  V := FVariables[VarIdx];
  case V.Kind of
    sbkFloat:
      begin
        if not TryStrToFloatDot(Trim(Trans.CompareValue), RhsFloat) then
          Exit(false);
        LhsFloat := V.FloatVal;
        case Trans.Op of
          scoEqual:          Result := SameValue(LhsFloat, RhsFloat, Eps);
          scoNotEqual:       Result := not SameValue(LhsFloat, RhsFloat, Eps);
          scoLess:           Result := LhsFloat < RhsFloat;
          scoLessOrEqual:    Result := LhsFloat <= RhsFloat + Eps;
          scoGreater:        Result := LhsFloat > RhsFloat;
          scoGreaterOrEqual: Result := LhsFloat >= RhsFloat - Eps;
          else               Result := true;
        end;
      end;
    sbkInt:
      begin
        if not TryStrToInt(Trim(Trans.CompareValue), RhsInt) then
          Exit(false);
        case Trans.Op of
          scoEqual:          Result := V.IntVal = RhsInt;
          scoNotEqual:       Result := V.IntVal <> RhsInt;
          scoLess:           Result := V.IntVal < RhsInt;
          scoLessOrEqual:    Result := V.IntVal <= RhsInt;
          scoGreater:        Result := V.IntVal > RhsInt;
          scoGreaterOrEqual: Result := V.IntVal >= RhsInt;
          else               Result := true;
        end;
      end;
    sbkBool:
      begin
        RhsBool := ParseBoolFlexible(Trans.CompareValue, true);
        case Trans.Op of
          scoEqual:          Result := V.BoolVal = RhsBool;
          scoNotEqual:       Result := V.BoolVal <> RhsBool;
          else               Result := V.BoolVal = RhsBool;
        end;
      end;
    sbkString:
      begin
        case Trans.Op of
          scoEqual:          Result := SameText(V.StrVal, Trans.CompareValue);
          scoNotEqual:       Result := not SameText(V.StrVal, Trans.CompareValue);
          scoLess:           Result := CompareText(V.StrVal, Trans.CompareValue) < 0;
          scoLessOrEqual:    Result := CompareText(V.StrVal, Trans.CompareValue) <= 0;
          scoGreater:        Result := CompareText(V.StrVal, Trans.CompareValue) > 0;
          scoGreaterOrEqual: Result := CompareText(V.StrVal, Trans.CompareValue) >= 0;
          else               Result := true;
        end;
      end;
  end;
end;

function TCastleStateGraphBehavior.ResolveActionRoot: TComponent;
begin
  if FTargetRoot <> nil then
    Result := FTargetRoot
  else if Owner <> nil then
    Result := Owner
  else
    Result := Parent;
end;

function FindComponentRecursiveByName(const Root: TComponent;
  const TargetName: String): TComponent;
var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if (Root = nil) or (TargetName = '') then
    Exit;
  if SameText(Root.Name, TargetName) then
    Exit(Root);

  Result := Root.FindComponent(TargetName);
  if Result <> nil then
    Exit;

  for I := 0 to Root.ComponentCount - 1 do
    if SameText(Root.Components[I].Name, TargetName) then
      Exit(Root.Components[I]);

  if Root is TCastleTransform then
  begin
    T := TCastleTransform(Root);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindComponentRecursiveByName(T[I], TargetName);
      if Result <> nil then
        Exit;
    end;
    for I := 0 to T.BehaviorsCount - 1 do
      if SameText(T.Behaviors[I].Name, TargetName) then
        Exit(T.Behaviors[I]);
  end else
  if Root is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(Root);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindComponentRecursiveByName(UI.Controls[I], TargetName);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function TCastleStateGraphBehavior.FindTargetComponent(
  const ATargetName: String): TComponent;
var
  Clean: String;
begin
  Clean := Trim(ATargetName);
  if (Clean = '') or SameText(Clean, '$Parent') or SameText(Clean, 'Parent') then
    Exit(Parent);
  if SameText(Clean, '$Self') then
    Exit(Self);
  Result := FindComponentRecursiveByName(ResolveActionRoot, Clean);
  if (Result = nil) and (Parent <> nil) then
    Result := FindComponentRecursiveByName(Parent, Clean);
end;

procedure ApplyComponentPropertyString(const Target: TComponent;
  const PropPath, ValStr: String);
var
  T: TCastleTransform;
  V3: TVector3;
  F: Single;
  N: Int64;
  DotPos: Integer;
  Head, Tail: String;
  SubObj: TObject;
  PropInfo: PPropInfo;
begin
  if (Target = nil) or (PropPath = '') then
    Exit;

  if Target is TCastleTransform then
  begin
    T := TCastleTransform(Target);
    if SameText(PropPath, 'Translation') and ParseVec3Flexible(ValStr, V3) then
    begin
      T.Translation := V3;
      Exit;
    end;
    if SameText(PropPath, 'Scale') and ParseVec3Flexible(ValStr, V3) then
    begin
      T.Scale := V3;
      Exit;
    end;
  end;

  DotPos := Pos('.', PropPath);
  if DotPos > 0 then
  begin
    Head := Copy(PropPath, 1, DotPos - 1);
    Tail := Copy(PropPath, DotPos + 1, MaxInt);
    PropInfo := GetPropInfo(Target.ClassInfo, Head);
    if (PropInfo <> nil) and (PropInfo^.PropType^.Kind = tkClass) then
    begin
      SubObj := GetObjectProp(Target, PropInfo);
      if SubObj <> nil then
      begin
        PropInfo := GetPropInfo(SubObj.ClassInfo, Tail);
        if (PropInfo <> nil) and (PropInfo^.PropType^.Kind = tkFloat) and
           TryStrToFloatDot(Trim(ValStr), F) then
          SetFloatProp(SubObj, PropInfo, F);
      end;
    end;
    Exit;
  end;

  PropInfo := GetPropInfo(Target.ClassInfo, PropPath);
  if PropInfo = nil then
    Exit;

  case PropInfo^.PropType^.Kind of
    tkFloat:
      if TryStrToFloatDot(Trim(ValStr), F) then
        SetFloatProp(Target, PropInfo, F);
    tkInteger, tkInt64:
      if TryStrToInt64(Trim(ValStr), N) then
        SetOrdProp(Target, PropInfo, N);
    tkBool:
      SetOrdProp(Target, PropInfo, Ord(ParseBoolFlexible(ValStr, false)));
    tkEnumeration:
      begin
        if PropInfo^.PropType = TypeInfo(Boolean) then
          SetOrdProp(Target, PropInfo, Ord(ParseBoolFlexible(ValStr, false)))
        else
        begin
          N := GetEnumValue(PropInfo^.PropType, Trim(ValStr));
          if N >= 0 then
            SetOrdProp(Target, PropInfo, N);
        end;
      end;
    tkSString, tkLString, tkAString:
      SetStrProp(Target, PropInfo, ValStr);
  end;
end;

procedure TCastleStateGraphBehavior.ExecuteSingleAction(const Act: TStateActionData);
var
  TargetComp: TComponent;
begin
  case Act.Kind of
    sakSetProperty:
      begin
        TargetComp := FindTargetComponent(Act.TargetName);
        ApplyComponentPropertyString(TargetComp, Act.KeyOrProp, Act.ValueStr);
      end;
    sakSetBlackboardVar:
      SetBlackboardFromString(Act.KeyOrProp, Act.ValueStr);
    sakPlayAnimation:
      begin
        TargetComp := FindTargetComponent(Act.TargetName);
        FLastPlayedAnimation := Act.KeyOrProp;
        if TargetComp <> nil then
          FLastPlayedAnimationTarget := TargetComp.Name
        else
          FLastPlayedAnimationTarget := Act.TargetName;
        if (TargetComp is TCastleSceneCore) and (Act.KeyOrProp <> '') and
           TCastleSceneCore(TargetComp).HasAnimation(Act.KeyOrProp) then
          TCastleSceneCore(TargetComp).PlayAnimation(Act.KeyOrProp, Act.LoopAnim);
      end;
    sakFireCue:
      if Assigned(FOnStateCue) then
        FOnStateCue(Self, Act.KeyOrProp, Act.ValueStr);
  end;
end;

procedure TCastleStateGraphBehavior.ExecuteActionList(
  const Actions: TStateActionDataArray);
var
  I: Integer;
begin
  for I := 0 to High(Actions) do
    ExecuteSingleAction(Actions[I]);
end;

procedure TCastleStateGraphBehavior.PerformTransitionTo(
  const NextStateId: String; const FireEvents: Boolean);
var
  PrevStateId: String;
  OldIdx, NewIdx: Integer;
begin
  EnsureParsed;
  NewIdx := FindStateIndex(NextStateId);
  if NewIdx < 0 then
    Exit;

  PrevStateId := FActiveStateId;
  if PrevStateId <> '' then
  begin
    OldIdx := FindStateIndex(PrevStateId);
    if OldIdx >= 0 then
      ExecuteActionList(FStates[OldIdx].ExitActions);
  end;

  FActiveStateId := FStates[NewIdx].StateId;
  FActiveStateElapsed := 0.0;
  if PrevStateId <> '' then
    Inc(FTotalTransitionCount);

  ExecuteActionList(FStates[NewIdx].EntryActions);

  if FireEvents and Assigned(FOnStateTransition) then
    FOnStateTransition(Self, PrevStateId, FActiveStateId);
end;

procedure TCastleStateGraphBehavior.StartGraph;
var
  EntryId: String;
begin
  EnsureParsed;
  FRunning := true;
  if FActiveStateId <> '' then
    Exit;
  EntryId := FInitialStateId;
  if (EntryId = '') and (Length(FStates) > 0) then
    EntryId := FStates[0].StateId;
  if (EntryId <> '') and (FindStateIndex(EntryId) >= 0) then
    PerformTransitionTo(EntryId, true);
end;

procedure TCastleStateGraphBehavior.StopGraph;
begin
  FRunning := false;
end;

procedure TCastleStateGraphBehavior.ResetGraph;
begin
  EnsureParsed;
  FRunning := false;
  FActiveStateId := '';
  FActiveStateElapsed := 0.0;
  FTotalTransitionCount := 0;
  FLastPlayedAnimation := '';
  FLastPlayedAnimationTarget := '';
  ResetBlackboardToDefaults;
end;

function TCastleStateGraphBehavior.ForceEnterState(const AStateId: String): Boolean;
begin
  EnsureParsed;
  Result := FindStateIndex(AStateId) >= 0;
  if not Result then
    Exit;
  PerformTransitionTo(AStateId, true);
end;

procedure TCastleStateGraphBehavior.StepGraph(const DeltaSec: Single);
var
  Hops, I, BestIdx, BestPriority: Integer;
  T: TStateTransitionData;
  IsFromMatch: Boolean;
begin
  EnsureParsed;
  if Length(FStates) = 0 then
    Exit;

  if FActiveStateId = '' then
    StartGraph;
  if FActiveStateId = '' then
    Exit;

  FActiveStateElapsed := FActiveStateElapsed + Max(0.0, DeltaSec);

  for Hops := 1 to FMaxTransitionsPerStep do
  begin
    BestIdx := -1;
    BestPriority := Low(Integer);

    for I := 0 to High(FTransitions) do
    begin
      T := FTransitions[I];
      IsFromMatch := SameText(T.FromStateId, FActiveStateId) or
        ((T.FromStateId = '*') and (not SameText(T.ToStateId, FActiveStateId)));
      if not IsFromMatch then
        Continue;
      if FindStateIndex(T.ToStateId) < 0 then
        Continue;
      if not EvaluateTransitionCondition(T) then
        Continue;

      if (BestIdx < 0) or (T.Priority > BestPriority) then
      begin
        BestIdx := I;
        BestPriority := T.Priority;
      end;
    end;

    if BestIdx < 0 then
      Break;

    PerformTransitionTo(FTransitions[BestIdx].ToStateId, true);
  end;
end;

function TCastleStateGraphBehavior.GraphSummaryBadge: String;
var
  ActivePart: String;
begin
  EnsureParsed;
  if FActiveStateId <> '' then
    ActivePart := ' Active:' + FActiveStateId
  else if FInitialStateId <> '' then
    ActivePart := ' Init:' + FInitialStateId
  else
    ActivePart := '';
  Result := Format('[FSM:%dst/%dtr%s]',
    [Length(FStates), Length(FTransitions), ActivePart]);
end;

initialization
  RegisterSerializableComponent(TCastleStateGraphBehavior,
    ['Behaviors', 'State Graph (StateTree / FSM)']);
end.
