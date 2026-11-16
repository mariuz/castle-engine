{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated unit tests for Phase 324 Volumetric Exponential Height Fog,
  Henyey-Greenstein Anisotropic God-Rays & Priority-Blended Box-Parallax
  Reflection Probe Studio (@link(TCastleVolumetricAtmosphere),
  @link(TCastleReflectionProbe), @link(TVolumetricStudioHelper)). }
unit TestToolVolumetricStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolVolumetricStudio = class(TCastleTestCase)
  published
    procedure TestExponentialHeightFogClosedFormIntegralAndHenyeyGreensteinForwardLobe;
    procedure TestBoxParallaxReflectionVectorWallPinningAndPriorityProbeBlending;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleViewport, CastleComponentSerialize,
  CastleVolumetrics, ToolVolumetricStudio;

procedure TTestToolVolumetricStudio.TestExponentialHeightFogClosedFormIntegralAndHenyeyGreensteinForwardLobe;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Atm, LoadedAtm: TCastleVolumetricAtmosphere;
  OuterP, InnerP: TCastleReflectionProbe;
  TauValley, TauPeak, TauDown, TauUp, TValley, TPeak, TDown, TUp: Single;
  PForward, PBackward: Single;
  AerialTowardSun, AerialAwaySun: TCastleColor;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TVolumetricStudioHelper.SpawnVolumetricValleyAndProbesDemo(
      Vp, OwnerComp, Atm, OuterP, InnerP);

    { 1. Valley horizontal ray (Y=0) has much denser fog (lower transmittance) than peak (Y=35m) }
    Atm.ApplyPreset(vpMorningValleyMist);
    TValley := Atm.EvaluateSegmentTransmittance(Vector3(0, 0, 0), Vector3(0, 0, -50), TauValley);
    TPeak := Atm.EvaluateSegmentTransmittance(Vector3(0, 35, 0), Vector3(0, 35, -50), TauPeak);
    AssertTrue(TValley < 0.20);
    AssertTrue(TPeak > 0.90);
    AssertTrue(TauValley > TauPeak * 20.0);

    { 2. Exact reciprocity / symmetry along inclined ray A(0, 30, 0) <-> B(0, 0, -40) }
    TDown := Atm.EvaluateSegmentTransmittance(Vector3(0, 30, 0), Vector3(0, 0, -40), TauDown);
    TUp := Atm.EvaluateSegmentTransmittance(Vector3(0, 0, -40), Vector3(0, 30, 0), TauUp);
    AssertSameValue(TauDown, TauUp, 1e-5);
    AssertSameValue(TDown, TUp, 1e-5);

    { 3. Henyey-Greenstein strong forward scattering lobe (g = 0.76) }
    PForward := EvaluateHenyeyGreensteinPhase(1.0, 0.76);
    PBackward := EvaluateHenyeyGreensteinPhase(-1.0, 0.76);
    AssertTrue(PForward > PBackward * 40.0);

    Atm.ApplyPreset(vpGoldenHourGodRays);
    Atm.SunDirectionW := Vector3(0.0, 0.0, 1.0); // Sun shines from -Z toward +Z -> looking along -Z looks INTO sun
    AerialTowardSun := Atm.EvaluateAerialPerspective(TVector3.Zero, Vector3(0.0, 0.0, -40.0));
    AerialAwaySun := Atm.EvaluateAerialPerspective(TVector3.Zero, Vector3(0.0, 0.0, 40.0));
    AssertTrue(AerialTowardSun.X > AerialAwaySun.X); // Warm golden sun in-scatter boosts Red channel!

    JsonStr := ComponentToString(Atm);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleVolumetricAtmosphere);
    LoadedAtm := TCastleVolumetricAtmosphere(LoadedComp);
    AssertEquals(Ord(vpGoldenHourGodRays), Ord(LoadedAtm.Preset));
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolVolumetricStudio.TestBoxParallaxReflectionVectorWallPinningAndPriorityProbeBlending;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Atm: TCastleVolumetricAtmosphere;
  OuterP, InnerP, DomProbe: TCastleReflectionProbe;
  ParallaxDir, ExpectedDir: TVector3;
  BlendCol: TCastleColorRGB;
  TotalW: Single;
  Rep: TVolumetricAuditReport;
begin
  { 1. Box-Parallax reflection vector pinning inside a [-5..+5]^3 finite room }
  { Shading at (3, 0, 0) reflecting straight up (0, 1, 0) hits ceiling at (3, 5, 0) ->
    lookup from probe origin (0, 0, 0) points along Normalize((3, 5, 0))! }
  ParallaxDir := ComputeBoxParallaxReflectionDir(
    Vector3(3.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
    TVector3.Zero, Vector3(-5.0, -5.0, -5.0), Vector3(5.0, 5.0, 5.0));
  ExpectedDir := Vector3(3.0, 5.0, 0.0).Normalize;
  AssertVectorEquals(ExpectedDir, ParallaxDir, 1e-4);

  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TVolumetricStudioHelper.SpawnVolumetricValleyAndProbesDemo(
      Vp, OwnerComp, Atm, OuterP, InnerP);

    { 2. At origin (inside InnerP core box, Priority 25 > OuterP Priority 5):
      InnerP completely wins 100% weight with warm torch tint (1.00, 0.72, 0.42)! }
    TotalW := TVolumetricStudioHelper.BlendReflectionProbesAtPoint(
      Vp, OwnerComp, TVector3.Zero, DomProbe, BlendCol);
    AssertSameValue(1.0, TotalW, 1e-4);
    AssertTrue(DomProbe = InnerP);
    AssertVectorEquals(InnerP.IrradianceTint, BlendCol, 1e-4);

    { 3. At X = 12.0m (outside InnerP 4.5 + 2.0m blend, inside OuterP 18.0m box):
      OuterP cleanly takes over 100% with cool sky tint (0.72, 0.84, 1.00)! }
    TotalW := TVolumetricStudioHelper.BlendReflectionProbesAtPoint(
      Vp, OwnerComp, Vector3(12.0, 0.0, 0.0), DomProbe, BlendCol);
    AssertSameValue(1.0, TotalW, 1e-4);
    AssertTrue(DomProbe = OuterP);
    AssertVectorEquals(OuterP.IrradianceTint, BlendCol, 1e-4);

    Rep := TVolumetricStudioHelper.AuditVolumetrics(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.AtmosphereCount);
      AssertEquals(2, Rep.ProbeCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolVolumetricStudio);
end.
