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

{ Stateless scene authoring, sibling Level Instance archetype synchronizer, and
  One-File-Per-Actor (OFPA / __ExternalActors__) Git branch split & conflict-free
  merge manager (@link(TLevelInstanceHelper), @link(TLevelInstanceAuditReport))
  (Phase 390 — UE 5.5 ALevelInstance, APackedLevelActor & OFPA Parity + 33rd MCP Tool). }
unit ToolLevelInstance;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleLevelInstance;

type
  TStringDynArray = array of String;

  { Scene-wide Level Instance, Packed ISM & OFPA audit report. }
  TLevelInstanceAuditReport = record
    LevelInstanceCount: Integer;
    TotalSubActors: Integer;
    TotalPackedBatches: Integer;
    ExternalizableWorldActorCount: Integer;
    EditingInPlaceCount: Integer;
  end;

  { Scene spawner, sibling archetype propagator, and OFPA Git branch merge engine. }
  TLevelInstanceHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectLevelInstances(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstLevelInstance(const ADesignRoot: TComponent): TCastleLevelInstance; static;
    class function FindLevelInstanceByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleLevelInstance; static;

    class function SpawnLevelInstancePresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TLevelInstancePreset;
      const AWorldPos: TVector3): TCastleLevelInstance; static;

    { Propagates committed SubLevelJson to all sibling TCastleLevelInstance actors sharing LevelAssetKey }
    class function SyncSiblingInstancesInDesign(
      const ADesignRoot: TComponent;
      const ASourceInstance: TCastleLevelInstance): Integer; static;

    { One-File-Per-Actor (OFPA / __ExternalActors__) Export, 3-Way Git Branch Merge & Rehydration }
    class function ExportDesignToOfpaRepo(
      const ADesignRoot: TComponent): TOfpaActorFileEntryArray; static;

    class function MergeDisjointBranchOfpaRepos(
      const ABaseRepo, AAliceRepo, ABobRepo: TOfpaActorFileEntryArray;
      out AConflictActors: TStringDynArray): TOfpaActorFileEntryArray; static;

    class function RehydrateDesignFromOfpaRepo(
      const ADesignRoot, ADesignOwner: TComponent;
      const ARepo: TOfpaActorFileEntryArray): Integer; static;

    class function AuditLevelInstancesInDesign(
      const ADesignRoot: TComponent): TLevelInstanceAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedLi: TCastleLevelInstance): String; static;
  end;

implementation

uses
  Math, CastleUtils, CastleClassUtils, CastleUIControls, CastleComponentSerialize;

class function TLevelInstanceHelper.FindParentViewportItems(
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

class procedure TLevelInstanceHelper.CollectLevelInstances(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleLevelInstance) and (AList.IndexOf(C) < 0) then
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

class function TLevelInstanceHelper.FindFirstLevelInstance(
  const ADesignRoot: TComponent): TCastleLevelInstance;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectLevelInstances(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleLevelInstance(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TLevelInstanceHelper.FindLevelInstanceByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleLevelInstance;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstLevelInstance(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleLevelInstance then
      Exit(TCastleLevelInstance(Found));
  end;

  L := TList.Create;
  try
    CollectLevelInstances(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleLevelInstance(L[I]).Name, AName) then
        Exit(TCastleLevelInstance(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TLevelInstancePreset;
  const AWorldPos: TVector3): TCastleLevelInstance;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleLevelInstance.Create(ADesignOwner);
  case APreset of
    lipCyberpunkStreetBlock12Actors: BaseName := 'LI_CyberStreetBlock';
    lipDungeonRoomModular8Actors:    BaseName := 'LI_DungeonVaultRoom';
  else
    BaseName := 'LI_Watchtower';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleLevelInstance, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TLevelInstanceHelper.SyncSiblingInstancesInDesign(
  const ADesignRoot: TComponent;
  const ASourceInstance: TCastleLevelInstance): Integer;
var
  L: TList;
  Other: TCastleLevelInstance;
  SharedJson: String;
  I: Integer;
begin
  Result := 0;
  if (ADesignRoot = nil) or (ASourceInstance = nil) then Exit;
  SharedJson := ASourceInstance.SubLevelJson;

  L := TList.Create;
  try
    CollectLevelInstances(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
    begin
      Other := TCastleLevelInstance(L[I]);
      if (Other <> ASourceInstance) and
         SameText(Other.LevelAssetKey, ASourceInstance.LevelAssetKey) then
      begin
        Other.SubLevelJson := SharedJson;
        Inc(Result);
      end;
    end;
  finally
    FreeAndNil(L);
  end;
end;

{ One-File-Per-Actor (OFPA) Split, Merge & Rehydrate ------------------------- }

class function TLevelInstanceHelper.ExportDesignToOfpaRepo(
  const ADesignRoot: TComponent): TOfpaActorFileEntryArray;
var
  ParentT: TCastleTransform;
  Actor: TCastleTransform;
  I, N: Integer;
  JsonStr: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  for I := 0 to ParentT.Count - 1 do
  begin
    Actor := ParentT[I];
    if (csTransient in Actor.ComponentStyle) or
       SameText(Actor.Name, 'MainCamera') then
      Continue;
    if Actor.ClassName = 'TCastleCamera' then
      Continue;

    JsonStr := ComponentToString(Actor);
    N := Length(Result);
    SetLength(Result, N + 1);
    Result[N].ActorName := Actor.Name;
    Result[N].RelativeOfpaPath := TCastleLevelInstance.BuildOfpaRelativePath(Actor.Name);
    Result[N].ContentHashHex := TCastleLevelInstance.ComputeContentHashHex(JsonStr);
    Result[N].SerializedActorJson := JsonStr;
  end;
end;

function FindInRepo(const ARepo: TOfpaActorFileEntryArray; const AActorName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ARepo) do
    if SameText(ARepo[I].ActorName, AActorName) then
      Exit(I);
  Result := -1;
end;

class function TLevelInstanceHelper.MergeDisjointBranchOfpaRepos(
  const ABaseRepo, AAliceRepo, ABobRepo: TOfpaActorFileEntryArray;
  out AConflictActors: TStringDynArray): TOfpaActorFileEntryArray;
var
  AllNames: TStringList;
  I, IdxBase, IdxA, IdxB, OutCnt, ConfCnt: Integer;
  ActorName: String;
  InBase, InA, InB, AChanged, BChanged: Boolean;
begin
  Result := nil;
  AConflictActors := nil;

  AllNames := TStringList.Create;
  AllNames.CaseSensitive := False;
  AllNames.Duplicates := dupIgnore;
  AllNames.Sorted := True;
  try
    for I := 0 to High(ABaseRepo)  do AllNames.Add(ABaseRepo[I].ActorName);
    for I := 0 to High(AAliceRepo) do AllNames.Add(AAliceRepo[I].ActorName);
    for I := 0 to High(ABobRepo)   do AllNames.Add(ABobRepo[I].ActorName);

    for I := 0 to AllNames.Count - 1 do
    begin
      ActorName := AllNames[I];
      IdxBase := FindInRepo(ABaseRepo,  ActorName);
      IdxA    := FindInRepo(AAliceRepo, ActorName);
      IdxB    := FindInRepo(ABobRepo,   ActorName);

      InBase := IdxBase >= 0;
      InA    := IdxA >= 0;
      InB    := IdxB >= 0;

      if InBase then
      begin
        AChanged := (not InA) or (AAliceRepo[IdxA].ContentHashHex <> ABaseRepo[IdxBase].ContentHashHex);
        BChanged := (not InB) or (ABobRepo[IdxB].ContentHashHex   <> ABaseRepo[IdxBase].ContentHashHex);

        if (not AChanged) and (not BChanged) then
        begin
          OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
          Result[OutCnt] := ABaseRepo[IdxBase];
        end else if AChanged and (not BChanged) then
        begin
          if InA then
          begin
            OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
            Result[OutCnt] := AAliceRepo[IdxA];
          end; { else Alice deleted -> omit! }
        end else if BChanged and (not AChanged) then
        begin
          if InB then
          begin
            OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
            Result[OutCnt] := ABobRepo[IdxB];
          end; { else Bob deleted -> omit! }
        end else
        begin
          { Both branches modified the same external actor file }
          if InA and InB and (AAliceRepo[IdxA].ContentHashHex = ABobRepo[IdxB].ContentHashHex) then
          begin
            OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
            Result[OutCnt] := AAliceRepo[IdxA];
          end else if (not InA) and (not InB) then
          begin
            { Both deleted identically }
          end else
          begin
            ConfCnt := Length(AConflictActors);
            SetLength(AConflictActors, ConfCnt + 1);
            AConflictActors[ConfCnt] := ActorName;
            if InA then
            begin
              OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
              Result[OutCnt] := AAliceRepo[IdxA];
            end else if InB then
            begin
              OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
              Result[OutCnt] := ABobRepo[IdxB];
            end;
          end;
        end;
      end else
      begin
        { Newly added actor on Alice and/or Bob }
        if InA and (not InB) then
        begin
          OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
          Result[OutCnt] := AAliceRepo[IdxA];
        end else if InB and (not InA) then
        begin
          OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
          Result[OutCnt] := ABobRepo[IdxB];
        end else if InA and InB then
        begin
          if AAliceRepo[IdxA].ContentHashHex <> ABobRepo[IdxB].ContentHashHex then
          begin
            ConfCnt := Length(AConflictActors);
            SetLength(AConflictActors, ConfCnt + 1);
            AConflictActors[ConfCnt] := ActorName;
          end;
          OutCnt := Length(Result); SetLength(Result, OutCnt + 1);
          Result[OutCnt] := AAliceRepo[IdxA];
        end;
      end;
    end;
  finally
    FreeAndNil(AllNames);
  end;
end;

class function TLevelInstanceHelper.RehydrateDesignFromOfpaRepo(
  const ADesignRoot, ADesignOwner: TComponent;
  const ARepo: TOfpaActorFileEntryArray): Integer;
var
  ParentT, Child: TCastleTransform;
  LoadedComp: TComponent;
  I: Integer;
begin
  Result := 0;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  { Remove existing non-camera user actors }
  for I := ParentT.Count - 1 downto 0 do
  begin
    Child := ParentT[I];
    if (not (csTransient in Child.ComponentStyle)) and
       (Child.ClassName <> 'TCastleCamera') then
    begin
      ParentT.Remove(Child);
      FreeAndNil(Child);
    end;
  end;

  for I := 0 to High(ARepo) do
  begin
    LoadedComp := StringToComponent(ARepo[I].SerializedActorJson, ADesignOwner);
    if LoadedComp is TCastleTransform then
    begin
      ParentT.Add(TCastleTransform(LoadedComp));
      Inc(Result);
    end else
      FreeAndNil(LoadedComp);
  end;
end;

{ Audit & Markdown Report ---------------------------------------------------- }

class function TLevelInstanceHelper.AuditLevelInstancesInDesign(
  const ADesignRoot: TComponent): TLevelInstanceAuditReport;
var
  L: TList;
  LI: TCastleLevelInstance;
  Repo: TOfpaActorFileEntryArray;
  I: Integer;
begin
  Result := Default(TLevelInstanceAuditReport);
  L := TList.Create;
  try
    CollectLevelInstances(ADesignRoot, L);
    Result.LevelInstanceCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      LI := TCastleLevelInstance(L[I]);
      Inc(Result.TotalSubActors, Length(LI.SubActors));
      Inc(Result.TotalPackedBatches, Length(LI.PackedBatches));
      if LI.EditMode = limEditingInPlace then
        Inc(Result.EditingInPlaceCount);
    end;
  finally
    FreeAndNil(L);
  end;

  Repo := ExportDesignToOfpaRepo(ADesignRoot);
  Result.ExternalizableWorldActorCount := Length(Repo);
end;

class function TLevelInstanceHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedLi: TCastleLevelInstance): String;
var
  Audit: TLevelInstanceAuditReport;
  Repo: TOfpaActorFileEntryArray;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditLevelInstancesInDesign(ADesignRoot);
  Repo := ExportDesignToOfpaRepo(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Level Instances, Packed Level Actors & OFPA Report (Phase 390 — UE 5.5 OFPA Parity)');
    SB.Add('');
    SB.Add(Format('- **Level Instances**: `%d` | **Sub-Actors**: `%d` | **Packed ISM Batches**: `%d`',
      [Audit.LevelInstanceCount, Audit.TotalSubActors, Audit.TotalPackedBatches]));
    SB.Add(Format('- **OFPA External Actor Files**: `%d` | **Editing In-Place**: `%d`',
      [Audit.ExternalizableWorldActorCount, Audit.EditingInPlaceCount]));
    if ASelectedLi <> nil then
    begin
      SB.Add('');
      SB.Add('## Active Level Instance: `' + ASelectedLi.Name + '` ' +
        ASelectedLi.LevelInstanceSummaryBadge);
      for I := 0 to High(ASelectedLi.PackedBatches) do
        SB.Add(Format('- Packed Batch **%s**: `%d` instances',
          [ASelectedLi.PackedBatches[I].MeshTag, ASelectedLi.PackedBatches[I].InstanceCount]));
    end;
    if Length(Repo) > 0 then
    begin
      SB.Add('');
      SB.Add('## OFPA `__ExternalActors__` Manifest');
      for I := 0 to Min(7, High(Repo)) do
        SB.Add(Format('- `%s` -> `%s` (`#%s`)',
          [Repo[I].ActorName, Repo[I].RelativeOfpaPath, Repo[I].ContentHashHex]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
