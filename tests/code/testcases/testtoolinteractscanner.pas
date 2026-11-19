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

{ Automated tests for Phase 394: Gameplay Interaction Focus Scanner (WorldRay
  Gaze + Proximity Cone, Hold-Progress Ring & Obstruction Gate) Studio. }
unit TestToolInteractScanner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolInteractScanner = class(TCastleTestCase)
  published
    procedure TestGazeVsPeripheralScoringAndThroughWallWorldRayRejection;
    procedure TestTimedHoldProgressReleaseDecayCooldownAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleInteractScanner, ToolInteractScanner;

procedure TTestToolInteractScanner.TestGazeVsPeripheralScoringAndThroughWallWorldRayRejection;
var
  Root: TComponent;
  VP: TCastleViewport;
  Scanner: TCastleInteractScanner;
  I: Integer;
  C: TInteractCandidateScore;
  SawBlockedChest: Boolean;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TInteractScannerHelper.SpawnVaultRoomInteractDemo(Root, Root, Scanner));

    { 1. Interact_KeycardSabotageTerminal wins focus over peripheral crate AND
         over Interact_VaultChestBehindWall (blocked by LockedVaultDoorSlab)! }
    AssertEquals('Interact_KeycardSabotageTerminal', Scanner.FocusedTargetName);

    SawBlockedChest := False;
    for I := 0 to Scanner.CandidateCount - 1 do
    begin
      C := Scanner.GetCandidate(I);
      if C.TargetName = 'Interact_VaultChestBehindWall' then
      begin
        SawBlockedChest := True;
        AssertTrue('Behind-wall chest flagged ObstructedByWall', C.ObstructedByWall);
      end;
    end;
    AssertTrue(SawBlockedChest);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolInteractScanner.TestTimedHoldProgressReleaseDecayCooldownAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Scanner, Restored: TCastleInteractScanner;
  Triggered: String;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleInteractScanner.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TInteractScannerHelper.SpawnVaultRoomInteractDemo(Root, Root, Scanner));
    { HoldDurationSec = 1.20s }

    { 1. Hold for 0.60s -> reaches 50%, does NOT trigger yet }
    AssertFalse(Scanner.StepHoldInteraction(VP.Items, True, 0.60, Triggered));
    AssertSameValue(0.50, Scanner.HoldProgress01, 0.02);

    { 2. Release button for 0.20s -> HoldProgress01 decays down (< 0.30) }
    AssertFalse(Scanner.StepHoldInteraction(VP.Items, False, 0.20, Triggered));
    AssertTrue('Early button release decays hold progress',
      Scanner.HoldProgress01 < 0.30);

    { 3. Hold for full 1.10s -> crosses 100%, triggers completion & enters cooldown! }
    AssertTrue(Scanner.StepHoldInteraction(VP.Items, True, 1.10, Triggered));
    AssertEquals('Interact_KeycardSabotageTerminal', Triggered);
    AssertEquals(1, Scanner.CompletedInteractionsCount);
    AssertEquals(Ord(ihsCompletedCooldown), Ord(Scanner.HoldStatus));

    { Immediate repeat step while in RepeatCooldownSec (0.60s) is suppressed }
    AssertFalse(Scanner.StepHoldInteraction(VP.Items, True, 0.10, Triggered));
    AssertEquals(1, Scanner.CompletedInteractionsCount);

    SerializedScene := ComponentToString(Scanner);
    AssertTrue(Pos('InteractScannerPreview', SerializedScene) = 0);

    Scanner.MaxInteractRangeMeters := 6.2;
    JsonCfg := TInteractScannerHelper.ExportScannerJson(Scanner);
    AssertTrue(TInteractScannerHelper.ImportScannerJson(Restored, JsonCfg));
    AssertSameValue(6.2, Restored.MaxInteractRangeMeters, 0.01);
    Md := TInteractScannerHelper.GenerateMarkdownReport(Scanner);
    AssertTrue(Pos('Interact_KeycardSabotageTerminal', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolInteractScanner);

end.
