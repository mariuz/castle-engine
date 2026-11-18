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

{ Automated tests for Phase 371 Cinematic Camera Shake, Recoil & FOV Kickback Studio. }
unit TestToolCameraShake;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolCameraShake = class(TCastleTestCase)
  published
    procedure TestWorldExplosionDistanceFalloffDirectionalWeaponRecoilAndDecayToRest;
    procedure TestAccessibilityZeroScaleMotionSicknessGateMultiBlastCapAndJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleCameraShake, ToolCameraShake;

procedure TTestToolCameraShake.TestWorldExplosionDistanceFalloffDirectionalWeaponRecoilAndDecayToRest;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Director: TCastleCameraShakeDirector;
  FarT, MidT, CloseT: Single;
  KickFrame, RestFrame: TCameraShakeFrameOffset;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TCameraShakeHelper.SpawnFiringRangeShakeDemo(Vp, RootOwner, Director));

    { 1. Explosion beyond OuterZeroBlastRadiusMeters (40m > 28m) produces 0 trauma & 0 active layers }
    FarT := Director.TriggerWorldExplosionShake(Vector3(0, 0, -40.0), TVector3.Zero, 1.0);
    AssertSameValue(0.0, FarT, 0.0001);
    AssertEquals(0, Director.ActiveLayerCount);

    { 2. Mid-range (16m) vs. point-blank (2m <= 4m InnerFull): smoothstep midpoint = 0.50 vs. 1.00 }
    MidT := Director.TriggerWorldExplosionShake(Vector3(0, 0, -16.0), TVector3.Zero, 1.0);
    CloseT := Director.TriggerWorldExplosionShake(Vector3(0, 0, -2.0), TVector3.Zero, 1.0);
    AssertSameValue(0.50, MidT, 0.01);
    AssertSameValue(1.00, CloseT, 0.001);

    { 3. Directional weapon recoil (+6 deg upward pitch, +4.5 deg FOV kick) & full decay back to zero }
    Director.ClearAllShakes;
    Director.TriggerDirectionalRecoil(6.0, -1.5, 4.5, 0.40);
    KickFrame := Director.StepCameraShakes(0.02);
    AssertTrue('Shotgun recoil must kick camera pitch upward (> +3.5 deg)',
      KickFrame.PitchYawRollDeg.X > 3.5);
    AssertTrue('Shotgun recoil must punch FOV wider (> +3.0 deg)',
      KickFrame.FovDeltaDegrees > 3.0);

    RestFrame := Director.StepCameraShakes(0.50);
    AssertEquals(0, RestFrame.ActiveLayerCount);
    AssertVectorEquals(TVector3.Zero, RestFrame.PitchYawRollDeg, 0.0001);
    AssertSameValue(0.0, RestFrame.FovDeltaDegrees, 0.0001);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolCameraShake.TestAccessibilityZeroScaleMotionSicknessGateMultiBlastCapAndJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Director, Restored: TCastleCameraShakeDirector;
  CappedFrame, SafeFrame: TCameraShakeFrameOffset;
  I: Integer;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Director := TCastleCameraShakeDirector.Create(RootOwner);
    Director.Name := 'CinemaShakeDir';
    Director.Preset := cspArtilleryConcussionBlast;
    Director.MaxPitchRollCapDeg := 10.0;

    { 1. Stack 8 simultaneous point-blank blasts -> angular offset never exceeds MaxPitchRollCapDeg (10 deg)! }
    for I := 1 to 8 do
      Director.TriggerWorldExplosionShake(Vector3(0, 0, -1.0), TVector3.Zero, 1.0);
    CappedFrame := Director.StepCameraShakes(0.05);
    AssertTrue(Abs(CappedFrame.PitchYawRollDeg.X) <= 10.001);
    AssertTrue(Abs(CappedFrame.PitchYawRollDeg.Y) <= 10.001);
    AssertTrue(Abs(CappedFrame.PitchYawRollDeg.Z) <= 10.001);

    { 2. Accessibility GlobalShakeScale = 0.0 zeroes all positional, angular, and FOV motion immediately }
    Director.GlobalShakeScale := 0.0;
    SafeFrame := Director.StepCameraShakes(0.02);
    AssertVectorEquals(TVector3.Zero, SafeFrame.PositionOffsetLocal, 0.0001);
    AssertVectorEquals(TVector3.Zero, SafeFrame.PitchYawRollDeg, 0.0001);
    AssertSameValue(0.0, SafeFrame.FovDeltaDegrees, 0.0001);

    ReportMd := TCameraShakeHelper.GenerateShakeReport(Director);
    AssertTrue(Pos('GlobalShakeScale = 0%', ReportMd) > 0);

    Director.GlobalShakeScale := 0.75;
    JsonStr := ComponentToString(Director);
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleCameraShakeDirector;
    AssertSameValue(0.75, Restored.GlobalShakeScale, 0.001);
    AssertSameValue(10.0, Restored.MaxPitchRollCapDeg, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolCameraShake);
end.
