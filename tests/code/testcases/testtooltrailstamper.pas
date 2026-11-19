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

{ Automated tests for Phase 383 Interactive Snow, Mud & Sand Persistent
  Deformation Trail Stamper Studio. }
unit TestToolTrailStamper;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolTrailStamper = class(TCastleTestCase)
  published
    procedure TestFurrowBowlDepressionRaisedSideBermsAndOutOfBoundsSafety;
    procedure TestGradualSnowfallRefillRecoveryPresetsAndTransientCleanJson;
  end;

implementation

uses
  Math, CastleVectors, CastleViewport, CastleComponentSerialize,
  CastleTrailStamper, ToolTrailStamper;

procedure TTestToolTrailStamper.TestFurrowBowlDepressionRaisedSideBermsAndOutOfBoundsSafety;
var
  Owner: TComponent;
  Vp: TCastleViewport;
  Stamper: TCastleTrailStamper;
  CenterTroughS, SideBermS, OutsideS: TTrailStampSample;
begin
  Owner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    Stamper := TCastleTrailStamper.Create(Owner);
    Stamper.Name := 'SnowTestPatch';
    Stamper.ApplyPreset(tmpDeepAlpineSnow);
    Vp.Items.Add(Stamper);

    { Carve straight +X sled furrow along Z = 0 with Radius = 2.0m, Depth = 0.35m }
    AssertTrue(Stamper.StampFurrowSegmentWorld(
      Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), 2.0, 0.35) > 20);

    { 1. Centerline (0, 0, 0) is deeply depressed (< -0.30m) and compacted (> 0.85) }
    CenterTroughS := Stamper.SampleDeformationAtWorld(Vector3(0.0, 0.0, 0.0));
    AssertTrue(CenterTroughS.InsideGrid);
    AssertTrue(CenterTroughS.DisplacementMeters < -0.30);
    AssertTrue(CenterTroughS.Compaction01 > 0.85);

    { 2. Displaced collar berm at Z = +2.55m (~1.275 * R) rises ABOVE undisturbed 0.0m }
    SideBermS := Stamper.SampleDeformationAtWorld(Vector3(0.0, 0.0, 2.55));
    AssertTrue(SideBermS.InsideGrid);
    AssertTrue(SideBermS.DisplacementMeters > 0.04);
    AssertTrue(Stamper.MaxBermHeightMeters > 0.04);

    { 3. Slope wall at Z = +1.0m tilts SurfaceNormal inward toward -Z }
    AssertTrue(Stamper.SampleDeformationAtWorld(Vector3(0.0, 0.0, 1.0)).SurfaceNormal.Z < -0.05);

    { 4. Out-of-patch query returns InsideGrid = False cleanly }
    OutsideS := Stamper.SampleDeformationAtWorld(Vector3(50.0, 0.0, 50.0));
    AssertFalse(OutsideS.InsideGrid);
    AssertSameValue(0.0, OutsideS.DisplacementMeters, 0.0001);
  finally
    FreeAndNil(Owner);
  end;
end;

procedure TTestToolTrailStamper.TestGradualSnowfallRefillRecoveryPresetsAndTransientCleanJson;
var
  Owner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Stamper, Restored: TCastleTrailStamper;
  MidDepth: Single;
  SavedJson, Cfg, Md: String;
begin
  Owner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TTrailStamperHelper.SpawnAlpineSnowTrailDemo(Vp, Owner, Stamper));
    AssertTrue(Stamper <> nil);
    AssertTrue(Stamper.ActiveDeformedCellCount > 25);
    AssertTrue(Stamper.MinDisplacementMeters < -0.25);

    { 1. Partial snowfall refill shallows trough monotonically, then full refill restores 0 cells }
    Stamper.StepWeatherRefill(3.0);
    MidDepth := Stamper.MinDisplacementMeters;
    AssertTrue((MidDepth > -0.25) and (MidDepth < -0.05));

    Stamper.StepWeatherRefill(12.0);
    AssertEquals(0, Stamper.ActiveDeformedCellCount);
    AssertSameValue(0.0, Stamper.MinDisplacementMeters, 0.0001);
    AssertSameValue(0.0, Stamper.MaxBermHeightMeters, 0.0001);

    { 2. Switch to Desert Dune Sand preset }
    Stamper.ApplyPreset(tmpDesertDuneSand);
    Stamper.StampBootOrWheelAtWorld(TVector3.Zero, 1.5, 0.18);
    AssertTrue(Stamper.MaxBermHeightMeters > 0.03);

    Md := TTrailStamperHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Interactive Snow, Mud & Sand Persistent Deformation Trail Report', Md) > 0);

    { 3. Verify csTransient mesh never leaks into serialized JSON + ConfigJson roundtrip }
    SavedJson := ComponentToString(Stamper);
    AssertEquals(0, Pos('TransientTrailSurfaceMesh', SavedJson));
    Cfg := Stamper.ConfigJson;
    Restored := StringToComponent(SavedJson, RestoredOwner) as TCastleTrailStamper;
    AssertTrue(Restored <> nil);
    Restored.ConfigJson := Cfg;
    AssertEquals(Ord(tmpDesertDuneSand), Ord(Restored.Preset));
    AssertSameValue(0.48, Restored.RimBermRatio01, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Owner);
  end;
end;

initialization
  RegisterTest(TTestToolTrailStamper);

end.
