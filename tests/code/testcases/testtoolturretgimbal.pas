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

{ Automated tests for Phase 413: Dual-Axis Gimbal Turret, Slew-Rate Servo,
  Critically-Damped Barrel Recoil & Thermal Overheat Vent Studio. }
unit TestToolTurretGimbal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolTurretGimbal = class(TCastleTestCase)
  published
    procedure TestShortestArc360SlewCasemateClampAndWorldRayFriendlySuperstructureInhibit;
    procedure TestThermalOverheatVentLockoutCriticallyDampedRecoilAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleTurretGimbal, ToolTurretGimbal;

procedure TTestToolTurretGimbal.TestShortestArc360SlewCasemateClampAndWorldRayFriendlySuperstructureInhibit;
var
  Root: TComponent;
  VP: TCastleViewport;
  Turret: TCastleTurretGimbal;
  SWrapped, SAftBlocked, SCasemate: TTurretGimbalState;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TTurretGimbalHelper.SpawnBattleshipDeckTurretDemo(Root, Root, Turret));

    { 1. Shortest-arc +/-180 deg wraparound: start at Yaw = +170 deg aiming aft-starboard,
         target at aft-port (-170 deg, i.e. (-Sin10, 0, +Cos10) * 20): a 1.0s step at
         30 deg/s slews +20 deg across +/-180 directly onto -170 deg (NOT 340 deg)! }
    Turret.ResetGimbalAngles(170.0, 0.0);
    SWrapped := Turret.StepServoTracking(VP.Items,
      Vector3(-Sin(DegToRad(10.0)) * 20.0, 1.8, Cos(DegToRad(10.0)) * 20.0), 1.0);
    AssertSameValue(-170.0, SWrapped.CurrentYawDeg, 0.2);

    { 2. Aiming directly aft (Yaw = 180 deg, +Z) through FriendlyShipSuperstructureBridge
         at Z = +5.0m toward target at Z = +20.0m triggers FriendlyHullBlocked = True
         and inhibits FireCannonRound! }
    Turret.ResetGimbalAngles(180.0, 0.0);
    SAftBlocked := Turret.StepServoTracking(VP.Items, Vector3(0.0, 2.0, 20.0), 0.05);
    AssertTrue('WorldRay detects FriendlyShipSuperstructureBridge in line of fire',
      SAftBlocked.FriendlyHullBlocked);
    AssertFalse('Turret refuses to fire into friendly ship bridge',
      Turret.FireCannonRound);

    { 3. Casemate preset clamps yaw strictly within [-45 .. +45 deg] }
    Turret.ApplyPreset(tgpSponsonCasemateLimitedArc);
    Turret.ResetGimbalAngles(0.0, 0.0);
    SCasemate := Turret.StepServoTracking(nil, Vector3(20.0, 1.8, 0.0), 3.0);
    AssertSameValue(45.0, SCasemate.CurrentYawDeg, 0.05);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolTurretGimbal.TestThermalOverheatVentLockoutCriticallyDampedRecoilAndJsonRoundtrip;
var
  Turret, Restored: TCastleTurretGimbal;
  SCoolMid, SCooled: TTurretGimbalState;
  SerializedScene, JsonCfg, Md: String;
begin
  Turret := TCastleTurretGimbal.Create(nil);
  Restored := TCastleTurretGimbal.Create(nil);
  try
    Turret.ApplyPreset(tgpHeavyBattleshipMainBattery);
    { HeatPerShot01 = 0.35 -> 3 rapid salvos reach 1.00 and trip IsOverheatedVenting! }
    AssertTrue(Turret.FireCannonRound);
    AssertTrue(Turret.FireCannonRound);
    AssertTrue(Turret.FireCannonRound);
    AssertTrue(Turret.State.IsOverheatedVenting);
    AssertSameValue(0.65, Turret.State.RecoilOffsetMeters, 0.01);

    { Locked out while venting; partial cooling to ~0.56 (> 0.25 VentResetHeat01) stays locked }
    AssertFalse(Turret.FireCannonRound);
    SCoolMid := Turret.StepServoTracking(nil, Vector3(0.0, 0.0, -20.0), 2.0);
    AssertTrue(SCoolMid.IsOverheatedVenting);
    AssertTrue('Critically-damped recoil settles smoothly back to battery rest',
      SCoolMid.RecoilOffsetMeters < 0.01);

    { Full cooling below 0.25 clears steam-vent lockout and allows firing again! }
    SCooled := Turret.StepServoTracking(nil, Vector3(0.0, 0.0, -20.0), 2.5);
    AssertFalse(SCooled.IsOverheatedVenting);
    AssertTrue(Turret.FireCannonRound);

    SerializedScene := ComponentToString(Turret);
    AssertTrue(Pos('TurretGimbalPreview', SerializedScene) = 0);

    Turret.YawSlewDegPerSec := 72.5;
    JsonCfg := TTurretGimbalHelper.ExportTurretJson(Turret);
    AssertTrue(TTurretGimbalHelper.ImportTurretJson(Restored, JsonCfg));
    AssertSameValue(72.5, Restored.YawSlewDegPerSec, 0.05);
    Md := TTurretGimbalHelper.GenerateMarkdownReport(Turret);
    AssertTrue(Pos('HeavyBattleshipMainBattery', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Turret);
  end;
end;

initialization
  RegisterTest(TTestToolTurretGimbal);

end.
