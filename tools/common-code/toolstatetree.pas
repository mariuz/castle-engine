{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for the StateTree Hierarchical AI Decision Tree,
  Enter-Conditions, Evaluators & Task Tick Studio (Phase 337). }
unit ToolStateTree;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleStateTree;

type
  TStateTreeStudioSummary = record
    TreeCount: Integer;
    TotalStateNodes: Integer;
    TotalTransitionsTaken: Integer;
    ValidationWarningsCount: Integer;
  end;

  TStateTreeHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstStateTree(const ARoot: TComponent): TCastleStateTreeBehavior; static;

    class function SpawnTacticalGuardStateTreeDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AGuard, AIntruder: TCastleTransform;
      out ATree: TCastleStateTreeBehavior): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TStateTreeStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TStateTreeHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TStateTreeHelper.FindFirstStateTree(
  const ARoot: TComponent): TCastleStateTreeBehavior;

  function ScanRec(const T: TCastleTransform): TCastleStateTreeBehavior;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleStateTreeBehavior then
        Exit(TCastleStateTreeBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TStateTreeHelper.SpawnTacticalGuardStateTreeDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AGuard, AIntruder: TCastleTransform;
  out ATree: TCastleStateTreeBehavior): Boolean;
var
  RootT: TCastleTransform;
  GuardCyl: TCastleCylinder;
  IntruderBox: TCastleBox;
begin
  AGuard := nil;
  AIntruder := nil;
  ATree := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  IntruderBox := TCastleBox.Create(ADesignOwner);
  IntruderBox.Name := MakeUniqueName(ADesignOwner, 'StateTreeIntruderTarget');
  IntruderBox.Size := Vector3(0.9, 1.8, 0.9);
  IntruderBox.Translation := Vector3(0.0, 0.9, 22.0);
  IntruderBox.Color := Vector4(0.92, 0.32, 0.26, 1.0);
  RootT.Add(IntruderBox);
  AIntruder := IntruderBox;

  GuardCyl := TCastleCylinder.Create(ADesignOwner);
  GuardCyl.Name := MakeUniqueName(ADesignOwner, 'StateTreeSentryGuard');
  GuardCyl.Radius := 0.45;
  GuardCyl.Height := 1.85;
  GuardCyl.Translation := Vector3(0.0, 0.925, 0.0);
  GuardCyl.Color := Vector4(0.28, 0.68, 0.92, 1.0);
  RootT.Add(GuardCyl);
  AGuard := GuardCyl;

  ATree := TCastleStateTreeBehavior.Create(ADesignOwner);
  ATree.Name := MakeUniqueName(ADesignOwner, 'SentryStateTree');
  ATree.TargetTransformName := IntruderBox.Name;
  GuardCyl.AddBehavior(ATree);
  ATree.ApplyPreset(stpTacticalGuardSquad);
  Result := True;
end;

class function TStateTreeHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TStateTreeStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    ST: TCastleStateTreeBehavior;
    LocalWarns: TStringList;
  begin
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleStateTreeBehavior then
      begin
        ST := TCastleStateTreeBehavior(T.Behaviors[I]);
        Inc(Result.TreeCount);
        Result.TotalStateNodes := Result.TotalStateNodes + ST.NodeCount;
        Result.TotalTransitionsTaken := Result.TotalTransitionsTaken + ST.TransitionCount;
        LocalWarns := TStringList.Create;
        try
          if not ST.ValidateTree(LocalWarns) then
          begin
            Result.ValidationWarningsCount := Result.ValidationWarningsCount + LocalWarns.Count;
            if AWarnings <> nil then
              AWarnings.AddStrings(LocalWarns);
          end;
        finally
          FreeAndNil(LocalWarns);
        end;
      end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TStateTreeStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TStateTreeHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TStateTreeStudioSummary;
  ST: TCastleStateTreeBehavior;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    ST := FindFirstStateTree(ARoot);
    SB.AppendLine('# Castle Game Engine — StateTree Hierarchical AI Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **StateTree Behaviors**: `%d` (`%d` total nodes, `%d` transitions)', [
      Sum.TreeCount, Sum.TotalStateNodes, Sum.TotalTransitionsTaken]));
    if ST <> nil then
    begin
      SB.AppendLine(Format('- **Active Lineage Path**: `%s` (`%s`)', [
        ST.ActiveStatePath, ST.ActiveTaskAction]));
      SB.AppendLine;
      SB.AppendLine('```mermaid');
      SB.Append(ST.ExportMermaidHierarchyDiagram);
      SB.AppendLine('```');
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Validation Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
