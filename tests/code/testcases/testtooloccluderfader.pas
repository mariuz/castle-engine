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

{ Automated tests for Phase 362 Smart Camera Occluder Cutaway & Foliage Parting Studio. }
unit TestToolOccluderFader;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolOccluderFader = class(TCastleTestCase)
  published
    procedure TestCameraSightlineWallCutawayNonBlockingPillarIsolationAndOpacityRecovery;
    procedure TestRadialFoliagePartingExactBladeLengthPreservationAndCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleComponentSerialize,
  CastleOccluderFader, ToolOccluderFader;

procedure TTestToolOccluderFader.TestCameraSightlineWallCutawayNonBlockingPillarIsolationAndOpacityRecovery;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Fader: TCastleCameraOccluderFader;
  Hero, FrontWall, SidePillar: TCastleTransform;
  I, ActiveCnt: Integer;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TOccluderFaderHelper.SpawnArpgCourtyardCutawayDemo(
      Vp, RootOwner, Fader, Hero, FrontWall, SidePillar));

    { 1. Step camera at (0, 2.5, 10) looking through CastleFrontWallOccluder (Z=4) toward Hero (0, 0.9, 0) }
    for I := 1 to 10 do
      ActiveCnt := Fader.StepOccluderAndFoliage(
        Vp.Items, Vector3(0.0, 2.5, 10.0), Hero.Translation, [Hero.Translation], 0.15);

    AssertEquals('Exactly 1 obstructing wall must fade while side pillar & hero stay solid', 1, ActiveCnt);
    AssertSameValue(Fader.CutawayMinOpacity, Fader.GetTrackedOpacity('CastleFrontWallOccluder'), 0.02);
    AssertSameValue(Fader.CutawayMinOpacity, (FrontWall as TCastleBox).Color.W, 0.02);
    AssertSameValue(1.0, (SidePillar as TCastleBox).Color.W, 0.001);
    AssertSameValue(1.0, (Hero as TCastleBox).Color.W, 0.001);

    { 2. Move camera overhead to an unobstructed sightline (0, 14, 1.0) -> wall must smoothly recover to 100% opacity! }
    for I := 1 to 16 do
      ActiveCnt := Fader.StepOccluderAndFoliage(
        Vp.Items, Vector3(0.0, 14.0, 1.0), Hero.Translation, [Hero.Translation], 0.15);

    AssertEquals('Cleared sightline must recover all occluders back to 100% opacity', 0, ActiveCnt);
    AssertSameValue(1.0, (FrontWall as TCastleBox).Color.W, 0.01);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolOccluderFader.TestRadialFoliagePartingExactBladeLengthPreservationAndCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Fader, Restored: TCastleCameraOccluderFader;
  NearBladeRoot, FarBladeRoot, NearTip, FarTip: TVector3;
  NearBendDeg, FarBendDeg: Single;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Fader := TCastleCameraOccluderFader.Create(RootOwner);
    Fader.Name := 'MeadowFader';
    Fader.Preset := ofpStealthTallGrassParting;

    { 1. Grass blade at X = +0.40m next to Hero at Origin must bend radially outward (+X)
         while preserving exact 1.35m inextensible blade length! }
    NearBladeRoot := Vector3(0.40, 0.0, 0.0);
    NearTip := Fader.EvaluateBladePartingTip(NearBladeRoot, 1.35, [Vector3(0, 0, 0)], NearBendDeg);
    AssertTrue('Near grass blade must bend strongly outward (> 35 deg)', NearBendDeg > 35.0);
    AssertTrue('Near grass tip must part radially away along +X', NearTip.X > NearBladeRoot.X + 0.70);
    AssertSameValue(1.35, (NearTip - NearBladeRoot).Length, 0.0005);

    { 2. Grass blade outside FoliagePartingRadius (X = 6.0m > 2.6m) must stand straight upright (0 deg) }
    FarBladeRoot := Vector3(6.0, 0.0, 0.0);
    FarTip := Fader.EvaluateBladePartingTip(FarBladeRoot, 1.35, [Vector3(0, 0, 0)], FarBendDeg);
    AssertSameValue(0.0, FarBendDeg, 0.001);
    AssertVectorEquals(Vector3(6.0, 1.35, 0.0), FarTip, 0.001);

    ReportMd := TOccluderFaderHelper.GenerateOccluderReport(Fader);
    AssertTrue(Pos('Stealth Tall-Grass Meadow Parting', ReportMd) > 0);

    JsonStr := ComponentToString(Fader);
    AssertEquals(0, Pos('TransientFoliagePartingMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleCameraOccluderFader;
    AssertTrue(Restored.Preset = ofpStealthTallGrassParting);
    AssertSameValue(2.60, Restored.FoliagePartingRadius, 0.001);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolOccluderFader);
end.
