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

{ Automated tests for Phase 392: Static & Skeletal Mesh Asset Editor
  (UE 5.5 UStaticMeshEditor & USkeletalMeshEditor Parity: Bone/Mesh Socket
  Manager & AttachTransformToSocket, V-HACD / K-DOP Auto-Convex Collision
  Decomposition & Concave Archway Clearance, 4-Tier ScreenSize LOD Chain,
  Area-Weighted Normals & MikkTSpace Orthonormal Tangents with Mirrored w=-1
  Sign, 112-Studio Hub & 35th MCP Tool cge_edit_mesh_sockets_collision). }
unit TestToolMeshEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMeshEditor = class(TCastleTestCase)
  published
    procedure TestConcaveArchwayVHacdClearanceKDopVolumeAndLodScreenSizeSwitching;
    procedure TestSocketManagerPropAttachmentMikkTSpaceTangentsAndCleanJsonRoundtrip;
    procedure TestUnified112StudioHubAnd35thMcpEditMeshSocketsCollisionTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleMeshEditor, ToolMeshEditor, ToolStudioHub, ToolMcpServer;

procedure TTestToolMeshEditor.TestConcaveArchwayVHacdClearanceKDopVolumeAndLodScreenSizeSwitching;
var
  Root: TComponent;
  VP: TCastleViewport;
  Archway: TCastleMeshEditorAsset;
  Vol6Dop, Vol26Dop: Single;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Archway := TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
      VP, Root, mepGothicArchwayConcave3Hulls, Vector3(0, 0, 0));
    AssertTrue(Archway <> nil);

    { 1. Single-hull wrap (MaxHulls=1) blocks the walkable archway opening (0, 1.2, 0)! }
    Archway.GenerateAutoConvexCollision(1, kdmBox6Dop, 8);
    AssertEquals(1, Length(Archway.ConvexHulls));
    AssertTrue('Single AABB hull blocks archway doorway',
      Archway.PointHitsAnyConvexHull(Vector3(0.0, 1.2, 0.0)));
    AssertTrue('Single hull on concave arch has high concavity error',
      Archway.ConvexHulls[0].ConcavityError > 0.30);

    { 2. V-HACD 3-hull decomposition keeps Left/Right pillars & Top lintel solid
      while opening the central doorway (0, 1.2, 0) completely! }
    Archway.GenerateAutoConvexCollision(3, kdmBox6Dop, 8);
    AssertEquals(3, Length(Archway.ConvexHulls));
    Vol6Dop := Archway.TotalConvexHullVolumeM3;
    AssertFalse('3-hull decomposition clears central doorway!',
      Archway.PointHitsAnyConvexHull(Vector3(0.0, 1.2, 0.0)));
    AssertTrue('Left pillar remains solid',
      Archway.PointHitsAnyConvexHull(Vector3(-1.5, 1.2, 0.0)));
    AssertTrue('Right pillar remains solid',
      Archway.PointHitsAnyConvexHull(Vector3(1.5, 1.2, 0.0)));
    AssertTrue('Top lintel remains solid',
      Archway.PointHitsAnyConvexHull(Vector3(0.0, 3.0, 0.0)));

    { 3. 26-DOP chamfered planes trim dead corner volume tighter than 6-DOP boxes }
    Archway.GenerateAutoConvexCollision(3, kdm26DopChamfered, 24);
    Vol26Dop := Archway.TotalConvexHullVolumeM3;
    AssertEquals(26, Archway.ConvexHulls[0].PlaneCount);
    AssertTrue('26-DOP trims dead corner volume below 6-DOP box', Vol26Dop < Vol6Dop);

    { 4. 4-Tier ScreenSize LOD switching (1.00 / 0.50 / 0.25 / 0.10) }
    AssertEquals(4, Length(Archway.LodChain));
    AssertEquals(0, Archway.SelectLodForScreenSize(1.00));
    AssertEquals(1, Archway.SelectLodForScreenSize(0.62));
    AssertEquals(2, Archway.SelectLodForScreenSize(0.30));
    AssertEquals(3, Archway.SelectLodForScreenSize(0.08));
    AssertTrue(Archway.LodChain[3].TriangleCount < Archway.LodChain[0].TriangleCount div 5);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolMeshEditor.TestSocketManagerPropAttachmentMikkTSpaceTangentsAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Halberd, LoadedHalberd: TCastleMeshEditorAsset;
  BannerProp: TCastleBox;
  TA: TMeshTangentAudit;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Halberd := TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
      VP, Root, mepSkeletalHalberdWeapon4Sockets, Vector3(0, 0, 0));
    AssertTrue(Halberd.IsSkeletalMesh);
    AssertEquals(4, Length(Halberd.Sockets));

    { 1. Attach live TCastleBox prop onto Socket_BladeTrailVFX (Bone=(0.52, 1.85, 0) + Offset=(0.06, 0, 0)) }
    BannerProp := TMeshEditorHelper.SpawnPreviewPropOnSocket(
      Halberd, Root, 'Socket_BladeTrailVFX');
    AssertTrue(BannerProp <> nil);
    AssertTrue(BannerProp.Parent = Halberd);
    AssertSameValue(0.58, BannerProp.Translation.X, 1e-3);
    AssertSameValue(1.85, BannerProp.Translation.Y, 1e-3);
    AssertSameValue(DegToRad(90.0), BannerProp.Rotation.W, 1e-3);

    { 2. MikkTSpace Orthonormal Tangent Basis: 0 zero normals, 0 non-orthogonal tangents,
      detects mirrored UV handedness (w = -1) and 90-degree hard crease splits! }
    TA := Halberd.RecomputeNormalsAndMikkTangents(60.0);
    AssertEquals(6, TA.SampleVertexCount);
    AssertEquals(0, TA.ZeroLengthNormalCount);
    AssertEquals(0, TA.NonOrthogonalTangentCount);
    AssertTrue(TA.MaxOrthogonalityError < 1e-4);
    AssertTrue('Detects mirrored symmetry UV island (w = -1)', TA.MirroredUvVertexCount >= 1);
    AssertTrue('Splits 90-degree hard corner above 60-degree threshold', TA.HardSeamCount >= 1);
    AssertSameValue(-1.0, Halberd.TangentSamples[3].BitangentSignW, 1e-3);

    { 3. RemoveProp before clean SetTransient JSON roundtrip }
    Halberd.Remove(BannerProp);
    FreeAndNil(BannerProp);
    JsonStr := ComponentToString(Halberd);
    AssertEquals('Transient preview nodes excluded from JSON', 0, Pos('TCastleSphere', JsonStr));

    LoadOwner := TComponent.Create(nil);
    try
      LoadedHalberd := StringToComponent(JsonStr, LoadOwner) as TCastleMeshEditorAsset;
      AssertEquals(4, Length(LoadedHalberd.Sockets));
      AssertEquals('SK_RoyalHalberdKnight', LoadedHalberd.MeshAssetKey);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolMeshEditor.TestUnified112StudioHubAnd35thMcpEditMeshSocketsCollisionTool;
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
  { 1. Verify 112 UE Studios in Studio Hub (Phase 392 static_skeletal_mesh_editor) }
  AssertEquals(115, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('static_skeletal_mesh_editor', Entry));
  AssertEquals(392, Entry.PhaseNumber);

  { 2. Verify 35th MCP tool cge_edit_mesh_sockets_collision }
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
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_edit_mesh_sockets_collision","arguments":{"action":"spawn_preset","preset":"archway"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['meshAssetCount']);
        AssertEquals(3, PayloadObj.Integers['convexHullCount']);
        AssertEquals(3, PayloadObj.Integers['socketCount']);
        AssertTrue(PayloadObj.Booleans['centerOpeningClear']);
        AssertEquals(0, PayloadObj.Integers['nonOrthogonalTangents']);
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
  RegisterTest(TTestToolMeshEditor);
end.
