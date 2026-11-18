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

{ Automated tests for Phase 353 Nanite-Style Meshlet Cluster & Normal-Cone Culler Studio. }
unit TestToolMeshletStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolMeshletStudio = class(TCastleTestCase)
  published
    procedure TestMeshlet64v124tPartitionInvariantsAndBackfaceConeClusterRejection;
    procedure TestScreenSpacePixelErrorLodTierPresetsAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleMeshletCluster, ToolMeshletStudio;

procedure TTestToolMeshletStudio.TestMeshlet64v124tPartitionInvariantsAndBackfaceConeClusterRejection;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Clusterer: TCastleMeshletClusterer;
  StatsPosZ, StatsNegZ: TMeshletViewStats;
  I, SumTris: Integer;
  Info: TMeshletClusterInfo;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TMeshletStudioHelper.SpawnMeshletClusterDemo(Vp, RootOwner, Clusterer));
    AssertTrue(Clusterer <> nil);
    AssertEquals(1536, Clusterer.SourceTriangleCount);
    AssertTrue(Clusterer.ClusterCount >= 12);

    SumTris := 0;
    for I := 0 to Clusterer.ClusterCount - 1 do
    begin
      Info := Clusterer.GetClusterInfo(I);
      AssertTrue('UniqueVertexCount must obey <= 64 hardware meshlet cap',
        (Info.UniqueVertexCount > 0) and (Info.UniqueVertexCount <= 64));
      AssertTrue('TriangleCount must obey <= 124 hardware meshlet cap',
        (Info.TriangleCount > 0) and (Info.TriangleCount <= 124));
      AssertTrue('BoundingRadius must be positive and tight (< 3.5m on R=3.5m sphere)',
        (Info.BoundingRadius > 0.1) and (Info.BoundingRadius < 3.5));
      Inc(SumTris, Info.TriangleCount);
    end;
    AssertEquals('Partition must neither drop nor duplicate any source triangle',
      1536, SumTris);

    { Camera at +Z (0, 0, +12): must backface-cone cull far-hemisphere (-Z) clusters
      while keeping 100% of front-hemisphere (+Z) clusters visible! }
    StatsPosZ := Clusterer.EvaluateViewMeshletCulling(Vector3(0.0, 0.0, 12.0), 1080, 60.0);
    AssertTrue('Normal-cone culler must reject multiple far-hemisphere backface clusters',
      StatsPosZ.BackfaceConeCulledClusters >= 2);
    AssertTrue('CulledTrianglePercent must be > 10% and < 55% on closed sphere',
      (StatsPosZ.CulledTrianglePercent > 10.0) and (StatsPosZ.CulledTrianglePercent < 55.0));

    for I := 0 to Clusterer.ClusterCount - 1 do
    begin
      Info := Clusterer.GetClusterInfo(I);
      if Info.LastCulledByBackfaceCone then
        AssertTrue('Any culled cluster from +Z=12 camera must lie beyond perspective silhouette (Z < R^2/12 = 1.021m) and face away from camera',
          (Info.BoundingCenterLocal.Z < (Sqr(3.5) / 12.0)) and
          (TVector3.DotProduct(Info.BoundingCenterLocal - Vector3(0.0, 0.0, 12.0), Info.NormalConeAxisLocal) > 0.0));
      if (Info.BoundingCenterLocal.Z > 1.8) and (Info.NormalConeAxisLocal.Z > 0.52) then
        AssertFalse('Front-facing +Z cap clusters must NEVER be false-positive culled',
          Info.LastCulledByBackfaceCone);
    end;

    { Symmetric check from -Z camera (0, 0, -12) }
    StatsNegZ := Clusterer.EvaluateViewMeshletCulling(Vector3(0.0, 0.0, -12.0), 1080, 60.0);
    AssertTrue(StatsNegZ.BackfaceConeCulledClusters >= 2);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolMeshletStudio.TestScreenSpacePixelErrorLodTierPresetsAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Clusterer, Restored: TCastleMeshletClusterer;
  NearStats, FarStats: TMeshletViewStats;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Clusterer := TCastleMeshletClusterer.Create(RootOwner);
    Clusterer.Name := 'HeroNaniteMesh';
    Clusterer.PixelErrorThreshold := 2.0;

    NearStats := Clusterer.EvaluateViewMeshletCulling(Vector3(0.0, 0.0, 9.0), 1080, 60.0);
    FarStats := Clusterer.EvaluateViewMeshletCulling(Vector3(0.0, 0.0, 220.0), 1080, 60.0);

    AssertTrue('Close camera must project higher pixel error than far camera',
      NearStats.MaxProjectedPixelError > FarStats.MaxProjectedPixelError * 8.0);
    AssertEquals('Close camera must select full-detail LOD 0', 0, NearStats.RecommendedLodTier);
    AssertEquals('Far 220m camera must select coarse LOD 2', 2, FarStats.RecommendedLodTier);

    Clusterer.Preset := mspTwistedTorusRing;
    AssertEquals(1296, Clusterer.SourceTriangleCount);
    Clusterer.MaxVerticesPerMeshlet := 48;
    Clusterer.MaxTrianglesPerMeshlet := 96;

    ReportMd := TMeshletStudioHelper.GenerateMeshletReport(Clusterer);
    AssertTrue(Pos('Twisted Torus Ring', ReportMd) > 0);

    JsonStr := ComponentToString(Clusterer);
    AssertEquals(0, Pos('TransientMeshletClusters', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleMeshletClusterer;
    AssertTrue(Restored.Preset = mspTwistedTorusRing);
    AssertEquals(48, Restored.MaxVerticesPerMeshlet);
    AssertEquals(96, Restored.MaxTrianglesPerMeshlet);
    AssertEquals(1296, Restored.SourceTriangleCount);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMeshletStudio);
end.
