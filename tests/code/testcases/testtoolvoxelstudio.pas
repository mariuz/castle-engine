{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated unit tests for Phase 329 3D Voxel SDF Cave, Overhang & Crack-Free
  Marching-Tetrahedra Isosurface Studio (@link(CastleVoxelTerrain),
  @link(ToolVoxelStudio)). }
unit TestToolVoxelStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolVoxelStudio = class(TCastleTestCase)
  published
    procedure TestSdfPrimitivesSmoothBooleansAndWalkthroughCaveCeilingOverhangWorldRay;
    procedure TestNaturalStoneArchFloatingIslandNonDestructiveBrushToggleAndCleanJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTriangles, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleVoxelTerrain, ToolVoxelStudio;

procedure TTestToolVoxelStudio.TestSdfPrimitivesSmoothBooleansAndWalkthroughCaveCeilingOverhangWorldRay;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Cave: TCastleVoxelVolume;
  RayHit: TRayCollision;
  HardUnion, SmoothU, SubD: Single;
begin
  { 1. Exact analytical 3D SDF primitive & smooth Quilez Boolean checks }
  AssertSameValue(-2.0, SdfSphere3D(TVector3.Zero, TVector3.Zero, 2.0), 1e-5);
  AssertSameValue(3.0, SdfSphere3D(Vector3(5.0, 0.0, 0.0), TVector3.Zero, 2.0), 1e-5);
  AssertSameValue(1.0, SdfCapsule3D(Vector3(0.0, 3.0, 0.0), Vector3(-4.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0), 2.0), 1e-5);

  HardUnion := Min(0.10, 0.10);
  SmoothU := SmoothSdfUnion(0.10, 0.10, 0.80);
  AssertTrue(SmoothU < HardUnion - 0.05); // Smooth fillet pulls seam inward (< min)

  SubD := SmoothSdfSubtract(-1.0, -0.5, 0.0);
  AssertSameValue(0.5, SubD, 1e-5); // Inside cutter (-0.5) turns solid (-1.0) into air (+0.5)

  { 2. Spawn 3D Walkthrough Cave Tunnel & verify true 3D ceiling overhang + floor + open Z portal! }
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Cave := TVoxelStudioHelper.SpawnVoxelCaveDemo(
      Vp, DesignOwner, vvpWalkthroughCaveTunnel);
    AssertTrue(Cave <> nil);
    AssertTrue(Cave.GeneratedTriangleCount > 500);

    { Inside cavern at (0, 2.35, 0) is open air (SDF > 0) }
    AssertTrue(Cave.SampleSdfAtLocalPos(Vector3(0.0, 2.35, 0.0)) > 0.5);

    { Ray UP from inside cavern hits the solid 3D rock ceiling overhang above Y=2.35! }
    RayHit := Vp.Items.WorldRay(Vector3(0.0, 2.35, 0.0), Vector3(0.0, 1.0, 0.0));
    try
      AssertTrue(RayHit <> nil);
      AssertTrue((RayHit.Distance > 1.0) and (RayHit.Distance < 6.0));
    finally
      FreeAndNil(RayHit);
    end;

    { Ray DOWN from inside cavern hits the solid cave floor below Y=2.35! }
    RayHit := Vp.Items.WorldRay(Vector3(0.0, 2.35, 0.0), Vector3(0.0, -1.0, 0.0));
    try
      AssertTrue(RayHit <> nil);
      AssertTrue((RayHit.Distance > 1.2) and (RayHit.Distance < 3.0));
    finally
      FreeAndNil(RayHit);
    end;

    { Ray SIDEWAYS (+X) from inside cavern hits the solid rock cave wall! }
    RayHit := Vp.Items.WorldRay(Vector3(0.0, 2.35, 0.0), Vector3(1.0, 0.0, 0.0));
    try
      AssertTrue(RayHit <> nil);
      AssertTrue((RayHit.Distance > 1.5) and (RayHit.Distance < 5.0));
    finally
      FreeAndNil(RayHit);
    end;

    { Ray STRAIGHT THROUGH the Z-axis walkthrough tunnel from Z=+12 toward -Z passes
      all the way through the open tunnel without hitting any wall! }
    RayHit := Vp.Items.WorldRay(Vector3(0.0, 2.35, 12.0), Vector3(0.0, 0.0, -1.0));
    try
      AssertTrue(RayHit = nil);
    finally
      FreeAndNil(RayHit);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolVoxelStudio.TestNaturalStoneArchFloatingIslandNonDestructiveBrushToggleAndCleanJson;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Vol, RestoredVol: TCastleVoxelVolume;
  TrisWithArchCut, TrisWithoutArchCut, CarveIdx: Integer;
  SavedJson, Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vol := TVoxelStudioHelper.SpawnVoxelCaveDemo(
      Vp, DesignOwner, vvpNaturalStoneArchOverhang);
    AssertTrue(Vol <> nil);

    TrisWithArchCut := Vol.GeneratedTriangleCount;
    AssertTrue(TrisWithArchCut > 300);

    { Disable the arch-carving capsule brush -> solid wall has different triangle count;
      re-enabling restores the exact original arch triangle count non-destructively! }
    CarveIdx := Vol.BrushCount - 1;
    Vol.SetBrushEnabled(CarveIdx, False);
    TrisWithoutArchCut := Vol.GeneratedTriangleCount;
    AssertTrue(TrisWithoutArchCut <> TrisWithArchCut);

    Vol.SetBrushEnabled(CarveIdx, True);
    AssertEquals(TrisWithArchCut, Vol.GeneratedTriangleCount);

    { Switch to Floating Sky Island preset & verify csTransient-clean JSON roundtrip }
    Vol.ApplyPreset(vvpFloatingSkyIslandPillars);
    AssertTrue(Vol.GeneratedTriangleCount > 300);

    SavedJson := ComponentToString(Vol);
    AssertEquals(0, Pos('TriangleSet', SavedJson));
    RestoredOwner := TComponent.Create(nil);
    try
      RestoredVol := StringToComponent(SavedJson, RestoredOwner) as TCastleVoxelVolume;
      AssertTrue(RestoredVol.Preset = vvpFloatingSkyIslandPillars);
      AssertEquals(Vol.BrushCount, RestoredVol.BrushCount);
      AssertEquals(Vol.GeneratedTriangleCount, RestoredVol.GeneratedTriangleCount);
    finally
      FreeAndNil(RestoredOwner);
    end;

    Md := TVoxelStudioHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('3D Voxel SDF Cave & Overhang Volume Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolVoxelStudio);
end.
