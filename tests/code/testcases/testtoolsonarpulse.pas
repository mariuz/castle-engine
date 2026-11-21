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

{ Automated tests for Phase 414: 3D Echolocation & Active Sonar Pulse
  (WorldRay Spherical Ping Wavefront, Two-Way Echo & Doppler Shift) Studio. }
unit TestToolSonarPulse;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSonarPulse = class(TCastleTestCase)
  published
    procedure TestTwoWayRoundtripEchoArrivalGatingReflectivityAndPhosphorDecay;
    procedure TestMonostaticDopplerUpDownShiftWorldRayOcclusionAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleSonarPulse, ToolSonarPulse;

procedure TTestToolSonarPulse.TestTwoWayRoundtripEchoArrivalGatingReflectivityAndPhosphorDecay;
var
  Root: TComponent;
  VP: TCastleViewport;
  Sonar: TCastleSonarPulse;
  I: Integer;
  C: TSonarEchoContact;
  NearBright, FarStealthBright: Single;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSonarPulseHelper.SpawnTrenchSubmarineSonarDemo(Root, Root, Sonar));

    { At t = 0.0s right after EmitSonarPing: wavefront hasn't returned yet -> 0 revealed! }
    AssertTrue(Sonar.ContactCount >= 2);
    AssertEquals(0, Sonar.RevealedContactCount);

    { 1. At t = 0.75s (c = 40 m/s): SteelWreckHull_Near at 12.0m (2*12/40 = 0.60s)
         HAS arrived, while StealthAnechoicSub_Far at 32.0m (2*32/40 = 1.60s) has NOT! }
    Sonar.StepPulsePropagation(0.75);
    NearBright := 0.0;
    for I := 0 to Sonar.ContactCount - 1 do
    begin
      C := Sonar.GetContact(I);
      if C.TargetName = 'SteelWreckHull_Near' then
      begin
        AssertTrue(C.EchoArrived);
        NearBright := Max(NearBright, C.PhosphorBrightness01);
      end else
      if C.TargetName = 'StealthAnechoicSub_Far' then
        AssertFalse('32m contact remains hidden before two-way 1.60s return', C.EchoArrived);
    end;
    AssertTrue('Steel hull produces bright > 0.65 phosphor blip', NearBright > 0.65);

    { 2. Step another +0.95s (t = 1.70s > 1.60s): far anechoic sub arrives with faint
         stealth return (< 0.10), and after +5.0s phosphor fades completely to 0! }
    Sonar.StepPulsePropagation(0.95);
    FarStealthBright := 0.0;
    for I := 0 to Sonar.ContactCount - 1 do
    begin
      C := Sonar.GetContact(I);
      if C.TargetName = 'StealthAnechoicSub_Far' then
      begin
        AssertTrue(C.EchoArrived);
        FarStealthBright := Max(FarStealthBright, C.PhosphorBrightness01);
      end;
    end;
    AssertTrue((FarStealthBright > 0.01) and (FarStealthBright < 0.10));

    Sonar.StepPulsePropagation(5.0);
    AssertEquals(0, Sonar.RevealedContactCount);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolSonarPulse.TestMonostaticDopplerUpDownShiftWorldRayOcclusionAndJsonRoundtrip;
var
  DfApproach, DfRecede, DfStatic: Single;
  Root: TComponent;
  VP: TCastleViewport;
  Sonar, Restored: TCastleSonarPulse;
  SeamountWall: TCastleBox;
  SerializedScene, JsonCfg, Md: String;
begin
  { 1. Exact two-way active Doppler in 1500 m/s seawater at 3500 Hz:
       +30 m/s closing torpedo shifts +142.86 Hz; receding shifts negative; static = 0! }
  DfApproach := TCastleSonarPulse.ComputeTwoWayDopplerShiftHz(
    3500.0, 1500.0, TVector3.Zero, Vector3(0.0, 0.0, -200.0), Vector3(0.0, 0.0, 30.0));
  DfRecede := TCastleSonarPulse.ComputeTwoWayDopplerShiftHz(
    3500.0, 1500.0, TVector3.Zero, Vector3(0.0, 0.0, -200.0), Vector3(0.0, 0.0, -30.0));
  DfStatic := TCastleSonarPulse.ComputeTwoWayDopplerShiftHz(
    3500.0, 1500.0, TVector3.Zero, Vector3(0.0, 0.0, -200.0), TVector3.Zero);

  AssertSameValue(3500.0 * ((1530.0 / 1470.0) - 1.0), DfApproach, 0.05);
  AssertTrue(DfRecede < -130.0);
  AssertSameValue(0.0, DfStatic, 0.0001);

  { 2. WorldRay seamount acoustic shadow blocks hidden contact behind rock ridge }
  Root := TComponent.Create(nil);
  Restored := TCastleSonarPulse.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    SeamountWall := TCastleBox.Create(Root);
    SeamountWall.Name := 'BasaltSeamountRidge';
    SeamountWall.Size := Vector3(12.0, 12.0, 2.0);
    SeamountWall.Translation := Vector3(0.0, 0.0, -20.0);
    VP.Items.Add(SeamountWall);

    Sonar := TCastleSonarPulse.Create(Root);
    Sonar.ApplyPreset(sppSubmarineHydrophone1500);
    VP.Items.Add(Sonar);
    Sonar.EmitSonarPing(VP.Items);

    AssertFalse('Target shadowed behind BasaltSeamountRidge is rejected by WorldRay',
      Sonar.ProbeDynamicContact(VP.Items, 'ShadowedSub',
        Vector3(0.0, 0.0, -50.0), TVector3.Zero, 0.95));
    AssertTrue('Unobstructed contact in open water registers cleanly',
      Sonar.ProbeDynamicContact(VP.Items, 'OpenWaterTorpedo',
        Vector3(40.0, 0.0, 0.0), Vector3(-25.0, 0.0, 0.0), 0.95));

    SerializedScene := ComponentToString(Sonar);
    AssertTrue(Pos('SonarPulsePreview', SerializedScene) = 0);

    Sonar.CarrierFrequencyHz := 4200.0;
    JsonCfg := TSonarPulseHelper.ExportSonarJson(Sonar);
    AssertTrue(TSonarPulseHelper.ImportSonarJson(Restored, JsonCfg));
    AssertSameValue(4200.0, Restored.CarrierFrequencyHz, 0.1);
    Md := TSonarPulseHelper.GenerateMarkdownReport(Sonar);
    AssertTrue(Pos('SubmarineHydrophone1500', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolSonarPulse);

end.
