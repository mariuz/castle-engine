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

{ Automated tests for Phase 398: Multi-Leg Quadruped / Hexapod / Spider Gait
  Phase, WorldRay Slope Foot-Plant & Body Tilt Studio. }
unit TestToolQuadrupedGait;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolQuadrupedGait = class(TCastleTestCase)
  published
    procedure TestStaticStabilityPolygonDutyFactorAndSteppedLedgeBodyPitch;
    procedure TestParabolicSwingApexOctopod8LegPresetAndTransientCleanJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleQuadrupedGait, ToolQuadrupedGait;

procedure TTestToolQuadrupedGait.TestStaticStabilityPolygonDutyFactorAndSteppedLedgeBodyPitch;
var
  Root: TComponent;
  VP: TCastleViewport;
  Rig: TCastleMultiLegGaitRig;
  StepIdx: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TQuadrupedGaitHelper.SpawnSteppedRampGaitDemo(Root, Root, Rig));

    { 1. Across all 20 gait phase samples in [0..1), 6-leg tripod with DutyFactor >= 0.56
         ALWAYS maintains >= 3 grounded legs (tripod static stability)! }
    for StepIdx := 0 to 19 do
    begin
      Rig.EvaluateAtNormalizedCycle(VP.Items, StepIdx / 20.0);
      AssertTrue('Hexapod tripod keeps >= 3 legs grounded at every phase',
        Rig.GroundedLegCount >= 3);
    end;

    { 2. Front legs planted on GaitFrontElevatedRock (Y = +0.42m) while rear legs
         stand on GaitRearGroundSlab (Y = 0.0m) tilt BodyPitchDeg nose-up (> +5 deg)! }
    AssertTrue('Elevated front rock ledge tilts body nose-up',
      Rig.BodyPitchDeg > 5.0);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolQuadrupedGait.TestParabolicSwingApexOctopod8LegPresetAndTransientCleanJson;
var
  Rig, Restored: TCastleMultiLegGaitRig;
  LegStance, LegSwingMid: TLegFootSample;
  SerializedScene, JsonCfg, Md: String;
begin
  Rig := TCastleMultiLegGaitRig.Create(nil);
  Restored := TCastleMultiLegGaitRig.Create(nil);
  try
    Rig.ApplyPreset(mgpCanineDiagonalTrot4Leg);
    { Leg 0 has PhaseOffset = 0.0, DutyFactor = 0.58:
      - at Cycle = 0.20 -> grounded in stance (FootY = GroundY)
      - at Cycle = 0.79 (exact midpoint of [0.58..1.00] swing) -> apex lift = SwingStepHeightMeters! }
    Rig.EvaluateAtNormalizedCycle(nil, 0.20);
    LegStance := Rig.GetLegSample(0);
    AssertTrue(LegStance.IsStanceGrounded);
    AssertSameValue(LegStance.GroundElevationY, LegStance.FootWorldPos.Y, 0.001);

    Rig.EvaluateAtNormalizedCycle(nil, 0.79);
    LegSwingMid := Rig.GetLegSample(0);
    AssertFalse(LegSwingMid.IsStanceGrounded);
    AssertSameValue(LegSwingMid.GroundElevationY + Rig.SwingStepHeightMeters,
      LegSwingMid.FootWorldPos.Y, 0.005);

    { 8-leg arachnid preset }
    Rig.ApplyPreset(mgpArachnidOctopod8Leg);
    AssertEquals(8, Rig.LegCount);
    AssertTrue(Rig.GroundedLegCount >= 4);

    SerializedScene := ComponentToString(Rig);
    AssertTrue(Pos('MultiLegGaitPreview', SerializedScene) = 0);

    Rig.MoveSpeedMps := 3.8;
    JsonCfg := TQuadrupedGaitHelper.ExportRigJson(Rig);
    AssertTrue(TQuadrupedGaitHelper.ImportRigJson(Restored, JsonCfg));
    AssertEquals(8, Restored.LegCount);
    AssertSameValue(3.8, Restored.MoveSpeedMps, 0.01);
    Md := TQuadrupedGaitHelper.GenerateMarkdownReport(Rig);
    AssertTrue(Pos('ArachnidOctopod8Leg', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Rig);
  end;
end;

initialization
  RegisterTest(TTestToolQuadrupedGait);

end.
