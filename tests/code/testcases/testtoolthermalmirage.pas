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

{ Automated tests for Phase 401: Heat-Haze Mirage, Thermal Convection Plume &
  Underwater Caustic Refraction Field Studio. }
unit TestToolThermalMirage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolThermalMirage = class(TCastleTestCase)
  published
    procedure TestGrazingVsSteepInferiorMirageAndBoussinesqThermalUpdraft;
    procedure TestSunlitCoralReefCausticFocalCuspsOutOfBoundsAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleThermalMirage, ToolThermalMirage;

procedure TTestToolThermalMirage.TestGrazingVsSteepInferiorMirageAndBoussinesqThermalUpdraft;
var
  Root: TComponent;
  VP: TCastleViewport;
  Vol: TCastleThermalMirageVolume;
  SmpGrazing, SmpOverhead: TThermalOpticalSample;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TThermalMirageHelper.SpawnDesertHighwayMirageDemo(Root, Root, Vol));

    { 1. Shallow ~2 deg driver gaze across hot desert asphalt (0, 0.1, -12) from
         (0, 1.1, +18) produces strong inferior mirage sky reflection (> 0.65)! }
    SmpGrazing := Vol.SampleOpticalFieldAtWorld(
      Vector3(0.0, 0.10, -12.0), Vector3(0.0, 1.10, 18.0));
    AssertTrue(SmpGrazing.InsideVolume);
    AssertTrue('Grazing desert highway sightline triggers strong inferior mirage',
      SmpGrazing.InferiorMirageReflectivity01 > 0.65);
    AssertTrue('Hot asphalt generates buoyant Boussinesq updraft > 0.4 m/s',
      SmpGrazing.UpdraftVelocityMps > 0.40);

    { 2. Steep 65 deg overhead bird''s-eye view sees zero inferior mirage! }
    SmpOverhead := Vol.SampleOpticalFieldAtWorld(
      Vector3(0.0, 0.10, 0.0), Vector3(0.0, 22.0, 4.0));
    AssertSameValue(0.0, SmpOverhead.InferiorMirageReflectivity01, 0.001);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolThermalMirage.TestSunlitCoralReefCausticFocalCuspsOutOfBoundsAndJsonRoundtrip;
var
  Vol, Restored: TCastleThermalMirageVolume;
  SmpCusp, SmpOutside: TThermalOpticalSample;
  PeakCaustic: Single;
  I: Integer;
  SerializedScene, JsonCfg, Md: String;
begin
  Vol := TCastleThermalMirageVolume.Create(nil);
  Restored := TCastleThermalMirageVolume.Create(nil);
  try
    Vol.ApplyPreset(tmpSunlitCoralReefCaustics);
    Vol.StepOpticalPhase(0.5);

    PeakCaustic := 0.0;
    for I := 0 to 40 do
    begin
      SmpCusp := Vol.SampleOpticalFieldAtWorld(
        Vector3(-4.0 + I * 0.2, 0.2, -4.0 + I * 0.15), Vector3(0.0, 5.0, 5.0));
      if SmpCusp.CausticLuminanceBoost > PeakCaustic then
        PeakCaustic := SmpCusp.CausticLuminanceBoost;
    end;
    AssertTrue('Coral reef caustic network produces bright focal cusps > 0.8x',
      PeakCaustic > 0.80);

    { Point outside volume extents returns InsideVolume = False and zero distortion }
    SmpOutside := Vol.SampleOpticalFieldAtWorld(
      Vector3(999.0, 0.5, 0.0), TVector3.Zero);
    AssertFalse(SmpOutside.InsideVolume);
    AssertSameValue(0.0, SmpOutside.CausticLuminanceBoost, 0.0001);

    SerializedScene := ComponentToString(Vol);
    AssertTrue(Pos('ThermalMiragePreview', SerializedScene) = 0);

    Vol.WaterDepthMeters := 7.25;
    JsonCfg := TThermalMirageHelper.ExportVolumeJson(Vol);
    AssertTrue(TThermalMirageHelper.ImportVolumeJson(Restored, JsonCfg));
    AssertEquals(Ord(tmpSunlitCoralReefCaustics), Ord(Restored.Preset));
    AssertSameValue(7.25, Restored.WaterDepthMeters, 0.01);
    Md := TThermalMirageHelper.GenerateMarkdownReport(Vol);
    AssertTrue(Pos('SunlitCoralReefCaustics', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Vol);
  end;
end;

initialization
  RegisterTest(TTestToolThermalMirage);

end.
