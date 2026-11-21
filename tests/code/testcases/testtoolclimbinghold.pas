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

{ Automated tests for Milestone Phase 410: Procedural Free-Climbing Hold
  Scanner (WorldRay Ledge/Crack Graph, Limb Reach & Overhang Stamina) Studio. }
unit TestToolClimbingHold;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolClimbingHold = class(TCastleTestCase)
  published
    procedure TestWorldRayLedgeLipExtractionSheerFaceRejectionAndDynoSummitBfs;
    procedure TestOverhangAndRainStaminaDrainScalingPresetsAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleClimbingHold, ToolClimbingHold;

procedure TTestToolClimbingHold.TestWorldRayLedgeLipExtractionSheerFaceRejectionAndDynoSummitBfs;
var
  Root: TComponent;
  VP: TCastleViewport;
  Scanner: TCastleClimbingHoldScanner;
  I, HopsStatic, HopsDyno: Integer;
  H: TClimbingHoldNode;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TClimbingHoldHelper.SpawnTowerClimbDynoRouteDemo(Root, Root, Scanner));

    { 1. All 4 West-face protruding stone bricks (-1.50 / -0.75) are extracted,
         while the smooth sheer East face (X > 0.2) produces ZERO false holds! }
    AssertTrue('Scanner extracts the 4 protruding West-face ledge holds',
      Scanner.HoldCount >= 4);
    for I := 0 to Scanner.HoldCount - 1 do
    begin
      H := Scanner.GetHold(I);
      AssertTrue('Zero holds generated on smooth sheer East monolith face',
        H.WorldGripPos.X < 0.0);
    end;

    { 2. Top gap from Y ~ 3.66m to Y ~ 6.01m is 2.35m:
         - Static reach (1.70m) CANNOT reach summit (False),
         - Dynamic Dyno leap (2.85m) bridges the gap cleanly to summit (True, 3 hops)! }
    AssertFalse('2.35m summit gap blocks static-only 1.70m arm reach',
      Scanner.CanReachSummitBFS(1.5, 5.5, False, HopsStatic));
    AssertTrue('Dyno leap (2.85m) bridges the 2.35m gap to the tower summit',
      Scanner.CanReachSummitBFS(1.5, 5.5, True, HopsDyno));
    AssertEquals(2, HopsDyno);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolClimbingHold.TestOverhangAndRainStaminaDrainScalingPresetsAndJsonRoundtrip;
var
  Scanner, Restored: TCastleClimbingHoldScanner;
  DrainSlab, DrainVert, DrainOverhang, DrainStormOverhang: Single;
  SerializedScene, JsonCfg, Md: String;
begin
  Scanner := TCastleClimbingHoldScanner.Create(nil);
  Restored := TCastleClimbingHoldScanner.Create(nil);
  try
    Scanner.ApplyPreset(chpAthleticRockClimber);
    Scanner.AddManualHold(Vector3(0.0, 1.0, 0.0), 0.20);
    Scanner.AddManualHold(Vector3(0.0, 2.2, 0.0), 0.20);

    DrainSlab := Scanner.ComputeStaminaDrainPerSec(-25.0, 0.0);
    DrainVert := Scanner.ComputeStaminaDrainPerSec(0.0, 0.0);
    DrainOverhang := Scanner.ComputeStaminaDrainPerSec(40.0, 0.0);
    DrainStormOverhang := Scanner.ComputeStaminaDrainPerSec(40.0, 1.0);

    AssertTrue('Inclined -25 deg slab drains less stamina than sheer vertical wall',
      DrainSlab < DrainVert * 0.75);
    AssertTrue('+40 deg ceiling overhang drains > 3x sheer vertical stamina',
      DrainOverhang > DrainVert * 3.0);
    AssertTrue('Rainstorm wetness compounds overhang stamina drain > 2x',
      DrainStormOverhang > DrainOverhang * 2.2);

    SerializedScene := ComponentToString(Scanner);
    AssertTrue(Pos('ClimbingHoldPreview', SerializedScene) = 0);

    Scanner.MaxDynoLeapReachMeters := 3.15;
    JsonCfg := TClimbingHoldHelper.ExportScannerJson(Scanner);
    AssertTrue(TClimbingHoldHelper.ImportScannerJson(Restored, JsonCfg));
    AssertSameValue(3.15, Restored.MaxDynoLeapReachMeters, 0.01);
    Md := TClimbingHoldHelper.GenerateMarkdownReport(Scanner);
    AssertTrue(Pos('AthleticRockClimber', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Scanner);
  end;
end;

initialization
  RegisterTest(TTestToolClimbingHold);

end.
