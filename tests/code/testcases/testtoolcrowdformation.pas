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

{ Automated tests for Phase 405: Tactical Squad & Crowd Formation Controller
  (Wedge, Phalanx, Shield-Circle, Column & WorldRay Obstacle Split) Studio. }
unit TestToolCrowdFormation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolCrowdFormation = class(TCastleTestCase)
  published
    procedure TestPhalanxBoulderSplitAroundZeroIntrusionAndSlopedTerrainSnap;
    procedure TestCavalryWedgeOutwardVipShieldCircle360FacingAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleCrowdFormation, ToolCrowdFormation;

procedure TTestToolCrowdFormation.TestPhalanxBoulderSplitAroundZeroIntrusionAndSlopedTerrainSnap;
var
  Root: TComponent;
  VP: TCastleViewport;
  Form: TCastleCrowdFormation;
  LowTerrace: TCastleBox;
  I: Integer;
  S: TSquadFormationSlot;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TCrowdFormationHelper.SpawnSquadPassWithBoulderDemo(Root, Root, Form));

    { 1. 16-unit Phalanx marches across PassGraniteBoulderObstacle ([-1.4..+1.4] x [2.1..4.7],
         top Y = 3.0m > MaxStepHeight 1.25m): center-column ranks at Z = 3.42m detect
         the tall boulder and split laterally around it so ZERO units stand inside
         [-1.35..+1.35] x [2.15..4.65] or at Y = 3.0m! }
    AssertEquals(16, Form.SlotCount);
    AssertEquals(16, Form.GroundSnappedSlotCount);
    AssertTrue('Center phalanx ranks split around the granite boulder',
      Form.ObstacleAvoidedSlotCount >= 2);

    for I := 0 to Form.SlotCount - 1 do
    begin
      S := Form.GetSlot(I);
      AssertSameValue(0.0, S.WorldPosition.Y, 0.02);
      AssertFalse('Zero squad units stand inside the impassable granite boulder footprint',
        (Abs(S.WorldPosition.X) < 1.35) and
        (S.WorldPosition.Z > 2.15) and (S.WorldPosition.Z < 4.65));
    end;

    { 2. Add a walkable 0.65m raised stone terrace under the vanguard row (Z = 0.0):
         0.65m <= MaxStepHeightMeters (1.25m), so front rank snaps cleanly onto Y = 0.65m! }
    LowTerrace := TCastleBox.Create(Root);
    LowTerrace.Name := 'WalkableStoneStep';
    LowTerrace.Size := Vector3(12.0, 0.65, 1.4);
    LowTerrace.Translation := Vector3(0.0, 0.325, 0.0);
    VP.Items.Add(LowTerrace);

    Form.SolveFormationSlots(VP.Items);
    AssertSameValue(0.65, Form.GetSlot(0).WorldPosition.Y, 0.02);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolCrowdFormation.TestCavalryWedgeOutwardVipShieldCircle360FacingAndJsonRoundtrip;
var
  Form, Restored: TCastleCrowdFormation;
  I: Integer;
  S, SL, SR: TSquadFormationSlot;
  RadialOut: TVector3;
  SerializedScene, JsonCfg, Md: String;
begin
  Form := TCastleCrowdFormation.Create(nil);
  Restored := TCastleCrowdFormation.Create(nil);
  try
    { 1. Cavalry V-Wedge: Slot 0 is apex spearhead at (0,0,0), odd/even wings mirror X }
    Form.UnitCount := 9;
    Form.SlotSpacingMeters := 2.0;
    Form.FormationShape := sfsCavalryVWedge;
    Form.SolveFormationSlots(nil);
    AssertSameValue(0.0, Form.GetSlot(0).WorldPosition.X, 0.001);
    AssertSameValue(0.0, Form.GetSlot(0).WorldPosition.Z, 0.001);
    SL := Form.GetSlot(1);
    SR := Form.GetSlot(2);
    AssertSameValue(-SL.WorldPosition.X, SR.WorldPosition.X, 0.001);
    AssertSameValue(SL.WorldPosition.Z, SR.WorldPosition.Z, 0.001);
    AssertTrue('Wedge wings trail behind leader (+Z)', SL.WorldPosition.Z > 1.5);

    { 2. Outward VIP Shield-Circle: Slot 0 is VIP at center (0,0,0); Slots 1..8 form
         an equidistant protective ring facing radially OUTWARD (Dot > 0.999)! }
    Form.FormationShape := sfsVipOutwardShieldCircle;
    Form.SolveFormationSlots(nil);
    AssertSameValue(0.0, Form.GetSlot(0).WorldPosition.Length, 0.001);
    for I := 1 to Form.SlotCount - 1 do
    begin
      S := Form.GetSlot(I);
      AssertTrue(S.WorldPosition.Length > 1.8);
      RadialOut := S.WorldPosition.Normalize;
      AssertSameValue(1.0, TVector3.DotProduct(RadialOut, S.WorldForward), 0.002);
    end;

    SerializedScene := ComponentToString(Form);
    AssertTrue(Pos('CrowdFormationPreview', SerializedScene) = 0);

    Form.UnitCount := 24;
    Form.PhalanxColumns := 6;
    JsonCfg := TCrowdFormationHelper.ExportFormationJson(Form);
    AssertTrue(TCrowdFormationHelper.ImportFormationJson(Restored, JsonCfg));
    AssertEquals(24, Restored.UnitCount);
    AssertEquals(6, Restored.PhalanxColumns);
    AssertEquals(Ord(sfsVipOutwardShieldCircle), Ord(Restored.FormationShape));
    Md := TCrowdFormationHelper.GenerateMarkdownReport(Form);
    AssertTrue(Pos('VipOutwardShieldCircle', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Form);
  end;
end;

initialization
  RegisterTest(TTestToolCrowdFormation);

end.
