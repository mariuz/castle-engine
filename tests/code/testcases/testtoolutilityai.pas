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

{ Automated unit tests for Phase 314 Smart Objects, RVO Crowd Separation &
  Response-Curve Utility AI (@link(CastleUtilityAi), @link(ToolUtilityAi)). }
unit TestToolUtilityAi;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolUtilityAi = class(TCastleTestCase)
  published
    procedure TestResponseCurvesSmartObjectSlotContentionNeedRestorationAndJson;
    procedure TestRvoCrowdSeparationCollisionAvoidanceAndVillageAudit;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleUtilityAi, ToolUtilityAi;

procedure TTestToolUtilityAi.TestResponseCurvesSmartObjectSlotContentionNeedRestorationAndJson;
var
  DesignOwner, ReloadOwner: TComponent;
  Vp: TCastleViewport;
  Campfire, Tavern: TCastleSmartObject;
  AgentA, AgentB: TCastleUtilityAiBehavior;
  ReloadedT: TCastleTransform;
  ReloadedAI: TCastleUtilityAiBehavior;
  StepIdx: Integer;
  JsonText: String;
begin
  { 1. Verify response-curve shapes }
  AssertSameValue(0.75, EvaluateUtilityCurve(0.25, urcLinearDeficit), 0.001);
  AssertSameValue(0.25, EvaluateUtilityCurve(0.50, urcQuadraticUrgency, 2.0), 0.001);
  AssertTrue(EvaluateUtilityCurve(0.10, urcLogisticSigmoid) > 0.90);
  AssertTrue(EvaluateUtilityCurve(0.80, urcLogisticSigmoid) < 0.05);
  AssertSameValue(0.85, EvaluateUtilityCurve(0.85, urcInverseAbundance), 0.001);

  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    { Single-slot Campfire (MaxUsers = 1) vs 2-slot Tavern }
    Campfire := TUtilityAiHelper.SpawnSmartObjectInDesign(
      Vp, DesignOwner, sopCampfireRestBench, Vector3(0.0, 0.0, -3.0), 'Campfire1Slot');
    Campfire.MaxUsers := 1;
    Campfire.RestoreRatePerSec := 0.80;

    Tavern := TUtilityAiHelper.SpawnSmartObjectInDesign(
      Vp, DesignOwner, sopTavernMealTable, Vector3(4.0, 0.0, -3.0), 'Tavern2Slots');
    Tavern.MaxUsers := 2;

    AgentA := TUtilityAiHelper.SpawnUtilityAgentInDesign(
      Vp, DesignOwner, uapVillagerArtisan, Vector3(0.0, 0.0, -1.5), 'VillagerA');
    AgentA.SetNeed('Energy', 0.10);
    AgentA.SetNeed('Hunger', 0.22);

    AgentB := TUtilityAiHelper.SpawnUtilityAgentInDesign(
      Vp, DesignOwner, uapVillagerArtisan, Vector3(1.5, 0.0, -1.5), 'VillagerB');
    AgentB.SetNeed('Energy', 0.12);
    AgentB.SetNeed('Hunger', 0.20);

    { Step AgentA first -> claims sole Campfire slot; AgentB falls back to Tavern! }
    AgentA.StepUtilityAi(0.10);
    AssertTrue(AgentA.ClaimedSmartObject = Campfire);
    AssertEquals(1, Campfire.ActiveUserCount);
    AssertFalse(Campfire.HasFreeSlot);

    AgentB.StepUtilityAi(0.10);
    AssertTrue(AgentB.ClaimedSmartObject = Tavern);
    AssertEquals('EatAtTavern', AgentB.CurrentActionId);

    { Step AgentA until it reaches Campfire, restores Energy >= 0.98 & releases the slot }
    for StepIdx := 1 to 20 do
    begin
      AgentA.StepUtilityAi(0.20);
      if Campfire.HasFreeSlot then
        Break;
    end;

    AssertTrue(AgentA.GetNeed('Energy') >= 0.98);
    AssertTrue(Campfire.HasFreeSlot);

    { JSON roundtrip of actor + UtilityAI ConfigJson & csTransient-clean SmartObject }
    JsonText := ComponentToString(Campfire);
    AssertEquals(0, Pos('TCastleScene', JsonText));

    JsonText := ComponentToString(AgentA.Parent);
    ReloadedT := StringToComponent(JsonText, ReloadOwner) as TCastleTransform;
    ReloadedAI := ReloadedT.FindBehavior(TCastleUtilityAiBehavior) as TCastleUtilityAiBehavior;
    AssertTrue(ReloadedAI <> nil);
    AssertEquals(AgentA.Actions.Count, ReloadedAI.Actions.Count);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolUtilityAi.TestRvoCrowdSeparationCollisionAvoidanceAndVillageAudit;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Tavern: TCastleSmartObject;
  A1, A2: TCastleUtilityAiBehavior;
  StepIdx: Integer;
  FinalDist: Single;
  Report: TUtilityAiAuditReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    Tavern := TUtilityAiHelper.SpawnSmartObjectInDesign(
      Vp, DesignOwner, sopTavernMealTable, Vector3(0.0, 0.0, -8.0), 'SharedTavern');
    Tavern.MaxUsers := 4;

    { Spawn two agents nearly overlapping (0.20m apart, inside SeparationRadius = 2.0m) }
    A1 := TUtilityAiHelper.SpawnUtilityAgentInDesign(
      Vp, DesignOwner, uapVillagerArtisan, Vector3(-0.10, 0.0, 0.0), 'CrowdNpc1');
    A1.SeparationRadius := 2.0;
    A1.SeparationWeight := 3.0;
    A1.SetNeed('Hunger', 0.10);

    A2 := TUtilityAiHelper.SpawnUtilityAgentInDesign(
      Vp, DesignOwner, uapVillagerArtisan, Vector3(0.10, 0.0, 0.0), 'CrowdNpc2');
    A2.SeparationRadius := 2.0;
    A2.SeparationWeight := 3.0;
    A2.SetNeed('Hunger', 0.10);

    for StepIdx := 1 to 6 do
      TUtilityAiHelper.StepAllUtilityAgents(Vp, DesignOwner, 0.15);

    FinalDist := PointsDistance(A1.Parent.Translation, A2.Parent.Translation);
    AssertTrue(FinalDist > 0.75);

    Report := TUtilityAiHelper.ScanDesign(Vp, DesignOwner);
    try
      AssertEquals(1, Length(Report.Stations));
      AssertEquals(2, Length(Report.Agents));
      AssertEquals(2, Report.OccupiedSlots);
    finally
      FreeAndNil(Report);
    end;

    Md := TUtilityAiHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('SharedTavern', Md) > 0);
    AssertTrue(Pos('CrowdNpc1', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolUtilityAi);
end.
