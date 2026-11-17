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

{ Automated tests for Phase 335 PCG Spline-Biome Settlement, Road-Intersection
  Graph, Zero-Overlap Building Lot Slicer & Terrain Foundation Snapping. }
unit TestToolSettlementStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSettlementStudio = class(TCastleTestCase)
  published
    procedure TestCrossroadsAndMarketTownZeroOverlapRoadClearanceAndSeededDeterminism;
    procedure TestWorldRayTerrainFoundationSnappingAndCsTransientCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleScene, X3DNodes,
  CastleComponentSerialize,
  CastlePcgSettlement, ToolSettlementStudio;

function CreateFlatPlateauScene(const AOwner: TComponent;
  const AHeightY, AHalfExtentXZ: Single): TCastleScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  Pts: TVector3List;
begin
  Result := TCastleScene.Create(AOwner);
  Result.Name := 'ElevatedPlateauMesh';
  Result.PreciseCollisions := True;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  Coord := TCoordinateNode.Create;
  Pts := TVector3List.Create;
  try
    Pts.Add(Vector3(-AHalfExtentXZ, AHeightY, -AHalfExtentXZ));
    Pts.Add(Vector3(+AHalfExtentXZ, AHeightY, -AHalfExtentXZ));
    Pts.Add(Vector3(+AHalfExtentXZ, AHeightY, +AHalfExtentXZ));

    Pts.Add(Vector3(-AHalfExtentXZ, AHeightY, -AHalfExtentXZ));
    Pts.Add(Vector3(+AHalfExtentXZ, AHeightY, +AHalfExtentXZ));
    Pts.Add(Vector3(-AHalfExtentXZ, AHeightY, +AHalfExtentXZ));
    Coord.SetPoint(Pts);
  finally
    FreeAndNil(Pts);
  end;
  TriSet.Coord := Coord;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  Result.Load(Root, True);
end;

procedure TTestToolSettlementStudio.TestCrossroadsAndMarketTownZeroOverlapRoadClearanceAndSeededDeterminism;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Settl: TCastlePcgSettlement;
  Lot0SeedA, Lot0SeedA2: TPcgBuildingLot;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TSettlementStudioHelper.SpawnCrossroadsVillageDemo(Vp, DesignOwner, Settl));
    AssertTrue(Settl <> nil);

    { Crossroads Hamlet: 2 orthogonal roads, multiple lots, 0 overlaps, 0 road intrusions }
    AssertEquals(2, Settl.RoadSegmentCount);
    AssertTrue(Settl.BuildingLotCount >= 8);
    AssertEquals(0, Settl.CountOverlappingLotPairs);
    AssertEquals(0, Settl.CountRoadIntrudingLots);
    AssertTrue(Settl.StreetlampCount >= 4);
    AssertTrue(Settl.FencePostCount >= 12);
    AssertTrue(Settl.GeneratedTriangleCount > 150);

    { Walled Market Town: 4 road segments, dense lots, still 0 overlaps & 0 road intrusions }
    Settl.Preset := pspWalledMarketTown;
    AssertEquals(4, Settl.RoadSegmentCount);
    AssertTrue(Settl.BuildingLotCount >= 10);
    AssertEquals(0, Settl.CountOverlappingLotPairs);
    AssertEquals(0, Settl.CountRoadIntrudingLots);

    { Linear Highway Outpost: 1 highway segment, 0 overlaps & 0 road intrusions }
    Settl.Preset := pspLinearHighwayOutpost;
    AssertEquals(1, Settl.RoadSegmentCount);
    AssertTrue(Settl.BuildingLotCount >= 6);
    AssertEquals(0, Settl.CountOverlappingLotPairs);
    AssertEquals(0, Settl.CountRoadIntrudingLots);

    { Seeded determinism }
    Settl.RandomSeed := 777;
    Lot0SeedA := Settl.GetBuildingLot(0);
    Settl.RandomSeed := 888;
    Settl.RandomSeed := 777;
    Lot0SeedA2 := Settl.GetBuildingLot(0);
    AssertVectorEquals(Lot0SeedA.CenterWorld, Lot0SeedA2.CenterWorld, 0.0001);
    AssertSameValue(Lot0SeedA.WallHeight, Lot0SeedA2.WallHeight, 0.0001);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolSettlementStudio.TestWorldRayTerrainFoundationSnappingAndCsTransientCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Plateau: TCastleScene;
  Settl, RestoredSettl: TCastlePcgSettlement;
  I: Integer;
  JsonStr, ReportMd: String;
  Warnings: TStringList;
  Sum: TSettlementStudioSummary;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Plateau := CreateFlatPlateauScene(DesignOwner, 4.25, 100.0);
    Vp.Items.Add(Plateau);

    AssertTrue(TSettlementStudioHelper.SpawnCrossroadsVillageDemo(Vp, DesignOwner, Settl));
    { Every building foundation must snap onto the Y = 4.25m plateau via WorldRay }
    AssertTrue(Settl.BuildingLotCount >= 8);
    for I := 0 to Settl.BuildingLotCount - 1 do
      AssertSameValue(4.25, Settl.GetBuildingLot(I).CenterWorld.Y, 0.05);

    Sum := TSettlementStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.SettlementCount);
    AssertEquals(0, Sum.OverlappingPairs);
    AssertEquals(0, Sum.RoadIntrusions);
    AssertEquals(0, Sum.WarningsCount);
    ReportMd := TSettlementStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('PCG Biome Settlement & Road Graph Report', ReportMd) > 0);

    { Verify csTransient settlement mesh never leaks into serialized JSON }
    Settl.MaxBuildingFloors := 4;
    Settl.SettlementRadius := 38.0;
    JsonStr := ComponentToString(Settl);
    AssertEquals(0, Pos('TransientSettlementMesh', JsonStr));

    RestoredSettl := StringToComponent(JsonStr, RestoredOwner) as TCastlePcgSettlement;
    AssertTrue(RestoredSettl <> nil);
    AssertEquals(4, RestoredSettl.MaxBuildingFloors);
    AssertSameValue(38.0, RestoredSettl.SettlementRadius, 0.01);
    AssertEquals(0, RestoredSettl.CountOverlappingLotPairs);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSettlementStudio);

end.
