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

{ Automated tests for Phase 350 Runtime Virtual Texture (RVT) LRU Tile Page
  Cache, Deformable Snow/Mud Sinkage + Raised Rim Berms & Snowfill Recovery. }
unit TestToolRvtStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolRvtStudio = class(TCastleTestCase)
  published
    procedure TestLruPageTableHitMissEvictionAndFootprintSinkageWithRaisedBerm;
    procedure TestGrayscaleHeightmapExportMaterialSwitchAndTransientCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleImages, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleRuntimeVt, ToolRvtStudio;

procedure TTestToolRvtStudio.TestLruPageTableHitMissEvictionAndFootprintSinkageWithRaisedBerm;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Rvt: TCastleRuntimeVirtualTexture;
  DeepestBefore: Single;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Rvt := TCastleRuntimeVirtualTexture.Create(DesignOwner);
    Rvt.Name := 'TestRvt';
    Rvt.PhysicalCacheSlots := 4;
    Vp.Items.Add(Rvt);

    { 1. Fill all 4 physical slots -> 4 misses, 0 hits, 0 evictions }
    Rvt.RequestVirtualTile(0, 0, 0);
    Rvt.RequestVirtualTile(1, 0, 0);
    Rvt.RequestVirtualTile(2, 0, 0);
    Rvt.RequestVirtualTile(3, 0, 0);
    AssertEquals(4, Rvt.OccupiedPageCount);
    AssertEquals(4, Rvt.CacheMissCount);
    AssertEquals(0, Rvt.CacheHitCount);
    AssertEquals(0, Rvt.EvictionCount);

    { 2. Touch Tile (0,0) -> Cache Hit! Now Tile (1,0) is the oldest LRU entry! }
    Rvt.RequestVirtualTile(0, 0, 0);
    AssertEquals(1, Rvt.CacheHitCount);

    { 3. Request 5th Tile (4,0) -> evicts oldest LRU Tile (1,0) while keeping Tile (0,0)! }
    Rvt.RequestVirtualTile(4, 0, 0);
    AssertEquals(1, Rvt.EvictionCount);
    AssertTrue(Rvt.IsVirtualTileResident(0, 0, 0));
    AssertFalse(Rvt.IsVirtualTileResident(1, 0, 0));
    AssertTrue(Rvt.IsVirtualTileResident(4, 0, 0));

    { 4. Stamp footprint at center (0, 0): carves central rut < -0.20m & raises outer berm > +0.03m }
    Rvt.StampFootprintOrTire(0.0, 0.0, 1.20, 0.26);
    DeepestBefore := Rvt.MinDepressionMeters;
    AssertTrue(DeepestBefore < -0.20);
    AssertTrue(Rvt.MaxBermRimMeters > 0.03);

    { 5. Thermal snowfill recovery relaxes ruts smoothly toward 0.0 }
    Rvt.StepThermalSnowfillRecovery(4.0);
    AssertTrue(Rvt.MinDepressionMeters > DeepestBefore * 0.60);
    AssertTrue(Rvt.MinDepressionMeters < -0.02);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolRvtStudio.TestGrayscaleHeightmapExportMaterialSwitchAndTransientCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Rvt, RestoredRvt: TCastleRuntimeVirtualTexture;
  Img: TRGBImage;
  CenterLum, CornerLum: Byte;
  Warnings: TStringList;
  Sum: TRvtStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TRvtStudioHelper.SpawnAlpineSnowfieldRvtDemo(Vp, DesignOwner, Rvt));
    Rvt.ClearDisplacementField;
    Rvt.StampFootprintOrTire(0.0, 0.0, 1.50, 0.30);

    { 1. Grayscale heightmap export: center rut < 100, untouched far corner = 128 }
    Img := Rvt.ExportDisplacementGrayscaleImage;
    try
      CenterLum := Img.PixelPtr(Rvt.GridResolution div 2, Rvt.GridResolution div 2)^.X;
      CornerLum := Img.PixelPtr(0, 0)^.X;
      AssertTrue(CenterLum < 95);
      AssertEquals(128, CornerLum);
    finally
      FreeAndNil(Img);
    end;

    Rvt.SurfaceMaterial := rsmPeatBogMud;
    Sum := TRvtStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.RvtCount);
    ReportMd := TRvtStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Runtime Virtual Texture & Snow/Mud Trail Report', ReportMd) > 0);

    { 2. Transient snow surface scene is never duplicated across JSON roundtrip }
    JsonStr := ComponentToString(Rvt);
    AssertEquals(0, Pos('TransientRvtSnowMesh', JsonStr));

    RestoredRvt := StringToComponent(JsonStr, RestoredOwner) as TCastleRuntimeVirtualTexture;
    AssertTrue(RestoredRvt <> nil);
    AssertTrue(RestoredRvt.SurfaceMaterial = rsmPeatBogMud);
    AssertEquals(1, RestoredRvt.Count);
    AssertTrue(csTransient in RestoredRvt[0].ComponentStyle);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolRvtStudio);

end.
