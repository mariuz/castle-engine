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

{ Automated tests for Phase 355 MassTraffic Multi-Lane Signal & IDM Headway Studio. }
unit TestToolMassTraffic;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolMassTraffic = class(TCastleTestCase)
  published
    procedure TestNemaSignalConflictInterlockRedLightQueueBrakingAndZeroRearEndOverlaps;
    procedure TestRushHour40VehiclesFullPhaseCycleDischargeAndTransientCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleMassTraffic, ToolMassTraffic;

procedure TTestToolMassTraffic.TestNemaSignalConflictInterlockRedLightQueueBrakingAndZeroRearEndOverlaps;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Traffic: TCastleMassTrafficManager;
  I: Integer;
  V: TTrafficVehicleState;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TMassTrafficHelper.SpawnMassTrafficCrossroads(Vp, RootOwner, Traffic));
    AssertTrue(Traffic <> nil);
    AssertEquals(24, Traffic.Stats.ActiveVehicles);
    AssertEquals(8, Traffic.Stats.LaneCount);

    { Hold NS=GREEN / EW=RED for 6.5s so NS cars flow across intersection while EW cars queue cleanly }
    Traffic.GreenDurationSec := 20.0;
    Traffic.ForceSignalPhase(tspNorthSouthGreen);
    AssertTrue(Traffic.NorthSouthLightColor = tlcGreen);
    AssertTrue(Traffic.EastWestLightColor = tlcRed);

    for I := 1 to 65 do
    begin
      Traffic.StepTraffic(0.10);
      AssertFalse('NEMA safety interlock: NS and EW lights can NEVER both be Green',
        (Traffic.NorthSouthLightColor = tlcGreen) and (Traffic.EastWestLightColor = tlcGreen));
      AssertEquals('IDM headway braking must maintain ZERO rear-end overlaps on every tick',
        0, Traffic.Stats.RearEndOverlapCount);
    end;

    AssertEquals(0, Traffic.Stats.SignalConflictCount);
    AssertTrue('East-West red-light lanes must queue multiple stopped vehicles cleanly',
      Traffic.Stats.StoppedQueueCount >= 4);

    { Verify no East-West vehicle (lanes 4..7, spawned at 4..46m < StopLine 51m) ran the red stop line }
    for I := 0 to Traffic.VehicleStateCount - 1 do
    begin
      V := Traffic.GetVehicleState(I);
      if V.LaneIndex >= 4 then
        AssertTrue('EW vehicle must stop upstream of StopLineMeters (51.0m) on Red',
          V.DistanceAlongLane <= 50.0);
    end;
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolMassTraffic.TestRushHour40VehiclesFullPhaseCycleDischargeAndTransientCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Traffic, Restored: TCastleMassTrafficManager;
  I: Integer;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Traffic := TCastleMassTrafficManager.Create(RootOwner);
    Traffic.Name := 'RushHourCity';
    Traffic.Preset := mtpRushHourGridlock40;
    Traffic.GreenDurationSec := 5.0;
    Traffic.YellowDurationSec := 1.5;
    Traffic.AllRedDurationSec := 1.0;
    AssertEquals(40, Traffic.Stats.ActiveVehicles);

    { Run 18 seconds (~2.4 full NEMA stages) across NS Green -> Yellow -> AllRed -> EW Green -> Yellow -> AllRed }
    for I := 1 to 90 do
    begin
      Traffic.StepTraffic(0.20);
      AssertEquals(0, Traffic.Stats.RearEndOverlapCount);
      AssertEquals(0, Traffic.Stats.SignalConflictCount);
    end;

    AssertTrue('Signal controller must advance across all NEMA transitions',
      Traffic.Stats.TotalPhaseTransitions >= 5);
    AssertTrue(Traffic.Stats.MeanSpeedMps > 1.5);

    ReportMd := TMassTrafficHelper.GenerateMassTrafficReport(Traffic);
    AssertTrue(Pos('Rush-Hour Commuter Flow', ReportMd) > 0);

    JsonStr := ComponentToString(Traffic);
    AssertEquals(0, Pos('TransientMassTrafficPreview', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleMassTrafficManager;
    AssertTrue(Restored.Preset = mtpRushHourGridlock40);
    AssertEquals(40, Restored.VehicleCount);
    AssertSameValue(5.0, Restored.GreenDurationSec, 0.01);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMassTraffic);
end.
