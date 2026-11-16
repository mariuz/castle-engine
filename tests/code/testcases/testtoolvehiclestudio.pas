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

{ Automated unit tests for Phase 317 Chaos-Style Wheeled Vehicle, Raycast
  Spring-Damper Suspension, Ackermann Steering, Multi-Gear Drivetrain &
  Pacejka Tire Slip Studio (@link(TCastleWheeledVehicle), @link(TVehicleStudioHelper)). }
unit TestToolVehicleStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolVehicleStudio = class(TCastleTestCase)
  published
    procedure TestAckermannGeometryTorqueCurveSuspensionEquilibriumAndRampPitch;
    procedure TestAccelerationAutoGearUpshiftAckermannTurnHandbrakeDriftAndJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize, CastleVehicleSystem, ToolVehicleStudio;

procedure TTestToolVehicleStudio.TestAckermannGeometryTorqueCurveSuspensionEquilibriumAndRampPitch;
var
  LeftDeg, RightDeg, CotOuter, CotInner: Single;
  TqIdle, TqPeak, TqRedline, TqOverRev: Single;
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  FloorBox, StepPlatform: TCastleBox;
  Car: TCastleWheeledVehicle;
  FwdW: TVector3;
  K: Integer;
begin
  { 1. Exact Ackermann steering invariant: cot(delta_outer) - cot(delta_inner) = TrackWidth / Wheelbase }
  ComputeAckermannWheelAnglesDeg(1.0, 32.0, 2.60, 1.60, LeftDeg, RightDeg);
  AssertTrue(RightDeg > LeftDeg); // Right turn -> inner right wheel steers sharper than outer left
  AssertTrue(LeftDeg > 0.0);
  CotOuter := 1.0 / Tan(DegToRad(LeftDeg));
  CotInner := 1.0 / Tan(DegToRad(RightDeg));
  AssertSameValue(1.60 / 2.60, CotOuter - CotInner, 1e-3);

  { Symmetry on left turn }
  ComputeAckermannWheelAnglesDeg(-1.0, 32.0, 2.60, 1.60, LeftDeg, RightDeg);
  AssertTrue(LeftDeg < RightDeg);
  AssertTrue(Abs(LeftDeg) > Abs(RightDeg));

  { 2. Engine torque bell curve & rev-limiter cutoff }
  TqIdle := EvaluateEngineTorqueCurveNm(950.0, 950.0, 4600.0, 7200.0, 460.0);
  TqPeak := EvaluateEngineTorqueCurveNm(4600.0, 950.0, 4600.0, 7200.0, 460.0);
  TqRedline := EvaluateEngineTorqueCurveNm(7200.0, 950.0, 4600.0, 7200.0, 460.0);
  TqOverRev := EvaluateEngineTorqueCurveNm(7700.0, 950.0, 4600.0, 7200.0, 460.0);
  AssertSameValue(460.0, TqPeak, 1e-3);
  AssertTrue((TqIdle > 280.0) and (TqIdle < TqPeak));
  AssertTrue((TqRedline > 300.0) and (TqRedline < TqPeak));
  AssertSameValue(0.0, TqOverRev, 1e-4);

  { 3. 4-Wheel WorldRay suspension equilibrium on flat floor + nose-up pitch on raised front platform }
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    FloorBox := TCastleBox.Create(OwnerComp);
    FloorBox.Size := Vector3(60.0, 1.0, 60.0);
    FloorBox.Translation := Vector3(0.0, -0.5, 0.0);
    Vp.Items.Add(FloorBox);

    Car := TVehicleStudioHelper.SpawnVehicleInDesign(Vp, OwnerComp, vpRallySportsCar, Vector3(0.0, 0.0, 0.0));
    AssertTrue(Car <> nil);

    for K := 1 to 25 do
      Car.StepVehicle(0.05);

    AssertEquals(4, Car.GroundedWheelCount);
    AssertTrue(Car.GetWheelTelemetry(0).CompressionMeters > 0.04);
    AssertTrue(Car.GetWheelTelemetry(0).CompressionMeters < Car.SuspensionRestLength);
    { Total vertical normal force across 4 wheels balances Mass * g = 1380 * 9.81 = 13537.8 N }
    AssertSameValue(Car.ChassisMassKg * 9.81,
      Car.GetWheelTelemetry(0).NormalForceN + Car.GetWheelTelemetry(1).NormalForceN +
      Car.GetWheelTelemetry(2).NormalForceN + Car.GetWheelTelemetry(3).NormalForceN,
      350.0);

    { Place a 0.24m raised platform strictly under the front axle (Z < -0.4) }
    StepPlatform := TCastleBox.Create(OwnerComp);
    StepPlatform.Size := Vector3(6.0, 0.24, 4.0);
    StepPlatform.Translation := Vector3(0.0, 0.12, -2.4);
    Vp.Items.Add(StepPlatform);

    for K := 1 to 25 do
      Car.StepVehicle(0.05);

    FwdW := RotatePointAroundAxis(Car.Rotation, Vector3(0.0, 0.0, -1.0)).Normalize;
    AssertTrue(FwdW.Y > 0.04); // Nose pitched cleanly upward onto the raised front platform!
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolVehicleStudio.TestAccelerationAutoGearUpshiftAckermannTurnHandbrakeDriftAndJson;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  GripCar, DriftCar, LoadedCar: TCastleWheeledVehicle;
  Rep: TVehicleAuditReport;
  JsonStr, Md: String;
  K: Integer;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(Vp, OwnerComp);

    GripCar := TVehicleStudioHelper.SpawnVehicleInDesign(Vp, OwnerComp, vpRallySportsCar, Vector3(-12.0, 0.0, 20.0));
    DriftCar := TVehicleStudioHelper.SpawnVehicleInDesign(Vp, OwnerComp, vpRallySportsCar, Vector3(12.0, 0.0, 20.0));
    GripCar.UseFlatGroundFallback := True;
    DriftCar.UseFlatGroundFallback := True;

    { Accelerate straight at full throttle for 4.0s -> verify speed > 55 km/h & auto-upshift >= Gear 2 }
    GripCar.ThrottleInput := 1.0;
    DriftCar.ThrottleInput := 1.0;
    for K := 1 to 40 do
      TVehicleStudioHelper.StepAllVehicles(Vp, OwnerComp, 0.10);

    AssertTrue(GripCar.ForwardSpeedKmh > 55.0);
    AssertTrue(GripCar.CurrentGear >= 2);
    AssertTrue(GripCar.Translation.Z < -15.0);

    { Initiate right turn: GripCar without handbrake vs DriftCar with Handbrake = 1.0 }
    GripCar.SteerInput := 0.85;
    DriftCar.SteerInput := 0.85;
    DriftCar.HandbrakeInput := 1.0;
    for K := 1 to 8 do
      TVehicleStudioHelper.StepAllVehicles(Vp, OwnerComp, 0.05);

    AssertTrue(GripCar.Translation.X > -11.8); // Turned right (+X)
    AssertTrue(Abs(DriftCar.GetWheelTelemetry(2).SlipAngleDeg) >
               Abs(GripCar.GetWheelTelemetry(2).SlipAngleDeg));

    { Verify csTransient-clean JSON serialization roundtrip }
    JsonStr := ComponentToString(GripCar);
    AssertEquals(0, Pos('ChassisScene', JsonStr));
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleWheeledVehicle);
    LoadedCar := TCastleWheeledVehicle(LoadedComp);
    AssertEquals(Ord(vpRallySportsCar), Ord(LoadedCar.Preset));

    Rep := TVehicleStudioHelper.AuditVehicles(Vp, OwnerComp);
    try
      AssertTrue(Rep.VehicleCount >= 2);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
    Md := TVehicleStudioHelper.BuildMarkdownReport(Vp, OwnerComp);
    AssertTrue(Pos('Wheeled Vehicle', Md) > 0);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolVehicleStudio);
end.
