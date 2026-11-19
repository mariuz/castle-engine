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

{ Automated tests for Phase 388: Acoustic Raytraced Reverb, Sabine/Eyring RT60
  Decay & Doorway Diffraction Obstruction Studio. }
unit TestToolAcousticSpace;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolAcousticSpace = class(TCastleTestCase)
  published
    procedure TestStoneCathedralVsPaddedBoothVsOpenSkyRt60Scaling;
    procedure TestDirectVsDoorwayDiffractedVsSealedWallLpfAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleAcousticSpace, ToolAcousticSpace;

procedure TTestToolAcousticSpace.TestStoneCathedralVsPaddedBoothVsOpenSkyRt60Scaling;
var
  Root: TComponent;
  VP, EmptyVP: TCastleViewport;
  Probe, OutdoorProbe: TCastleAcousticProbe;
  StoneRep, PaddedRep, OutdoorRep: TAcousticRoomReport;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    AssertTrue(TAcousticSpaceHelper.SpawnStoneHallAndDoorwayDemo(Root, Root, Probe));
    StoneRep := Probe.LastRoom;
    AssertTrue('Enclosed cathedral hits majority of rays', StoneRep.HitRayCount >= 40);
    AssertTrue('Stone cathedral produces lush Sabine RT60 > 2.0s',
      StoneRep.SabineRt60Sec > 2.0);
    AssertTrue('Eyring RT60 <= Sabine RT60 physically',
      StoneRep.EyringRt60Sec <= StoneRep.SabineRt60Sec + 0.01);

    { Converting stone walls to PaddedFoam slashes RT60 by > 5x }
    PaddedRep := TAcousticSpaceHelper.ConvertRoomToPaddedBooth(Root, Probe);
    AssertTrue('Padded booth RT60 < 0.8s and < 1/4 of stone cathedral',
      (PaddedRep.SabineRt60Sec < 0.80) and
      (PaddedRep.SabineRt60Sec < StoneRep.SabineRt60Sec * 0.25));

    { Open sky viewport with zero walls -> 100% sky escape, 0s indoor RT60 }
    EmptyVP := TCastleViewport.Create(Root);
    OutdoorProbe := TCastleAcousticProbe.Create(Root);
    EmptyVP.Items.Add(OutdoorProbe);
    OutdoorRep := OutdoorProbe.BakeRoomAcoustics(EmptyVP.Items);
    AssertSameValue(1.0, OutdoorRep.OutdoorLeak01, 0.001);
    AssertSameValue(0.0, OutdoorRep.SabineRt60Sec, 0.001);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolAcousticSpace.TestDirectVsDoorwayDiffractedVsSealedWallLpfAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Probe, Restored: TCastleAcousticProbe;
  ObsClear, ObsPortal, ObsSealed: TAcousticObstructionSample;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleAcousticProbe.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TAcousticSpaceHelper.SpawnStoneHallAndDoorwayDemo(Root, Root, Probe));

    { 1. Direct unobstructed source on same side of divider wall (Z = +8m) }
    ObsClear := Probe.EvaluateSourceObstruction(
      VP.Items, Vector3(0.0, 1.7, 8.0), Vector3(6.8, 1.7, -3.0));
    AssertTrue(ObsClear.DirectLineOfSight);
    AssertSameValue(20000.0, ObsClear.LowPassCutoffHz, 1.0);
    AssertSameValue(1.0, ObsClear.DirectGain01, 0.001);

    { 2. Source behind StoneDividerWall (Z = -8m) diffracting through open East
         doorway gap at X = +6.8m, Z = -3.0m }
    ObsPortal := Probe.EvaluateSourceObstruction(
      VP.Items, Vector3(0.0, 1.7, -8.0), Vector3(6.8, 1.7, -3.0));
    AssertFalse(ObsPortal.DirectLineOfSight);
    AssertTrue('East doorway gap provides clear 2-segment diffraction path',
      ObsPortal.DiffractedViaPortal);
    AssertTrue('Doorway diffraction applies intermediate LPF (750..8500 Hz)',
      (ObsPortal.LowPassCutoffHz >= 750.0) and (ObsPortal.LowPassCutoffHz < 8500.0));

    { 3. Bogus portal inside solid West wall -> sealed wall muffling (380 Hz) }
    ObsSealed := Probe.EvaluateSourceObstruction(
      VP.Items, Vector3(0.0, 1.7, -8.0), Vector3(-15.0, 1.7, -3.0));
    AssertFalse(ObsSealed.DirectLineOfSight);
    AssertFalse(ObsSealed.DiffractedViaPortal);
    AssertTrue('Sealed masonry muffles LPF below doorway diffraction',
      ObsSealed.LowPassCutoffHz < ObsPortal.LowPassCutoffHz);

    { Transient preview exclusion & JSON roundtrip }
    SerializedScene := ComponentToString(Probe);
    AssertTrue(Pos('AcousticProbePreview', SerializedScene) = 0);

    Probe.RayCount := 96;
    JsonCfg := TAcousticSpaceHelper.ExportProbeJson(Probe);
    AssertTrue(TAcousticSpaceHelper.ImportProbeJson(Restored, JsonCfg));
    AssertEquals(96, Restored.RayCount);
    Md := TAcousticSpaceHelper.GenerateMarkdownReport(Probe);
    AssertTrue(Pos('CathedralStoneNave', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolAcousticSpace);

end.
