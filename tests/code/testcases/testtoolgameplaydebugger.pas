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

{ Automated tests for Phase 363 GameplayDebugger Live 3D HUD & Hotkey Channels Studio. }
unit TestToolGameplayDebugger;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolGameplayDebugger = class(TCastleTestCase)
  published
    procedure TestSixChannelMultiSubsystemAggregationAndNumpadBitmaskToggling;
    procedure TestOverlayDisableZeroOverheadDiagnosticJsonExportAndCleanRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleGameplayDebugger, ToolGameplayDebugger;

procedure TTestToolGameplayDebugger.TestSixChannelMultiSubsystemAggregationAndNumpadBitmaskToggling;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  Debugger: TCastleGameplayDebugger;
  Hero: TCastleTransform;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TGameplayDebuggerHelper.SpawnMultiSubsystemDebugSandbox(
      Vp, RootOwner, Debugger, Hero));

    { 1. All 6 channels (0..5) enabled -> exactly 6 HUD lines & 6 3D beacons across AI, LockOn, GAS, Mover2, Traffic & GI! }
    AssertEquals(63, Debugger.ChannelMask);
    AssertEquals('DebuggedPaladinHero', Debugger.ResolvedActorName);
    AssertEquals(6, Debugger.HudLineCount);
    AssertEquals(6, Debugger.MarkerCount);
    AssertTrue(Pos('Class.Paladin', Debugger.GetHudLine(2)) > 0);
    AssertTrue(Pos('DebugBossTarget', Debugger.GetHudLine(1)) > 0);

    { 2. Toggle Numpad '4' (MassTraffic) and Numpad '5' (SurfaceGI) OFF -> ChannelMask drops to 15 and HudLineCount drops to 4! }
    AssertFalse(Debugger.ToggleChannelByNumpadKey(4));
    AssertFalse(Debugger.ToggleChannelByNumpadKey(5));
    AssertEquals(15, Debugger.ChannelMask);
    AssertEquals(4, Debugger.CollectSnapshotFromWorld(Vp.Items));
    AssertEquals(4, Debugger.MarkerCount);

    { 3. Toggle Numpad '4' back ON -> HudLineCount rises to 5 }
    AssertTrue(Debugger.ToggleChannelByNumpadKey(4));
    AssertEquals(5, Debugger.CollectSnapshotFromWorld(Vp.Items));
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolGameplayDebugger.TestOverlayDisableZeroOverheadDiagnosticJsonExportAndCleanRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Debugger, Restored: TCastleGameplayDebugger;
  Hero: TCastleTransform;
  SnapJson, ReportMd, JsonStr: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TGameplayDebuggerHelper.SpawnMultiSubsystemDebugSandbox(
      Vp, RootOwner, Debugger, Hero));

    SnapJson := Debugger.ExportDiagnosticSnapshotJson;
    AssertTrue(Pos('debuggedActor', SnapJson) > 0);
    AssertTrue(Pos('DebuggedPaladinHero', SnapJson) > 0);
    AssertTrue(Pos('hudLines', SnapJson) > 0);

    ReportMd := TGameplayDebuggerHelper.GenerateDebuggerReport(Debugger);
    AssertTrue(Pos('[0] AI StateTree', ReportMd) > 0);

    { Disabling OverlayActive clears HUD lines, 3D markers, and transient marker geometry }
    Debugger.OverlayActive := False;
    AssertEquals(0, Debugger.CollectSnapshotFromWorld(Vp.Items));
    AssertEquals(0, Debugger.MarkerCount);
    AssertEquals(0, Debugger.Count);

    Debugger.OverlayActive := True;
    Debugger.ChannelMask := 21; { Channels 0, 2, 4 }
    Debugger.CollectSnapshotFromWorld(Vp.Items);

    JsonStr := ComponentToString(Debugger);
    AssertEquals(0, Pos('TransientGameplayDebuggerMarkers', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleGameplayDebugger;
    AssertEquals(21, Restored.ChannelMask);
    AssertEquals('DebuggedPaladinHero', Restored.DebuggedActorName);
    AssertEquals(0, Restored.Count);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolGameplayDebugger);
end.
