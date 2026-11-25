{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 390: Level Instances, Packed Level Actors &
  One-File-Per-Actor (OFPA Parity: In-Place Edit / Commit / Discard / Break,
  Sibling LevelAssetKey Archetype Synchronization, Packed ISM Batch Draw-Call
  Consolidation, Deterministic FNV-1a __ExternalActors__ Bucketing, Conflict-Free
  Disjoint Git Branch Merging & Rehydration, 110-Studio Hub & 33rd MCP Tool
  cge_manage_ofpa_actors). }
unit TestToolLevelInstance;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolLevelInstance = class(TCastleTestCase)
  published
    procedure TestInPlaceEditDiscardCommitSiblingSyncPackedIsmAndBreakIntoWorld;
    procedure TestOfpaDeterministicBucketingDisjointZeroConflictGitMergeAndConflictDetection;
    procedure TestUnified110StudioHubAnd33rdMcpManageOfpaActorsTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene, CastleBoxes,
  CastleComponentSerialize,
  CastleLevelInstance, ToolLevelInstance, ToolStudioHub, ToolMcpServer;

procedure TTestToolLevelInstance.TestInPlaceEditDiscardCommitSiblingSyncPackedIsmAndBreakIntoWorld;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  TowerA, TowerB, TowerBreak, LoadedTower: TCastleLevelInstance;
  BrazierIdx, SyncedCnt, BrokenCnt: Integer;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    TowerA := TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
      VP, Root, lipMedievalWatchtower10Actors, Vector3(0, 0, 0));
    TowerB := TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
      VP, Root, lipMedievalWatchtower10Actors, Vector3(24, 0, 0));
    AssertTrue((TowerA <> nil) and (TowerB <> nil));

    { 1. Packed Level Actor ISM consolidates 10 sub-actors into 3 GPU-instanced batches (-70% draw calls!) }
    AssertEquals(10, Length(TowerA.SubActors));
    AssertEquals(3, Length(TowerA.PackedBatches));
    AssertSameValue(70.0, TowerA.DrawCallReductionPercent, 1e-2);

    BrazierIdx := TowerA.FindSubActorIndex('BeaconBrazier');
    AssertTrue(BrazierIdx >= 0);
    AssertSameValue(6.2, TowerA.SubActors[BrazierIdx].LocalPos.Y, 1e-3);

    { 2. Locked mode rejects direct sub-actor edit; BeginEditInPlace -> Modify -> Discard restores 6.2m! }
    AssertFalse(TowerA.ModifySubActorPositionInEdit('BeaconBrazier', Vector3(0, 9.5, 0)));
    AssertTrue(TowerA.BeginEditInPlace);
    AssertTrue(TowerA.EditMode = limEditingInPlace);
    AssertTrue(TowerA.ModifySubActorPositionInEdit('BeaconBrazier', Vector3(0, 9.5, 0)));
    AssertSameValue(9.5, TowerA.SubActors[BrazierIdx].LocalPos.Y, 1e-3);

    AssertTrue(TowerA.DiscardInPlaceEdits);
    AssertTrue(TowerA.EditMode = limLocked);
    AssertSameValue(6.2, TowerA.SubActors[TowerA.FindSubActorIndex('BeaconBrazier')].LocalPos.Y, 1e-3);

    { 3. BeginEditInPlace -> Modify to Y=8.8m -> Commit + SyncSiblingInstances propagates to TowerB! }
    AssertTrue(TowerA.BeginEditInPlace);
    AssertTrue(TowerA.ModifySubActorPositionInEdit('BeaconBrazier', Vector3(0, 8.8, 0)));
    AssertTrue(TowerA.CommitInPlaceEdits);
    SyncedCnt := TLevelInstanceHelper.SyncSiblingInstancesInDesign(VP, TowerA);
    AssertEquals(1, SyncedCnt);
    AssertSameValue(8.8, TowerB.SubActors[TowerB.FindSubActorIndex('BeaconBrazier')].LocalPos.Y, 1e-3);

    { 4. BreakIntoWorldActors promotes all 4 dungeon sub-actors into standalone world TCastleBoxes }
    TowerBreak := TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
      VP, Root, lipDungeonRoomModular8Actors, Vector3(10, 0, -5));
    BrokenCnt := TowerBreak.BreakIntoWorldActors(VP.Items, Root);
    AssertEquals(4, BrokenCnt);

    { 5. SetTransient-clean JSON serialization roundtrip }
    JsonStr := ComponentToString(TowerA);
    AssertTrue('SetTransient LI_PreviewActors must not leak into serialized JSON',
      Pos('LI_PreviewActors', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedTower := StringToComponent(JsonStr, LoadOwner) as TCastleLevelInstance;
      AssertTrue(LoadedTower <> nil);
      AssertEquals(10, Length(LoadedTower.SubActors));
      AssertSameValue(8.8, LoadedTower.SubActors[LoadedTower.FindSubActorIndex('BeaconBrazier')].LocalPos.Y, 1e-3);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolLevelInstance.TestOfpaDeterministicBucketingDisjointZeroConflictGitMergeAndConflictDetection;
var
  Root, AliceOwner, BobOwner, MergedOwner: TComponent;
  VP, AliceVP, BobVP, MergedVP: TCastleViewport;
  Watchtower, Tavern, OldCart, Gatehouse: TCastleBox;
  BaseRepo, AliceRepo, BobRepo, MergedRepo: TOfpaActorFileEntryArray;
  Conflicts: TStringDynArray;
  RehydratedCnt: Integer;
  MovedTower, MovedTavern: TCastleTransform;
begin
  { 1. Deterministic __ExternalActors__ FNV-1a bucketing }
  AssertEquals(
    TCastleLevelInstance.BuildOfpaRelativePath('Watchtower_North'),
    TCastleLevelInstance.BuildOfpaRelativePath('Watchtower_North'));
  AssertTrue(Pos('__ExternalActors__/', TCastleLevelInstance.BuildOfpaRelativePath('Watchtower_North')) = 1);

  Root := TComponent.Create(nil);
  AliceOwner := TComponent.Create(nil);
  BobOwner := TComponent.Create(nil);
  MergedOwner := TComponent.Create(nil);
  try
    { 2. Build Base World: Watchtower_North, Tavern_East, OldCart_01 }
    VP := TCastleViewport.Create(Root);
    Watchtower := TCastleBox.Create(Root); Watchtower.Name := 'Watchtower_North'; Watchtower.Translation := Vector3(0, 0, 0); VP.Items.Add(Watchtower);
    Tavern     := TCastleBox.Create(Root); Tavern.Name     := 'Tavern_East';      Tavern.Translation     := Vector3(5, 0, 0); VP.Items.Add(Tavern);
    OldCart    := TCastleBox.Create(Root); OldCart.Name    := 'OldCart_01';       OldCart.Translation    := Vector3(2, 0, 2); VP.Items.Add(OldCart);
    BaseRepo := TLevelInstanceHelper.ExportDesignToOfpaRepo(VP);
    AssertEquals(3, Length(BaseRepo));

    { 3. Branch A (Alice): moves Watchtower_North -> (12, 0, -8) & adds Gatehouse_West }
    AliceVP := TCastleViewport.Create(AliceOwner);
    TLevelInstanceHelper.RehydrateDesignFromOfpaRepo(AliceVP, AliceOwner, BaseRepo);
    (AliceOwner.FindComponent('Watchtower_North') as TCastleTransform).Translation := Vector3(12, 0, -8);
    Gatehouse := TCastleBox.Create(AliceOwner); Gatehouse.Name := 'Gatehouse_West'; Gatehouse.Translation := Vector3(-20, 0, 0); AliceVP.Items.Add(Gatehouse);
    AliceRepo := TLevelInstanceHelper.ExportDesignToOfpaRepo(AliceVP);
    AssertEquals(4, Length(AliceRepo));

    { 4. Branch B (Bob): moves Tavern_East -> (-15, 0, 6) & deletes OldCart_01 }
    BobVP := TCastleViewport.Create(BobOwner);
    TLevelInstanceHelper.RehydrateDesignFromOfpaRepo(BobVP, BobOwner, BaseRepo);
    (BobOwner.FindComponent('Tavern_East') as TCastleTransform).Translation := Vector3(-15, 0, 6);
    BobOwner.FindComponent('OldCart_01').Free;
    BobRepo := TLevelInstanceHelper.ExportDesignToOfpaRepo(BobVP);
    AssertEquals(2, Length(BobRepo));

    { 5. Disjoint OFPA 3-Way Git Merge -> ZERO conflicts, preserves Alice's move+add & Bob's move+delete! }
    MergedRepo := TLevelInstanceHelper.MergeDisjointBranchOfpaRepos(
      BaseRepo, AliceRepo, BobRepo, Conflicts);
    AssertEquals('Zero OFPA conflicts on disjoint actor edits', 0, Length(Conflicts));
    AssertEquals('Watchtower_North + Tavern_East + Gatehouse_West (OldCart_01 deleted)', 3, Length(MergedRepo));

    MergedVP := TCastleViewport.Create(MergedOwner);
    RehydratedCnt := TLevelInstanceHelper.RehydrateDesignFromOfpaRepo(MergedVP, MergedOwner, MergedRepo);
    AssertEquals(3, RehydratedCnt);
    AssertTrue(MergedOwner.FindComponent('OldCart_01') = nil);
    AssertTrue(MergedOwner.FindComponent('Gatehouse_West') <> nil);
    MovedTower := MergedOwner.FindComponent('Watchtower_North') as TCastleTransform;
    MovedTavern := MergedOwner.FindComponent('Tavern_East') as TCastleTransform;
    AssertSameValue(12.0, MovedTower.Translation.X, 1e-3);
    AssertSameValue(-15.0, MovedTavern.Translation.X, 1e-3);

    { 6. Colliding concurrent edit on same actor (Watchtower_North) flags exact actor conflict! }
    (BobOwner.FindComponent('Watchtower_North') as TCastleTransform).Translation := Vector3(99, 0, 0);
    BobRepo := TLevelInstanceHelper.ExportDesignToOfpaRepo(BobVP);
    TLevelInstanceHelper.MergeDisjointBranchOfpaRepos(BaseRepo, AliceRepo, BobRepo, Conflicts);
    AssertEquals(1, Length(Conflicts));
    AssertEquals('Watchtower_North', Conflicts[0]);
  finally
    FreeAndNil(MergedOwner);
    FreeAndNil(BobOwner);
    FreeAndNil(AliceOwner);
    FreeAndNil(Root);
  end;
end;

procedure TTestToolLevelInstance.TestUnified110StudioHubAnd33rdMcpManageOfpaActorsTool;
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr, ManifestArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify 110 UE Studios in Studio Hub (Phase 390 level_instance_ofpa) }
  AssertEquals(111, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('level_instance_ofpa', Entry));
  AssertEquals(390, Entry.PhaseNumber);

  { 2. Verify 33rd MCP tool cge_manage_ofpa_actors }
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Srv := TCastleMcpServer.Create(Root);
    Srv.AutonomyMode := mamEditWithUndo;
    Srv.StandaloneDesignRoot := VP;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    OuterJson := GetJSON(ListResp);
    try
      ToolsArr := OuterJson.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(34, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_manage_ofpa_actors","arguments":{"action":"spawn_preset","preset":"watchtower"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['levelInstanceCount']);
        AssertEquals(10, PayloadObj.Integers['totalSubActors']);
        AssertEquals(3, PayloadObj.Integers['totalPackedBatches']);
        AssertSameValue(70.0, PayloadObj.Floats['drawCallReductionPercent'], 1e-2);
        AssertEquals(111, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_manage_ofpa_actors","arguments":{"action":"export_ofpa"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        ManifestArr := PayloadObj.Arrays['ofpaManifest'];
        AssertEquals(1, ManifestArr.Count);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolLevelInstance);
end.
