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

{ Stateless scene authoring, Behavior Tree tick driver, and diagnostic helper
  for the Unreal Engine 5.5-style Behavior Tree & Blackboard Visual Editor
  (@link(TBehaviorTreeHelper), @link(TBehaviorTreeAuditReport))
  (Phase 384 — UE 5.5 UBehaviorTree Parity + 27th MCP Tool). }
unit ToolBehaviorTree;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleBehaviorTree;

type
  { Summary audit across all @link(TCastleBehaviorTree) instances in the design. }
  TBehaviorTreeAuditReport = record
    TreeCount: Integer;
    ValidTreeCount: Integer;
    ErrorTreeCount: Integer;
    TotalNodeCount: Integer;
    TotalBlackboardKeys: Integer;
    TotalObserverAborts: Integer;
    TotalServiceTicks: Integer;
  end;

  { Scene spawner, batch Behavior Tree auditor, and Markdown report builder. }
  TBehaviorTreeHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class function FindFirstBehaviorTree(const ADesignRoot: TComponent): TCastleBehaviorTree; static;
    class function FindBehaviorTreeByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleBehaviorTree; static;
    class procedure CollectBehaviorTrees(const ADesignRoot: TComponent;
      const AList: TList); static;

    class function SpawnBehaviorTreePresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TBehaviorTreePreset;
      const AWorldPos: TVector3): TCastleBehaviorTree; static;

    class function AuditBehaviorTreesInDesign(
      const ADesignRoot: TComponent): TBehaviorTreeAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedTree: TCastleBehaviorTree): String; static;
  end;

implementation

uses
  Math, CastleUtils, CastleClassUtils, CastleUIControls;

class function TBehaviorTreeHelper.FindParentViewportItems(
  const ADesignRoot: TComponent): TCastleTransform;

  function SearchVp(const C: TComponent): TCastleViewport;
  var
    UI: TCastleUserInterface;
    I: Integer;
  begin
    Result := nil;
    if C = nil then Exit;
    if C is TCastleViewport then Exit(TCastleViewport(C));
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := SearchVp(UI.Controls[I]);
        if Result <> nil then Exit;
      end;
    end;
  end;

var
  VP: TCastleViewport;
begin
  Result := nil;
  if ADesignRoot = nil then Exit;
  if ADesignRoot is TCastleTransform then
    Exit(TCastleTransform(ADesignRoot));
  VP := SearchVp(ADesignRoot);
  if VP <> nil then
    Result := VP.Items;
end;

class procedure TBehaviorTreeHelper.CollectBehaviorTrees(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleBehaviorTree) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Scan(UI.Controls[I]);
    end;
    if C is TCastleViewport then
      Scan(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class function TBehaviorTreeHelper.FindFirstBehaviorTree(
  const ADesignRoot: TComponent): TCastleBehaviorTree;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectBehaviorTrees(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleBehaviorTree(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TBehaviorTreeHelper.FindBehaviorTreeByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleBehaviorTree;
var
  L: TList;
  I: Integer;
  Found: TComponent;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstBehaviorTree(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleBehaviorTree then
      Exit(TCastleBehaviorTree(Found));
  end;

  L := TList.Create;
  try
    CollectBehaviorTrees(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleBehaviorTree(L[I]).Name, AName) then
        Exit(TCastleBehaviorTree(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TBehaviorTreePreset;
  const AWorldPos: TVector3): TCastleBehaviorTree;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleBehaviorTree.Create(ADesignOwner);
  case APreset of
    btpSimpleParallelSuppressAndMove: BaseName := 'BT_ParallelAdvance';
    btpAmmoReloadFallbackSequence:    BaseName := 'BT_AmmoReloadAI';
  else
    BaseName := 'BT_TacticalGuard';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleBehaviorTree, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TBehaviorTreeHelper.AuditBehaviorTreesInDesign(
  const ADesignRoot: TComponent): TBehaviorTreeAuditReport;
var
  L: TList;
  BT: TCastleBehaviorTree;
  I: Integer;
begin
  Result := Default(TBehaviorTreeAuditReport);
  L := TList.Create;
  try
    CollectBehaviorTrees(ADesignRoot, L);
    Result.TreeCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      BT := TCastleBehaviorTree(L[I]);
      if BT.LastTreeValid then
        Inc(Result.ValidTreeCount)
      else
        Inc(Result.ErrorTreeCount);
      Inc(Result.TotalNodeCount, Length(BT.Nodes));
      Inc(Result.TotalBlackboardKeys, Length(BT.Blackboard));
      Inc(Result.TotalObserverAborts, BT.AbortCount);
      Inc(Result.TotalServiceTicks, BT.ServiceTickCount);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TBehaviorTreeHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedTree: TCastleBehaviorTree): String;
var
  Audit: TBehaviorTreeAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditBehaviorTreesInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Behavior Tree & Blackboard Report (Phase 384 — UE 5.5 UBehaviorTree Parity)');
    SB.Add('');
    SB.Add(Format('- **Behavior Trees**: `%d` (`%d` Valid, `%d` Errors)',
      [Audit.TreeCount, Audit.ValidTreeCount, Audit.ErrorTreeCount]));
    SB.Add(Format('- **Total Nodes / Blackboard Keys**: `%d` / `%d`',
      [Audit.TotalNodeCount, Audit.TotalBlackboardKeys]));
    SB.Add(Format('- **Observer Aborts / Service Ticks**: `%d` / `%d`',
      [Audit.TotalObserverAborts, Audit.TotalServiceTicks]));
    if ASelectedTree <> nil then
    begin
      SB.Add('');
      SB.Add('## Active Tree: `' + ASelectedTree.Name + '` ' + ASelectedTree.BehaviorTreeSummaryBadge);
      for I := 0 to High(ASelectedTree.Blackboard) do
        SB.Add(Format('- BB `%s` = `%s`',
          [ASelectedTree.Blackboard[I].KeyName, ASelectedTree.Blackboard[I].ValueAsText]));
      if ASelectedTree.ExecutionLog.Count > 0 then
      begin
        SB.Add('');
        SB.Add('### Observer Aborts & Service Trace');
        for I := Max(0, ASelectedTree.ExecutionLog.Count - 8) to ASelectedTree.ExecutionLog.Count - 1 do
          SB.Add('- `' + ASelectedTree.ExecutionLog[I] + '`');
      end;
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
