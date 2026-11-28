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

{ Automated tests for Phase 399: Static Lightmap & Ambient Occlusion Atlas
  Baker (GPU Lightmass Parity), 119-Studio Hub & 42nd MCP Tool
  (cge_bake_static_lightmaps). }
unit TestToolLightmassBaker;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, fpjson, jsonparser,
  CastleTester, CastleVectors, CastleComponentSerialize,
  CastleUIControls, CastleViewport, CastleTransform,
  CastleLightmassBaker, ToolLightmassBaker, ToolStudioHub, ToolMcpServer;

type
  TTestToolLightmassBaker = class(TCastleTestCase)
  published
    procedure TestCornellColorBleedingBounceMonotonicityShadowAndCornerAmbientOcclusion;
    procedure TestNonOverlappingUv2ChartPackingGutterSeamDilationRebuildFlagAndJsonRoundtrip;
    procedure TestUnified119StudioHubAnd42ndMcpBakeStaticLightmaps;
  end;

implementation

procedure TTestToolLightmassBaker.TestCornellColorBleedingBounceMonotonicityShadowAndCornerAmbientOcclusion;
var
  OwnerComp, RootUi: TComponent;
  VP: TCastleViewport;
  Baker: TCastleLightmassBaker;
  LeftFloorTex, RightFloorTex, ShadowFloorTex, LitFloorTex, CornerTex, OpenFloorTex: TLightmassTexel;
  Lum0, Lum1, Lum2: Single;
begin
  OwnerComp := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    VP := TCastleViewport.Create(OwnerComp);
    TCastleUserInterface(RootUi).InsertFront(VP);

    Baker := TLightmassBakerHelper.SpawnLightmassPresetInDesign(
      RootUi, OwnerComp, lbpCornellColorBleedRoom, Vector3(0, 0, 0));
    AssertTrue(Baker <> nil);
    AssertFalse(Baker.LightingNeedsRebuild);

    { 1. Multi-bounce indirect GI luminance strictly increases from 0 -> 1 -> 2 bounces }
    Baker.IndirectBounces := 0;
    Baker.BakeStaticLightmaps;
    Lum0 := Baker.AverageIndirectLuminance;
    AssertSameValue(0.0, Lum0, 0.0001);

    Baker.IndirectBounces := 1;
    Baker.BakeStaticLightmaps;
    Lum1 := Baker.AverageIndirectLuminance;
    AssertTrue(Lum1 > 0.04);

    Baker.IndirectBounces := 2;
    Baker.BakeStaticLightmaps;
    Lum2 := Baker.AverageIndirectLuminance;
    AssertTrue(Lum2 > Lum1);

    { 2. Cornell Color Bleeding: Floor near Left Red Wall (U=0.08, V=0.5) has Red > Blue * 1.4;
         Floor near Right Blue Wall (U=0.92, V=0.5) has Blue > Red * 1.4! }
    LeftFloorTex := Baker.SampleChartTexelNearUV(0, 0.08, 0.50);
    RightFloorTex := Baker.SampleChartTexelNearUV(0, 0.92, 0.50);
    AssertTrue(LeftFloorTex.IndirectRGB.X > LeftFloorTex.IndirectRGB.Z * 1.40);
    AssertTrue(RightFloorTex.IndirectRGB.Z > RightFloorTex.IndirectRGB.X * 1.40);

    { 3. Direct Sun Shadow: Floor behind CenterOccluderBlock (U=0.50, V=0.30 -> Z=-1.2)
         is in shadow vs front sunlit floor (U=0.50, V=0.90 -> Z=+2.4) }
    ShadowFloorTex := Baker.SampleChartTexelNearUV(0, 0.50, 0.30);
    LitFloorTex := Baker.SampleChartTexelNearUV(0, 0.50, 0.90);
    AssertTrue(LitFloorTex.DirectRGB.X > 1.0);
    AssertSameValue(0.0, ShadowFloorTex.DirectRGB.X, 0.01);

    { 4. Hemisphere Sky AO: Deep back-left room corner (U=0.04, V=0.04) is darker
         than open front-center floor threshold (U=0.50, V=0.95) }
    CornerTex := Baker.SampleChartTexelNearUV(0, 0.04, 0.04);
    OpenFloorTex := Baker.SampleChartTexelNearUV(0, 0.50, 0.95);
    AssertTrue(CornerTex.SkyAo01 < OpenFloorTex.SkyAo01 - 0.15);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolLightmassBaker.TestNonOverlappingUv2ChartPackingGutterSeamDilationRebuildFlagAndJsonRoundtrip;
var
  OwnerComp, RehydratedOwner: TComponent;
  Baker, RehydratedBaker: TCastleLightmassBaker;
  I, J: Integer;
  A, B: TLightmassSurfaceChart;
  Overlaps: Boolean;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Baker := TCastleLightmassBaker.Create(OwnerComp);
    Baker.Name := 'TestLightmassAtlas';
    AssertEquals(6, Baker.ChartCount);

    { 1. Verify zero rectangle overlap across all 6 UV2 charts }
    for I := 0 to Baker.ChartCount - 1 do
      for J := I + 1 to Baker.ChartCount - 1 do
      begin
        A := Baker.Charts[I];
        B := Baker.Charts[J];
        Overlaps := (A.AtlasX < B.AtlasX + B.AtlasW) and (A.AtlasX + A.AtlasW > B.AtlasX) and
                    (A.AtlasY < B.AtlasY + B.AtlasH) and (A.AtlasY + A.AtlasH > B.AtlasY);
        AssertFalse(Overlaps);
      end;

    { 2. Verify 2-pass Gutter Seam Dilation eliminates all raw black border neighbors! }
    AssertTrue(Baker.ValidInteriorTexelCount >= 180);
    AssertTrue(Baker.DilatedBorderTexelCount >= 120);
    AssertEquals(0, Baker.UndilatedAdjacentGutterCount);

    { Without dilation (0 passes), interior border texels touch raw empty gutters }
    Baker.DilateGutterPasses := 0;
    AssertTrue(Baker.LightingNeedsRebuild);
    Baker.BakeStaticLightmaps;
    AssertFalse(Baker.LightingNeedsRebuild);
    AssertTrue(Baker.UndilatedAdjacentGutterCount > 50);

    { Restore 2-pass dilation }
    Baker.DilateGutterPasses := 2;
    Baker.BakeStaticLightmaps;
    AssertEquals(0, Baker.UndilatedAdjacentGutterCount);

    { 3. Lossless JSON serialization roundtrip }
    JsonStr := ComponentToString(Baker);
    RehydratedOwner := TComponent.Create(nil);
    try
      RehydratedBaker := StringToComponent(JsonStr, RehydratedOwner) as TCastleLightmassBaker;
      AssertFalse(RehydratedBaker.LightingNeedsRebuild);
      AssertEquals(0, RehydratedBaker.UndilatedAdjacentGutterCount);
      AssertSameValue(Baker.AverageSkyAo01, RehydratedBaker.AverageSkyAo01, 0.002);
    finally
      FreeAndNil(RehydratedOwner);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolLightmassBaker.TestUnified119StudioHubAnd42ndMcpBakeStaticLightmaps;
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
  AssertTrue(TStudioHubManager.FindStudioById('lightmass_baker', Entry));
  AssertEquals(399, Entry.PhaseNumber);

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
        if TJSONObject(ToolsArr.Items[I]).Get('name', '') = 'cge_bake_static_lightmaps' then
          FoundTool := True;
      AssertTrue(FoundTool);
    finally
      FreeAndNil(ParsedResp);
    end;

    { 1. Spawn Cornell GPU Lightmass Baker via MCP }
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_bake_static_lightmaps","arguments":{"action":"spawn_preset","preset":"cornell_room"}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(1, TJSONObject(InnerData).Get('bakerCount', 0));
        AssertEquals(6, TJSONObject(InnerData).Get('chartCount', 0));
        AssertEquals(119, TJSONObject(InnerData).Get('studioCatalogCount', 0));
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    { 2. Invalidate then Bake 3-bounce Lightmap via MCP }
    Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_bake_static_lightmaps","arguments":{"action":"invalidate_lighting"}}}');
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cge_bake_static_lightmaps","arguments":{"action":"bake_lightmaps","bounces":3}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(0, TJSONObject(InnerData).Get('unbuiltVolumeCount', -1));
        AssertEquals(0, TJSONObject(InnerData).Get('undilatedSeamLeaks', -1));
        AssertTrue(TJSONObject(InnerData).Get('avgIndirectLum', 0.0) > 0.05);
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
  RegisterTest(TTestToolLightmassBaker);

end.
