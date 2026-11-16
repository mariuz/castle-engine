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

{ Stateless Editor & Headless Helper for Chaos-Style Wheeled Vehicles,
  Test-Track Spawning, Multi-Vehicle Stepping, Suspension Sag Auditing &
  Markdown Telemetry Export (@link(TVehicleStudioHelper), @link(TVehicleAuditReport))
  (Phase 317 — UE 6.0+ Chaos Vehicles Parity). }
unit ToolVehicleStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleVehicleSystem;

type
  TVehicleArray = array of TCastleWheeledVehicle;

  { Summary & suspension/drivetrain QA report across all wheeled vehicles in a design. }
  TVehicleAuditReport = class
  public
    VehicleCount: Integer;
    GroundedVehicleCount: Integer;
    TotalGroundedWheels: Integer;
    MaxSpeedKmh: Single;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for spawning, stepping, and auditing @link(TCastleWheeledVehicle)
    instances inside @code(castle-editor) or headless @code(CastleTester) suites. }
  TVehicleStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanVehicles(const RootComp, DesignOwner: TComponent;
      out OutVehicles: TVehicleArray); static;

    class function SpawnVehicleInDesign(const RootComp, DesignOwner: TComponent;
      const APreset: TVehiclePreset; const AWorldPos: TVector3): TCastleWheeledVehicle; static;

    class procedure SpawnTestTrackFloorAndRamp(
      const RootComp, DesignOwner: TComponent); static;

    class procedure StepAllVehicles(const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function AuditVehicles(const RootComp, DesignOwner: TComponent): TVehicleAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  Math,
  CastleColors, CastleScene;

{ TVehicleAuditReport -------------------------------------------------------- }

constructor TVehicleAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TVehicleAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TVehicleStudioHelper ------------------------------------------------------- }

class function TVehicleStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
  if RootComp is TCastleTransform then
    Exit(nil);
end;

class procedure TVehicleStudioHelper.ScanVehicles(
  const RootComp, DesignOwner: TComponent; out OutVehicles: TVehicleArray);

  procedure AddUnique(const V: TCastleWheeledVehicle);
  var
    K: Integer;
  begin
    if (V = nil) or (csTransient in V.ComponentStyle) then
      Exit;
    for K := 0 to High(OutVehicles) do
      if OutVehicles[K] = V then
        Exit;
    SetLength(OutVehicles, Length(OutVehicles) + 1);
    OutVehicles[High(OutVehicles)] := V;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleWheeledVehicle then
      AddUnique(TCastleWheeledVehicle(C));
    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutVehicles := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class function TVehicleStudioHelper.SpawnVehicleInDesign(
  const RootComp, DesignOwner: TComponent;
  const APreset: TVehiclePreset;
  const AWorldPos: TVector3): TCastleWheeledVehicle;
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  BaseName: String;
  Idx: Integer;
begin
  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit(nil);

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  case APreset of
    vpOffroadMonsterTruck: BaseName := 'MonsterTruck';
    vpArmoredReconBuggy:   BaseName := 'ReconBuggy';
    else                   BaseName := 'RallySportsCar';
  end;
  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent(BaseName + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  Result := TCastleWheeledVehicle.Create(OwnerToUse);
  Result.Name := BaseName + IntToStr(Idx);
  Result.ApplyPreset(APreset);
  Result.Translation := AWorldPos +
    Vector3(0.0, Result.SuspensionRestLength + Result.WheelRadius * 0.92, 0.0);
  ParentTrans.Add(Result);
end;

class procedure TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(
  const RootComp, DesignOwner: TComponent);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  FloorBox, RampBox: TCastleBox;
begin
  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  if (OwnerToUse = nil) or (OwnerToUse.FindComponent('VehicleTestTrackFloor') = nil) then
  begin
    FloorBox := TCastleBox.Create(OwnerToUse);
    FloorBox.Name := 'VehicleTestTrackFloor';
    FloorBox.Size := Vector3(140.0, 1.0, 220.0);
    FloorBox.Translation := Vector3(0.0, -0.5, -40.0);
    FloorBox.Color := Vector4(0.24, 0.26, 0.29, 1.0);
    ParentTrans.Add(FloorBox);
  end;

  if (OwnerToUse = nil) or (OwnerToUse.FindComponent('VehicleTestJumpRamp') = nil) then
  begin
    RampBox := TCastleBox.Create(OwnerToUse);
    RampBox.Name := 'VehicleTestJumpRamp';
    RampBox.Size := Vector3(6.5, 0.6, 12.0);
    RampBox.Translation := Vector3(0.0, 0.85, -16.0);
    RampBox.Rotation := Vector4(1.0, 0.0, 0.0, DegToRad(12.0));
    RampBox.Color := Vector4(0.84, 0.56, 0.18, 1.0);
    ParentTrans.Add(RampBox);
  end;
end;

class procedure TVehicleStudioHelper.StepAllVehicles(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Vehicles: TVehicleArray;
  I: Integer;
begin
  ScanVehicles(RootComp, DesignOwner, Vehicles);
  for I := 0 to High(Vehicles) do
    Vehicles[I].StepVehicle(Dt);
end;

class function TVehicleStudioHelper.AuditVehicles(
  const RootComp, DesignOwner: TComponent): TVehicleAuditReport;
var
  Vehicles: TVehicleArray;
  V: TCastleWheeledVehicle;
  I, GW: Integer;
  StaticSagPerWheel: Single;
begin
  Result := TVehicleAuditReport.Create;
  ScanVehicles(RootComp, DesignOwner, Vehicles);
  Result.VehicleCount := Length(Vehicles);

  for I := 0 to High(Vehicles) do
  begin
    V := Vehicles[I];
    GW := V.GroundedWheelCount;
    Result.TotalGroundedWheels := Result.TotalGroundedWheels + GW;
    if GW > 0 then
      Inc(Result.GroundedVehicleCount);
    Result.MaxSpeedKmh := Max(Result.MaxSpeedKmh, Abs(V.ForwardSpeedKmh));

    { Static Hooke sag check: (Mass * g / 4) / SpringStiffness vs SuspensionRestLength }
    StaticSagPerWheel := (V.ChassisMassKg * 9.81 * 0.25) / Max(1.0, V.SpringStiffness);
    if StaticSagPerWheel > V.SuspensionRestLength * 0.85 then
      Result.Warnings.Add(Format(
        'Vehicle "%s" static suspension sag (%.2fm) exceeds 85%% of SuspensionRestLength (%.2fm) — springs will bottom out; increase SpringStiffness or SuspensionRestLength.',
        [V.Name, StaticSagPerWheel, V.SuspensionRestLength]));

    if (GW = 0) and (not V.UseFlatGroundFallback) and (V.Translation.Y < -10.0) then
      Result.Warnings.Add(Format(
        'Vehicle "%s" is airborne below Y = -10m with 0 grounded wheels — spawn a floor collider or enable UseFlatGroundFallback.',
        [V.Name]));
  end;
end;

class function TVehicleStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Vehicles: TVehicleArray;
  Rep: TVehicleAuditReport;
  SB: TStringBuilder;
  V: TCastleWheeledVehicle;
  W0, W1: TWheelTelemetry;
  I: Integer;
begin
  ScanVehicles(RootComp, DesignOwner, Vehicles);
  Rep := AuditVehicles(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Wheeled Vehicle, Suspension & Drivetrain Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Vehicles in Design:** %d (`%d` grounded, `%d` total grounded wheels)',
      [Rep.VehicleCount, Rep.GroundedVehicleCount, Rep.TotalGroundedWheels]));
    SB.AppendLine(Format('- **Peak Recorded Speed:** %.1f km/h', [Rep.MaxSpeedKmh]));
    SB.AppendLine('');
    SB.AppendLine('| Vehicle | Preset | Drive | Speed (km/h) | Gear / RPM | Front Steer L/R | Grounded Wheels |');
    SB.AppendLine('| :--- | :--- | :---: | :---: | :---: | :---: | :---: |');
    for I := 0 to High(Vehicles) do
    begin
      V := Vehicles[I];
      W0 := V.GetWheelTelemetry(0);
      W1 := V.GetWheelTelemetry(1);
      SB.AppendLine(Format('| `%s` | %s | %s | %.1f | G%d / %.0f RPM | %.1f° / %.1f° | %d / 4 |',
        [V.Name, TCastleWheeledVehicle.PresetDisplayName(V.Preset),
         TCastleWheeledVehicle.DriveModeDisplayName(V.DriveMode),
         V.ForwardSpeedKmh, V.CurrentGear, V.EngineRpm,
         W0.SteerAngleDeg, W1.SteerAngleDeg, V.GroundedWheelCount]));
    end;
    if Rep.Warnings.Count > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('## Suspension & Drivetrain QA Warnings');
      for I := 0 to Rep.Warnings.Count - 1 do
        SB.AppendLine('- ' + Rep.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
