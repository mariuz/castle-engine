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

{ Stateless scene authoring, Parent -> Child Blueprint SCS showcase spawner,
  and USimpleConstructionScript / UInheritableComponentHandler audit helper
  (@link(TBlueprintScsHelper), @link(TBlueprintScsSceneAudit))
  (Phase 395 — UE 5.5 Blueprint Components Viewport & SCS Parity + 38th MCP Tool). }
unit ToolBlueprintScs;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleBlueprintScs;

type
  { Scene-wide Blueprint SCS & Inherited Subobject audit summary. }
  TBlueprintScsSceneAudit = record
    BlueprintScsCount: Integer;
    ChildInheritedClassCount: Integer;
    TotalAssembledSubobjects: Integer;
    TotalInheritedSubobjects: Integer;
    TotalOverriddenSubobjects: Integer;
  end;

  { Scene spawner, class hierarchy builder, and Markdown report generator. }
  TBlueprintScsHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectBlueprintScsActors(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstBlueprintScs(
      const ADesignRoot: TComponent): TCastleBlueprintScsActor; static;
    class function FindBlueprintScsByName(
      const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleBlueprintScsActor; static;

    { Spawns BP_BaseCharacter + BP_BossPaladin_Child (linked via ParentBlueprintScs!) }
    class function SpawnParentAndChildBlueprintShowcaseInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      out OutBaseBp, OutChildBp: TCastleBlueprintScsActor): Integer; static;

    class function SpawnBlueprintScsPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TBlueprintScsPreset;
      const AWorldPos: TVector3): TCastleBlueprintScsActor; static;

    class function AuditBlueprintScsInDesign(
      const ADesignRoot: TComponent): TBlueprintScsSceneAudit; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const AActiveBp: TCastleBlueprintScsActor): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TBlueprintScsHelper.FindParentViewportItems(
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

class procedure TBlueprintScsHelper.CollectBlueprintScsActors(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleBlueprintScsActor) and (AList.IndexOf(C) < 0) then
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

class function TBlueprintScsHelper.FindFirstBlueprintScs(
  const ADesignRoot: TComponent): TCastleBlueprintScsActor;
var
  L: TList;
  I: Integer;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectBlueprintScsActors(ADesignRoot, L);
    { Prefer a Child Blueprint with ParentBlueprintScs assigned so Studio opens on the richest view }
    for I := 0 to L.Count - 1 do
      if TCastleBlueprintScsActor(L[I]).ParentBlueprintScs <> nil then
        Exit(TCastleBlueprintScsActor(L[I]));
    if L.Count > 0 then
      Result := TCastleBlueprintScsActor(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TBlueprintScsHelper.FindBlueprintScsByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleBlueprintScsActor;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstBlueprintScs(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleBlueprintScsActor then
      Exit(TCastleBlueprintScsActor(Found));
  end;

  L := TList.Create;
  try
    CollectBlueprintScsActors(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleBlueprintScsActor(L[I]).Name, AName) then
        Exit(TCastleBlueprintScsActor(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TBlueprintScsHelper.SpawnBlueprintScsPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TBlueprintScsPreset;
  const AWorldPos: TVector3): TCastleBlueprintScsActor;
var
  ParentT: TCastleTransform;
  BaseName: String;
  OwnerToUse: TComponent;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  OwnerToUse := ADesignOwner;
  if OwnerToUse = nil then
    OwnerToUse := ADesignRoot;

  Result := TCastleBlueprintScsActor.Create(OwnerToUse);
  case APreset of
    bspChildBossPaladinOverrides: BaseName := 'BP_BossPaladin';
    bspModularInteractableChestBp: BaseName := 'BP_TreasureChest';
  else
    BaseName := 'BP_BaseCharacter';
  end;

  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleBlueprintScsActor, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TBlueprintScsHelper.SpawnParentAndChildBlueprintShowcaseInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  out OutBaseBp, OutChildBp: TCastleBlueprintScsActor): Integer;
begin
  Result := 0;
  OutBaseBp := SpawnBlueprintScsPresetInDesign(
    ADesignRoot, ADesignOwner, bspBaseThirdPersonCharacter, Vector3(-3.0, 0.0, 0.0));
  if OutBaseBp <> nil then
    Inc(Result);

  OutChildBp := SpawnBlueprintScsPresetInDesign(
    ADesignRoot, ADesignOwner, bspChildBossPaladinOverrides, Vector3(3.0, 0.0, 0.0));
  if OutChildBp <> nil then
  begin
    OutChildBp.ParentBlueprintScs := OutBaseBp;
    OutChildBp.ApplyPreset(bspChildBossPaladinOverrides);
    Inc(Result);
  end;
end;

class function TBlueprintScsHelper.AuditBlueprintScsInDesign(
  const ADesignRoot: TComponent): TBlueprintScsSceneAudit;
var
  L: TList;
  Bp: TCastleBlueprintScsActor;
  I: Integer;
begin
  Result := Default(TBlueprintScsSceneAudit);
  L := TList.Create;
  try
    CollectBlueprintScsActors(ADesignRoot, L);
    Result.BlueprintScsCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      Bp := TCastleBlueprintScsActor(L[I]);
      if Bp.ParentBlueprintScs <> nil then
        Inc(Result.ChildInheritedClassCount);
      Inc(Result.TotalAssembledSubobjects, Length(Bp.Assembled));
      Inc(Result.TotalInheritedSubobjects, Bp.InheritedComponentCount);
      Inc(Result.TotalOverriddenSubobjects, Bp.OverriddenInheritedCount);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TBlueprintScsHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const AActiveBp: TCastleBlueprintScsActor): String;
var
  Audit: TBlueprintScsSceneAudit;
  SB: TStringBuilder;
  TagStr: String;
  I: Integer;
begin
  Audit := AuditBlueprintScsInDesign(ADesignRoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Blueprint Components Viewport & USimpleConstructionScript Report (Phase 395 — UE 5.5 Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Blueprint Classes (`%d` Child Inherited) | `%d` Assembled Components | `%d` Inherited | `%d` Delta Overrides',
      [Audit.BlueprintScsCount, Audit.ChildInheritedClassCount,
       Audit.TotalAssembledSubobjects, Audit.TotalInheritedSubobjects,
       Audit.TotalOverriddenSubobjects]));

    if AActiveBp <> nil then
    begin
      SB.AppendLine(Format('- **Active Blueprint Class**: `%s` (`%d` Assembled Subobjects, `%d` Inherited, `%d` Overridden)',
        [AActiveBp.BlueprintClassKey, Length(AActiveBp.Assembled),
         AActiveBp.InheritedComponentCount, AActiveBp.OverriddenInheritedCount]));
      SB.AppendLine;
      SB.AppendLine('| Component Node | UE Class | Provenance | Actor-Space Pos `(X, Y, Z)` | Primary Param |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :---: |');
      for I := 0 to High(AActiveBp.Assembled) do
      begin
        if AActiveBp.Assembled[I].IsInherited then
        begin
          if AActiveBp.Assembled[I].IsOverriddenInChild then
            TagStr := 'Inherited (Overridden)'
          else
            TagStr := 'Inherited (' + AActiveBp.Assembled[I].SourceBlueprintName + ')';
        end else
          TagStr := 'Local SCS (' + AActiveBp.BlueprintClassKey + ')';

        SB.AppendLine(Format('| `%s` | `%s` | %s | `(%.2f, %.2f, %.2f)` | `%.2f` |',
          [AActiveBp.Assembled[I].NodeName,
           ScsKindDisplayName(AActiveBp.Assembled[I].Kind),
           TagStr,
           AActiveBp.Assembled[I].ActorSpacePos.X,
           AActiveBp.Assembled[I].ActorSpacePos.Y,
           AActiveBp.Assembled[I].ActorSpacePos.Z,
           AActiveBp.Assembled[I].PrimaryParam]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
