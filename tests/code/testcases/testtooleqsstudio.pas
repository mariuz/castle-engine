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

{ Automated unit tests for Phase 319 Environment Query System (EQS) Tactical
  Ring/Grid Generator, Line-of-Sight Cover Occlusion, High-Ground Sniper
  Vantage & Rear-Flank Scoring Studio (@link(TCastleEqsQueryBehavior),
  @link(TEqsStudioHelper)). }
unit TestToolEqsStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolEqsStudio = class(TCastleTestCase)
  published
    procedure TestTakeCoverBehindWallLoSOcclusionWallTopRejectionAndJsonRoundtrip;
    procedure TestSniperHighGroundElevationBonusAndRearFlankDotProductScoring;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleEqsTactical, ToolEqsStudio;

procedure TTestToolEqsStudio.TestTakeCoverBehindWallLoSOcclusionWallTopRejectionAndJsonRoundtrip;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Agent, Threat, Wall, Balcony: TCastleTransform;
  Eqs, LoadedEqs: TCastleEqsQueryBehavior;
  I: Integer;
  C: TEqsCandidateItem;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TEqsStudioHelper.SpawnTacticalCoverArenaDemo(Vp, OwnerComp,
      Agent, Threat, Wall, Balcony, Eqs);

    { Threat is at Z = -7.5, CoverWall (width 6.5, height 3.0, depth 1.2) is at Z = 0.0 }
    AssertTrue(Eqs <> nil);
    AssertTrue(Eqs.RunQuery);
    AssertTrue(Eqs.HasValidBestSpot);

    { Best cover spot must lie strictly BEHIND CoverWall (Z > +0.6) and on the floor (Y < 0.5, NOT on the 3m wall top!) }
    AssertTrue(Eqs.BestWorldPos.Z > 0.6);
    AssertTrue(Abs(Eqs.BestWorldPos.X) <= 3.5);
    AssertTrue(Eqs.BestWorldPos.Y < 0.5);

    { Every candidate in front of the wall (Z < -1.0) has clear LoS to Threat and must be FilteredOut }
    for I := 0 to Eqs.CandidateCount - 1 do
    begin
      C := Eqs.GetCandidate(I);
      if (C.WorldPos.Z < -1.0) and (Abs(C.WorldPos.X) < 3.0) then
        AssertTrue(C.FilteredOut);
    end;

    { Verify DebugSpheres transient non-baking + ConfigJson roundtrip }
    Eqs.ShowDebugSpheres := True;
    Eqs.RunQuery;
    JsonStr := ComponentToString(Eqs);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleEqsQueryBehavior);
    LoadedEqs := TCastleEqsQueryBehavior(LoadedComp);
    AssertEquals(Ord(epTakeCoverFromThreat), Ord(LoadedEqs.Preset));
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolEqsStudio.TestSniperHighGroundElevationBonusAndRearFlankDotProductScoring;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Agent, Threat, Wall, Balcony: TCastleTransform;
  Eqs: TCastleEqsQueryBehavior;
  Rep: TEqsAuditReport;
  K: Integer;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TEqsStudioHelper.SpawnTacticalCoverArenaDemo(Vp, OwnerComp,
      Agent, Threat, Wall, Balcony, Eqs);

    { 1. Sniper High-Ground Vantage: SniperBalcony top is at Y = 2.8m with clear LoS to Threat! }
    Eqs.ApplyPreset(epSniperLineOfSightVantage);
    AssertTrue(Eqs.RunQuery);
    AssertTrue(Eqs.HasValidBestSpot);
    AssertTrue(Eqs.BestWorldPos.Y > 2.5); // Picked elevated SniperBalcony over Y=0 ground!
    AssertTrue(Eqs.GetCandidate(Eqs.BestCandidateIndex).HasClearLoSToThreat);

    { 2. Rear Flank Surround: Threat at Z = -7.5 faces +Z (Rotation Pi around Y),
      so 180 deg behind Threat's back is Z < -10.5! }
    Eqs.ApplyPreset(epFlankRearSurround);
    AssertTrue(Eqs.RunQuery);
    AssertTrue(Eqs.HasValidBestSpot);
    AssertTrue(Eqs.BestWorldPos.Z < Threat.Translation.Z - 2.5);

    { 3. AutoMoveToBestSpot steers Agent smoothly toward BestWorldPos }
    Eqs.AutoMoveToBestSpot := True;
    for K := 1 to 40 do
      Eqs.StepEqsAgent(0.10);
    AssertTrue(Agent.Translation.Z < Threat.Translation.Z - 2.0);

    Rep := TEqsStudioHelper.AuditEqsQueries(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.QueryCount);
      AssertEquals(1, Rep.SolvedCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolEqsStudio);
end.
