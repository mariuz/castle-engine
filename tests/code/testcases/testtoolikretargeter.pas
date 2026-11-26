{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 387: Skeletal IK Retargeter
  (UIKRetargeter & UIKRigDefinition Parity: 7-Chain Humanoid Mapping, T-Pose <->
  A-Pose Reference Delta Compensation, Pelvis-Height Proportional Stride
  Scaling, Analytical 2-Bone Foot/Hand IK Goal Planting with Exact Limb Length
  Preservation, 107-Studio Hub & 30th MCP Tool cge_retarget_ik_skeleton). }
unit TestToolIkRetargeter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolIkRetargeter = class(TCastleTestCase)
  published
    procedure TestTPoseToAPoseReferenceDeltaCompensationStrideScalingAndCleanJsonRoundtrip;
    procedure TestBruteOgreUpscaledStrideAndCustomTwoHandedPropIkGoalPinning;
    procedure TestUnified107StudioHubAnd30thMcpRetargetIkSkeletonTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleIkRetargeter, ToolIkRetargeter, ToolStudioHub, ToolMcpServer;

procedure TTestToolIkRetargeter.TestTPoseToAPoseReferenceDeltaCompensationStrideScalingAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Rtg, LoadedRtg: TCastleIkRetargeter;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Rtg := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
      VP, Root, irpMannequinToCompactAPose, Vector3(0, 0, 0));
    AssertTrue(Rtg <> nil);
    AssertSameValue(0.64, Rtg.PelvisHeightScaleRatio, 1e-3);

    { 1. T-Pose (0 deg) -> Compact A-Pose (-35 deg) Reference Delta Compensation:
         In irmNeutralStandCheck, Source arms are at -45 deg world elevation.
         With CompensateRefPoseDelta = True, Target world arm elevation matches -45 deg!
         Without CompensateRefPoseDelta, Target drops to -35 + (-45) = -80 deg (clipping into hip)! }
    Rtg.MotionClip := irmNeutralStandCheck;
    Rtg.CompensateRefPoseDelta := True;
    Rtg.EvaluateRetargetAtTime(0.0);
    AssertSameValue(-45.0, Rtg.SourcePose.LeftArmWorldElevDeg, 1e-3);
    AssertSameValue(-45.0, Rtg.TargetPose.LeftArmWorldElevDeg, 1e-3);

    Rtg.CompensateRefPoseDelta := False;
    AssertSameValue(-80.0, Rtg.TargetPose.LeftArmWorldElevDeg, 1e-3);
    Rtg.CompensateRefPoseDelta := True;

    { 2. Forward Stride Scaling (1.00m -> 0.64m Pelvis) + Zero-Skate Planted Foot IK:
         At t=0.20s in irmForwardStrideWalk, Source PelvisZ = 0.20 * 1.60 = 0.320m ->
         Target PelvisZ = 0.320 * 0.64 = 0.2048m, LeftFoot planted on floor (Y = 0.0),
         RightFoot swinging above floor (Y > 0.05), and all 8 limb segments preserve exact rest lengths! }
    Rtg.MotionClip := irmForwardStrideWalk;
    Rtg.EvaluateRetargetAtTime(0.20);
    AssertSameValue(0.320, Rtg.SourcePose.JointPos[ihjPelvis].Z, 1e-3);
    AssertSameValue(0.2048, Rtg.TargetPose.JointPos[ihjPelvis].Z, 1e-3);
    AssertTrue(Rtg.TargetPose.LeftFootPlanted);
    AssertSameValue(0.0, Rtg.TargetPose.JointPos[ihjFootL].Y, 1e-3);
    AssertTrue('Swinging right foot clears floor proportionally',
      Rtg.TargetPose.JointPos[ihjFootR].Y > 0.05);
    AssertTrue('All 8 target arm/leg segments preserve exact bone lengths (< 1mm drift)',
      Rtg.MaxTargetLimbLengthError < 1e-3);

    { 3. SetTransient-clean JSON serialization roundtrip }
    Rtg.SetChainStrideScale(ircPelvisRoot, 1.15);
    JsonStr := ComponentToString(Rtg);
    AssertTrue('SetTransient IKRetarget_Preview must not leak into serialized JSON',
      Pos('IKRetarget_Preview', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedRtg := StringToComponent(JsonStr, LoadOwner) as TCastleIkRetargeter;
      AssertTrue(LoadedRtg <> nil);
      AssertEquals(7, Length(LoadedRtg.Chains));
      AssertSameValue(1.15, LoadedRtg.GetChainConfig(ircPelvisRoot).StrideScale, 1e-3);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolIkRetargeter.TestBruteOgreUpscaledStrideAndCustomTwoHandedPropIkGoalPinning;
var
  Root: TComponent;
  VP: TCastleViewport;
  OgreRtg, GripRtg: TCastleIkRetargeter;
  PropGoal: TVector3;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    { 1. Tall Brute Ogre (PelvisHeight = 1.32m) scales forward stride up by 1.32x }
    OgreRtg := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
      VP, Root, irpMannequinToBruteOgre, Vector3(0, 0, 0));
    OgreRtg.EvaluateRetargetAtTime(0.25);
    AssertSameValue(0.400, OgreRtg.SourcePose.JointPos[ihjPelvis].Z, 1e-3);
    AssertSameValue(0.528, OgreRtg.TargetPose.JointPos[ihjPelvis].Z, 1e-3);
    AssertTrue(OgreRtg.MaxTargetLimbLengthError < 1e-3);

    { 2. Reachable Custom Hand IK Goal pins Hand_R within < 1mm while preserving exact arm bone lengths }
    GripRtg := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
      VP, Root, irpTwoHandedGripIkRetarget, Vector3(3, 0, 0));
    PropGoal := GripRtg.TargetPose.JointPos[ihjShoulderR] + Vector3(-0.08, -0.18, 0.24);
    GripRtg.SetChainIkBlend(ircRightArm, 1.0, True, PropGoal);
    AssertTrue('Right hand IK pinned directly onto reachable two-handed prop grip',
      (GripRtg.TargetPose.JointPos[ihjHandR] - PropGoal).Length < 1e-3);
    AssertTrue(GripRtg.MaxTargetLimbLengthError < 1e-3);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolIkRetargeter.TestUnified107StudioHubAnd30thMcpRetargetIkSkeletonTool;
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify 107 UE Studios in Studio Hub (Phase 387 ik_retargeter) }
  AssertEquals(114, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('ik_retargeter', Entry));
  AssertEquals(387, Entry.PhaseNumber);

  { 2. Verify 30th MCP tool cge_retarget_ik_skeleton }
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Srv := TCastleMcpServer.Create(Root);
    Srv.AutonomyMode := mamEditWithUndo;
    Srv.StandaloneDesignRoot := VP;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    OuterJson := GetJSON(ListResp);
    try
      ToolsArr := OuterJson.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(37, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_retarget_ik_skeleton","arguments":{"action":"spawn_preset","preset":"two_hand_ik"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['retargeterCount']);
        AssertEquals(7, PayloadObj.Integers['totalMappedChains']);
        AssertEquals(4, PayloadObj.Integers['ikEnabledChainCount']);
        AssertEquals(114, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolIkRetargeter);
end.
