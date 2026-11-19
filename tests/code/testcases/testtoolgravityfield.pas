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

{ Automated tests for Phase 381 Dynamic Gravity Well, Planetary Spherical Walk
  & Tube Up-Vector Blending Studio. }
unit TestToolGravityField;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolGravityField = class(TCastleTestCase)
  published
    procedure TestSphericalPlanet360WalkInverseSquareFalloffAndOuterCutoff;
    procedure TestHollowCylinderInteriorCeilingWalkPriorityOverrideSlerpAndJson;
  end;

implementation

uses
  Math, CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleGravityField, ToolGravityField;

procedure TTestToolGravityField.TestSphericalPlanet360WalkInverseSquareFalloffAndOuterCutoff;
var
  Owner: TComponent;
  Vp: TCastleViewport;
  Planet, InvZone: TCastleGravityField;
  NorthS, EastS, SouthS, DoubleR, FarOut: TGravitySample;
begin
  Owner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TGravityFieldHelper.SpawnPlanetoidAndInversionDemo(Vp, Owner, Planet, InvZone));
    AssertTrue(Planet <> nil);
    AssertSameValue(8.0, Planet.PlanetRadius, 0.001);
    AssertSameValue(20.0, Planet.OuterInfluenceRadius, 0.001);

    { 1. 360-degree surface walk: North Pole, East Equator, and upside-down South Pole }
    NorthS := Planet.SampleFieldAtWorld(Vector3(0, 8.0, 0));
    EastS := Planet.SampleFieldAtWorld(Vector3(8.0, 0, 0));
    SouthS := Planet.SampleFieldAtWorld(Vector3(0, -8.0, 0));

    AssertTrue(NorthS.InsideInfluence);
    AssertVectorEquals(Vector3(0, 1, 0), NorthS.UpVector, 0.001);
    AssertVectorEquals(Vector3(0, -9.80, 0), NorthS.GravityAccelVec, 0.01);

    AssertTrue(EastS.InsideInfluence);
    AssertVectorEquals(Vector3(1, 0, 0), EastS.UpVector, 0.001);
    AssertVectorEquals(Vector3(-9.80, 0, 0), EastS.GravityAccelVec, 0.01);

    AssertTrue(SouthS.InsideInfluence);
    AssertVectorEquals(Vector3(0, -1, 0), SouthS.UpVector, 0.001);
    AssertVectorEquals(Vector3(0, 9.80, 0), SouthS.GravityAccelVec, 0.01);

    { 2. Inverse-square Newton falloff at r = 2 * R (16.0m): g = 9.80 / 4 = 2.45 m/s^2 }
    DoubleR := Planet.SampleFieldAtWorld(Vector3(0, 16.0, 0));
    AssertTrue(DoubleR.InsideInfluence);
    AssertSameValue(2.45, DoubleR.AccelMagnitudeMps2, 0.02);

    { 3. Beyond OuterInfluenceRadius (20m) -> InsideInfluence = False }
    FarOut := Planet.SampleFieldAtWorld(Vector3(0, 25.0, 0));
    AssertFalse(FarOut.InsideInfluence);
    AssertSameValue(0.0, FarOut.BlendWeight, 0.0001);
  finally
    FreeAndNil(Owner);
  end;
end;

procedure TTestToolGravityField.TestHollowCylinderInteriorCeilingWalkPriorityOverrideSlerpAndJson;
var
  Owner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Tube, LowPrioPlanet, HighPrioCeiling, Restored: TCastleGravityField;
  BottomHull, TopCeilingHull, RightWallHull, CompositeS: TGravitySample;
  CurUp: TVector3;
  StepIdx: Integer;
  SavedJson, Cfg, Md: String;
begin
  Owner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);

    { 1. O'Neill hollow spinning cylinder interior: centrifugal hull gravity pushes outward,
         so Up always points INWARD toward the central Z axis }
    Tube := TCastleGravityField.Create(Owner);
    Tube.Name := 'ONeillHabitatTube';
    Tube.ApplyPreset(gfpONeillRingworldTube);
    Vp.Items.Add(Tube);

    BottomHull := Tube.SampleFieldAtWorld(Vector3(0, -10.0, 0));
    TopCeilingHull := Tube.SampleFieldAtWorld(Vector3(0, 10.0, 0));
    RightWallHull := Tube.SampleFieldAtWorld(Vector3(10.0, 0, 0));

    AssertTrue(BottomHull.InsideInfluence);
    AssertVectorEquals(Vector3(0, 1, 0), BottomHull.UpVector, 0.001);
    AssertTrue(TopCeilingHull.InsideInfluence);
    AssertVectorEquals(Vector3(0, -1, 0), TopCeilingHull.UpVector, 0.001);
    AssertTrue(RightWallHull.InsideInfluence);
    AssertVectorEquals(Vector3(-1, 0, 0), RightWallHull.UpVector, 0.001);

    { 2. Overlapping priority override: Priority=50 ceiling box overrides Priority=10 planet }
    LowPrioPlanet := TCastleGravityField.Create(Owner);
    LowPrioPlanet.Name := 'BackgroundPlanet';
    LowPrioPlanet.ApplyPreset(gfpMarioPlanetoidWalk);
    LowPrioPlanet.Priority := 10;
    LowPrioPlanet.Translation := Vector3(50, 0, 0);
    Vp.Items.Add(LowPrioPlanet);

    HighPrioCeiling := TCastleGravityField.Create(Owner);
    HighPrioCeiling.Name := 'InvertedCeilingRoom';
    HighPrioCeiling.ApplyPreset(gfpZeroGCorridorInversion);
    HighPrioCeiling.Priority := 50;
    HighPrioCeiling.Translation := Vector3(50, 8.0, 0);
    Vp.Items.Add(HighPrioCeiling);

    CompositeS := TCastleGravityField.EvaluateCompositeWorldGravity(Vp, Vector3(50, 8.0, 0));
    AssertTrue(CompositeS.InsideInfluence);
    AssertEquals(50, CompositeS.SourcePriority);
    AssertVectorEquals(Vector3(0, -1, 0), CompositeS.UpVector, 0.001);

    { 3. Bounded-rate Up-vector slerp including exact 180-degree antipodal flip without NaN }
    CurUp := Vector3(0, 1, 0);
    for StepIdx := 1 to 12 do
    begin
      CurUp := TCastleGravityField.StepSmoothUpVectorSlerp(CurUp, Vector3(0, -1, 0), 6.0, 0.05);
      AssertFalse(IsNan(CurUp.X) or IsNan(CurUp.Y) or IsNan(CurUp.Z));
      AssertSameValue(1.0, CurUp.Length, 0.001);
    end;
    AssertVectorEquals(Vector3(0, -1, 0), CurUp, 0.001);

    Md := TGravityFieldHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Dynamic Gravity Well & Planetary Walk Report', Md) > 0);

    { 4. Verify csTransient preview gizmo never leaks into serialized JSON + ConfigJson roundtrip }
    SavedJson := ComponentToString(Tube);
    AssertEquals(0, Pos('TransientGravityPreview', SavedJson));
    Cfg := Tube.ConfigJson;
    Restored := StringToComponent(SavedJson, RestoredOwner) as TCastleGravityField;
    AssertTrue(Restored <> nil);
    Restored.ConfigJson := Cfg;
    AssertEquals(Ord(gskHollowCylinderInterior), Ord(Restored.ShapeKind));
    AssertSameValue(10.0, Restored.PlanetRadius, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Owner);
  end;
end;

initialization
  RegisterTest(TTestToolGravityField);

end.
