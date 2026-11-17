{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 345 Ambient Soundscape Biome Director,
  Context-Reactive Palette Selection & WorldRay Acoustic Wall Occlusion. }
unit TestToolSoundscape;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSoundscape = class(TCastleTestCase)
  published
    procedure TestContextBiomePaletteSwitchingAndAcousticWallOcclusionMuffling;
    procedure TestSeededHemisphereDeterminismCallExpirationAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleSoundscape, ToolSoundscape;

procedure TTestToolSoundscape.TestContextBiomePaletteSwitchingAndAcousticWallOcclusionMuffling;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  D: TCastleSoundscapeDirector;
  ListenerPos: TVector3;
  IdxClear, IdxBlocked: Integer;
  CallClear, CallBlocked: TSoundscapeActiveCall;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TSoundscapeHelper.SpawnAcousticBiomeSoundscapeDemo(Vp, DesignOwner, D));
    AssertTrue(D <> nil);

    { 1. Verify context-reactive biome switching across Time / Altitude / Enclosure }
    D.HourOfDay := 7.0;
    D.ListenerAltitudeY := 4.0;
    D.IndoorEnclosureRatio := 0.0;
    AssertTrue(D.DominantBiomeLayer = slkForestDawnBirds);

    D.HourOfDay := 23.0;
    AssertTrue(D.DominantBiomeLayer = slkNocturnalCrickets);

    D.HourOfDay := 12.0;
    D.ListenerAltitudeY := 80.0;
    AssertTrue(D.DominantBiomeLayer = slkAlpineHowlingWind);

    D.IndoorEnclosureRatio := 0.85;
    AssertTrue(D.DominantBiomeLayer = slkCavernWaterDrips);

    { 2. Acoustic bunker wall stands at Z = -5.5m; listener is at (0, 1.7, 0):
         South emitter at (0, 2.5, +10.0) has clear LOS (20kHz, full gain);
         North emitter at (0, 2.5, -10.0) is occluded by wall (950Hz, 0.28x muffled gain)! }
    D.ClearActiveCalls;
    ListenerPos := Vector3(0.0, 1.7, 0.0);
    IdxClear := D.TriggerCallAtWorldPos(Vp.Items, ListenerPos, Vector3(0.0, 2.5, +10.0), slkForestDawnBirds);
    IdxBlocked := D.TriggerCallAtWorldPos(Vp.Items, ListenerPos, Vector3(0.0, 2.5, -10.0), slkForestDawnBirds);

    CallClear := D.GetActiveCall(IdxClear);
    CallBlocked := D.GetActiveCall(IdxBlocked);

    AssertFalse(CallClear.Occluded);
    AssertTrue(CallBlocked.Occluded);
    AssertSameValue(20000.0, CallClear.LowPassCutoffHz, 1.0);
    AssertSameValue(950.0, CallBlocked.LowPassCutoffHz, 1.0);
    AssertSameValue(CallClear.BaseGain * D.OccludedGainMultiplier, CallBlocked.EffectiveGain, 0.002);
    AssertEquals(1, D.OccludedCallCount);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolSoundscape.TestSeededHemisphereDeterminismCallExpirationAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  D, RestoredD: TCastleSoundscapeDirector;
  PosRun1, PosRun2: TVector3;
  SlotIdx: Integer;
  Warnings: TStringList;
  Sum: TSoundscapeStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TSoundscapeHelper.SpawnAcousticBiomeSoundscapeDemo(Vp, DesignOwner, D));

    { 1. Identical RandomSeed produces bit-identical 3D hemisphere call coordinates }
    D.RandomSeed := 777123;
    D.ClearActiveCalls;
    SlotIdx := D.SpawnScatterCall(Vp.Items, Vector3(0, 1.7, 0));
    PosRun1 := D.GetActiveCall(SlotIdx).WorldPos;
    AssertTrue(PosRun1.Y > 1.7);

    D.RandomSeed := 777123;
    D.ClearActiveCalls;
    SlotIdx := D.SpawnScatterCall(Vp.Items, Vector3(0, 1.7, 0));
    PosRun2 := D.GetActiveCall(SlotIdx).WorldPos;
    AssertSameValue(0.0, PointsDistance(PosRun1, PosRun2), 0.0001);

    { 2. Summary & Markdown report }
    Sum := TSoundscapeHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.DirectorCount);
    AssertEquals(1, Sum.ActiveCalls);
    ReportMd := TSoundscapeHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Ambient Soundscape Biome & Acoustic Occlusion Report', ReportMd) > 0);

    { 3. Transient debug line scene is never serialized into JSON }
    D.OccludedLowPassHz := 820.0;
    JsonStr := ComponentToString(D);
    AssertEquals(0, Pos('TransientSoundscapeRays', JsonStr));

    RestoredD := StringToComponent(JsonStr, RestoredOwner) as TCastleSoundscapeDirector;
    AssertTrue(RestoredD <> nil);
    AssertSameValue(820.0, RestoredD.OccludedLowPassHz, 0.1);
    AssertEquals(0, RestoredD.Count);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSoundscape);

end.
