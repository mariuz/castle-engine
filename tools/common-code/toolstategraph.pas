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

{ Design-time authoring, template generation, graph reachability validation,
  and Mermaid @code(stateDiagram-v2) export helpers for
  @link(TCastleStateGraphBehavior) (Phase 288). }
unit ToolStateGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTransform, CastleStateGraph;

type
  { Built-in 1-click gameplay StateTree templates. }
  TStateGraphTemplate = (
    sgtAiPatrolChaseAttack,
    sgtInteractiveDoor,
    sgtUiMenuFlow
  );

  { Discovered @link(TCastleStateGraphBehavior) summary inside a live design. }
  TStateGraphInfo = record
    Graph: TCastleStateGraphBehavior;
    BehaviorName: String;
    ParentTransformName: String;
    GraphLabel: String;
    InitialStateId: String;
    ActiveStateId: String;
    StateCount: Integer;
    TransitionCount: Integer;
    VariableCount: Integer;
  end;
  TStateGraphInfoArray = array of TStateGraphInfo;

  { Static editor & CLI helper methods for @link(TCastleStateGraphBehavior). }
  TStateGraphHelper = class
  public
    { Discover all @link(TCastleStateGraphBehavior) instances in @code(DesignRoot). }
    class function ScanStateGraphs(const DesignRoot: TComponent): TStateGraphInfoArray; static;

    { Resolve the most appropriate @link(TCastleTransform) in a design for
      attaching a new @link(TCastleStateGraphBehavior). }
    class function FindFirstTransformTarget(
      const DesignRoot, PreferredComp: TComponent): TCastleTransform; static;

    { Create and attach a uniquely named @link(TCastleStateGraphBehavior)
      to @code(TargetTransform). }
    class function AttachStateGraphToTransform(
      const TargetTransform: TCastleTransform;
      const DesignOwner: TComponent;
      const BaseLabel: String = 'AI StateTree'): TCastleStateGraphBehavior; static;

    { Populate @code(Graph) with a ready-to-run gameplay StateTree template. }
    class procedure ApplyGameplayTemplate(const Graph: TCastleStateGraphBehavior;
      const Template: TStateGraphTemplate); static;

    { Audit @code(Graph) for missing initial state, broken endpoints,
      undeclared blackboard variables, and unreachable state islands.
      Returns @true when zero warnings are found. }
    class function ValidateGraph(const Graph: TCastleStateGraphBehavior;
      const Warnings: TStrings): Boolean; static;

    { Export @code(Graph) as a Markdown + Mermaid @code(stateDiagram-v2) document. }
    class function FormatGraphMarkdown(const Graph: TCastleStateGraphBehavior): String; static;
  end;

implementation

uses
  CastleUIControls, CastleControls, CastleViewport, CastleUtils;

procedure CollectStateGraphsRecursive(const C: TComponent;
  var List: TStateGraphInfoArray);

  procedure AddGraph(const G: TCastleStateGraphBehavior);
  var
    I, N: Integer;
    Info: TStateGraphInfo;
  begin
    if (G = nil) or (csTransient in G.ComponentStyle) then
      Exit;
    for I := 0 to High(List) do
      if List[I].Graph = G then
        Exit;

    Info := Default(TStateGraphInfo);
    Info.Graph := G;
    Info.BehaviorName := G.Name;
    if (G.Parent <> nil) and (G.Parent.Name <> '') then
      Info.ParentTransformName := G.Parent.Name
    else if G.Parent <> nil then
      Info.ParentTransformName := G.Parent.ClassName
    else
      Info.ParentTransformName := '<detached>';
    Info.GraphLabel := G.GraphLabel;
    Info.InitialStateId := G.InitialStateId;
    Info.ActiveStateId := G.ActiveStateId;
    Info.StateCount := G.StateCount;
    Info.TransitionCount := G.TransitionCount;
    Info.VariableCount := G.VariableCount;

    N := Length(List);
    SetLength(List, N + 1);
    List[N] := Info;
  end;

var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  VP: TCastleViewport;
begin
  if (C = nil) or (csTransient in C.ComponentStyle) then
    Exit;

  if C is TCastleStateGraphBehavior then
    AddGraph(TCastleStateGraphBehavior(C));

  for I := 0 to C.ComponentCount - 1 do
    CollectStateGraphsRecursive(C.Components[I], List);

  if C is TCastleTransform then
  begin
    T := TCastleTransform(C);
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleStateGraphBehavior then
        AddGraph(TCastleStateGraphBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
      CollectStateGraphsRecursive(T[I], List);
  end else
  if C is TCastleUserInterface then
  begin
    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        CollectStateGraphsRecursive(VP.Items, List);
    end;
    UI := TCastleUserInterface(C);
    for I := 0 to UI.ControlsCount - 1 do
      CollectStateGraphsRecursive(UI.Controls[I], List);
  end;
end;

class function TStateGraphHelper.ScanStateGraphs(
  const DesignRoot: TComponent): TStateGraphInfoArray;
begin
  Result := nil;
  CollectStateGraphsRecursive(DesignRoot, Result);
end;

class function TStateGraphHelper.FindFirstTransformTarget(
  const DesignRoot, PreferredComp: TComponent): TCastleTransform;
var
  I: Integer;
  VP: TCastleViewport;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if PreferredComp is TCastleTransform then
    Exit(TCastleTransform(PreferredComp));
  if (PreferredComp is TCastleBehavior) and
     (TCastleBehavior(PreferredComp).Parent <> nil) then
    Exit(TCastleBehavior(PreferredComp).Parent);

  if DesignRoot is TCastleTransform then
    Exit(TCastleTransform(DesignRoot));

  if DesignRoot is TCastleViewport then
  begin
    VP := TCastleViewport(DesignRoot);
    if VP.Items <> nil then
    begin
      { Prefer non-camera gameplay entities over the default viewport camera }
      for I := 0 to VP.Items.Count - 1 do
        if (not (csTransient in VP.Items[I].ComponentStyle)) and
           (not (VP.Items[I] is TCastleCamera)) then
          Exit(VP.Items[I]);
      for I := 0 to VP.Items.Count - 1 do
        if not (csTransient in VP.Items[I].ComponentStyle) then
          Exit(VP.Items[I]);
      Exit(VP.Items);
    end;
  end;

  if DesignRoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(DesignRoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindFirstTransformTarget(UI.Controls[I], nil);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function ProposeUniqueBehaviorName(const AOwner: TComponent;
  const BaseName: String): String;
var
  Idx: Integer;
begin
  if (AOwner = nil) or (AOwner.FindComponent(BaseName) = nil) then
    Exit(BaseName);
  Idx := 1;
  repeat
    Result := BaseName + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TStateGraphHelper.AttachStateGraphToTransform(
  const TargetTransform: TCastleTransform;
  const DesignOwner: TComponent;
  const BaseLabel: String): TCastleStateGraphBehavior;
var
  UseOwner: TComponent;
begin
  Result := nil;
  if TargetTransform = nil then
    Exit;
  if DesignOwner <> nil then
    UseOwner := DesignOwner
  else
    UseOwner := TargetTransform.Owner;

  Result := TCastleStateGraphBehavior.Create(UseOwner);
  Result.Name := ProposeUniqueBehaviorName(UseOwner, 'StateGraphBehavior');
  Result.GraphLabel := BaseLabel;
  TargetTransform.AddBehavior(Result);
end;

class procedure TStateGraphHelper.ApplyGameplayTemplate(
  const Graph: TCastleStateGraphBehavior; const Template: TStateGraphTemplate);
begin
  if Graph = nil then
    Exit;

  Graph.ClearGraph;

  case Template of
    sgtAiPatrolChaseAttack:
      begin
        Graph.GraphLabel := 'AI Patrol / Chase / Attack';
        Graph.AddOrUpdateVariable('PlayerDistance', sbkFloat, '25.0');
        Graph.AddOrUpdateVariable('Health', sbkFloat, '100.0');
        Graph.AddOrUpdateVariable('Alerted', sbkBool, 'false');

        Graph.AddOrUpdateState('Idle', 'Idle Guard', 60, 140,
          'Stand watch before beginning patrol route');
        Graph.AddOrUpdateState('Patrol', 'Patrol Route', 270, 140,
          'Walk waypoint loop until target enters sight radius');
        Graph.AddOrUpdateState('Chase', 'Pursue Target', 490, 80,
          'Sprint toward player while closing melee distance');
        Graph.AddOrUpdateState('Attack', 'Melee Strike', 700, 140,
          'Execute melee combo while in strike range');
        Graph.AddOrUpdateState('Flee', 'Retreat / Low HP', 490, 260,
          'High-priority Any-State interrupt when Health <= 20');
        Graph.InitialStateId := 'Idle';

        Graph.AddEntryAction('Idle', sakPlayAnimation, '$Parent', 'idle', '', true);
        Graph.AddEntryAction('Patrol', sakPlayAnimation, '$Parent', 'walk', '', true);
        Graph.AddEntryAction('Chase', sakPlayAnimation, '$Parent', 'run', '', true);
        Graph.AddEntryAction('Chase', sakSetBlackboardVar, '', 'Alerted', 'true', false);
        Graph.AddEntryAction('Attack', sakPlayAnimation, '$Parent', 'attack', '', true);
        Graph.AddEntryAction('Attack', sakFireCue, '', 'OnMeleeStrike', 'heavy', false);
        Graph.AddEntryAction('Flee', sakPlayAnimation, '$Parent', 'flee', '', true);
        Graph.AddEntryAction('Flee', sakFireCue, '', 'OnLowHealthRetreat', '', false);

        { High-priority wildcard interrupt from any state }
        Graph.AddTransition('*', 'Flee', scoLessOrEqual, 'Health', '20', 0.0, 10);
        { Standard state transitions }
        Graph.AddTransition('Idle', 'Patrol', scoAlways, '', '', 2.0, 0);
        Graph.AddTransition('Idle', 'Chase', scoLessOrEqual, 'PlayerDistance', '12', 0.0, 2);
        Graph.AddTransition('Patrol', 'Chase', scoLessOrEqual, 'PlayerDistance', '12', 0.0, 2);
        Graph.AddTransition('Chase', 'Attack', scoLessOrEqual, 'PlayerDistance', '2.5', 0.0, 3);
        Graph.AddTransition('Attack', 'Chase', scoGreater, 'PlayerDistance', '3.0', 0.4, 1);
        Graph.AddTransition('Chase', 'Patrol', scoGreater, 'PlayerDistance', '18', 1.0, 0);
        Graph.AddTransition('Flee', 'Patrol', scoGreater, 'Health', '50', 1.0, 0);
      end;

    sgtInteractiveDoor:
      begin
        Graph.GraphLabel := 'Interactive Door Mechanism';
        Graph.AddOrUpdateVariable('IsLocked', sbkBool, 'false');
        Graph.AddOrUpdateVariable('InteractPressed', sbkBool, 'false');

        Graph.AddOrUpdateState('Closed', 'Door Closed', 70, 140,
          'Awaiting player interaction');
        Graph.AddOrUpdateState('Locked', 'Door Locked', 70, 270,
          'Locked feedback state');
        Graph.AddOrUpdateState('Opening', 'Swinging Open', 310, 140,
          'Playing door-open animation');
        Graph.AddOrUpdateState('Open', 'Door Open', 550, 140,
          'Auto-closes after 3.0s or on second interact');
        Graph.InitialStateId := 'Closed';

        Graph.AddEntryAction('Closed', sakSetBlackboardVar, '', 'InteractPressed', 'false', false);
        Graph.AddEntryAction('Opening', sakSetBlackboardVar, '', 'InteractPressed', 'false', false);
        Graph.AddEntryAction('Opening', sakPlayAnimation, '$Parent', 'door_open', '', false);
        Graph.AddEntryAction('Opening', sakFireCue, '', 'PlayDoorCreak', '', false);
        Graph.AddEntryAction('Open', sakSetBlackboardVar, '', 'InteractPressed', 'false', false);
        Graph.AddEntryAction('Locked', sakSetBlackboardVar, '', 'InteractPressed', 'false', false);
        Graph.AddEntryAction('Locked', sakFireCue, '', 'PlayLockedRattle', '', false);

        Graph.AddTransition('Closed', 'Locked', scoEqual, 'IsLocked', 'true', 0.0, 5);
        Graph.AddTransition('Locked', 'Closed', scoEqual, 'IsLocked', 'false', 0.0, 5);
        Graph.AddTransition('Closed', 'Opening', scoEqual, 'InteractPressed', 'true', 0.0, 1);
        Graph.AddTransition('Opening', 'Open', scoAlways, '', '', 1.0, 0);
        Graph.AddTransition('Open', 'Closed', scoEqual, 'InteractPressed', 'true', 0.0, 2);
        Graph.AddTransition('Open', 'Closed', scoAlways, '', '', 3.0, 0);
      end;

    sgtUiMenuFlow:
      begin
        Graph.GraphLabel := 'UI Screen / Dialog Flow';
        Graph.AddOrUpdateVariable('ShowRequested', sbkBool, 'false');
        Graph.AddOrUpdateVariable('DismissRequested', sbkBool, 'false');

        Graph.AddOrUpdateState('Hidden', 'Hidden', 80, 150, 'Dialog off-screen');
        Graph.AddOrUpdateState('Intro', 'Intro Reveal', 310, 150, 'Entrance transition');
        Graph.AddOrUpdateState('Active', 'Interactive', 540, 150, 'Accepting user input');
        Graph.InitialStateId := 'Hidden';

        Graph.AddEntryAction('Hidden', sakSetBlackboardVar, '', 'DismissRequested', 'false', false);
        Graph.AddEntryAction('Intro', sakSetBlackboardVar, '', 'ShowRequested', 'false', false);
        Graph.AddEntryAction('Intro', sakFireCue, '', 'OnDialogIntro', '', false);
        Graph.AddEntryAction('Active', sakFireCue, '', 'OnDialogReady', '', false);

        Graph.AddTransition('Hidden', 'Intro', scoEqual, 'ShowRequested', 'true', 0.0, 1);
        Graph.AddTransition('Intro', 'Active', scoAlways, '', '', 0.35, 0);
        Graph.AddTransition('Active', 'Hidden', scoEqual, 'DismissRequested', 'true', 0.0, 1);
      end;
  end;
end;

class function TStateGraphHelper.ValidateGraph(
  const Graph: TCastleStateGraphBehavior; const Warnings: TStrings): Boolean;
var
  I, J, InitIdx: Integer;
  Reachable: array of Boolean;
  Changed: Boolean;
  T: TStateTransitionData;
  S: TStateNodeData;
begin
  if Warnings <> nil then
    Warnings.Clear;
  if Graph = nil then
  begin
    if Warnings <> nil then
      Warnings.Add('StateGraph behavior reference is nil.');
    Exit(false);
  end;

  if Graph.StateCount = 0 then
  begin
    if Warnings <> nil then
      Warnings.Add('Graph has 0 states defined.');
    Exit(false);
  end;

  InitIdx := Graph.FindStateIndex(Graph.InitialStateId);
  if InitIdx < 0 then
  begin
    if Warnings <> nil then
      Warnings.Add(Format('InitialStateId "%s" does not match any state node.',
        [Graph.InitialStateId]));
  end;

  for I := 0 to Graph.TransitionCount - 1 do
  begin
    T := Graph.GetTransition(I);
    if (T.FromStateId <> '*') and (Graph.FindStateIndex(T.FromStateId) < 0) then
      if Warnings <> nil then
        Warnings.Add(Format('Transition #%d references unknown source state "%s".',
          [I, T.FromStateId]));
    if Graph.FindStateIndex(T.ToStateId) < 0 then
      if Warnings <> nil then
        Warnings.Add(Format('Transition #%d references unknown target state "%s".',
          [I, T.ToStateId]));
    if (T.Op <> scoAlways) and (Graph.FindVariableIndex(T.VarName) < 0) then
      if Warnings <> nil then
        Warnings.Add(Format('Transition #%d (%s -> %s) references undeclared blackboard variable "%s".',
          [I, T.FromStateId, T.ToStateId, T.VarName]));
  end;

  SetLength(Reachable, Graph.StateCount);
  for I := 0 to High(Reachable) do
    Reachable[I] := false;
  if InitIdx >= 0 then
    Reachable[InitIdx] := true
  else
    Reachable[0] := true;

  { Any state targeted by a '*' wildcard rule is reachable from the initial state }
  for I := 0 to Graph.TransitionCount - 1 do
  begin
    T := Graph.GetTransition(I);
    if T.FromStateId = '*' then
    begin
      J := Graph.FindStateIndex(T.ToStateId);
      if J >= 0 then
        Reachable[J] := true;
    end;
  end;

  repeat
    Changed := false;
    for I := 0 to Graph.TransitionCount - 1 do
    begin
      T := Graph.GetTransition(I);
      if T.FromStateId = '*' then
        Continue;
      InitIdx := Graph.FindStateIndex(T.FromStateId);
      J := Graph.FindStateIndex(T.ToStateId);
      if (InitIdx >= 0) and (J >= 0) and Reachable[InitIdx] and (not Reachable[J]) then
      begin
        Reachable[J] := true;
        Changed := true;
      end;
    end;
  until not Changed;

  for I := 0 to Graph.StateCount - 1 do
    if not Reachable[I] then
    begin
      S := Graph.GetState(I);
      if Warnings <> nil then
        Warnings.Add(Format('State "%s" is unreachable from InitialStateId "%s".',
          [S.StateId, Graph.InitialStateId]));
    end;

  Result := (Warnings = nil) or (Warnings.Count = 0);
end;

class function TStateGraphHelper.FormatGraphMarkdown(
  const Graph: TCastleStateGraphBehavior): String;
var
  SB: TStringBuilder;
  I: Integer;
  V: TStateBlackboardVarData;
  S: TStateNodeData;
  T: TStateTransitionData;
  SrcLabel: String;
begin
  if Graph = nil then
    Exit('');
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('## StateGraph: %s (`%s`)', [Graph.GraphLabel, Graph.Name]));
    SB.AppendLine(Format('- **Initial State:** `%s` | **Active State:** `%s` | **States:** %d | **Transitions:** %d',
      [Graph.InitialStateId, Graph.ActiveStateId, Graph.StateCount, Graph.TransitionCount]));
    SB.AppendLine;

    SB.AppendLine('### Mermaid State Diagram');
    SB.AppendLine('```mermaid');
    SB.AppendLine('stateDiagram-v2');
    if Graph.InitialStateId <> '' then
      SB.AppendLine(Format('  [*] --> %s', [Graph.InitialStateId]));
    for I := 0 to Graph.StateCount - 1 do
    begin
      S := Graph.GetState(I);
      if (S.DisplayName <> '') and (not SameText(S.DisplayName, S.StateId)) then
        SB.AppendLine(Format('  %s : %s', [S.StateId, S.DisplayName]));
    end;
    for I := 0 to Graph.TransitionCount - 1 do
    begin
      T := Graph.GetTransition(I);
      if T.FromStateId = '*' then
        SrcLabel := 'AnyState'
      else
        SrcLabel := T.FromStateId;
      SB.AppendLine(Format('  %s --> %s : %s',
        [SrcLabel, T.ToStateId, FormatTransitionSummary(T)]));
    end;
    SB.AppendLine('```');
    SB.AppendLine;

    if Graph.VariableCount > 0 then
    begin
      SB.AppendLine('### Blackboard Variables');
      SB.AppendLine('| Variable | Type | Default | Live Value |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to Graph.VariableCount - 1 do
      begin
        V := Graph.GetVariable(I);
        SB.AppendLine(Format('| `%s` | `%s` | `%s` | `%s` |',
          [V.VarName, StateVarKindToString(V.Kind), V.DefaultStr,
           Graph.FormatBlackboardValue(V.VarName)]));
      end;
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
