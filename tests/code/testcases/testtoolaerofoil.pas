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

{ Automated tests for Phase 369 Aerodynamic Wing / Sail Foil Polar & Stall Studio. }
unit TestToolAeroFoil;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolAeroFoil = class(TCastleTestCase)
  published
    procedure TestPrandtlLiftToDragRatioCriticalStallSeparationAndDragSurge;
    procedure TestThermalUpdraftAltitudeClimbVsCalmAirGlideAndJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleAeroFoil, ToolAeroFoil;

procedure TTestToolAeroFoil.TestPrandtlLiftToDragRatioCriticalStallSeparationAndDragSurge;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Glider: TCastleTransform;
  Foil: TCastleAeroFoilBehavior;
  CruiseP, PeakP, DeepStallP: TAeroFoilPolarSample;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TAeroFoilHelper.SpawnGliderThermalCanyonDemo(Vp, RootOwner, Glider, Foil));

    { 1. Attached soaring flight at Alpha = 8 deg achieves high L/D > 14 with IsStalled = False }
    CruiseP := Foil.EvaluatePolarAtAlphaDeg(8.0);
    PeakP := Foil.EvaluatePolarAtAlphaDeg(14.5);
    AssertFalse(CruiseP.IsStalled);
    AssertTrue('High-aspect hang-glider at 8 deg must achieve L/D > 14.0',
      CruiseP.LiftToDragRatio > 14.0);

    { 2. Exceeding CriticalStallAngleDeg (28 deg > 15 deg) triggers flow separation:
         CL drops sharply from peak while separated form drag surges > 4x! }
    DeepStallP := Foil.EvaluatePolarAtAlphaDeg(28.0);
    AssertTrue(DeepStallP.IsStalled);
    AssertTrue('Post-stall CL at 28 deg must drop below 70% of pre-stall peak CL',
      DeepStallP.LiftCoeffCL < PeakP.LiftCoeffCL * 0.70);
    AssertTrue('Post-stall separated drag CD at 28 deg must surge > 4x above cruise CD',
      DeepStallP.DragCoeffCD > CruiseP.DragCoeffCD * 4.0);
    AssertTrue(DeepStallP.LiftToDragRatio < 3.0);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolAeroFoil.TestThermalUpdraftAltitudeClimbVsCalmAirGlideAndJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Foil, Restored: TCastleAeroFoilBehavior;
  InThermalPos, InThermalVel, OutThermalPos, OutThermalVel: TVector3;
  I: Integer;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Foil := TCastleAeroFoilBehavior.Create(RootOwner);
    Foil.Name := 'GliderFoil';
    Foil.Preset := afpHangGliderHighAspectWing;

    { 1. Inside thermal core (X=0, Z=0, +4.0 m/s updraft) vs. calm air outside thermal (X=60m, 0 m/s updraft) }
    InThermalPos := Vector3(0.0, 20.0, 0.0);
    InThermalVel := Vector3(0.0, 0.0, -20.0);
    OutThermalPos := Vector3(60.0, 20.0, 0.0);
    OutThermalVel := Vector3(0.0, 0.0, -20.0);

    for I := 1 to 20 do
    begin
      Foil.StepGliderFlight(InThermalPos, InThermalVel, 0.0, TVector3.Zero, 0.05);
      Foil.StepGliderFlight(OutThermalPos, OutThermalVel, 0.0, TVector3.Zero, 0.05);
    end;

    AssertTrue('Glider inside +4.0 m/s thermal updraft must climb significantly above calm-air glide',
      InThermalPos.Y > OutThermalPos.Y + 2.0);
    AssertTrue('Glider inside thermal must gain net altitude above 20.0m launch height',
      InThermalPos.Y > 21.0);

    ReportMd := TAeroFoilHelper.GenerateAeroReport(Foil);
    AssertTrue(Pos('Soaring Hang-Glider Wing', ReportMd) > 0);

    Foil.Preset := afpWingsuitDeltaMembrane;
    JsonStr := ComponentToString(Foil);
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleAeroFoilBehavior;
    AssertTrue(Restored.Preset = afpWingsuitDeltaMembrane);
    AssertSameValue(2.8, Restored.AspectRatio, 0.001);
    AssertSameValue(24.0, Restored.CriticalStallAngleDeg, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolAeroFoil);
end.
