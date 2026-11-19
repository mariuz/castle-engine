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

{ Automated tests for Phase 387: Ballistic Projectile Trajectory, Aerodynamic
  Drag, Magnus Spin Drift & WorldRay Ricochet/Penetration Studio. }
unit TestToolBallisticStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBallisticStudio = class(TCastleTestCase)
  published
    procedure TestThinCoverPenetrationGrazingRicochetAndCrosswindMagnusDrift;
    procedure TestMovingTargetInterceptLeadSolverPresetsAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene, CastleBoxes,
  CastleComponentSerialize,
  CastleBallisticSolver, ToolBallisticStudio;

procedure TTestToolBallisticStudio.TestThinCoverPenetrationGrazingRicochetAndCrosswindMagnusDrift;
var
  Root: TComponent;
  VP: TCastleViewport;
  Launcher: TCastleBallisticLauncher;
  TracePen, TraceRic, TraceCalm, TraceWind: TBallisticTraceResult;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    AssertTrue(TBallisticStudioHelper.SpawnFiringRangeDemo(Root, Root, Launcher));
    AssertTrue(Launcher <> nil);

    { 1. Direct shot from Z=0 hits ThinPlywoodBarricade (0.18m thick at Z=-10),
         punches through it (PenetrationCount = 1), and embeds into thick 2.2m
         ConcreteBackstopWall at Z=-24! }
    TracePen := TBallisticStudioHelper.FireThinCoverPenetrationTest(Launcher, Root);
    AssertEquals(1, TracePen.PenetrationCount);
    AssertEquals(Ord(bioEmbeddedStop), Ord(TracePen.FinalOutcome));
    AssertTrue('Terminal speed reduced after cover penetration',
      TracePen.TerminalSpeedMps < Launcher.MuzzleSpeedMps - 20.0);
    AssertTrue('Bullet reached concrete backstop past Z=-10m cover',
      TracePen.HorizontalRangeMeters > 20.0);

    { 2. Shallow -10 deg shot onto SteelRicochetFloor grazes and ricochets upward
         into ConcreteBackstopWall }
    TraceRic := TBallisticStudioHelper.FireGrazingRicochetTest(Launcher, Root);
    AssertTrue('Grazing steel plate triggers ricochet', TraceRic.RicochetCount >= 1);
    AssertTrue('Ricochet bounces projectile forward toward backstop',
      TraceRic.HorizontalRangeMeters > 8.0);

    { 3. Crosswind + Magnus drift in open air shifts lateral drift measurably }
    Launcher.WindVelocityMps := TVector3.Zero;
    Launcher.SpinRateRps := 0.0;
    TraceCalm := Launcher.SimulateTrajectory(nil, Vector3(0.0, 2.0, 0.0),
      Vector3(0.0, 0.15, -1.0).Normalize);
    AssertSameValue(0.0, TraceCalm.LateralWindSpinDriftMeters, 0.001);

    Launcher.WindVelocityMps := Vector3(14.0, 0.0, 0.0);
    Launcher.SpinRateRps := 2400.0;
    TraceWind := Launcher.SimulateTrajectory(nil, Vector3(0.0, 2.0, 0.0),
      Vector3(0.0, 0.15, -1.0).Normalize);
    AssertTrue('Positive +X crosswind drifts bullet toward +X',
      TraceWind.LateralWindSpinDriftMeters > 0.05);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBallisticStudio.TestMovingTargetInterceptLeadSolverPresetsAndJsonRoundtrip;
var
  Launcher, Restored: TCastleBallisticLauncher;
  LowElev, HighElev: Single;
  LeadPos: TVector3;
  JsonCfg, SerializedScene, Md: String;
begin
  Launcher := TCastleBallisticLauncher.Create(nil);
  Restored := TCastleBallisticLauncher.Create(nil);
  try
    Launcher.ApplyPreset(blpMortarHighArcHE);
    AssertSameValue(68.0, Launcher.MuzzleSpeedMps, 0.01);

    { Solve low-arc and high-arc mortar elevation against moving lateral target }
    AssertTrue(Launcher.SolveInterceptElevationDeg(
      Vector3(0.0, 0.0, 0.0),
      Vector3(0.0, 0.0, -180.0),
      Vector3(5.0, 0.0, 0.0),
      False, LowElev, LeadPos));
    AssertTrue('Low-arc elevation is < 45 deg', (LowElev > 2.0) and (LowElev < 45.0));
    AssertTrue('Moving target lead shifts X > 0', LeadPos.X > 5.0);

    AssertTrue(Launcher.SolveInterceptElevationDeg(
      Vector3(0.0, 0.0, 0.0),
      Vector3(0.0, 0.0, -180.0),
      Vector3(5.0, 0.0, 0.0),
      True, HighElev, LeadPos));
    AssertTrue('High-arc mortar plunge elevation > 45 deg', HighElev > 45.0);

    { Transient preview geometry must NOT leak into ComponentToString }
    Launcher.SimulateTrajectory(nil, Vector3(0.0, 1.5, 0.0),
      Vector3(0.0, 0.5, -0.866).Normalize);
    Launcher.RebuildPreview;
    SerializedScene := ComponentToString(Launcher);
    AssertTrue('Transient tracer preview excluded from serialized JSON',
      Pos('BallisticTracerPreview', SerializedScene) = 0);

    { JSON config roundtrip & Markdown report }
    Launcher.WindVelocityMps := Vector3(8.5, 0.0, -2.0);
    JsonCfg := TBallisticStudioHelper.ExportLauncherJson(Launcher);
    AssertTrue(TBallisticStudioHelper.ImportLauncherJson(Restored, JsonCfg));
    AssertEquals(Ord(blpMortarHighArcHE), Ord(Restored.Preset));
    AssertSameValue(8.5, Restored.WindVelocityMps.X, 0.01);

    Md := TBallisticStudioHelper.GenerateMarkdownReport(Launcher);
    AssertTrue(Pos('MortarHighArcHE', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Launcher);
  end;
end;

initialization
  RegisterTest(TTestToolBallisticStudio);

end.
