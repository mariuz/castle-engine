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

{ Automated tests for Phase 395: Blueprint Components Viewport & Inherited
  Subobject Tree (UE 5.5 USimpleConstructionScript / USCS_Node &
  UInheritableComponentHandler Parity: Parent->Child Blueprint Component
  Inheritance, Non-Deletable [Inherited] Guard, Child Subobject Attachment onto
  Inherited Parent Nodes, SpringArm->Camera Boom Kinematics, Delta Overrides &
  Revert-to-Parent, 115-Studio Hub & 38th MCP Tool cge_assemble_blueprint_components). }
unit TestToolBlueprintScs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolBlueprintScs = class(TCastleTestCase)
  published
    procedure TestParentChildScsInheritanceDeletionGuardAndCycleProtection;
    procedure TestSpringArmBoomKinematicsDeltaOverrideRevertAndCleanJsonRoundtrip;
    procedure TestUnified115StudioHubAnd38thMcpAssembleBlueprintComponentsTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleBlueprintScs, ToolBlueprintScs, ToolStudioHub, ToolMcpServer;

procedure TTestToolBlueprintScs.TestParentChildScsInheritanceDeletionGuardAndCycleProtection;
var
  Root: TComponent;
  VP: TCastleViewport;
  BaseBp, ChildBp: TCastleBlueprintScsActor;
  SwordIdx: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    AssertEquals(2, TBlueprintScsHelper.SpawnParentAndChildBlueprintShowcaseInDesign(
      VP, Root, BaseBp, ChildBp));
    AssertTrue((BaseBp <> nil) and (ChildBp <> nil));

    { 1. Cycle protection prevents BaseBp.ParentBlueprintScs := ChildBp }
    BaseBp.ParentBlueprintScs := ChildBp;
    AssertTrue(BaseBp.ParentBlueprintScs = nil);

    { 2. BaseBp has 4 USCS_Nodes; ChildBp adds 3 local nodes -> 7 assembled (4 Inherited, 2 Overridden)! }
    AssertEquals(4, Length(BaseBp.Assembled));
    AssertEquals(7, Length(ChildBp.Assembled));
    AssertEquals(4, ChildBp.InheritedComponentCount);
    AssertEquals(2, ChildBp.OverriddenInheritedCount);

    { 3. Child SCS node GreatSword_R attaches onto [Inherited] CharacterMesh0 at TreeDepth = 2! }
    SwordIdx := ChildBp.FindAssembledIndex('GreatSword_R');
    AssertTrue(SwordIdx >= 0);
    AssertFalse(ChildBp.Assembled[SwordIdx].IsInherited);
    AssertEquals(2, ChildBp.Assembled[SwordIdx].TreeDepth);

    { 4. UE 5.5 Rule: [Inherited] parent components CANNOT be deleted in Child Blueprint,
      whereas local child components CAN be deleted! }
    AssertFalse('Cannot delete [Inherited] CapsuleComponent in Child Blueprint',
      ChildBp.RemoveSubobject('CapsuleComponent'));
    AssertFalse('Cannot delete [Inherited] CharacterMesh0 in Child Blueprint',
      ChildBp.RemoveSubobject('CharacterMesh0'));
    AssertTrue('Can delete local GreatSword_R in Child Blueprint',
      ChildBp.RemoveSubobject('GreatSword_R'));
    AssertEquals(6, Length(ChildBp.Assembled));

    { 5. FreeNotification safety: freeing BaseBp detaches ChildBp.ParentBlueprintScs cleanly }
    VP.Items.Remove(BaseBp);
    FreeAndNil(BaseBp);
    AssertTrue(ChildBp.ParentBlueprintScs = nil);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBlueprintScs.TestSpringArmBoomKinematicsDeltaOverrideRevertAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  BaseBp, ChildBp, LoadedChild: TCastleBlueprintScsActor;
  BaseCamIdx, ChildCamIdx: Integer;
  BaseCamX, PaladinCamX, ExtendedCamX: Single;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    TBlueprintScsHelper.SpawnParentAndChildBlueprintShowcaseInDesign(
      VP, Root, BaseBp, ChildBp);

    BaseCamIdx := BaseBp.FindAssembledIndex('FollowCamera');
    ChildCamIdx := ChildBp.FindAssembledIndex('FollowCamera');
    AssertTrue((BaseCamIdx >= 0) and (ChildCamIdx >= 0));

    BaseCamX := BaseBp.Assembled[BaseCamIdx].ActorSpacePos.X;
    PaladinCamX := ChildBp.Assembled[ChildCamIdx].ActorSpacePos.X;

    { 1. Child Paladin overrides CameraBoom Arm 3.6m -> 5.4m, pulling FollowCamera further back (-X)! }
    AssertTrue('5.4m Paladin boom pulls FollowCamera further behind character than 3.6m base',
      PaladinCamX < BaseCamX - 1.2);

    { 2. Overriding CameraBoom to 6.8m pulls FollowCamera even further back }
    AssertTrue(ChildBp.OverrideInheritedParams('CameraBoom', 6.80, 18.0));
    ExtendedCamX := ChildBp.Assembled[ChildBp.FindAssembledIndex('FollowCamera')].ActorSpacePos.X;
    AssertTrue(ExtendedCamX < PaladinCamX - 1.0);

    { 3. RevertInheritedOverride('CameraBoom') snaps FollowCamera right back to BaseBp's exact position! }
    AssertTrue(ChildBp.RevertInheritedOverride('CameraBoom'));
    AssertSameValue(BaseCamX,
      ChildBp.Assembled[ChildBp.FindAssembledIndex('FollowCamera')].ActorSpacePos.X, 1e-3);

    { 4. SetTransient-clean JSON roundtrip }
    JsonStr := ComponentToString(ChildBp);
    AssertEquals('Transient preview nodes excluded from JSON', 0, Pos('TCastleSphere', JsonStr));

    LoadOwner := TComponent.Create(nil);
    try
      LoadedChild := StringToComponent(JsonStr, LoadOwner) as TCastleBlueprintScsActor;
      AssertEquals(Length(ChildBp.LocalNodes), Length(LoadedChild.LocalNodes));
      AssertEquals(Length(ChildBp.InheritedOverrides), Length(LoadedChild.InheritedOverrides));
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolBlueprintScs.TestUnified115StudioHubAnd38thMcpAssembleBlueprintComponentsTool;
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
  { 1. Verify 115 UE Studios in Studio Hub (Phase 395 blueprint_scs_viewport) }
  AssertEquals(119, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('blueprint_scs_viewport', Entry));
  AssertEquals(395, Entry.PhaseNumber);

  { 2. Verify 38th MCP tool cge_assemble_blueprint_components }
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
      AssertEquals(42, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_assemble_blueprint_components","arguments":{"action":"spawn_showcase"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(2, PayloadObj.Integers['blueprintScsCount']);
        AssertEquals(1, PayloadObj.Integers['childInheritedClassCount']);
        AssertEquals(7, PayloadObj.Integers['assembledCount']);
        AssertEquals(4, PayloadObj.Integers['inheritedCount']);
        AssertEquals(2, PayloadObj.Integers['overriddenCount']);
        AssertEquals(119, PayloadObj.Integers['studioCatalogCount']);
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
  RegisterTest(TTestToolBlueprintScs);
end.
