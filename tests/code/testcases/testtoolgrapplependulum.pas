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

{ Automated tests for Phase 403: Grappling Hook & Vine 3D Spherical Pendulum
  Swing, Motorized Winch Reel-In & Apex Release Studio. }
unit TestToolGrapplePendulum;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolGrapplePendulum = class(TCastleTestCase)
  published
    procedure TestWorldRayHookLockSphericalPendulumArcAndSlackFreefall;
    procedure TestMotorizedWinchReelInApexJumpBoostAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleGrapplePendulum, ToolGrapplePendulum;

procedure TTestToolGrapplePendulum.TestWorldRayHookLockSphericalPendulumArcAndSlackFreefall;
var
  Root: TComponent;
  VP: TCastleViewport;
  Rig: TCastleGrapplePendulum;
  S0, SBottom, SSlack: TGrappleSwingState;
  ExpectedSpeed: Single;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TGrapplePendulumHelper.SpawnGargoyleChasmSwingDemo(Root, Root, Rig));

    { 1. WorldRay hit the underside of ChasmOverheadGargoyleBeam (Y = 14.0)! }
    S0 := Rig.State;
    AssertTrue(S0.HookAttached);
    AssertSameValue(14.0, S0.AnchorWorldPos.Y, 0.05);
    AssertTrue('Rope length locked around 10m', S0.RopeLengthMeters > 9.5);

    { 2. Pure frictionless pendulum conservation check: attach at (-8, 10, 0) under
         (0, 10, 0) with L = 8.0m and AirDrag = 0 -> large-angle 90-deg elliptic
         quarter-period T/4 = 1.1803 * (pi/2)*sqrt(8/9.81) = 1.675s swings right
         through bottom X ~ 0 at Y ~ 2.0m with v = sqrt(2 * g * dY) and ||P - A|| = 8.00m! }
    Rig.AirDragPerSec := 0.0;
    Rig.AttachHookDirect(Vector3(0.0, 10.0, 0.0), Vector3(-8.0, 10.0, 0.0),
      TVector3.Zero, 8.0);
    SBottom := Rig.StepPendulumSwing(1.68, False);
    AssertTrue(SBottom.RopeIsTaut);
    AssertSameValue(8.0, PointsDistance(SBottom.AnchorWorldPos, SBottom.PlayerWorldPos), 0.01);
    AssertTrue('Pendulum swings forward across chasm (+X velocity / progress)',
      SBottom.PlayerWorldPos.X > -2.0);
    ExpectedSpeed := Sqrt(2.0 * 9.81 * (10.0 - SBottom.PlayerWorldPos.Y));
    AssertSameValue(ExpectedSpeed, SBottom.VelocityMps.Length, 0.35);
    AssertTrue('Centripetal + weight tension at bottom of swing exceeds 2x weight',
      SBottom.CableTensionNewtons > Rig.RiderMassKg * 9.81 * 1.5);

    { 3. Unilateral slack rope check: start inside sphere at (0, 8, 0) with L = 10.0m ->
         rope is SLACK (Tension = 0) while ||P - A|| < 10m! }
    Rig.AttachHookDirect(Vector3(0.0, 10.0, 0.0), Vector3(0.0, 8.0, 0.0),
      Vector3(2.0, 1.0, 0.0), 10.0);
    SSlack := Rig.StepPendulumSwing(0.15, False);
    AssertFalse('Rope inside 10m sphere remains slack without compressive push',
      SSlack.RopeIsTaut);
    AssertSameValue(0.0, SSlack.CableTensionNewtons, 0.001);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolGrapplePendulum.TestMotorizedWinchReelInApexJumpBoostAndJsonRoundtrip;
var
  Rig, Restored: TCastleGrapplePendulum;
  SAfterWinch: TGrappleSwingState;
  LaunchVel: TVector3;
  SerializedScene, JsonCfg, Md: String;
begin
  Rig := TCastleGrapplePendulum.Create(nil);
  Restored := TCastleGrapplePendulum.Create(nil);
  try
    Rig.ApplyPreset(gppBatmanMotorizedGrapnel);
    Rig.AttachHookDirect(Vector3(0.0, 20.0, 0.0), Vector3(-6.0, 8.0, 0.0),
      Vector3(4.0, 0.0, 0.0), 13.42);

    { Motorized grapnel winch reels rope shorter and lifts player Y upward! }
    SAfterWinch := Rig.StepPendulumSwing(0.60, True);
    AssertTrue('Motorized grapnel shortens RopeLengthMeters by > 6m',
      SAfterWinch.RopeLengthMeters < 7.0);
    AssertTrue('Winch pulls rider upward above starting Y = 8.0m',
      SAfterWinch.PlayerWorldPos.Y > 12.5);

    { Apex jump release detaches hook and adds upward + forward velocity boost }
    LaunchVel := Rig.ReleaseApexJump;
    AssertFalse(Rig.State.HookAttached);
    AssertTrue('Apex release imparts strong upward velocity', LaunchVel.Y > 4.0);

    SerializedScene := ComponentToString(Rig);
    AssertTrue(Pos('GrapplePendulumPreview', SerializedScene) = 0);

    Rig.ApexJumpUpSpeedMps := 8.25;
    JsonCfg := TGrapplePendulumHelper.ExportRigJson(Rig);
    AssertTrue(TGrapplePendulumHelper.ImportRigJson(Restored, JsonCfg));
    AssertEquals(Ord(gppBatmanMotorizedGrapnel), Ord(Restored.Preset));
    AssertSameValue(8.25, Restored.ApexJumpUpSpeedMps, 0.01);
    Md := TGrapplePendulumHelper.GenerateMarkdownReport(Rig);
    AssertTrue(Pos('BatmanMotorizedGrapnel', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Rig);
  end;
end;

initialization
  RegisterTest(TTestToolGrapplePendulum);

end.
