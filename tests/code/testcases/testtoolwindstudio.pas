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

{ Automated tests for Phase 364 Procedural Foliage Wind Gust Field & Shockwave Studio. }
unit TestToolWindStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolWindStudio = class(TCastleTestCase)
  published
    procedure TestBeaufortTrunkHeightScalingPropagatingShockwaveArrivalAndExpiration;
    procedure TestHurricanePresetAzimuthDirectionAndCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleWindField, ToolWindStudio;

procedure TTestToolWindStudio.TestBeaufortTrunkHeightScalingPropagatingShockwaveArrivalAndExpiration;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Director: TCastleWindFieldDirector;
  SaplingS, TallTreeS, PreArrivalS, CrestArrivalS, PostPassS: TPivotPainterWindSample;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TWindStudioHelper.SpawnForestWindShockwaveDemo(Vp, RootOwner, Director));

    { 1. Cantilever trunk bend scales quadratically with tree height (6m tree bends > 3x more than 2m sapling) }
    SaplingS := Director.SamplePivotWindAtWorld(Vector3(0, 0, 0), 2.0);
    TallTreeS := Director.SamplePivotWindAtWorld(Vector3(0, 0, 0), 6.0);
    AssertTrue('6m tree trunk must bend > 3x further than 2m sapling in identical wind',
      TallTreeS.TrunkBendOffsetMeters.Length > SaplingS.TrunkBendOffsetMeters.Length * 3.0);

    { 2. Trigger radial blast at Origin (PeakForce=30 m/s, WaveSpeed=10 m/s, MaxRadius=20m)
         and sample a tree at X = +10.0m before arrival (t=0s), at wavefront crest (t=1.0s), and after expiration (t=3.0s) }
    Director.TriggerRadialShockwave(Vector3(0, 0, 0), 30.0, 10.0, 20.0);
    AssertEquals(1, Director.ActiveShockwaveCount);

    PreArrivalS := Director.SamplePivotWindAtWorld(Vector3(10.0, 0.0, 0.0), 5.0);
    AssertSameValue(0.0, PreArrivalS.ShockwaveContributionMps, 0.001);

    Director.StepWindField(1.0); { Wavefront reaches R = 10.0m -> hits tree at X = +10.0m! }
    CrestArrivalS := Director.SamplePivotWindAtWorld(Vector3(10.0, 0.0, 0.0), 5.0);
    AssertTrue('Shockwave crest at R=10m must blast +X tree with > 15 m/s outward impulse',
      CrestArrivalS.ShockwaveContributionMps > 15.0);
    AssertTrue(CrestArrivalS.NetWindVelocityMps.X > PreArrivalS.NetWindVelocityMps.X + 12.0);

    Director.StepWindField(2.0); { R = 30.0m > MaxRadius + BandHalfWidth -> shockwave expires cleanly! }
    AssertEquals(0, Director.ActiveShockwaveCount);
    PostPassS := Director.SamplePivotWindAtWorld(Vector3(10.0, 0.0, 0.0), 5.0);
    AssertSameValue(0.0, PostPassS.ShockwaveContributionMps, 0.001);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolWindStudio.TestHurricanePresetAzimuthDirectionAndCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Director, Restored: TCastleWindFieldDirector;
  NorthWindS: TPivotPainterWindSample;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Director := TCastleWindFieldDirector.Create(RootOwner);
    Director.Name := 'HurricaneDirector';
    Director.Preset := wbpHurricaneTempest;
    Director.WindAzimuthDeg := 90.0; { Pure +Z wind direction }

    NorthWindS := Director.SamplePivotWindAtWorld(Vector3(0, 0, 0), 4.5);
    AssertTrue('90-deg Hurricane wind must blow strongly along +Z (> 25 m/s)',
      NorthWindS.NetWindVelocityMps.Z > 25.0);
    AssertSameValue(0.0, NorthWindS.NetWindVelocityMps.X, 0.01);

    ReportMd := TWindStudioHelper.GenerateWindReport(Director);
    AssertTrue(Pos('Wind Gust Field & Shockwave Report', ReportMd) > 0);

    JsonStr := ComponentToString(Director);
    AssertEquals(0, Pos('TransientWindGrovePreview', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleWindFieldDirector;
    AssertSameValue(90.0, Restored.WindAzimuthDeg, 0.001);
    AssertSameValue(28.0, Restored.BaseWindSpeedMps, 0.001);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolWindStudio);
end.
