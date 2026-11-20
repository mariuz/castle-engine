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

{ Automated tests for Phase 399: Procedural Zipline, Pulley Trolley Gravity
  Acceleration, Hand-Brake & Momentum Vault Studio. }
unit TestToolZiplineRig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolZiplineRig = class(TCastleTestCase)
  published
    procedure TestDownhillGravityAccelerationHandBrakeAndEndArrestorStop;
    procedure TestMomentumConservingMidSpanVaultLaunchAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleZiplineRig, ToolZiplineRig;

procedure TTestToolZiplineRig.TestDownhillGravityAccelerationHandBrakeAndEndArrestorStop;
var
  Root: TComponent;
  VP: TCastleViewport;
  Zipline: TCastleZiplineRig;
  StFast, StBraked, StEnd: TZiplineRiderState;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TZiplineRigHelper.SpawnCanyonZiplineTowersDemo(Root, Root, Zipline));

    { 1. Unbraked glide for 1.6s accelerates pulley past 5.0 m/s with live rider sag }
    StFast := Zipline.StepZiplineRide(1.6, 0.0);
    AssertTrue('Gravity accelerates rider downhill > 5.0 m/s', StFast.SpeedMps > 5.0);
    AssertTrue('Rider weight induces live cable depression > 0.05m',
      StFast.LiveRiderSagMeters > 0.05);

    { 2. Full hand-brake (1.0) over 0.6s decelerates the rider cleanly }
    StBraked := Zipline.StepZiplineRide(0.6, 1.0);
    AssertTrue('Hand-brake reduces trolley speed', StBraked.SpeedMps < StFast.SpeedMps - 2.0);

    { 3. Continuing to end of span engages the arrestor spring and halts safely }
    StEnd := Zipline.StepZiplineRide(12.0, 0.0);
    AssertTrue('End-of-line arrestor collar stops pulley safely before tower',
      StEnd.ReachedArrestorStop);
    AssertSameValue(0.0, StEnd.SpeedMps, 0.01);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolZiplineRig.TestMomentumConservingMidSpanVaultLaunchAndJsonRoundtrip;
var
  Zipline, Restored: TCastleZiplineRig;
  StMid: TZiplineRiderState;
  LaunchPos, LaunchVel: TVector3;
  SerializedScene, JsonCfg, Md: String;
begin
  Zipline := TCastleZiplineRig.Create(nil);
  Restored := TCastleZiplineRig.Create(nil);
  try
    Zipline.ApplyPreset(zrpUrbanTacticalRappelLine);
    Zipline.AttachRiderAtProgress(0.10, 2.0);
    StMid := Zipline.StepZiplineRide(1.0, 0.0);
    AssertTrue(StMid.SpeedMps > 4.0);

    { Vaulting off mid-span preserves forward -Z momentum AND adds upward hop }
    AssertTrue(Zipline.DisembarkVaultLaunch(LaunchPos, LaunchVel));
    AssertFalse(Zipline.LastState.IsRiding);
    AssertTrue('Vault preserves strong forward -Z velocity', LaunchVel.Z < -3.5);
    AssertTrue('Vault imparts upward hop above horizontal', LaunchVel.Y > 0.5);

    Zipline.AttachRiderAtProgress(0.25, 3.0);
    SerializedScene := ComponentToString(Zipline);
    AssertTrue(Pos('ZiplineRigPreview', SerializedScene) = 0);

    Zipline.RiderMassKg := 96.5;
    JsonCfg := TZiplineRigHelper.ExportZiplineJson(Zipline);
    AssertTrue(TZiplineRigHelper.ImportZiplineJson(Restored, JsonCfg));
    AssertEquals(Ord(zrpUrbanTacticalRappelLine), Ord(Restored.Preset));
    AssertSameValue(96.5, Restored.RiderMassKg, 0.01);
    Md := TZiplineRigHelper.GenerateMarkdownReport(Zipline);
    AssertTrue(Pos('UrbanTacticalRappelLine', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Zipline);
  end;
end;

initialization
  RegisterTest(TTestToolZiplineRig);

end.
