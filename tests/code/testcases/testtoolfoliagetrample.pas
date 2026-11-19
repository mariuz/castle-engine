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

{ Automated tests for Phase 393: Dynamic Foliage/Grass Trample, Radial
  Shockwave Blast Flatten & Damped Spring-Back Bend Field Studio. }
unit TestToolFoliageTrample;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolFoliageTrample = class(TCastleTestCase)
  published
    procedure TestRadialShockwaveOutwardPartingAndLengthPreservingStalkKinematics;
    procedure TestHookeanElasticSpringBackRecoveryPresetsAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleFoliageTrample, ToolFoliageTrample;

procedure TTestToolFoliageTrample.TestRadialShockwaveOutwardPartingAndLengthPreservingStalkKinematics;
var
  Field: TCastleFoliageTrampleField;
  SmpEast, SmpWest, SmpNorth, SmpFar: TFoliageBendSample;
begin
  Field := TCastleFoliageTrampleField.Create(nil);
  try
    Field.ApplyPreset(ftpGoldenWheatField);
    Field.ResetField;
    AssertEquals(0, Field.TrampledCellCount);

    { Detonate grenade shockwave at origin (R = 5.0m) }
    Field.TriggerShockwaveBlast(TVector3.Zero, 5.0, 1.0);
    AssertTrue('Shockwave flattens interior cells', Field.TrampledCellCount > 25);

    SmpEast  := Field.SampleBendAtWorld(Vector3( 2.0, 0.0,  0.0));
    SmpWest  := Field.SampleBendAtWorld(Vector3(-2.0, 0.0,  0.0));
    SmpNorth := Field.SampleBendAtWorld(Vector3( 0.0, 0.0, -2.0));
    SmpFar   := Field.SampleBendAtWorld(Vector3( 7.2, 0.0,  7.2));

    { Stalks part radially outward from epicenter in every quadrant }
    AssertTrue('East stalks bend toward +X', SmpEast.BendXZ.X > 0.45);
    AssertTrue('West stalks bend toward -X', SmpWest.BendXZ.X < -0.45);
    AssertTrue('North stalks bend toward -Z', SmpNorth.BendXZ.Y < -0.45);
    AssertSameValue(0.0, SmpFar.TiltAngleDeg, 0.001);

    { Stalk length ||TipLocalOffset|| is strictly conserved under 3D bend }
    AssertSameValue(Field.StalkHeightMeters, SmpEast.TipLocalOffset.Length, 0.001);
    AssertSameValue(Field.StalkHeightMeters, SmpFar.TipLocalOffset.Length, 0.001);
  finally
    FreeAndNil(Field);
  end;
end;

procedure TTestToolFoliageTrample.TestHookeanElasticSpringBackRecoveryPresetsAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Field, Restored: TCastleFoliageTrampleField;
  PeakInitial: Single;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleFoliageTrampleField.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TFoliageTrampleHelper.SpawnWheatFieldDemo(Root, Root, Field));

    PeakInitial := Field.MaxActiveTiltDeg;
    AssertTrue(PeakInitial > 35.0);

    { Step damped Hookean recovery for 4.0s -> wheat stalks spring upright to rest }
    Field.StepElasticSpringBack(4.0);
    AssertTrue('Elastic spring-back restores stalks upright (< 2 deg)',
      Field.MaxActiveTiltDeg < 2.0);
    AssertEquals(0, Field.TrampledCellCount);

    SerializedScene := ComponentToString(Field);
    AssertTrue(Pos('FoliageTramplePreview', SerializedScene) = 0);

    Field.ApplyPreset(ftpAlienBioluminescentFerns);
    JsonCfg := TFoliageTrampleHelper.ExportFieldJson(Field);
    AssertTrue(TFoliageTrampleHelper.ImportFieldJson(Restored, JsonCfg));
    AssertEquals(Ord(ftpAlienBioluminescentFerns), Ord(Restored.Preset));
    Md := TFoliageTrampleHelper.GenerateMarkdownReport(Field);
    AssertTrue(Pos('AlienBioluminescentFerns', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolFoliageTrample);

end.
