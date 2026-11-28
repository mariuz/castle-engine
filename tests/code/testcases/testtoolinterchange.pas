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

{ Automated tests for Phase 398: Interchange Asset Import Pipeline & Reimport
  Rules (UInterchangeManager Parity), 118-Studio Hub & 41st MCP Tool
  (cge_run_interchange_import). }
unit TestToolInterchange;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, fpjson, jsonparser,
  CastleTester, CastleVectors, CastleComponentSerialize,
  CastleUIControls, CastleViewport, CastleTransform,
  CastleInterchange, ToolInterchange, ToolStudioHub, ToolMcpServer;

type
  TTestToolInterchange = class(TCastleTestCase)
  published
    procedure TestZUpCentimeterConversionUcxSocketExtractionAndTextureColorSpaceRules;
    procedure TestNonDestructiveOneClickReimportPreservingUserSlotOverridesAndJsonRoundtrip;
    procedure TestUnified118StudioHubAnd41stMcpRunInterchangeImport;
  end;

implementation

procedure TTestToolInterchange.TestZUpCentimeterConversionUcxSocketExtractionAndTextureColorSpaceRules;
var
  OwnerComp, RootUi: TComponent;
  VP: TCastleViewport;
  Pipe: TCastleInterchangePipeline;
  Bounds, ConvPos: TVector3;
  I: Integer;
  A: TInterchangeTranslatedAsset;
  FoundBc, FoundNormalDx, FoundOrm: Boolean;
begin
  OwnerComp := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    VP := TCastleViewport.Create(OwnerComp);
    TCastleUserInterface(RootUi).InsertFront(VP);

    Pipe := TInterchangeHelper.SpawnInterchangePresetInDesign(
      RootUi, OwnerComp, ippModularArchitectureProps, Vector3(0, 0, 0));
    AssertTrue(Pipe <> nil);

    { 1. Blender Z-Up cm (450 x 40 x 520 cm) -> CGE Y-Up meters (4.50 x 5.20 x 0.40 m)! }
    Bounds := Pipe.PrimaryMeshBoundsMeters;
    AssertSameValue(4.50, Bounds.X, 0.001);
    AssertSameValue(5.20, Bounds.Y, 0.001);
    AssertSameValue(0.40, Bounds.Z, 0.001);

    { Position swizzle: Blender (-145, -25, 305) cm -> CGE (-1.45, +3.05, +0.25) m }
    ConvPos := Pipe.ConvertDccPositionToCgeMeters(Vector3(-145, -25, 305));
    AssertSameValue(-1.45, ConvPos.X, 0.001);
    AssertSameValue(3.05, ConvPos.Y, 0.001);
    AssertSameValue(0.25, ConvPos.Z, 0.001);

    { 2. UCX_/UBX_/USP_ (4 hulls = 220 tris) & SOCKET_ (2 sockets) stripped from visual tris (1920 + 920 = 2840) }
    AssertEquals(2840, Pipe.TotalVisualTriangles);
    AssertEquals(4, Pipe.ExtractedColliderCount);
    AssertEquals(2, Pipe.ExtractedSocketCount);

    { 3. PBR Texture Color-Space & DirectX Normal Green-Channel Flip Rules }
    FoundBc := False;
    FoundNormalDx := False;
    FoundOrm := False;
    for I := 0 to Pipe.TranslatedAssetCount - 1 do
    begin
      A := Pipe.TranslatedAssets[I];
      if A.AssetName = 'T_FortressStone_BC' then
      begin
        FoundBc := True;
        AssertTrue(A.IsSrgbGamma);
        AssertFalse(A.FlipNormalGreenChannel);
      end else
      if A.AssetName = 'T_FortressStone_N_DX' then
      begin
        FoundNormalDx := True;
        AssertFalse(A.IsSrgbGamma);
        AssertTrue(A.FlipNormalGreenChannel);
      end else
      if A.AssetName = 'T_FortressStone_ORM' then
      begin
        FoundOrm := True;
        AssertFalse(A.IsSrgbGamma);
        AssertFalse(A.FlipNormalGreenChannel);
      end;
    end;
    AssertTrue(FoundBc and FoundNormalDx and FoundOrm);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolInterchange.TestNonDestructiveOneClickReimportPreservingUserSlotOverridesAndJsonRoundtrip;
var
  OwnerComp, RehydratedOwner: TComponent;
  Pipe, RehydratedPipe: TCastleInterchangePipeline;
  JsonStr: String;
const
  CustomSteelUrl = 'castle-data:/materials/MI_RustedDamascusSteel.castle-material';
begin
  OwnerComp := TComponent.Create(nil);
  try
    Pipe := TCastleInterchangePipeline.Create(OwnerComp);
    Pipe.Name := 'TestInterchangeGate';
    AssertEquals(1, Pipe.ReimportRevision);
    AssertEquals(0, Pipe.LockedSlotOverrideCount);

    { Artist assigns custom Material Instance to Slot_PortcullisIron in-editor }
    Pipe.SetUserMaterialSlotOverride('Slot_PortcullisIron', CustomSteelUrl);
    AssertEquals(1, Pipe.LockedSlotOverrideCount);
    AssertEquals(CustomSteelUrl, Pipe.GetEffectiveMaterialSlotUrl('Slot_PortcullisIron'));

    { Artist exports v2 FBX (+420 visual triangles + new SOCKET_BannerPole) & clicks 1-Click Reimport }
    Pipe.SimulateReimportUpdatedDccSource(420, 'SOCKET_BannerPole');
    AssertEquals(2, Pipe.ReimportRevision);
    AssertEquals(3260, Pipe.TotalVisualTriangles);
    AssertEquals(3, Pipe.ExtractedSocketCount);

    { User-locked Material Instance override MUST remain 100% intact across Reimport! }
    AssertEquals(1, Pipe.LockedSlotOverrideCount);
    AssertEquals(CustomSteelUrl, Pipe.GetEffectiveMaterialSlotUrl('Slot_PortcullisIron'));
    AssertEquals('castle-data:/materials/MI_Slot_AshlarStone.castle-material',
      Pipe.GetEffectiveMaterialSlotUrl('Slot_AshlarStone'));

    { Lossless JSON roundtrip preserves v2 geometry, sockets & locked MI override }
    JsonStr := ComponentToString(Pipe);
    RehydratedOwner := TComponent.Create(nil);
    try
      RehydratedPipe := StringToComponent(JsonStr, RehydratedOwner) as TCastleInterchangePipeline;
      AssertEquals(2, RehydratedPipe.ReimportRevision);
      AssertEquals(3260, RehydratedPipe.TotalVisualTriangles);
      AssertEquals(3, RehydratedPipe.ExtractedSocketCount);
      AssertEquals(CustomSteelUrl, RehydratedPipe.GetEffectiveMaterialSlotUrl('Slot_PortcullisIron'));
    finally
      FreeAndNil(RehydratedOwner);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolInterchange.TestUnified118StudioHubAnd41stMcpRunInterchangeImport;
var
  Entry: TStudioCatalogEntry;
  Mcp: TCastleMcpServer;
  OwnerComp, RootUi: TComponent;
  VP: TCastleViewport;
  ListResp, CallResp, MdReport: String;
  ParsedResp, InnerData: TJSONData;
  ToolsArr: TJSONArray;
  FoundTool: Boolean;
  I: Integer;
begin
  AssertEquals(119, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('interchange_pipeline', Entry));
  AssertEquals(398, Entry.PhaseNumber);

  OwnerComp := TComponent.Create(nil);
  Mcp := TCastleMcpServer.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    RootUi.Name := 'RootUi';
    VP := TCastleViewport.Create(OwnerComp);
    VP.Name := 'ViewportMain';
    TCastleUserInterface(RootUi).InsertFront(VP);

    Mcp.AutonomyMode := mamFullControl;
    Mcp.StandaloneDesignRoot := RootUi;
    Mcp.StandaloneDesignOwner := OwnerComp;

    ListResp := Mcp.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    ParsedResp := GetJSON(ListResp);
    try
      ToolsArr := ParsedResp.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(42, ToolsArr.Count);
      FoundTool := False;
      for I := 0 to ToolsArr.Count - 1 do
        if TJSONObject(ToolsArr.Items[I]).Get('name', '') = 'cge_run_interchange_import' then
          FoundTool := True;
      AssertTrue(FoundTool);
    finally
      FreeAndNil(ParsedResp);
    end;

    { 1. Spawn Architecture Interchange Pipeline via MCP }
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_run_interchange_import","arguments":{"action":"spawn_preset","preset":"architecture_fbx"}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(1, TJSONObject(InnerData).Get('pipelineCount', 0));
        AssertEquals(4, TJSONObject(InnerData).Get('extractedColliders', 0));
        AssertEquals(119, TJSONObject(InnerData).Get('studioCatalogCount', 0));
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    { 2. Lock slot override + run 1-Click Reimport via MCP }
    Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_run_interchange_import","arguments":{"action":"lock_slot_override","slotName":"Slot_PortcullisIron","miUrl":"castle-data:/materials/MI_RustedDamascusSteel.castle-material"}}}');
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cge_run_interchange_import","arguments":{"action":"reimport_dcc_update"}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(2, TJSONObject(InnerData).Get('reimportRevision', 0));
        AssertEquals(1, TJSONObject(InnerData).Get('lockedOverrides', 0));
        AssertEquals(3, TJSONObject(InnerData).Get('extractedSockets', 0));
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    MdReport := TStudioHubManager.BuildExecutiveMarkdownReport(RootUi, OwnerComp);
    AssertTrue(Pos('`119` across `6` domains', MdReport) > 0);
  finally
    FreeAndNil(Mcp);
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolInterchange);

end.
