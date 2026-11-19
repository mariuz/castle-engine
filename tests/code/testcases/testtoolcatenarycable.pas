{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 385 Procedural Catenary Cable, Powerline Sag &
  Hanging Lantern Garland Studio. }
unit TestToolCatenaryCable;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolCatenaryCable = class(TCastleTestCase)
  published
    procedure TestExactHyperbolicCatenaryEndpointPinningArcLengthAndAsymmetricAnchors;
    procedure TestLateralWindSwayEndpointInvarianceEvenLanternSpacingAndJsonRoundtrip;
  end;

implementation

uses
  Math, CastleVectors, CastleViewport, CastleComponentSerialize,
  CastleCatenaryCable, ToolCatenaryCable;

procedure TTestToolCatenaryCable.TestExactHyperbolicCatenaryEndpointPinningArcLengthAndAsymmetricAnchors;
var
  Owner: TComponent;
  Vp: TCastleViewport;
  Cable: TCastleCatenaryCable;
  SagTaut, SagMedium, SagLoose, ExpectedChord: Single;
begin
  Owner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TCatenaryCableHelper.SpawnFestivalGarlandDemo(Vp, Owner, Cable));
    AssertTrue(Cable <> nil);

    { 1. Calm-air exact cosh solver: endpoints pinned & polygonal arc length matches 16m * SlackRatio }
    Cable.WindSpeedMps := 0.0;
    Cable.SlackRatio := 1.02;
    SagTaut := Cable.MidpointSagMeters;
    AssertVectorEquals(Vector3(-8.0, 6.0, 0.0), Cable.GetKnotWorld(0), 0.0001);
    AssertVectorEquals(Vector3(8.0, 6.0, 0.0), Cable.GetKnotWorld(Cable.KnotCount - 1), 0.0001);
    AssertSameValue(16.0 * 1.02, Cable.TotalArcLengthMeters, 0.15);

    Cable.SlackRatio := 1.15;
    SagMedium := Cable.MidpointSagMeters;
    AssertSameValue(16.0 * 1.15, Cable.TotalArcLengthMeters, 0.20);

    Cable.SlackRatio := 1.32;
    SagLoose := Cable.MidpointSagMeters;
    AssertSameValue(16.0 * 1.32, Cable.TotalArcLengthMeters, 0.25);

    AssertTrue(SagTaut > 0.20);
    AssertTrue(SagMedium > SagTaut);
    AssertTrue(SagLoose > SagMedium);

    { 2. Asymmetric height anchors (-8, 2.5, -3) -> (+8, 9.5, +3): exact endpoint pinning }
    Cable.StartY := 2.5;
    Cable.StartZ := -3.0;
    Cable.EndY := 9.5;
    Cable.EndZ := 3.0;
    Cable.SlackRatio := 1.18;
    ExpectedChord := PointsDistance(Vector3(-8.0, 2.5, -3.0), Vector3(8.0, 9.5, 3.0));
    AssertVectorEquals(Vector3(-8.0, 2.5, -3.0), Cable.GetKnotWorld(0), 0.0001);
    AssertVectorEquals(Vector3(8.0, 9.5, 3.0), Cable.GetKnotWorld(Cable.KnotCount - 1), 0.0001);
    AssertSameValue(ExpectedChord * 1.18, Cable.TotalArcLengthMeters, 0.30);
  finally
    FreeAndNil(Owner);
  end;
end;

procedure TTestToolCatenaryCable.TestLateralWindSwayEndpointInvarianceEvenLanternSpacingAndJsonRoundtrip;
var
  Owner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Cable, Restored: TCastleCatenaryCable;
  MidPt: TVector3;
  D01, D12, D23: Single;
  SavedJson, Cfg, Md: String;
begin
  Owner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TCatenaryCableHelper.SpawnFestivalGarlandDemo(Vp, Owner, Cable));

    { 1. Strong +Z crosswind sways midspan laterally while keeping endpoints 0.0000m locked }
    Cable.WindSpeedMps := 14.0;
    Cable.WindDirectionDeg := 90.0;
    Cable.StepWindSway(0.35);
    MidPt := Cable.EvaluatePointAtNormalizedSpan(0.5);
    AssertTrue(Abs(MidPt.Z) > 0.25);
    AssertVectorEquals(Vector3(-8.0, 6.0, 0.0), Cable.GetKnotWorld(0), 0.0001);
    AssertVectorEquals(Vector3(8.0, 6.0, 0.0), Cable.GetKnotWorld(Cable.KnotCount - 1), 0.0001);

    { 2. 5 hanging lanterns evenly spaced along arc length at 1/6, 2/6, 3/6, 4/6, 5/6 }
    Cable.WindSpeedMps := 0.0;
    AssertEquals(5, Cable.AttachmentCount);
    D01 := PointsDistance(Cable.GetAttachment(0).WorldPos, Cable.GetAttachment(1).WorldPos);
    D12 := PointsDistance(Cable.GetAttachment(1).WorldPos, Cable.GetAttachment(2).WorldPos);
    D23 := PointsDistance(Cable.GetAttachment(2).WorldPos, Cable.GetAttachment(3).WorldPos);
    AssertSameValue(D12, D23, 0.08);
    AssertTrue(Abs(D01 - D12) < 0.25);

    Md := TCatenaryCableHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Procedural Catenary Cable, Powerline Sag & Lantern Garland Report', Md) > 0);

    { 3. Verify csTransient preview never leaks into serialized JSON + ConfigJson roundtrip }
    Cable.ApplyPreset(ccpHarborMooringHawser);
    SavedJson := ComponentToString(Cable);
    AssertEquals(0, Pos('TransientCatenaryPreview', SavedJson));
    Cfg := Cable.ConfigJson;
    Restored := StringToComponent(SavedJson, RestoredOwner) as TCastleCatenaryCable;
    AssertTrue(Restored <> nil);
    Restored.ConfigJson := Cfg;
    AssertEquals(Ord(ccpHarborMooringHawser), Ord(Restored.Preset));
    AssertSameValue(1.28, Restored.SlackRatio, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Owner);
  end;
end;

initialization
  RegisterTest(TTestToolCatenaryCable);

end.
