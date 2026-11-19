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

{ Automated tests for Phase 380 Skeletal Footstep Decal & Acoustic Surface Studio. }
unit TestToolFootstepDirector;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolFootstepDirector = class(TCastleTestCase)
  published
    procedure TestAlternatingLeftRightStrideCrossingsAndWorldRaySurfaceMatching;
    procedure TestMetalVsSnowAcousticGainIdleZeroStepsAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleFootstepDirector, ToolFootstepDirector;

procedure TTestToolFootstepDirector.TestAlternatingLeftRightStrideCrossingsAndWorldRaySurfaceMatching;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Dir: TCastleFootstepDirector;
  StepSnow, StepPuddle: TFootprintDecalEntry;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TFootstepDirectorHelper.SpawnMultiSurfaceWalkwayDemo(Vp, RootOwner, Dir));

    { 1. Standing idle (0.0 m/s) for 2.0s must trigger 0 footsteps }
    AssertEquals(0, Dir.AdvanceLocomotionCycle(Vp.Items, Vector3(0.0, 0.0, 2.0), 0.0, 0.0, 2.0));
    AssertEquals(0, Dir.TotalFootstepsTriggered);

    { 2. Full stride cycle (1.8m stride at 3.6 m/s for 0.50s = 1.00 cycle) over Snow (Z=2.0):
         must fire BOTH Left (0.25) and Right (0.75) foot strikes on fsmSoftSnow! }
    AssertEquals(2, Dir.AdvanceLocomotionCycle(Vp.Items, Vector3(0.0, 0.0, 2.0), 0.0, 3.6, 0.50));
    AssertEquals(Ord(fsLeftFoot), Ord(Dir.GetDecalSlot(0).FootSide));
    AssertEquals(Ord(fsRightFoot), Ord(Dir.GetDecalSlot(1).FootSide));
    AssertTrue(Dir.GetDecalSlot(0).WorldPos.X < 0.0);
    AssertTrue(Dir.GetDecalSlot(1).WorldPos.X > 0.0);
    StepSnow := Dir.LastFootstep;
    AssertEquals(Ord(fsmSoftSnow), Ord(StepSnow.SurfaceMaterial));

    { 3. Next half-stride over ShallowPuddle (Z=6.0) matches fsmShallowPuddle with higher splash particle count! }
    AssertTrue(Dir.AdvanceLocomotionCycle(Vp.Items, Vector3(0.0, 0.0, 6.0), 0.0, 3.6, 0.25) >= 1);
    StepPuddle := Dir.LastFootstep;
    AssertEquals(Ord(fsmShallowPuddle), Ord(StepPuddle.SurfaceMaterial));
    AssertTrue(StepPuddle.ParticleCount > StepSnow.ParticleCount);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolFootstepDirector.TestMetalVsSnowAcousticGainIdleZeroStepsAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Dir, Restored: TCastleFootstepDirector;
  SnowGain, MetalGain: Single;
  JsonStr: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TFootstepDirectorHelper.SpawnMultiSurfaceWalkwayDemo(Vp, RootOwner, Dir));

    { Compare Snow (Z=2.0) vs MetalGrating (Z=10.0) acoustic gain at identical 3.6 m/s speed }
    Dir.ClearFootprints;
    Dir.AdvanceLocomotionCycle(Vp.Items, Vector3(0.0, 0.0, 2.0), 0.0, 3.6, 0.30);
    SnowGain := Dir.LastFootstep.AcousticGain01;

    Dir.ClearFootprints;
    Dir.AdvanceLocomotionCycle(Vp.Items, Vector3(0.0, 0.0, 10.0), 0.0, 3.6, 0.30);
    AssertEquals(Ord(fsmMetalGrating), Ord(Dir.LastFootstep.SurfaceMaterial));
    MetalGain := Dir.LastFootstep.AcousticGain01;
    AssertTrue('Metal grating footstep must be louder than muffled soft snow', MetalGain > SnowGain);

    { Verify csTransient-clean JSON roundtrip }
    Dir.Preset := fdpStealthRogueSneak;
    JsonStr := ComponentToString(Dir);
    AssertEquals(0, Pos('FootstepDecalsTransient', JsonStr));
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleFootstepDirector;
    AssertEquals(Ord(fdpStealthRogueSneak), Ord(Restored.Preset));
    AssertSameValue(0.35, Restored.ArmorWeightAcousticMult, 1e-3);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolFootstepDirector);
end.
