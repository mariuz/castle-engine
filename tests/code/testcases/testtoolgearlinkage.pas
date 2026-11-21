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

{ Automated tests for Phase 415: Mechanical Gear Train, Rack-and-Pinion,
  Belt Pulley & Odd-Cycle Jam Detection Studio. }
unit TestToolGearLinkage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolGearLinkage = class(TCastleTestCase)
  published
    procedure TestCompoundGearReductionTorqueMultiplicationBeltSignAndPortcullisRack;
    procedure TestOdd3GearTriangleJamVsEven4GearLoopFreeSpinAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleGearLinkage, ToolGearLinkage;

procedure TTestToolGearLinkage.TestCompoundGearReductionTorqueMultiplicationBeltSignAndPortcullisRack;
var
  Root: TComponent;
  VP: TCastleViewport;
  Gear: TCastleGearLinkage;
  ExpectedRackSpeed: Single;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TGearLinkageHelper.SpawnPortcullisGearboxDemo(Root, Root, Gear));

    { 1. Compound 12:1 reduction:
         Node 0 (12T) = +120 RPM, 10 Nm
         -> Node 1 (36T spur) = -40 RPM, 30 * 0.95 = 28.5 Nm
         -> Node 2 (12T coaxial) = -40 RPM, 28.5 Nm
         -> Node 3 (48T spur drum, R=1.0m) = +10 RPM, 28.5 * 4 * 0.95 = 108.3 Nm! }
    AssertFalse(Gear.IsJammedLoop);
    AssertSameValue(-40.0, Gear.GetNode(1).SolvedRpm, 0.01);
    AssertSameValue(-40.0, Gear.GetNode(2).SolvedRpm, 0.01);
    AssertSameValue(10.0, Gear.GetNode(3).SolvedRpm, 0.01);
    AssertSameValue(108.3, Gear.GetNode(3).SolvedTorqueNm, 0.05);

    { 2. Rack-and-pinion linear gate lift: omega = 10 * 2*pi / 60 = pi/3 rad/s
         * R=1.0m -> +1.0472 m/s! Stepping 2.0s lifts gate by +2.0944 m! }
    ExpectedRackSpeed := (10.0 * 2.0 * Pi / 60.0) * 1.0;
    AssertSameValue(ExpectedRackSpeed, Gear.GetNode(4).SolvedRpm, 0.005);
    Gear.StepClockwork(2.0);
    AssertSameValue(ExpectedRackSpeed * 2.0, Gear.GetNode(4).LinearPositionMeters, 0.01);

    { 3. Uncrossed belt pulley preserves spin sign (+180 RPM * 40T / 20T = +360 RPM!) }
    Gear.ApplyPreset(glpBeltDrivenSawmillPulley);
    AssertSameValue(360.0, Gear.GetNode(1).SolvedRpm, 0.05);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolGearLinkage.TestOdd3GearTriangleJamVsEven4GearLoopFreeSpinAndJsonRoundtrip;
var
  Gear, Restored: TCastleGearLinkage;
  SerializedScene, JsonCfg, Md: String;
begin
  Gear := TCastleGearLinkage.Create(nil);
  Restored := TCastleGearLinkage.Create(nil);
  try
    { 1. 3 mutually meshing 20T spur gears in a closed odd triangle MUST JAM! }
    Gear.ClearMechanism;
    Gear.AddGearWheel('G0', Vector3(-0.5, 0.0, 0.0), 20, 0.4);
    Gear.AddGearWheel('G1', Vector3(0.5, 0.0, 0.0), 20, 0.4);
    Gear.AddGearWheel('G2', Vector3(0.0, 0.8, 0.0), 20, 0.4);
    Gear.AddCouplingLink(0, 1, glkExternalSpurMesh);
    Gear.AddCouplingLink(1, 2, glkExternalSpurMesh);
    Gear.AddCouplingLink(2, 0, glkExternalSpurMesh);
    AssertFalse('3-gear triangular spur mesh must detect kinematic jam',
      Gear.SolveGearTrainKinematics);
    AssertTrue(Gear.IsJammedLoop);
    AssertSameValue(0.0, Gear.GetNode(0).SolvedRpm, 0.001);
    Gear.StepClockwork(1.0);
    AssertSameValue(0.0, Gear.GetNode(0).AngleRad, 0.0001);

    { 2. 4-gear even square spur loop (+120 -> -120 -> +120 -> -120 -> +120) spins freely! }
    Gear.ClearMechanism;
    Gear.AddGearWheel('Q0', Vector3(0, 0, 0), 20, 0.4);
    Gear.AddGearWheel('Q1', Vector3(1, 0, 0), 20, 0.4);
    Gear.AddGearWheel('Q2', Vector3(1, 1, 0), 20, 0.4);
    Gear.AddGearWheel('Q3', Vector3(0, 1, 0), 20, 0.4);
    Gear.AddCouplingLink(0, 1, glkExternalSpurMesh);
    Gear.AddCouplingLink(1, 2, glkExternalSpurMesh);
    Gear.AddCouplingLink(2, 3, glkExternalSpurMesh);
    Gear.AddCouplingLink(3, 0, glkExternalSpurMesh);
    AssertTrue('4-gear even square spur loop is kinematically consistent',
      Gear.SolveGearTrainKinematics);
    AssertFalse(Gear.IsJammedLoop);
    AssertSameValue(-120.0, Gear.GetNode(3).SolvedRpm, 0.01);

    SerializedScene := ComponentToString(Gear);
    AssertTrue(Pos('GearLinkagePreview', SerializedScene) = 0);

    Gear.ApplyPreset(glpCathedralClocktowerEscapement);
    Gear.MotorInputRpm := 90.0;
    JsonCfg := TGearLinkageHelper.ExportLinkageJson(Gear);
    AssertTrue(TGearLinkageHelper.ImportLinkageJson(Restored, JsonCfg));
    AssertSameValue(90.0, Restored.MotorInputRpm, 0.05);
    AssertSameValue(-15.0, Restored.GetNode(1).SolvedRpm, 0.05);
    Md := TGearLinkageHelper.GenerateMarkdownReport(Gear);
    AssertTrue(Pos('CathedralClocktowerEscapement', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Gear);
  end;
end;

initialization
  RegisterTest(TTestToolGearLinkage);

end.
