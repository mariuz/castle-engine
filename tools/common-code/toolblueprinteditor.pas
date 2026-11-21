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

{ Stateless scene authoring, multi-Blueprint compiler, and diagnostic helper for
  the Unreal Engine 5.5-style Blueprint Visual Scripting Editor
  (@link(TBlueprintEditorHelper), @link(TBlueprintSceneAuditReport))
  (Phase 381 — UE 5.5 UBlueprint Parity + 24th MCP Tool). }
unit ToolBlueprintEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleBlueprint;

type
  { Summary audit across all @link(TCastleBlueprint) instances in the open design. }
  TBlueprintSceneAuditReport = record
    BlueprintCount: Integer;
    CompiledOkCount: Integer;
    ErrorBlueprintCount: Integer;
    DirtyBlueprintCount: Integer;
    TotalNodeCount: Integer;
    TotalVariableCount: Integer;
    TotalConstructionMeshes: Integer;
    PausedBreakpointCount: Integer;
  end;

  { Scene spawner, batch Blueprint compiler, and Markdown auditor. }
  TBlueprintEditorHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class function FindFirstBlueprint(const ADesignRoot: TComponent): TCastleBlueprint; static;
    class function FindBlueprintByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleBlueprint; static;
    class procedure CollectBlueprints(const ADesignRoot: TComponent;
      const AList: TList); static;

    class function SpawnBlueprintPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TBlueprintPreset;
      const AWorldPos: TVector3): TCastleBlueprint; static;

    class function CompileAllBlueprintsInDesign(
      const ADesignRoot: TComponent;
      out OutErrorMessages: String): TBlueprintSceneAuditReport; static;

    class function AuditBlueprintsInDesign(
      const ADesignRoot: TComponent): TBlueprintSceneAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedBp: TCastleBlueprint): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TBlueprintEditorHelper.FindParentViewportItems(
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

class procedure TBlueprintEditorHelper.CollectBlueprints(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleBlueprint) and (AList.IndexOf(C) < 0) then
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

class function TBlueprintEditorHelper.FindFirstBlueprint(
  const ADesignRoot: TComponent): TCastleBlueprint;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectBlueprints(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleBlueprint(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TBlueprintEditorHelper.FindBlueprintByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleBlueprint;
var
  L: TList;
  I: Integer;
  Found: TComponent;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstBlueprint(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleBlueprint then
      Exit(TCastleBlueprint(Found));
  end;

  L := TList.Create;
  try
    CollectBlueprints(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleBlueprint(L[I]).Name, AName) or
         SameText(TCastleBlueprint(L[I]).BlueprintClassName, AName) then
        Exit(TCastleBlueprint(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TBlueprintPreset;
  const AWorldPos: TVector3): TCastleBlueprint;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleBlueprint.Create(ADesignOwner);
  case APreset of
    bppSlidingDoorTimelineAndGate: BaseName := 'BP_SlidingDoor';
    bppPatrolBranchAndLatentDelay: BaseName := 'BP_WarmupBranch';
  else
    BaseName := 'BP_ColonnadeSpin';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleBlueprint, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TBlueprintEditorHelper.CompileAllBlueprintsInDesign(
  const ADesignRoot: TComponent;
  out OutErrorMessages: String): TBlueprintSceneAuditReport;
var
  L: TList;
  ErrList: TStringList;
  BP: TCastleBlueprint;
  I, E: Integer;
begin
  OutErrorMessages := '';
  L := TList.Create;
  ErrList := TStringList.Create;
  try
    CollectBlueprints(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
    begin
      BP := TCastleBlueprint(L[I]);
      if not BP.CompileBlueprint then
        for E := 0 to BP.CompileErrors.Count - 1 do
          ErrList.Add(Format('[%s] %s', [BP.Name, BP.CompileErrors[E]]))
      else if BP.AutoRunConstruction then
        BP.RunConstructionScript;
    end;
    OutErrorMessages := Trim(ErrList.Text);
    Result := AuditBlueprintsInDesign(ADesignRoot);
  finally
    FreeAndNil(ErrList);
    FreeAndNil(L);
  end;
end;

class function TBlueprintEditorHelper.AuditBlueprintsInDesign(
  const ADesignRoot: TComponent): TBlueprintSceneAuditReport;
var
  L: TList;
  BP: TCastleBlueprint;
  I: Integer;
begin
  Result := Default(TBlueprintSceneAuditReport);
  L := TList.Create;
  try
    CollectBlueprints(ADesignRoot, L);
    Result.BlueprintCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      BP := TCastleBlueprint(L[I]);
      case BP.CompileStatus of
        bcsUpToDate: Inc(Result.CompiledOkCount);
        bcsError:    Inc(Result.ErrorBlueprintCount);
      else
        Inc(Result.DirtyBlueprintCount);
      end;
      Inc(Result.TotalNodeCount, Length(BP.Nodes));
      Inc(Result.TotalVariableCount, Length(BP.Variables));
      Inc(Result.TotalConstructionMeshes, BP.ConstructionSpawnCount);
      if BP.IsPausedAtBreakpoint then
        Inc(Result.PausedBreakpointCount);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TBlueprintEditorHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedBp: TCastleBlueprint): String;
var
  Audit: TBlueprintSceneAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditBlueprintsInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Blueprint Visual Scripting Editor Report (Phase 381 — UE 5.5 UBlueprint Parity)');
    SB.Add('');
    SB.Add(Format('- **Scene Blueprints**: `%d` (`%d` Compiled OK, `%d` Errors, `%d` Dirty)',
      [Audit.BlueprintCount, Audit.CompiledOkCount, Audit.ErrorBlueprintCount, Audit.DirtyBlueprintCount]));
    SB.Add(Format('- **Total Nodes / Variables**: `%d` Nodes / `%d` Variables',
      [Audit.TotalNodeCount, Audit.TotalVariableCount]));
    SB.Add(Format('- **Construction Script Meshes**: `%d` procedural components',
      [Audit.TotalConstructionMeshes]));
    if ASelectedBp <> nil then
    begin
      SB.Add('');
      SB.Add('## Active Blueprint: `' + ASelectedBp.Name + '` (`' + ASelectedBp.BlueprintClassName + '`)');
      SB.Add('- **Badge**: `' + ASelectedBp.BlueprintSummaryBadge + '`');
      SB.Add(Format('- **Exec Links / Data Links**: `%d` / `%d`',
        [Length(ASelectedBp.ExecLinks), Length(ASelectedBp.DataLinks)]));
      if ASelectedBp.CompileErrors.Count > 0 then
      begin
        SB.Add('');
        SB.Add('### Compiler Errors');
        for I := 0 to ASelectedBp.CompileErrors.Count - 1 do
          SB.Add('- ' + ASelectedBp.CompileErrors[I]);
      end;
      if ASelectedBp.PrintLog.Count > 0 then
      begin
        SB.Add('');
        SB.Add('### Execution Print Log');
        for I := 0 to ASelectedBp.PrintLog.Count - 1 do
          SB.Add('- `' + ASelectedBp.PrintLog[I] + '`');
      end;
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
