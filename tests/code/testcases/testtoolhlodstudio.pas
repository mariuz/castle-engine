{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 333 World Partition Hierarchical LOD (HLOD)
  Spatial Cluster Baker, Proxy Synthesis & Hysteresis Swapper. }
unit TestToolHlodStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolHlodStudio = class(TCastleTestCase)
  published
    procedure TestSpatialCellClusteringDrawCallCompressionAndHysteresisDeadbandSwap;
    procedure TestProxyModesRestoreFullDetailAndCsTransientCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleHlodBaker, ToolHlodStudio;

procedure TTestToolHlodStudio.TestSpatialCellClusteringDrawCallCompressionAndHysteresisDeadbandSwap;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Mgr: TCastleHlodClusterManager;
  Beacon, PropSample: TCastleTransform;
  Cell0Center: TVector3;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    AssertTrue(THlodStudioHelper.SpawnCityDistrictHlodDemo(Vp, DesignOwner, Mgr));
    AssertTrue(Mgr <> nil);
    AssertEquals(4, Mgr.CellCount);
    AssertEquals(16, Mgr.TotalClusteredProps);
    AssertEquals(16, Mgr.BaselineDrawCalls);

    { HlodIgnore_HeroBeacon must be excluded from clustering and stay visible }
    Beacon := DesignOwner.FindComponent('HlodIgnore_HeroBeacon') as TCastleTransform;
    AssertTrue(Beacon <> nil);
    AssertTrue(Beacon.Exists);

    { Near camera at origin: all 4 cells (~34m away < 45 + 5 = 50m) stay Full Detail }
    Mgr.EvaluateCameraDistanceSwap(Vector3(0, 4, 0), Vp.Items, DesignOwner);
    AssertEquals(0, Mgr.ActiveHlodCellCount);
    AssertEquals(16, Mgr.EffectiveDrawCalls);
    PropSample := DesignOwner.FindComponent('DistrictBuilding_Q1_P1') as TCastleTransform;
    AssertTrue(PropSample <> nil);
    AssertTrue(PropSample.Exists);
    AssertFalse(Mgr.ProxySceneForCell(0).Exists);

    { Far camera at Z = 130m: all 4 cells (> 50m) switch to single-draw HLOD proxies }
    Mgr.EvaluateCameraDistanceSwap(Vector3(0, 8, 130), Vp.Items, DesignOwner);
    AssertEquals(4, Mgr.ActiveHlodCellCount);
    AssertEquals(4, Mgr.EffectiveDrawCalls);
    AssertSameValue(0.75, Mgr.DrawCallReductionRatio, 0.001);
    AssertFalse(PropSample.Exists);
    AssertTrue(Mgr.ProxySceneForCell(0).Exists);
    { Ignored dynamic beacon remains untouched }
    AssertTrue(Beacon.Exists);

    { Hysteresis deadband verification on Cell 0: Switch = 45m, Margin = 5m -> [40..50m] }
    Cell0Center := Mgr.GetCell(0).WorldCenter;
    { Moving from Far (HLOD=True) to 43.0m (inside deadband >= 40m) must remain HLOD }
    Mgr.EvaluateCameraDistanceSwap(Cell0Center + Vector3(0, 0, 43.0), Vp.Items, DesignOwner);
    AssertTrue(Mgr.GetCell(0).UsingHlodProxy);

    { Stepping inside inner threshold (38.0m < 40.0m) switches back to Full Detail }
    Mgr.EvaluateCameraDistanceSwap(Cell0Center + Vector3(0, 0, 38.0), Vp.Items, DesignOwner);
    AssertFalse(Mgr.GetCell(0).UsingHlodProxy);

    { Stepping outward to 47.0m (inside deadband <= 50.0m) stays Full Detail (no thrashing) }
    Mgr.EvaluateCameraDistanceSwap(Cell0Center + Vector3(0, 0, 47.0), Vp.Items, DesignOwner);
    AssertFalse(Mgr.GetCell(0).UsingHlodProxy);

    { Stepping past outer threshold (52.0m > 50.0m) switches to HLOD }
    Mgr.EvaluateCameraDistanceSwap(Cell0Center + Vector3(0, 0, 52.0), Vp.Items, DesignOwner);
    AssertTrue(Mgr.GetCell(0).UsingHlodProxy);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolHlodStudio.TestProxyModesRestoreFullDetailAndCsTransientCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Mgr, RestoredMgr: TCastleHlodClusterManager;
  JsonStr, ReportMd: String;
  Warnings: TStringList;
  Sum: THlodStudioSummary;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(THlodStudioHelper.SpawnCityDistrictHlodDemo(Vp, DesignOwner, Mgr));

    { Clustered boxes: 4 props * 12 tris = 48 tris in 1 TTriangleSetNode }
    AssertEquals(48, Mgr.GetCell(0).ProxyTrianglesCount);

    { Merged cell bounds: 12 tris per cell }
    Mgr.ProxyMode := hpmMergedCellBounds;
    AssertEquals(12, Mgr.GetCell(0).ProxyTrianglesCount);

    { Octagonal skyline prism: 28 tris per cell }
    Mgr.ProxyMode := hpmOctagonalPrism;
    AssertEquals(28, Mgr.GetCell(0).ProxyTrianglesCount);

    { Switch to far HLOD, verify polygon compression (4 * 28 = 112 vs 3*12+128 = 164*4 = 656) }
    Mgr.EvaluateCameraDistanceSwap(Vector3(0, 10, 140), Vp.Items, DesignOwner);
    AssertEquals(656, Mgr.BaselineTriangles);
    AssertEquals(112, Mgr.EffectiveTriangles);

    Sum := THlodStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(0, Sum.WarningsCount);
    AssertSameValue(75.0, Sum.DrawCallSavingsPercent, 0.1);
    ReportMd := THlodStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('World Partition HLOD Cluster Report', ReportMd) > 0);

    { RestoreAllFullDetailProps brings all 16 source props back before serialization }
    Mgr.RestoreAllFullDetailProps(Vp.Items, DesignOwner);
    AssertEquals(0, Mgr.ActiveHlodCellCount);
    AssertTrue((DesignOwner.FindComponent('DistrictTower_Q4_P4') as TCastleTransform).Exists);

    { Verify csTransient proxy scenes do NOT leak into ComponentToString JSON }
    Mgr.HlodSwitchDistance := 62.5;
    Mgr.HlodHysteresisMargin := 7.5;
    JsonStr := ComponentToString(Mgr);
    AssertEquals(0, Pos('HlodCellProxy_', JsonStr));

    RestoredMgr := StringToComponent(JsonStr, RestoredOwner) as TCastleHlodClusterManager;
    AssertTrue(RestoredMgr <> nil);
    AssertSameValue(62.5, RestoredMgr.HlodSwitchDistance, 0.01);
    AssertSameValue(7.5, RestoredMgr.HlodHysteresisMargin, 0.01);
    AssertTrue(RestoredMgr.ProxyMode = hpmOctagonalPrism);
    AssertEquals(4, RestoredMgr.CellCount);
    AssertEquals(28, RestoredMgr.GetCell(0).ProxyTrianglesCount);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolHlodStudio);

end.
