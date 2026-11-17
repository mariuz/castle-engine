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

{ Automated tests for Phase 334 Niagara-Style Sword-Slash / Projectile Ribbon
  Trail, Catmull-Rom Subdivider & Midpoint-Displaced Lightning Beam VFX. }
unit TestToolRibbonStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolRibbonStudio = class(TCastleTestCase)
  published
    procedure TestCatmullRomSubdivisionSwordSlashLifetimePruningAndWidthTaper;
    procedure TestMidpointDisplacedLightningExactEndpointsSeededDeterminismForksAndJson;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleRibbonTrail, ToolRibbonStudio;

procedure TTestToolRibbonStudio.TestCatmullRomSubdivisionSwordSlashLifetimePruningAndWidthTaper;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Rib: TCastleRibbonTrail;
  Beam: TCastleLightningBeam;
  Pillar: TCastleTransform;
  K0, K1, K2, K3, At0, At1, AtMid: TVector3;
  TrisSub1, TrisSub4: Integer;
begin
  { 1. Exact Catmull-Rom endpoint Kronecker interpolation + curved arc midpoint }
  K0 := Vector3(-1, 0, 0);
  K1 := Vector3(0, 0, 1);
  K2 := Vector3(1, 0, 0);
  K3 := Vector3(0, 0, -1);
  At0 := EvaluateCatmullRomVec3(K0, K1, K2, K3, 0.0);
  At1 := EvaluateCatmullRomVec3(K0, K1, K2, K3, 1.0);
  AtMid := EvaluateCatmullRomVec3(K0, K1, K2, K3, 0.5);
  AssertVectorEquals(K1, At0, 0.0001);
  AssertVectorEquals(K2, At1, 0.0001);
  { Curved Catmull-Rom arc bows outward beyond straight chord midpoint (0.5, 0, 0.5) }
  AssertTrue(AtMid.X > 0.55);
  AssertTrue(AtMid.Z > 0.55);

  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TRibbonStudioHelper.SpawnKatanaSlashAndLightningDemo(
      Vp, DesignOwner, Rib, Beam, Pillar));
    AssertTrue(Rib <> nil);
    AssertEquals(10, Rib.ActiveSampleCount);
    AssertTrue(Rib.TotalArcLengthMeters > 1.5);

    { Compare CatmullSubdivisions = 1 vs 4 -> exact 4x triangle amplification }
    Rib.CatmullSubdivisions := 1;
    TrisSub1 := Rib.GeneratedTriangleCount;
    AssertEquals((10 - 1) * 1 * 2, TrisSub1);

    Rib.CatmullSubdivisions := 4;
    TrisSub4 := Rib.GeneratedTriangleCount;
    AssertEquals(TrisSub1 * 4, TrisSub4);

    { Switch to single-point projectile comet taper mode }
    Rib.ApplyPreset(rtpArcaneProjectileComet);
    AssertTrue(Rib.GeneratedTriangleCount = TrisSub4);

    { Stop emitting and step past LifetimeSec (0.45s) -> all aged samples prune to 0 }
    Rib.Emitting := False;
    Rib.StepTrail(0.30, False);
    AssertTrue(Rib.ActiveSampleCount < 10);
    Rib.StepTrail(0.30, False);
    AssertEquals(0, Rib.ActiveSampleCount);
    AssertEquals(0, Rib.GeneratedTriangleCount);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolRibbonStudio.TestMidpointDisplacedLightningExactEndpointsSeededDeterminismForksAndJson;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Rib, RestoredRib: TCastleRibbonTrail;
  Beam, RestoredBeam: TCastleLightningBeam;
  Pillar: TCastleTransform;
  MidSegSeedA, MidSegSeedA2, MidSegSeedB: TVector3;
  JsonRib, JsonBeam, ReportMd: String;
  Warnings: TStringList;
  Sum: TRibbonStudioSummary;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TRibbonStudioHelper.SpawnKatanaSlashAndLightningDemo(
      Vp, DesignOwner, Rib, Beam, Pillar));
    AssertTrue(Beam <> nil);
    AssertTrue(Pillar <> nil);

    { Exact start & target world endpoint pinning + jagged interior displacement }
    AssertVectorEquals(Beam.WorldTranslation, Beam.BoltStartWorld, 0.001);
    AssertVectorEquals(Pillar.WorldTranslation, Beam.BoltEndWorld, 0.001);
    AssertVectorEquals(Beam.WorldTranslation, Beam.GetSegment(0).A, 0.001);
    AssertVectorEquals(Pillar.WorldTranslation, Beam.GetSegment(Beam.MainSegmentCount - 1).B, 0.001);
    AssertTrue(Beam.MaxLateralDisplacement > 0.05);

    { Depth=4 -> 16 main segments + 3*2=6 fork segments = 22 segments * 4 tris = 88 tris }
    AssertEquals(16, Beam.MainSegmentCount);
    AssertEquals(22, Beam.TotalSegmentCount);
    AssertEquals(88, Beam.TotalBoltTriangles);

    { Seeded determinism vs new seed variation }
    Beam.StrikeNow(4242);
    MidSegSeedA := Beam.GetSegment(8).A;
    Beam.StrikeNow(4242);
    MidSegSeedA2 := Beam.GetSegment(8).A;
    AssertVectorEquals(MidSegSeedA, MidSegSeedA2, 0.0001);

    Beam.StrikeNow(9999);
    MidSegSeedB := Beam.GetSegment(8).A;
    AssertTrue(PointsDistance(MidSegSeedA, MidSegSeedB) > 0.01);

    Sum := TRibbonStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.RibbonCount);
    AssertEquals(1, Sum.LightningCount);
    AssertEquals(0, Sum.WarningsCount);
    ReportMd := TRibbonStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Niagara Ribbon Trail & Arc Lightning VFX Report', ReportMd) > 0);

    { Verify csTransient meshes never leak into serialized JSON }
    JsonRib := ComponentToString(Rib);
    JsonBeam := ComponentToString(Beam);
    AssertEquals(0, Pos('TransientRibbonMesh', JsonRib));
    AssertEquals(0, Pos('TransientLightningMesh', JsonBeam));

    RestoredRib := StringToComponent(JsonRib, RestoredOwner) as TCastleRibbonTrail;
    RestoredBeam := StringToComponent(JsonBeam, RestoredOwner) as TCastleLightningBeam;
    AssertTrue(RestoredRib <> nil);
    AssertTrue(RestoredBeam <> nil);
    AssertSameValue(1.30, RestoredRib.BladeLength, 0.01);
    AssertEquals(4, RestoredBeam.SubdivisionDepth);
    AssertEquals(3, RestoredBeam.BranchCount);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolRibbonStudio);

end.
