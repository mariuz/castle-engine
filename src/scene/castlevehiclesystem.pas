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

{ Chaos-Style 4-Wheel Raycast Vehicle Chassis, Spring-Damper Suspension,
  Ackermann Inner/Outer Steering, Engine Torque Curve, Automatic Multi-Gear
  Drivetrain & Pacejka Tire Slip Physics (@link(TCastleWheeledVehicle),
  @link(ComputeAckermannWheelAnglesDeg), @link(EvaluateEngineTorqueCurveNm),
  @link(EvaluatePacejkaLateralForceN))
  (Phase 317 — UE 6.0+ Chaos Vehicles Parity). }
unit CastleVehicleSystem;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleScene, X3DNodes;

type
  { Built-in wheeled vehicle tuning presets. }
  TVehiclePreset = (
    vpCustom,
    vpRallySportsCar,
    vpOffroadMonsterTruck,
    vpArmoredReconBuggy
  );

  { Drivetrain power distribution across front and rear axles. }
  TVehicleDriveMode = (
    vdmRearWheelDrive,
    vdmFrontWheelDrive,
    vdmAllWheelDrive
  );

  { Per-wheel real-time suspension, steering, and tire contact telemetry
    (0 = Front-Left, 1 = Front-Right, 2 = Rear-Left, 3 = Rear-Right). }
  TWheelTelemetry = record
    WheelName: String;
    LocalMountPos: TVector3;
    IsFrontAxle: Boolean;
    IsLeftSide: Boolean;
    IsDriven: Boolean;
    IsGrounded: Boolean;
    SteerAngleDeg: Single;
    CompressionMeters: Single;
    CompressionRatio: Single;
    NormalForceN: Single;
    SlipAngleDeg: Single;
    WheelSpinRad: Single;
    GroundWorldY: Single;
    ContactPointW: TVector3;
    ContactNormalW: TVector3;
  end;

  { Self-contained 4-wheel raycast suspension, Ackermann steering, multi-gear
    drivetrain, and Pacejka tire dynamics vehicle transform.
    Generates @code(csTransient) PBR chassis and animated steering/spinning
    wheel meshes so designs serialize cleanly without baking procedural nodes. }
  TCastleWheeledVehicle = class(TCastleTransform)
  public
    const
      DefaultChassisMassKg = 1380.0;
      DefaultWheelbase = 2.65;
      DefaultTrackWidth = 1.62;
      DefaultWheelRadius = 0.36;
      DefaultSuspensionRestLength = 0.42;
      DefaultSpringStiffness = 34000.0;
      DefaultSpringDamping = 4200.0;
      DefaultAntiRollStiffness = 6500.0;
      DefaultMaxSteerDeg = 34.0;
      DefaultPeakTorqueNm = 460.0;
      DefaultIdleRpm = 950.0;
      DefaultPeakTorqueRpm = 4600.0;
      DefaultRedlineRpm = 7200.0;
      DefaultFinalDriveRatio = 3.70;
      DefaultTireFrictionMu = 1.25;
      DefaultCorneringStiffness = 9.5;
      DefaultBrakeForceN = 14000.0;
      DefaultHandbrakeRearMuScale = 0.38;
      DefaultAeroDragCoeff = 0.42;
      DefaultGravityY = 9.81;
  strict private
    FPreset: TVehiclePreset;
    FDriveMode: TVehicleDriveMode;
    FChassisMassKg: Single;
    FWheelbase: Single;
    FTrackWidth: Single;
    FWheelRadius: Single;
    FSuspensionRestLength: Single;
    FSpringStiffness: Single;
    FSpringDamping: Single;
    FAntiRollStiffness: Single;
    FMaxSteerDeg: Single;
    FPeakTorqueNm: Single;
    FIdleRpm: Single;
    FPeakTorqueRpm: Single;
    FRedlineRpm: Single;
    FFinalDriveRatio: Single;
    FTireFrictionMu: Single;
    FCorneringStiffness: Single;
    FBrakeForceN: Single;
    FHandbrakeRearMuScale: Single;
    FAeroDragCoeff: Single;
    FAutoTransmission: Boolean;
    FUseFlatGroundFallback: Boolean;
    FFlatGroundFallbackY: Single;
    FSimulateInEditor: Boolean;

    FChassisColor: TCastleColorRGB;
    FChassisColorPersistent: TCastleColorRGBPersistent;

    { Live control inputs }
    FThrottleInput: Single;
    FSteerInput: Single;
    FBrakeInput: Single;
    FHandbrakeInput: Single;

    { Live kinematic & drivetrain state }
    FLinearVelocityW: TVector3;
    FAngularVelocityLocal: TVector3; // X = pitch rate, Y = yaw rate, Z = roll rate (rad/s)
    FCurrentGear: Integer; // 1..6 forward gears
    FGearShiftCooldownSec: Single;
    FEngineRpm: Single;
    FForwardSpeedMps: Single;
    FLateralSpeedMps: Single;
    FGearRatios: array [1..6] of Single;
    FWheels: array [0..3] of TWheelTelemetry;
    FPrevCompression: array [0..3] of Single;

    { Transient visual hierarchy }
    FVisualRoot: TCastleTransform;
    FChassisScene: TCastleScene;
    FWheelPivotTransforms: array [0..3] of TCastleTransform;
    FWheelScenes: array [0..3] of TCastleScene;

    procedure SetPreset(const Value: TVehiclePreset);
    procedure SetDriveMode(const Value: TVehicleDriveMode);
    procedure SetChassisMassKg(const Value: Single);
    procedure SetWheelbase(const Value: Single);
    procedure SetTrackWidth(const Value: Single);
    procedure SetWheelRadius(const Value: Single);
    procedure SetSuspensionRestLength(const Value: Single);
    procedure SetSpringStiffness(const Value: Single);
    procedure SetSpringDamping(const Value: Single);
    procedure SetMaxSteerDeg(const Value: Single);
    procedure SetPeakTorqueNm(const Value: Single);
    procedure SetTireFrictionMu(const Value: Single);
    procedure SetThrottleInput(const Value: Single);
    procedure SetSteerInput(const Value: Single);
    procedure SetBrakeInput(const Value: Single);
    procedure SetHandbrakeInput(const Value: Single);
    procedure SetCurrentGear(const Value: Integer);
    procedure SetChassisColor(const Value: TCastleColorRGB);
    function GetChassisColorForPersistent: TCastleColorRGB;
    procedure SetChassisColorForPersistent(const AValue: TCastleColorRGB);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    procedure InitWheelDefinitions;
    procedure RebuildVisualVehicle;
    procedure SyncVisualWheels;
    procedure StepSingleSubstep(const Dt: Single);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TVehiclePreset): String; static;
    class function DriveModeDisplayName(const AMode: TVehicleDriveMode): String; static;

    procedure ApplyPreset(const APreset: TVehiclePreset);
    procedure ResetKinematics;
    procedure StepVehicle(const TotalDt: Single);

    function GetWheelTelemetry(const WheelIndex: Integer): TWheelTelemetry;
    function GroundedWheelCount: Integer;
    function ForwardSpeedKmh: Single;
    function CurrentGearRatio: Single;
    function VehicleSummaryBadge: String;

    property ChassisColor: TCastleColorRGB read FChassisColor write SetChassisColor;
    property LinearVelocityW: TVector3 read FLinearVelocityW write FLinearVelocityW;
    property AngularVelocityLocal: TVector3 read FAngularVelocityLocal write FAngularVelocityLocal;
    property EngineRpm: Single read FEngineRpm;
    property ForwardSpeedMps: Single read FForwardSpeedMps;
    property LateralSpeedMps: Single read FLateralSpeedMps;
  published
    property Preset: TVehiclePreset read FPreset write SetPreset default vpRallySportsCar;
    property DriveMode: TVehicleDriveMode read FDriveMode write SetDriveMode default vdmAllWheelDrive;
    property ChassisMassKg: Single read FChassisMassKg write SetChassisMassKg {$ifdef FPC}default DefaultChassisMassKg{$endif};
    property Wheelbase: Single read FWheelbase write SetWheelbase {$ifdef FPC}default DefaultWheelbase{$endif};
    property TrackWidth: Single read FTrackWidth write SetTrackWidth {$ifdef FPC}default DefaultTrackWidth{$endif};
    property WheelRadius: Single read FWheelRadius write SetWheelRadius {$ifdef FPC}default DefaultWheelRadius{$endif};
    property SuspensionRestLength: Single read FSuspensionRestLength write SetSuspensionRestLength {$ifdef FPC}default DefaultSuspensionRestLength{$endif};
    property SpringStiffness: Single read FSpringStiffness write SetSpringStiffness {$ifdef FPC}default DefaultSpringStiffness{$endif};
    property SpringDamping: Single read FSpringDamping write SetSpringDamping {$ifdef FPC}default DefaultSpringDamping{$endif};
    property AntiRollStiffness: Single read FAntiRollStiffness write FAntiRollStiffness {$ifdef FPC}default DefaultAntiRollStiffness{$endif};
    property MaxSteerDeg: Single read FMaxSteerDeg write SetMaxSteerDeg {$ifdef FPC}default DefaultMaxSteerDeg{$endif};
    property PeakTorqueNm: Single read FPeakTorqueNm write SetPeakTorqueNm {$ifdef FPC}default DefaultPeakTorqueNm{$endif};
    property IdleRpm: Single read FIdleRpm write FIdleRpm {$ifdef FPC}default DefaultIdleRpm{$endif};
    property PeakTorqueRpm: Single read FPeakTorqueRpm write FPeakTorqueRpm {$ifdef FPC}default DefaultPeakTorqueRpm{$endif};
    property RedlineRpm: Single read FRedlineRpm write FRedlineRpm {$ifdef FPC}default DefaultRedlineRpm{$endif};
    property FinalDriveRatio: Single read FFinalDriveRatio write FFinalDriveRatio {$ifdef FPC}default DefaultFinalDriveRatio{$endif};
    property TireFrictionMu: Single read FTireFrictionMu write SetTireFrictionMu {$ifdef FPC}default DefaultTireFrictionMu{$endif};
    property CorneringStiffness: Single read FCorneringStiffness write FCorneringStiffness {$ifdef FPC}default DefaultCorneringStiffness{$endif};
    property BrakeForceN: Single read FBrakeForceN write FBrakeForceN {$ifdef FPC}default DefaultBrakeForceN{$endif};
    property HandbrakeRearMuScale: Single read FHandbrakeRearMuScale write FHandbrakeRearMuScale {$ifdef FPC}default DefaultHandbrakeRearMuScale{$endif};
    property AeroDragCoeff: Single read FAeroDragCoeff write FAeroDragCoeff {$ifdef FPC}default DefaultAeroDragCoeff{$endif};
    property AutoTransmission: Boolean read FAutoTransmission write FAutoTransmission default true;
    property UseFlatGroundFallback: Boolean read FUseFlatGroundFallback write FUseFlatGroundFallback default false;
    property FlatGroundFallbackY: Single read FFlatGroundFallbackY write FFlatGroundFallbackY {$ifdef FPC}default 0.0{$endif};
    property SimulateInEditor: Boolean read FSimulateInEditor write FSimulateInEditor default false;

    property ThrottleInput: Single read FThrottleInput write SetThrottleInput {$ifdef FPC}default 0.0{$endif};
    property SteerInput: Single read FSteerInput write SetSteerInput {$ifdef FPC}default 0.0{$endif};
    property BrakeInput: Single read FBrakeInput write SetBrakeInput {$ifdef FPC}default 0.0{$endif};
    property HandbrakeInput: Single read FHandbrakeInput write SetHandbrakeInput {$ifdef FPC}default 0.0{$endif};
    property CurrentGear: Integer read FCurrentGear write SetCurrentGear default 1;

    property ChassisColorPersistent: TCastleColorRGBPersistent read FChassisColorPersistent;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored false;
  end;

{ Compute exact Ackermann steering wheel angles (degrees, positive = turn right,
  negative = turn left) so both front wheel axle lines intersect at a single
  instantaneous turn center. }
procedure ComputeAckermannWheelAnglesDeg(
  const ASteerInput, AMaxSteerDeg, AWheelbase, ATrackWidth: Single;
  out OutFrontLeftDeg, OutFrontRightDeg: Single);

{ Smooth bell-shaped internal-combustion / hybrid torque curve (N*m) peaking at
  @code(APeakTorqueRpm) and cutting off cleanly above @code(ARedlineRpm * 1.05). }
function EvaluateEngineTorqueCurveNm(
  const ARpm, AIdleRpm, APeakTorqueRpm, ARedlineRpm, APeakTorqueNm: Single): Single;

{ Simplified Pacejka Magic Formula lateral tire force (N) opposing lateral slip
  angle @code(ASlipAngleRad), smoothly saturating at @code(AFrictionMu * ANormalForceN). }
function EvaluatePacejkaLateralForceN(
  const ASlipAngleRad, ANormalForceN, ACorneringStiffness, AFrictionMu: Single): Single;

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize, CastleApplicationProperties,
  CastleQuaternions;

procedure ComputeAckermannWheelAnglesDeg(
  const ASteerInput, AMaxSteerDeg, AWheelbase, ATrackWidth: Single;
  out OutFrontLeftDeg, OutFrontRightDeg: Single);
var
  ClampedSteer, RefAngleRad, L, HalfW, TurnRadius, InnerRad, OuterRad: Single;
begin
  ClampedSteer := Clamped(ASteerInput, -1.0, 1.0);
  if (Abs(ClampedSteer) < 1e-5) or (AMaxSteerDeg <= 0.01) then
  begin
    OutFrontLeftDeg := 0.0;
    OutFrontRightDeg := 0.0;
    Exit;
  end;

  L := Max(0.25, AWheelbase);
  HalfW := Max(0.05, ATrackWidth * 0.5);
  RefAngleRad := DegToRad(Clamped(Abs(ClampedSteer) * AMaxSteerDeg, 0.01, 75.0));
  TurnRadius := L / Tan(RefAngleRad);
  if TurnRadius <= HalfW + 0.05 then
    TurnRadius := HalfW + 0.05;

  InnerRad := ArcTan2(L, TurnRadius - HalfW);
  OuterRad := ArcTan2(L, TurnRadius + HalfW);

  if ClampedSteer > 0.0 then
  begin
    { Turning right: Front-Right is inner wheel, Front-Left is outer wheel }
    OutFrontRightDeg := RadToDeg(InnerRad);
    OutFrontLeftDeg := RadToDeg(OuterRad);
  end else
  begin
    { Turning left: Front-Left is inner wheel, Front-Right is outer wheel }
    OutFrontLeftDeg := -RadToDeg(InnerRad);
    OutFrontRightDeg := -RadToDeg(OuterRad);
  end;
end;

function EvaluateEngineTorqueCurveNm(
  const ARpm, AIdleRpm, APeakTorqueRpm, ARedlineRpm, APeakTorqueNm: Single): Single;
var
  SafeIdle, SafePeak, SafeRedline, HardCutoff, T, Factor: Single;
begin
  if APeakTorqueNm <= 0.0 then
    Exit(0.0);
  SafeIdle := Max(200.0, AIdleRpm);
  SafePeak := Max(SafeIdle + 200.0, APeakTorqueRpm);
  SafeRedline := Max(SafePeak + 400.0, ARedlineRpm);
  HardCutoff := SafeRedline * 1.05;

  if ARpm >= HardCutoff then
    Exit(0.0);

  if ARpm <= SafeIdle then
    Factor := 0.68
  else if ARpm <= SafePeak then
  begin
    T := (ARpm - SafeIdle) / (SafePeak - SafeIdle);
    { Smoothly rises from 0.68 at Idle to 1.00 at PeakTorqueRpm }
    Factor := 0.68 + 0.32 * (1.0 - Sqr(1.0 - T));
  end else if ARpm <= SafeRedline then
  begin
    T := (ARpm - SafePeak) / (SafeRedline - SafePeak);
    { Smoothly tapers from 1.00 at PeakTorqueRpm to 0.74 at RedlineRpm }
    Factor := 1.0 - 0.26 * Sqr(T);
  end else
  begin
    { Soft rev-limiter taper between RedlineRpm and 1.05 * RedlineRpm }
    T := (ARpm - SafeRedline) / (HardCutoff - SafeRedline);
    Factor := 0.74 * Max(0.0, 1.0 - T);
  end;

  Result := APeakTorqueNm * Factor;
end;

function EvaluatePacejkaLateralForceN(
  const ASlipAngleRad, ANormalForceN, ACorneringStiffness, AFrictionMu: Single): Single;
const
  ShapeFactorC = 1.35;
var
  PeakForce, StiffnessB: Single;
begin
  if (ANormalForceN <= 0.0) or (AFrictionMu <= 0.0) then
    Exit(0.0);
  PeakForce := AFrictionMu * ANormalForceN;
  StiffnessB := Max(0.5, ACorneringStiffness) / ShapeFactorC;
  Result := -PeakForce * Sin(ShapeFactorC * ArcTan(StiffnessB * ASlipAngleRad));
  Result := Clamped(Result, -PeakForce, PeakForce);
end;

function CreateBoxRootNode(const SizeVec: TVector3;
  const BaseCol: TCastleColorRGB; const Rough, Metal: Single): TX3DRootNode;
var
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BoxNode: TBoxNode;
begin
  Result := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := BaseCol;
  Mat.Roughness := Clamped(Rough, 0.04, 1.0);
  Mat.Metallic := Clamped(Metal, 0.0, 1.0);
  App.Material := Mat;
  Shape.Appearance := App;

  BoxNode := TBoxNode.Create;
  BoxNode.Size := SizeVec;
  Shape.Geometry := BoxNode;
  Result.AddChildren(Shape);
end;

function CreateWheelRootNode(const ARadius, AWidth: Single): TX3DRootNode;
var
  RotTrans: TTransformNode;
  TireShape, HubShape: TShapeNode;
  TireApp, HubApp: TAppearanceNode;
  TireMat, HubMat: TPhysicalMaterialNode;
  TireCyl, HubCyl: TCylinderNode;
begin
  Result := TX3DRootNode.Create;
  { Rotate X3D Y-aligned cylinder by 90 deg around Z so axle aligns with local X }
  RotTrans := TTransformNode.Create;
  RotTrans.Rotation := Vector4(0.0, 0.0, 1.0, Pi * 0.5);

  TireShape := TShapeNode.Create;
  TireApp := TAppearanceNode.Create;
  TireMat := TPhysicalMaterialNode.Create;
  TireMat.BaseColor := Vector3(0.14, 0.14, 0.16);
  TireMat.Roughness := 0.86;
  TireMat.Metallic := 0.05;
  TireApp.Material := TireMat;
  TireShape.Appearance := TireApp;
  TireCyl := TCylinderNode.Create;
  TireCyl.Radius := Max(0.08, ARadius);
  TireCyl.Height := Max(0.06, AWidth);
  TireShape.Geometry := TireCyl;
  RotTrans.AddChildren(TireShape);

  HubShape := TShapeNode.Create;
  HubApp := TAppearanceNode.Create;
  HubMat := TPhysicalMaterialNode.Create;
  HubMat.BaseColor := Vector3(0.76, 0.79, 0.84);
  HubMat.Roughness := 0.32;
  HubMat.Metallic := 0.82;
  HubApp.Material := HubMat;
  HubShape.Appearance := HubApp;
  HubCyl := TCylinderNode.Create;
  HubCyl.Radius := Max(0.04, ARadius * 0.58);
  HubCyl.Height := Max(0.07, AWidth * 1.04);
  HubShape.Geometry := HubCyl;
  RotTrans.AddChildren(HubShape);

  Result.AddChildren(RotTrans);
end;

{ TCastleWheeledVehicle ------------------------------------------------------ }

constructor TCastleWheeledVehicle.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChassisColor := Vector3(0.86, 0.20, 0.16);
  FChassisColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FChassisColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetChassisColorForPersistent;
  FChassisColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetChassisColorForPersistent;
  FChassisColorPersistent.InternalDefaultValue := FChassisColor;

  FGearRatios[1] := 3.45;
  FGearRatios[2] := 2.28;
  FGearRatios[3] := 1.68;
  FGearRatios[4] := 1.30;
  FGearRatios[5] := 1.04;
  FGearRatios[6] := 0.86;

  FAutoTransmission := True;
  FUseFlatGroundFallback := False;
  FFlatGroundFallbackY := 0.0;
  FSimulateInEditor := False;

  ApplyPreset(vpRallySportsCar);
  ResetKinematics;
end;

destructor TCastleWheeledVehicle.Destroy;
begin
  FreeAndNil(FChassisColorPersistent);
  inherited;
end;

procedure TCastleWheeledVehicle.Loaded;
begin
  inherited;
  InitWheelDefinitions;
  RebuildVisualVehicle;
end;

class function TCastleWheeledVehicle.PresetDisplayName(const APreset: TVehiclePreset): String;
begin
  case APreset of
    vpCustom:              Result := 'Custom Tuning';
    vpRallySportsCar:      Result := 'Rally Sports Car (AWD)';
    vpOffroadMonsterTruck: Result := 'Offroad Monster Truck (4x4)';
    vpArmoredReconBuggy:   Result := 'Armored Recon Buggy (RWD)';
  end;
end;

class function TCastleWheeledVehicle.DriveModeDisplayName(const AMode: TVehicleDriveMode): String;
begin
  case AMode of
    vdmRearWheelDrive:  Result := 'RWD';
    vdmFrontWheelDrive: Result := 'FWD';
    vdmAllWheelDrive:   Result := 'AWD';
  end;
end;

procedure TCastleWheeledVehicle.ApplyPreset(const APreset: TVehiclePreset);
begin
  FPreset := APreset;
  case APreset of
    vpRallySportsCar:
      begin
        FDriveMode := vdmAllWheelDrive;
        FChassisMassKg := DefaultChassisMassKg;
        FWheelbase := DefaultWheelbase;
        FTrackWidth := DefaultTrackWidth;
        FWheelRadius := DefaultWheelRadius;
        FSuspensionRestLength := DefaultSuspensionRestLength;
        FSpringStiffness := DefaultSpringStiffness;
        FSpringDamping := DefaultSpringDamping;
        FAntiRollStiffness := DefaultAntiRollStiffness;
        FMaxSteerDeg := DefaultMaxSteerDeg;
        FPeakTorqueNm := DefaultPeakTorqueNm;
        FIdleRpm := DefaultIdleRpm;
        FPeakTorqueRpm := DefaultPeakTorqueRpm;
        FRedlineRpm := DefaultRedlineRpm;
        FFinalDriveRatio := DefaultFinalDriveRatio;
        FTireFrictionMu := DefaultTireFrictionMu;
        FCorneringStiffness := DefaultCorneringStiffness;
        FBrakeForceN := DefaultBrakeForceN;
        FHandbrakeRearMuScale := DefaultHandbrakeRearMuScale;
        FAeroDragCoeff := DefaultAeroDragCoeff;
        FChassisColor := Vector3(0.86, 0.20, 0.16);
      end;
    vpOffroadMonsterTruck:
      begin
        FDriveMode := vdmAllWheelDrive;
        FChassisMassKg := 2250.0;
        FWheelbase := 3.30;
        FTrackWidth := 2.25;
        FWheelRadius := 0.68;
        FSuspensionRestLength := 0.78;
        FSpringStiffness := 48000.0;
        FSpringDamping := 5800.0;
        FAntiRollStiffness := 8200.0;
        FMaxSteerDeg := 28.0;
        FPeakTorqueNm := 780.0;
        FIdleRpm := 850.0;
        FPeakTorqueRpm := 3600.0;
        FRedlineRpm := 5800.0;
        FFinalDriveRatio := 4.30;
        FTireFrictionMu := 1.15;
        FCorneringStiffness := 7.8;
        FBrakeForceN := 19000.0;
        FHandbrakeRearMuScale := 0.45;
        FAeroDragCoeff := 0.72;
        FChassisColor := Vector3(0.18, 0.56, 0.92);
      end;
    vpArmoredReconBuggy:
      begin
        FDriveMode := vdmRearWheelDrive;
        FChassisMassKg := 980.0;
        FWheelbase := 2.45;
        FTrackWidth := 1.76;
        FWheelRadius := 0.40;
        FSuspensionRestLength := 0.52;
        FSpringStiffness := 26000.0;
        FSpringDamping := 3300.0;
        FAntiRollStiffness := 4600.0;
        FMaxSteerDeg := 38.0;
        FPeakTorqueNm := 390.0;
        FIdleRpm := 1050.0;
        FPeakTorqueRpm := 5100.0;
        FRedlineRpm := 7600.0;
        FFinalDriveRatio := 3.85;
        FTireFrictionMu := 1.18;
        FCorneringStiffness := 10.2;
        FBrakeForceN := 11500.0;
        FHandbrakeRearMuScale := 0.30;
        FAeroDragCoeff := 0.48;
        FChassisColor := Vector3(0.88, 0.68, 0.18);
      end;
    vpCustom: ;
  end;
  InitWheelDefinitions;
  RebuildVisualVehicle;
end;

procedure TCastleWheeledVehicle.ResetKinematics;
var
  I: Integer;
begin
  FLinearVelocityW := TVector3.Zero;
  FAngularVelocityLocal := TVector3.Zero;
  FCurrentGear := 1;
  FGearShiftCooldownSec := 0.0;
  FEngineRpm := FIdleRpm;
  FForwardSpeedMps := 0.0;
  FLateralSpeedMps := 0.0;
  for I := 0 to 3 do
  begin
    FPrevCompression[I] := 0.0;
    FWheels[I].IsGrounded := False;
    FWheels[I].CompressionMeters := 0.0;
    FWheels[I].CompressionRatio := 0.0;
    FWheels[I].NormalForceN := 0.0;
    FWheels[I].SlipAngleDeg := 0.0;
    FWheels[I].WheelSpinRad := 0.0;
    FWheels[I].SteerAngleDeg := 0.0;
  end;
  InitWheelDefinitions;
  SyncVisualWheels;
end;

procedure TCastleWheeledVehicle.InitWheelDefinitions;
const
  Names: array [0..3] of String = ('FrontLeft', 'FrontRight', 'RearLeft', 'RearRight');
var
  HalfL, HalfW: Single;
  I: Integer;
begin
  HalfL := Max(0.25, FWheelbase * 0.5);
  HalfW := Max(0.15, FTrackWidth * 0.5);

  { CGE vehicle forward convention: local -Z is Forward, +X is Right, +Y is Up }
  FWheels[0].LocalMountPos := Vector3(-HalfW, 0.0, -HalfL); // FL
  FWheels[1].LocalMountPos := Vector3( HalfW, 0.0, -HalfL); // FR
  FWheels[2].LocalMountPos := Vector3(-HalfW, 0.0,  HalfL); // RL
  FWheels[3].LocalMountPos := Vector3( HalfW, 0.0,  HalfL); // RR

  for I := 0 to 3 do
  begin
    FWheels[I].WheelName := Names[I];
    FWheels[I].IsFrontAxle := I < 2;
    FWheels[I].IsLeftSide := (I = 0) or (I = 2);
    case FDriveMode of
      vdmFrontWheelDrive: FWheels[I].IsDriven := FWheels[I].IsFrontAxle;
      vdmRearWheelDrive:  FWheels[I].IsDriven := not FWheels[I].IsFrontAxle;
      vdmAllWheelDrive:   FWheels[I].IsDriven := True;
    end;
  end;
end;

procedure TCastleWheeledVehicle.RebuildVisualVehicle;
var
  CabinScene: TCastleScene;
  BodySize, CabinSize: TVector3;
  I: Integer;
begin
  if csLoading in ComponentState then
    Exit;

  FreeAndNil(FVisualRoot);

  FVisualRoot := TCastleTransform.Create(Self);
  FVisualRoot.SetTransient;
  FVisualRoot.Pickable := False;
  FVisualRoot.Collides := False;
  Add(FVisualRoot);

  BodySize := Vector3(Max(0.8, FTrackWidth * 0.92), Max(0.32, FWheelRadius * 1.15),
    Max(1.4, FWheelbase * 1.38));
  FChassisScene := TCastleScene.Create(FVisualRoot);
  FChassisScene.SetTransient;
  FChassisScene.Pickable := False;
  FChassisScene.Collides := False;
  FChassisScene.Translation := Vector3(0.0, BodySize.Y * 0.45, 0.0);
  FChassisScene.Load(CreateBoxRootNode(BodySize, FChassisColor, 0.34, 0.42), True);
  FVisualRoot.Add(FChassisScene);

  CabinSize := Vector3(BodySize.X * 0.80, BodySize.Y * 0.72, BodySize.Z * 0.46);
  CabinScene := TCastleScene.Create(FVisualRoot);
  CabinScene.SetTransient;
  CabinScene.Pickable := False;
  CabinScene.Collides := False;
  CabinScene.Translation := Vector3(0.0, BodySize.Y * 0.96, BodySize.Z * 0.06);
  CabinScene.Load(CreateBoxRootNode(CabinSize, Vector3(0.14, 0.18, 0.24), 0.18, 0.65), True);
  FVisualRoot.Add(CabinScene);

  for I := 0 to 3 do
  begin
    FWheelPivotTransforms[I] := TCastleTransform.Create(FVisualRoot);
    FWheelPivotTransforms[I].SetTransient;
    FWheelPivotTransforms[I].Pickable := False;
    FWheelPivotTransforms[I].Collides := False;
    FVisualRoot.Add(FWheelPivotTransforms[I]);

    FWheelScenes[I] := TCastleScene.Create(FWheelPivotTransforms[I]);
    FWheelScenes[I].SetTransient;
    FWheelScenes[I].Pickable := False;
    FWheelScenes[I].Collides := False;
    FWheelScenes[I].Load(CreateWheelRootNode(FWheelRadius, FWheelRadius * 0.68), True);
    FWheelPivotTransforms[I].Add(FWheelScenes[I]);
  end;

  SyncVisualWheels;
end;

procedure TCastleWheeledVehicle.SyncVisualWheels;
var
  I: Integer;
  DropDist, SteerYawRad: Single;
begin
  if FVisualRoot = nil then
    Exit;
  for I := 0 to 3 do
  begin
    if FWheelPivotTransforms[I] = nil then
      Continue;
    DropDist := Max(0.0, FSuspensionRestLength - FWheels[I].CompressionMeters);
    FWheelPivotTransforms[I].Translation :=
      FWheels[I].LocalMountPos + Vector3(0.0, -DropDist, 0.0);
    { Positive SteerAngleDeg = turn right = negative yaw around +Y }
    SteerYawRad := -DegToRad(FWheels[I].SteerAngleDeg);
    FWheelPivotTransforms[I].Rotation := Vector4(0.0, 1.0, 0.0, SteerYawRad);
    if FWheelScenes[I] <> nil then
      FWheelScenes[I].Rotation := Vector4(-1.0, 0.0, 0.0, FWheels[I].WheelSpinRad);
  end;
end;

function TCastleWheeledVehicle.CurrentGearRatio: Single;
begin
  Result := FGearRatios[Clamped(FCurrentGear, 1, 6)];
end;

procedure TCastleWheeledVehicle.StepSingleSubstep(const Dt: Single);
var
  ChassisPosW, ChassisRightW, ChassisUpW, ChassisFwdW: TVector3;
  NetForceW, NetTorqueLocal: TVector3;
  MountPosW, RayDirW, PointVelW, WheelFwdW, WheelRightW: TVector3;
  LocalOffset, LeverLocal, ForceLocal, CrossTorqueLocal, AeroDragW: TVector3;
  LeftSteerDeg, RightSteerDeg, MaxRayLen, HitDist: Single;
  CompVel, SpringF, AntiRollFront, AntiRollRear: Single;
  WheelFwdSpeed, WheelLatSpeed, SlipRad, EffectiveMu, LatForceN, LongForceN: Single;
  DrivenCount, I: Integer;
  DrivenAvgRpm, WheelRpm, EngineTorque, DriveForcePerWheel, TotalBrakePerWheel: Single;
  InertiaPitch, InertiaYaw, InertiaRoll: Single;
  QCurrent, QDelta: TQuaternion;
  AxisAngle: TVector4;
  RayHit: TRayCollision;
  SavedPick, SavedCollides, HitFound: Boolean;
begin
  if Dt <= 1e-6 then
    Exit;

  InitWheelDefinitions;

  { Update Ackermann front steering angles }
  ComputeAckermannWheelAnglesDeg(FSteerInput, FMaxSteerDeg, FWheelbase, FTrackWidth,
    LeftSteerDeg, RightSteerDeg);
  FWheels[0].SteerAngleDeg := LeftSteerDeg;
  FWheels[1].SteerAngleDeg := RightSteerDeg;
  FWheels[2].SteerAngleDeg := 0.0;
  FWheels[3].SteerAngleDeg := 0.0;

  { World basis of chassis (-Z forward, +X right, +Y up) }
  ChassisPosW := Translation;
  ChassisRightW := RotatePointAroundAxis(Rotation, Vector3(1.0, 0.0, 0.0)).Normalize;
  ChassisUpW := RotatePointAroundAxis(Rotation, Vector3(0.0, 1.0, 0.0)).Normalize;
  ChassisFwdW := RotatePointAroundAxis(Rotation, Vector3(0.0, 0.0, -1.0)).Normalize;

  FForwardSpeedMps := TVector3.DotProduct(FLinearVelocityW, ChassisFwdW);
  FLateralSpeedMps := TVector3.DotProduct(FLinearVelocityW, ChassisRightW);

  { Gravity + quadratic aerodynamic drag }
  NetForceW := Vector3(0.0, -DefaultGravityY * FChassisMassKg, 0.0);
  if FLinearVelocityW.LengthSqr > 1e-4 then
  begin
    AeroDragW := -FLinearVelocityW.Normalize *
      (FAeroDragCoeff * FLinearVelocityW.LengthSqr);
    NetForceW := NetForceW + AeroDragW;
  end;
  NetTorqueLocal := TVector3.Zero;

  { 1. Raycast each wheel suspension along -ChassisUpW }
  RayDirW := -ChassisUpW;
  MaxRayLen := FSuspensionRestLength + FWheelRadius;

  SavedPick := Pickable;
  SavedCollides := Collides;
  Pickable := False;
  Collides := False;
  try
    for I := 0 to 3 do
    begin
      LocalOffset := FWheels[I].LocalMountPos;
      MountPosW := ChassisPosW +
        ChassisRightW * LocalOffset.X +
        ChassisUpW * LocalOffset.Y +
        (-ChassisFwdW) * LocalOffset.Z;

      HitFound := False;
      HitDist := MaxRayLen + 1.0;
      FWheels[I].ContactNormalW := Vector3(0.0, 1.0, 0.0);

      if World <> nil then
      begin
        RayHit := World.WorldRay(MountPosW, RayDirW);
        if RayHit <> nil then
        try
          if (RayHit.Transform <> nil) and (RayHit.Distance <= MaxRayLen) then
          begin
            HitFound := True;
            HitDist := RayHit.Distance;
            FWheels[I].ContactPointW := MountPosW + RayDirW * HitDist;
            FWheels[I].GroundWorldY := FWheels[I].ContactPointW.Y;
            if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
               (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
            begin
              FWheels[I].ContactNormalW := RayHit.First.Item.LocalToWorldDirection(
                RayHit.First.Triangle^.SceneSpace.Normal);
              if FWheels[I].ContactNormalW.LengthSqr < 1e-6 then
                FWheels[I].ContactNormalW := Vector3(0.0, 1.0, 0.0)
              else
                FWheels[I].ContactNormalW := FWheels[I].ContactNormalW.Normalize;
              if TVector3.DotProduct(FWheels[I].ContactNormalW, ChassisUpW) < 0.0 then
                FWheels[I].ContactNormalW := -FWheels[I].ContactNormalW;
            end;
          end;
        finally
          FreeAndNil(RayHit);
        end;
      end;

      if (not HitFound) and FUseFlatGroundFallback and (RayDirW.Y < -0.15) then
      begin
        HitDist := (MountPosW.Y - FFlatGroundFallbackY) / (-RayDirW.Y);
        if (HitDist >= 0.0) and (HitDist <= MaxRayLen) then
        begin
          HitFound := True;
          FWheels[I].ContactPointW := MountPosW + RayDirW * HitDist;
          FWheels[I].GroundWorldY := FFlatGroundFallbackY;
          FWheels[I].ContactNormalW := Vector3(0.0, 1.0, 0.0);
        end;
      end;

      if HitFound then
      begin
        FWheels[I].IsGrounded := True;
        FWheels[I].CompressionMeters := Clamped(
          MaxRayLen - HitDist, 0.0, FSuspensionRestLength);
        if FSuspensionRestLength > 1e-4 then
          FWheels[I].CompressionRatio := FWheels[I].CompressionMeters / FSuspensionRestLength
        else
          FWheels[I].CompressionRatio := 0.0;
        CompVel := (FWheels[I].CompressionMeters - FPrevCompression[I]) / Dt;
        SpringF := FSpringStiffness * FWheels[I].CompressionMeters +
          FSpringDamping * CompVel;
        FWheels[I].NormalForceN := Max(0.0, SpringF);
      end else
      begin
        FWheels[I].IsGrounded := False;
        FWheels[I].CompressionMeters := 0.0;
        FWheels[I].CompressionRatio := 0.0;
        FWheels[I].NormalForceN := 0.0;
        FWheels[I].SlipAngleDeg := 0.0;
      end;
      FPrevCompression[I] := FWheels[I].CompressionMeters;
    end;
  finally
    Pickable := SavedPick;
    Collides := SavedCollides;
  end;

  { 2. Anti-roll stabilizer bar transfer across front (0,1) and rear (2,3) pairs }
  if FWheels[0].IsGrounded or FWheels[1].IsGrounded then
  begin
    AntiRollFront := (FWheels[0].CompressionRatio - FWheels[1].CompressionRatio) *
      FAntiRollStiffness;
    if FWheels[0].IsGrounded then
      FWheels[0].NormalForceN := Max(0.0, FWheels[0].NormalForceN + AntiRollFront);
    if FWheels[1].IsGrounded then
      FWheels[1].NormalForceN := Max(0.0, FWheels[1].NormalForceN - AntiRollFront);
  end;
  if FWheels[2].IsGrounded or FWheels[3].IsGrounded then
  begin
    AntiRollRear := (FWheels[2].CompressionRatio - FWheels[3].CompressionRatio) *
      FAntiRollStiffness;
    if FWheels[2].IsGrounded then
      FWheels[2].NormalForceN := Max(0.0, FWheels[2].NormalForceN + AntiRollRear);
    if FWheels[3].IsGrounded then
      FWheels[3].NormalForceN := Max(0.0, FWheels[3].NormalForceN - AntiRollRear);
  end;

  { 3. Drivetrain RPM, Automatic Gear Shifting & Wheel Drive Force }
  DrivenCount := 0;
  DrivenAvgRpm := 0.0;
  for I := 0 to 3 do
    if FWheels[I].IsDriven then
    begin
      Inc(DrivenCount);
      WheelRpm := (Abs(FForwardSpeedMps) / (2.0 * Pi * Max(0.08, FWheelRadius))) * 60.0;
      DrivenAvgRpm := DrivenAvgRpm + WheelRpm;
    end;
  if DrivenCount > 0 then
    DrivenAvgRpm := DrivenAvgRpm / DrivenCount;

  FEngineRpm := Max(FIdleRpm, DrivenAvgRpm * CurrentGearRatio * FFinalDriveRatio);

  if FGearShiftCooldownSec > 0.0 then
    FGearShiftCooldownSec := Max(0.0, FGearShiftCooldownSec - Dt);

  if FAutoTransmission and (FGearShiftCooldownSec <= 0.0) then
  begin
    if (FCurrentGear < 6) and (FThrottleInput > 0.15) and
       (FEngineRpm >= FRedlineRpm * 0.88) then
    begin
      Inc(FCurrentGear);
      FGearShiftCooldownSec := 0.22;
      FEngineRpm := Max(FIdleRpm, DrivenAvgRpm * CurrentGearRatio * FFinalDriveRatio);
    end else
    if (FCurrentGear > 1) and (FEngineRpm <= FRedlineRpm * 0.38) then
    begin
      Dec(FCurrentGear);
      FGearShiftCooldownSec := 0.22;
      FEngineRpm := Max(FIdleRpm, DrivenAvgRpm * CurrentGearRatio * FFinalDriveRatio);
    end;
  end;

  EngineTorque := EvaluateEngineTorqueCurveNm(
    FEngineRpm, FIdleRpm, FPeakTorqueRpm, FRedlineRpm, FPeakTorqueNm) * FThrottleInput;
  if DrivenCount > 0 then
    DriveForcePerWheel := (EngineTorque * CurrentGearRatio * FFinalDriveRatio) /
      (Max(0.08, FWheelRadius) * DrivenCount)
  else
    DriveForcePerWheel := 0.0;

  TotalBrakePerWheel := FBrakeInput * FBrakeForceN * 0.25;

  { 4. Accumulate 3D Suspension + Longitudinal + Pacejka Lateral forces & torques }
  for I := 0 to 3 do
  begin
    LocalOffset := FWheels[I].LocalMountPos;
    { Steered wheel axes in chassis local & world space }
    WheelFwdW := RotatePointAroundAxis(
      Vector4(ChassisUpW, -DegToRad(FWheels[I].SteerAngleDeg)), ChassisFwdW).Normalize;
    WheelRightW := TVector3.CrossProduct(WheelFwdW, ChassisUpW).Normalize;

    { Point velocity at contact patch in chassis-local -> world }
    LeverLocal := Vector3(LocalOffset.X,
      -(FSuspensionRestLength - FWheels[I].CompressionMeters), LocalOffset.Z);
    CrossTorqueLocal := TVector3.CrossProduct(FAngularVelocityLocal, LeverLocal);
    PointVelW := FLinearVelocityW +
      ChassisRightW * CrossTorqueLocal.X +
      ChassisUpW * CrossTorqueLocal.Y +
      (-ChassisFwdW) * CrossTorqueLocal.Z;

    WheelFwdSpeed := TVector3.DotProduct(PointVelW, WheelFwdW);
    WheelLatSpeed := TVector3.DotProduct(PointVelW, WheelRightW);

    FWheels[I].WheelSpinRad := FWheels[I].WheelSpinRad +
      (WheelFwdSpeed / Max(0.08, FWheelRadius)) * Dt;

    if not FWheels[I].IsGrounded then
      Continue;

    if (Abs(WheelFwdSpeed) < 0.25) and (Abs(WheelLatSpeed) < 0.05) then
      SlipRad := 0.0
    else
      SlipRad := ArcTan2(WheelLatSpeed, Max(0.6, Abs(WheelFwdSpeed)));
    FWheels[I].SlipAngleDeg := RadToDeg(SlipRad);

    EffectiveMu := FTireFrictionMu;
    if (not FWheels[I].IsFrontAxle) and (FHandbrakeInput > 0.01) then
      EffectiveMu := FTireFrictionMu * Lerp(FHandbrakeInput, 1.0, FHandbrakeRearMuScale);

    LatForceN := EvaluatePacejkaLateralForceN(
      SlipRad, FWheels[I].NormalForceN, FCorneringStiffness, EffectiveMu);
    { Low-speed lateral velocity scrub damping to prevent micro-oscillation at rest }
    if Abs(WheelFwdSpeed) < 1.5 then
      LatForceN := LatForceN * Clamped(Abs(WheelFwdSpeed) / 1.5, 0.25, 1.0)
        - WheelLatSpeed * (FChassisMassKg * 1.8);

    LongForceN := 0.0;
    if FWheels[I].IsDriven then
      LongForceN := DriveForcePerWheel;
    if TotalBrakePerWheel > 0.0 then
    begin
      if Abs(WheelFwdSpeed) > 0.15 then
        LongForceN := LongForceN - Sign(WheelFwdSpeed) * TotalBrakePerWheel
      else
        LongForceN := LongForceN - WheelFwdSpeed * TotalBrakePerWheel;
    end;
    if (not FWheels[I].IsFrontAxle) and (FHandbrakeInput > 0.01) then
      LongForceN := LongForceN - Sign(WheelFwdSpeed) *
        (FHandbrakeInput * FBrakeForceN * 0.35);

    { Rolling resistance }
    LongForceN := LongForceN - WheelFwdSpeed * 18.0;
    LongForceN := Clamped(LongForceN,
      -EffectiveMu * FWheels[I].NormalForceN,
       EffectiveMu * FWheels[I].NormalForceN);

    { Sum world force from this wheel }
    NetForceW := NetForceW +
      FWheels[I].ContactNormalW * FWheels[I].NormalForceN +
      WheelFwdW * LongForceN +
      WheelRightW * LatForceN;

    { Convert wheel world force into chassis local frame for r x F torque }
    ForceLocal := Vector3(
      TVector3.DotProduct(
        FWheels[I].ContactNormalW * FWheels[I].NormalForceN +
        WheelFwdW * LongForceN + WheelRightW * LatForceN, ChassisRightW),
      TVector3.DotProduct(
        FWheels[I].ContactNormalW * FWheels[I].NormalForceN +
        WheelFwdW * LongForceN + WheelRightW * LatForceN, ChassisUpW),
      TVector3.DotProduct(
        FWheels[I].ContactNormalW * FWheels[I].NormalForceN +
        WheelFwdW * LongForceN + WheelRightW * LatForceN, -ChassisFwdW));

    { Apply tire planar forces near CG height*0.35 to model realistic roll/pitch center }
    LeverLocal := Vector3(LocalOffset.X, -FWheelRadius * 0.35, LocalOffset.Z);
    NetTorqueLocal := NetTorqueLocal + TVector3.CrossProduct(LeverLocal, ForceLocal);
  end;

  { 5. Symplectic Euler linear & angular integration }
  FLinearVelocityW := FLinearVelocityW + (NetForceW / Max(50.0, FChassisMassKg)) * Dt;
  Translation := Translation + FLinearVelocityW * Dt;

  InertiaPitch := Max(40.0, FChassisMassKg * Sqr(FWheelbase) * 0.22);
  InertiaYaw   := Max(40.0, FChassisMassKg * (Sqr(FWheelbase) + Sqr(FTrackWidth)) * 0.18);
  InertiaRoll  := Max(30.0, FChassisMassKg * Sqr(FTrackWidth) * 0.20);

  FAngularVelocityLocal.X := (FAngularVelocityLocal.X + (NetTorqueLocal.X / InertiaPitch) * Dt) *
    Exp(-2.6 * Dt);
  FAngularVelocityLocal.Y := (FAngularVelocityLocal.Y + (NetTorqueLocal.Y / InertiaYaw) * Dt) *
    Exp(-3.2 * Dt);
  FAngularVelocityLocal.Z := (FAngularVelocityLocal.Z + (NetTorqueLocal.Z / InertiaRoll) * Dt) *
    Exp(-2.8 * Dt);

  if FAngularVelocityLocal.LengthSqr > 1e-10 then
  begin
    QCurrent := QuatFromAxisAngle(Rotation);
    QDelta := QuatFromAxisAngle(Vector4(
      FAngularVelocityLocal.Normalize, FAngularVelocityLocal.Length * Dt));
    QCurrent := (QCurrent * QDelta).Normalize;
    AxisAngle := QCurrent.ToAxisAngle;
    Rotation := AxisAngle;
  end;

  { Recompute chassis forward/lateral speeds after integration }
  ChassisRightW := RotatePointAroundAxis(Rotation, Vector3(1.0, 0.0, 0.0)).Normalize;
  ChassisFwdW := RotatePointAroundAxis(Rotation, Vector3(0.0, 0.0, -1.0)).Normalize;
  FForwardSpeedMps := TVector3.DotProduct(FLinearVelocityW, ChassisFwdW);
  FLateralSpeedMps := TVector3.DotProduct(FLinearVelocityW, ChassisRightW);
end;

procedure TCastleWheeledVehicle.StepVehicle(const TotalDt: Single);
const
  MaxSubStep = 1.0 / 120.0;
var
  Remaining, StepDt: Single;
begin
  if TotalDt <= 0.0 then
    Exit;
  Remaining := Min(TotalDt, 0.5);
  while Remaining > 1e-6 do
  begin
    StepDt := Min(Remaining, MaxSubStep);
    StepSingleSubstep(StepDt);
    Remaining := Remaining - StepDt;
  end;
  SyncVisualWheels;
end;

procedure TCastleWheeledVehicle.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if (CastleApplicationMode = appRunning) or FSimulateInEditor then
    StepVehicle(SecondsPassed);
end;

function TCastleWheeledVehicle.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'DriveMode') or
     (PropertyName = 'ChassisMassKg') or
     (PropertyName = 'Wheelbase') or
     (PropertyName = 'TrackWidth') or
     (PropertyName = 'WheelRadius') or
     (PropertyName = 'SuspensionRestLength') or
     (PropertyName = 'SpringStiffness') or
     (PropertyName = 'SpringDamping') or
     (PropertyName = 'AntiRollStiffness') or
     (PropertyName = 'MaxSteerDeg') or
     (PropertyName = 'PeakTorqueNm') or
     (PropertyName = 'TireFrictionMu') or
     (PropertyName = 'AutoTransmission') or
     (PropertyName = 'SimulateInEditor') or
     (PropertyName = 'ChassisColorPersistent') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleWheeledVehicle.GetWheelTelemetry(const WheelIndex: Integer): TWheelTelemetry;
begin
  Result := FWheels[Clamped(WheelIndex, 0, 3)];
end;

function TCastleWheeledVehicle.GroundedWheelCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 3 do
    if FWheels[I].IsGrounded then
      Inc(Result);
end;

function TCastleWheeledVehicle.ForwardSpeedKmh: Single;
begin
  Result := FForwardSpeedMps * 3.6;
end;

function TCastleWheeledVehicle.VehicleSummaryBadge: String;
begin
  Result := Format('[Vehicle:%s %s %.0f km/h G%d %.0f RPM]', [
    DriveModeDisplayName(FDriveMode),
    PresetDisplayName(FPreset),
    ForwardSpeedKmh,
    FCurrentGear,
    FEngineRpm]);
end;

procedure TCastleWheeledVehicle.SetPreset(const Value: TVehiclePreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleWheeledVehicle.SetDriveMode(const Value: TVehicleDriveMode);
begin
  if FDriveMode <> Value then
  begin
    FDriveMode := Value;
    FPreset := vpCustom;
    InitWheelDefinitions;
  end;
end;

procedure TCastleWheeledVehicle.SetChassisMassKg(const Value: Single);
begin
  FChassisMassKg := Max(80.0, Value);
end;

procedure TCastleWheeledVehicle.SetWheelbase(const Value: Single);
begin
  FWheelbase := Max(0.4, Value);
  InitWheelDefinitions;
  RebuildVisualVehicle;
end;

procedure TCastleWheeledVehicle.SetTrackWidth(const Value: Single);
begin
  FTrackWidth := Max(0.4, Value);
  InitWheelDefinitions;
  RebuildVisualVehicle;
end;

procedure TCastleWheeledVehicle.SetWheelRadius(const Value: Single);
begin
  FWheelRadius := Max(0.08, Value);
  RebuildVisualVehicle;
end;

procedure TCastleWheeledVehicle.SetSuspensionRestLength(const Value: Single);
begin
  FSuspensionRestLength := Max(0.05, Value);
  SyncVisualWheels;
end;

procedure TCastleWheeledVehicle.SetSpringStiffness(const Value: Single);
begin
  FSpringStiffness := Max(500.0, Value);
end;

procedure TCastleWheeledVehicle.SetSpringDamping(const Value: Single);
begin
  FSpringDamping := Max(50.0, Value);
end;

procedure TCastleWheeledVehicle.SetMaxSteerDeg(const Value: Single);
begin
  FMaxSteerDeg := Clamped(Value, 1.0, 65.0);
end;

procedure TCastleWheeledVehicle.SetPeakTorqueNm(const Value: Single);
begin
  FPeakTorqueNm := Max(10.0, Value);
end;

procedure TCastleWheeledVehicle.SetTireFrictionMu(const Value: Single);
begin
  FTireFrictionMu := Clamped(Value, 0.05, 3.5);
end;

procedure TCastleWheeledVehicle.SetThrottleInput(const Value: Single);
begin
  FThrottleInput := Clamped(Value, -1.0, 1.0);
end;

procedure TCastleWheeledVehicle.SetSteerInput(const Value: Single);
var
  L, R: Single;
begin
  FSteerInput := Clamped(Value, -1.0, 1.0);
  ComputeAckermannWheelAnglesDeg(FSteerInput, FMaxSteerDeg, FWheelbase, FTrackWidth, L, R);
  FWheels[0].SteerAngleDeg := L;
  FWheels[1].SteerAngleDeg := R;
  SyncVisualWheels;
end;

procedure TCastleWheeledVehicle.SetBrakeInput(const Value: Single);
begin
  FBrakeInput := Clamped(Value, 0.0, 1.0);
end;

procedure TCastleWheeledVehicle.SetHandbrakeInput(const Value: Single);
begin
  FHandbrakeInput := Clamped(Value, 0.0, 1.0);
end;

procedure TCastleWheeledVehicle.SetCurrentGear(const Value: Integer);
begin
  FCurrentGear := Clamped(Value, 1, 6);
end;

procedure TCastleWheeledVehicle.SetChassisColor(const Value: TCastleColorRGB);
begin
  FChassisColor := Value;
  RebuildVisualVehicle;
end;

function TCastleWheeledVehicle.GetChassisColorForPersistent: TCastleColorRGB;
begin
  Result := FChassisColor;
end;

procedure TCastleWheeledVehicle.SetChassisColorForPersistent(const AValue: TCastleColorRGB);
begin
  ChassisColor := AValue;
end;

function TCastleWheeledVehicle.GetConfigJson: String;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('driveMode', Ord(FDriveMode));
    Root.Add('massKg', FChassisMassKg);
    Root.Add('wheelbase', FWheelbase);
    Root.Add('trackWidth', FTrackWidth);
    Root.Add('wheelRadius', FWheelRadius);
    Root.Add('suspRest', FSuspensionRestLength);
    Root.Add('springK', FSpringStiffness);
    Root.Add('springC', FSpringDamping);
    Root.Add('peakTorque', FPeakTorqueNm);
    Arr := TJSONArray.Create;
    for I := 1 to 6 do
      Arr.Add(FGearRatios[I]);
    Root.Add('gearRatios', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleWheeledVehicle.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TVehiclePreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TVehiclePreset))));
      FDriveMode := TVehicleDriveMode(Clamped(Root.Get('driveMode', Ord(FDriveMode)),
        0, Ord(High(TVehicleDriveMode))));
      FChassisMassKg := Max(80.0, Root.Get('massKg', FChassisMassKg));
      FWheelbase := Max(0.4, Root.Get('wheelbase', FWheelbase));
      FTrackWidth := Max(0.4, Root.Get('trackWidth', FTrackWidth));
      FWheelRadius := Max(0.08, Root.Get('wheelRadius', FWheelRadius));
      FSuspensionRestLength := Max(0.05, Root.Get('suspRest', FSuspensionRestLength));
      FSpringStiffness := Max(500.0, Root.Get('springK', FSpringStiffness));
      FSpringDamping := Max(50.0, Root.Get('springC', FSpringDamping));
      FPeakTorqueNm := Max(10.0, Root.Get('peakTorque', FPeakTorqueNm));
      Arr := Root.Find('gearRatios', jtArray) as TJSONArray;
      if Arr <> nil then
        for I := 0 to Min(5, Arr.Count - 1) do
          FGearRatios[I + 1] := Max(0.2, Arr.Floats[I]);
      InitWheelDefinitions;
      RebuildVisualVehicle;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleWheeledVehicle,
    ['Vehicles & Physics', 'Wheeled Vehicle (Raycast Suspension & Drivetrain)']);
end.
