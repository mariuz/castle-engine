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

{ Unreal Engine 5.5-style Behavior Tree & Blackboard component
  (@link(TCastleBehaviorTree)) featuring Selector, Sequence, and SimpleParallel
  composites, MoveTo/Wait/Blackboard tasks, Blackboard Decorators with Observer
  Aborts (None / Self / LowerPriority / Both), periodic branch Services, and
  deterministic pre-order ExecutionIndex numbering
  (Phase 384 — UE 5.5 UBehaviorTree & UBlackboardData Parity). }
unit CastleBehaviorTree;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Typed Blackboard entry kinds (UE5 UBlackboardData parity). }
  TBlackboardKeyType = (
    bktBool,
    bktInt,
    bktFloat,
    bktString,
    bktVector3
  );

  { Node execution result per Behavior Tree tick. }
  TBehaviorNodeStatus = (
    btsIdle,
    btsRunning,
    btsSucceeded,
    btsFailed
  );

  { UE5 Behavior Tree node types. }
  TBehaviorTreeNodeKind = (
    btnRoot,
    btnSelector,
    btnSequence,
    btnSimpleParallel,
    btnTaskMoveTo,
    btnTaskWait,
    btnTaskSetBlackboardBool,
    btnTaskAddBlackboardInt
  );

  { UE5 Decorator condition operators against a Blackboard key. }
  TBlackboardDecoratorOp = (
    bdopNone,
    bdopBoolIsSet,
    bdopBoolIsNotSet,
    bdopIntGreaterThan,
    bdopFloatGreaterOrEqual
  );

  { UE5 Decorator Observer Aborts mode controlling dynamic reactive preemption. }
  TFlowAbortMode = (
    famNone,
    famSelf,
    famLowerPriority,
    famBoth
  );

  { Built-in UE 5.5 Behavior Tree starter presets. }
  TBehaviorTreePreset = (
    btpCustom,
    btpTacticalGuardObserverAborts,
    btpSimpleParallelSuppressAndMove,
    btpAmmoReloadFallbackSequence
  );

  { Single key-value entry in the Behavior Tree's Blackboard. }
  TBlackboardEntry = record
    KeyName: String;
    KeyType: TBlackboardKeyType;
    BoolVal: Boolean;
    IntVal: Integer;
    FloatVal: Single;
    StrVal: String;
    VecVal: TVector3;
    function ValueAsText: String;
  end;
  TBlackboardEntryArray = array of TBlackboardEntry;

  { Single node inside a @link(TCastleBehaviorTree) with optional Decorator & Service. }
  TBehaviorTreeNode = record
    NodeId: String;
    Title: String;
    Kind: TBehaviorTreeNodeKind;
    ParentNodeId: String;
    PosX: Single;
    PosY: Single;

    { Task parameters }
    TargetBlackboardKey: String;
    TaskDurationSec: Single;
    MoveSpeedMps: Single;
    AcceptableRadius: Single;
    TaskBoolValue: Boolean;
    TaskIntDelta: Integer;

    { Optional Blackboard Decorator }
    DecoratorOp: TBlackboardDecoratorOp;
    DecoratorKey: String;
    DecoratorThreshold: Single;
    ObserverAborts: TFlowAbortMode;

    { Optional Periodic Service (ticks every ServiceIntervalSec while branch active) }
    ServiceName: String;
    ServiceTargetKey: String;
    ServiceIntervalSec: Single;

    { Transient runtime & compiler fields }
    ExecutionIndex: Integer;
    SubtreeMaxExecIndex: Integer;
    LastStatus: TBehaviorNodeStatus;
    RuntimeElapsedSec: Single;
    RuntimeChildCursor: Integer;
    RuntimeServiceAccumSec: Single;
  end;
  TBehaviorTreeNodeArray = array of TBehaviorTreeNode;

  { Unreal Engine 5.5-style Behavior Tree & Blackboard Actor/Transform component. }
  TCastleBehaviorTree = class(TCastleTransform)
  private
    FPreset: TBehaviorTreePreset;
    FShowAgentGizmo: Boolean;
    FBlackboard: TBlackboardEntryArray;
    FNodes: TBehaviorTreeNodeArray;

    { Transient execution & diagnostic state }
    FRunningLeafNodeId: String;
    FRunningLeafExecIndex: Integer;
    FTotalTickCount: Integer;
    FAbortCount: Integer;
    FServiceTickCount: Integer;
    FLastTreeValid: Boolean;
    FValidationErrors: TStringList;
    FExecutionLog: TStringList;
    FAgentGizmo: TCastleTransform;

    procedure SetPreset(const AValue: TBehaviorTreePreset);
    procedure SetShowAgentGizmo(const AValue: Boolean);
    function GetTreeJson: String;
    procedure SetTreeJson(const AValue: String);

    procedure ClearAgentGizmo;
    procedure SyncAgentGizmo;
    procedure CollectSortedChildren(const AParentId: String; out OutChildIndices: array of Integer;
      out OutCount: Integer);
    procedure RebuildExecutionIndices;
    function EvaluateDecoratorCondition(const ANode: TBehaviorTreeNode): Boolean;
    procedure ResetSubtreeRuntime(const ANodeIdx: Integer);
    procedure CheckObserverAbortsBeforeTick;
    procedure TickNodeService(const ANodeIdx: Integer; const ADeltaSec: Single);
    function TickNodeRecursive(const ANodeIdx: Integer; const ADeltaSec: Single): TBehaviorNodeStatus;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function NodeKindTitle(const AKind: TBehaviorTreeNodeKind): String; static;
    class function AbortModeName(const AMode: TFlowAbortMode): String; static;
    class function MakeDefaultNode(const ANodeId, ATitle: String;
      const AKind: TBehaviorTreeNodeKind; const AParentId: String;
      const AX, AY: Single): TBehaviorTreeNode; static;

    { Blackboard API }
    procedure ClearTree;
    procedure ApplyPreset(const APreset: TBehaviorTreePreset);
    function FindBlackboardIndex(const AKey: String): Integer;
    procedure SetBlackboardBool(const AKey: String; const AVal: Boolean);
    procedure SetBlackboardInt(const AKey: String; const AVal: Integer);
    procedure SetBlackboardFloat(const AKey: String; const AVal: Single);
    procedure SetBlackboardString(const AKey: String; const AVal: String);
    procedure SetBlackboardVec3(const AKey: String; const AVal: TVector3);
    function GetBlackboardBool(const AKey: String; const ADefault: Boolean = False): Boolean;
    function GetBlackboardInt(const AKey: String; const ADefault: Integer = 0): Integer;
    function GetBlackboardFloat(const AKey: String; const ADefault: Single = 0.0): Single;
    function GetBlackboardVec3(const AKey: String): TVector3;

    { Node Authoring API }
    function FindNodeIndex(const ANodeId: String): Integer;
    function FindRootNodeIndex: Integer;
    function AddOrUpdateNode(const ANode: TBehaviorTreeNode): Integer;
    function SetNodePosition(const ANodeId: String; const AX, AY: Single): Boolean;

    { Validation & Simulation }
    function ValidateBehaviorTree: Boolean;
    procedure ResetBehaviorTree;
    function TickBehaviorTree(const ADeltaSeconds: Single): TBehaviorNodeStatus;

    function BehaviorTreeSummaryBadge: String;

    property Blackboard: TBlackboardEntryArray read FBlackboard;
    property Nodes: TBehaviorTreeNodeArray read FNodes;
    property RunningLeafNodeId: String read FRunningLeafNodeId;
    property TotalTickCount: Integer read FTotalTickCount;
    property AbortCount: Integer read FAbortCount;
    property ServiceTickCount: Integer read FServiceTickCount;
    property LastTreeValid: Boolean read FLastTreeValid;
    property ValidationErrors: TStringList read FValidationErrors;
    property ExecutionLog: TStringList read FExecutionLog;
  published
    property ShowAgentGizmo: Boolean read FShowAgentGizmo write SetShowAgentGizmo default True;
    property TreeJson: String read GetTreeJson write SetTreeJson;
    property Preset: TBehaviorTreePreset read FPreset write SetPreset default btpTacticalGuardObserverAborts;
  end;

implementation

uses
  fpjson, jsonparser;

{ TBlackboardEntry ----------------------------------------------------------- }

function TBlackboardEntry.ValueAsText: String;
begin
  case KeyType of
    bktBool:    Result := BoolToStr(BoolVal, 'True', 'False');
    bktInt:     Result := IntToStr(IntVal);
    bktFloat:   Result := FormatFloat('0.##', FloatVal);
    bktString:  Result := '"' + StrVal + '"';
    bktVector3: Result := Format('(%.1f, %.1f, %.1f)', [VecVal.X, VecVal.Y, VecVal.Z]);
  end;
end;

{ TCastleBehaviorTree -------------------------------------------------------- }

constructor TCastleBehaviorTree.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowAgentGizmo := True;
  FRunningLeafExecIndex := -1;
  FValidationErrors := TStringList.Create;
  FExecutionLog := TStringList.Create;
  ApplyPreset(btpTacticalGuardObserverAborts);
end;

destructor TCastleBehaviorTree.Destroy;
begin
  ClearAgentGizmo;
  FreeAndNil(FExecutionLog);
  FreeAndNil(FValidationErrors);
  inherited;
end;

procedure TCastleBehaviorTree.Loaded;
begin
  inherited;
  ValidateBehaviorTree;
  SyncAgentGizmo;
end;

function TCastleBehaviorTree.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or (PropertyName = 'ShowAgentGizmo') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleBehaviorTree.SetPreset(const AValue: TBehaviorTreePreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleBehaviorTree.SetShowAgentGizmo(const AValue: Boolean);
begin
  if FShowAgentGizmo <> AValue then
  begin
    FShowAgentGizmo := AValue;
    if not FShowAgentGizmo then
      ClearAgentGizmo
    else
      SyncAgentGizmo;
  end;
end;

class function TCastleBehaviorTree.NodeKindTitle(
  const AKind: TBehaviorTreeNodeKind): String;
begin
  case AKind of
    btnRoot:                  Result := 'Root';
    btnSelector:              Result := 'Selector (?)';
    btnSequence:              Result := 'Sequence (->)';
    btnSimpleParallel:        Result := 'Simple Parallel';
    btnTaskMoveTo:            Result := 'Task: Move To';
    btnTaskWait:              Result := 'Task: Wait';
    btnTaskSetBlackboardBool: Result := 'Task: Set BB Bool';
    btnTaskAddBlackboardInt:  Result := 'Task: Add BB Int';
  end;
end;

class function TCastleBehaviorTree.AbortModeName(const AMode: TFlowAbortMode): String;
begin
  case AMode of
    famNone:          Result := 'None';
    famSelf:          Result := 'Self';
    famLowerPriority: Result := 'LowerPriority';
    famBoth:          Result := 'Both';
  end;
end;

class function TCastleBehaviorTree.MakeDefaultNode(const ANodeId, ATitle: String;
  const AKind: TBehaviorTreeNodeKind; const AParentId: String;
  const AX, AY: Single): TBehaviorTreeNode;
begin
  Result := Default(TBehaviorTreeNode);
  Result.NodeId := ANodeId;
  Result.Title := ATitle;
  Result.Kind := AKind;
  Result.ParentNodeId := AParentId;
  Result.PosX := AX;
  Result.PosY := AY;
  Result.TaskDurationSec := 1.0;
  Result.MoveSpeedMps := 6.0;
  Result.AcceptableRadius := 0.35;
  Result.DecoratorOp := bdopNone;
  Result.ObserverAborts := famNone;
  Result.ServiceIntervalSec := 0.5;
  Result.ExecutionIndex := -1;
  Result.SubtreeMaxExecIndex := -1;
end;

procedure TCastleBehaviorTree.ClearAgentGizmo;
begin
  if FAgentGizmo <> nil then
    FreeAndNil(FAgentGizmo);
end;

procedure TCastleBehaviorTree.SyncAgentGizmo;
var
  BodyCyl: TCastleCylinder;
begin
  if not FShowAgentGizmo then Exit;
  if FAgentGizmo = nil then
  begin
    FAgentGizmo := TCastleTransform.Create(nil);
    FAgentGizmo.SetTransient;
    FAgentGizmo.Pickable := False;
    FAgentGizmo.Collides := False;
    FAgentGizmo.Name := 'BT_AgentPreview';
    Add(FAgentGizmo);

    BodyCyl := TCastleCylinder.Create(FAgentGizmo);
    BodyCyl.SetTransient;
    BodyCyl.Pickable := False;
    BodyCyl.Collides := False;
    BodyCyl.Radius := 0.42;
    BodyCyl.Height := 1.75;
    BodyCyl.Translation := Vector3(0, 0.875, 0);
    BodyCyl.Color := Vector4(0.88, 0.58, 0.22, 1.0);
    FAgentGizmo.Add(BodyCyl);
  end;
end;

procedure TCastleBehaviorTree.ClearTree;
begin
  FBlackboard := nil;
  FNodes := nil;
  FRunningLeafNodeId := '';
  FRunningLeafExecIndex := -1;
  FTotalTickCount := 0;
  FAbortCount := 0;
  FServiceTickCount := 0;
  FLastTreeValid := False;
  FValidationErrors.Clear;
  FExecutionLog.Clear;
end;

{ Blackboard Operations ------------------------------------------------------ }

function TCastleBehaviorTree.FindBlackboardIndex(const AKey: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FBlackboard) do
    if SameText(FBlackboard[I].KeyName, AKey) then
      Exit(I);
  Result := -1;
end;

procedure TCastleBehaviorTree.SetBlackboardBool(const AKey: String; const AVal: Boolean);
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx < 0 then
  begin
    Idx := Length(FBlackboard);
    SetLength(FBlackboard, Idx + 1);
    FBlackboard[Idx] := Default(TBlackboardEntry);
    FBlackboard[Idx].KeyName := AKey;
  end;
  FBlackboard[Idx].KeyType := bktBool;
  FBlackboard[Idx].BoolVal := AVal;
end;

procedure TCastleBehaviorTree.SetBlackboardInt(const AKey: String; const AVal: Integer);
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx < 0 then
  begin
    Idx := Length(FBlackboard);
    SetLength(FBlackboard, Idx + 1);
    FBlackboard[Idx] := Default(TBlackboardEntry);
    FBlackboard[Idx].KeyName := AKey;
  end;
  FBlackboard[Idx].KeyType := bktInt;
  FBlackboard[Idx].IntVal := AVal;
end;

procedure TCastleBehaviorTree.SetBlackboardFloat(const AKey: String; const AVal: Single);
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx < 0 then
  begin
    Idx := Length(FBlackboard);
    SetLength(FBlackboard, Idx + 1);
    FBlackboard[Idx] := Default(TBlackboardEntry);
    FBlackboard[Idx].KeyName := AKey;
  end;
  FBlackboard[Idx].KeyType := bktFloat;
  FBlackboard[Idx].FloatVal := AVal;
end;

procedure TCastleBehaviorTree.SetBlackboardString(const AKey: String; const AVal: String);
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx < 0 then
  begin
    Idx := Length(FBlackboard);
    SetLength(FBlackboard, Idx + 1);
    FBlackboard[Idx] := Default(TBlackboardEntry);
    FBlackboard[Idx].KeyName := AKey;
  end;
  FBlackboard[Idx].KeyType := bktString;
  FBlackboard[Idx].StrVal := AVal;
end;

procedure TCastleBehaviorTree.SetBlackboardVec3(const AKey: String; const AVal: TVector3);
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx < 0 then
  begin
    Idx := Length(FBlackboard);
    SetLength(FBlackboard, Idx + 1);
    FBlackboard[Idx] := Default(TBlackboardEntry);
    FBlackboard[Idx].KeyName := AKey;
  end;
  FBlackboard[Idx].KeyType := bktVector3;
  FBlackboard[Idx].VecVal := AVal;
end;

function TCastleBehaviorTree.GetBlackboardBool(const AKey: String;
  const ADefault: Boolean): Boolean;
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx >= 0 then Result := FBlackboard[Idx].BoolVal else Result := ADefault;
end;

function TCastleBehaviorTree.GetBlackboardInt(const AKey: String;
  const ADefault: Integer): Integer;
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx >= 0 then Result := FBlackboard[Idx].IntVal else Result := ADefault;
end;

function TCastleBehaviorTree.GetBlackboardFloat(const AKey: String;
  const ADefault: Single): Single;
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx >= 0 then Result := FBlackboard[Idx].FloatVal else Result := ADefault;
end;

function TCastleBehaviorTree.GetBlackboardVec3(const AKey: String): TVector3;
var
  Idx: Integer;
begin
  Idx := FindBlackboardIndex(AKey);
  if Idx >= 0 then Result := FBlackboard[Idx].VecVal else Result := TVector3.Zero;
end;

{ Node Graph & ExecutionIndex Ordering --------------------------------------- }

function TCastleBehaviorTree.FindNodeIndex(const ANodeId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].NodeId, ANodeId) then
      Exit(I);
  Result := -1;
end;

function TCastleBehaviorTree.FindRootNodeIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if FNodes[I].Kind = btnRoot then
      Exit(I);
  Result := -1;
end;

function TCastleBehaviorTree.AddOrUpdateNode(const ANode: TBehaviorTreeNode): Integer;
begin
  Result := FindNodeIndex(ANode.NodeId);
  if Result < 0 then
  begin
    Result := Length(FNodes);
    SetLength(FNodes, Result + 1);
  end;
  FNodes[Result] := ANode;
  RebuildExecutionIndices;
end;

function TCastleBehaviorTree.SetNodePosition(const ANodeId: String;
  const AX, AY: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  FNodes[Idx].PosX := AX;
  FNodes[Idx].PosY := AY;
  RebuildExecutionIndices;
  Result := True;
end;

procedure TCastleBehaviorTree.CollectSortedChildren(const AParentId: String;
  out OutChildIndices: array of Integer; out OutCount: Integer);
var
  I, J, Temp: Integer;
begin
  OutCount := 0;
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].ParentNodeId, AParentId) and (OutCount <= High(OutChildIndices)) then
    begin
      OutChildIndices[OutCount] := I;
      Inc(OutCount);
    end;

  { Sort siblings left-to-right by PosX (exact UE5 Behavior Tree child priority order!) }
  for I := 0 to OutCount - 2 do
    for J := I + 1 to OutCount - 1 do
      if FNodes[OutChildIndices[J]].PosX < FNodes[OutChildIndices[I]].PosX then
      begin
        Temp := OutChildIndices[I];
        OutChildIndices[I] := OutChildIndices[J];
        OutChildIndices[J] := Temp;
      end;
end;

procedure TCastleBehaviorTree.RebuildExecutionIndices;
var
  Counter: Integer;

  procedure AssignDfs(const NodeIdx: Integer; const Depth: Integer);
  var
    Kids: array[0..31] of Integer;
    KidCnt, K: Integer;
  begin
    if (NodeIdx < 0) or (Depth > 32) then Exit;
    FNodes[NodeIdx].ExecutionIndex := Counter;
    Inc(Counter);
    CollectSortedChildren(FNodes[NodeIdx].NodeId, Kids, KidCnt);
    for K := 0 to KidCnt - 1 do
      AssignDfs(Kids[K], Depth + 1);
    FNodes[NodeIdx].SubtreeMaxExecIndex := Counter - 1;
  end;

var
  RootIdx, I: Integer;
begin
  for I := 0 to High(FNodes) do
  begin
    FNodes[I].ExecutionIndex := -1;
    FNodes[I].SubtreeMaxExecIndex := -1;
  end;
  RootIdx := FindRootNodeIndex;
  Counter := 0;
  if RootIdx >= 0 then
    AssignDfs(RootIdx, 0);
end;

function TCastleBehaviorTree.ValidateBehaviorTree: Boolean;
var
  I, J, RootCnt: Integer;
begin
  FValidationErrors.Clear;
  RootCnt := 0;
  for I := 0 to High(FNodes) do
  begin
    if FNodes[I].Kind = btnRoot then
      Inc(RootCnt)
    else if (FNodes[I].ParentNodeId <> '') and (FindNodeIndex(FNodes[I].ParentNodeId) < 0) then
      FValidationErrors.Add(Format('Node "%s" references missing parent "%s".',
        [FNodes[I].NodeId, FNodes[I].ParentNodeId]));

    for J := I + 1 to High(FNodes) do
      if SameText(FNodes[I].NodeId, FNodes[J].NodeId) then
        FValidationErrors.Add(Format('Duplicate NodeId "%s".', [FNodes[I].NodeId]));
  end;

  if RootCnt <> 1 then
    FValidationErrors.Add(Format('Behavior Tree must have exactly 1 Root node (found %d).', [RootCnt]));

  RebuildExecutionIndices;
  FLastTreeValid := FValidationErrors.Count = 0;
  Result := FLastTreeValid;
end;

procedure TCastleBehaviorTree.ResetSubtreeRuntime(const ANodeIdx: Integer);
var
  Kids: array[0..31] of Integer;
  KidCnt, K: Integer;
begin
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then Exit;
  FNodes[ANodeIdx].LastStatus := btsIdle;
  FNodes[ANodeIdx].RuntimeElapsedSec := 0.0;
  FNodes[ANodeIdx].RuntimeChildCursor := 0;
  FNodes[ANodeIdx].RuntimeServiceAccumSec := 0.0;
  CollectSortedChildren(FNodes[ANodeIdx].NodeId, Kids, KidCnt);
  for K := 0 to KidCnt - 1 do
    ResetSubtreeRuntime(Kids[K]);
end;

procedure TCastleBehaviorTree.ResetBehaviorTree;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
  begin
    FNodes[I].LastStatus := btsIdle;
    FNodes[I].RuntimeElapsedSec := 0.0;
    FNodes[I].RuntimeChildCursor := 0;
    FNodes[I].RuntimeServiceAccumSec := 0.0;
  end;
  FRunningLeafNodeId := '';
  FRunningLeafExecIndex := -1;
end;

{ Decorators, Observer Aborts & Services ------------------------------------- }

function TCastleBehaviorTree.EvaluateDecoratorCondition(
  const ANode: TBehaviorTreeNode): Boolean;
begin
  case ANode.DecoratorOp of
    bdopNone:
      Result := True;
    bdopBoolIsSet:
      Result := GetBlackboardBool(ANode.DecoratorKey, False);
    bdopBoolIsNotSet:
      Result := not GetBlackboardBool(ANode.DecoratorKey, False);
    bdopIntGreaterThan:
      Result := GetBlackboardInt(ANode.DecoratorKey, 0) > Round(ANode.DecoratorThreshold);
    bdopFloatGreaterOrEqual:
      Result := GetBlackboardFloat(ANode.DecoratorKey, 0.0) >= ANode.DecoratorThreshold;
  else
    Result := True;
  end;
end;

procedure TCastleBehaviorTree.CheckObserverAbortsBeforeTick;
var
  I, RunningIdx: Integer;
  CondNow, InsideSelfSubtree, InLowerPriorityBranch: Boolean;
begin
  if (FRunningLeafNodeId = '') or (FRunningLeafExecIndex < 0) then Exit;

  for I := 0 to High(FNodes) do
    if (FNodes[I].DecoratorOp <> bdopNone) and
       (FNodes[I].ObserverAborts <> famNone) and
       (FNodes[I].ExecutionIndex >= 0) then
    begin
      CondNow := EvaluateDecoratorCondition(FNodes[I]);
      InsideSelfSubtree :=
        (FRunningLeafExecIndex >= FNodes[I].ExecutionIndex) and
        (FRunningLeafExecIndex <= FNodes[I].SubtreeMaxExecIndex);
      InLowerPriorityBranch := FRunningLeafExecIndex > FNodes[I].SubtreeMaxExecIndex;

      { 1. Self Abort: currently executing inside this branch, and Decorator turned FALSE! }
      if InsideSelfSubtree and (not CondNow) and
         (FNodes[I].ObserverAborts in [famSelf, famBoth]) then
      begin
        Inc(FAbortCount);
        FExecutionLog.Add(Format('[ABORT:Self] Decorator "%s" failed -> aborted "%s"',
          [FNodes[I].NodeId, FRunningLeafNodeId]));
        ResetBehaviorTree;
        Exit;
      end;

      { 2. LowerPriority Abort: currently executing a lower-priority right-hand branch,
           and this higher-priority Decorator turned TRUE! }
      if InLowerPriorityBranch and CondNow and
         (FNodes[I].ObserverAborts in [famLowerPriority, famBoth]) then
      begin
        Inc(FAbortCount);
        RunningIdx := FindNodeIndex(FRunningLeafNodeId);
        if RunningIdx >= 0 then
          FNodes[RunningIdx].LastStatus := btsIdle;
        FExecutionLog.Add(Format('[ABORT:LowerPriority] High-priority "%s" preempted "%s"',
          [FNodes[I].NodeId, FRunningLeafNodeId]));
        ResetBehaviorTree;
        Exit;
      end;
    end;
end;

procedure TCastleBehaviorTree.TickNodeService(const ANodeIdx: Integer;
  const ADeltaSec: Single);
var
  DistVal: Single;
  TgtPos: TVector3;
begin
  if Trim(FNodes[ANodeIdx].ServiceName) = '' then Exit;
  FNodes[ANodeIdx].RuntimeServiceAccumSec :=
    FNodes[ANodeIdx].RuntimeServiceAccumSec + ADeltaSec;

  while FNodes[ANodeIdx].RuntimeServiceAccumSec + 1e-5 >=
        Max(0.05, FNodes[ANodeIdx].ServiceIntervalSec) do
  begin
    FNodes[ANodeIdx].RuntimeServiceAccumSec :=
      FNodes[ANodeIdx].RuntimeServiceAccumSec - Max(0.05, FNodes[ANodeIdx].ServiceIntervalSec);
    Inc(FServiceTickCount);
    if FNodes[ANodeIdx].ServiceTargetKey <> '' then
    begin
      TgtPos := GetBlackboardVec3('TargetLocation');
      DistVal := PointsDistance(Translation, TgtPos);
      SetBlackboardFloat(FNodes[ANodeIdx].ServiceTargetKey, DistVal);
    end;
    FExecutionLog.Add(Format('[SERVICE] %s ticked', [FNodes[ANodeIdx].ServiceName]));
  end;
end;

{ Recursive Tree Tick -------------------------------------------------------- }

function TCastleBehaviorTree.TickNodeRecursive(const ANodeIdx: Integer;
  const ADeltaSec: Single): TBehaviorNodeStatus;
var
  Kids: array[0..31] of Integer;
  KidCnt, StartChild, K: Integer;
  ChildStatus, BgStatus: TBehaviorNodeStatus;
  TgtPos, DeltaVec: TVector3;
  Dist, StepDist: Single;
begin
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then
    Exit(btsFailed);

  { Decorator gate }
  if not EvaluateDecoratorCondition(FNodes[ANodeIdx]) then
  begin
    FNodes[ANodeIdx].LastStatus := btsFailed;
    Exit(btsFailed);
  end;

  { Periodic Service attached to active node }
  if ADeltaSec > 0.0 then
    TickNodeService(ANodeIdx, ADeltaSec);

  CollectSortedChildren(FNodes[ANodeIdx].NodeId, Kids, KidCnt);

  case FNodes[ANodeIdx].Kind of
    btnRoot:
      begin
        if KidCnt = 0 then
          Result := btsFailed
        else
          Result := TickNodeRecursive(Kids[0], ADeltaSec);
      end;

    btnSelector:
      begin
        Result := btsFailed;
        StartChild := EnsureRange(FNodes[ANodeIdx].RuntimeChildCursor, 0, Max(0, KidCnt - 1));
        for K := StartChild to KidCnt - 1 do
        begin
          ChildStatus := TickNodeRecursive(Kids[K], ADeltaSec);
          if ChildStatus = btsRunning then
          begin
            FNodes[ANodeIdx].RuntimeChildCursor := K;
            Result := btsRunning;
            Break;
          end else if ChildStatus = btsSucceeded then
          begin
            FNodes[ANodeIdx].RuntimeChildCursor := 0;
            Result := btsSucceeded;
            Break;
          end;
        end;
        if Result = btsFailed then
          FNodes[ANodeIdx].RuntimeChildCursor := 0;
      end;

    btnSequence:
      begin
        Result := btsSucceeded;
        StartChild := EnsureRange(FNodes[ANodeIdx].RuntimeChildCursor, 0, Max(0, KidCnt - 1));
        for K := StartChild to KidCnt - 1 do
        begin
          ChildStatus := TickNodeRecursive(Kids[K], ADeltaSec);
          if ChildStatus = btsRunning then
          begin
            FNodes[ANodeIdx].RuntimeChildCursor := K;
            Result := btsRunning;
            Break;
          end else if ChildStatus = btsFailed then
          begin
            FNodes[ANodeIdx].RuntimeChildCursor := 0;
            Result := btsFailed;
            Break;
          end;
        end;
        if Result = btsSucceeded then
          FNodes[ANodeIdx].RuntimeChildCursor := 0;
      end;

    btnSimpleParallel:
      begin
        if KidCnt = 0 then
          Result := btsFailed
        else
        begin
          { Child 0 = Main Task, Child 1 = Background Subtree }
          ChildStatus := TickNodeRecursive(Kids[0], ADeltaSec);
          if (ChildStatus = btsRunning) and (KidCnt >= 2) then
          begin
            BgStatus := TickNodeRecursive(Kids[1], ADeltaSec);
            if BgStatus = btsIdle then ;
          end else if KidCnt >= 2 then
            ResetSubtreeRuntime(Kids[1]);
          Result := ChildStatus;
        end;
      end;

    btnTaskMoveTo:
      begin
        TgtPos := GetBlackboardVec3(FNodes[ANodeIdx].TargetBlackboardKey);
        DeltaVec := TgtPos - Translation;
        Dist := DeltaVec.Length;
        if Dist <= Max(0.05, FNodes[ANodeIdx].AcceptableRadius) then
        begin
          Translation := TgtPos;
          Result := btsSucceeded;
        end else
        begin
          StepDist := Max(0.1, FNodes[ANodeIdx].MoveSpeedMps) * Max(0.0, ADeltaSec);
          if StepDist >= Dist then
          begin
            Translation := TgtPos;
            Result := btsSucceeded;
          end else
          begin
            Translation := Translation + (DeltaVec / Dist) * StepDist;
            FRunningLeafNodeId := FNodes[ANodeIdx].NodeId;
            FRunningLeafExecIndex := FNodes[ANodeIdx].ExecutionIndex;
            Result := btsRunning;
          end;
        end;
      end;

    btnTaskWait:
      begin
        FNodes[ANodeIdx].RuntimeElapsedSec :=
          FNodes[ANodeIdx].RuntimeElapsedSec + Max(0.0, ADeltaSec);
        if FNodes[ANodeIdx].RuntimeElapsedSec + 1e-5 >= Max(0.01, FNodes[ANodeIdx].TaskDurationSec) then
        begin
          FNodes[ANodeIdx].RuntimeElapsedSec := 0.0;
          Result := btsSucceeded;
        end else
        begin
          FRunningLeafNodeId := FNodes[ANodeIdx].NodeId;
          FRunningLeafExecIndex := FNodes[ANodeIdx].ExecutionIndex;
          Result := btsRunning;
        end;
      end;

    btnTaskSetBlackboardBool:
      begin
        SetBlackboardBool(FNodes[ANodeIdx].TargetBlackboardKey, FNodes[ANodeIdx].TaskBoolValue);
        Result := btsSucceeded;
      end;

    btnTaskAddBlackboardInt:
      begin
        SetBlackboardInt(FNodes[ANodeIdx].TargetBlackboardKey,
          GetBlackboardInt(FNodes[ANodeIdx].TargetBlackboardKey, 0) + FNodes[ANodeIdx].TaskIntDelta);
        Result := btsSucceeded;
      end;
  else
    Result := btsFailed;
  end;

  FNodes[ANodeIdx].LastStatus := Result;
end;

function TCastleBehaviorTree.TickBehaviorTree(
  const ADeltaSeconds: Single): TBehaviorNodeStatus;
var
  RootIdx, I: Integer;
begin
  if not ValidateBehaviorTree then
    Exit(btsFailed);

  Inc(FTotalTickCount);

  { 1. Evaluate dynamic Observer Aborts against currently Running leaf before ticking }
  CheckObserverAbortsBeforeTick;

  { Clear non-running status highlights for visual clarity }
  for I := 0 to High(FNodes) do
    if FNodes[I].LastStatus <> btsRunning then
      FNodes[I].LastStatus := btsIdle;

  FRunningLeafNodeId := '';
  FRunningLeafExecIndex := -1;

  RootIdx := FindRootNodeIndex;
  Result := TickNodeRecursive(RootIdx, Max(0.0, ADeltaSeconds));
  SyncAgentGizmo;
end;

{ Built-In UE 5.5 Presets ---------------------------------------------------- }

procedure TCastleBehaviorTree.ApplyPreset(const APreset: TBehaviorTreePreset);
var
  N: TBehaviorTreeNode;
begin
  FPreset := APreset;
  if APreset = btpCustom then Exit;

  ClearTree;
  FPreset := APreset;

  case APreset of
    btpTacticalGuardObserverAborts:
      begin
        SetBlackboardBool('HasLineOfSight', False);
        SetBlackboardVec3('TargetLocation', Vector3(8.0, 0.0, 0.0));
        SetBlackboardVec3('PatrolPoint', Vector3(-4.0, 0.0, 0.0));
        SetBlackboardFloat('DistanceToTarget', 8.0);

        AddOrUpdateNode(MakeDefaultNode('BT_Root', 'Root', btnRoot, '', 420, 24));
        AddOrUpdateNode(MakeDefaultNode('Sel_Main', 'Main Selector', btnSelector, 'BT_Root', 420, 110));

        { Left high-priority Combat branch (Decorator: HasLineOfSight == True, Observer Aborts = Both!) }
        N := MakeDefaultNode('Seq_Combat', 'Engage Enemy', btnSequence, 'Sel_Main', 175, 220);
        N.DecoratorOp := bdopBoolIsSet;
        N.DecoratorKey := 'HasLineOfSight';
        N.ObserverAborts := famBoth;
        N.ServiceName := 'Svc_RangeTracker';
        N.ServiceTargetKey := 'DistanceToTarget';
        N.ServiceIntervalSec := 0.25;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Task_ChaseTarget', 'MoveTo TargetLocation', btnTaskMoveTo, 'Seq_Combat', 65, 350);
        N.TargetBlackboardKey := 'TargetLocation';
        N.MoveSpeedMps := 6.0;
        N.AcceptableRadius := 0.5;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Task_AttackPause', 'Attack Cooldown (0.5s)', btnTaskWait, 'Seq_Combat', 275, 350);
        N.TaskDurationSec := 0.5;
        AddOrUpdateNode(N);

        { Right lower-priority Patrol branch }
        AddOrUpdateNode(MakeDefaultNode('Seq_Patrol', 'Patrol Sector', btnSequence, 'Sel_Main', 665, 220));

        N := MakeDefaultNode('Task_MovePatrol', 'MoveTo PatrolPoint', btnTaskMoveTo, 'Seq_Patrol', 555, 350);
        N.TargetBlackboardKey := 'PatrolPoint';
        N.MoveSpeedMps := 4.0;
        N.AcceptableRadius := 0.5;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Task_PatrolWait', 'Guard Watch Wait (4.0s)', btnTaskWait, 'Seq_Patrol', 775, 350);
        N.TaskDurationSec := 4.0;
        AddOrUpdateNode(N);
      end;

    btpSimpleParallelSuppressAndMove:
      begin
        SetBlackboardVec3('CoverPoint', Vector3(6.0, 0.0, 0.0));
        SetBlackboardInt('BurstShotsFired', 0);

        AddOrUpdateNode(MakeDefaultNode('BT_Root', 'Root', btnRoot, '', 400, 24));
        AddOrUpdateNode(MakeDefaultNode('Par_Advance', 'Advance Under Fire', btnSimpleParallel, 'BT_Root', 400, 120));

        N := MakeDefaultNode('Main_MoveCover', 'MoveTo CoverPoint', btnTaskMoveTo, 'Par_Advance', 210, 250);
        N.TargetBlackboardKey := 'CoverPoint';
        N.MoveSpeedMps := 3.0;
        N.AcceptableRadius := 0.4;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Bg_SuppressShot', 'Suppressing Fire (+1)', btnTaskAddBlackboardInt, 'Par_Advance', 580, 250);
        N.TargetBlackboardKey := 'BurstShotsFired';
        N.TaskIntDelta := 1;
        AddOrUpdateNode(N);
      end;

    btpAmmoReloadFallbackSequence:
      begin
        SetBlackboardInt('AmmoCount', 2);
        AddOrUpdateNode(MakeDefaultNode('BT_Root', 'Root', btnRoot, '', 400, 24));
        AddOrUpdateNode(MakeDefaultNode('Sel_Weapon', 'Fire Or Reload', btnSelector, 'BT_Root', 400, 120));

        N := MakeDefaultNode('Task_FireRound', 'Fire 1 Round', btnTaskAddBlackboardInt, 'Sel_Weapon', 210, 250);
        N.DecoratorOp := bdopIntGreaterThan;
        N.DecoratorKey := 'AmmoCount';
        N.DecoratorThreshold := 0.0;
        N.TargetBlackboardKey := 'AmmoCount';
        N.TaskIntDelta := -1;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Task_ReloadMag', 'Reload Magazine (+6)', btnTaskAddBlackboardInt, 'Sel_Weapon', 580, 250);
        N.TargetBlackboardKey := 'AmmoCount';
        N.TaskIntDelta := 6;
        AddOrUpdateNode(N);
      end;
  end;

  ValidateBehaviorTree;
  SyncAgentGizmo;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleBehaviorTree.GetTreeJson: String;
var
  Root, Obj: TJSONObject;
  BbArr, NodesArr, VecArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    BbArr := TJSONArray.Create;
    for I := 0 to High(FBlackboard) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('k', FBlackboard[I].KeyName);
      Obj.Add('t', Ord(FBlackboard[I].KeyType));
      Obj.Add('b', FBlackboard[I].BoolVal);
      Obj.Add('i', FBlackboard[I].IntVal);
      Obj.Add('f', FBlackboard[I].FloatVal);
      Obj.Add('s', FBlackboard[I].StrVal);
      VecArr := TJSONArray.Create;
      VecArr.Add(FBlackboard[I].VecVal.X);
      VecArr.Add(FBlackboard[I].VecVal.Y);
      VecArr.Add(FBlackboard[I].VecVal.Z);
      Obj.Add('v', VecArr);
      BbArr.Add(Obj);
    end;
    Root.Add('blackboard', BbArr);

    NodesArr := TJSONArray.Create;
    for I := 0 to High(FNodes) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FNodes[I].NodeId);
      Obj.Add('title', FNodes[I].Title);
      Obj.Add('kind', Ord(FNodes[I].Kind));
      Obj.Add('parent', FNodes[I].ParentNodeId);
      Obj.Add('x', FNodes[I].PosX);
      Obj.Add('y', FNodes[I].PosY);
      Obj.Add('bbKey', FNodes[I].TargetBlackboardKey);
      Obj.Add('dur', FNodes[I].TaskDurationSec);
      Obj.Add('spd', FNodes[I].MoveSpeedMps);
      Obj.Add('rad', FNodes[I].AcceptableRadius);
      Obj.Add('tb', FNodes[I].TaskBoolValue);
      Obj.Add('ti', FNodes[I].TaskIntDelta);
      Obj.Add('dop', Ord(FNodes[I].DecoratorOp));
      Obj.Add('dkey', FNodes[I].DecoratorKey);
      Obj.Add('dthr', FNodes[I].DecoratorThreshold);
      Obj.Add('abort', Ord(FNodes[I].ObserverAborts));
      Obj.Add('svc', FNodes[I].ServiceName);
      Obj.Add('svck', FNodes[I].ServiceTargetKey);
      Obj.Add('svci', FNodes[I].ServiceIntervalSec);
      NodesArr.Add(Obj);
    end;
    Root.Add('nodes', NodesArr);

    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleBehaviorTree.SetTreeJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr, VecArr: TJSONArray;
  I: Integer;
  KType: TBlackboardKeyType;
  N: TBehaviorTreeNode;
begin
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;
  try
    if not (Parsed is TJSONObject) then Exit;
    Root := TJSONObject(Parsed);
    ClearTree;
    FPreset := btpCustom;

    Arr := Root.Find('blackboard', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          KType := TBlackboardKeyType(EnsureRange(Obj.Get('t', 0), 0, Ord(High(TBlackboardKeyType))));
          case KType of
            bktBool:   SetBlackboardBool(Obj.Get('k', ''), Obj.Get('b', False));
            bktInt:    SetBlackboardInt(Obj.Get('k', ''), Obj.Get('i', 0));
            bktFloat:  SetBlackboardFloat(Obj.Get('k', ''), Obj.Get('f', 0.0));
            bktString: SetBlackboardString(Obj.Get('k', ''), Obj.Get('s', ''));
            bktVector3:
              begin
                VecArr := Obj.Find('v', jtArray) as TJSONArray;
                if (VecArr <> nil) and (VecArr.Count >= 3) then
                  SetBlackboardVec3(Obj.Get('k', ''),
                    Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]));
              end;
          end;
        end;

    Arr := Root.Find('nodes', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          N := MakeDefaultNode(
            Obj.Get('id', 'BT_' + IntToStr(I)),
            Obj.Get('title', 'Node'),
            TBehaviorTreeNodeKind(EnsureRange(Obj.Get('kind', 0), 0, Ord(High(TBehaviorTreeNodeKind)))),
            Obj.Get('parent', ''),
            Obj.Get('x', 100.0),
            Obj.Get('y', 100.0));
          N.TargetBlackboardKey := Obj.Get('bbKey', '');
          N.TaskDurationSec := Obj.Get('dur', 1.0);
          N.MoveSpeedMps := Obj.Get('spd', 6.0);
          N.AcceptableRadius := Obj.Get('rad', 0.35);
          N.TaskBoolValue := Obj.Get('tb', False);
          N.TaskIntDelta := Obj.Get('ti', 0);
          N.DecoratorOp := TBlackboardDecoratorOp(EnsureRange(Obj.Get('dop', 0), 0, Ord(High(TBlackboardDecoratorOp))));
          N.DecoratorKey := Obj.Get('dkey', '');
          N.DecoratorThreshold := Obj.Get('dthr', 0.0);
          N.ObserverAborts := TFlowAbortMode(EnsureRange(Obj.Get('abort', 0), 0, Ord(High(TFlowAbortMode))));
          N.ServiceName := Obj.Get('svc', '');
          N.ServiceTargetKey := Obj.Get('svck', '');
          N.ServiceIntervalSec := Obj.Get('svci', 0.5);
          AddOrUpdateNode(N);
        end;

    ValidateBehaviorTree;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleBehaviorTree.BehaviorTreeSummaryBadge: String;
var
  ActiveStr: String;
begin
  if not FLastTreeValid then
    ActiveStr := Format('ERR:%d', [FValidationErrors.Count])
  else if FRunningLeafNodeId <> '' then
    ActiveStr := 'Run:' + FRunningLeafNodeId
  else
    ActiveStr := 'Ready';
  Result := Format('[BT:%s Nodes=%d BB=%d Aborts=%d]',
    [ActiveStr, Length(FNodes), Length(FBlackboard), FAbortCount]);
end;

initialization
  RegisterSerializableComponent(TCastleBehaviorTree, 'Behavior Tree & Blackboard AI');
end.
