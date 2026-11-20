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

{ Automated tests for Phase 402: Tactical Stealth Light-Gem Meter, WorldRay
  Multi-Light Shadow Occlusion & Backlight Silhouette Studio. }
unit TestToolStealthLightGem;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolStealthLightGem = class(TCastleTestCase)
  published
    procedure TestWorldRayPillarShadowOcclusionDirectTorchlightAndStanceMultiplier;
    procedure TestGuardSightlineBacklightSilhouetteSpotConeAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleStealthLightGem, ToolStealthLightGem;

procedure TTestToolStealthLightGem.TestWorldRayPillarShadowOcclusionDirectTorchlightAndStanceMultiplier;
var
  Root: TComponent;
  VP: TCastleViewport;
  Gem: TCastleStealthLightGem;
  SmpShadowCrouch, SmpExposedStand, SmpExposedCrouchStill: TStealthLightGemSample;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TStealthLightGemHelper.SpawnGothicCloisterStealthDemo(Root, Root, Gem));

    { 1. Behind CloisterShadowPillar at (0, 1.2, -2.2): NorthCourtyardSconce at
         (0, 2.0, +4.0) is occluded by the stone pillar via WorldRay and
         FarArchwayBrazier (R=7m at (3.5, 1.8, -10.0), dist ~8.55m) is out of range! }
    SmpShadowCrouch := Gem.EvaluateLightGem(VP.Items,
      Vector3(0.0, 1.2, -2.2), Vector3(-5.0, 1.7, -2.2), True, True);
    AssertEquals(1, SmpShadowCrouch.ShadowedTorchCount);
    AssertEquals(0, SmpShadowCrouch.VisibleTorchCount);
    AssertTrue('Deep stone-pillar shadow + crouch/still keeps LightGem < 0.05',
      SmpShadowCrouch.FinalVisibilityGem01 < 0.05);

    { 2. Step directly in front of NorthCourtyardSconce at (0, 1.5, +2.4) standing/moving }
    SmpExposedStand := Gem.EvaluateLightGem(VP.Items,
      Vector3(0.0, 1.5, 2.4), Vector3(-5.0, 1.7, 2.4), False, False);
    AssertEquals(1, SmpExposedStand.VisibleTorchCount);
    AssertTrue('Direct unoccluded torchlight drives LightGem above alert threshold',
      SmpExposedStand.FinalVisibilityGem01 > 0.70);

    { 3. Crouching + holding still at the exact same lit spot reduces visibility }
    SmpExposedCrouchStill := Gem.EvaluateLightGem(VP.Items,
      Vector3(0.0, 1.5, 2.4), Vector3(-5.0, 1.7, 2.4), True, True);
    AssertTrue('Crouch + Stillness multiplier significantly lowers gem visibility',
      SmpExposedCrouchStill.FinalVisibilityGem01 < SmpExposedStand.FinalVisibilityGem01 * 0.55);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolStealthLightGem.TestGuardSightlineBacklightSilhouetteSpotConeAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Gem, Restored: TCastleStealthLightGem;
  SmpBacklit, SmpSideSafe: TStealthLightGemSample;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleStealthLightGem.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    Gem := TCastleStealthLightGem.Create(Root);
    Gem.Name := 'SilhouetteTestGem';
    VP.Items.Add(Gem);

    { Narrow 20-deg spotlight pointing AWAY (-Z) at Z = -14.0 (radius 5m so player at Z = 0
      receives ZERO direct illumination, yet stands right between Guard (0, 1.6, +6)
      and the bright distant window/brazier at (0, 1.6, -14)!) }
    Gem.AddSpotTorch('DistantWindowBacklight', Vector3(0.0, 1.6, -14.0),
      Vector3(0.0, 0.0, 1.0), 1.6, 5.0, 35.0);

    SmpBacklit := Gem.EvaluateLightGem(VP.Items,
      Vector3(0.0, 1.6, 0.0), Vector3(0.0, 1.6, 6.0), False, False);
    AssertTrue('Direct illumination at 14m outside 5m torch radius is ambient-only',
      SmpBacklit.DirectIllumination01 < 0.06);
    AssertTrue('Standing directly on Guard->Torch sightline exposes strong backlight silhouette',
      SmpBacklit.BacklightSilhouette01 > 0.65);
    AssertTrue('Backlight silhouette raises FinalVisibilityGem above alert threshold',
      SmpBacklit.FinalVisibilityGem01 > Gem.AlertThreshold01);

    { Guard looking from the side (-8, 1.6, 0) sees no backlight alignment (< 0.01) }
    SmpSideSafe := Gem.EvaluateLightGem(VP.Items,
      Vector3(0.0, 1.6, 0.0), Vector3(-8.0, 1.6, 0.0), False, False);
    AssertSameValue(0.0, SmpSideSafe.BacklightSilhouette01, 0.001);

    SerializedScene := ComponentToString(Gem);
    AssertTrue(Pos('StealthLightGemPreview', SerializedScene) = 0);

    Gem.ApplyPreset(slpDaylightGhillieCamouflage);
    Gem.AlertThreshold01 := 0.68;
    JsonCfg := TStealthLightGemHelper.ExportGemJson(Gem);
    AssertTrue(TStealthLightGemHelper.ImportGemJson(Restored, JsonCfg));
    AssertEquals(Ord(slpDaylightGhillieCamouflage), Ord(Restored.Preset));
    AssertSameValue(0.68, Restored.AlertThreshold01, 0.01);
    Md := TStealthLightGemHelper.GenerateMarkdownReport(Gem);
    AssertTrue(Pos('DaylightGhillieCamouflage', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolStealthLightGem);

end.
