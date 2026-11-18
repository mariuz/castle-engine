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

{ Automated tests for Phase 361 River Spline Rapids, Width/Depth & Drift Studio. }
unit TestToolRiverStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolRiverStudio = class(TCastleTestCase)
  published
    procedure TestGorgeContinuityVelocityAccelerationWhitewaterFoamAndKayakAdvection;
    procedure TestWaterfallCascadeSlopeBoostOutOfBankRejectionAndCleanJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleRiverSpline, ToolRiverStudio;

procedure TTestToolRiverStudio.TestGorgeContinuityVelocityAccelerationWhitewaterFoamAndKayakAdvection;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  River: TCastleRiverSpline;
  Kayak: TCastleTransform;
  WideHeadwater, NarrowGorge, WideBasin: TRiverCrossSectionSample;
  KayakPos, KayakVel: TVector3;
  I: Integer;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TRiverStudioHelper.SpawnMountainGorgeRiverDemo(Vp, RootOwner, River, Kayak));
    AssertTrue(River <> nil);

    { 1. Q = A * v continuity: narrow 2.2m gorge (u=0.50) MUST flow > 3x faster than
         wide 9.0m headwater (u=0.05) and wide 10.0m outflow basin (u=0.95), generating whitewater foam! }
    WideHeadwater := River.SampleRiverAtParam(0.05);
    NarrowGorge := River.SampleRiverAtParam(0.50);
    WideBasin := River.SampleRiverAtParam(0.95);

    AssertTrue('Narrow gorge must accelerate flow > 3x faster than wide headwater',
      NarrowGorge.FlowSpeedMps > WideHeadwater.FlowSpeedMps * 3.0);
    AssertTrue('Narrow gorge must flow > 3x faster than wide outflow basin',
      NarrowGorge.FlowSpeedMps > WideBasin.FlowSpeedMps * 3.0);
    AssertTrue('Fast gorge rapids must generate whitewater foam while placid headwater stays clear',
      NarrowGorge.WhitewaterFoamFactor > WideHeadwater.WhitewaterFoamFactor + 0.40);

    { 2. Kayak downstream advection along river spline (+X, +Z, descending -Y) }
    KayakPos := Kayak.Translation;
    KayakVel := TVector3.Zero;
    for I := 1 to 40 do
      AssertTrue(River.StepFloatingBodyAlongRiver(KayakPos, KayakVel, 4.0, 0.10));

    AssertTrue('Kayak must drift downstream (+X and +Z) and descend river elevation (-Y)',
      (KayakPos.X > Kayak.Translation.X + 3.0) and
      (KayakPos.Z > Kayak.Translation.Z + 2.0) and
      (KayakPos.Y < Kayak.Translation.Y - 0.15));
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolRiverStudio.TestWaterfallCascadeSlopeBoostOutOfBankRejectionAndCleanJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  River, Restored: TCastleRiverSpline;
  PlungeSample, FarSample: TRiverCrossSectionSample;
  InsideBank: Boolean;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    River := TCastleRiverSpline.Create(RootOwner);
    River.Name := 'CascadeRiver';
    River.Preset := rspWaterfallPlungeCascade;

    PlungeSample := River.SampleRiverAtParam(0.50);
    AssertTrue('Waterfall plunge must exhibit steep downward SlopeSin > 0.45 and max whitewater foam',
      (PlungeSample.SlopeSin > 0.45) and (PlungeSample.WhitewaterFoamFactor > 0.85));

    { Dry-land point 30m lateral to channel must report InsideChannel = False }
    FarSample := River.SampleRiverFlowAtWorldPoint(Vector3(30.0, 2.0, -30.0), InsideBank);
    AssertFalse('Point far outside river banks must report InsideChannel = False', InsideBank);
    AssertTrue(FarSample.WidthMeters > 0.0);

    ReportMd := TRiverStudioHelper.GenerateRiverReport(River);
    AssertTrue(Pos('Steep Waterfall Plunge Cascade', ReportMd) > 0);

    JsonStr := ComponentToString(River);
    AssertEquals(0, Pos('TransientRiverSplineMesh', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleRiverSpline;
    AssertTrue(Restored.Preset = rspWaterfallPlungeCascade);
    AssertEquals(4, Restored.KnotCount);
    AssertEquals(1, Restored.Count);
    AssertTrue(csTransient in Restored[0].ComponentStyle);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolRiverStudio);
end.
