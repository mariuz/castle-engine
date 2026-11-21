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

{ Automated tests for Phase 407: Procedural Rain Puddle, Roof Shelter,
  Specular Wetness & Splash Ripple Studio. }
unit TestToolPuddleWetness;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolPuddleWetness = class(TCastleTestCase)
  published
    procedure TestOpenSkyPuddleMirrorRoughnessVsWorldRayPorchRoofDryShelter;
    procedure TestSplashRipplePropagationRingCapEvaporationAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastlePuddleWetness, ToolPuddleWetness;

procedure TTestToolPuddleWetness.TestOpenSkyPuddleMirrorRoughnessVsWorldRayPorchRoofDryShelter;
var
  Root: TComponent;
  VP: TCastleViewport;
  Field: TCastlePuddleWetnessField;
  SmpPuddle, SmpRidge, SmpUnderPorch: TPuddleSurfaceSample;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TPuddleWetnessHelper.SpawnCobblestonePorchStormDemo(Root, Root, Field));

    { 1. Open-sky basin center (0, 0, 0): standing water pools > 25mm, roughness
         collapses from 0.78 to mirror 0.025, and porous stone darkens (< 0.65)! }
    SmpPuddle := Field.SampleSurfaceWetnessAtWorld(VP.Items, TVector3.Zero);
    AssertTrue(SmpPuddle.InsideField);
    AssertFalse(SmpPuddle.RoofSheltered);
    AssertTrue('Basin center accumulates > 25mm standing rain puddle',
      SmpPuddle.StandingWaterDepthMeters > 0.025);
    AssertSameValue(0.025, SmpPuddle.EffectiveRoughness, 0.002);
    AssertTrue('Capillary wetness darkens porous cobblestone albedo',
      SmpPuddle.PorousAlbedoScale < 0.65);

    { 2. Open-sky cobblestone crest (Pi / 0.95 ~ 3.31m, 0, 0): Cos = -1 -> zero
         basin depression (no standing puddle), yet rain dampness still darkens stone! }
    SmpRidge := Field.SampleSurfaceWetnessAtWorld(VP.Items, Vector3(3.307, 0.0, 0.0));
    AssertSameValue(0.0, SmpRidge.StandingWaterDepthMeters, 0.0005);
    AssertTrue('Damp un-submerged crest is glossier than dry stone',
      (SmpRidge.EffectiveRoughness > 0.10) and (SmpRidge.EffectiveRoughness < Field.DryRoughness));

    { 3. Beneath TavernRainShelterAwning at (+6.0, 0.0, 0.0): upward WorldRay hits
         porch roof at Y = 3.075m -> completely dry (0mm water, 1.0 albedo, 0.78 rough)! }
    SmpUnderPorch := Field.SampleSurfaceWetnessAtWorld(VP.Items, Vector3(6.0, 0.0, 0.0));
    AssertTrue('Upward WorldRay detects overhead tavern awning', SmpUnderPorch.RoofSheltered);
    AssertSameValue(0.0, SmpUnderPorch.StandingWaterDepthMeters, 0.0001);
    AssertSameValue(1.0, SmpUnderPorch.PorousAlbedoScale, 0.001);
    AssertSameValue(Field.DryRoughness, SmpUnderPorch.EffectiveRoughness, 0.001);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolPuddleWetness.TestSplashRipplePropagationRingCapEvaporationAndJsonRoundtrip;
var
  Field, Restored: TCastlePuddleWetnessField;
  SmpFront, SmpDried: TPuddleSurfaceSample;
  I: Integer;
  SerializedScene, JsonCfg, Md: String;
begin
  Field := TCastlePuddleWetnessField.Create(nil);
  Restored := TCastlePuddleWetnessField.Create(nil);
  try
    Field.ApplyPreset(pwpMuddyTrenchDownpour);
    Field.ClearRipples;
    Field.TriggerSplashAtWorld(TVector3.Zero, 6.0, 2.0);
    Field.StepRipplesAndEvaporation(0.40, 0.0);

    { Wave speed 1.15 m/s * 0.40s = 0.46m wavefront crest -> strong positive ripple! }
    SmpFront := Field.SampleSurfaceWetnessAtWorld(nil, Vector3(0.46, 0.0, 0.0));
    AssertTrue('Expanding splash wavefront produces > 2.5mm crest at R = v*t',
      SmpFront.RippleDisplacementMm > 2.5);

    { Ring buffer cap: 40 splashes never exceed MaxPooledPuddleRipples (24) }
    for I := 1 to 40 do
      Field.TriggerSplashAtWorld(Vector3(0.0, 0.0, 0.0), 3.0, 1.5);
    AssertEquals(MaxPooledPuddleRipples, Field.ActiveRippleCount);

    { Sun drying step evaporates all ripples & standing puddles }
    Field.StepRipplesAndEvaporation(2.5, 0.50);
    AssertEquals(0, Field.ActiveRippleCount);
    SmpDried := Field.SampleSurfaceWetnessAtWorld(nil, TVector3.Zero);
    AssertSameValue(0.0, SmpDried.StandingWaterDepthMeters, 0.0001);

    SerializedScene := ComponentToString(Field);
    AssertTrue(Pos('PuddleWetnessPreview', SerializedScene) = 0);

    Field.WaterFillLevel01 := 0.64;
    JsonCfg := TPuddleWetnessHelper.ExportFieldJson(Field);
    AssertTrue(TPuddleWetnessHelper.ImportFieldJson(Restored, JsonCfg));
    AssertEquals(Ord(pwpMuddyTrenchDownpour), Ord(Restored.Preset));
    AssertSameValue(0.64, Restored.WaterFillLevel01, 0.01);
    Md := TPuddleWetnessHelper.GenerateMarkdownReport(Field);
    AssertTrue(Pos('MuddyTrenchDownpour', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Field);
  end;
end;

initialization
  RegisterTest(TTestToolPuddleWetness);

end.
