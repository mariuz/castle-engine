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

{ Automated tests for Phase 383: Animation Blueprint Editor (UAnimBlueprint
  Parity: AnimGraph StateMachine, Save/Use Cached Pose Single-Evaluation,
  Layered Blend Per Bone Upper/Lower Body Isolation, Two-Bone Foot IK,
  Frame-Accurate Looping AnimNotify & AnimNotifyState [Begin/Tick/End] Tracks,
  103-Studio Hub & 26th MCP Tool cge_evaluate_anim_blueprint). }
unit TestToolAnimBlueprint;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolAnimBlueprint = class(TCastleTestCase)
  published
    procedure TestLayeredBlendPerBoneUpperBodyIsolationCachedPoseAndCleanJsonRoundtrip;
    procedure TestFrameAccurateLoopingAnimNotifyAndNotifyStateBeginTickEndTransitions;
    procedure TestUnified103StudioHubAnd26thMcpEvaluateAnimBlueprintTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleAnimBlueprint, ToolAnimBlueprint, ToolStudioHub, ToolMcpServer;

procedure TTestToolAnimBlueprint.TestLayeredBlendPerBoneUpperBodyIsolationCachedPoseAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Abp, LoadedAbp: TCastleAnimBlueprint;
  PosePureSprint, PoseSprintPlusAim: TAnimPose;
  SaveNodeIdx: Integer;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Abp := TAnimBlueprintHelper.SpawnAnimBlueprintPresetInDesign(
      VP, Root, abpLocomotionUpperBodyAimAndFootIk, Vector3(0, 0, 0));
    AssertTrue(Abp <> nil);
    AssertTrue(Abp.LastEvaluationValid);
    AssertEquals('Locomotion', Abp.ActiveLocomotionState);

    { 1. Compare UpperBodyAimWeight = 0.0 (pure sprint) vs. 1.0 (sprint legs + rifle-aim upper body) }
    Abp.ResetPlayback;
    Abp.SpeedMps := 6.0;
    Abp.UpperBodyAimWeight := 0.0;
    AssertTrue(Abp.StepAnimBlueprint(0.25));
    PosePureSprint := Abp.CurrentPose;

    Abp.ResetPlayback;
    Abp.SpeedMps := 6.0;
    Abp.UpperBodyAimWeight := 1.0;
    AssertTrue(Abp.StepAnimBlueprint(0.25));
    PoseSprintPlusAim := Abp.CurrentPose;

    { Lower-body leg swing (+48 deg pitch at t=0.25s) + +0.06m LeftFoot IK must remain IDENTICAL! }
    AssertVectorEquals(PosePureSprint.Bones[absLeftLeg].EulerDeg,
      PoseSprintPlusAim.Bones[absLeftLeg].EulerDeg, 1e-4);
    AssertVectorEquals(PosePureSprint.Bones[absRightLeg].EulerDeg,
      PoseSprintPlusAim.Bones[absRightLeg].EulerDeg, 1e-4);
    AssertSameValue(0.54, PoseSprintPlusAim.Bones[absLeftLeg].LocalOffset.Y, 1e-3);

    { Upper-body right arm & upper spine MUST switch to the aimed rifle pose (-75 deg pitch, +25 deg yaw)! }
    AssertSameValue(-75.0, PoseSprintPlusAim.Bones[absRightArm].EulerDeg.X, 1e-3);
    AssertSameValue(25.0, PoseSprintPlusAim.Bones[absSpineUpper].EulerDeg.Y, 1e-3);
    AssertTrue(Abs(PosePureSprint.Bones[absRightArm].EulerDeg.X -
      PoseSprintPlusAim.Bones[absRightArm].EulerDeg.X) > 90.0);

    { 2. SaveCachedPose node evaluated exactly ONCE during tick }
    SaveNodeIdx := Abp.FindNodeIndex('Save_LocoCache');
    AssertTrue(SaveNodeIdx >= 0);
    AssertEquals(1, Abp.Nodes[SaveNodeIdx].EvalCountThisTick);

    { 3. StateMachine JumpAir transition }
    Abp.IsInAir := True;
    AssertTrue(Abp.StepAnimBlueprint(0.0));
    AssertEquals('JumpAir', Abp.ActiveLocomotionState);
    AssertSameValue(1.18, Abp.CurrentPose.Bones[absPelvis].LocalOffset.Y, 1e-3);

    { 4. SetTransient-clean JSON roundtrip }
    Abp.IsInAir := False;
    Abp.SpeedMps := 4.25;
    JsonStr := ComponentToString(Abp);
    AssertTrue('SetTransient Bone_Pelvis must not leak into serialized JSON',
      Pos('Bone_Pelvis', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedAbp := StringToComponent(JsonStr, LoadOwner) as TCastleAnimBlueprint;
      AssertTrue(LoadedAbp <> nil);
      AssertSameValue(4.25, LoadedAbp.SpeedMps, 1e-3);
      AssertEquals(Length(Abp.Nodes), Length(LoadedAbp.Nodes));
      AssertEquals(Length(Abp.Notifies), Length(LoadedAbp.Notifies));
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolAnimBlueprint.TestFrameAccurateLoopingAnimNotifyAndNotifyStateBeginTickEndTransitions;
var
  Root: TComponent;
  VP: TCastleViewport;
  Abp, BadAbp: TCastleAnimBlueprint;
  N: TAnimGraphNode;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Abp := TAnimBlueprintHelper.SpawnAnimBlueprintPresetInDesign(
      VP, Root, abpLocomotionUpperBodyAimAndFootIk, Vector3(0, 0, 0));
    Abp.ResetPlayback;
    Abp.SpeedMps := 6.0;

    { Presets on ackSprintForward:
      - Footstep_L instant @ 0.25s
      - Footstep_R instant @ 0.75s
      - WeaponHitboxActive state [0.20s .. 0.55s] }

    { Step 0.00 -> 0.30s: crosses Footstep_L (0.25s) AND enters WeaponHitboxActive [0.20..0.55]! }
    AssertTrue(Abp.StepAnimBlueprint(0.30));
    AssertTrue(Abp.TriggeredNotifies.IndexOf('NOTIFY:Footstep_L') >= 0);
    AssertTrue(Abp.TriggeredNotifies.IndexOf('STATE_BEGIN:WeaponHitboxActive') >= 0);

    { Step 0.30 -> 0.45s: stays inside WeaponHitboxActive -> STATE_TICK! }
    AssertTrue(Abp.StepAnimBlueprint(0.15));
    AssertTrue(Abp.TriggeredNotifies.IndexOf('STATE_TICK:WeaponHitboxActive') >= 0);

    { Step 0.45 -> 0.80s: exits WeaponHitboxActive (> 0.55s -> STATE_END) AND crosses Footstep_R (0.75s)! }
    AssertTrue(Abp.StepAnimBlueprint(0.35));
    AssertTrue(Abp.TriggeredNotifies.IndexOf('STATE_END:WeaponHitboxActive') >= 0);
    AssertTrue(Abp.TriggeredNotifies.IndexOf('NOTIFY:Footstep_R') >= 0);

    { Loop wraparound 0.80 -> 1.30s (wraps to 0.30s): crosses Footstep_L (0.25s) a 2nd time! }
    Abp.TriggeredNotifies.Clear;
    AssertTrue(Abp.StepAnimBlueprint(0.50));
    AssertTrue('Loop wraparound across 1.00s -> 0.30s must fire Footstep_L at 0.25s',
      Abp.TriggeredNotifies.IndexOf('NOTIFY:Footstep_L') >= 0);

    { Validation catches missing OutputPose & undeclared CachedPose }
    BadAbp := TCastleAnimBlueprint.Create(Root);
    BadAbp.ClearAll;
    N := TCastleAnimBlueprint.MakeDefaultNode('BadUse', ankUseCachedPose, 20, 20);
    N.CachePoseName := 'GhostCache';
    BadAbp.AddOrUpdateNode(N);
    AssertFalse(BadAbp.ValidateAnimGraph);
    AssertFalse(BadAbp.StepAnimBlueprint(0.1));
    AssertEquals(2, BadAbp.ValidationErrors.Count);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolAnimBlueprint.TestUnified103StudioHubAnd26thMcpEvaluateAnimBlueprintTool;
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
  { 1. Verify 103 UE Studios in Studio Hub (Phase 383 anim_blueprint) }
  AssertEquals(107, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('anim_blueprint', Entry));
  AssertEquals(383, Entry.PhaseNumber);

  { 2. Verify 26th MCP tool cge_evaluate_anim_blueprint }
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
      AssertEquals(30, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_evaluate_anim_blueprint","arguments":{"action":"spawn_preset","preset":"loco_aim_ik"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['animBpCount']);
        AssertEquals(1, PayloadObj.Integers['validCount']);
        AssertEquals(7, PayloadObj.Integers['totalPoseNodeCount']);
        AssertEquals(107, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_evaluate_anim_blueprint","arguments":{"action":"step_pose","deltaSec":0.30}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertTrue(PayloadObj.Integers['totalTriggeredNotifies'] >= 2);
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
  RegisterTest(TTestToolAnimBlueprint);
end.
