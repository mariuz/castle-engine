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

{ Automated tests for Phase 340 Landscape Thermal Talus & Droplet Hydraulic
  Erosion, Mass Conservation, RGBA Splatmap Baking & JSON Roundtrips. }
unit TestToolErosionStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolErosionStudio = class(TCastleTestCase)
  published
    procedure TestThermalTalusExactMassConservationAndCliffSlopeRelaxation;
    procedure TestHydraulicRaindropGulliesPartitionOfUnitySplatmapAndCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleImages, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleErosionBaker, ToolErosionStudio;

procedure TTestToolErosionStudio.TestThermalTalusExactMassConservationAndCliffSlopeRelaxation;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Baker: TCastleTerrainErosionBaker;
  VolBefore, VolAfter: Double;
  SlopeBefore, SlopeAfter: Single;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Baker := TCastleTerrainErosionBaker.Create(DesignOwner);
    Baker.Name := 'MesaErosionTest';
    Baker.Preset := etpMesaPlateauEscarpment;
    Baker.TalusAngleDeg := 32.0;
    Vp.Items.Add(Baker);

    VolBefore := Baker.TotalTerrainVolume;
    SlopeBefore := Baker.MaxSlopeAngleDeg;
    AssertTrue(SlopeBefore > 65.0);

    { Run 25 thermal talus repose passes }
    Baker.RunThermalErosionSteps(25);
    VolAfter := Baker.TotalTerrainVolume;
    SlopeAfter := Baker.MaxSlopeAngleDeg;

    { 1. Exact mass conservation across symmetric flux exchanges }
    AssertSameValue(VolBefore, VolAfter, 0.25);
    { 2. Steep vertical cliff slumps noticeably toward TalusAngleDeg }
    AssertTrue(SlopeAfter < SlopeBefore - 12.0);
    { 3. Positive scree deposition recorded at cliff toe }
    AssertTrue(Baker.TotalDepositedMeters > 1.0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolErosionStudio.TestHydraulicRaindropGulliesPartitionOfUnitySplatmapAndCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Baker, RestoredBaker: TCastleTerrainErosionBaker;
  SplatImg: TRGBAlphaImage;
  X, Z, SumRGBA: Integer;
  Pix: TVector4Byte;
  Warnings: TStringList;
  Sum: TErosionStudioSummary;
  JsonStr, ReportMd: String;
  MaxFlow: Single;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TErosionStudioHelper.SpawnErodedAlpinePeakDemo(Vp, DesignOwner, Baker));
    AssertTrue(Baker <> nil);
    AssertEquals(8, Baker.ThermalPassesRun);
    AssertEquals(1200, Baker.DropletsSimulated);
    AssertTrue(Baker.TotalErodedMeters > 0.5);
    AssertTrue(Baker.TotalDepositedMeters > 0.5);

    MaxFlow := 0.0;
    for Z := 0 to Baker.GridSize - 1 do
      for X := 0 to Baker.GridSize - 1 do
        if Baker.SampleFlow(X, Z) > MaxFlow then
          MaxFlow := Baker.SampleFlow(X, Z);
    AssertTrue(MaxFlow > 0.25);

    { Bake 4-channel RGBA splatmap and verify exact R+G+B+A = 255 partition of unity }
    SplatImg := Baker.ExportSplatmapRgbaImage;
    try
      AssertEquals(Baker.GridSize, Integer(SplatImg.Width));
      AssertEquals(Baker.GridSize, Integer(SplatImg.Height));
      for Z := 0 to Baker.GridSize - 1 do
        for X := 0 to Baker.GridSize - 1 do
        begin
          Pix := SplatImg.PixelPtr(X, Z)^;
          SumRGBA := Integer(Pix.X) + Integer(Pix.Y) + Integer(Pix.Z) + Integer(Pix.W);
          AssertEquals(255, SumRGBA);
        end;
    finally
      FreeAndNil(SplatImg);
    end;

    Sum := TErosionStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.BakerCount);
    AssertEquals(0, Sum.WarningsCount);
    ReportMd := TErosionStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Landscape Thermal & Hydraulic Erosion Report', ReportMd) > 0);

    { Verify csTransient terrain mesh never leaks into serialized JSON }
    JsonStr := ComponentToString(Baker);
    AssertEquals(0, Pos('TransientErosionTerrainMesh', JsonStr));

    RestoredBaker := StringToComponent(JsonStr, RestoredOwner) as TCastleTerrainErosionBaker;
    AssertTrue(RestoredBaker <> nil);
    AssertEquals(8, RestoredBaker.ThermalPassesRun);
    AssertEquals(1200, RestoredBaker.DropletsSimulated);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolErosionStudio);

end.
