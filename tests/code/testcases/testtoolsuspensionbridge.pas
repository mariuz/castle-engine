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

{ Automated tests for Phase 389: Procedural Rope Suspension Bridge, Live-Load
  Plank Deflection, Roll Tilt & Broken-Slat Hazard Studio. }
unit TestToolSuspensionBridge;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSuspensionBridge = class(TCastleTestCase)
  published
    procedure TestPinnedEndpointInvarianceLiveLoadDeflectionAndLateralRollTorque;
    procedure TestDwarvenIronStiffnessRottedBrokenPlankDeterminismAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleSuspensionBridge, ToolSuspensionBridge;

procedure TTestToolSuspensionBridge.TestPinnedEndpointInvarianceLiveLoadDeflectionAndLateralRollTorque;
var
  Root: TComponent;
  VP: TCastleViewport;
  Bridge: TCastleSuspensionBridge;
  UnloadedMidY, LoadedMidY, DropStart, DropEnd, DropAtLoad, RollStart, RollLoad: Single;
  DummyDrop, DummyRoll, UnloadedDrop: Single;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSuspensionBridgeHelper.SpawnChasmBridgeDemo(Root, Root, Bridge));

    Bridge.EvaluateDeckAtNormalizedT(0.35, UnloadedMidY, UnloadedDrop, DummyRoll);
    AssertSameValue(0.0, UnloadedDrop, 0.0001);

    { Apply 280 kg troll off-center at t=0.35, +0.70m toward East handrail }
    Bridge.ApplyWalkerLoad(0.35, 0.70, 280.0);

    { Endpoints t=0 and t=1 must remain strictly pinned with 0 live drop & 0 roll }
    Bridge.EvaluateDeckAtNormalizedT(0.0, DummyDrop, DropStart, RollStart);
    Bridge.EvaluateDeckAtNormalizedT(1.0, DummyDrop, DropEnd, DummyRoll);
    AssertSameValue(0.0, DropStart, 0.0001);
    AssertSameValue(0.0, DropEnd, 0.0001);
    AssertSameValue(0.0, RollStart, 0.0001);

    { Loaded point t=0.35 drops significantly further below unloaded sag & rolls }
    Bridge.EvaluateDeckAtNormalizedT(0.35, LoadedMidY, DropAtLoad, RollLoad);
    AssertTrue('280 kg point load depresses vine bridge > 0.15m deeper',
      (LoadedMidY < UnloadedMidY - 0.15) and (DropAtLoad < -0.15));
    AssertTrue('Positive +X lateral offset induces positive roll angle',
      RollLoad > 0.05);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolSuspensionBridge.TestDwarvenIronStiffnessRottedBrokenPlankDeterminismAndJsonRoundtrip;
var
  Bridge, Restored: TCastleSuspensionBridge;
  VineDrop, IronDrop, DummyY, DummyRoll: Single;
  SerializedScene, JsonCfg, Md: String;
  FirstBrokenCount: Integer;
begin
  Bridge := TCastleSuspensionBridge.Create(nil);
  Restored := TCastleSuspensionBridge.Create(nil);
  try
    Bridge.ApplyPreset(sbpJungleVineFootbridge);
    Bridge.ApplyWalkerLoad(0.50, 0.0, 250.0);
    Bridge.EvaluateDeckAtNormalizedT(0.50, DummyY, VineDrop, DummyRoll);

    Bridge.ApplyPreset(sbpDwarvenIronChainSpan);
    Bridge.ApplyWalkerLoad(0.50, 0.0, 250.0);
    Bridge.EvaluateDeckAtNormalizedT(0.50, DummyY, IronDrop, DummyRoll);
    AssertTrue('Dwarven iron chains deflect < 20% as much as jungle vines',
      Abs(IronDrop) < Abs(VineDrop) * 0.20);

    { Rotted chasm trap preset deterministically removes interior planks while
      keeping first (0) and last (N-1) abutment planks intact }
    Bridge.ApplyPreset(sbpRottedChasmTrapBridge);
    AssertFalse(Bridge.IsPlankBroken(0));
    AssertFalse(Bridge.IsPlankBroken(Bridge.PlankCount - 1));
    FirstBrokenCount := Bridge.BrokenGapCount;
    AssertTrue('Rotted chasm bridge contains broken gaps', FirstBrokenCount >= 3);
    Bridge.RebuildBridge;
    AssertEquals(FirstBrokenCount, Bridge.BrokenGapCount);

    { Transient 3D plank/cable geometry excluded from ComponentToString }
    SerializedScene := ComponentToString(Bridge);
    AssertTrue(Pos('SuspensionBridgePreview', SerializedScene) = 0);

    JsonCfg := TSuspensionBridgeHelper.ExportBridgeJson(Bridge);
    AssertTrue(TSuspensionBridgeHelper.ImportBridgeJson(Restored, JsonCfg));
    AssertEquals(Ord(sbpRottedChasmTrapBridge), Ord(Restored.Preset));
    AssertEquals(FirstBrokenCount, Restored.BrokenGapCount);
    Md := TSuspensionBridgeHelper.GenerateMarkdownReport(Bridge);
    AssertTrue(Pos('RottedChasmTrapBridge', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Bridge);
  end;
end;

initialization
  RegisterTest(TTestToolSuspensionBridge);

end.
