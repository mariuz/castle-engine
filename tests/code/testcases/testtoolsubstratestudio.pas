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

{ Automated tests for Phase 367 Substrate Multi-Slab Layered Material Studio. }
unit TestToolSubstrateStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolSubstrateStudio = class(TCastleTestCase)
  published
    procedure TestStrictMultiSlabEnergyConservationBeerLambertAbsorptionAndVelvetGrazingRim;
    procedure TestThinFilmIridescenceSpectralShiftAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleSubstrateMaterial, ToolSubstrateStudio;

procedure TTestToolSubstrateStudio.TestStrictMultiSlabEnergyConservationBeerLambertAbsorptionAndVelvetGrazingRim;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Mat: TCastleSubstrateMaterial;
  ThinCoatS, ThickCoatS, VelvetNormalS, VelvetGrazingS: TSubstrateEvalSample;
  P: TSubstratePreset;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TSubstrateStudioHelper.SpawnSubstrateShaderBallDemo(Vp, RootOwner, Mat));

    { 1. Every preset across all viewing angles [0.05..1.0] must strictly conserve energy (<= 1.0)! }
    for P := subpAutomotiveCandyClearCoat to subpWetMossyCobblestone do
    begin
      Mat.Preset := P;
      AssertTrue('Substrate slab stack must never exceed 100% reflectance energy',
        Mat.EnergyConservedAcrossAngles);
      AssertTrue(Mat.PeakDirectionalAlbedo <= 1.0001);
    end;

    { 2. Beer-Lambert law: thickening tinted candy clear-coat from 5 um -> 90 um deepens green/blue absorption! }
    Mat.Preset := subpAutomotiveCandyClearCoat;
    Mat.TopCoatThicknessMicrons := 5.0;
    ThinCoatS := Mat.EvaluateSlabAtCosTheta(0.80);
    Mat.TopCoatThicknessMicrons := 90.0;
    ThickCoatS := Mat.EvaluateSlabAtCosTheta(0.80);
    AssertTrue('90 um tinted clear-coat must absorb more green channel than 5 um coat',
      ThickCoatS.BeerLambertTransmittance.Y < ThinCoatS.BeerLambertTransmittance.Y * 0.45);

    { 3. Royal Velvet microfiber fuzz exhibits strong grazing rim sheen vs. normal incidence }
    Mat.Preset := subpRoyalVelvetGoldTrim;
    VelvetNormalS := Mat.EvaluateSlabAtCosTheta(0.98);
    VelvetGrazingS := Mat.EvaluateSlabAtCosTheta(0.12);
    AssertTrue('Velvet grazing rim factor must exceed normal incidence by > 0.50',
      VelvetGrazingS.FuzzRimFactor > VelvetNormalS.FuzzRimFactor + 0.50);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolSubstrateStudio.TestThinFilmIridescenceSpectralShiftAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Mat, Restored: TCastleSubstrateMaterial;
  NormalFilmS, GrazingFilmS: TSubstrateEvalSample;
  SpectralDelta: Single;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Mat := TCastleSubstrateMaterial.Create(RootOwner);
    Mat.Name := 'ScarabMat';
    Mat.Preset := subpIridescentScarabCarapace;

    NormalFilmS := Mat.EvaluateSlabAtCosTheta(1.0);
    GrazingFilmS := Mat.EvaluateSlabAtCosTheta(0.30);
    SpectralDelta := (NormalFilmS.ThinFilmTint - GrazingFilmS.ThinFilmTint).Length;
    AssertTrue('520 nm thin-film carapace must shift interference color across viewing angles',
      SpectralDelta > 0.25);

    { Stress test extreme 100% white base + 100% fuzz + high-IOR coat -> still <= 1.0 energy! }
    Mat.SetBaseAlbedoRgb(Vector3(1.0, 1.0, 1.0));
    Mat.BaseMetallic := 1.0;
    Mat.FuzzCoverage := 1.0;
    Mat.TopCoatCoverage := 1.0;
    Mat.TopCoatIor := 2.40;
    AssertTrue(Mat.EnergyConservedAcrossAngles);

    ReportMd := TSubstrateStudioHelper.GenerateSubstrateReport(Mat);
    AssertTrue(Pos('PASS (100% CONSERVED)', ReportMd) > 0);

    JsonStr := ComponentToString(Mat);
    AssertEquals(0, Pos('TransientSubstrateSphereMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleSubstrateMaterial;
    AssertSameValue(2.40, Restored.TopCoatIor, 0.001);
    AssertSameValue(520.0, Restored.ThinFilmNanometers, 0.01);
    AssertTrue(Restored.EnergyConservedAcrossAngles);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSubstrateStudio);
end.
