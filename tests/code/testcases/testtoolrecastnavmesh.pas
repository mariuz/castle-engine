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

{ Automated tests for Phase 393: 3D Polygonal Recast NavMesh Volume &
  NavLinkProxy Off-Mesh Links (UE 5.5 ANavMeshBoundsVolume & ANavLinkProxy
  Parity: Multi-Floor Stacked Bridge/Underpass Polygons at Identical XZ,
  AgentHeight Ceiling Headroom & Slope Filtering, One-Way Drop vs. Bidirectional
  Jump ANavLinkProxy Asymmetry, Portal-Smoothed 3D A* Pathfinding, 113-Studio
  Hub & 36th MCP Tool cge_build_recast_navmesh). }
unit TestToolRecastNavMesh;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolRecastNavMesh = class(TCastleTestCase)
  published
    procedure TestStackedMultiFloorBridgeUnderpassSlopeFilterAndOgreHeadroomClearance;
    procedure TestDirectionalNavLinkProxyOneWayDropAsymmetryDisableAndCleanJsonRoundtrip;
    procedure TestUnified113StudioHubAnd36thMcpBuildRecastNavMeshTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleRecastNavMesh, ToolRecastNavMesh, ToolStudioHub, ToolMcpServer;

procedure TTestToolRecastNavMesh.TestStackedMultiFloorBridgeUnderpassSlopeFilterAndOgreHeadroomClearance;
var
  Root: TComponent;
  VP: TCastleViewport;
  Nav: TCastleRecastNavMesh;
  LowerPoly, UpperPoly, I: Integer;
  FoundSteepRubble: Boolean;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Nav := TRecastNavMeshHelper.SpawnRecastPresetInDesign(
      VP, Root, rnpTwoStoryBridgeAndStairs, Vector3(0, 0, 0));
    AssertTrue(Nav <> nil);

    { 1. Steep 58-degree rubble slab (> MaxSlope 45 deg) is rejected automatically }
    FoundSteepRubble := False;
    for I := 0 to High(Nav.Polys) do
      if SameText(Nav.Polys[I].SourceSlabName, 'CollapsedRubble_58Deg') then
        FoundSteepRubble := True;
    AssertFalse('58-deg slope rejected by 45-deg AgentMaxSlopeDeg', FoundSteepRubble);

    { 2. Stacked 2-story multi-floor polygons at identical XZ=(0.5, 0.0):
      Floor 0 Underpass_Tunnel (Y=0.0m) AND Floor 1 Overpass_BridgeDeck (Y=3.0m)! }
    AssertTrue('Detects stacked multi-floor polygon overlap', Nav.CountStackedMultiFloorPairs >= 1);
    LowerPoly := Nav.FindContainingOrNearestPoly(Vector3(0.5, 0.0, 0.0));
    UpperPoly := Nav.FindContainingOrNearestPoly(Vector3(0.5, 3.0, 0.0));
    AssertTrue((LowerPoly >= 0) and (UpperPoly >= 0) and (LowerPoly <> UpperPoly));
    AssertEquals('Underpass_Tunnel', Nav.Polys[LowerPoly].SourceSlabName);
    AssertEquals('Overpass_BridgeDeck', Nav.Polys[UpperPoly].SourceSlabName);

    { 3. Raising AgentHeight to 2.80m Brute Ogre exceeds the 2.55m bridge ceiling clearance:
      Underpass_Tunnel is culled while Overpass_BridgeDeck (open sky above) stays walkable! }
    Nav.AgentHeight := 2.80;
    LowerPoly := Nav.FindContainingOrNearestPoly(Vector3(0.5, 0.0, 0.0), 0.4);
    UpperPoly := Nav.FindContainingOrNearestPoly(Vector3(0.5, 3.0, 0.0), 0.4);
    AssertEquals('2.8m Ogre cannot fit under 2.55m bridge ceiling', -1, LowerPoly);
    AssertTrue('Upper bridge deck remains walkable for 2.8m Ogre', UpperPoly >= 0);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolRecastNavMesh.TestDirectionalNavLinkProxyOneWayDropAsymmetryDisableAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Nav, LoadedNav: TCastleRecastNavMesh;
  ClimbUpPath, DropDownPath, BlockedChasmPath: TRecastPathResult;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Nav := TRecastNavMeshHelper.SpawnRecastPresetInDesign(
      VP, Root, rnpTwoStoryBridgeAndStairs, Vector3(0, 0, 0));

    { 1. Climbing UP from Courtyard_East (6.5, 0, -2.5) to SniperBastion (8.2, 3.0, 2.6):
      Cannot climb UP the one-way DropDownLedge, so routes via Underpass -> West StairRamp ->
      Overpass Bridge -> JumpChasm (1 NavLink used, longer climb route > 24m)! }
    ClimbUpPath := Nav.FindPath3D(Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
    AssertTrue('Climb-up route via West StairRamp + JumpChasm found', ClimbUpPath.Found);
    AssertEquals(1, ClimbUpPath.UsedLinkCount);
    AssertTrue('Climb-up route traverses underpass & west stairs (> 22m)',
      ClimbUpPath.TotalDistanceM > 22.0);

    { 2. Dropping DOWN from SniperBastion (8.2, 3.0, 2.6) to Courtyard_East (6.5, 0, -2.5):
      Uses JumpChasm + One-Way DropDownLedge shortcut (2 NavLinks, < 16m)! }
    DropDownPath := Nav.FindPath3D(Vector3(8.2, 3.0, 2.6), Vector3(6.5, 0.0, -2.5));
    AssertTrue('Drop-down shortcut route found', DropDownPath.Found);
    AssertEquals(2, DropDownPath.UsedLinkCount);
    AssertTrue('One-way ledge drop saves > 8m vs stair detour!',
      DropDownPath.TotalDistanceM < ClimbUpPath.TotalDistanceM - 8.0);

    { 3. Disabling NL_BridgeToBastionJump isolates SniperBastion completely }
    AssertTrue(Nav.SetNavLinkEnabled('NL_BridgeToBastionJump', False));
    BlockedChasmPath := Nav.FindPath3D(Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
    AssertFalse('Isolated bastion unreachable when JumpChasm NavLink disabled',
      BlockedChasmPath.Found);
    AssertTrue(Nav.SetNavLinkEnabled('NL_BridgeToBastionJump', True));

    { 4. SetTransient-clean JSON roundtrip }
    JsonStr := ComponentToString(Nav);
    AssertEquals('Transient preview boxes excluded from JSON', 0, Pos('TCastleBox', JsonStr));

    LoadOwner := TComponent.Create(nil);
    try
      LoadedNav := StringToComponent(JsonStr, LoadOwner) as TCastleRecastNavMesh;
      AssertEquals(Length(Nav.NavLinks), Length(LoadedNav.NavLinks));
      AssertSameValue(Nav.AgentRadius, LoadedNav.AgentRadius, 1e-3);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolRecastNavMesh.TestUnified113StudioHubAnd36thMcpBuildRecastNavMeshTool;
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify 113 UE Studios in Studio Hub (Phase 393 recast_navmesh) }
  AssertEquals(115, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('recast_navmesh', Entry));
  AssertEquals(393, Entry.PhaseNumber);

  { 2. Verify 36th MCP tool cge_build_recast_navmesh }
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
      AssertEquals(38, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_build_recast_navmesh","arguments":{"action":"spawn_preset","preset":"bridge_2story"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['navVolumeCount']);
        AssertTrue(PayloadObj.Integers['polyCount'] >= 6);
        AssertTrue(PayloadObj.Integers['stackedFloorPairs'] >= 1);
        AssertTrue(PayloadObj.Booleans['pathFound']);
        AssertEquals(115, PayloadObj.Integers['studioCatalogCount']);
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
  RegisterTest(TTestToolRecastNavMesh);
end.
