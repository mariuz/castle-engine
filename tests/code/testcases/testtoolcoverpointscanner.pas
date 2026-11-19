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

{ Automated tests for Phase 384 Tactical Cover Point Scanner, Crouch-Peek /
  Corner-Lean & Threat Exposure Studio. }
unit TestToolCoverPointScanner;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolCoverPointScanner = class(TCastleTestCase)
  published
    procedure TestWaistJerseyBarrierOverPeekVsTallPillarCornerLeanClassification;
    procedure TestMultiThreatFlankInvalidationSafeSelectionAndTransientCleanJson;
  end;

implementation

uses
  Math, CastleVectors, CastleViewport, CastleComponentSerialize,
  CastleCoverPointScanner, ToolCoverPointScanner;

procedure TTestToolCoverPointScanner.TestWaistJerseyBarrierOverPeekVsTallPillarCornerLeanClassification;
var
  Owner: TComponent;
  Vp: TCastleViewport;
  Scanner: TCastleCoverPointScanner;
  I: Integer;
  Node: TCoverNodeCandidate;
  FoundWaistPeek, FoundPillarCornerLean: Boolean;
begin
  Owner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TCoverPointScannerHelper.SpawnKillhouseCoverArena(Vp, Owner, Scanner));
    AssertTrue(Scanner <> nil);
    AssertTrue(Scanner.CoverNodeCount >= 6);
    AssertTrue(Scanner.WaistCoverCount >= 2);
    AssertTrue(Scanner.FullCoverCount >= 2);

    FoundWaistPeek := False;
    FoundPillarCornerLean := False;
    for I := 0 to Scanner.CoverNodeCount - 1 do
    begin
      Node := Scanner.GetCoverNode(I);
      if (Node.Posture = cpkWaistCrouchOverPeek) and Node.CanPeekOverTop then
        FoundWaistPeek := True;
      if (Node.Posture = cpkFullStandingCornerLean) and (not Node.CanPeekOverTop) and
         (Node.CanLeanLeft or Node.CanLeanRight) then
        FoundPillarCornerLean := True;
    end;
    AssertTrue(FoundWaistPeek);
    AssertTrue(FoundPillarCornerLean);
  finally
    FreeAndNil(Owner);
  end;
end;

procedure TTestToolCoverPointScanner.TestMultiThreatFlankInvalidationSafeSelectionAndTransientCleanJson;
var
  Owner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Scanner, Restored: TCastleCoverPointScanner;
  BestSingle, BestCrossfire: TCoverNodeCandidate;
  SafeSingle, SafeOppositePincer: Integer;
  SavedJson, Cfg, Md: String;
begin
  Owner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(Owner);
    AssertTrue(TCoverPointScannerHelper.SpawnKillhouseCoverArena(Vp, Owner, Scanner));

    { 1. North sniper at (0, 0, -14): safe spots sit on the sheltered +Z south side of obstacles }
    SafeSingle := Scanner.EvaluateBestCoverAgainstThreats(Vp.Items,
      [Vector3(0.0, 0.0, -14.0)], BestSingle);
    AssertTrue(SafeSingle >= 2);
    AssertTrue(SafeSingle < Scanner.CoverNodeCount);
    AssertTrue(BestSingle.ProtectedFromThreats);
    AssertTrue(BestSingle.WorldPos.Z > 0.40);

    { 2. Adding a rear +Z flanker at (-3.5, 0, +14) invalidates south-side barrier spots }
    SafeOppositePincer := Scanner.EvaluateBestCoverAgainstThreats(Vp.Items,
      [Vector3(-3.5, 0.0, -14.0), Vector3(-3.5, 0.0, 14.0)], BestCrossfire);
    AssertTrue(SafeOppositePincer < SafeSingle);

    Md := TCoverPointScannerHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Tactical Cover Point Scanner & Threat Flanking Report', Md) > 0);

    { 3. Verify csTransient markers never leak into serialized JSON + ConfigJson roundtrip }
    Scanner.ApplyPreset(cspHeavyMechBarricade);
    SavedJson := ComponentToString(Scanner);
    AssertEquals(0, Pos('TransientCoverMarkers', SavedJson));
    Cfg := Scanner.ConfigJson;
    Restored := StringToComponent(SavedJson, RestoredOwner) as TCastleCoverPointScanner;
    AssertTrue(Restored <> nil);
    Restored.ConfigJson := Cfg;
    AssertEquals(Ord(cspHeavyMechBarricade), Ord(Restored.Preset));
    AssertSameValue(3.10, Restored.StandingEyeHeightMeters, 0.001);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(Owner);
  end;
end;

initialization
  RegisterTest(TTestToolCoverPointScanner);

end.
