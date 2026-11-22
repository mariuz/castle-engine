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

{ Stateless scene authoring, stack simulation driver, and diagnostic helper for
  the Unreal Engine 5.5-style Niagara Modular Emitter Stack & Curve Editor
  (@link(TNiagaraStackHelper), @link(TNiagaraSceneAuditReport))
  (Phase 385 — UE 5.5 UNiagaraSystem Parity + 28th MCP Tool). }
unit ToolNiagaraStack;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleNiagaraStack;

type
  { Summary audit across all @link(TCastleNiagaraSystem) emitters in the design. }
  TNiagaraSceneAuditReport = record
    SystemCount: Integer;
    TotalModuleCount: Integer;
    EnabledModuleCount: Integer;
    TotalActiveParticles: Integer;
    TotalCollisionEvents: Integer;
    TotalSubSparksSpawned: Integer;
  end;

  { Scene spawner, batch Niagara auditor, and Markdown report builder. }
  TNiagaraStackHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class function FindFirstNiagaraSystem(const ADesignRoot: TComponent): TCastleNiagaraSystem; static;
    class function FindNiagaraSystemByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleNiagaraSystem; static;
    class procedure CollectNiagaraSystems(const ADesignRoot: TComponent;
      const AList: TList); static;

    class function SpawnNiagaraPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TNiagaraSystemPreset;
      const AWorldPos: TVector3): TCastleNiagaraSystem; static;

    class function AuditNiagaraSystemsInDesign(
      const ADesignRoot: TComponent): TNiagaraSceneAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedSys: TCastleNiagaraSystem): String; static;
  end;

implementation

uses
  Math, CastleUtils, CastleClassUtils, CastleUIControls;

class function TNiagaraStackHelper.FindParentViewportItems(
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

class procedure TNiagaraStackHelper.CollectNiagaraSystems(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleNiagaraSystem) and (AList.IndexOf(C) < 0) then
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

class function TNiagaraStackHelper.FindFirstNiagaraSystem(
  const ADesignRoot: TComponent): TCastleNiagaraSystem;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectNiagaraSystems(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleNiagaraSystem(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TNiagaraStackHelper.FindNiagaraSystemByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleNiagaraSystem;
var
  L: TList;
  I: Integer;
  Found: TComponent;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstNiagaraSystem(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleNiagaraSystem then
      Exit(TCastleNiagaraSystem(Found));
  end;

  L := TList.Create;
  try
    CollectNiagaraSystems(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleNiagaraSystem(L[I]).Name, AName) then
        Exit(TCastleNiagaraSystem(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TNiagaraSystemPreset;
  const AWorldPos: TVector3): TCastleNiagaraSystem;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleNiagaraSystem.Create(ADesignOwner);
  case APreset of
    nspAnvilSparksCollisionBurst: BaseName := 'NS_AnvilCollisionSparks';
    nspCampfireEmberColumn:       BaseName := 'NS_CampfireEmbers';
  else
    BaseName := 'NS_ArcaneVortex';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleNiagaraSystem, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TNiagaraStackHelper.AuditNiagaraSystemsInDesign(
  const ADesignRoot: TComponent): TNiagaraSceneAuditReport;
var
  L: TList;
  NS: TCastleNiagaraSystem;
  I, M: Integer;
begin
  Result := Default(TNiagaraSceneAuditReport);
  L := TList.Create;
  try
    CollectNiagaraSystems(ADesignRoot, L);
    Result.SystemCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      NS := TCastleNiagaraSystem(L[I]);
      Inc(Result.TotalModuleCount, Length(NS.Modules));
      for M := 0 to High(NS.Modules) do
        if NS.Modules[M].Enabled then
          Inc(Result.EnabledModuleCount);
      Inc(Result.TotalActiveParticles, NS.ActiveParticleCount);
      Inc(Result.TotalCollisionEvents, NS.CollisionEventCount);
      Inc(Result.TotalSubSparksSpawned, NS.SubSparkSpawnCount);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TNiagaraStackHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedSys: TCastleNiagaraSystem): String;
var
  Audit: TNiagaraSceneAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditNiagaraSystemsInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Niagara Modular Emitter Stack Report (Phase 385 — UE 5.5 UNiagaraSystem Parity)');
    SB.Add('');
    SB.Add(Format('- **Niagara Systems**: `%d` | **Enabled Modules**: `%d / %d`',
      [Audit.SystemCount, Audit.EnabledModuleCount, Audit.TotalModuleCount]));
    SB.Add(Format('- **Active Particles**: `%d` | **Collisions / SubSparks**: `%d / %d`',
      [Audit.TotalActiveParticles, Audit.TotalCollisionEvents, Audit.TotalSubSparksSpawned]));
    if ASelectedSys <> nil then
    begin
      SB.Add('');
      SB.Add('## Active Emitter Stack: `' + ASelectedSys.Name + '` ' + ASelectedSys.NiagaraSummaryBadge);
      for I := 0 to High(ASelectedSys.Modules) do
        SB.Add(Format('- `[%s]` **%s** (`%s`) Enabled=`%s`',
          [TCastleNiagaraSystem.StageTitle(ASelectedSys.Modules[I].Stage),
           TCastleNiagaraSystem.ModuleKindTitle(ASelectedSys.Modules[I].Kind),
           ASelectedSys.Modules[I].ModuleId,
           BoolToStr(ASelectedSys.Modules[I].Enabled, 'Yes', 'No')]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
