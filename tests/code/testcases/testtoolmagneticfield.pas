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

{ Automated tests for Phase 409: 3D Magnetic Dipole, Ferromagnetic Snap,
  Zero-G Mag-Boots & Eddy-Current Brake Studio. }
unit TestToolMagneticField;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolMagneticField = class(TCastleTestCase)
  published
    procedure TestExactDipolePolarVsEquatorialRatioInverseCubeAndAttractRepelPolarity;
    procedure TestLenzEddyCurrentBrakingWorldRayZeroGMagBootsAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleMagneticField, ToolMagneticField;

procedure TTestToolMagneticField.TestExactDipolePolarVsEquatorialRatioInverseCubeAndAttractRepelPolarity;
var
  Mag: TCastleMagneticField;
  BPole2m, BEq2m, BPole4m: TVector3;
  FAttract, FRepel: TMagneticForceSample;
begin
  Mag := TCastleMagneticField.Create(nil);
  try
    Mag.ApplyPreset(mfpScrapyardElectromagnetCrane);

    { 1. Exact dipole tensor identity: at equal radius r = 2.0m, polar |B(0, 2, 0)|
         is EXACTLY 2.0x equatorial |B(2, 0, 0)|, and doubling r -> 4.0m drops |B| by 8x! }
    BPole2m := Mag.SampleBFieldTeslaAtWorld(Vector3(0.0, 2.0, 0.0));
    BEq2m := Mag.SampleBFieldTeslaAtWorld(Vector3(2.0, 0.0, 0.0));
    BPole4m := Mag.SampleBFieldTeslaAtWorld(Vector3(0.0, 4.0, 0.0));

    AssertTrue(BPole2m.Y > 0.0);
    AssertTrue(BEq2m.Y < 0.0);
    AssertSameValue(2.0 * Abs(BEq2m.Y), BPole2m.Y, 1e-5);
    AssertSameValue(BPole2m.Y / 8.0, BPole4m.Y, 1e-5);

    { 2. Parallel axial dipole at (0, +2.0, 0) (North-to-South) experiences
         downward ATTRACTIVE force (Fy < 0 toward origin), whereas anti-parallel
         like-pole dipole experiences upward REPULSIVE force (Fy > 0)! }
    FAttract := Mag.EvaluateMagneticForces(
      Vector3(0.0, 2.0, 0.0), TVector3.Zero, Vector3(0.0, 5000.0, 0.0), 0.0);
    FRepel := Mag.EvaluateMagneticForces(
      Vector3(0.0, 2.0, 0.0), TVector3.Zero, Vector3(0.0, -5000.0, 0.0), 0.0);
    AssertTrue('Aligned North-South poles attract toward origin (Fy < 0)',
      FAttract.DipoleForceNewtons.Y < -50.0);
    AssertTrue('Opposing North-North poles repel away from origin (Fy > 0)',
      FRepel.DipoleForceNewtons.Y > 50.0);
    AssertSameValue(-FAttract.DipoleForceNewtons.Y, FRepel.DipoleForceNewtons.Y, 0.05);
  finally
    FreeAndNil(Mag);
  end;
end;

procedure TTestToolMagneticField.TestLenzEddyCurrentBrakingWorldRayZeroGMagBootsAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Mag, Restored: TCastleMagneticField;
  EddyRest, EddyFast: TMagneticForceSample;
  BootLock, BootVoid: TMagBootGripResult;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleMagneticField.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TMagneticFieldHelper.SpawnSpacecraftHullMagBootDemo(Root, Root, Mag));

    { 1. Lenz-law eddy-current brake: zero force at rest (v = 0), strong opposing
         braking force (-X) when coaster fin slices through gap at +25 m/s! }
    Mag.ApplyPreset(mfpRailcoasterEddyBrake);
    EddyRest := Mag.EvaluateMagneticForces(
      Vector3(0.0, 0.6, 0.0), TVector3.Zero, TVector3.Zero, 0.0);
    EddyFast := Mag.EvaluateMagneticForces(
      Vector3(0.0, 0.6, 0.0), Vector3(25.0, 0.0, 0.0), TVector3.Zero, 0.0);
    AssertSameValue(0.0, EddyRest.EddyBrakeForceNewtons.Length, 1e-5);
    AssertTrue('Lenz eddy-current brake opposes +X velocity with strong -X force',
      EddyFast.EddyBrakeForceNewtons.X < -500.0);

    { 2. Zero-G astronaut mag-boots upside-down beneath OrbitalSteelHullDeck (underside Y = 4.8m):
         probing upward (+Y) from Y = 4.2m locks onto Y = 4.8m; deep space misses! }
    Mag.ApplyPreset(mfpZeroGHullMagBoots);
    BootLock := Mag.ProbeZeroGMagBootGrip(VP.Items,
      Vector3(0.0, 4.2, 0.0), Vector3(0.0, 1.0, 0.0));
    AssertTrue(BootLock.HullLocked);
    AssertSameValue(4.8, BootLock.SnapWorldPoint.Y, 0.02);
    AssertTrue(BootLock.HoldForceNewtons > 2000.0);

    BootVoid := Mag.ProbeZeroGMagBootGrip(VP.Items,
      Vector3(50.0, 4.2, 0.0), Vector3(0.0, 1.0, 0.0));
    AssertFalse(BootVoid.HullLocked);

    SerializedScene := ComponentToString(Mag);
    AssertTrue(Pos('MagneticFieldPreview', SerializedScene) = 0);

    Mag.EddyConductivityGain := 3450.0;
    JsonCfg := TMagneticFieldHelper.ExportMagnetJson(Mag);
    AssertTrue(TMagneticFieldHelper.ImportMagnetJson(Restored, JsonCfg));
    AssertSameValue(3450.0, Restored.EddyConductivityGain, 0.1);
    Md := TMagneticFieldHelper.GenerateMarkdownReport(Mag);
    AssertTrue(Pos('ZeroGHullMagBoots', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolMagneticField);

end.
