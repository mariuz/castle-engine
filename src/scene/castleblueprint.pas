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

{ Unreal Engine 5.5-style Blueprint Visual Scripting Actor component,
  Construction Script + EventGraph bytecode/node VM, latent Delay/Timeline
  scheduler, node breakpoints, wire watch trace, and Pascal nativization
  (@link(TCastleBlueprint)) (Phase 381 — UE 5.5 UBlueprint / Kismet 2.0 Parity). }
unit CastleBlueprint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Sub-graph inside a @link(TCastleBlueprint) asset. }
  TBlueprintGraphKind = (
    bgkConstructionScript,
    bgkEventGraph
  );

  { Strongly-typed execution and data pin types matching UE5 Kismet colors. }
  TBlueprintPinType = (
    bptExec,
    bptBool,
    bptInt,
    bptFloat,
    bptString,
    bptVec3,
    bptObject
  );

  { Compile health of a @link(TCastleBlueprint). }
  TBlueprintCompileStatus = (
    bcsDirty,
    bcsUpToDate,
    bcsError
  );

  { Built-in UE5 Blueprint starter templates. }
  TBlueprintPreset = (
    bppCustom,
    bppPillarRowConstructionAndSpinPickup,
    bppSlidingDoorTimelineAndGate,
    bppPatrolBranchAndLatentDelay
  );

  { Node kinds supported in Construction Script and EventGraph. }
  TBlueprintNodeKind = (
    { Events }
    bnkConstructionEntry,
    bnkEventBeginPlay,
    bnkEventTick,
    bnkEventBeginOverlap,
    bnkCustomEvent,
    { Flow Control }
    bnkBranch,
    bnkSequence,
    bnkForLoop,
    bnkDoOnce,
    bnkFlipFlop,
    bnkGate,
    { Latent Actions (EventGraph only) }
    bnkDelay,
    bnkTimeline,
    { Variables }
    bnkGetVariable,
    bnkSetVariable,
    { Pure Math & Logic }
    bnkAddFloat,
    bnkMultiplyFloat,
    bnkGreaterFloat,
    bnkMakeVector,
    bnkLerpVector,
    { Scene / Actor Actions }
    bnkSpawnProceduralBox,
    bnkSetRelativeLocation,
    bnkAddLocalOffset,
    bnkAddLocalRotationYaw,
    bnkPrintString,
    bnkCallCustomEvent
  );

  { Runtime variant value carried across Blueprint data pins and variables. }
  TBlueprintValue = record
    PinType: TBlueprintPinType;
    BoolVal: Boolean;
    IntVal: Integer;
    FloatVal: Single;
    StrVal: String;
    VecVal: TVector3;
    ObjVal: TComponent;
    class function FromBool(const V: Boolean): TBlueprintValue; static;
    class function FromInt(const V: Integer): TBlueprintValue; static;
    class function FromFloat(const V: Single): TBlueprintValue; static;
    class function FromString(const V: String): TBlueprintValue; static;
    class function FromVec3(const V: TVector3): TBlueprintValue; static;
    class function FromObject(const V: TComponent): TBlueprintValue; static;
    function AsText: String;
  end;

  { Member variable declared in the Blueprint's "My Blueprint" panel. }
  TBlueprintVariable = record
    VarName: String;
    VarType: TBlueprintPinType;
    IsInstanceEditable: Boolean;
    Category: String;
    DefaultBool: Boolean;
    DefaultInt: Integer;
    DefaultFloat: Single;
    DefaultStr: String;
    DefaultVec: TVector3;
    CurrentValue: TBlueprintValue;
  end;
  TBlueprintVariableArray = array of TBlueprintVariable;

  { Node instance placed on either Construction Script or EventGraph canvas. }
  TBlueprintNode = record
    NodeId: String;
    Graph: TBlueprintGraphKind;
    Kind: TBlueprintNodeKind;
    MemberName: String;
    PosX: Single;
    PosY: Single;
    HasBreakpoint: Boolean;
    CommentText: String;
    { Literal fallback values for unconnected input data pins }
    DefaultBool0: Boolean;
    DefaultInt0: Integer;
    DefaultInt1: Integer;
    DefaultFloat0: Single;
    DefaultFloat1: Single;
    DefaultFloat2: Single;
    DefaultStr0: String;
    DefaultVec0: TVector3;
    DefaultVec1: TVector3;
    { Transient per-node runtime state (DoOnce, FlipFlop, Gate) }
    RuntimeDoOnceConsumed: Boolean;
    RuntimeFlipFlopNextIsA: Boolean;
    RuntimeGateInitialized: Boolean;
    RuntimeGateIsOpen: Boolean;
  end;
  TBlueprintNodeArray = array of TBlueprintNode;

  { White execution wire connecting an output Exec pin to an input Exec pin. }
  TBlueprintExecLink = record
    Graph: TBlueprintGraphKind;
    FromNodeId: String;
    FromExecPin: Integer;
    ToNodeId: String;
    ToExecPin: Integer;
  end;
  TBlueprintExecLinkArray = array of TBlueprintExecLink;

  { Color-coded typed data wire connecting an output Data pin to an input Data pin. }
  TBlueprintDataLink = record
    Graph: TBlueprintGraphKind;
    FromNodeId: String;
    FromDataPin: Integer;
    ToNodeId: String;
    ToDataPin: Integer;
  end;
  TBlueprintDataLinkArray = array of TBlueprintDataLink;

  { Pending latent action (Delay or Timeline) ticked during EventGraph updates. }
  TBlueprintLatentTask = record
    Active: Boolean;
    NodeId: String;
    Kind: TBlueprintNodeKind;
    DurationSec: Single;
    ElapsedSec: Single;
    ReverseDirection: Boolean;
  end;
  TBlueprintLatentTaskArray = array of TBlueprintLatentTask;

  { Unreal Engine 5.5-style Blueprint Actor component combining a live in-editor
    Construction Script, an event-driven EventGraph VM, latent Delay/Timeline
    schedulers, node breakpoints with wire watch values, and Pascal codegen. }
  TCastleBlueprint = class(TCastleTransform)
  public
    const
      DefaultMaxExecStepsPerCall = 2048;
  private
    FPreset: TBlueprintPreset;
    FBlueprintClassName: String;
    FAutoRunConstruction: Boolean;
    FBreakpointsEnabled: Boolean;
    FMaxExecStepsPerCall: Integer;

    FVariables: TBlueprintVariableArray;
    FNodes: TBlueprintNodeArray;
    FExecLinks: TBlueprintExecLinkArray;
    FDataLinks: TBlueprintDataLinkArray;

    { Transient runtime & compiler state }
    FCompileStatus: TBlueprintCompileStatus;
    FCompileErrors: TStringList;
    FCompileWarnings: TStringList;
    FPrintLog: TStringList;
    FWatchTrace: TStringList;
    FActiveExecTrace: TStringList;
    FLatentTasks: TBlueprintLatentTaskArray;
    FConstructionContainer: TCastleTransform;
    FConstructionSpawnCount: Integer;

    FIsPausedAtBreakpoint: Boolean;
    FPausedGraph: TBlueprintGraphKind;
    FPausedNodeId: String;
    FPausedExecInPin: Integer;
    FSkipBreakpointOnceNodeId: String;
    FHaltedByInfiniteLoopGuard: Boolean;
    FLastTickDeltaSeconds: Single;
    FLastOverlapActorName: String;
    FLastTimelineAlpha: Single;
    FLastForLoopIndex: Integer;
    FYawDegreesAccum: Single;
    FTotalExecutedSteps: Integer;

    procedure SetPreset(const AValue: TBlueprintPreset);
    procedure SetMaxExecStepsPerCall(const AValue: Integer);
    function GetGraphJson: String;
    procedure SetGraphJson(const AValue: String);
    procedure MarkDirty;
    procedure ClearConstructionSpawnedChildren;
    procedure EnsureConstructionContainer;

    function EvaluateDataInput(const ANodeIdx, AInPin: Integer;
      var VisitedPureMask: array of Byte): TBlueprintValue;
    function EvaluateNodeDataOutput(const ANodeIdx, AOutPin: Integer;
      var VisitedPureMask: array of Byte): TBlueprintValue;
    procedure ExecuteFromNode(const AGraph: TBlueprintGraphKind;
      const ANodeIdx, AExecInPin: Integer; var StepBudget: Integer);
    procedure FollowExecOut(const AGraph: TBlueprintGraphKind;
      const AFromNodeIdx, AFromExecOutPin: Integer; var StepBudget: Integer);
    procedure UpsertLatentTask(const ANodeId: String; const AKind: TBlueprintNodeKind;
      const ADurationSec: Single; const AReverse: Boolean);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Static metadata for node pins, titles, and UE5 Kismet header categories }
    class function NodeKindTitle(const AKind: TBlueprintNodeKind): String; static;
    class function NodeIsPure(const AKind: TBlueprintNodeKind): Boolean; static;
    class function NodeIsEvent(const AKind: TBlueprintNodeKind): Boolean; static;
    class function NodeIsLatent(const AKind: TBlueprintNodeKind): Boolean; static;
    class function NodeExecInCount(const AKind: TBlueprintNodeKind): Integer; static;
    class function NodeExecOutCount(const AKind: TBlueprintNodeKind): Integer; static;
    class function NodeExecInName(const AKind: TBlueprintNodeKind; const PinIdx: Integer): String; static;
    class function NodeExecOutName(const AKind: TBlueprintNodeKind; const PinIdx: Integer): String; static;
    class function NodeDataInCount(const AKind: TBlueprintNodeKind): Integer; static;
    class function NodeDataOutCount(const AKind: TBlueprintNodeKind): Integer; static;
    class function NodeDataInName(const AKind: TBlueprintNodeKind; const PinIdx: Integer): String; static;
    class function NodeDataOutName(const AKind: TBlueprintNodeKind; const PinIdx: Integer): String; static;
    class function NodeDataInType(const AKind: TBlueprintNodeKind;
      const PinIdx: Integer; const AVarType: TBlueprintPinType = bptFloat): TBlueprintPinType; static;
    class function NodeDataOutType(const AKind: TBlueprintNodeKind;
      const PinIdx: Integer; const AVarType: TBlueprintPinType = bptFloat): TBlueprintPinType; static;
    class function PinTypesCompatible(const AFromType, AToType: TBlueprintPinType): Boolean; static;
    class function PinTypeName(const AType: TBlueprintPinType): String; static;

    { Graph authoring API }
    procedure ClearAllGraphs;
    procedure ApplyPreset(const APreset: TBlueprintPreset);

    function AddOrUpdateVariable(const AName: String; const AType: TBlueprintPinType;
      const ADefaultVal: TBlueprintValue; const AInstanceEditable: Boolean = True;
      const ACategory: String = 'Default'): Integer;
    function FindVariableIndex(const AName: String): Integer;
    function GetVariableValue(const AName: String; out OutVal: TBlueprintValue): Boolean;
    function SetVariableFloat(const AName: String; const AVal: Single): Boolean;
    function SetVariableInt(const AName: String; const AVal: Integer): Boolean;
    function SetVariableBool(const AName: String; const AVal: Boolean): Boolean;
    function SetVariableString(const AName: String; const AVal: String): Boolean;
    function SetVariableVec3(const AName: String; const AVal: TVector3): Boolean;
    procedure ResetVariablesToDefaults;

    class function MakeDefaultNode(const ANodeId: String;
      const AGraph: TBlueprintGraphKind; const AKind: TBlueprintNodeKind;
      const AX: Single = 80; const AY: Single = 80;
      const AMemberName: String = ''): TBlueprintNode; static;
    function AddOrUpdateNode(const ANode: TBlueprintNode): Integer;
    function RemoveNode(const ANodeId: String): Boolean;
    function FindNodeIndex(const ANodeId: String): Integer;
    function ToggleNodeBreakpoint(const ANodeId: String): Boolean;
    function SetNodePosition(const ANodeId: String; const AX, AY: Single): Boolean;

    function ConnectExec(const AGraph: TBlueprintGraphKind;
      const AFromNodeId: String; const AFromExecPin: Integer;
      const AToNodeId: String; const AToExecPin: Integer = 0): Boolean;
    function ConnectData(const AGraph: TBlueprintGraphKind;
      const AFromNodeId: String; const AFromDataPin: Integer;
      const AToNodeId: String; const AToDataPin: Integer): Boolean;
    procedure DisconnectNodePins(const ANodeId: String);

    { Compiler, Construction Script, EventGraph Execution & Breakpoint Debugging }
    function CompileBlueprint: Boolean;
    procedure ResetRuntimeState;
    function RunConstructionScript: Boolean;
    function ExecuteBeginPlay: Boolean;
    function StepBlueprintTick(const ADeltaSeconds: Single): Boolean;
    function ExecuteActorBeginOverlap(const AOtherActorName: String): Boolean;
    function ExecuteCustomEvent(const AEventName: String): Boolean;
    function ResumeFromBreakpoint: Boolean;

    { Blueprint Nativization -> Compilable CGE Pascal Behavior Unit }
    function GeneratePascalUnit(const AUnitName: String = ''): String;

    { Concise Hierarchy badge }
    function BlueprintSummaryBadge: String;

    property Variables: TBlueprintVariableArray read FVariables;
    property Nodes: TBlueprintNodeArray read FNodes;
    property ExecLinks: TBlueprintExecLinkArray read FExecLinks;
    property DataLinks: TBlueprintDataLinkArray read FDataLinks;

    property CompileStatus: TBlueprintCompileStatus read FCompileStatus;
    property CompileErrors: TStringList read FCompileErrors;
    property CompileWarnings: TStringList read FCompileWarnings;
    property PrintLog: TStringList read FPrintLog;
    property WatchTrace: TStringList read FWatchTrace;
    property ActiveExecTrace: TStringList read FActiveExecTrace;
    property ConstructionSpawnCount: Integer read FConstructionSpawnCount;
    property IsPausedAtBreakpoint: Boolean read FIsPausedAtBreakpoint;
    property PausedNodeId: String read FPausedNodeId;
    property PausedGraph: TBlueprintGraphKind read FPausedGraph;
    property HaltedByInfiniteLoopGuard: Boolean read FHaltedByInfiniteLoopGuard;
    property YawDegreesAccum: Single read FYawDegreesAccum;
    property TotalExecutedSteps: Integer read FTotalExecutedSteps;
  published
    property BlueprintClassName: String read FBlueprintClassName write FBlueprintClassName;
    property AutoRunConstruction: Boolean read FAutoRunConstruction write FAutoRunConstruction default True;
    property BreakpointsEnabled: Boolean read FBreakpointsEnabled write FBreakpointsEnabled default True;
    property MaxExecStepsPerCall: Integer read FMaxExecStepsPerCall write SetMaxExecStepsPerCall default DefaultMaxExecStepsPerCall;
    property GraphJson: String read GetGraphJson write SetGraphJson;
    property Preset: TBlueprintPreset read FPreset write SetPreset default bppPillarRowConstructionAndSpinPickup;
  end;

implementation

uses
  fpjson, jsonparser, TypInfo;

{ TBlueprintValue ------------------------------------------------------------ }

class function TBlueprintValue.FromBool(const V: Boolean): TBlueprintValue;
begin
  Result := Default(TBlueprintValue);
  Result.PinType := bptBool;
  Result.BoolVal := V;
  if V then Result.IntVal := 1 else Result.IntVal := 0;
  Result.FloatVal := Result.IntVal;
end;

class function TBlueprintValue.FromInt(const V: Integer): TBlueprintValue;
begin
  Result := Default(TBlueprintValue);
  Result.PinType := bptInt;
  Result.IntVal := V;
  Result.FloatVal := V;
  Result.BoolVal := V <> 0;
end;

class function TBlueprintValue.FromFloat(const V: Single): TBlueprintValue;
begin
  Result := Default(TBlueprintValue);
  Result.PinType := bptFloat;
  Result.FloatVal := V;
  Result.IntVal := Round(V);
  Result.BoolVal := not IsZero(V);
end;

class function TBlueprintValue.FromString(const V: String): TBlueprintValue;
begin
  Result := Default(TBlueprintValue);
  Result.PinType := bptString;
  Result.StrVal := V;
  Result.BoolVal := V <> '';
end;

class function TBlueprintValue.FromVec3(const V: TVector3): TBlueprintValue;
begin
  Result := Default(TBlueprintValue);
  Result.PinType := bptVec3;
  Result.VecVal := V;
end;

class function TBlueprintValue.FromObject(const V: TComponent): TBlueprintValue;
begin
  Result := Default(TBlueprintValue);
  Result.PinType := bptObject;
  Result.ObjVal := V;
  Result.BoolVal := V <> nil;
end;

function TBlueprintValue.AsText: String;
begin
  case PinType of
    bptBool:   Result := BoolToStr(BoolVal, 'True', 'False');
    bptInt:    Result := IntToStr(IntVal);
    bptFloat:  Result := FormatFloat('0.###', FloatVal);
    bptString: Result := '"' + StrVal + '"';
    bptVec3:   Result := Format('(%.2f, %.2f, %.2f)', [VecVal.X, VecVal.Y, VecVal.Z]);
    bptObject:
      if ObjVal <> nil then
        Result := ObjVal.Name + ':' + ObjVal.ClassName
      else
        Result := 'None';
  else
    Result := '<Exec>';
  end;
end;

{ TCastleBlueprint ----------------------------------------------------------- }

constructor TCastleBlueprint.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBlueprintClassName := 'BP_ActorLogic';
  FAutoRunConstruction := True;
  FBreakpointsEnabled := True;
  FMaxExecStepsPerCall := DefaultMaxExecStepsPerCall;
  FCompileStatus := bcsDirty;
  FCompileErrors := TStringList.Create;
  FCompileWarnings := TStringList.Create;
  FPrintLog := TStringList.Create;
  FWatchTrace := TStringList.Create;
  FActiveExecTrace := TStringList.Create;
  ApplyPreset(bppPillarRowConstructionAndSpinPickup);
end;

destructor TCastleBlueprint.Destroy;
begin
  ClearConstructionSpawnedChildren;
  FreeAndNil(FActiveExecTrace);
  FreeAndNil(FWatchTrace);
  FreeAndNil(FPrintLog);
  FreeAndNil(FCompileWarnings);
  FreeAndNil(FCompileErrors);
  inherited;
end;

procedure TCastleBlueprint.Loaded;
begin
  inherited;
  CompileBlueprint;
  if FAutoRunConstruction and (FCompileStatus = bcsUpToDate) then
    RunConstructionScript;
end;

function TCastleBlueprint.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'BlueprintClassName') or
     (PropertyName = 'Preset') or
     (PropertyName = 'AutoRunConstruction') or
     (PropertyName = 'BreakpointsEnabled') or
     (PropertyName = 'MaxExecStepsPerCall') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleBlueprint.SetPreset(const AValue: TBlueprintPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleBlueprint.SetMaxExecStepsPerCall(const AValue: Integer);
begin
  FMaxExecStepsPerCall := Max(16, AValue);
end;

procedure TCastleBlueprint.MarkDirty;
begin
  FCompileStatus := bcsDirty;
end;

class function TCastleBlueprint.NodeKindTitle(const AKind: TBlueprintNodeKind): String;
begin
  case AKind of
    bnkConstructionEntry:   Result := 'Construction Script';
    bnkEventBeginPlay:      Result := 'Event BeginPlay';
    bnkEventTick:           Result := 'Event Tick';
    bnkEventBeginOverlap:   Result := 'Event ActorBeginOverlap';
    bnkCustomEvent:         Result := 'Custom Event';
    bnkBranch:              Result := 'Branch';
    bnkSequence:            Result := 'Sequence';
    bnkForLoop:             Result := 'For Loop';
    bnkDoOnce:              Result := 'Do Once';
    bnkFlipFlop:            Result := 'Flip Flop';
    bnkGate:                Result := 'Gate';
    bnkDelay:               Result := 'Delay (Latent)';
    bnkTimeline:            Result := 'Timeline (0..1 Curve)';
    bnkGetVariable:         Result := 'Get Variable';
    bnkSetVariable:         Result := 'Set Variable';
    bnkAddFloat:            Result := 'Float + Float';
    bnkMultiplyFloat:       Result := 'Float * Float';
    bnkGreaterFloat:        Result := 'Float > Float';
    bnkMakeVector:          Result := 'Make Vector';
    bnkLerpVector:          Result := 'VLerp (Vector)';
    bnkSpawnProceduralBox:  Result := 'Add Procedural Box';
    bnkSetRelativeLocation: Result := 'Set Relative Location';
    bnkAddLocalOffset:      Result := 'Add Local Offset';
    bnkAddLocalRotationYaw: Result := 'Add Local Rotation Yaw';
    bnkPrintString:         Result := 'Print String';
    bnkCallCustomEvent:     Result := 'Call Custom Event';
  end;
end;

class function TCastleBlueprint.NodeIsPure(const AKind: TBlueprintNodeKind): Boolean;
begin
  Result := AKind in [
    bnkGetVariable, bnkAddFloat, bnkMultiplyFloat, bnkGreaterFloat,
    bnkMakeVector, bnkLerpVector
  ];
end;

class function TCastleBlueprint.NodeIsEvent(const AKind: TBlueprintNodeKind): Boolean;
begin
  Result := AKind in [
    bnkConstructionEntry, bnkEventBeginPlay, bnkEventTick,
    bnkEventBeginOverlap, bnkCustomEvent
  ];
end;

class function TCastleBlueprint.NodeIsLatent(const AKind: TBlueprintNodeKind): Boolean;
begin
  Result := AKind in [bnkDelay, bnkTimeline];
end;

class function TCastleBlueprint.NodeExecInCount(const AKind: TBlueprintNodeKind): Integer;
begin
  if NodeIsPure(AKind) or NodeIsEvent(AKind) then
    Exit(0);
  case AKind of
    bnkDoOnce:   Result := 2; { 0=Execute, 1=Reset }
    bnkGate:     Result := 4; { 0=Enter, 1=Open, 2=Close, 3=Toggle }
    bnkTimeline: Result := 2; { 0=PlayFromStart, 1=ReverseFromEnd }
  else
    Result := 1;
  end;
end;

class function TCastleBlueprint.NodeExecOutCount(const AKind: TBlueprintNodeKind): Integer;
begin
  if NodeIsPure(AKind) then
    Exit(0);
  case AKind of
    bnkBranch:   Result := 2; { 0=True, 1=False }
    bnkSequence: Result := 3; { 0=Then 0, 1=Then 1, 2=Then 2 }
    bnkForLoop:  Result := 2; { 0=LoopBody, 1=Completed }
    bnkFlipFlop: Result := 2; { 0=A, 1=B }
    bnkTimeline: Result := 2; { 0=Update, 1=Finished }
  else
    Result := 1;
  end;
end;

class function TCastleBlueprint.NodeExecInName(const AKind: TBlueprintNodeKind;
  const PinIdx: Integer): String;
begin
  case AKind of
    bnkDoOnce:
      if PinIdx = 1 then Result := 'Reset' else Result := 'Execute';
    bnkGate:
      case PinIdx of
        1: Result := 'Open';
        2: Result := 'Close';
        3: Result := 'Toggle';
      else
        Result := 'Enter';
      end;
    bnkTimeline:
      if PinIdx = 1 then Result := 'ReverseFromEnd' else Result := 'PlayFromStart';
  else
    Result := 'Exec';
  end;
end;

class function TCastleBlueprint.NodeExecOutName(const AKind: TBlueprintNodeKind;
  const PinIdx: Integer): String;
begin
  case AKind of
    bnkBranch:
      if PinIdx = 1 then Result := 'False' else Result := 'True';
    bnkSequence:
      Result := Format('Then %d', [PinIdx]);
    bnkForLoop:
      if PinIdx = 1 then Result := 'Completed' else Result := 'LoopBody';
    bnkFlipFlop:
      if PinIdx = 1 then Result := 'B' else Result := 'A';
    bnkTimeline:
      if PinIdx = 1 then Result := 'Finished' else Result := 'Update';
    bnkDelay:
      Result := 'Completed';
  else
    Result := 'Then';
  end;
end;

class function TCastleBlueprint.NodeDataInCount(const AKind: TBlueprintNodeKind): Integer;
begin
  case AKind of
    bnkBranch, bnkDoOnce, bnkGate, bnkDelay, bnkTimeline,
    bnkSetVariable, bnkSetRelativeLocation, bnkAddLocalOffset,
    bnkAddLocalRotationYaw, bnkPrintString:
      Result := 1;
    bnkForLoop, bnkAddFloat, bnkMultiplyFloat, bnkGreaterFloat:
      Result := 2;
    bnkMakeVector, bnkLerpVector, bnkSpawnProceduralBox:
      Result := 3;
  else
    Result := 0;
  end;
end;

class function TCastleBlueprint.NodeDataOutCount(const AKind: TBlueprintNodeKind): Integer;
begin
  case AKind of
    bnkEventTick, bnkEventBeginOverlap, bnkForLoop, bnkFlipFlop,
    bnkTimeline, bnkGetVariable, bnkSetVariable,
    bnkAddFloat, bnkMultiplyFloat, bnkGreaterFloat,
    bnkMakeVector, bnkLerpVector, bnkSpawnProceduralBox:
      Result := 1;
  else
    Result := 0;
  end;
end;

class function TCastleBlueprint.NodeDataInName(const AKind: TBlueprintNodeKind;
  const PinIdx: Integer): String;
begin
  case AKind of
    bnkBranch: Result := 'Condition';
    bnkForLoop:
      if PinIdx = 0 then Result := 'FirstIndex' else Result := 'LastIndex';
    bnkDoOnce, bnkGate: Result := 'StartClosed';
    bnkDelay: Result := 'Duration';
    bnkTimeline: Result := 'LengthSec';
    bnkSetVariable: Result := 'Value';
    bnkAddFloat, bnkMultiplyFloat, bnkGreaterFloat:
      if PinIdx = 0 then Result := 'A' else Result := 'B';
    bnkMakeVector:
      case PinIdx of
        0: Result := 'X';
        1: Result := 'Y';
      else
        Result := 'Z';
      end;
    bnkLerpVector:
      case PinIdx of
        0: Result := 'A';
        1: Result := 'B';
      else
        Result := 'Alpha';
      end;
    bnkSpawnProceduralBox:
      case PinIdx of
        0: Result := 'LocalOffset';
        1: Result := 'BoxSize';
      else
        Result := 'ColorRGB';
      end;
    bnkSetRelativeLocation: Result := 'NewLocation';
    bnkAddLocalOffset: Result := 'DeltaLocation';
    bnkAddLocalRotationYaw: Result := 'DeltaYawDeg';
    bnkPrintString: Result := 'InString';
  else
    Result := 'In';
  end;
end;

class function TCastleBlueprint.NodeDataOutName(const AKind: TBlueprintNodeKind;
  const PinIdx: Integer): String;
begin
  case AKind of
    bnkEventTick: Result := 'DeltaSeconds';
    bnkEventBeginOverlap: Result := 'OtherActor';
    bnkForLoop: Result := 'Index';
    bnkFlipFlop: Result := 'IsA';
    bnkTimeline: Result := 'Alpha';
    bnkGetVariable, bnkSetVariable: Result := 'Value';
    bnkGreaterFloat: Result := 'Result';
    bnkMakeVector, bnkLerpVector: Result := 'ReturnVec';
    bnkSpawnProceduralBox: Result := 'SpawnedBox';
  else
    Result := 'ReturnValue';
  end;
end;

class function TCastleBlueprint.NodeDataInType(const AKind: TBlueprintNodeKind;
  const PinIdx: Integer; const AVarType: TBlueprintPinType): TBlueprintPinType;
begin
  case AKind of
    bnkBranch, bnkDoOnce, bnkGate: Result := bptBool;
    bnkForLoop: Result := bptInt;
    bnkDelay, bnkTimeline, bnkAddFloat, bnkMultiplyFloat, bnkGreaterFloat,
    bnkMakeVector, bnkAddLocalRotationYaw:
      Result := bptFloat;
    bnkSetVariable: Result := AVarType;
    bnkLerpVector:
      if PinIdx = 2 then Result := bptFloat else Result := bptVec3;
    bnkSpawnProceduralBox, bnkSetRelativeLocation, bnkAddLocalOffset:
      Result := bptVec3;
    bnkPrintString:
      Result := bptString;
  else
    Result := bptFloat;
  end;
end;

class function TCastleBlueprint.NodeDataOutType(const AKind: TBlueprintNodeKind;
  const PinIdx: Integer; const AVarType: TBlueprintPinType): TBlueprintPinType;
begin
  case AKind of
    bnkEventTick, bnkTimeline, bnkAddFloat, bnkMultiplyFloat:
      Result := bptFloat;
    bnkEventBeginOverlap:
      Result := bptString;
    bnkForLoop:
      Result := bptInt;
    bnkFlipFlop, bnkGreaterFloat:
      Result := bptBool;
    bnkGetVariable, bnkSetVariable:
      Result := AVarType;
    bnkMakeVector, bnkLerpVector:
      Result := bptVec3;
    bnkSpawnProceduralBox:
      Result := bptObject;
  else
    Result := bptFloat;
  end;
end;

class function TCastleBlueprint.PinTypesCompatible(
  const AFromType, AToType: TBlueprintPinType): Boolean;
begin
  if (AFromType = bptExec) or (AToType = bptExec) then
    Exit(AFromType = AToType);
  if AFromType = AToType then
    Exit(True);
  { UE5 Blueprint automatic conversion nodes: Int -> Float, Bool/Int/Float/Vec3 -> String }
  if (AFromType = bptInt) and (AToType = bptFloat) then
    Exit(True);
  if AToType = bptString then
    Exit(True);
  Result := False;
end;

class function TCastleBlueprint.PinTypeName(const AType: TBlueprintPinType): String;
begin
  case AType of
    bptExec:   Result := 'Exec';
    bptBool:   Result := 'Boolean';
    bptInt:    Result := 'Integer';
    bptFloat:  Result := 'Single';
    bptString: Result := 'String';
    bptVec3:   Result := 'TVector3';
    bptObject: Result := 'TComponent';
  end;
end;

procedure TCastleBlueprint.ClearAllGraphs;
begin
  ClearConstructionSpawnedChildren;
  FVariables := nil;
  FNodes := nil;
  FExecLinks := nil;
  FDataLinks := nil;
  FLatentTasks := nil;
  FPrintLog.Clear;
  FWatchTrace.Clear;
  FActiveExecTrace.Clear;
  FIsPausedAtBreakpoint := False;
  FPausedNodeId := '';
  FHaltedByInfiniteLoopGuard := False;
  MarkDirty;
end;

function TCastleBlueprint.FindVariableIndex(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FVariables) do
    if SameText(FVariables[I].VarName, AName) then
      Exit(I);
  Result := -1;
end;

function TCastleBlueprint.AddOrUpdateVariable(const AName: String;
  const AType: TBlueprintPinType; const ADefaultVal: TBlueprintValue;
  const AInstanceEditable: Boolean; const ACategory: String): Integer;
begin
  Result := FindVariableIndex(AName);
  if Result < 0 then
  begin
    Result := Length(FVariables);
    SetLength(FVariables, Result + 1);
  end;
  FVariables[Result].VarName := AName;
  FVariables[Result].VarType := AType;
  FVariables[Result].IsInstanceEditable := AInstanceEditable;
  FVariables[Result].Category := ACategory;
  FVariables[Result].DefaultBool := ADefaultVal.BoolVal;
  FVariables[Result].DefaultInt := ADefaultVal.IntVal;
  FVariables[Result].DefaultFloat := ADefaultVal.FloatVal;
  FVariables[Result].DefaultStr := ADefaultVal.StrVal;
  FVariables[Result].DefaultVec := ADefaultVal.VecVal;
  FVariables[Result].CurrentValue := ADefaultVal;
  FVariables[Result].CurrentValue.PinType := AType;
  MarkDirty;
end;

function TCastleBlueprint.GetVariableValue(const AName: String;
  out OutVal: TBlueprintValue): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AName);
  Result := Idx >= 0;
  if Result then
    OutVal := FVariables[Idx].CurrentValue
  else
    OutVal := Default(TBlueprintValue);
end;

function TCastleBlueprint.SetVariableFloat(const AName: String; const AVal: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AName);
  Result := (Idx >= 0) and (FVariables[Idx].VarType = bptFloat);
  if Result then
  begin
    FVariables[Idx].DefaultFloat := AVal;
    FVariables[Idx].CurrentValue := TBlueprintValue.FromFloat(AVal);
  end;
end;

function TCastleBlueprint.SetVariableInt(const AName: String; const AVal: Integer): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AName);
  Result := (Idx >= 0) and (FVariables[Idx].VarType = bptInt);
  if Result then
  begin
    FVariables[Idx].DefaultInt := AVal;
    FVariables[Idx].CurrentValue := TBlueprintValue.FromInt(AVal);
  end;
end;

function TCastleBlueprint.SetVariableBool(const AName: String; const AVal: Boolean): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AName);
  Result := (Idx >= 0) and (FVariables[Idx].VarType = bptBool);
  if Result then
  begin
    FVariables[Idx].DefaultBool := AVal;
    FVariables[Idx].CurrentValue := TBlueprintValue.FromBool(AVal);
  end;
end;

function TCastleBlueprint.SetVariableString(const AName: String; const AVal: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AName);
  Result := (Idx >= 0) and (FVariables[Idx].VarType = bptString);
  if Result then
  begin
    FVariables[Idx].DefaultStr := AVal;
    FVariables[Idx].CurrentValue := TBlueprintValue.FromString(AVal);
  end;
end;

function TCastleBlueprint.SetVariableVec3(const AName: String; const AVal: TVector3): Boolean;
var
  Idx: Integer;
begin
  Idx := FindVariableIndex(AName);
  Result := (Idx >= 0) and (FVariables[Idx].VarType = bptVec3);
  if Result then
  begin
    FVariables[Idx].DefaultVec := AVal;
    FVariables[Idx].CurrentValue := TBlueprintValue.FromVec3(AVal);
  end;
end;

procedure TCastleBlueprint.ResetVariablesToDefaults;
var
  I: Integer;
begin
  for I := 0 to High(FVariables) do
    case FVariables[I].VarType of
      bptBool:   FVariables[I].CurrentValue := TBlueprintValue.FromBool(FVariables[I].DefaultBool);
      bptInt:    FVariables[I].CurrentValue := TBlueprintValue.FromInt(FVariables[I].DefaultInt);
      bptFloat:  FVariables[I].CurrentValue := TBlueprintValue.FromFloat(FVariables[I].DefaultFloat);
      bptString: FVariables[I].CurrentValue := TBlueprintValue.FromString(FVariables[I].DefaultStr);
      bptVec3:   FVariables[I].CurrentValue := TBlueprintValue.FromVec3(FVariables[I].DefaultVec);
      bptObject: FVariables[I].CurrentValue := TBlueprintValue.FromObject(Self);
    else
      FVariables[I].CurrentValue := Default(TBlueprintValue);
    end;
end;

class function TCastleBlueprint.MakeDefaultNode(const ANodeId: String;
  const AGraph: TBlueprintGraphKind; const AKind: TBlueprintNodeKind;
  const AX, AY: Single; const AMemberName: String): TBlueprintNode;
begin
  Result := Default(TBlueprintNode);
  Result.NodeId := ANodeId;
  Result.Graph := AGraph;
  Result.Kind := AKind;
  Result.MemberName := AMemberName;
  Result.PosX := AX;
  Result.PosY := AY;
  Result.DefaultBool0 := False;
  Result.DefaultInt0 := 0;
  Result.DefaultInt1 := 3;
  Result.DefaultFloat0 := 1.0;
  Result.DefaultFloat1 := 1.0;
  Result.DefaultFloat2 := 0.0;
  Result.DefaultStr0 := 'Hello Blueprint';
  Result.DefaultVec0 := Vector3(0, 0, 0);
  Result.DefaultVec1 := Vector3(1, 2, 1);
  Result.RuntimeFlipFlopNextIsA := True;
  if AKind = bnkSpawnProceduralBox then
  begin
    Result.DefaultVec0 := Vector3(0, 1.0, 0);
    Result.DefaultVec1 := Vector3(0.8, 2.0, 0.8);
    Result.DefaultFloat0 := 0.82;
    Result.DefaultFloat1 := 0.76;
    Result.DefaultFloat2 := 0.65;
  end;
end;

function TCastleBlueprint.FindNodeIndex(const ANodeId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].NodeId, ANodeId) then
      Exit(I);
  Result := -1;
end;

function TCastleBlueprint.AddOrUpdateNode(const ANode: TBlueprintNode): Integer;
begin
  Result := FindNodeIndex(ANode.NodeId);
  if Result < 0 then
  begin
    Result := Length(FNodes);
    SetLength(FNodes, Result + 1);
  end;
  FNodes[Result] := ANode;
  FNodes[Result].RuntimeFlipFlopNextIsA := True;
  MarkDirty;
end;

procedure TCastleBlueprint.DisconnectNodePins(const ANodeId: String);
var
  I, KeepCnt: Integer;
begin
  KeepCnt := 0;
  for I := 0 to High(FExecLinks) do
    if (not SameText(FExecLinks[I].FromNodeId, ANodeId)) and
       (not SameText(FExecLinks[I].ToNodeId, ANodeId)) then
    begin
      FExecLinks[KeepCnt] := FExecLinks[I];
      Inc(KeepCnt);
    end;
  SetLength(FExecLinks, KeepCnt);

  KeepCnt := 0;
  for I := 0 to High(FDataLinks) do
    if (not SameText(FDataLinks[I].FromNodeId, ANodeId)) and
       (not SameText(FDataLinks[I].ToNodeId, ANodeId)) then
    begin
      FDataLinks[KeepCnt] := FDataLinks[I];
      Inc(KeepCnt);
    end;
  SetLength(FDataLinks, KeepCnt);
end;

function TCastleBlueprint.RemoveNode(const ANodeId: String): Boolean;
var
  Idx, I: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  DisconnectNodePins(ANodeId);
  for I := Idx to High(FNodes) - 1 do
    FNodes[I] := FNodes[I + 1];
  SetLength(FNodes, Length(FNodes) - 1);
  MarkDirty;
  Result := True;
end;

function TCastleBlueprint.ToggleNodeBreakpoint(const ANodeId: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  FNodes[Idx].HasBreakpoint := not FNodes[Idx].HasBreakpoint;
  Result := FNodes[Idx].HasBreakpoint;
end;

function TCastleBlueprint.SetNodePosition(const ANodeId: String;
  const AX, AY: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  FNodes[Idx].PosX := AX;
  FNodes[Idx].PosY := AY;
  Result := True;
end;

function TCastleBlueprint.ConnectExec(const AGraph: TBlueprintGraphKind;
  const AFromNodeId: String; const AFromExecPin: Integer;
  const AToNodeId: String; const AToExecPin: Integer): Boolean;
var
  I, N: Integer;
begin
  { Output exec pin in UE5 Kismet is single-outgoing: replace prior outgoing wire }
  for I := 0 to High(FExecLinks) do
    if (FExecLinks[I].Graph = AGraph) and
       SameText(FExecLinks[I].FromNodeId, AFromNodeId) and
       (FExecLinks[I].FromExecPin = AFromExecPin) then
    begin
      FExecLinks[I].ToNodeId := AToNodeId;
      FExecLinks[I].ToExecPin := AToExecPin;
      MarkDirty;
      Exit(True);
    end;

  N := Length(FExecLinks);
  SetLength(FExecLinks, N + 1);
  FExecLinks[N].Graph := AGraph;
  FExecLinks[N].FromNodeId := AFromNodeId;
  FExecLinks[N].FromExecPin := AFromExecPin;
  FExecLinks[N].ToNodeId := AToNodeId;
  FExecLinks[N].ToExecPin := AToExecPin;
  MarkDirty;
  Result := True;
end;

function TCastleBlueprint.ConnectData(const AGraph: TBlueprintGraphKind;
  const AFromNodeId: String; const AFromDataPin: Integer;
  const AToNodeId: String; const AToDataPin: Integer): Boolean;
var
  I, N: Integer;
begin
  { Input data pin has at most one incoming wire }
  for I := 0 to High(FDataLinks) do
    if (FDataLinks[I].Graph = AGraph) and
       SameText(FDataLinks[I].ToNodeId, AToNodeId) and
       (FDataLinks[I].ToDataPin = AToDataPin) then
    begin
      FDataLinks[I].FromNodeId := AFromNodeId;
      FDataLinks[I].FromDataPin := AFromDataPin;
      MarkDirty;
      Exit(True);
    end;

  N := Length(FDataLinks);
  SetLength(FDataLinks, N + 1);
  FDataLinks[N].Graph := AGraph;
  FDataLinks[N].FromNodeId := AFromNodeId;
  FDataLinks[N].FromDataPin := AFromDataPin;
  FDataLinks[N].ToNodeId := AToNodeId;
  FDataLinks[N].ToDataPin := AToDataPin;
  MarkDirty;
  Result := True;
end;

{ Compiler & Validation ------------------------------------------------------ }

function TCastleBlueprint.CompileBlueprint: Boolean;
var
  I, J, FromIdx, ToIdx, VarIdx: Integer;
  FromType, ToType, FromVarT, ToVarT: TBlueprintPinType;
  FoundTargetEvent: Boolean;
  PureColor: array of Byte;

  function HasPureCycleDfs(const NodeIdx: Integer): Boolean;
  var
    L, SrcIdx: Integer;
  begin
    Result := False;
    if not NodeIsPure(FNodes[NodeIdx].Kind) then Exit;
    PureColor[NodeIdx] := 1;
    for L := 0 to High(FDataLinks) do
      if SameText(FDataLinks[L].ToNodeId, FNodes[NodeIdx].NodeId) then
      begin
        SrcIdx := FindNodeIndex(FDataLinks[L].FromNodeId);
        if (SrcIdx >= 0) and NodeIsPure(FNodes[SrcIdx].Kind) then
        begin
          if PureColor[SrcIdx] = 1 then
            Exit(True);
          if (PureColor[SrcIdx] = 0) and HasPureCycleDfs(SrcIdx) then
            Exit(True);
        end;
      end;
    PureColor[NodeIdx] := 2;
  end;

begin
  FCompileErrors.Clear;
  FCompileWarnings.Clear;

  { 1. Validate nodes (variables, latent restrictions in Construction Script, CustomEvent targets) }
  for I := 0 to High(FNodes) do
  begin
    if Trim(FNodes[I].NodeId) = '' then
      FCompileErrors.Add('Blueprint contains a node with an empty NodeId.');

    for J := I + 1 to High(FNodes) do
      if SameText(FNodes[I].NodeId, FNodes[J].NodeId) then
        FCompileErrors.Add(Format('Duplicate NodeId "%s" detected.', [FNodes[I].NodeId]));

    if (FNodes[I].Graph = bgkConstructionScript) and NodeIsLatent(FNodes[I].Kind) then
      FCompileErrors.Add(Format(
        'Node "%s" (%s): Latent actions are forbidden inside Construction Script.',
        [FNodes[I].NodeId, NodeKindTitle(FNodes[I].Kind)]));

    if FNodes[I].Kind in [bnkGetVariable, bnkSetVariable] then
    begin
      if FindVariableIndex(FNodes[I].MemberName) < 0 then
        FCompileErrors.Add(Format(
          'Node "%s" references undeclared Blueprint variable "%s".',
          [FNodes[I].NodeId, FNodes[I].MemberName]));
    end;

    if FNodes[I].Kind = bnkCallCustomEvent then
    begin
      FoundTargetEvent := False;
      for J := 0 to High(FNodes) do
        if (FNodes[J].Kind = bnkCustomEvent) and
           SameText(FNodes[J].MemberName, FNodes[I].MemberName) then
        begin
          FoundTargetEvent := True;
          Break;
        end;
      if not FoundTargetEvent then
        FCompileErrors.Add(Format(
          'Node "%s" calls missing Custom Event "%s".',
          [FNodes[I].NodeId, FNodes[I].MemberName]));
    end;
  end;

  { 2. Validate ExecLinks }
  for I := 0 to High(FExecLinks) do
  begin
    FromIdx := FindNodeIndex(FExecLinks[I].FromNodeId);
    ToIdx := FindNodeIndex(FExecLinks[I].ToNodeId);
    if FromIdx < 0 then
      FCompileErrors.Add(Format('Exec wire references missing source node "%s".', [FExecLinks[I].FromNodeId]))
    else if ToIdx < 0 then
      FCompileErrors.Add(Format('Exec wire references missing target node "%s".', [FExecLinks[I].ToNodeId]))
    else
    begin
      if FNodes[FromIdx].Graph <> FNodes[ToIdx].Graph then
        FCompileErrors.Add(Format('Exec wire "%s -> %s" crosses between Construction Script and EventGraph.',
          [FExecLinks[I].FromNodeId, FExecLinks[I].ToNodeId]));
      if (FExecLinks[I].FromExecPin < 0) or
         (FExecLinks[I].FromExecPin >= NodeExecOutCount(FNodes[FromIdx].Kind)) then
        FCompileErrors.Add(Format('Exec wire from "%s" uses out-of-range output Exec pin %d.',
          [FExecLinks[I].FromNodeId, FExecLinks[I].FromExecPin]));
      if (FExecLinks[I].ToExecPin < 0) or
         (FExecLinks[I].ToExecPin >= NodeExecInCount(FNodes[ToIdx].Kind)) then
        FCompileErrors.Add(Format('Exec wire to "%s" uses out-of-range input Exec pin %d.',
          [FExecLinks[I].ToNodeId, FExecLinks[I].ToExecPin]));
    end;
  end;

  { 3. Validate DataLinks & Type Compatibility }
  for I := 0 to High(FDataLinks) do
  begin
    FromIdx := FindNodeIndex(FDataLinks[I].FromNodeId);
    ToIdx := FindNodeIndex(FDataLinks[I].ToNodeId);
    if FromIdx < 0 then
      FCompileErrors.Add(Format('Data wire references missing source node "%s".', [FDataLinks[I].FromNodeId]))
    else if ToIdx < 0 then
      FCompileErrors.Add(Format('Data wire references missing target node "%s".', [FDataLinks[I].ToNodeId]))
    else
    begin
      FromVarT := bptFloat;
      VarIdx := FindVariableIndex(FNodes[FromIdx].MemberName);
      if VarIdx >= 0 then FromVarT := FVariables[VarIdx].VarType;

      ToVarT := bptFloat;
      VarIdx := FindVariableIndex(FNodes[ToIdx].MemberName);
      if VarIdx >= 0 then ToVarT := FVariables[VarIdx].VarType;

      if (FDataLinks[I].FromDataPin < 0) or
         (FDataLinks[I].FromDataPin >= NodeDataOutCount(FNodes[FromIdx].Kind)) then
        FCompileErrors.Add(Format('Data wire from "%s" uses invalid output Data pin %d.',
          [FDataLinks[I].FromNodeId, FDataLinks[I].FromDataPin]))
      else if (FDataLinks[I].ToDataPin < 0) or
              (FDataLinks[I].ToDataPin >= NodeDataInCount(FNodes[ToIdx].Kind)) then
        FCompileErrors.Add(Format('Data wire to "%s" uses invalid input Data pin %d.',
          [FDataLinks[I].ToNodeId, FDataLinks[I].ToDataPin]))
      else
      begin
        FromType := NodeDataOutType(FNodes[FromIdx].Kind, FDataLinks[I].FromDataPin, FromVarT);
        ToType := NodeDataInType(FNodes[ToIdx].Kind, FDataLinks[I].ToDataPin, ToVarT);
        if not PinTypesCompatible(FromType, ToType) then
          FCompileErrors.Add(Format(
            'Type mismatch on wire "%s.%s (%s) -> %s.%s (%s)".',
            [FNodes[FromIdx].NodeId, NodeDataOutName(FNodes[FromIdx].Kind, FDataLinks[I].FromDataPin),
             PinTypeName(FromType),
             FNodes[ToIdx].NodeId, NodeDataInName(FNodes[ToIdx].Kind, FDataLinks[I].ToDataPin),
             PinTypeName(ToType)]));
      end;
    end;
  end;

  { 4. Check pure data evaluation cycles }
  SetLength(PureColor, Length(FNodes));
  for I := 0 to High(PureColor) do PureColor[I] := 0;
  for I := 0 to High(FNodes) do
    if NodeIsPure(FNodes[I].Kind) and (PureColor[I] = 0) then
      if HasPureCycleDfs(I) then
        FCompileErrors.Add(Format('Pure data evaluation cycle detected involving node "%s".',
          [FNodes[I].NodeId]));

  Result := FCompileErrors.Count = 0;
  if Result then
  begin
    FCompileStatus := bcsUpToDate;
    ResetRuntimeState;
  end else
    FCompileStatus := bcsError;
end;

procedure TCastleBlueprint.ResetRuntimeState;
var
  I: Integer;
begin
  ResetVariablesToDefaults;
  for I := 0 to High(FNodes) do
  begin
    FNodes[I].RuntimeDoOnceConsumed := FNodes[I].DefaultBool0;
    FNodes[I].RuntimeFlipFlopNextIsA := True;
    FNodes[I].RuntimeGateInitialized := False;
    FNodes[I].RuntimeGateIsOpen := not FNodes[I].DefaultBool0;
  end;
  FLatentTasks := nil;
  FIsPausedAtBreakpoint := False;
  FPausedNodeId := '';
  FSkipBreakpointOnceNodeId := '';
  FHaltedByInfiniteLoopGuard := False;
  FTotalExecutedSteps := 0;
end;

{ Construction Script Container ---------------------------------------------- }

procedure TCastleBlueprint.ClearConstructionSpawnedChildren;
begin
  if FConstructionContainer <> nil then
    FreeAndNil(FConstructionContainer);
  FConstructionSpawnCount := 0;
end;

procedure TCastleBlueprint.EnsureConstructionContainer;
begin
  if FConstructionContainer = nil then
  begin
    FConstructionContainer := TCastleTransform.Create(nil);
    FConstructionContainer.SetTransient;
    FConstructionContainer.Name := 'BP_ConstructionComponents';
    Add(FConstructionContainer);
  end;
end;

{ VM Evaluation & Execution -------------------------------------------------- }

function TCastleBlueprint.EvaluateNodeDataOutput(const ANodeIdx, AOutPin: Integer;
  var VisitedPureMask: array of Byte): TBlueprintValue;
var
  N: TBlueprintNode;
  V0, V1, V2: TBlueprintValue;
  VarIdx: Integer;
begin
  Result := Default(TBlueprintValue);
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then Exit;
  N := FNodes[ANodeIdx];

  if NodeIsPure(N.Kind) then
  begin
    if VisitedPureMask[ANodeIdx] <> 0 then Exit;
    VisitedPureMask[ANodeIdx] := 1;
  end;

  case N.Kind of
    bnkEventTick:
      Result := TBlueprintValue.FromFloat(FLastTickDeltaSeconds);
    bnkEventBeginOverlap:
      Result := TBlueprintValue.FromString(FLastOverlapActorName);
    bnkForLoop:
      Result := TBlueprintValue.FromInt(FLastForLoopIndex);
    bnkFlipFlop:
      Result := TBlueprintValue.FromBool(not N.RuntimeFlipFlopNextIsA);
    bnkTimeline:
      Result := TBlueprintValue.FromFloat(FLastTimelineAlpha);
    bnkGetVariable, bnkSetVariable:
      begin
        VarIdx := FindVariableIndex(N.MemberName);
        if VarIdx >= 0 then
          Result := FVariables[VarIdx].CurrentValue;
      end;
    bnkAddFloat:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, VisitedPureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, VisitedPureMask);
        Result := TBlueprintValue.FromFloat(V0.FloatVal + V1.FloatVal);
      end;
    bnkMultiplyFloat:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, VisitedPureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, VisitedPureMask);
        Result := TBlueprintValue.FromFloat(V0.FloatVal * V1.FloatVal);
      end;
    bnkGreaterFloat:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, VisitedPureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, VisitedPureMask);
        Result := TBlueprintValue.FromBool(V0.FloatVal > V1.FloatVal);
      end;
    bnkMakeVector:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, VisitedPureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, VisitedPureMask);
        V2 := EvaluateDataInput(ANodeIdx, 2, VisitedPureMask);
        Result := TBlueprintValue.FromVec3(Vector3(V0.FloatVal, V1.FloatVal, V2.FloatVal));
      end;
    bnkLerpVector:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, VisitedPureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, VisitedPureMask);
        V2 := EvaluateDataInput(ANodeIdx, 2, VisitedPureMask);
        Result := TBlueprintValue.FromVec3(Lerp(EnsureRange(V2.FloatVal, 0.0, 1.0), V0.VecVal, V1.VecVal));
      end;
  else
    Result := TBlueprintValue.FromObject(Self);
  end;

  if NodeIsPure(N.Kind) then
    VisitedPureMask[ANodeIdx] := 0;

  FWatchTrace.Add(Format('%s.%s = %s',
    [N.NodeId, NodeDataOutName(N.Kind, AOutPin), Result.AsText]));
end;

function TCastleBlueprint.EvaluateDataInput(const ANodeIdx, AInPin: Integer;
  var VisitedPureMask: array of Byte): TBlueprintValue;
var
  N: TBlueprintNode;
  I, SrcIdx, VarIdx: Integer;
  ExpectedType, VarT: TBlueprintPinType;
  RawVal: TBlueprintValue;
begin
  N := FNodes[ANodeIdx];
  VarT := bptFloat;
  VarIdx := FindVariableIndex(N.MemberName);
  if VarIdx >= 0 then VarT := FVariables[VarIdx].VarType;
  ExpectedType := NodeDataInType(N.Kind, AInPin, VarT);

  for I := 0 to High(FDataLinks) do
    if (FDataLinks[I].Graph = N.Graph) and
       SameText(FDataLinks[I].ToNodeId, N.NodeId) and
       (FDataLinks[I].ToDataPin = AInPin) then
    begin
      SrcIdx := FindNodeIndex(FDataLinks[I].FromNodeId);
      if SrcIdx >= 0 then
      begin
        RawVal := EvaluateNodeDataOutput(SrcIdx, FDataLinks[I].FromDataPin, VisitedPureMask);
        { Auto-coercions }
        if (RawVal.PinType = bptInt) and (ExpectedType = bptFloat) then
          Exit(TBlueprintValue.FromFloat(RawVal.IntVal));
        if (RawVal.PinType <> bptString) and (ExpectedType = bptString) then
          Exit(TBlueprintValue.FromString(RawVal.AsText));
        Exit(RawVal);
      end;
    end;

  { Literal fallback on node }
  case N.Kind of
    bnkBranch, bnkDoOnce, bnkGate:
      Result := TBlueprintValue.FromBool(N.DefaultBool0);
    bnkForLoop:
      if AInPin = 0 then
        Result := TBlueprintValue.FromInt(N.DefaultInt0)
      else
        Result := TBlueprintValue.FromInt(N.DefaultInt1);
    bnkDelay, bnkTimeline, bnkAddLocalRotationYaw:
      Result := TBlueprintValue.FromFloat(N.DefaultFloat0);
    bnkAddFloat, bnkMultiplyFloat, bnkGreaterFloat:
      if AInPin = 0 then
        Result := TBlueprintValue.FromFloat(N.DefaultFloat0)
      else
        Result := TBlueprintValue.FromFloat(N.DefaultFloat1);
    bnkMakeVector:
      case AInPin of
        0: Result := TBlueprintValue.FromFloat(N.DefaultFloat0);
        1: Result := TBlueprintValue.FromFloat(N.DefaultFloat1);
      else
        Result := TBlueprintValue.FromFloat(N.DefaultFloat2);
      end;
    bnkLerpVector:
      case AInPin of
        0: Result := TBlueprintValue.FromVec3(N.DefaultVec0);
        1: Result := TBlueprintValue.FromVec3(N.DefaultVec1);
      else
        Result := TBlueprintValue.FromFloat(N.DefaultFloat0);
      end;
    bnkSpawnProceduralBox:
      case AInPin of
        0: Result := TBlueprintValue.FromVec3(N.DefaultVec0);
        1: Result := TBlueprintValue.FromVec3(N.DefaultVec1);
      else
        Result := TBlueprintValue.FromVec3(Vector3(N.DefaultFloat0, N.DefaultFloat1, N.DefaultFloat2));
      end;
    bnkSetRelativeLocation, bnkAddLocalOffset:
      Result := TBlueprintValue.FromVec3(N.DefaultVec0);
    bnkPrintString:
      Result := TBlueprintValue.FromString(N.DefaultStr0);
    bnkSetVariable:
      case ExpectedType of
        bptBool:   Result := TBlueprintValue.FromBool(N.DefaultBool0);
        bptInt:    Result := TBlueprintValue.FromInt(N.DefaultInt0);
        bptFloat:  Result := TBlueprintValue.FromFloat(N.DefaultFloat0);
        bptString: Result := TBlueprintValue.FromString(N.DefaultStr0);
        bptVec3:   Result := TBlueprintValue.FromVec3(N.DefaultVec0);
      else
        Result := TBlueprintValue.FromObject(Self);
      end;
  else
    Result := TBlueprintValue.FromFloat(0.0);
  end;
end;

procedure TCastleBlueprint.UpsertLatentTask(const ANodeId: String;
  const AKind: TBlueprintNodeKind; const ADurationSec: Single;
  const AReverse: Boolean);
var
  I, N: Integer;
begin
  for I := 0 to High(FLatentTasks) do
    if SameText(FLatentTasks[I].NodeId, ANodeId) then
    begin
      FLatentTasks[I].Active := True;
      FLatentTasks[I].Kind := AKind;
      FLatentTasks[I].DurationSec := Max(0.001, ADurationSec);
      if AReverse then
        FLatentTasks[I].ElapsedSec := FLatentTasks[I].DurationSec
      else
        FLatentTasks[I].ElapsedSec := 0.0;
      FLatentTasks[I].ReverseDirection := AReverse;
      Exit;
    end;

  N := Length(FLatentTasks);
  SetLength(FLatentTasks, N + 1);
  FLatentTasks[N].Active := True;
  FLatentTasks[N].NodeId := ANodeId;
  FLatentTasks[N].Kind := AKind;
  FLatentTasks[N].DurationSec := Max(0.001, ADurationSec);
  if AReverse then
    FLatentTasks[N].ElapsedSec := FLatentTasks[N].DurationSec
  else
    FLatentTasks[N].ElapsedSec := 0.0;
  FLatentTasks[N].ReverseDirection := AReverse;
end;

procedure TCastleBlueprint.FollowExecOut(const AGraph: TBlueprintGraphKind;
  const AFromNodeIdx, AFromExecOutPin: Integer; var StepBudget: Integer);
var
  I, TargetIdx: Integer;
begin
  if FIsPausedAtBreakpoint or FHaltedByInfiniteLoopGuard then Exit;
  for I := 0 to High(FExecLinks) do
    if (FExecLinks[I].Graph = AGraph) and
       SameText(FExecLinks[I].FromNodeId, FNodes[AFromNodeIdx].NodeId) and
       (FExecLinks[I].FromExecPin = AFromExecOutPin) then
    begin
      TargetIdx := FindNodeIndex(FExecLinks[I].ToNodeId);
      if TargetIdx >= 0 then
      begin
        FActiveExecTrace.Add(Format('%s:%d->%s:%d',
          [FNodes[AFromNodeIdx].NodeId, AFromExecOutPin,
           FNodes[TargetIdx].NodeId, FExecLinks[I].ToExecPin]));
        ExecuteFromNode(AGraph, TargetIdx, FExecLinks[I].ToExecPin, StepBudget);
      end;
      Exit;
    end;
end;

procedure TCastleBlueprint.ExecuteFromNode(const AGraph: TBlueprintGraphKind;
  const ANodeIdx, AExecInPin: Integer; var StepBudget: Integer);
var
  PureMask: array of Byte;
  V0, V1, V2: TBlueprintValue;
  LoopIdx, FirstI, LastI, VarIdx, J: Integer;
  SpawnBox: TCastleBox;
begin
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then Exit;
  if FIsPausedAtBreakpoint or FHaltedByInfiniteLoopGuard then Exit;

  { Breakpoint check }
  if FBreakpointsEnabled and FNodes[ANodeIdx].HasBreakpoint and
     (not SameText(FSkipBreakpointOnceNodeId, FNodes[ANodeIdx].NodeId)) then
  begin
    FIsPausedAtBreakpoint := True;
    FPausedGraph := AGraph;
    FPausedNodeId := FNodes[ANodeIdx].NodeId;
    FPausedExecInPin := AExecInPin;
    FWatchTrace.Add(Format('[BREAKPOINT PAUSED at %s (%s)]',
      [FNodes[ANodeIdx].NodeId, NodeKindTitle(FNodes[ANodeIdx].Kind)]));
    Exit;
  end;
  if SameText(FSkipBreakpointOnceNodeId, FNodes[ANodeIdx].NodeId) then
    FSkipBreakpointOnceNodeId := '';

  { Infinite loop guard }
  Dec(StepBudget);
  Inc(FTotalExecutedSteps);
  if StepBudget < 0 then
  begin
    FHaltedByInfiniteLoopGuard := True;
    FPrintLog.Add(Format('[InfiniteLoopGuard] Halted runaway execution at node "%s" (> %d steps).',
      [FNodes[ANodeIdx].NodeId, FMaxExecStepsPerCall]));
    Exit;
  end;

  SetLength(PureMask, Length(FNodes));
  for J := 0 to High(PureMask) do PureMask[J] := 0;

  case FNodes[ANodeIdx].Kind of
    bnkConstructionEntry, bnkEventBeginPlay, bnkEventTick,
    bnkEventBeginOverlap, bnkCustomEvent:
      FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);

    bnkBranch:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        FWatchTrace.Add(Format('%s.Condition = %s', [FNodes[ANodeIdx].NodeId, V0.AsText]));
        if V0.BoolVal then
          FollowExecOut(AGraph, ANodeIdx, 0, StepBudget)
        else
          FollowExecOut(AGraph, ANodeIdx, 1, StepBudget);
      end;

    bnkSequence:
      begin
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
        FollowExecOut(AGraph, ANodeIdx, 1, StepBudget);
        FollowExecOut(AGraph, ANodeIdx, 2, StepBudget);
      end;

    bnkForLoop:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, PureMask);
        FirstI := V0.IntVal;
        LastI := V1.IntVal;
        for LoopIdx := FirstI to LastI do
        begin
          FLastForLoopIndex := LoopIdx;
          FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
          if FIsPausedAtBreakpoint or FHaltedByInfiniteLoopGuard then Exit;
        end;
        FollowExecOut(AGraph, ANodeIdx, 1, StepBudget);
      end;

    bnkDoOnce:
      begin
        if AExecInPin = 1 then
          FNodes[ANodeIdx].RuntimeDoOnceConsumed := False
        else if not FNodes[ANodeIdx].RuntimeDoOnceConsumed then
        begin
          FNodes[ANodeIdx].RuntimeDoOnceConsumed := True;
          FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
        end;
      end;

    bnkFlipFlop:
      begin
        if FNodes[ANodeIdx].RuntimeFlipFlopNextIsA then
        begin
          FNodes[ANodeIdx].RuntimeFlipFlopNextIsA := False;
          FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
        end else
        begin
          FNodes[ANodeIdx].RuntimeFlipFlopNextIsA := True;
          FollowExecOut(AGraph, ANodeIdx, 1, StepBudget);
        end;
      end;

    bnkGate:
      begin
        if not FNodes[ANodeIdx].RuntimeGateInitialized then
        begin
          V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
          FNodes[ANodeIdx].RuntimeGateIsOpen := not V0.BoolVal;
          FNodes[ANodeIdx].RuntimeGateInitialized := True;
        end;
        case AExecInPin of
          1: FNodes[ANodeIdx].RuntimeGateIsOpen := True;
          2: FNodes[ANodeIdx].RuntimeGateIsOpen := False;
          3: FNodes[ANodeIdx].RuntimeGateIsOpen := not FNodes[ANodeIdx].RuntimeGateIsOpen;
        else
          if FNodes[ANodeIdx].RuntimeGateIsOpen then
            FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
        end;
      end;

    bnkDelay:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        UpsertLatentTask(FNodes[ANodeIdx].NodeId, bnkDelay, V0.FloatVal, False);
      end;

    bnkTimeline:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        UpsertLatentTask(FNodes[ANodeIdx].NodeId, bnkTimeline, V0.FloatVal, AExecInPin = 1);
      end;

    bnkSetVariable:
      begin
        VarIdx := FindVariableIndex(FNodes[ANodeIdx].MemberName);
        if VarIdx >= 0 then
        begin
          V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
          V0.PinType := FVariables[VarIdx].VarType;
          FVariables[VarIdx].CurrentValue := V0;
          FWatchTrace.Add(Format('Set %s := %s',
            [FVariables[VarIdx].VarName, V0.AsText]));
        end;
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;

    bnkSpawnProceduralBox:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        V1 := EvaluateDataInput(ANodeIdx, 1, PureMask);
        V2 := EvaluateDataInput(ANodeIdx, 2, PureMask);
        EnsureConstructionContainer;
        SpawnBox := TCastleBox.Create(FConstructionContainer);
        SpawnBox.SetTransient;
        Inc(FConstructionSpawnCount);
        SpawnBox.Name := Format('BP_Box_%d', [FConstructionSpawnCount]);
        SpawnBox.Translation := V0.VecVal;
        SpawnBox.Size := Vector3(
          Max(0.05, V1.VecVal.X),
          Max(0.05, V1.VecVal.Y),
          Max(0.05, V1.VecVal.Z));
        SpawnBox.Color := Vector4(
          EnsureRange(V2.VecVal.X, 0.0, 1.0),
          EnsureRange(V2.VecVal.Y, 0.0, 1.0),
          EnsureRange(V2.VecVal.Z, 0.0, 1.0), 1.0);
        FConstructionContainer.Add(SpawnBox);
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;

    bnkSetRelativeLocation:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        Translation := V0.VecVal;
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;

    bnkAddLocalOffset:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        Translation := Translation + V0.VecVal;
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;

    bnkAddLocalRotationYaw:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        FYawDegreesAccum := FYawDegreesAccum + V0.FloatVal;
        Rotation := Vector4(0, 1, 0, DegToRad(FYawDegreesAccum));
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;

    bnkPrintString:
      begin
        V0 := EvaluateDataInput(ANodeIdx, 0, PureMask);
        FPrintLog.Add(V0.StrVal);
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;

    bnkCallCustomEvent:
      begin
        for J := 0 to High(FNodes) do
          if (FNodes[J].Graph = AGraph) and
             (FNodes[J].Kind = bnkCustomEvent) and
             SameText(FNodes[J].MemberName, FNodes[ANodeIdx].MemberName) then
          begin
            ExecuteFromNode(AGraph, J, 0, StepBudget);
            Break;
          end;
        FollowExecOut(AGraph, ANodeIdx, 0, StepBudget);
      end;
  end;
end;

function TCastleBlueprint.RunConstructionScript: Boolean;
var
  I, Budget: Integer;
begin
  if (FCompileStatus <> bcsUpToDate) and (not CompileBlueprint) then
    Exit(False);

  ClearConstructionSpawnedChildren;
  ResetVariablesToDefaults;
  FActiveExecTrace.Clear;
  FWatchTrace.Clear;
  FHaltedByInfiniteLoopGuard := False;

  Budget := FMaxExecStepsPerCall;
  for I := 0 to High(FNodes) do
    if (FNodes[I].Graph = bgkConstructionScript) and
       (FNodes[I].Kind = bnkConstructionEntry) then
      ExecuteFromNode(bgkConstructionScript, I, 0, Budget);

  Result := not FHaltedByInfiniteLoopGuard;
end;

function TCastleBlueprint.ExecuteBeginPlay: Boolean;
var
  I, Budget: Integer;
begin
  if (FCompileStatus <> bcsUpToDate) and (not CompileBlueprint) then
    Exit(False);
  if FIsPausedAtBreakpoint then Exit(False);

  FActiveExecTrace.Clear;
  Budget := FMaxExecStepsPerCall;
  for I := 0 to High(FNodes) do
    if (FNodes[I].Graph = bgkEventGraph) and
       (FNodes[I].Kind = bnkEventBeginPlay) then
      ExecuteFromNode(bgkEventGraph, I, 0, Budget);

  Result := not FHaltedByInfiniteLoopGuard;
end;

function TCastleBlueprint.StepBlueprintTick(const ADeltaSeconds: Single): Boolean;
var
  I, NodeIdx, Budget: Integer;
  RawT, SmoothAlpha: Single;
  FinishedNow: Boolean;
begin
  if (FCompileStatus <> bcsUpToDate) and (not CompileBlueprint) then
    Exit(False);
  if FIsPausedAtBreakpoint then Exit(False);

  FLastTickDeltaSeconds := Max(0.0, ADeltaSeconds);
  FActiveExecTrace.Clear;
  Budget := FMaxExecStepsPerCall;

  { 1. Advance active Latent Tasks (Delay & Timeline) }
  for I := 0 to High(FLatentTasks) do
    if FLatentTasks[I].Active then
    begin
      NodeIdx := FindNodeIndex(FLatentTasks[I].NodeId);
      if NodeIdx < 0 then
      begin
        FLatentTasks[I].Active := False;
        Continue;
      end;

      case FLatentTasks[I].Kind of
        bnkDelay:
          begin
            FLatentTasks[I].ElapsedSec := FLatentTasks[I].ElapsedSec + FLastTickDeltaSeconds;
            if FLatentTasks[I].ElapsedSec + 1e-5 >= FLatentTasks[I].DurationSec then
            begin
              FLatentTasks[I].Active := False;
              FollowExecOut(bgkEventGraph, NodeIdx, 0, Budget);
            end;
          end;

        bnkTimeline:
          begin
            FinishedNow := False;
            if FLatentTasks[I].ReverseDirection then
            begin
              FLatentTasks[I].ElapsedSec := FLatentTasks[I].ElapsedSec - FLastTickDeltaSeconds;
              if FLatentTasks[I].ElapsedSec <= 1e-5 then
              begin
                FLatentTasks[I].ElapsedSec := 0.0;
                FinishedNow := True;
              end;
            end else
            begin
              FLatentTasks[I].ElapsedSec := FLatentTasks[I].ElapsedSec + FLastTickDeltaSeconds;
              if FLatentTasks[I].ElapsedSec + 1e-5 >= FLatentTasks[I].DurationSec then
              begin
                FLatentTasks[I].ElapsedSec := FLatentTasks[I].DurationSec;
                FinishedNow := True;
              end;
            end;

            RawT := EnsureRange(FLatentTasks[I].ElapsedSec / FLatentTasks[I].DurationSec, 0.0, 1.0);
            { Cubic Hermite S-curve 3t^2 - 2t^3 matching UE5 Timeline Float Track auto-tangents }
            SmoothAlpha := RawT * RawT * (3.0 - 2.0 * RawT);
            FLastTimelineAlpha := SmoothAlpha;
            FollowExecOut(bgkEventGraph, NodeIdx, 0, Budget);
            if FinishedNow then
            begin
              FLatentTasks[I].Active := False;
              FollowExecOut(bgkEventGraph, NodeIdx, 1, Budget);
            end;
          end;
      end;
    end;

  { 2. Dispatch Event Tick }
  for I := 0 to High(FNodes) do
    if (FNodes[I].Graph = bgkEventGraph) and
       (FNodes[I].Kind = bnkEventTick) then
      ExecuteFromNode(bgkEventGraph, I, 0, Budget);

  Result := not FHaltedByInfiniteLoopGuard;
end;

function TCastleBlueprint.ExecuteActorBeginOverlap(const AOtherActorName: String): Boolean;
var
  I, Budget: Integer;
begin
  if (FCompileStatus <> bcsUpToDate) and (not CompileBlueprint) then
    Exit(False);
  if FIsPausedAtBreakpoint then Exit(False);

  FLastOverlapActorName := AOtherActorName;
  FActiveExecTrace.Clear;
  Budget := FMaxExecStepsPerCall;
  for I := 0 to High(FNodes) do
    if (FNodes[I].Graph = bgkEventGraph) and
       (FNodes[I].Kind = bnkEventBeginOverlap) then
      ExecuteFromNode(bgkEventGraph, I, 0, Budget);

  Result := not FHaltedByInfiniteLoopGuard;
end;

function TCastleBlueprint.ExecuteCustomEvent(const AEventName: String): Boolean;
var
  I, Budget: Integer;
begin
  if (FCompileStatus <> bcsUpToDate) and (not CompileBlueprint) then
    Exit(False);
  if FIsPausedAtBreakpoint then Exit(False);

  FActiveExecTrace.Clear;
  Budget := FMaxExecStepsPerCall;
  for I := 0 to High(FNodes) do
    if (FNodes[I].Graph = bgkEventGraph) and
       (FNodes[I].Kind = bnkCustomEvent) and
       SameText(FNodes[I].MemberName, AEventName) then
      ExecuteFromNode(bgkEventGraph, I, 0, Budget);

  Result := not FHaltedByInfiniteLoopGuard;
end;

function TCastleBlueprint.ResumeFromBreakpoint: Boolean;
var
  NodeIdx, Budget: Integer;
  ResumeGraph: TBlueprintGraphKind;
  ResumePin: Integer;
begin
  if not FIsPausedAtBreakpoint then Exit(False);
  NodeIdx := FindNodeIndex(FPausedNodeId);
  ResumeGraph := FPausedGraph;
  ResumePin := FPausedExecInPin;
  FSkipBreakpointOnceNodeId := FPausedNodeId;
  FIsPausedAtBreakpoint := False;
  FPausedNodeId := '';

  if NodeIdx < 0 then Exit(False);
  Budget := FMaxExecStepsPerCall;
  ExecuteFromNode(ResumeGraph, NodeIdx, ResumePin, Budget);
  Result := not FHaltedByInfiniteLoopGuard;
end;

{ Built-In UE5 Blueprint Presets --------------------------------------------- }

procedure TCastleBlueprint.ApplyPreset(const APreset: TBlueprintPreset);
var
  N: TBlueprintNode;
begin
  FPreset := APreset;
  if APreset = bppCustom then Exit;

  ClearAllGraphs;
  FPreset := APreset;

  case APreset of
    bppPillarRowConstructionAndSpinPickup:
      begin
        FBlueprintClassName := 'BP_ColonnadeAndPickup';
        AddOrUpdateVariable('PillarCount', bptInt, TBlueprintValue.FromInt(4), True, 'Construction');
        AddOrUpdateVariable('PillarSpacing', bptFloat, TBlueprintValue.FromFloat(2.5), True, 'Construction');
        AddOrUpdateVariable('SpinSpeedDeg', bptFloat, TBlueprintValue.FromFloat(90.0), True, 'Motion');

        { Construction Script: Entry -> ForLoop(0 .. PillarCount - 1) -> MakeVector(Index * Spacing, 1.0, 0) -> SpawnBox }
        AddOrUpdateNode(MakeDefaultNode('CS_Entry', bgkConstructionScript, bnkConstructionEntry, 40, 80));
        AddOrUpdateNode(MakeDefaultNode('CS_GetCount', bgkConstructionScript, bnkGetVariable, 40, 210, 'PillarCount'));
        N := MakeDefaultNode('CS_LastIdx', bgkConstructionScript, bnkAddFloat, 210, 210);
        N.DefaultFloat1 := -1.0;
        AddOrUpdateNode(N);
        N := MakeDefaultNode('CS_Loop', bgkConstructionScript, bnkForLoop, 250, 80);
        N.DefaultInt0 := 0;
        AddOrUpdateNode(N);
        AddOrUpdateNode(MakeDefaultNode('CS_GetSpace', bgkConstructionScript, bnkGetVariable, 250, 290, 'PillarSpacing'));
        AddOrUpdateNode(MakeDefaultNode('CS_MulX', bgkConstructionScript, bnkMultiplyFloat, 450, 230));
        N := MakeDefaultNode('CS_PosVec', bgkConstructionScript, bnkMakeVector, 620, 220);
        N.DefaultFloat1 := 1.0;
        N.DefaultFloat2 := 0.0;
        AddOrUpdateNode(N);
        N := MakeDefaultNode('CS_SpawnBox', bgkConstructionScript, bnkSpawnProceduralBox, 520, 75);
        N.DefaultVec1 := Vector3(0.7, 2.0, 0.7);
        N.DefaultFloat0 := 0.85;
        N.DefaultFloat1 := 0.78;
        N.DefaultFloat2 := 0.62;
        AddOrUpdateNode(N);

        ConnectData(bgkConstructionScript, 'CS_GetCount', 0, 'CS_LastIdx', 0);
        { Connect PillarCount - 1 via DefaultInt1 override or direct ForLoop LastIndex:
          let's wire CS_GetCount directly into ForLoop LastIndex as 1..PillarCount for crisp integer typing! }
        DisconnectNodePins('CS_LastIdx');
        RemoveNode('CS_LastIdx');
        N := FNodes[FindNodeIndex('CS_Loop')];
        N.DefaultInt0 := 1;
        AddOrUpdateNode(N);
        ConnectData(bgkConstructionScript, 'CS_GetCount', 0, 'CS_Loop', 1);
        ConnectExec(bgkConstructionScript, 'CS_Entry', 0, 'CS_Loop', 0);
        ConnectExec(bgkConstructionScript, 'CS_Loop', 0, 'CS_SpawnBox', 0);
        ConnectData(bgkConstructionScript, 'CS_Loop', 0, 'CS_MulX', 0);
        ConnectData(bgkConstructionScript, 'CS_GetSpace', 0, 'CS_MulX', 1);
        ConnectData(bgkConstructionScript, 'CS_MulX', 0, 'CS_PosVec', 0);
        ConnectData(bgkConstructionScript, 'CS_PosVec', 0, 'CS_SpawnBox', 0);

        { EventGraph: BeginPlay -> PrintString; EventTick -> SpinSpeedDeg * DeltaSeconds -> AddLocalRotationYaw }
        AddOrUpdateNode(MakeDefaultNode('EG_Begin', bgkEventGraph, bnkEventBeginPlay, 40, 60));
        N := MakeDefaultNode('EG_Hello', bgkEventGraph, bnkPrintString, 260, 60);
        N.DefaultStr0 := 'BP_ColonnadeAndPickup BeginPlay Ready';
        AddOrUpdateNode(N);
        ConnectExec(bgkEventGraph, 'EG_Begin', 0, 'EG_Hello', 0);

        AddOrUpdateNode(MakeDefaultNode('EG_Tick', bgkEventGraph, bnkEventTick, 40, 200));
        AddOrUpdateNode(MakeDefaultNode('EG_GetSpin', bgkEventGraph, bnkGetVariable, 40, 320, 'SpinSpeedDeg'));
        AddOrUpdateNode(MakeDefaultNode('EG_MulYaw', bgkEventGraph, bnkMultiplyFloat, 250, 260));
        AddOrUpdateNode(MakeDefaultNode('EG_RotYaw', bgkEventGraph, bnkAddLocalRotationYaw, 470, 200));
        ConnectExec(bgkEventGraph, 'EG_Tick', 0, 'EG_RotYaw', 0);
        ConnectData(bgkEventGraph, 'EG_Tick', 0, 'EG_MulYaw', 0);
        ConnectData(bgkEventGraph, 'EG_GetSpin', 0, 'EG_MulYaw', 1);
        ConnectData(bgkEventGraph, 'EG_MulYaw', 0, 'EG_RotYaw', 0);
      end;

    bppSlidingDoorTimelineAndGate:
      begin
        FBlueprintClassName := 'BP_SlidingDoorTimeline';
        AddOrUpdateVariable('ClosedPos', bptVec3, TBlueprintValue.FromVec3(Vector3(0, 0, 0)), True, 'Door');
        AddOrUpdateVariable('OpenPos', bptVec3, TBlueprintValue.FromVec3(Vector3(0, 3.0, 0)), True, 'Door');
        AddOrUpdateVariable('DoorDuration', bptFloat, TBlueprintValue.FromFloat(1.0), True, 'Door');

        AddOrUpdateNode(MakeDefaultNode('EG_Overlap', bgkEventGraph, bnkEventBeginOverlap, 40, 80));
        N := MakeDefaultNode('EG_Gate', bgkEventGraph, bnkGate, 250, 80);
        N.DefaultBool0 := False; { StartClosed = False -> Open }
        AddOrUpdateNode(N);
        AddOrUpdateNode(MakeDefaultNode('EG_FlipFlop', bgkEventGraph, bnkFlipFlop, 430, 80));
        AddOrUpdateNode(MakeDefaultNode('EG_GetDur', bgkEventGraph, bnkGetVariable, 430, 230, 'DoorDuration'));
        AddOrUpdateNode(MakeDefaultNode('EG_Timeline', bgkEventGraph, bnkTimeline, 620, 80));
        AddOrUpdateNode(MakeDefaultNode('EG_GetClosed', bgkEventGraph, bnkGetVariable, 620, 240, 'ClosedPos'));
        AddOrUpdateNode(MakeDefaultNode('EG_GetOpen', bgkEventGraph, bnkGetVariable, 620, 320, 'OpenPos'));
        AddOrUpdateNode(MakeDefaultNode('EG_LerpPos', bgkEventGraph, bnkLerpVector, 830, 230));
        AddOrUpdateNode(MakeDefaultNode('EG_SetLoc', bgkEventGraph, bnkSetRelativeLocation, 1020, 80));
        N := MakeDefaultNode('EG_DonePrint', bgkEventGraph, bnkPrintString, 1020, 200);
        N.DefaultStr0 := 'Door Timeline Finished';
        AddOrUpdateNode(N);

        ConnectExec(bgkEventGraph, 'EG_Overlap', 0, 'EG_Gate', 0);
        ConnectExec(bgkEventGraph, 'EG_Gate', 0, 'EG_FlipFlop', 0);
        ConnectExec(bgkEventGraph, 'EG_FlipFlop', 0, 'EG_Timeline', 0); { A -> PlayFromStart }
        ConnectExec(bgkEventGraph, 'EG_FlipFlop', 1, 'EG_Timeline', 1); { B -> ReverseFromEnd }
        ConnectData(bgkEventGraph, 'EG_GetDur', 0, 'EG_Timeline', 0);
        ConnectExec(bgkEventGraph, 'EG_Timeline', 0, 'EG_SetLoc', 0);
        ConnectExec(bgkEventGraph, 'EG_Timeline', 1, 'EG_DonePrint', 0);
        ConnectData(bgkEventGraph, 'EG_GetClosed', 0, 'EG_LerpPos', 0);
        ConnectData(bgkEventGraph, 'EG_GetOpen', 0, 'EG_LerpPos', 1);
        ConnectData(bgkEventGraph, 'EG_Timeline', 0, 'EG_LerpPos', 2);
        ConnectData(bgkEventGraph, 'EG_LerpPos', 0, 'EG_SetLoc', 0);
      end;

    bppPatrolBranchAndLatentDelay:
      begin
        FBlueprintClassName := 'BP_WarmupAndBranch';
        AddOrUpdateVariable('IsArmed', bptBool, TBlueprintValue.FromBool(False), True, 'State');
        AddOrUpdateVariable('WarmupSec', bptFloat, TBlueprintValue.FromFloat(0.5), True, 'State');

        AddOrUpdateNode(MakeDefaultNode('EG_Begin', bgkEventGraph, bnkEventBeginPlay, 40, 80));
        AddOrUpdateNode(MakeDefaultNode('EG_Once', bgkEventGraph, bnkDoOnce, 230, 80));
        AddOrUpdateNode(MakeDefaultNode('EG_GetWarm', bgkEventGraph, bnkGetVariable, 230, 210, 'WarmupSec'));
        AddOrUpdateNode(MakeDefaultNode('EG_Delay', bgkEventGraph, bnkDelay, 430, 80));
        N := MakeDefaultNode('EG_SetArmed', bgkEventGraph, bnkSetVariable, 620, 80, 'IsArmed');
        N.DefaultBool0 := True;
        AddOrUpdateNode(N);
        AddOrUpdateNode(MakeDefaultNode('EG_Branch', bgkEventGraph, bnkBranch, 820, 80));
        N := MakeDefaultNode('EG_PrintArmed', bgkEventGraph, bnkPrintString, 1020, 60);
        N.DefaultStr0 := 'Turret Armed After Delay';
        AddOrUpdateNode(N);

        ConnectExec(bgkEventGraph, 'EG_Begin', 0, 'EG_Once', 0);
        ConnectExec(bgkEventGraph, 'EG_Once', 0, 'EG_Delay', 0);
        ConnectData(bgkEventGraph, 'EG_GetWarm', 0, 'EG_Delay', 0);
        ConnectExec(bgkEventGraph, 'EG_Delay', 0, 'EG_SetArmed', 0);
        ConnectExec(bgkEventGraph, 'EG_SetArmed', 0, 'EG_Branch', 0);
        ConnectData(bgkEventGraph, 'EG_SetArmed', 0, 'EG_Branch', 0);
        ConnectExec(bgkEventGraph, 'EG_Branch', 0, 'EG_PrintArmed', 0);
      end;
  end;

  CompileBlueprint;
  if FAutoRunConstruction and (FCompileStatus = bcsUpToDate) then
    RunConstructionScript;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleBlueprint.GetGraphJson: String;
var
  Root, Obj: TJSONObject;
  VarsArr, NodesArr, ExecArr, DataArr, VecArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('className', FBlueprintClassName);

    VarsArr := TJSONArray.Create;
    for I := 0 to High(FVariables) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('name', FVariables[I].VarName);
      Obj.Add('type', Ord(FVariables[I].VarType));
      Obj.Add('editable', FVariables[I].IsInstanceEditable);
      Obj.Add('category', FVariables[I].Category);
      Obj.Add('b', FVariables[I].DefaultBool);
      Obj.Add('i', FVariables[I].DefaultInt);
      Obj.Add('f', FVariables[I].DefaultFloat);
      Obj.Add('s', FVariables[I].DefaultStr);
      VecArr := TJSONArray.Create;
      VecArr.Add(FVariables[I].DefaultVec.X);
      VecArr.Add(FVariables[I].DefaultVec.Y);
      VecArr.Add(FVariables[I].DefaultVec.Z);
      Obj.Add('v', VecArr);
      VarsArr.Add(Obj);
    end;
    Root.Add('variables', VarsArr);

    NodesArr := TJSONArray.Create;
    for I := 0 to High(FNodes) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FNodes[I].NodeId);
      Obj.Add('graph', Ord(FNodes[I].Graph));
      Obj.Add('kind', Ord(FNodes[I].Kind));
      Obj.Add('member', FNodes[I].MemberName);
      Obj.Add('x', FNodes[I].PosX);
      Obj.Add('y', FNodes[I].PosY);
      Obj.Add('bp', FNodes[I].HasBreakpoint);
      Obj.Add('b0', FNodes[I].DefaultBool0);
      Obj.Add('i0', FNodes[I].DefaultInt0);
      Obj.Add('i1', FNodes[I].DefaultInt1);
      Obj.Add('f0', FNodes[I].DefaultFloat0);
      Obj.Add('f1', FNodes[I].DefaultFloat1);
      Obj.Add('f2', FNodes[I].DefaultFloat2);
      Obj.Add('s0', FNodes[I].DefaultStr0);
      VecArr := TJSONArray.Create;
      VecArr.Add(FNodes[I].DefaultVec0.X);
      VecArr.Add(FNodes[I].DefaultVec0.Y);
      VecArr.Add(FNodes[I].DefaultVec0.Z);
      Obj.Add('v0', VecArr);
      VecArr := TJSONArray.Create;
      VecArr.Add(FNodes[I].DefaultVec1.X);
      VecArr.Add(FNodes[I].DefaultVec1.Y);
      VecArr.Add(FNodes[I].DefaultVec1.Z);
      Obj.Add('v1', VecArr);
      NodesArr.Add(Obj);
    end;
    Root.Add('nodes', NodesArr);

    ExecArr := TJSONArray.Create;
    for I := 0 to High(FExecLinks) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('g', Ord(FExecLinks[I].Graph));
      Obj.Add('fn', FExecLinks[I].FromNodeId);
      Obj.Add('fp', FExecLinks[I].FromExecPin);
      Obj.Add('tn', FExecLinks[I].ToNodeId);
      Obj.Add('tp', FExecLinks[I].ToExecPin);
      ExecArr.Add(Obj);
    end;
    Root.Add('execLinks', ExecArr);

    DataArr := TJSONArray.Create;
    for I := 0 to High(FDataLinks) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('g', Ord(FDataLinks[I].Graph));
      Obj.Add('fn', FDataLinks[I].FromNodeId);
      Obj.Add('fp', FDataLinks[I].FromDataPin);
      Obj.Add('tn', FDataLinks[I].ToNodeId);
      Obj.Add('tp', FDataLinks[I].ToDataPin);
      DataArr.Add(Obj);
    end;
    Root.Add('dataLinks', DataArr);

    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleBlueprint.SetGraphJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr, VecArr: TJSONArray;
  I: Integer;
  DefV: TBlueprintValue;
  N: TBlueprintNode;
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
    ClearAllGraphs;
    FPreset := bppCustom;
    FBlueprintClassName := Root.Get('className', FBlueprintClassName);

    Arr := Root.Find('variables', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          DefV := Default(TBlueprintValue);
          DefV.PinType := TBlueprintPinType(EnsureRange(Obj.Get('type', 3), 0, Ord(High(TBlueprintPinType))));
          DefV.BoolVal := Obj.Get('b', False);
          DefV.IntVal := Obj.Get('i', 0);
          DefV.FloatVal := Obj.Get('f', 0.0);
          DefV.StrVal := Obj.Get('s', '');
          VecArr := Obj.Find('v', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            DefV.VecVal := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          AddOrUpdateVariable(Obj.Get('name', 'Var' + IntToStr(I)), DefV.PinType,
            DefV, Obj.Get('editable', True), Obj.Get('category', 'Default'));
        end;

    Arr := Root.Find('nodes', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          N := MakeDefaultNode(
            Obj.Get('id', 'Node_' + IntToStr(I)),
            TBlueprintGraphKind(EnsureRange(Obj.Get('graph', 1), 0, 1)),
            TBlueprintNodeKind(EnsureRange(Obj.Get('kind', 0), 0, Ord(High(TBlueprintNodeKind)))),
            Obj.Get('x', 80.0),
            Obj.Get('y', 80.0),
            Obj.Get('member', ''));
          N.HasBreakpoint := Obj.Get('bp', False);
          N.DefaultBool0 := Obj.Get('b0', False);
          N.DefaultInt0 := Obj.Get('i0', 0);
          N.DefaultInt1 := Obj.Get('i1', 3);
          N.DefaultFloat0 := Obj.Get('f0', 1.0);
          N.DefaultFloat1 := Obj.Get('f1', 1.0);
          N.DefaultFloat2 := Obj.Get('f2', 0.0);
          N.DefaultStr0 := Obj.Get('s0', '');
          VecArr := Obj.Find('v0', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            N.DefaultVec0 := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          VecArr := Obj.Find('v1', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            N.DefaultVec1 := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          AddOrUpdateNode(N);
        end;

    Arr := Root.Find('execLinks', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          ConnectExec(
            TBlueprintGraphKind(EnsureRange(Obj.Get('g', 1), 0, 1)),
            Obj.Get('fn', ''), Obj.Get('fp', 0),
            Obj.Get('tn', ''), Obj.Get('tp', 0));
        end;

    Arr := Root.Find('dataLinks', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          ConnectData(
            TBlueprintGraphKind(EnsureRange(Obj.Get('g', 1), 0, 1)),
            Obj.Get('fn', ''), Obj.Get('fp', 0),
            Obj.Get('tn', ''), Obj.Get('tp', 0));
        end;

    CompileBlueprint;
    if (not (csLoading in ComponentState)) and FAutoRunConstruction and
       (FCompileStatus = bcsUpToDate) then
      RunConstructionScript;
  finally
    FreeAndNil(Parsed);
  end;
end;

{ Blueprint Nativization -> Pascal Codegen ----------------------------------- }

function TCastleBlueprint.GeneratePascalUnit(const AUnitName: String): String;
var
  SB: TStringList;
  CleanClass, CleanUnit: String;
  I: Integer;

  function SanitizeIdent(const S: String): String;
  var
    K: Integer;
  begin
    Result := '';
    for K := 1 to Length(S) do
      if S[K] in ['A'..'Z', 'a'..'z', '0'..'9', '_'] then
        Result := Result + S[K];
    if Result = '' then
      Result := 'GeneratedBP';
    if Result[1] in ['0'..'9'] then
      Result := 'BP_' + Result;
  end;

  function EmitDataExpr(const AGraph: TBlueprintGraphKind;
    const ANodeIdx, AInPin: Integer; const Depth: Integer): String;
  var
    L, SrcIdx: Integer;
    SrcNode, CurNode: TBlueprintNode;
  begin
    CurNode := FNodes[ANodeIdx];
    if Depth < 12 then
      for L := 0 to High(FDataLinks) do
        if (FDataLinks[L].Graph = AGraph) and
           SameText(FDataLinks[L].ToNodeId, CurNode.NodeId) and
           (FDataLinks[L].ToDataPin = AInPin) then
        begin
          SrcIdx := FindNodeIndex(FDataLinks[L].FromNodeId);
          if SrcIdx >= 0 then
          begin
            SrcNode := FNodes[SrcIdx];
            case SrcNode.Kind of
              bnkEventTick:         Exit('SecondsPassed');
              bnkEventBeginOverlap: Exit('OtherActorName');
              bnkForLoop:           Exit('LoopIdx_' + SanitizeIdent(SrcNode.NodeId));
              bnkGetVariable, bnkSetVariable:
                Exit('F' + SanitizeIdent(SrcNode.MemberName));
              bnkAddFloat:
                Exit(Format('(%s + %s)', [
                  EmitDataExpr(AGraph, SrcIdx, 0, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 1, Depth + 1)]));
              bnkMultiplyFloat:
                Exit(Format('(%s * %s)', [
                  EmitDataExpr(AGraph, SrcIdx, 0, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 1, Depth + 1)]));
              bnkGreaterFloat:
                Exit(Format('(%s > %s)', [
                  EmitDataExpr(AGraph, SrcIdx, 0, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 1, Depth + 1)]));
              bnkMakeVector:
                Exit(Format('Vector3(%s, %s, %s)', [
                  EmitDataExpr(AGraph, SrcIdx, 0, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 1, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 2, Depth + 1)]));
              bnkLerpVector:
                Exit(Format('Lerp(EnsureRange(%s, 0.0, 1.0), %s, %s)', [
                  EmitDataExpr(AGraph, SrcIdx, 2, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 0, Depth + 1),
                  EmitDataExpr(AGraph, SrcIdx, 1, Depth + 1)]));
              bnkTimeline:
                Exit('FTimelineAlpha');
            end;
          end;
        end;

    case CurNode.Kind of
      bnkBranch, bnkDoOnce, bnkGate:
        Result := BoolToStr(CurNode.DefaultBool0, 'True', 'False');
      bnkForLoop:
        if AInPin = 0 then Result := IntToStr(CurNode.DefaultInt0)
        else Result := IntToStr(CurNode.DefaultInt1);
      bnkPrintString:
        Result := QuotedStr(CurNode.DefaultStr0);
      bnkSetRelativeLocation, bnkAddLocalOffset, bnkSpawnProceduralBox:
        if AInPin = 1 then
          Result := Format('Vector3(%.3f, %.3f, %.3f)',
            [CurNode.DefaultVec1.X, CurNode.DefaultVec1.Y, CurNode.DefaultVec1.Z])
        else
          Result := Format('Vector3(%.3f, %.3f, %.3f)',
            [CurNode.DefaultVec0.X, CurNode.DefaultVec0.Y, CurNode.DefaultVec0.Z]);
    else
      case AInPin of
        0: Result := FormatFloat('0.0##', CurNode.DefaultFloat0);
        1: Result := FormatFloat('0.0##', CurNode.DefaultFloat1);
      else
        Result := FormatFloat('0.0##', CurNode.DefaultFloat2);
      end;
    end;
  end;

  procedure EmitExecChain(const AGraph: TBlueprintGraphKind;
    const AFromIdx, AFromOutPin: Integer; const Indent: String; const Depth: Integer);
  var
    L, NextIdx: Integer;
    NextNode: TBlueprintNode;
    LoopVar: String;
  begin
    if Depth > 24 then Exit;
    for L := 0 to High(FExecLinks) do
      if (FExecLinks[L].Graph = AGraph) and
         SameText(FExecLinks[L].FromNodeId, FNodes[AFromIdx].NodeId) and
         (FExecLinks[L].FromExecPin = AFromOutPin) then
      begin
        NextIdx := FindNodeIndex(FExecLinks[L].ToNodeId);
        if NextIdx < 0 then Exit;
        NextNode := FNodes[NextIdx];
        case NextNode.Kind of
          bnkBranch:
            begin
              SB.Add(Format('%sif %s then', [Indent, EmitDataExpr(AGraph, NextIdx, 0, 0)]));
              SB.Add(Indent + 'begin');
              EmitExecChain(AGraph, NextIdx, 0, Indent + '  ', Depth + 1);
              SB.Add(Indent + 'end else');
              SB.Add(Indent + 'begin');
              EmitExecChain(AGraph, NextIdx, 1, Indent + '  ', Depth + 1);
              SB.Add(Indent + 'end;');
            end;
          bnkSequence:
            begin
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
              EmitExecChain(AGraph, NextIdx, 1, Indent, Depth + 1);
              EmitExecChain(AGraph, NextIdx, 2, Indent, Depth + 1);
            end;
          bnkForLoop:
            begin
              LoopVar := 'LoopIdx_' + SanitizeIdent(NextNode.NodeId);
              SB.Add(Format('%sfor %s := %s to %s do', [
                Indent, LoopVar,
                EmitDataExpr(AGraph, NextIdx, 0, 0),
                EmitDataExpr(AGraph, NextIdx, 1, 0)]));
              SB.Add(Indent + 'begin');
              EmitExecChain(AGraph, NextIdx, 0, Indent + '  ', Depth + 1);
              SB.Add(Indent + 'end;');
              EmitExecChain(AGraph, NextIdx, 1, Indent, Depth + 1);
            end;
          bnkSetVariable:
            begin
              SB.Add(Format('%sF%s := %s;', [
                Indent, SanitizeIdent(NextNode.MemberName),
                EmitDataExpr(AGraph, NextIdx, 0, 0)]));
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
            end;
          bnkSpawnProceduralBox:
            begin
              SB.Add(Format('%sSpawnProceduralBox(%s, %s);', [
                Indent,
                EmitDataExpr(AGraph, NextIdx, 0, 0),
                EmitDataExpr(AGraph, NextIdx, 1, 0)]));
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
            end;
          bnkSetRelativeLocation:
            begin
              SB.Add(Format('%sParent.Translation := %s;', [
                Indent, EmitDataExpr(AGraph, NextIdx, 0, 0)]));
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
            end;
          bnkAddLocalOffset:
            begin
              SB.Add(Format('%sParent.Translation := Parent.Translation + %s;', [
                Indent, EmitDataExpr(AGraph, NextIdx, 0, 0)]));
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
            end;
          bnkAddLocalRotationYaw:
            begin
              SB.Add(Format('%sFYawDeg := FYawDeg + (%s);', [
                Indent, EmitDataExpr(AGraph, NextIdx, 0, 0)]));
              SB.Add(Format('%sParent.Rotation := Vector4(0, 1, 0, DegToRad(FYawDeg));', [Indent]));
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
            end;
          bnkPrintString:
            begin
              SB.Add(Format('%sWritelnLog(''%s'', %s);', [
                Indent, CleanClass, EmitDataExpr(AGraph, NextIdx, 0, 0)]));
              EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
            end;
        else
          begin
            SB.Add(Format('%s{ %s (%s) }', [Indent, NextNode.NodeId, NodeKindTitle(NextNode.Kind)]));
            EmitExecChain(AGraph, NextIdx, 0, Indent, Depth + 1);
          end;
        end;
        Exit;
      end;
  end;

begin
  CleanClass := 'T' + SanitizeIdent(FBlueprintClassName) + 'Behavior';
  if Trim(AUnitName) <> '' then
    CleanUnit := SanitizeIdent(AUnitName)
  else
    CleanUnit := 'GameBlueprint_' + SanitizeIdent(FBlueprintClassName);

  SB := TStringList.Create;
  try
    SB.Add('{ Auto-generated by Castle Game Engine Blueprint Nativizer (Phase 381) }');
    SB.Add('unit ' + CleanUnit + ';');
    SB.Add('');
    SB.Add('{$mode objfpc}{$H+}');
    SB.Add('');
    SB.Add('interface');
    SB.Add('');
    SB.Add('uses Classes, SysUtils, Math, CastleVectors, CastleTransform, CastleScene, CastleLog;');
    SB.Add('');
    SB.Add('type');
    SB.Add('  ' + CleanClass + ' = class(TCastleBehavior)');
    SB.Add('  private');
    SB.Add('    FYawDeg: Single;');
    SB.Add('    FTimelineAlpha: Single;');
    for I := 0 to High(FVariables) do
      SB.Add(Format('    F%s: %s;', [
        SanitizeIdent(FVariables[I].VarName),
        PinTypeName(FVariables[I].VarType)]));
    SB.Add('    procedure SpawnProceduralBox(const AOffset, ASize: TVector3);');
    SB.Add('  public');
    SB.Add('    constructor Create(AOwner: TComponent); override;');
    SB.Add('    procedure RunConstructionScript;');
    SB.Add('    procedure ParentAfterAttach; override;');
    SB.Add('    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;');
    for I := 0 to High(FVariables) do
      if FVariables[I].IsInstanceEditable then
        SB.Add(Format('    property %s: %s read F%s write F%s;', [
          SanitizeIdent(FVariables[I].VarName),
          PinTypeName(FVariables[I].VarType),
          SanitizeIdent(FVariables[I].VarName),
          SanitizeIdent(FVariables[I].VarName)]));
    SB.Add('  end;');
    SB.Add('');
    SB.Add('implementation');
    SB.Add('');
    SB.Add('constructor ' + CleanClass + '.Create(AOwner: TComponent);');
    SB.Add('begin');
    SB.Add('  inherited Create(AOwner);');
    for I := 0 to High(FVariables) do
      case FVariables[I].VarType of
        bptBool:   SB.Add(Format('  F%s := %s;', [SanitizeIdent(FVariables[I].VarName), BoolToStr(FVariables[I].DefaultBool, 'True', 'False')]));
        bptInt:    SB.Add(Format('  F%s := %d;', [SanitizeIdent(FVariables[I].VarName), FVariables[I].DefaultInt]));
        bptFloat:  SB.Add(Format('  F%s := %.3f;', [SanitizeIdent(FVariables[I].VarName), FVariables[I].DefaultFloat]));
        bptString: SB.Add(Format('  F%s := %s;', [SanitizeIdent(FVariables[I].VarName), QuotedStr(FVariables[I].DefaultStr)]));
        bptVec3:   SB.Add(Format('  F%s := Vector3(%.3f, %.3f, %.3f);', [
          SanitizeIdent(FVariables[I].VarName),
          FVariables[I].DefaultVec.X, FVariables[I].DefaultVec.Y, FVariables[I].DefaultVec.Z]));
      end;
    SB.Add('end;');
    SB.Add('');
    SB.Add('procedure ' + CleanClass + '.SpawnProceduralBox(const AOffset, ASize: TVector3);');
    SB.Add('var B: TCastleBox;');
    SB.Add('begin');
    SB.Add('  if Parent = nil then Exit;');
    SB.Add('  B := TCastleBox.Create(Self);');
    SB.Add('  B.Translation := AOffset;');
    SB.Add('  B.Size := ASize;');
    SB.Add('  Parent.Add(B);');
    SB.Add('end;');
    SB.Add('');
    SB.Add('procedure ' + CleanClass + '.RunConstructionScript;');
    for I := 0 to High(FNodes) do
      if (FNodes[I].Graph = bgkConstructionScript) and (FNodes[I].Kind = bnkForLoop) then
        SB.Add('var LoopIdx_' + SanitizeIdent(FNodes[I].NodeId) + ': Integer;');
    SB.Add('begin');
    for I := 0 to High(FNodes) do
      if (FNodes[I].Graph = bgkConstructionScript) and (FNodes[I].Kind = bnkConstructionEntry) then
        EmitExecChain(bgkConstructionScript, I, 0, '  ', 0);
    SB.Add('end;');
    SB.Add('');
    SB.Add('procedure ' + CleanClass + '.ParentAfterAttach;');
    SB.Add('begin');
    SB.Add('  inherited;');
    for I := 0 to High(FNodes) do
      if (FNodes[I].Graph = bgkEventGraph) and (FNodes[I].Kind = bnkEventBeginPlay) then
        EmitExecChain(bgkEventGraph, I, 0, '  ', 0);
    SB.Add('end;');
    SB.Add('');
    SB.Add('procedure ' + CleanClass + '.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);');
    SB.Add('begin');
    SB.Add('  inherited;');
    SB.Add('  if Parent = nil then Exit;');
    for I := 0 to High(FNodes) do
      if (FNodes[I].Graph = bgkEventGraph) and (FNodes[I].Kind = bnkEventTick) then
        EmitExecChain(bgkEventGraph, I, 0, '  ', 0);
    SB.Add('end;');
    SB.Add('');
    SB.Add('end.');
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

function TCastleBlueprint.BlueprintSummaryBadge: String;
var
  StateTag: String;
begin
  if FIsPausedAtBreakpoint then
    StateTag := 'PAUSED@' + FPausedNodeId
  else
    case FCompileStatus of
      bcsUpToDate: StateTag := 'Compiled';
      bcsError:    StateTag := Format('ERR:%d', [FCompileErrors.Count]);
    else
      StateTag := 'Dirty';
    end;
  Result := Format('[BP:%s %s Nodes=%d Vars=%d CS=%d]',
    [FBlueprintClassName, StateTag, Length(FNodes), Length(FVariables), FConstructionSpawnCount]);
end;

initialization
  RegisterSerializableComponent(TCastleBlueprint, 'Blueprint Actor (Visual Scripting)');
end.
