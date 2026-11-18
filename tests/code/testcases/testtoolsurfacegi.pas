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

{ Automated tests for Phase 357 Lumen-Style Surface Cache SH2 GI Probe Studio. }
unit TestToolSurfaceGi;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolSurfaceGi = class(TCastleTestCase)
  published
    procedure TestSkyOcclusionRoofShadowingAndCornellRedBlueColorBleeding;
    procedure TestProbeGridCountsBounceGainScalingAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleSurfaceGi, ToolSurfaceGi;

procedure TTestToolSurfaceGi.TestSkyOcclusionRoofShadowingAndCornellRedBlueColorBleeding;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  GiGrid: TCastleSurfaceGiGrid;
  OutdoorProbe, RoofedProbe: TSurfaceGiProbe;
  WestRedSideIrrad, EastBlueSideIrrad: TVector3;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TSurfaceGiHelper.SpawnCornellBounceAndRoofDemo(Vp, RootOwner, GiGrid));
    AssertTrue(GiGrid <> nil);
    AssertEquals(32, GiGrid.ProbeCount);
    AssertTrue(GiGrid.BakeStats.RaysCastCount = 32 * 32);

    { South (+Z, IZ = 3) is open to sky; North (-Z, IZ = 0) sits under CornellNorthBunkerRoof }
    OutdoorProbe := GiGrid.GetProbe3D(1, 0, 3);
    RoofedProbe := GiGrid.GetProbe3D(1, 0, 0);
    AssertTrue('Open-sky courtyard probe must have higher SkyVisibility than roofed bunker probe',
      OutdoorProbe.SkyVisibility > RoofedProbe.SkyVisibility + 0.25);

    { Cornell Color-Bleeding:
      Near Red West Wall (-X = -3.2m) with normal facing -X -> Red channel dominates Blue!
      Near Blue East Wall (+X = +3.2m) with normal facing +X -> Blue channel dominates Red! }
    WestRedSideIrrad := GiGrid.SampleIrradianceAtWorld(Vector3(-3.2, 1.2, 1.5), Vector3(-1.0, 0.0, 0.0));
    EastBlueSideIrrad := GiGrid.SampleIrradianceAtWorld(Vector3(3.2, 1.2, 1.5), Vector3(1.0, 0.0, 0.0));

    AssertTrue('Cornell Red West Wall must bleed warm Red SH2 bounce onto -X surfaces',
      WestRedSideIrrad.X > WestRedSideIrrad.Z * 1.15);
    AssertTrue('Cornell Blue East Wall must bleed cool Blue SH2 bounce onto +X surfaces',
      EastBlueSideIrrad.Z > EastBlueSideIrrad.X * 1.15);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolSurfaceGi.TestProbeGridCountsBounceGainScalingAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  GiGrid, Restored: TCastleSurfaceGiGrid;
  LowBounceIrrad, HighBounceIrrad: TVector3;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TSurfaceGiHelper.SpawnCornellBounceAndRoofDemo(Vp, RootOwner, GiGrid));

    GiGrid.BounceIntensity := 0.5;
    GiGrid.BakeIrradianceProbes(Vp.Items);
    LowBounceIrrad := GiGrid.SampleIrradianceAtWorld(Vector3(-3.2, 1.2, -2.5), Vector3(-1, 0, 0));

    GiGrid.BounceIntensity := 2.8;
    GiGrid.BakeIrradianceProbes(Vp.Items);
    HighBounceIrrad := GiGrid.SampleIrradianceAtWorld(Vector3(-3.2, 1.2, -2.5), Vector3(-1, 0, 0));

    AssertTrue('Increasing BounceIntensity must increase indirect wall bounce irradiance',
      HighBounceIrrad.X > LowBounceIrrad.X * 1.5);

    GiGrid.Preset := sgpIndoorOutdoorCourtyard;
    AssertEquals(50, GiGrid.ProbeCount);

    ReportMd := TSurfaceGiHelper.GenerateSurfaceGiReport(GiGrid);
    AssertTrue(Pos('Indoor/Outdoor Sky-Occlusion Grid', ReportMd) > 0);

    JsonStr := ComponentToString(GiGrid);
    AssertEquals(0, Pos('TransientSurfaceGiProbes', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleSurfaceGiGrid;
    AssertTrue(Restored.Preset = sgpIndoorOutdoorCourtyard);
    AssertEquals(5, Restored.GridX);
    AssertEquals(5, Restored.GridZ);
    AssertEquals(50, Restored.ProbeCount);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSurfaceGi);
end.
