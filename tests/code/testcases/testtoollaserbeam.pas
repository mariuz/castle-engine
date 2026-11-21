{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 411: Multi-Bounce Optical Laser, Mirror Reflection,
  Snell Prism Refraction & Beam-Break Cutoff Studio. }
unit TestToolLaserBeam;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolLaserBeam = class(TCastleTestCase)
  published
    procedure TestTwo45DegMirrorRelayReceiverPoweringAndCrateBeamBreakCutoff;
    procedure TestExactVectorSnellLawRefractionTotalInternalReflectionAndJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleLaserBeam, ToolLaserBeam;

procedure TTestToolLaserBeam.TestTwo45DegMirrorRelayReceiverPoweringAndCrateBeamBreakCutoff;
var
  Root: TComponent;
  VP: TCastleViewport;
  Laser: TCastleLaserBeamRig;
  Crate: TCastleTransform;
  I: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TLaserBeamHelper.SpawnTwoMirrorReceiverPuzzleDemo(Root, Root, Laser));

    { 1. Unobstructed 2-mirror U-turn: (0,1.5,0) -> Mirror_NorthWest45 (0,1.5,-5)
         -> Mirror_NorthEast45 (+6,1.5,-5) -> Receiver_CrystalGoal (+6,1.5,0)! }
    AssertEquals(3, Laser.SegmentCount);
    AssertTrue('2-mirror relay powers Receiver_CrystalGoal', Laser.ReceiverPowered);
    AssertEquals('Receiver_CrystalGoal', Laser.PoweredReceiverName);
    AssertTrue(Laser.DeliveredPowerWatts > 35.0);

    { 2. Slide Crate_BeamBlocker onto Leg #2 at (+3, 1.5, -5): cuts off beam immediately! }
    Crate := nil;
    for I := 0 to VP.Items.Count - 1 do
      if VP.Items[I].Name = 'Crate_BeamBlocker' then
        Crate := VP.Items[I];
    AssertTrue(Crate <> nil);

    Crate.Translation := Vector3(3.0, 1.5, -5.0);
    Laser.TraceLaserBeam(VP.Items);
    AssertEquals(2, Laser.SegmentCount);
    AssertFalse('Solid crate blocking Leg #2 immediately de-powers receiver',
      Laser.ReceiverPowered);
    AssertEquals('Crate_BeamBlocker', Laser.LastHitObjectName);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolLaserBeam.TestExactVectorSnellLawRefractionTotalInternalReflectionAndJson;
var
  Inc30, NormUp, RefractDir,IncSteep, TirDir: TVector3;
  SinTheta1, SinTheta2: Single;
  WasTIR: Boolean;
  Laser, Restored: TCastleLaserBeamRig;
  SerializedScene, JsonCfg, Md: String;
begin
  { 1. Air (n1 = 1.0) -> Crown Glass (n2 = 1.50) at theta1 = 30 deg:
       n1 * sin(theta1) = n2 * sin(theta2) -> sin(theta2) = 0.5 / 1.5 = 1/3! }
  Inc30 := Vector3(Sin(DegToRad(30.0)), -Cos(DegToRad(30.0)), 0.0);
  NormUp := Vector3(0.0, 1.0, 0.0);
  RefractDir := TCastleLaserBeamRig.ComputeSnellRefractionOrTIR(
    Inc30, NormUp, 1.0 / 1.50, WasTIR);
  AssertFalse(WasTIR);
  SinTheta1 := Sin(DegToRad(30.0));
  SinTheta2 := Abs(RefractDir.X);
  AssertSameValue(1.0 * SinTheta1, 1.50 * SinTheta2, 1e-5);

  { 2. Glass (n1 = 1.52) -> Air (n2 = 1.0) at 60 deg (> critical 41.1 deg):
       triggers Total Internal Reflection (TIR, Y flips positive)! }
  IncSteep := Vector3(Sin(DegToRad(60.0)), -Cos(DegToRad(60.0)), 0.0);
  TirDir := TCastleLaserBeamRig.ComputeSnellRefractionOrTIR(
    IncSteep, NormUp, 1.52 / 1.0, WasTIR);
  AssertTrue('60 deg internal incidence in n=1.52 glass triggers TIR', WasTIR);
  AssertSameValue(Cos(DegToRad(60.0)), TirDir.Y, 1e-5);

  Laser := TCastleLaserBeamRig.Create(nil);
  Restored := TCastleLaserBeamRig.Create(nil);
  try
    Laser.TraceLaserBeam(nil);
    SerializedScene := ComponentToString(Laser);
    AssertTrue(Pos('LaserBeamPreview', SerializedScene) = 0);

    Laser.PrismRefractiveIndex := 1.74;
    JsonCfg := TLaserBeamHelper.ExportLaserJson(Laser);
    AssertTrue(TLaserBeamHelper.ImportLaserJson(Restored, JsonCfg));
    AssertSameValue(1.74, Restored.PrismRefractiveIndex, 0.01);
    Md := TLaserBeamHelper.GenerateMarkdownReport(Laser);
    AssertTrue(Pos('RubyPuzzleRelayLaser', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Laser);
  end;
end;

initialization
  RegisterTest(TTestToolLaserBeam);

end.
