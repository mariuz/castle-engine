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

{ Automated unit tests for Phase 331 Physical Animation Localized Hit-Reaction
  Impulse, PD Pose Spring-Back, PBD Articulated Ragdoll Collapse & Smooth Get-Up
  Recovery Studio (@link(CastleRagdollHit), @link(ToolRagdollStudio)). }
unit TestToolRagdollStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolRagdollStudio = class(TCastleTestCase)
  published
    procedure TestLocalizedHeadshotImpulseTopologicalAttenuationAndPdSpringRecovery;
    procedure TestHeavyBlastKnockdownFullRagdollBoneLengthPreservationGetUpAndJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleRagdollHit, ToolRagdollStudio;

procedure TTestToolRagdollStudio.TestLocalizedHeadshotImpulseTopologicalAttenuationAndPdSpringRecovery;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Actor: TCastleTransform;
  Rig: TCastlePhysicalHitRagdollBehavior;
  HeadZ, ChestZ, PelvisZ: Single;
  HitBone: TRagdollBoneId;
  I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    TRagdollStudioHelper.SpawnPhysicalRagdollArenaDemo(Vp, DesignOwner, Actor, Rig);
    AssertTrue(Actor <> nil);
    AssertTrue(Rig <> nil);
    AssertTrue(Rig.Mode = prmActivePhysicalHitReact);

    { 1. Point hit near Y=1.68m auto-selects rbiHead and stays in ActivePDHitReact (<28 threshold) }
    HitBone := Rig.ApplyPointHitImpulse(Vector3(0.0, 1.70, 0.0), Vector3(0.0, 0.0, 14.0));
    AssertTrue(HitBone = rbiHead);
    AssertTrue(Rig.Mode = prmActivePhysicalHitReact);

    Rig.StepPhysicalAnimation(0.06);
    HeadZ := Rig.GetBoneState(rbiHead).CurLocalPos.Z;
    ChestZ := Rig.GetBoneState(rbiSpineChest).CurLocalPos.Z;
    PelvisZ := Rig.GetBoneState(rbiPelvis).CurLocalPos.Z;

    { Topological hop attenuation: Head recoils furthest, then Chest, then Pelvis > 0 }
    AssertTrue(HeadZ > ChestZ);
    AssertTrue(ChestZ > PelvisZ);
    AssertTrue(PelvisZ > 0.001);

    { 2. Critically-damped PD motor springs recover upright rest pose cleanly }
    for I := 1 to 30 do
      Rig.StepPhysicalAnimation(0.05);
    AssertTrue(Rig.MaxPoseDeviationMeters < 0.015);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolRagdollStudio.TestHeavyBlastKnockdownFullRagdollBoneLengthPreservationGetUpAndJson;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Actor, RestoredActor: TCastleTransform;
  Rig, RestoredRig: TCastlePhysicalHitRagdollBehavior;
  RestNeckLen,RagdollNeckLen: Single;
  B: TRagdollBoneId;
  I: Integer;
  SavedJson, Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    TRagdollStudioHelper.SpawnPhysicalRagdollArenaDemo(Vp, DesignOwner, Actor, Rig);
    RestNeckLen := Rig.GetBoneState(rbiHead).RestLengthToParent;

    { 1. Heavy 40 N*s blast exceeds KnockdownThreshold (28) -> enters FullLimpRagdoll! }
    Rig.ApplyHitImpulseAtBone(rbiSpineChest, Vector3(4.0, 6.0, 40.0));
    AssertTrue(Rig.Mode = prmFullLimpRagdoll);

    for I := 1 to 35 do
      Rig.StepPhysicalAnimation(0.05);

    { 2. Fallen ragdoll respects FloorLocalY = 0.0 and preserves articulated bone lengths! }
    AssertTrue(Rig.GetBoneState(rbiHead).CurLocalPos.Y < 0.60);
    for B in TRagdollBoneId do
      AssertTrue(Rig.GetBoneState(B).CurLocalPos.Y >= Rig.GetBoneState(B).BoneRadius - 1e-3);

    RagdollNeckLen := PointsDistance(
      Rig.GetBoneState(rbiHead).CurLocalPos,
      Rig.GetBoneState(rbiSpineChest).CurLocalPos);
    AssertSameValue(RestNeckLen, RagdollNeckLen, 0.02);

    { 3. Smooth Hermite Get-Up recovery blends fallen ragdoll back to upright standing pose! }
    Rig.BeginGetUpRecovery(0.60);
    AssertTrue(Rig.Mode = prmGetUpBlendRecovery);
    for I := 1 to 15 do
      Rig.StepPhysicalAnimation(0.05);

    AssertTrue(Rig.Mode = prmActivePhysicalHitReact);
    AssertSameValue(1.68, Rig.GetBoneState(rbiHead).CurLocalPos.Y, 0.02);

    { 4. Verify csTransient-clean JSON serialization roundtrip on parent actor }
    Rig.ApplyPreset(papStiffArmoredKnight);
    SavedJson := ComponentToString(Actor);
    AssertEquals(0, Pos('TCastleBox', SavedJson));
    RestoredOwner := TComponent.Create(nil);
    try
      RestoredActor := StringToComponent(SavedJson, RestoredOwner) as TCastleTransform;
      RestoredRig := RestoredActor.FindBehavior(TCastlePhysicalHitRagdollBehavior) as TCastlePhysicalHitRagdollBehavior;
      AssertTrue(RestoredRig <> nil);
      AssertTrue(RestoredRig.Preset = papStiffArmoredKnight);
      AssertSameValue(220.0, RestoredRig.SpringStiffnessKp, 1e-3);
    finally
      FreeAndNil(RestoredOwner);
    end;

    Md := TRagdollStudioHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('Physical Animation Hit-Reaction & Ragdoll Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolRagdollStudio);
end.
