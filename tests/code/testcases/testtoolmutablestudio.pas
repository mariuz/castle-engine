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

{ Automated tests for Phase 360 Mutable Modular Character Customizer Studio. }
unit TestToolMutableStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolMutableStudio = class(TCastleTestCase)
  published
    procedure TestClosedHelmHairAutoExclusionBodyMorphScalingAndMergedSingleDrawMesh;
    procedure TestCompactRecipeCodeRoundtripSeededDeterminismAndCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleMutableCharacter, ToolMutableStudio;

procedure TTestToolMutableStudio.TestClosedHelmHairAutoExclusionBodyMorphScalingAndMergedSingleDrawMesh;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Hero: TCastleMutableCharacter;
  ClosedHelmParts, OpenCircletParts: Integer;
  SlimShoulder, TitanShoulder, BaseHeight, TallHeight: Single;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TMutableStudioHelper.SpawnMutableTurntablePedestal(Vp, RootOwner, Hero));
    AssertTrue(Hero <> nil);

    { 1. Paladin preset uses HeadgearSlot = 1 (FullClosedGreathelm) + HairStyleSlot = 1:
         Hair MUST be auto-hidden so zero hair triangles clip through closed plate helm! }
    AssertTrue(Hero.IsHairAutoHiddenByHelm);
    ClosedHelmParts := Hero.MergedPartCount;
    AssertEquals(ClosedHelmParts * 12, Hero.GeneratedTriangleCount);

    { Switching to Open Circlet (HeadgearSlot = 3) un-hides HairStyleSlot = 1 (+1 merged part, +12 tris)! }
    Hero.HeadgearSlot := 3;
    AssertFalse(Hero.IsHairAutoHiddenByHelm);
    OpenCircletParts := Hero.MergedPartCount;
    AssertEquals(ClosedHelmParts + 1, OpenCircletParts);

    { 2. Parametric morph sliders scale shoulder span and stature monotonically }
    Hero.ShoulderBulkMorph := 0.0;
    Hero.HeightScale := 0.85;
    SlimShoulder := Hero.ShoulderSpanMeters;
    BaseHeight := Hero.TotalBoundsHeightMeters;

    Hero.ShoulderBulkMorph := 1.0;
    Hero.HeightScale := 1.22;
    TitanShoulder := Hero.ShoulderSpanMeters;
    TallHeight := Hero.TotalBoundsHeightMeters;

    AssertTrue('ShoulderBulkMorph must widen shoulder span', TitanShoulder > SlimShoulder + 0.30);
    AssertTrue('HeightScale must scale character total height', TallHeight > BaseHeight + 0.55);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolMutableStudio.TestCompactRecipeCodeRoundtripSeededDeterminismAndCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  HeroA, HeroB, Restored: TCastleMutableCharacter;
  RecipeA, JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    HeroA := TCastleMutableCharacter.Create(RootOwner);
    HeroA.Name := 'HeroA';
    HeroA.Preset := mapArcaneBattleMage;
    HeroA.HeightScale := 1.14;
    HeroA.ShoulderBulkMorph := 0.82;
    RecipeA := HeroA.ExportRecipeCode;
    AssertTrue(Pos('MUT1:', RecipeA) = 1);

    HeroB := TCastleMutableCharacter.Create(RootOwner);
    HeroB.Name := 'HeroB';
    AssertTrue(HeroB.ImportRecipeCode(RecipeA));
    AssertEquals(HeroA.HeadgearSlot, HeroB.HeadgearSlot);
    AssertEquals(HeroA.TorsoArmorSlot, HeroB.TorsoArmorSlot);
    AssertEquals(HeroA.WeaponHandSlot, HeroB.WeaponHandSlot);
    AssertSameValue(1.14, HeroB.HeightScale, 0.015);
    AssertSameValue(0.82, HeroB.ShoulderBulkMorph, 0.015);

    { Seeded randomization determinism }
    HeroA.RandomizeCharacter(777123);
    HeroB.RandomizeCharacter(777123);
    AssertEquals(HeroA.ExportRecipeCode, HeroB.ExportRecipeCode);

    HeroA.Preset := mapRangerHoodedScout;
    ReportMd := TMutableStudioHelper.GenerateMutableReport(HeroA);
    AssertTrue(Pos('Ranger Hooded Woodland Scout', ReportMd) > 0);

    JsonStr := ComponentToString(HeroA);
    AssertEquals(0, Pos('TransientMutableCharacterMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleMutableCharacter;
    AssertTrue(Restored.Preset = mapRangerHoodedScout);
    AssertEquals(2, Restored.HeadgearSlot);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMutableStudio);
end.
