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

{ Automated tests for Phase 408: Granular Rockslide, Talus Scree Cone &
  Angle-of-Repose Avalanche Studio. }
unit TestToolAvalancheSlide;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolAvalancheSlide = class(TCastleTestCase)
  published
    procedure TestExactMassConservationAngleOfReposeRunoutScaling;
    procedure TestWorldRayConcreteDeflectionBermCompleteDownstreamProtectionAndJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleAvalancheSlide, ToolAvalancheSlide;

procedure TTestToolAvalancheSlide.TestExactMassConservationAngleOfReposeRunoutScaling;
var
  Granite, WetSnow: TCastleAvalancheSlide;
  InitialVol: Single;
begin
  Granite := TCastleAvalancheSlide.Create(nil);
  WetSnow := TCastleAvalancheSlide.Create(nil);
  try
    Granite.ApplyPreset(aspGraniteTalusRockslide);
    Granite.ResetDefaultMountainChute;
    InitialVol := Granite.TotalDebrisVolumeCubicMeters;
    AssertSameValue(72.0, InitialVol, 0.01);

    Granite.StepAvalancheRelaxation(80);
    { 1. Exact 100.00% granular debris mass/volume conservation across 80 passes }
    AssertSameValue(InitialVol, Granite.TotalDebrisVolumeCubicMeters, 0.005);

    { 2. Wet alpine slab snow (16 deg angle of repose) flows substantially farther
         down-valley than angular 38-deg granite talus scree! }
    WetSnow.ResetDefaultMountainChute;
    WetSnow.ApplyPreset(aspWetAlpineSlabAvalanche);
    WetSnow.StepAvalancheRelaxation(80);
    AssertSameValue(InitialVol, WetSnow.TotalDebrisVolumeCubicMeters, 0.005);
    AssertTrue('16-deg wet slab snow runout exceeds 38-deg granite scree cone',
      WetSnow.MaxRunoutDistanceMeters > Granite.MaxRunoutDistanceMeters + 2.5);
  finally
    FreeAndNil(WetSnow);
    FreeAndNil(Granite);
  end;
end;

procedure TTestToolAvalancheSlide.TestWorldRayConcreteDeflectionBermCompleteDownstreamProtectionAndJson;
var
  Root: TComponent;
  VP: TCastleViewport;
  Slide, Restored: TCastleAvalancheSlide;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleAvalancheSlide.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TAvalancheSlideHelper.SpawnMountainChuteWithBermDemo(Root, Root, Slide));

    { Bake WorldRay valley floor + 6.0m ConcreteSnowShedBerm at X = 15.5m (Bin 15),
      re-add steep upper cliff (bins 0..6) and release wet avalanche slab! }
    Slide.BakeBedrockAndBermsFromWorld(VP.Items);
    AssertSameValue(6.0, Slide.GetBinSample(15).BedrockElevationY, 0.05);

    Slide.ApplyPreset(aspWetAlpineSlabAvalanche);
    Slide.ReleaseHeadscarpSlab(8, 11, 1.80);
    Slide.StepAvalancheRelaxation(90);

    { 6.0m concrete deflection berm completely arrests the avalanche upstream:
      ZERO debris spills onto the protected village roadbed in bins 16..23! }
    AssertSameValue(0.0, Slide.DebrisVolumeFromBinRange(16, 23), 0.0001);

    SerializedScene := ComponentToString(Slide);
    AssertTrue(Pos('AvalancheSlidePreview', SerializedScene) = 0);

    Slide.AngleOfReposeDeg := 29.5;
    JsonCfg := TAvalancheSlideHelper.ExportSlideJson(Slide);
    AssertTrue(TAvalancheSlideHelper.ImportSlideJson(Restored, JsonCfg));
    AssertSameValue(29.5, Restored.AngleOfReposeDeg, 0.01);
    Md := TAvalancheSlideHelper.GenerateMarkdownReport(Slide);
    AssertTrue(Pos('WetAlpineSlabAvalanche', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolAvalancheSlide);

end.
