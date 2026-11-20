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

{ Automated tests for Phase 404: Procedural Torch & Campfire Blackbody Flicker,
  Wind-Draft Tilt, Gust Blowout & Wall Soot Studio. }
unit TestToolFlameFlicker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolFlameFlicker = class(TCastleTestCase)
  published
    procedure TestPlanckianBlackbodyShiftWindTiltGustBlowoutAndStormLanternShielding;
    procedure TestWorldRayWallAndCeilingSootDarkeningReigniteAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleFlameFlicker, ToolFlameFlicker;

procedure TTestToolFlameFlicker.TestPlanckianBlackbodyShiftWindTiltGustBlowoutAndStormLanternShielding;
var
  RgbEmber, RgbHot: TVector3;
  Torch, Lantern: TCastleFlameFlickerRig;
  SmpDraft, SmpBlowout, SmpDecay, SmpLanternGale: TFlameFlickerSample;
begin
  { 1. Planckian locus monotonicity: 1800K ember is deep red-orange (B = 0),
       while 2900K hot gas flame shifts dramatically whiter (higher G and B > 0.35)! }
  RgbEmber := TCastleFlameFlickerRig.KelvinToBlackbodyRgb(1800.0);
  RgbHot := TCastleFlameFlickerRig.KelvinToBlackbodyRgb(2900.0);
  AssertSameValue(1.0, RgbEmber.X, 0.001);
  AssertSameValue(0.0, RgbEmber.Z, 0.001);
  AssertTrue('2900K blackbody green channel exceeds 1800K ember', RgbHot.Y > RgbEmber.Y + 0.18);
  AssertTrue('2900K blackbody blue channel exceeds 0.35', RgbHot.Z > 0.35);

  Torch := TCastleFlameFlickerRig.Create(nil);
  Lantern := TCastleFlameFlickerRig.Create(nil);
  try
    Torch.ApplyPreset(ffpDungeonWallSconceTorch);
    { 2. Moderate +5 m/s +X draft tilts flame tip toward +X while staying lit }
    SmpDraft := Torch.StepFlameCombustion(0.20, Vector3(5.0, 0.0, 0.0));
    AssertTrue(SmpDraft.IsLit);
    AssertTrue('Draft tilts flame tip in +X wind direction', SmpDraft.FlameTipLocalOffset.X > 0.15);
    AssertTrue(SmpDraft.IntensityMultiplier > 0.5);

    { 3. Fierce +14 m/s gale exceeds 9.5 m/s BlowoutWindSpeedMps -> extinguishes sconce
         and emits a 100% smoke puff that decays over subsequent seconds! }
    SmpBlowout := Torch.StepFlameCombustion(0.10, Vector3(14.0, 0.0, 0.0));
    AssertFalse('14 m/s dungeon gale blows out open wall sconce', SmpBlowout.IsLit);
    AssertTrue(SmpBlowout.ExtinguishedThisStep);
    AssertSameValue(0.0, SmpBlowout.IntensityMultiplier, 0.0001);
    AssertSameValue(1.0, SmpBlowout.SmokePuffAlpha01, 0.001);

    SmpDecay := Torch.StepFlameCombustion(0.60, TVector3.Zero);
    AssertFalse(SmpDecay.IsLit);
    AssertTrue('Smoke puff dissipates smoothly after blowout',
      (SmpDecay.SmokePuffAlpha01 > 0.1) and (SmpDecay.SmokePuffAlpha01 < 0.7));

    { 4. Glass-shielded storm lantern survives the exact same 14 m/s gale! }
    Lantern.ApplyPreset(ffpStormLanternShielded);
    SmpLanternGale := Lantern.StepFlameCombustion(0.15, Vector3(14.0, 0.0, 0.0));
    AssertTrue('Hurricane glass storm lantern stays lit in 14 m/s gale',
      SmpLanternGale.IsLit);
  finally
    FreeAndNil(Lantern);
    FreeAndNil(Torch);
  end;
end;

procedure TTestToolFlameFlicker.TestWorldRayWallAndCeilingSootDarkeningReigniteAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Rig, OpenCampfire, Restored: TCastleFlameFlickerRig;
  SootSconce, SootOpen: TWallSootProbeResult;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleFlameFlickerRig.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TFlameFlickerHelper.SpawnDungeonWallSconceDemo(Root, Root, Rig));

    { 1. Sconce at (0, 1.85, 0) detects both SconceStoneBackWall (0.35m -Z)
         and SconceVaultCeiling (1.10m +Y) via WorldRay! }
    SootSconce := Rig.ProbeWallAndCeilingSoot(VP.Items);
    AssertTrue(SootSconce.WallHit);
    AssertTrue(SootSconce.CeilingHit);
    AssertEquals(2, SootSconce.SootSurfaceCount);
    AssertTrue('Close stone back-wall accumulates > 45% soot darkening',
      SootSconce.WallSootDarkening01 > 0.45);
    AssertTrue('Low vault arch ceiling accumulates > 25% soot darkening',
      SootSconce.CeilingSootDarkening01 > 0.25);

    { 2. Open-sky campfire far at (+25, 0.5, +25) hits zero nearby walls/ceilings }
    OpenCampfire := TCastleFlameFlickerRig.Create(Root);
    OpenCampfire.ApplyPreset(ffpHearthCampfireBrazier);
    OpenCampfire.Translation := Vector3(25.0, 0.5, 25.0);
    VP.Items.Add(OpenCampfire);
    SootOpen := OpenCampfire.ProbeWallAndCeilingSoot(VP.Items);
    AssertEquals(0, SootOpen.SootSurfaceCount);
    AssertSameValue(0.0, SootOpen.WallSootDarkening01, 0.0001);

    { 3. Extinguish + Reignite + JSON roundtrip }
    Rig.ExtinguishFlame;
    AssertFalse(Rig.IsLit);
    Rig.ReigniteFlame;
    AssertTrue(Rig.IsLit);

    SerializedScene := ComponentToString(Rig);
    AssertTrue(Pos('FlameFlickerPreview', SerializedScene) = 0);

    Rig.BlowoutWindSpeedMps := 12.75;
    JsonCfg := TFlameFlickerHelper.ExportRigJson(Rig);
    AssertTrue(TFlameFlickerHelper.ImportRigJson(Restored, JsonCfg));
    AssertSameValue(12.75, Restored.BlowoutWindSpeedMps, 0.01);
    Md := TFlameFlickerHelper.GenerateMarkdownReport(Rig);
    AssertTrue(Pos('DungeonWallSconceTorch', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolFlameFlicker);

end.
