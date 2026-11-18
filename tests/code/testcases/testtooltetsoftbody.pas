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

{ Automated tests for Phase 354 Chaos Flesh Tetrahedral Volume-XPBD Soft-Body Studio. }
unit TestToolTetSoftBody;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolTetSoftBody = class(TCastleTestCase)
  published
    procedure TestFiveTetLatticeExactRestVolumeZeroInversionCrushAndVolumePreservation;
    procedure TestPinnedHangingTendonStretchPresetsAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleTetSoftBody, ToolTetSoftBody;

procedure TTestToolTetSoftBody.TestFiveTetLatticeExactRestVolumeZeroInversionCrushAndVolumePreservation;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Body: TCastleTetSoftBody;
  I: Integer;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TTetSoftBodyHelper.SpawnTetSoftBodyArena(Vp, RootOwner, Body));
    AssertTrue(Body <> nil);

    { 3x3x3 cubic lattice of 2x2x2m cube -> 64 vertices, 27 * 5 = 135 tets, exact 8.000 m^3 }
    AssertEquals(64, Body.Stats.VertexCount);
    AssertEquals(135, Body.Stats.TetrahedronCount);
    AssertSameValue(8.0, Body.Stats.RestTotalVolume, 0.01);
    AssertEquals(0, Body.Stats.InvertedTetCount);

    { Drop onto FloorLocalY = 0.0 AND slam top face with heavy -14 m/s radial hammer blow }
    for I := 1 to 35 do
      Body.StepSimulation(1.0 / 60.0);

    Body.ApplyRadialImpactImpulse(Vector3(0.0, Body.Stats.MaxVertexLocalY, 0.0),
      1.8, Vector3(0.0, -14.0, 0.0));
    for I := 1 to 25 do
      Body.StepSimulation(1.0 / 60.0);

    AssertEquals('Signed-volume 6V XPBD must maintain ZERO inverted tetrahedra under crush',
      0, Body.Stats.InvertedTetCount);
    AssertTrue('Floor clamp must prevent vertices from penetrating below FloorLocalY',
      Body.Stats.MinVertexLocalY >= Body.FloorLocalY - 0.001);
    AssertTrue('Volume-preserving XPBD must keep total volume within [88%..112%] of rest volume',
      (Body.Stats.VolumeRatioPercent > 88.0) and (Body.Stats.VolumeRatioPercent < 112.0));
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolTetSoftBody.TestPinnedHangingTendonStretchPresetsAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Body, Restored: TCastleTetSoftBody;
  InitialMinY: Single;
  I: Integer;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Body := TCastleTetSoftBody.Create(RootOwner);
    Body.Name := 'TendonFlesh';
    Body.Preset := tsbpHangingFleshPillar;
    AssertTrue(Body.PinTopFace);

    InitialMinY := Body.Stats.MinVertexLocalY;
    for I := 1 to 30 do
      Body.StepSimulation(1.0 / 60.0);

    { Top face (Y = 3.6 + 3.0 = 6.6m) stays pinned while bottom stretches downward elastically }
    AssertSameValue(6.60, Body.Stats.MaxVertexLocalY, 0.02);
    AssertTrue('Bottom of hanging flesh tendon must stretch downward under gravity',
      Body.Stats.MinVertexLocalY < InitialMinY - 0.05);
    AssertEquals(0, Body.Stats.InvertedTetCount);

    ReportMd := TTetSoftBodyHelper.GenerateTetSoftBodyReport(Body);
    AssertTrue(Pos('Pinned Hanging Flesh Tendon', ReportMd) > 0);

    JsonStr := ComponentToString(Body);
    AssertEquals(0, Pos('TransientTetFleshMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleTetSoftBody;
    AssertTrue(Restored.Preset = tsbpHangingFleshPillar);
    AssertTrue(Restored.PinTopFace);
    AssertEquals(135, Restored.Stats.TetrahedronCount);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolTetSoftBody);
end.
