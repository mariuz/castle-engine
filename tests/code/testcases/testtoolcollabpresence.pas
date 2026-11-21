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

{ Automated tests for Phase 366 Multi-User Collaborative Presence Locks,
  86-Studio Hub & 18-Tool MCP Upgrade. }
unit TestToolCollabPresence;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolCollabPresence = class(TCastleTestCase)
  published
    procedure TestAncestorDescendantSubtreeConflictSiblingConcurrencyAndLeaseExpiration;
    procedure TestUnified86StudioHubCatalogAnd18thMcpCollabLocksTool;
  end;

implementation

uses fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleViewport,
  ToolCollabPresence, ToolStudioHub, ToolMcpServer;

procedure TTestToolCollabPresence.TestAncestorDescendantSubtreeConflictSiblingConcurrencyAndLeaseExpiration;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Broker, RestoredBroker: TCollabPresenceBroker;
  ConflictReason, SessionJson: String;
begin
  RootOwner := TComponent.Create(nil);
  Broker := TCollabPresenceBroker.Create;
  RestoredBroker := TCollabPresenceBroker.Create;
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TCollabPresenceBroker.SpawnCollaborativeKeepDemo(Vp, RootOwner));

    { 1. Alice locks parent subtree 'CastleGate' for 30s -> succeeds }
    AssertTrue(Broker.AcquireSubtreeLock(Vp, 'alice', 'Alice', 'CastleGate', 30.0, ConflictReason));
    AssertEquals(1, Broker.ActiveLockCount);

    { 2. Bob attempts to lock child 'GateHinge' (descendant of 'CastleGate') -> REJECTED! }
    AssertFalse('Child GateHinge must be blocked while parent CastleGate is locked by Alice',
      Broker.AcquireSubtreeLock(Vp, 'bob', 'Bob', 'GateHinge', 30.0, ConflictReason));
    AssertTrue(Pos('ANCESTOR_SUBTREE_LOCKED_BY_alice', ConflictReason) > 0);

    { 3. Bob locks independent sibling 'TavernSign' -> SUCCEEDS in parallel! }
    AssertTrue('Independent sibling TavernSign must allow concurrent editing by Bob',
      Broker.AcquireSubtreeLock(Vp, 'bob', 'Bob', 'TavernSign', 20.0, ConflictReason));
    AssertEquals(2, Broker.ActiveLockCount);

    { 4. Advance +22s; Alice sends heartbeat renewal (+30s from t=22 -> expires at 52s),
         while Bob misses heartbeat (expired at 20s) -> Bob's stale lock is reclaimed! }
    Broker.AdvanceClockSeconds(15.0);
    AssertTrue(Broker.RenewHeartbeat('alice', 'CastleGate', 30.0));
    Broker.AdvanceClockSeconds(7.0); { t = 22.0s: Bob's 20s lease is stale, Alice's renewed lease expires at 45s }
    AssertEquals(1, Broker.ExpireStaleLocks);
    AssertEquals(1, Broker.ActiveLockCount);

    { 5. Session JSON export/import roundtrip }
    Broker.UpdatePeerPresence('alice', 'Alice', 'CastleGate', Vector3(-4, 3, 8));
    SessionJson := Broker.ExportSessionJson;
    AssertTrue(RestoredBroker.ImportSessionJson(SessionJson));
    AssertEquals(1, RestoredBroker.ActiveLockCount);
    AssertEquals(1, RestoredBroker.PeerCount);

    { 6. Once Alice releases 'CastleGate', Bob can immediately lock 'GateHinge' AND Alice cannot lock ancestor 'CastleGate'! }
    AssertTrue(Broker.ReleaseSubtreeLock('alice', 'CastleGate'));
    AssertTrue(Broker.AcquireSubtreeLock(Vp, 'bob', 'Bob', 'GateHinge', 30.0, ConflictReason));
    AssertFalse('Locking ancestor CastleGate must be blocked while descendant GateHinge is locked by Bob',
      Broker.AcquireSubtreeLock(Vp, 'alice', 'Alice', 'CastleGate', 30.0, ConflictReason));
    AssertTrue(Pos('DESCENDANT_SUBTREE_LOCKED_BY_bob', ConflictReason) > 0);
  finally
    FreeAndNil(RestoredBroker);
    FreeAndNil(Broker);
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolCollabPresence.TestUnified86StudioHubCatalogAnd18thMcpCollabLocksTool;
const
  Horizon10Ids: array[0..9] of String = (
    'surface_gi', 'contextual_anim', 'targeting_studio', 'mutable_studio', 'river_studio',
    'occluder_fader', 'gameplay_debugger', 'wind_studio', 'preload_studio', 'collab_presence'
  );
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Server: TCastleMcpServer;
  Entry: TStudioCatalogEntry;
  RespStr, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  I: Integer;
begin
  { 1. Verify all 96 studios across Horizons 2-11 are indexed in TStudioHubManager }
  AssertEquals(136, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon10Ids) do
    AssertTrue('Missing Horizon 10 studio in Hub: ' + Horizon10Ids[I],
      TStudioHubManager.FindStudioById(Horizon10Ids[I], Entry));

  TCollabPresenceBroker.SharedBroker.ResetAll;
  DesignOwner := TComponent.Create(nil);
  Server := TCastleMcpServer.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TCollabPresenceBroker.SpawnCollaborativeKeepDemo(Vp, DesignOwner));

    Server.AutonomyMode := mamEditWithUndo;
    Server.StandaloneDesignRoot := Vp;
    Server.StandaloneDesignOwner := DesignOwner;

    { 2. Agent-A acquires CastleGate via 18th MCP tool cge_manage_collab_locks }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":66,"method":"tools/call","params":{"name":"cge_manage_collab_locks","arguments":{"action":"acquire","userId":"agent-alpha","subtree":"CastleGate","leaseSec":45}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertTrue(TJSONObject(InnerJson).Booleans['ok']);
        AssertEquals(1, TJSONObject(InnerJson).Integers['activeLockCount']);
        AssertEquals(136, TJSONObject(InnerJson).Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    { 3. Agent-B tries to acquire child GateHinge via MCP -> conflict cleanly reported! }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":67,"method":"tools/call","params":{"name":"cge_manage_collab_locks","arguments":{"action":"acquire","userId":"agent-beta","subtree":"GateHinge","leaseSec":45}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertFalse(TJSONObject(InnerJson).Booleans['ok']);
        AssertTrue(Pos('ANCESTOR_SUBTREE_LOCKED', TJSONObject(InnerJson).Strings['conflictReason']) > 0);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    TCollabPresenceBroker.SharedBroker.ResetAll;
    FreeAndNil(Server);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolCollabPresence);
end.
