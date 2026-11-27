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

{ Automated tests for Phase 391: Material Instance Editor & Material Parameter
  Collections (UE 5.5 UMaterialInstanceConstant & UMaterialParameterCollection
  Parity: Multi-Level Parent -> Child -> GrandChild Inheritance, Zero-Recompile
  Scalar/Vector/Texture Overrides vs. Static Switch Permutations, Reset-to-Parent
  Cascade, Cycle Guard, Global MPC Rain Darkening & Blizzard Snow Modulation,
  111-Studio Hub & 34th MCP Tool cge_override_material_instance). }
unit TestToolMaterialInstance;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMaterialInstance = class(TCastleTestCase)
  published
    procedure TestMultiLevelParentChildInheritanceZeroRecompileOverridesAndCycleGuard;
    procedure TestGlobalMpcRainDarkeningSnowBlanketAndJsonRoundtrip;
    procedure TestUnified111StudioHubAnd34thMcpOverrideMaterialInstanceTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleMaterialInstance, ToolMaterialInstance, ToolStudioHub, ToolMcpServer;

procedure TTestToolMaterialInstance.TestMultiLevelParentChildInheritanceZeroRecompileOverridesAndCycleGuard;
var
  Root: TComponent;
  ParentMi, ChildMi, GrandChildMi: TCastleMaterialInstance;
  Surf: TResolvedPbrSurface;
  EffSlot: TMaterialParameterSlot;
  Src: String;
  StartPerm: Integer;
begin
  Root := TComponent.Create(nil);
  try
    ParentMi := TCastleMaterialInstance.Create(Root);
    ParentMi.Name := 'MI_ParentStone';
    ParentMi.ApplyPreset(mipWeatheredCastleStoneParent);

    ChildMi := TCastleMaterialInstance.Create(Root);
    ChildMi.Name := 'MI_ChildMossy';
    ChildMi.ParentInstance := ParentMi;
    ChildMi.ApplyPreset(mipMossyDungeonChild);

    GrandChildMi := TCastleMaterialInstance.Create(Root);
    GrandChildMi.Name := 'MI_GrandChildWetVault';
    GrandChildMi.ParentInstance := ChildMi;
    GrandChildMi.ResetAllOverrides;

    { 1. Cycle protection rejects ParentMi.ParentInstance := GrandChildMi }
    ParentMi.ParentInstance := GrandChildMi;
    AssertTrue(ParentMi.ParentInstance = nil);

    { 2. Multi-level inheritance: GrandChild inherits Roughness=0.64 from Child,
      and UVTiling=3.0 + AlbedoTexture from Parent! }
    AssertTrue(GrandChildMi.GetEffectiveSlot('Roughness', EffSlot, Src));
    AssertSameValue(0.64, EffSlot.ScalarValue, 1e-3);
    AssertTrue(Pos('MI_ChildMossy', Src) > 0);

    AssertTrue(GrandChildMi.GetEffectiveSlot('UVTiling', EffSlot, Src));
    AssertSameValue(3.0, EffSlot.ScalarValue, 1e-3);
    AssertTrue(Pos('MI_ParentStone', Src) > 0);

    { 3. Updating Parent UVTiling -> 6.0 propagates LIVE to Child and GrandChild with 0 shader recompiles! }
    StartPerm := GrandChildMi.ShaderPermutationsCompiled;
    ParentMi.SetScalarParameterValue('UVTiling', 6.0);
    Surf := GrandChildMi.EvaluateEffectiveSurface(nil);
    AssertSameValue(6.0, Surf.FinalUVTiling, 1e-3);
    AssertEquals(StartPerm, GrandChildMi.ShaderPermutationsCompiled);

    { 4. Scalar/Vector/Texture overrides on GrandChild trigger 0 shader recompiles;
      toggling Static Switch increments ShaderPermutationsCompiled by +1! }
    GrandChildMi.SetScalarParameterValue('Metallic', 0.42);
    GrandChildMi.SetVectorParameterValue('BaseColorTint', Vector4(0.20, 0.30, 0.40, 1.0));
    GrandChildMi.SetTextureParameterValue('AlbedoTexture', 'T_VaultWet_D.png');
    AssertEquals(StartPerm, GrandChildMi.ShaderPermutationsCompiled);

    GrandChildMi.SetStaticSwitchParameterValue('bTwoSidedFoliage', True);
    AssertEquals(StartPerm + 1, GrandChildMi.ShaderPermutationsCompiled);

    { 5. ResetParameterToParent('Roughness') on Child falls straight back to Parent's 0.78! }
    AssertTrue(ChildMi.ResetParameterToParent('Roughness'));
    Surf := GrandChildMi.EvaluateEffectiveSurface(nil);
    AssertSameValue(0.78, Surf.FinalRoughness, 1e-3);

    { 6. FreeNotification safety: freeing ParentMi clears ChildMi.ParentInstance cleanly }
    FreeAndNil(ParentMi);
    AssertTrue(ChildMi.ParentInstance = nil);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolMaterialInstance.TestGlobalMpcRainDarkeningSnowBlanketAndJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Mpc, LoadedMpc: TCastleMaterialParameterCollection;
  ParentMi, ChildMi, LoadedMi: TCastleMaterialInstance;
  DrySurf, RainSurf, SnowSurf: TResolvedPbrSurface;
  SpawnedCount: Integer;
  JsonMpc, JsonMi: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    SpawnedCount := TMaterialInstanceHelper.SpawnParentChildMpcShowcaseInDesign(
      VP, Root, Mpc, ParentMi, ChildMi);
    AssertEquals(3, SpawnedCount);
    AssertTrue((Mpc <> nil) and (ParentMi <> nil) and (ChildMi <> nil));

    { 1. Dry Noon baseline }
    TMaterialInstanceHelper.BroadcastMpcPresetInDesign(VP, mpcpClearNoonDry);
    DrySurf := ParentMi.EvaluateEffectiveSurface(Mpc);
    AssertSameValue(0.78, DrySurf.FinalRoughness, 1e-2);
    AssertSameValue(0.48, DrySurf.FinalBaseColor.X, 1e-2);

    { 2. Monsoon Rain MPC darkens porous stone albedo and smooths Roughness toward mirror water! }
    TMaterialInstanceHelper.BroadcastMpcPresetInDesign(VP, mpcpMonsoonRainStorm);
    RainSurf := ParentMi.EvaluateEffectiveSurface(Mpc);
    AssertTrue('Rain darkens porous dielectric stone',
      RainSurf.FinalBaseColor.X < DrySurf.FinalBaseColor.X * 0.80);
    AssertTrue('Rain smooths surface roughness dramatically',
      RainSurf.FinalRoughness < 0.25);
    AssertTrue('Rain adds wet clear-coat sheen',
      RainSurf.FinalClearCoat > 0.50);

    { 3. Blizzard Snow MPC blankets stone in bright frost albedo and raises frosty roughness }
    TMaterialInstanceHelper.BroadcastMpcPresetInDesign(VP, mpcpBlizzardSnowline);
    SnowSurf := ParentMi.EvaluateEffectiveSurface(Mpc);
    AssertTrue('Snow brightens surface albedo above 0.80',
      SnowSurf.FinalBaseColor.X > 0.80);
    AssertTrue('Snow restores rough frost microsurface',
      SnowSurf.FinalRoughness > 0.75);

    { 4. Clean JSON persistence roundtrips for both MPC and MaterialInstance }
    JsonMpc := ComponentToString(Mpc);
    JsonMi := ComponentToString(ParentMi);
    LoadOwner := TComponent.Create(nil);
    try
      LoadedMpc := StringToComponent(JsonMpc, LoadOwner) as TCastleMaterialParameterCollection;
      LoadedMi := StringToComponent(JsonMi, LoadOwner) as TCastleMaterialInstance;
      AssertSameValue(Mpc.SnowCoverage, LoadedMpc.SnowCoverage, 1e-3);
      AssertEquals(ParentMi.OverriddenParameterCount, LoadedMi.OverriddenParameterCount);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolMaterialInstance.TestUnified111StudioHubAnd34thMcpOverrideMaterialInstanceTool;
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
  { 1. Verify 111 UE Studios in Studio Hub (Phase 391 material_instance) }
  AssertEquals(116, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('material_instance', Entry));
  AssertEquals(391, Entry.PhaseNumber);

  { 2. Verify 34th MCP tool cge_override_material_instance }
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
      AssertEquals(39, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_override_material_instance","arguments":{"action":"spawn_showcase"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(3, PayloadObj.Integers['materialInstanceCount']);
        AssertEquals(1, PayloadObj.Integers['parentLinkedInstanceCount']);
        AssertEquals(1, PayloadObj.Integers['mpcCount']);
        AssertEquals(116, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_override_material_instance","arguments":{"action":"broadcast_mpc","mpcPreset":"blizzard_snow"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertSameValue(0.88, PayloadObj.Floats['snowCoverage'], 1e-2);
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
  RegisterTest(TTestToolMaterialInstance);
end.
