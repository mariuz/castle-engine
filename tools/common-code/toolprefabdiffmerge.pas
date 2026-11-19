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

{ Three-way scene and prefab JSON diff/merge engine comparing Common Ancestor
  (Base), Local Scene (Ours), and Incoming Branch (Theirs) component trees with
  automatic non-conflicting property/child merging and conflict resolution
  policies (Phase 386). }
unit ToolPrefabDiffMerge;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math, FpJson, JsonParser,
  CastleVectors, CastleTransform, CastleViewport, CastleScene,
  CastleComponentSerialize, CastleColors;

type
  { Policy used when both Ours and Theirs modified the same property to different values. }
  TMergeConflictPolicy = (
    mcpPreferOurs,
    mcpPreferTheirs
  );

  { Classification of a 3-way scene or prefab change entry. }
  TMergeChangeKind = (
    mckOursOnlyModified,
    mckTheirsOnlyModified,
    mckBothIdenticalChange,
    mckTrueConflict,
    mckAddedInOurs,
    mckAddedInTheirs,
    mckDeletedInOurs,
    mckDeletedInTheirs
  );

  { Single property or child-component delta discovered during a 3-way diff/merge. }
  TThreeWayChangeItem = record
    ComponentName: String;
    PropertyPath: String;
    Kind: TMergeChangeKind;
    BaseValueJson: String;
    OursValueJson: String;
    TheirsValueJson: String;
    ResolvedValueJson: String;
  end;

  { Summary and per-field log of a 3-way scene/prefab merge operation. }
  TThreeWayMergeReport = record
    Changes: array of TThreeWayChangeItem;
    AutoMergedCount: Integer;
    ConflictCount: Integer;
    AddedNodesCount: Integer;
    DeletedNodesCount: Integer;
    PolicyUsed: TMergeConflictPolicy;
    MergedSceneJson: String;
  end;

  { Stateful and static 3-way CGE component JSON diff/merge engine. }
  TPrefabDiffMergeEngine = class
  private
    FCapturedBaseJson: String;
    FLastReport: TThreeWayMergeReport;
  public
    class function SharedEngine: TPrefabDiffMergeEngine;
    class function ChangeKindToString(const AKind: TMergeChangeKind): String;
    class function PolicyToString(const APolicy: TMergeConflictPolicy): String;
    class function StringToPolicy(const AStr: String): TMergeConflictPolicy;

    { Perform a structural 3-way diff/merge on CGE ComponentToString JSON trees. }
    class function ComputeThreeWayMerge(
      const ABaseJson, AOursJson, ATheirsJson: String;
      const AConflictPolicy: TMergeConflictPolicy;
      out AReport: TThreeWayMergeReport): String;

    { Build a synthetic Base / Ours / Theirs demo scenario with both auto-merges and 1 conflict. }
    class procedure BuildSyntheticBranchConflictScenario(
      out ABaseJson, AOursJson, ATheirsJson: String);

    class function BuildMarkdownReport(const AReport: TThreeWayMergeReport): String;

    procedure CaptureBaseSnapshotFromComponent(const ARoot: TComponent);
    function RunMergeAndStore(const ABaseJson, AOursJson, ATheirsJson: String;
      const APolicy: TMergeConflictPolicy): TThreeWayMergeReport;

    property CapturedBaseJson: String read FCapturedBaseJson write FCapturedBaseJson;
    property LastReport: TThreeWayMergeReport read FLastReport;
  end;

implementation

uses CastleUtils, ToolStudioHub;

var
  GSharedDiffMergeEngine: TPrefabDiffMergeEngine = nil;

function IsStructuralArrayField(const AKey: String): Boolean;
begin
  Result := SameText(AKey, '$Children') or
            SameText(AKey, 'children') or
            SameText(AKey, '$Behaviors') or
            SameText(AKey, 'behaviors') or
            SameText(AKey, '$Controls') or
            SameText(AKey, 'controls') or
            SameText(AKey, '$NonVisualComponents') or
            SameText(AKey, 'non_visual_components');
end;

function GetJsonCompName(const AObj: TJSONObject): String;
var
  Idx: Integer;
begin
  Result := '';
  if AObj = nil then Exit;
  Idx := AObj.IndexOfName('Name', True);
  if (Idx >= 0) and (AObj.Items[Idx].JSONType = jtString) then
    Result := AObj.Items[Idx].AsString;
end;

function SafeParseJsonObject(const AJson: String): TJSONObject;
var
  D: TJSONData;
begin
  Result := nil;
  if Trim(AJson) = '' then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if D is TJSONObject then
      Result := TJSONObject(D)
    else
      FreeAndNil(D);
  except
    FreeAndNil(D);
    Result := nil;
  end;
end;

function FindNamedChildInObjArray(const AArr: TJSONArray;
  const ACompName: String): TJSONObject;
var
  I: Integer;
  SubObj: TJSONObject;
begin
  Result := nil;
  if AArr = nil then Exit;
  for I := 0 to AArr.Count - 1 do
    if AArr.Items[I] is TJSONObject then
    begin
      SubObj := TJSONObject(AArr.Items[I]);
      if SameText(GetJsonCompName(SubObj), ACompName) then
        Exit(SubObj);
    end;
end;

procedure RemoveNamedChildFromObjArray(const AArr: TJSONArray;
  const ACompName: String);
var
  I: Integer;
  SubObj: TJSONObject;
begin
  if AArr = nil then Exit;
  for I := AArr.Count - 1 downto 0 do
    if AArr.Items[I] is TJSONObject then
    begin
      SubObj := TJSONObject(AArr.Items[I]);
      if SameText(GetJsonCompName(SubObj), ACompName) then
      begin
        AArr.Delete(I);
        Exit;
      end;
    end;
end;

procedure AppendChange(var AReport: TThreeWayMergeReport;
  const ACompName, APropPath: String; const AKind: TMergeChangeKind;
  const ABaseV, AOursV, ATheirsV, AResolvedV: String);
var
  N: Integer;
begin
  N := Length(AReport.Changes);
  SetLength(AReport.Changes, N + 1);
  AReport.Changes[N].ComponentName := ACompName;
  AReport.Changes[N].PropertyPath := APropPath;
  AReport.Changes[N].Kind := AKind;
  AReport.Changes[N].BaseValueJson := ABaseV;
  AReport.Changes[N].OursValueJson := AOursV;
  AReport.Changes[N].TheirsValueJson := ATheirsV;
  AReport.Changes[N].ResolvedValueJson := AResolvedV;
  case AKind of
    mckOursOnlyModified,
    mckTheirsOnlyModified,
    mckBothIdenticalChange:
      Inc(AReport.AutoMergedCount);
    mckTrueConflict:
      Inc(AReport.ConflictCount);
    mckAddedInOurs,
    mckAddedInTheirs:
      begin
        Inc(AReport.AddedNodesCount);
        Inc(AReport.AutoMergedCount);
      end;
    mckDeletedInOurs,
    mckDeletedInTheirs:
      begin
        Inc(AReport.DeletedNodesCount);
        Inc(AReport.AutoMergedCount);
      end;
  end;
end;

procedure MergeJsonComponentObjects(
  const ACompPath: String;
  const ABaseObj, AOursObj, ATheirsObj, AMergedObj: TJSONObject;
  const APolicy: TMergeConflictPolicy;
  var AReport: TThreeWayMergeReport);
var
  Keys: TStringList;
  I, CIdx: Integer;
  Key, CompLabel, BaseStr, OursStr, TheirsStr, ChildName, ArrKey: String;
  BVal, OVal, TVal: TJSONData;
  BArr, OArr, TArr, MArr: TJSONArray;
  ChildNames: TStringList;
  BChild, OChild, TChild, MChild: TJSONObject;

  procedure CollectKeysFrom(const AObj: TJSONObject);
  var
    KIdx: Integer;
    KName: String;
  begin
    if AObj = nil then Exit;
    for KIdx := 0 to AObj.Count - 1 do
    begin
      KName := AObj.Names[KIdx];
      if Keys.IndexOf(KName) < 0 then
        Keys.Add(KName);
    end;
  end;

  procedure CollectChildNamesFrom(const AArr: TJSONArray);
  var
    J: Integer;
    NM: String;
  begin
    if AArr = nil then Exit;
    for J := 0 to AArr.Count - 1 do
      if AArr.Items[J] is TJSONObject then
      begin
        NM := GetJsonCompName(TJSONObject(AArr.Items[J]));
        if (NM <> '') and (ChildNames.IndexOf(NM) < 0) then
          ChildNames.Add(NM);
      end;
  end;

  function JsonDataCanon(const D: TJSONData): String;
  begin
    if D = nil then
      Result := '<unset>'
    else
      Result := D.AsJSON;
  end;

  procedure SetMergedFieldClone(const AFieldName: String; const ASourceData: TJSONData);
  var
    ExistingIdx: Integer;
  begin
    ExistingIdx := AMergedObj.IndexOfName(AFieldName);
    if ASourceData = nil then
    begin
      if ExistingIdx >= 0 then
        AMergedObj.Delete(ExistingIdx);
    end else
    begin
      if ExistingIdx >= 0 then
        AMergedObj.Items[ExistingIdx] := ASourceData.Clone
      else
        AMergedObj.Add(AFieldName, ASourceData.Clone);
    end;
  end;

begin
  CompLabel := ACompPath;
  if (CompLabel = '') and (AMergedObj <> nil) then
  begin
    CompLabel := GetJsonCompName(AMergedObj);
    if CompLabel = '' then
      CompLabel := AMergedObj.Get('$ClassName', 'Root');
  end;

  Keys := TStringList.Create;
  try
    CollectKeysFrom(ABaseObj);
    CollectKeysFrom(AOursObj);
    CollectKeysFrom(ATheirsObj);

    for I := 0 to Keys.Count - 1 do
    begin
      Key := Keys[I];
      if SameText(Key, '$ClassName') or SameText(Key, 'name') then
        Continue;

      if IsStructuralArrayField(Key) then
      begin
        ArrKey := Key;
        if (ABaseObj <> nil) and (ABaseObj.Find(ArrKey) is TJSONArray) then
          BArr := TJSONArray(ABaseObj.Find(ArrKey))
        else
          BArr := nil;
        if (AOursObj <> nil) and (AOursObj.Find(ArrKey) is TJSONArray) then
          OArr := TJSONArray(AOursObj.Find(ArrKey))
        else
          OArr := nil;
        if (ATheirsObj <> nil) and (ATheirsObj.Find(ArrKey) is TJSONArray) then
          TArr := TJSONArray(ATheirsObj.Find(ArrKey))
        else
          TArr := nil;

        if AMergedObj.Find(ArrKey) is TJSONArray then
          MArr := TJSONArray(AMergedObj.Find(ArrKey))
        else
        begin
          MArr := TJSONArray.Create;
          AMergedObj.Add(ArrKey, MArr);
        end;

        ChildNames := TStringList.Create;
        try
          CollectChildNamesFrom(BArr);
          CollectChildNamesFrom(OArr);
          CollectChildNamesFrom(TArr);

          for CIdx := 0 to ChildNames.Count - 1 do
          begin
            ChildName := ChildNames[CIdx];
            BChild := FindNamedChildInObjArray(BArr, ChildName);
            OChild := FindNamedChildInObjArray(OArr, ChildName);
            TChild := FindNamedChildInObjArray(TArr, ChildName);
            MChild := FindNamedChildInObjArray(MArr, ChildName);

            if (BChild = nil) and (OChild <> nil) and (TChild = nil) then
            begin
              { Added in Ours only -> already in MArr }
              AppendChange(AReport, ChildName, ArrKey, mckAddedInOurs,
                '<none>', OChild.Get('$ClassName', 'Component'), '<none>',
                OChild.Get('$ClassName', 'Component'));
            end else
            if (BChild = nil) and (OChild = nil) and (TChild <> nil) then
            begin
              { Added in Theirs only -> clone and insert into MArr! }
              MArr.Add(TChild.Clone);
              AppendChange(AReport, ChildName, ArrKey, mckAddedInTheirs,
                '<none>', '<none>', TChild.Get('$ClassName', 'Component'),
                TChild.Get('$ClassName', 'Component'));
            end else
            if (BChild <> nil) and (OChild = nil) and (TChild <> nil) then
            begin
              { Deleted in Ours -> keep deleted if Theirs untouched }
              AppendChange(AReport, ChildName, ArrKey, mckDeletedInOurs,
                BChild.Get('$ClassName', 'Component'), '<deleted>',
                TChild.Get('$ClassName', 'Component'), '<deleted>');
            end else
            if (BChild <> nil) and (OChild <> nil) and (TChild = nil) then
            begin
              { Deleted in Theirs -> remove from MArr if Ours untouched }
              if OChild.AsJSON = BChild.AsJSON then
              begin
                RemoveNamedChildFromObjArray(MArr, ChildName);
                AppendChange(AReport, ChildName, ArrKey, mckDeletedInTheirs,
                  BChild.Get('$ClassName', 'Component'),
                  OChild.Get('$ClassName', 'Component'), '<deleted>', '<deleted>');
              end;
            end else
            if (OChild <> nil) and (TChild <> nil) and (MChild <> nil) then
            begin
              MergeJsonComponentObjects(ChildName, BChild, OChild, TChild, MChild,
                APolicy, AReport);
            end;
          end;

          if MArr.Count = 0 then
            AMergedObj.Delete(AMergedObj.IndexOfName(ArrKey));
        finally
          FreeAndNil(ChildNames);
        end;
        Continue;
      end;

      if ABaseObj <> nil then BVal := ABaseObj.Find(Key) else BVal := nil;
      if AOursObj <> nil then OVal := AOursObj.Find(Key) else OVal := nil;
      if ATheirsObj <> nil then TVal := ATheirsObj.Find(Key) else TVal := nil;

      BaseStr := JsonDataCanon(BVal);
      OursStr := JsonDataCanon(OVal);
      TheirsStr := JsonDataCanon(TVal);

      if (OursStr = BaseStr) and (TheirsStr = BaseStr) then
        Continue;

      if (OursStr <> BaseStr) and (TheirsStr = BaseStr) then
      begin
        { Modified only in Ours -> already present in AMergedObj }
        AppendChange(AReport, CompLabel, Key, mckOursOnlyModified,
          BaseStr, OursStr, TheirsStr, OursStr);
      end else
      if (OursStr = BaseStr) and (TheirsStr <> BaseStr) then
      begin
        { Modified only in Theirs -> apply Theirs onto AMergedObj }
        SetMergedFieldClone(Key, TVal);
        AppendChange(AReport, CompLabel, Key, mckTheirsOnlyModified,
          BaseStr, OursStr, TheirsStr, TheirsStr);
      end else
      if OursStr = TheirsStr then
      begin
        { Identical modification in both Ours and Theirs }
        AppendChange(AReport, CompLabel, Key, mckBothIdenticalChange,
          BaseStr, OursStr, TheirsStr, OursStr);
      end else
      begin
        { True 3-way conflict: Ours <> Base, Theirs <> Base, Ours <> Theirs }
        if APolicy = mcpPreferTheirs then
        begin
          SetMergedFieldClone(Key, TVal);
          AppendChange(AReport, CompLabel, Key, mckTrueConflict,
            BaseStr, OursStr, TheirsStr, TheirsStr);
        end else
        begin
          AppendChange(AReport, CompLabel, Key, mckTrueConflict,
            BaseStr, OursStr, TheirsStr, OursStr);
        end;
      end;
    end;
  finally
    FreeAndNil(Keys);
  end;
end;

{ TPrefabDiffMergeEngine ----------------------------------------------------- }

class function TPrefabDiffMergeEngine.SharedEngine: TPrefabDiffMergeEngine;
begin
  if GSharedDiffMergeEngine = nil then
    GSharedDiffMergeEngine := TPrefabDiffMergeEngine.Create;
  Result := GSharedDiffMergeEngine;
end;

class function TPrefabDiffMergeEngine.ChangeKindToString(
  const AKind: TMergeChangeKind): String;
begin
  case AKind of
    mckOursOnlyModified:    Result := 'ours_modified';
    mckTheirsOnlyModified:  Result := 'theirs_modified';
    mckBothIdenticalChange: Result := 'both_identical';
    mckTrueConflict:        Result := 'true_conflict';
    mckAddedInOurs:         Result := 'added_in_ours';
    mckAddedInTheirs:       Result := 'added_in_theirs';
    mckDeletedInOurs:       Result := 'deleted_in_ours';
    mckDeletedInTheirs:     Result := 'deleted_in_theirs';
  end;
end;

class function TPrefabDiffMergeEngine.PolicyToString(
  const APolicy: TMergeConflictPolicy): String;
begin
  case APolicy of
    mcpPreferOurs:   Result := 'prefer_ours';
    mcpPreferTheirs: Result := 'prefer_theirs';
  end;
end;

class function TPrefabDiffMergeEngine.StringToPolicy(
  const AStr: String): TMergeConflictPolicy;
begin
  if SameText(Trim(AStr), 'prefer_theirs') or SameText(Trim(AStr), 'theirs') then
    Result := mcpPreferTheirs
  else
    Result := mcpPreferOurs;
end;

class function TPrefabDiffMergeEngine.ComputeThreeWayMerge(
  const ABaseJson, AOursJson, ATheirsJson: String;
  const AConflictPolicy: TMergeConflictPolicy;
  out AReport: TThreeWayMergeReport): String;
var
  BaseObj, OursObj, TheirsObj, MergedObj: TJSONObject;
begin
  AReport := Default(TThreeWayMergeReport);
  AReport.PolicyUsed := AConflictPolicy;

  BaseObj := SafeParseJsonObject(ABaseJson);
  OursObj := SafeParseJsonObject(AOursJson);
  TheirsObj := SafeParseJsonObject(ATheirsJson);
  MergedObj := nil;
  try
    if OursObj <> nil then
      MergedObj := TJSONObject(OursObj.Clone)
    else if TheirsObj <> nil then
      MergedObj := TJSONObject(TheirsObj.Clone)
    else
      MergedObj := TJSONObject.Create;

    MergeJsonComponentObjects('', BaseObj, OursObj, TheirsObj, MergedObj,
      AConflictPolicy, AReport);

    Result := MergedObj.FormatJSON;
    AReport.MergedSceneJson := Result;
  finally
    FreeAndNil(MergedObj);
    FreeAndNil(TheirsObj);
    FreeAndNil(OursObj);
    FreeAndNil(BaseObj);
  end;
end;

class procedure TPrefabDiffMergeEngine.BuildSyntheticBranchConflictScenario(
  out ABaseJson, AOursJson, ATheirsJson: String);
var
  Owner: TComponent;
  Root: TCastleTransform;
  Hero, Crate, Watchtower: TCastleBox;
begin
  Owner := TComponent.Create(nil);
  try
    Root := TCastleTransform.Create(Owner);
    Root.Name := 'SquadOutpostRoot';

    Hero := TCastleBox.Create(Owner);
    Hero.Name := 'VanguardHero';
    Hero.Translation := Vector3(0, 1, 0);
    Hero.Scale := Vector3(1, 1, 1);
    Root.Add(Hero);

    Crate := TCastleBox.Create(Owner);
    Crate.Name := 'SupplyCrateAlpha';
    Crate.Tag := 10;
    Crate.Size := Vector3(1.5, 1.5, 1.5);
    Root.Add(Crate);

    { 1. Common Ancestor (Base) }
    ABaseJson := ComponentToString(Root);

    { 2. Ours: move Hero to X=+6.0 and set SupplyCrateAlpha.Tag := 42 (conflict!) }
    Hero.Translation := Vector3(6.0, 1.0, 0.0);
    Crate.Tag := 42;
    AOursJson := ComponentToString(Root);

    { 3. Theirs (from Base): keep Hero.Translation=(0,1,0), scale Hero to 1.5x,
         set SupplyCrateAlpha.Tag := 99 (conflict!), and add WatchtowerTheirs }
    Hero.Translation := Vector3(0.0, 1.0, 0.0);
    Hero.Scale := Vector3(1.5, 1.5, 1.5);
    Crate.Tag := 99;

    Watchtower := TCastleBox.Create(Owner);
    Watchtower.Name := 'WatchtowerTheirs';
    Watchtower.Size := Vector3(3.0, 8.0, 3.0);
    Watchtower.Translation := Vector3(-10.0, 4.0, -8.0);
    Root.Add(Watchtower);

    ATheirsJson := ComponentToString(Root);
  finally
    FreeAndNil(Owner);
  end;
end;

class function TPrefabDiffMergeEngine.BuildMarkdownReport(
  const AReport: TThreeWayMergeReport): String;
var
  I: Integer;
begin
  Result :=
    '# Three-Way Scene & Prefab Diff/Merge Report (Phase 386)' + NL + NL +
    Format('- **Unified Horizon 2–12 Catalog**: **`%d` Studios** across `6` Domains (`20` MCP Tools incl. `cge_diff_merge_scene`)' + NL,
      [TStudioHubManager.StudioCount]) +
    Format('- **Conflict Resolution Policy**: `%s`' + NL, [PolicyToString(AReport.PolicyUsed)]) +
    Format('- **Non-Conflicting Auto-Merged Changes**: `%d` (`+%d` Added Nodes, `-%d` Deleted Nodes)' + NL,
      [AReport.AutoMergedCount, AReport.AddedNodesCount, AReport.DeletedNodesCount]) +
    Format('- **True 3-Way Conflicts Resolved**: `%d`' + NL + NL, [AReport.ConflictCount]);

  if Length(AReport.Changes) > 0 then
  begin
    Result := Result +
      '| Component | Property / Collection | Classification | Resolved |' + NL +
      '| :--- | :--- | :--- | :--- |' + NL;
    for I := 0 to High(AReport.Changes) do
      Result := Result + Format('| `%s` | `%s` | `%s` | `%s` |' + NL, [
        AReport.Changes[I].ComponentName,
        AReport.Changes[I].PropertyPath,
        ChangeKindToString(AReport.Changes[I].Kind),
        AReport.Changes[I].ResolvedValueJson]);
  end;
end;

procedure TPrefabDiffMergeEngine.CaptureBaseSnapshotFromComponent(
  const ARoot: TComponent);
begin
  if ARoot <> nil then
    FCapturedBaseJson := ComponentToString(ARoot)
  else
    FCapturedBaseJson := '';
end;

function TPrefabDiffMergeEngine.RunMergeAndStore(
  const ABaseJson, AOursJson, ATheirsJson: String;
  const APolicy: TMergeConflictPolicy): TThreeWayMergeReport;
begin
  ComputeThreeWayMerge(ABaseJson, AOursJson, ATheirsJson, APolicy, FLastReport);
  Result := FLastReport;
end;

finalization
  FreeAndNil(GSharedDiffMergeEngine);

end.
