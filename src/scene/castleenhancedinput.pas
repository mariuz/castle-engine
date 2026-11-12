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

{ Enhanced Input Action Mapping, Priority Contexts, Tap/Hold/Chord Triggers,
  Radial 2D Deadzones & User Key Rebinding Manager (@link(TCastleInputMapManager))
  (Phase 311 — UE 6.0+ Enhanced Input Parity). }
unit CastleEnhancedInput;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Generics.Collections,
  CastleVectors, CastleClassUtils;

type
  { Value dimensionality of a logical input action. }
  TInputActionValueKind = (
    iavDigitalBool,
    iavAxis1D,
    iavAxis2D
  );

  { Trigger evaluation rule matching UE Enhanced Input UInputTrigger subclasses. }
  TInputTriggerKind = (
    itkPressed,
    itkDown,
    itkTap,
    itkHold,
    itkChord
  );

  { Built-in multi-context input templates. }
  TInputPresetKind = (
    ipkCustom,
    ipkActionRpgThirdPerson,
    ipkTwinStickShooter,
    ipkVehicleRacing
  );

  { Single physical key / mouse button / gamepad stick binding inside a context. }
  TInputBindingDef = record
    ContextId: String;
    ActionId: String;
    ValueKind: TInputActionValueKind;
    KeyName: String;
    DefaultKeyName: String;
    ChordKeyName: String;
    TriggerKind: TInputTriggerKind;
    ThresholdSec: Single;
    AxisContribution: TVector2;
    InnerDeadzone: Single;
    OuterSaturation: Single;
    ResponseExponent: Single;
    ScaleFactor: Single;
    NormalizeDigital2D: Boolean;
    class function CreateDigital(const ACtx, AAction, AKey: String;
      const ATrigger: TInputTriggerKind = itkPressed;
      const AThresholdSec: Single = 0.25;
      const AChordKey: String = ''): TInputBindingDef; static;
    class function CreateAxis2DKey(const ACtx, AAction, AKey: String;
      const AContrib: TVector2): TInputBindingDef; static;
    class function CreateStick2D(const ACtx, AAction, AStickName: String;
      const AInnerDeadzone: Single = 0.20;
      const AResponseExp: Single = 1.5): TInputBindingDef; static;
  end;

  { Priority-layered Input Mapping Context (IMC). }
  TInputMappingContextDef = record
    ContextId: String;
    Priority: Integer;
    Active: Boolean;
    ConsumeMappedKeys: Boolean;
    class function CreateContext(const AId: String; const APriority: Integer;
      const AActive: Boolean = True;
      const AConsume: Boolean = True): TInputMappingContextDef; static;
  end;

  { Per-binding runtime state tracking hold durations and edge transitions. }
  TInputBindingRuntimeState = record
    WasDown: Boolean;
    HeldDurationSec: Single;
    HoldFiredThisPress: Boolean;
  end;

  { Evaluated frame output of a logical action. }
  TInputActionFrameValue = record
    ActionId: String;
    Triggered: Boolean;
    Axis2D: TVector2;
  end;

  TInputContextList = {$ifdef FPC}specialize{$endif} TList<TInputMappingContextDef>;
  TInputBindingList = {$ifdef FPC}specialize{$endif} TList<TInputBindingDef>;

  { Non-visual Enhanced Input manager component stored in @code($NonVisualComponents).
    Evaluates priority-sorted Input Mapping Contexts with key consumption,
    @code(Pressed) / @code(Down) / @code(Tap) / @code(Hold) / @code(Chord) triggers,
    radial 2D stick deadzones, diagonal WASD normalization, conflict auditing,
    and user-profile JSON key rebinding. }
  TCastleInputMapManager = class(TCastleComponent)
  strict private
    FPreset: TInputPresetKind;
    FContexts: TInputContextList;
    FBindings: TInputBindingList;
    FBindingStates: array of TInputBindingRuntimeState;
    FDownKeys: TStringList;
    FAnalogSticks: array of record
      StickName: String;
      RawVec: TVector2;
    end;
    FLastActionValues: array of TInputActionFrameValue;

    procedure SetPreset(const Value: TInputPresetKind);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure SyncRuntimeStateLength;
    function FindContextIndex(const AId: String): Integer;
    procedure SetOrAccumulateAction(const AActionId: String;
      const ATriggered: Boolean; const AAxis: TVector2);
    function GetRawStickValue(const AStickName: String): TVector2;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TInputPresetKind);

    property Contexts: TInputContextList read FContexts;
    property Bindings: TInputBindingList read FBindings;

    procedure AddOrUpdateContext(const ACtx: TInputMappingContextDef);
    procedure SetContextActive(const AContextId: String; const AActive: Boolean);
    function IsContextActive(const AContextId: String): Boolean;
    function AddBinding(const ABinding: TInputBindingDef): Integer;
    procedure ClearAll;

    { Physical input state injection (used by runtime view/window input & studio/unit tests). }
    procedure SetKeyState(const AKeyName: String; const AIsDown: Boolean);
    function IsKeyDown(const AKeyName: String): Boolean;
    procedure SetStickState(const AStickName: String; const ARawVec: TVector2);
    procedure ReleaseAllInputs;

    { Evaluate all active contexts in descending Priority order for a frame step Dt. }
    procedure StepInputFrame(const Dt: Single);

    { Query evaluated action state for the most recent StepInputFrame. }
    function WasActionTriggered(const AActionId: String): Boolean;
    function GetActionAxis2D(const AActionId: String): TVector2;
    function GetActionAxis1D(const AActionId: String): Single;

    { Runtime user key rebinding & JSON user-settings persistence. }
    function RebindByAction(const AContextId, AActionId, ANewKeyName: String;
      const ABindingOccurrence: Integer = 0): Boolean;
    function RebindAtIndex(const ABindingIndex: Integer; const ANewKeyName: String): Boolean;
    procedure ResetAllRebindsToDefault;
    function ExportUserRebindsJson: String;
    function ImportUserRebindsJson(const AJson: String): Integer;

    { Detect conflicting physical bindings inside the same active context. }
    function DetectBindingConflicts(const OutConflicts: TStrings): Integer;

    function InputSummaryBadge: String;
  published
    property Preset: TInputPresetKind
      read FPreset write SetPreset default ipkActionRpgThirdPerson;
    property ConfigJson: String
      read GetConfigJson write SetConfigJson stored True;
  end;

{ Exact radial 2D deadzone + power-curve remapper (eliminates axial cross-snapping). }
function EvaluateRadialDeadzone2D(const ARaw: TVector2;
  const AInnerDeadzone, AOuterSaturation, AResponseExponent: Single): TVector2;

function InputTriggerToString(const ATrigger: TInputTriggerKind): String;
function StringToInputTrigger(const S: String): TInputTriggerKind;
function InputValueKindToString(const AKind: TInputActionValueKind): String;
function StringToInputValueKind(const S: String): TInputActionValueKind;
function InputPresetDisplayName(const APreset: TInputPresetKind): String;

implementation

uses
  Math, fpjson, jsonparser,
  CastleComponentSerialize, CastleUtils;

function EvaluateRadialDeadzone2D(const ARaw: TVector2;
  const AInnerDeadzone, AOuterSaturation, AResponseExponent: Single): TVector2;
var
  Len, InnerD, OuterS, NormMag, CurvedMag: Single;
begin
  Len := ARaw.Length;
  InnerD := Clamped(AInnerDeadzone, 0.0, 0.95);
  OuterS := Max(InnerD + 1.0e-3, Clamped(AOuterSaturation, 0.05, 1.0));
  if Len <= InnerD + 1.0e-6 then
    Exit(TVector2.Zero);

  NormMag := Clamped((Len - InnerD) / (OuterS - InnerD), 0.0, 1.0);
  CurvedMag := Power(NormMag, Max(0.1, AResponseExponent));
  Result := (ARaw / Len) * CurvedMag;
end;

function InputTriggerToString(const ATrigger: TInputTriggerKind): String;
begin
  case ATrigger of
    itkPressed: Result := 'Pressed';
    itkDown:    Result := 'Down';
    itkTap:     Result := 'Tap';
    itkHold:    Result := 'Hold';
    itkChord:   Result := 'Chord';
  end;
end;

function StringToInputTrigger(const S: String): TInputTriggerKind;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'down' then
    Result := itkDown
  else if L = 'tap' then
    Result := itkTap
  else if L = 'hold' then
    Result := itkHold
  else if L = 'chord' then
    Result := itkChord
  else
    Result := itkPressed;
end;

function InputValueKindToString(const AKind: TInputActionValueKind): String;
begin
  case AKind of
    iavDigitalBool: Result := 'Bool';
    iavAxis1D:      Result := 'Axis1D';
    iavAxis2D:      Result := 'Axis2D';
  end;
end;

function StringToInputValueKind(const S: String): TInputActionValueKind;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if L = 'axis1d' then
    Result := iavAxis1D
  else if L = 'axis2d' then
    Result := iavAxis2D
  else
    Result := iavDigitalBool;
end;

function InputPresetDisplayName(const APreset: TInputPresetKind): String;
begin
  case APreset of
    ipkCustom:               Result := 'Custom';
    ipkActionRpgThirdPerson: Result := 'ActionRPG';
    ipkTwinStickShooter:     Result := 'TwinStick';
    ipkVehicleRacing:        Result := 'VehicleRacing';
  end;
end;

{ Record constructors -------------------------------------------------------- }

class function TInputBindingDef.CreateDigital(
  const ACtx, AAction, AKey: String;
  const ATrigger: TInputTriggerKind;
  const AThresholdSec: Single;
  const AChordKey: String): TInputBindingDef;
begin
  Result.ContextId := ACtx;
  Result.ActionId := AAction;
  Result.ValueKind := iavDigitalBool;
  Result.KeyName := AKey;
  Result.DefaultKeyName := AKey;
  Result.ChordKeyName := AChordKey;
  Result.TriggerKind := ATrigger;
  Result.ThresholdSec := AThresholdSec;
  Result.AxisContribution := Vector2(1.0, 0.0);
  Result.InnerDeadzone := 0.20;
  Result.OuterSaturation := 0.95;
  Result.ResponseExponent := 1.0;
  Result.ScaleFactor := 1.0;
  Result.NormalizeDigital2D := True;
end;

class function TInputBindingDef.CreateAxis2DKey(
  const ACtx, AAction, AKey: String;
  const AContrib: TVector2): TInputBindingDef;
begin
  Result := CreateDigital(ACtx, AAction, AKey, itkDown, 0.0, '');
  Result.ValueKind := iavAxis2D;
  Result.AxisContribution := AContrib;
  Result.NormalizeDigital2D := True;
end;

class function TInputBindingDef.CreateStick2D(
  const ACtx, AAction, AStickName: String;
  const AInnerDeadzone, AResponseExp: Single): TInputBindingDef;
begin
  Result := CreateDigital(ACtx, AAction, AStickName, itkDown, 0.0, '');
  Result.ValueKind := iavAxis2D;
  Result.AxisContribution := Vector2(0.0, 0.0);
  Result.InnerDeadzone := AInnerDeadzone;
  Result.OuterSaturation := 0.95;
  Result.ResponseExponent := AResponseExp;
  Result.NormalizeDigital2D := False;
end;

class function TInputMappingContextDef.CreateContext(
  const AId: String; const APriority: Integer;
  const AActive, AConsume: Boolean): TInputMappingContextDef;
begin
  Result.ContextId := AId;
  Result.Priority := APriority;
  Result.Active := AActive;
  Result.ConsumeMappedKeys := AConsume;
end;

{ TCastleInputMapManager ----------------------------------------------------- }

constructor TCastleInputMapManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FContexts := TInputContextList.Create;
  FBindings := TInputBindingList.Create;
  FDownKeys := TStringList.Create;
  FDownKeys.CaseSensitive := False;
  FDownKeys.Duplicates := dupIgnore;
  ApplyPreset(ipkActionRpgThirdPerson);
end;

destructor TCastleInputMapManager.Destroy;
begin
  FreeAndNil(FDownKeys);
  FreeAndNil(FBindings);
  FreeAndNil(FContexts);
  inherited;
end;

function TCastleInputMapManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or (PropertyName = 'ConfigJson') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleInputMapManager.SetPreset(const Value: TInputPresetKind);
begin
  if FPreset <> Value then
  begin
    if Value = ipkCustom then
      FPreset := ipkCustom
    else
      ApplyPreset(Value);
  end;
end;

procedure TCastleInputMapManager.SyncRuntimeStateLength;
var
  OldLen, NewLen, I: Integer;
begin
  OldLen := Length(FBindingStates);
  NewLen := FBindings.Count;
  SetLength(FBindingStates, NewLen);
  for I := OldLen to NewLen - 1 do
  begin
    FBindingStates[I].WasDown := False;
    FBindingStates[I].HeldDurationSec := 0.0;
    FBindingStates[I].HoldFiredThisPress := False;
  end;
end;

function TCastleInputMapManager.FindContextIndex(const AId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to FContexts.Count - 1 do
    if SameText(FContexts[I].ContextId, AId) then
      Exit(I);
  Result := -1;
end;

procedure TCastleInputMapManager.ClearAll;
begin
  FContexts.Clear;
  FBindings.Clear;
  FBindingStates := nil;
  FLastActionValues := nil;
end;

procedure TCastleInputMapManager.ApplyPreset(const APreset: TInputPresetKind);
begin
  FPreset := APreset;
  if APreset = ipkCustom then
    Exit;

  ClearAll;
  ReleaseAllInputs;

  case APreset of
    ipkActionRpgThirdPerson:
      begin
        AddOrUpdateContext(TInputMappingContextDef.CreateContext('GameplayDefault', 0, True, True));
        AddOrUpdateContext(TInputMappingContextDef.CreateContext('DialogueOverlay', 50, False, True));

        { WASD + LeftStick 2D movement }
        AddBinding(TInputBindingDef.CreateAxis2DKey('GameplayDefault', 'Move2D', 'KeyW', Vector2(0.0, 1.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('GameplayDefault', 'Move2D', 'KeyS', Vector2(0.0, -1.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('GameplayDefault', 'Move2D', 'KeyA', Vector2(-1.0, 0.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('GameplayDefault', 'Move2D', 'KeyD', Vector2(1.0, 0.0)));
        AddBinding(TInputBindingDef.CreateStick2D('GameplayDefault', 'Move2D', 'GamepadLeftStick', 0.20, 1.5));

        { Tap Dodge vs Hold Heavy Attack vs Chord Ultimate vs Interact }
        AddBinding(TInputBindingDef.CreateDigital('GameplayDefault', 'DodgeRoll', 'KeySpace', itkTap, 0.22));
        AddBinding(TInputBindingDef.CreateDigital('GameplayDefault', 'HeavyCharge', 'MouseLeft', itkHold, 0.45));
        AddBinding(TInputBindingDef.CreateDigital('GameplayDefault', 'UltimateBurst', 'KeyQ', itkChord, 0.0, 'LeftShift'));
        AddBinding(TInputBindingDef.CreateDigital('GameplayDefault', 'InteractWorld', 'KeyE', itkPressed));

        { Higher-priority DialogueOverlay consumes KeyE when active }
        AddBinding(TInputBindingDef.CreateDigital('DialogueOverlay', 'AdvanceDialogue', 'KeyE', itkPressed));
      end;

    ipkTwinStickShooter:
      begin
        AddOrUpdateContext(TInputMappingContextDef.CreateContext('TwinStickCombat', 0, True, True));
        AddBinding(TInputBindingDef.CreateAxis2DKey('TwinStickCombat', 'Move2D', 'KeyW', Vector2(0.0, 1.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('TwinStickCombat', 'Move2D', 'KeyS', Vector2(0.0, -1.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('TwinStickCombat', 'Move2D', 'KeyA', Vector2(-1.0, 0.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('TwinStickCombat', 'Move2D', 'KeyD', Vector2(1.0, 0.0)));
        AddBinding(TInputBindingDef.CreateStick2D('TwinStickCombat', 'Aim2D', 'GamepadRightStick', 0.18, 1.25));
        AddBinding(TInputBindingDef.CreateDigital('TwinStickCombat', 'Dash', 'KeySpace', itkPressed));
      end;

    ipkVehicleRacing:
      begin
        AddOrUpdateContext(TInputMappingContextDef.CreateContext('VehicleDriving', 10, True, True));
        AddBinding(TInputBindingDef.CreateAxis2DKey('VehicleDriving', 'SteerThrottle', 'KeyW', Vector2(0.0, 1.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('VehicleDriving', 'SteerThrottle', 'KeyS', Vector2(0.0, -1.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('VehicleDriving', 'SteerThrottle', 'KeyA', Vector2(-1.0, 0.0)));
        AddBinding(TInputBindingDef.CreateAxis2DKey('VehicleDriving', 'SteerThrottle', 'KeyD', Vector2(1.0, 0.0)));
        AddBinding(TInputBindingDef.CreateDigital('VehicleDriving', 'Handbrake', 'KeySpace', itkDown));
        AddBinding(TInputBindingDef.CreateDigital('VehicleDriving', 'NitroBoost', 'LeftShift', itkHold, 0.30));
      end;
  end;
end;

procedure TCastleInputMapManager.AddOrUpdateContext(const ACtx: TInputMappingContextDef);
var
  Idx: Integer;
begin
  Idx := FindContextIndex(ACtx.ContextId);
  if Idx >= 0 then
    FContexts[Idx] := ACtx
  else
    FContexts.Add(ACtx);
end;

procedure TCastleInputMapManager.SetContextActive(
  const AContextId: String; const AActive: Boolean);
var
  Idx: Integer;
  Ctx: TInputMappingContextDef;
begin
  Idx := FindContextIndex(AContextId);
  if Idx < 0 then
    Exit;
  Ctx := FContexts[Idx];
  Ctx.Active := AActive;
  FContexts[Idx] := Ctx;
end;

function TCastleInputMapManager.IsContextActive(const AContextId: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindContextIndex(AContextId);
  Result := (Idx >= 0) and FContexts[Idx].Active;
end;

function TCastleInputMapManager.AddBinding(const ABinding: TInputBindingDef): Integer;
begin
  Result := FBindings.Add(ABinding);
  SyncRuntimeStateLength;
end;

procedure TCastleInputMapManager.SetKeyState(
  const AKeyName: String; const AIsDown: Boolean);
var
  Idx: Integer;
  K: String;
begin
  K := Trim(AKeyName);
  if K = '' then
    Exit;
  Idx := FDownKeys.IndexOf(K);
  if AIsDown then
  begin
    if Idx < 0 then
      FDownKeys.Add(K);
  end else
  begin
    if Idx >= 0 then
      FDownKeys.Delete(Idx);
  end;
end;

function TCastleInputMapManager.IsKeyDown(const AKeyName: String): Boolean;
begin
  Result := (Trim(AKeyName) <> '') and (FDownKeys.IndexOf(Trim(AKeyName)) >= 0);
end;

procedure TCastleInputMapManager.SetStickState(
  const AStickName: String; const ARawVec: TVector2);
var
  I, L: Integer;
begin
  for I := 0 to High(FAnalogSticks) do
    if SameText(FAnalogSticks[I].StickName, AStickName) then
    begin
      FAnalogSticks[I].RawVec := ARawVec;
      Exit;
    end;
  L := Length(FAnalogSticks);
  SetLength(FAnalogSticks, L + 1);
  FAnalogSticks[L].StickName := AStickName;
  FAnalogSticks[L].RawVec := ARawVec;
end;

function TCastleInputMapManager.GetRawStickValue(const AStickName: String): TVector2;
var
  I: Integer;
begin
  for I := 0 to High(FAnalogSticks) do
    if SameText(FAnalogSticks[I].StickName, AStickName) then
      Exit(FAnalogSticks[I].RawVec);
  Result := TVector2.Zero;
end;

procedure TCastleInputMapManager.ReleaseAllInputs;
var
  I: Integer;
begin
  FDownKeys.Clear;
  FAnalogSticks := nil;
  FLastActionValues := nil;
  for I := 0 to High(FBindingStates) do
  begin
    FBindingStates[I].WasDown := False;
    FBindingStates[I].HeldDurationSec := 0.0;
    FBindingStates[I].HoldFiredThisPress := False;
  end;
end;

procedure TCastleInputMapManager.SetOrAccumulateAction(
  const AActionId: String; const ATriggered: Boolean; const AAxis: TVector2);
var
  I, L: Integer;
begin
  for I := 0 to High(FLastActionValues) do
    if SameText(FLastActionValues[I].ActionId, AActionId) then
    begin
      FLastActionValues[I].Triggered := FLastActionValues[I].Triggered or ATriggered;
      FLastActionValues[I].Axis2D := FLastActionValues[I].Axis2D + AAxis;
      Exit;
    end;
  L := Length(FLastActionValues);
  SetLength(FLastActionValues, L + 1);
  FLastActionValues[L].ActionId := AActionId;
  FLastActionValues[L].Triggered := ATriggered;
  FLastActionValues[L].Axis2D := AAxis;
end;

procedure TCastleInputMapManager.StepInputFrame(const Dt: Single);
var
  SortedCtxIdx: array of Integer;
  ConsumedKeys: TStringList;
  I, J, Tmp, CIdx: Integer;
  Ctx: TInputMappingContextDef;
  B: TInputBindingDef;
  St: TInputBindingRuntimeState;
  PhysDown, EffDown, Fired: Boolean;
  StickRaw, StickFiltered, OutAxis: TVector2;
  NeedsClampActions: TStringList;
begin
  SyncRuntimeStateLength;
  FLastActionValues := nil;

  { Sort active context indices by descending Priority }
  SetLength(SortedCtxIdx, 0);
  for I := 0 to FContexts.Count - 1 do
    if FContexts[I].Active then
    begin
      J := Length(SortedCtxIdx);
      SetLength(SortedCtxIdx, J + 1);
      SortedCtxIdx[J] := I;
    end;

  for I := 0 to High(SortedCtxIdx) - 1 do
    for J := I + 1 to High(SortedCtxIdx) do
      if FContexts[SortedCtxIdx[J]].Priority > FContexts[SortedCtxIdx[I]].Priority then
      begin
        Tmp := SortedCtxIdx[I];
        SortedCtxIdx[I] := SortedCtxIdx[J];
        SortedCtxIdx[J] := Tmp;
      end;

  ConsumedKeys := TStringList.Create;
  NeedsClampActions := TStringList.Create;
  try
    ConsumedKeys.CaseSensitive := False;
    ConsumedKeys.Duplicates := dupIgnore;
    NeedsClampActions.CaseSensitive := False;
    NeedsClampActions.Duplicates := dupIgnore;

    for I := 0 to High(SortedCtxIdx) do
    begin
      CIdx := SortedCtxIdx[I];
      Ctx := FContexts[CIdx];

      for J := 0 to FBindings.Count - 1 do
      begin
        B := FBindings[J];
        if not SameText(B.ContextId, Ctx.ContextId) then
          Continue;

        St := FBindingStates[J];

        { Analog 2D stick binding (AxisContribution = 0,0) }
        if (B.ValueKind = iavAxis2D) and B.AxisContribution.IsPerfectlyZero then
        begin
          if ConsumedKeys.IndexOf(B.KeyName) >= 0 then
            StickRaw := TVector2.Zero
          else
            StickRaw := GetRawStickValue(B.KeyName);
          StickFiltered := EvaluateRadialDeadzone2D(
            StickRaw, B.InnerDeadzone, B.OuterSaturation, B.ResponseExponent) * B.ScaleFactor;
          Fired := StickFiltered.LengthSqr > 1.0e-6;
          if Fired then
          begin
            SetOrAccumulateAction(B.ActionId, True, StickFiltered);
            if B.NormalizeDigital2D then
              NeedsClampActions.Add(B.ActionId);
            if Ctx.ConsumeMappedKeys then
              ConsumedKeys.Add(B.KeyName);
          end;
          Continue;
        end;

        PhysDown := IsKeyDown(B.KeyName) and (ConsumedKeys.IndexOf(B.KeyName) < 0);
        if B.TriggerKind = itkChord then
          EffDown := PhysDown and IsKeyDown(B.ChordKeyName)
        else
          EffDown := PhysDown;

        Fired := False;
        case B.TriggerKind of
          itkPressed:
            Fired := EffDown and (not St.WasDown);
          itkDown:
            Fired := EffDown;
          itkChord:
            Fired := EffDown and (not St.WasDown);
          itkTap:
            begin
              if EffDown then
                St.HeldDurationSec := St.HeldDurationSec + Max(0.0, Dt)
              else if St.WasDown then
              begin
                if St.HeldDurationSec <= Max(0.02, B.ThresholdSec) + 1.0e-5 then
                  Fired := True;
                St.HeldDurationSec := 0.0;
              end;
            end;
          itkHold:
            begin
              if EffDown then
              begin
                St.HeldDurationSec := St.HeldDurationSec + Max(0.0, Dt);
                if (not St.HoldFiredThisPress) and
                   (St.HeldDurationSec + 1.0e-5 >= Max(0.02, B.ThresholdSec)) then
                begin
                  Fired := True;
                  St.HoldFiredThisPress := True;
                end;
              end else
              begin
                St.HeldDurationSec := 0.0;
                St.HoldFiredThisPress := False;
              end;
            end;
        end;

        St.WasDown := EffDown;
        FBindingStates[J] := St;

        if Fired then
        begin
          OutAxis := B.AxisContribution * B.ScaleFactor;
          SetOrAccumulateAction(B.ActionId, True, OutAxis);
          if (B.ValueKind = iavAxis2D) and B.NormalizeDigital2D then
            NeedsClampActions.Add(B.ActionId);
        end;

        { Consume mapped physical key in lower-priority contexts when held or fired }
        if Ctx.ConsumeMappedKeys and (PhysDown or Fired) then
          ConsumedKeys.Add(B.KeyName);
      end;
    end;

    { Clamp/normalize composite digital 2D vectors (e.g. diagonal W+D -> length 1.0) }
    for I := 0 to High(FLastActionValues) do
      if (NeedsClampActions.IndexOf(FLastActionValues[I].ActionId) >= 0) and
         (FLastActionValues[I].Axis2D.LengthSqr > 1.0) then
        FLastActionValues[I].Axis2D := FLastActionValues[I].Axis2D.Normalize;
  finally
    FreeAndNil(NeedsClampActions);
    FreeAndNil(ConsumedKeys);
  end;
end;

function TCastleInputMapManager.WasActionTriggered(const AActionId: String): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FLastActionValues) do
    if SameText(FLastActionValues[I].ActionId, AActionId) then
      Exit(FLastActionValues[I].Triggered);
  Result := False;
end;

function TCastleInputMapManager.GetActionAxis2D(const AActionId: String): TVector2;
var
  I: Integer;
begin
  for I := 0 to High(FLastActionValues) do
    if SameText(FLastActionValues[I].ActionId, AActionId) then
      Exit(FLastActionValues[I].Axis2D);
  Result := TVector2.Zero;
end;

function TCastleInputMapManager.GetActionAxis1D(const AActionId: String): Single;
begin
  Result := GetActionAxis2D(AActionId).X;
end;

function TCastleInputMapManager.RebindAtIndex(
  const ABindingIndex: Integer; const ANewKeyName: String): Boolean;
var
  B: TInputBindingDef;
begin
  if (ABindingIndex < 0) or (ABindingIndex >= FBindings.Count) or
     (Trim(ANewKeyName) = '') then
    Exit(False);
  B := FBindings[ABindingIndex];
  B.KeyName := Trim(ANewKeyName);
  FBindings[ABindingIndex] := B;
  Result := True;
end;

function TCastleInputMapManager.RebindByAction(
  const AContextId, AActionId, ANewKeyName: String;
  const ABindingOccurrence: Integer): Boolean;
var
  I, Seen: Integer;
begin
  Seen := 0;
  for I := 0 to FBindings.Count - 1 do
    if SameText(FBindings[I].ContextId, AContextId) and
       SameText(FBindings[I].ActionId, AActionId) then
    begin
      if Seen = ABindingOccurrence then
        Exit(RebindAtIndex(I, ANewKeyName));
      Inc(Seen);
    end;
  Result := False;
end;

procedure TCastleInputMapManager.ResetAllRebindsToDefault;
var
  I: Integer;
  B: TInputBindingDef;
begin
  for I := 0 to FBindings.Count - 1 do
  begin
    B := FBindings[I];
    if B.DefaultKeyName <> '' then
      B.KeyName := B.DefaultKeyName;
    FBindings[I] := B;
  end;
end;

function TCastleInputMapManager.ExportUserRebindsJson: String;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  B: TInputBindingDef;
begin
  Arr := TJSONArray.Create;
  try
    for I := 0 to FBindings.Count - 1 do
    begin
      B := FBindings[I];
      if not SameText(B.KeyName, B.DefaultKeyName) then
      begin
        Obj := TJSONObject.Create;
        Obj.Add('index', I);
        Obj.Add('ctx', B.ContextId);
        Obj.Add('action', B.ActionId);
        Obj.Add('defaultKey', B.DefaultKeyName);
        Obj.Add('userKey', B.KeyName);
        Arr.Add(Obj);
      end;
    end;
    Result := Arr.AsJSON;
  finally
    FreeAndNil(Arr);
  end;
end;

function TCastleInputMapManager.ImportUserRebindsJson(const AJson: String): Integer;
var
  Data: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I, J, Idx: Integer;
  Ctx, Act, DefK, UserK: String;
  Applied: Boolean;
begin
  Result := 0;
  if Trim(AJson) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AJson);
    except
      Exit;
    end;
    if not (Data is TJSONArray) then
      Exit;
    Arr := TJSONArray(Data);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        Obj := TJSONObject(Arr.Items[I]);
        Ctx := Obj.Get('ctx', '');
        Act := Obj.Get('action', '');
        DefK := Obj.Get('defaultKey', '');
        UserK := Obj.Get('userKey', '');
        Idx := Obj.Get('index', -1);
        if UserK = '' then
          Continue;

        Applied := False;
        for J := 0 to FBindings.Count - 1 do
          if SameText(FBindings[J].ContextId, Ctx) and
             SameText(FBindings[J].ActionId, Act) and
             ((DefK = '') or SameText(FBindings[J].DefaultKeyName, DefK)) then
          begin
            Applied := RebindAtIndex(J, UserK);
            Break;
          end;
        if (not Applied) and (Idx >= 0) and (Idx < FBindings.Count) then
          Applied := RebindAtIndex(Idx, UserK);
        if Applied then
          Inc(Result);
      end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleInputMapManager.DetectBindingConflicts(const OutConflicts: TStrings): Integer;
var
  I, J: Integer;
  A, B: TInputBindingDef;
  Msg: String;
begin
  Result := 0;
  if OutConflicts <> nil then
    OutConflicts.Clear;

  for I := 0 to FBindings.Count - 2 do
  begin
    A := FBindings[I];
    if not IsContextActive(A.ContextId) then
      Continue;
    for J := I + 1 to FBindings.Count - 1 do
    begin
      B := FBindings[J];
      if not SameText(A.ContextId, B.ContextId) then
        Continue;
      if not SameText(A.KeyName, B.KeyName) then
        Continue;
      { Distinct chord modifiers on the same key (e.g. KeyQ vs LeftShift+KeyQ) are valid }
      if not SameText(A.ChordKeyName, B.ChordKeyName) then
        Continue;
      { Distinct Tap vs Hold on the same key is valid in UE Enhanced Input }
      if ((A.TriggerKind = itkTap) and (B.TriggerKind = itkHold)) or
         ((A.TriggerKind = itkHold) and (B.TriggerKind = itkTap)) then
        Continue;

      Inc(Result);
      if OutConflicts <> nil then
      begin
        Msg := Format('Context "%s" binds key "%s" to both "%s" (%s) and "%s" (%s).',
          [A.ContextId, A.KeyName, A.ActionId, InputTriggerToString(A.TriggerKind),
           B.ActionId, InputTriggerToString(B.TriggerKind)]);
        OutConflicts.Add(Msg);
      end;
    end;
  end;
end;

function TCastleInputMapManager.GetConfigJson: String;
var
  Root, Obj: TJSONObject;
  ArrCtx, ArrBind: TJSONArray;
  I: Integer;
  C: TInputMappingContextDef;
  B: TInputBindingDef;
begin
  Root := TJSONObject.Create;
  try
    ArrCtx := TJSONArray.Create;
    for I := 0 to FContexts.Count - 1 do
    begin
      C := FContexts[I];
      Obj := TJSONObject.Create;
      Obj.Add('id', C.ContextId);
      Obj.Add('prio', C.Priority);
      Obj.Add('active', C.Active);
      Obj.Add('consume', C.ConsumeMappedKeys);
      ArrCtx.Add(Obj);
    end;
    Root.Add('contexts', ArrCtx);

    ArrBind := TJSONArray.Create;
    for I := 0 to FBindings.Count - 1 do
    begin
      B := FBindings[I];
      Obj := TJSONObject.Create;
      Obj.Add('ctx', B.ContextId);
      Obj.Add('act', B.ActionId);
      Obj.Add('kind', InputValueKindToString(B.ValueKind));
      Obj.Add('key', B.KeyName);
      Obj.Add('defKey', B.DefaultKeyName);
      Obj.Add('chord', B.ChordKeyName);
      Obj.Add('trig', InputTriggerToString(B.TriggerKind));
      Obj.Add('thresh', B.ThresholdSec);
      Obj.Add('ax', B.AxisContribution.X);
      Obj.Add('ay', B.AxisContribution.Y);
      Obj.Add('dz', B.InnerDeadzone);
      Obj.Add('sat', B.OuterSaturation);
      Obj.Add('exp', B.ResponseExponent);
      Obj.Add('scale', B.ScaleFactor);
      Obj.Add('norm2d', B.NormalizeDigital2D);
      ArrBind.Add(Obj);
    end;
    Root.Add('bindings', ArrBind);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleInputMapManager.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  C: TInputMappingContextDef;
  B: TInputBindingDef;
begin
  if Trim(Value) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then
      Exit;
    Root := TJSONObject(Data);
    ClearAll;

    Arr := Root.Find('contexts', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          C := TInputMappingContextDef.CreateContext(
            Obj.Get('id', 'Default'),
            Obj.Get('prio', 0),
            Obj.Get('active', True),
            Obj.Get('consume', True));
          FContexts.Add(C);
        end;

    Arr := Root.Find('bindings', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          B := TInputBindingDef.CreateDigital(
            Obj.Get('ctx', 'Default'),
            Obj.Get('act', 'Action'),
            Obj.Get('key', 'KeySpace'),
            StringToInputTrigger(Obj.Get('trig', 'Pressed')),
            Obj.Get('thresh', 0.25),
            Obj.Get('chord', ''));
          B.DefaultKeyName := Obj.Get('defKey', B.KeyName);
          B.ValueKind := StringToInputValueKind(Obj.Get('kind', 'Bool'));
          B.AxisContribution := Vector2(Obj.Get('ax', 1.0), Obj.Get('ay', 0.0));
          B.InnerDeadzone := Obj.Get('dz', 0.20);
          B.OuterSaturation := Obj.Get('sat', 0.95);
          B.ResponseExponent := Obj.Get('exp', 1.0);
          B.ScaleFactor := Obj.Get('scale', 1.0);
          B.NormalizeDigital2D := Obj.Get('norm2d', True);
          AddBinding(B);
        end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleInputMapManager.InputSummaryBadge: String;
begin
  Result := Format('[Input:%s %d ctx %d binds]', [
    InputPresetDisplayName(FPreset),
    FContexts.Count,
    FBindings.Count
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleInputMapManager,
    ['Enhanced Input Map Manager']);
end.
