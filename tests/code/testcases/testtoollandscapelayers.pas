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

{ Automated tests for Phase 394: Non-Destructive Landscape Edit Layers &
  Terrain-Carving Landscape Splines (UE 5.5 Landscape Edit Layers &
  ULandscapeSplinesComponent Parity: Zero-Drift Non-Destructive Mute/Opacity
  Layer Compositing, Hillside Cut & Valley Causeway Fill Spline Deformation,
  Lower-Only River Trench Constraint, 4-Channel Normalized Splatmaps,
  114-Studio Hub & 37th MCP Tool cge_carve_landscape_layer_spline). }
unit TestToolLandscapeLayers;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolLandscapeLayers = class(TCastleTestCase)
  published
    procedure TestNonDestructiveSplineLayerMuteZeroDriftOpacityBlendAndCutFillEarthwork;
    procedure TestHillsideCutValleyCausewayFillRiverTrenchSplatSumAndCleanJsonRoundtrip;
    procedure TestUnified114StudioHubAnd37thMcpCarveLandscapeLayerSplineTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleLandscapeLayers, ToolLandscapeLayers, ToolStudioHub, ToolMcpServer;

procedure TTestToolLandscapeLayers.TestNonDestructiveSplineLayerMuteZeroDriftOpacityBlendAndCutFillEarthwork;
var
  Root: TComponent;
  VP: TCastleViewport;
  Terr: TCastleLandscapeLayerTerrain;
  CarvedWestH, UncarvedWestH, HalfBlendWestH: Single;
  GX, GZ: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Terr := TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
      VP, Root, llpAlpinePassSwitchbackRoadAndRiver, Vector3(0, 0, 0));
    AssertTrue(Terr <> nil);

    { 1. Active spline layer produces both hillside Cut (> 400 m^3) and valley Fill (> 400 m^3) }
    AssertTrue('Hillside cut volume > 400 m^3', Terr.Metrics.CutExcavatedVolumeM3 > 400.0);
    AssertTrue('Valley embankment fill volume > 400 m^3', Terr.Metrics.FillEmbankmentVolumeM3 > 400.0);
    AssertTrue('Cobble road splat area > 150 m^2', Terr.Metrics.RoadPaintedAreaM2 > 150.0);

    CarvedWestH := Terr.SampleHeightBilinear(-12.0, 0.0);
    AssertSameValue(6.50, CarvedWestH, 1e-2);

    { 2. Muting 02_LandscapeSplines restores EVERY grid vertex to exact underlying mountain (0.0m drift!) }
    AssertTrue(Terr.SetLayerVisible('02_LandscapeSplines', False));
    AssertSameValue(0.0, Terr.Metrics.CutExcavatedVolumeM3, 1e-3);
    AssertSameValue(0.0, Terr.Metrics.FillEmbankmentVolumeM3, 1e-3);
    for GZ := 0 to Terr.GridRes - 1 do
      for GX := 0 to Terr.GridRes - 1 do
        AssertSameValue(
          Terr.SampleBaseBeforeSplinesAtGrid(GX, GZ),
          Terr.SampleHeightAtGrid(GX, GZ), 1e-4);

    UncarvedWestH := Terr.SampleHeightBilinear(-12.0, 0.0);
    AssertTrue('Uncarved West mountain ridge > 11.0m', UncarvedWestH > 11.0);

    { 3. Re-enabling at 50% Opacity blends exactly halfway between uncarved ridge and 6.5m road! }
    AssertTrue(Terr.SetLayerVisible('02_LandscapeSplines', True));
    AssertTrue(Terr.SetLayerOpacity('02_LandscapeSplines', 0.50));
    HalfBlendWestH := Terr.SampleHeightBilinear(-12.0, 0.0);
    AssertSameValue((UncarvedWestH + 6.50) * 0.5, HalfBlendWestH, 5e-2);

    AssertTrue(Terr.SetLayerOpacity('02_LandscapeSplines', 1.00));
    AssertSameValue(6.50, Terr.SampleHeightBilinear(-12.0, 0.0), 1e-2);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolLandscapeLayers.TestHillsideCutValleyCausewayFillRiverTrenchSplatSumAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Terr, CausewayTerr, LoadedTerr: TCastleLandscapeLayerTerrain;
  SpRoad, SpCell: TVector4;
  GX, GZ: Integer;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Terr := TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
      VP, Root, llpAlpinePassSwitchbackRoadAndRiver, Vector3(0, 0, 0));

    { 1. East valley (+10, 0) was < 3.0m before splines, and is raised to 6.50m embankment causeway! }
    AssertSameValue(6.50, Terr.SampleHeightBilinear(10.0, 0.0), 1e-2);
    SpRoad := Terr.SampleSplatNearest(10.0, 0.0);
    AssertTrue('CobbleRoad splat channel Z = 1.0 on road centerline', SpRoad.Z > 0.95);

    { 2. Every vertex across the 33x33 terrain has partition-of-unity 4-channel splat sum = 1.000! }
    for GZ := 0 to Terr.GridRes - 1 do
      for GX := 0 to Terr.GridRes - 1 do
      begin
        SpCell := Terr.SampleSplatAtGrid(GX, GZ);
        AssertSameValue(1.0, SpCell.X + SpCell.Y + SpCell.Z + SpCell.W, 1e-3);
      end;

    { 3. Raise-Only Causeway mode (Desert Highway) has Fill > 0 and Cut = 0! }
    CausewayTerr := TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
      VP, Root, llpDesertCanyonHighwayCauseway, Vector3(80, 0, 0));
    AssertSameValue(0.0, CausewayTerr.Metrics.CutExcavatedVolumeM3, 1e-2);
    AssertTrue(CausewayTerr.Metrics.FillEmbankmentVolumeM3 > 100.0);

    { 4. SetTransient-clean JSON roundtrip }
    AssertTrue(Terr.SetLayerOpacity('02_LandscapeSplines', 0.75));
    JsonStr := ComponentToString(Terr);
    AssertEquals('Transient preview tiles excluded from JSON', 0, Pos('TCastleBox', JsonStr));

    LoadOwner := TComponent.Create(nil);
    try
      LoadedTerr := StringToComponent(JsonStr, LoadOwner) as TCastleLandscapeLayerTerrain;
      AssertSameValue(0.75, LoadedTerr.Layers[LoadedTerr.FindLayerIndex('02_LandscapeSplines')].Opacity, 1e-3);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolLandscapeLayers.TestUnified114StudioHubAnd37thMcpCarveLandscapeLayerSplineTool;
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
  { 1. Verify 114 UE Studios in Studio Hub (Phase 394 landscape_layers_splines) }
  AssertEquals(114, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('landscape_layers_splines', Entry));
  AssertEquals(394, Entry.PhaseNumber);

  { 2. Verify 37th MCP tool cge_carve_landscape_layer_spline }
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
      AssertEquals(37, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_carve_landscape_layer_spline","arguments":{"action":"spawn_preset","preset":"alpine_switchback"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['landscapeCount']);
        AssertEquals(3, PayloadObj.Integers['totalEditLayers']);
        AssertEquals(2, PayloadObj.Integers['totalSplines']);
        AssertTrue(PayloadObj.Floats['cutVolumeM3'] > 400.0);
        AssertTrue(PayloadObj.Floats['fillVolumeM3'] > 400.0);
        AssertEquals(114, PayloadObj.Integers['studioCatalogCount']);
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
  RegisterTest(TTestToolLandscapeLayers);
end.
