{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 344 Secondary-Motion Jiggle Bone Springs,
  Inertial Whip, Gravity Sag, Damping Oscillation & Spherical Cone Clamping. }
unit TestToolJiggleBone;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolJiggleBone = class(TCastleTestCase)
  published
    procedure TestParentImpulseWhipSphericalConeClampAndUnderVsCriticallyDampedSettle;
    procedure TestGravitySagCharacterDemoAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleJiggleBone, ToolJiggleBone;

procedure TTestToolJiggleBone.TestParentImpulseWhipSphericalConeClampAndUnderVsCriticallyDampedSettle;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  MountA, MountB: TCastleTransform;
  UnderSpring, CritSpring: TCastleJiggleBoneBehavior;
  ClampedDeg: Single;
  I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    MountA := TCastleTransform.Create(DesignOwner);
    MountA.Name := 'UnderDampedMount';
    Vp.Items.Add(MountA);

    UnderSpring := TCastleJiggleBoneBehavior.Create(DesignOwner);
    UnderSpring.Name := 'UnderSpring';
    UnderSpring.BoneLength := 0.80;
    UnderSpring.Stiffness := 160.0;
    UnderSpring.DampingRatio := 0.16;
    UnderSpring.GravityFactor := 0.0;
    UnderSpring.MaxConeAngleDeg := 30.0;
    MountA.AddBehavior(UnderSpring);
    UnderSpring.ResetSpringToRest;

    MountB := TCastleTransform.Create(DesignOwner);
    MountB.Name := 'CritDampedMount';
    Vp.Items.Add(MountB);

    CritSpring := TCastleJiggleBoneBehavior.Create(DesignOwner);
    CritSpring.Name := 'CritSpring';
    CritSpring.BoneLength := 0.80;
    CritSpring.Stiffness := 160.0;
    CritSpring.DampingRatio := 1.05;
    CritSpring.GravityFactor := 0.0;
    CritSpring.MaxConeAngleDeg := 30.0;
    MountB.AddBehavior(CritSpring);
    CritSpring.ResetSpringToRest;

    { 1. Direct cone clamp maps an 80-deg deflection onto exact 30.0-deg cone rim;
         violent +5.0m dodge step in 1/60s whips both springs > 20 deg while clamping <= 30.0 deg }
    ClampDirectionToCone(Vector3(-5.0, 0.80, 0.0), Vector3(0.0, 1.0, 0.0), 30.0, ClampedDeg);
    AssertSameValue(30.0, ClampedDeg, 0.01);

    MountA.Translation := Vector3(5.0, 0.0, 0.0);
    MountB.Translation := Vector3(5.0, 0.0, 0.0);
    UnderSpring.StepSpring(1.0 / 60.0);
    CritSpring.StepSpring(1.0 / 60.0);

    AssertTrue((UnderSpring.CurrentDeflectionDeg > 20.0) and (UnderSpring.CurrentDeflectionDeg <= 30.05));
    AssertTrue((CritSpring.CurrentDeflectionDeg > 20.0) and (CritSpring.CurrentDeflectionDeg <= 30.05));
    AssertSameValue(0.80, PointsDistance(UnderSpring.PivotWorld, UnderSpring.CurrentTipWorld), 0.001);
    AssertSameValue(0.80, PointsDistance(CritSpring.PivotWorld, CritSpring.CurrentTipWorld), 0.001);

    { 2. Step 2.5s: both converge to rest (< 0.5 deg), under-damped rings while critically-damped settles }
    for I := 1 to 150 do
    begin
      UnderSpring.StepSpring(1.0 / 60.0);
      CritSpring.StepSpring(1.0 / 60.0);
    end;

    AssertTrue(UnderSpring.CurrentDeflectionDeg < 0.5);
    AssertTrue(CritSpring.CurrentDeflectionDeg < 0.5);
    AssertTrue(UnderSpring.OscillationReversals >= 3);
    AssertTrue(UnderSpring.OscillationReversals > CritSpring.OscillationReversals + 1);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolJiggleBone.TestGravitySagCharacterDemoAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Carrier, TailMount: TCastleTransform;
  TailSpring, RestoredSpring: TCastleJiggleBoneBehavior;
  I: Integer;
  Warnings: TStringList;
  Sum: TJiggleBoneStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TJiggleBoneHelper.SpawnCharacterJiggleRigDemo(Vp, DesignOwner, Carrier));

    { 1. Horizontal +Z tail with GravityFactor = 1.2 sags downward (-Y) within cone }
    TailMount := TCastleTransform.Create(DesignOwner);
    TailMount.Name := 'HorizontalTail';
    TailMount.Translation := Vector3(0.0, 1.2, -0.3);
    Vp.Items.Add(TailMount);

    TailSpring := TCastleJiggleBoneBehavior.Create(DesignOwner);
    TailSpring.Name := 'TailSpring';
    TailSpring.LocalRestAxis := Vector3(0.0, 0.0, -1.0);
    TailSpring.BoneLength := 0.90;
    TailSpring.Stiffness := 45.0;
    TailSpring.DampingRatio := 0.80;
    TailSpring.GravityFactor := 1.20;
    TailSpring.MaxConeAngleDeg := 40.0;
    TailMount.AddBehavior(TailSpring);
    TailSpring.ResetSpringToRest;

    for I := 1 to 90 do
      TailSpring.StepSpring(1.0 / 60.0);

    AssertTrue(TailSpring.CurrentTipWorld.Y < TailSpring.PivotWorld.Y - 0.12);
    AssertTrue(TailSpring.CurrentDeflectionDeg <= 40.1);
    AssertSameValue(0.90, PointsDistance(TailSpring.PivotWorld, TailSpring.CurrentTipWorld), 0.001);

    Sum := TJiggleBoneHelper.CollectSummary(Vp, Warnings);
    AssertEquals(4, Sum.JiggleBehaviorCount);
    ReportMd := TJiggleBoneHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Secondary-Motion Jiggle Bone Springs Report', ReportMd) > 0);

    { 2. JSON roundtrip preserving custom Stiffness, DampingRatio & MaxConeAngleDeg }
    JsonStr := ComponentToString(TailSpring);
    RestoredSpring := StringToComponent(JsonStr, RestoredOwner) as TCastleJiggleBoneBehavior;
    AssertTrue(RestoredSpring <> nil);
    AssertTrue(RestoredSpring.Preset = jspCustom);
    AssertSameValue(45.0, RestoredSpring.Stiffness, 0.01);
    AssertSameValue(0.80, RestoredSpring.DampingRatio, 0.01);
    AssertSameValue(40.0, RestoredSpring.MaxConeAngleDeg, 0.01);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolJiggleBone);

end.
