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

{ Automated tests for Phase 376 Editor Action Macro Recorder,
  96-Studio Hub & 19-Tool MCP Upgrade. }
unit TestToolMacroRecorder;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolMacroRecorder = class(TCastleTestCase)
  published
    procedure TestMultiStepFilteredMacroRecordingJsonExportImportAndParameterizedReplay;
    procedure TestUnified96StudioHubCatalogAnd19thMcpRunEditorMacroTool;
  end;

implementation

uses fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport,
  ToolMacroRecorder, ToolStudioHub, ToolMcpServer;

procedure TTestToolMacroRecorder.TestMultiStepFilteredMacroRecordingJsonExportImportAndParameterizedReplay;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  RecA, RecB: TEditorMacroRecorder;
  Crate1, Lamp: TCastleTransform;
  ExportedJson: String;
begin
  RootOwner := TComponent.Create(nil);
  RecA := TEditorMacroRecorder.Create;
  RecB := TEditorMacroRecorder.Create;
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertEquals(4, TEditorMacroRecorder.SpawnCratePillarsDemo(Vp, RootOwner));

    Crate1 := RootOwner.FindComponent('MacroCrate_1') as TCastleTransform;
    Lamp := RootOwner.FindComponent('PropStreetLamp') as TCastleTransform;
    AssertTrue(Crate1 <> nil);
    AssertTrue(Lamp <> nil);

    { 1. Record 3 steps targeting 'MacroCrate' only }
    RecA.StartRecording('StackCratesMacro');
    AssertTrue(RecA.IsRecording);
    RecA.RecordStep(mskAddTranslate, 'MacroCrate', Vector3(0.0, 2.0, 0.0));
    RecA.RecordStep(mskMultiplyScale, 'MacroCrate', Vector3(1.0, 1.5, 1.0));
    RecA.RecordStep(mskSetTag, 'MacroCrate', TVector3.Zero, 42.0);
    RecA.StopRecording;
    AssertFalse(RecA.IsRecording);

    { 2. Roundtrip macro pipeline via JSON into RecB }
    ExportedJson := RecA.ExportMacroJson;
    AssertTrue(RecB.ImportMacroJson(ExportedJson));
    AssertEquals('StackCratesMacro', RecB.MacroName);
    AssertEquals(3, RecB.StepCount);

    { 3. Replay with DeltaMultiplier = 2.0 -> +4.0m Y lift, 1.5x Y scale, Tag = 84 on 4 crates, PropStreetLamp untouched! }
    AssertEquals(4, RecB.ReplayMacro(Vp, 2.0));
    AssertSameValue(0.6 + 4.0, Crate1.Translation.Y, 1e-4);
    AssertSameValue(1.5, Crate1.Scale.Y, 1e-4);
    AssertEquals(84, Crate1.Tag);

    { Unmatched PropStreetLamp must remain completely untouched }
    AssertSameValue(1.9, Lamp.Translation.Y, 1e-4);
    AssertSameValue(1.0, Lamp.Scale.Y, 1e-4);
    AssertEquals(0, Lamp.Tag);
  finally
    FreeAndNil(RecB);
    FreeAndNil(RecA);
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolMacroRecorder.TestUnified96StudioHubCatalogAnd19thMcpRunEditorMacroTool;
const
  Horizon11Ids: array[0..5] of String = (
    'substrate_studio', 'fire_grid_2d', 'gameplay_messenger',
    'octahedral_impostor', 'pose_snapshot', 'macro_recorder'
  );
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Crate2: TCastleTransform;
  Server: TCastleMcpServer;
  Entry: TStudioCatalogEntry;
  RespStr, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  I: Integer;
begin
  { 1. Verify all 100 UE 5.x studios across Horizons 2-11 are indexed in TStudioHubManager }
  AssertEquals(103, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon11Ids) do
    AssertTrue('Missing Horizon 11 studio in Hub: ' + Horizon11Ids[I],
      TStudioHubManager.FindStudioById(Horizon11Ids[I], Entry));

  TEditorMacroRecorder.SharedRecorder.ClearSteps;
  DesignOwner := TComponent.Create(nil);
  Server := TCastleMcpServer.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    AssertEquals(4, TEditorMacroRecorder.SpawnCratePillarsDemo(Vp, DesignOwner));
    Crate2 := DesignOwner.FindComponent('MacroCrate_2') as TCastleTransform;
    AssertTrue(Crate2 <> nil);

    Server.AutonomyMode := mamEditWithUndo;
    Server.StandaloneDesignRoot := Vp;
    Server.StandaloneDesignOwner := DesignOwner;

    { 2. Record a macro step via 19th MCP tool cge_run_editor_macro }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":76,"method":"tools/call","params":{"name":"cge_run_editor_macro","arguments":{"action":"record_step","stepKind":"add_translate","targetFilter":"MacroCrate","vecX":0,"vecY":3.5,"vecZ":0}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertTrue(TJSONObject(InnerJson).Booleans['ok']);
        AssertEquals(1, TJSONObject(InnerJson).Integers['stepCount']);
        AssertEquals(103, TJSONObject(InnerJson).Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    { 3. Replay macro via MCP with multiplier = 2.0 -> +7.0m Y translation on all 4 MacroCrates! }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":77,"method":"tools/call","params":{"name":"cge_run_editor_macro","arguments":{"action":"replay","multiplier":2.0}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertTrue(TJSONObject(InnerJson).Booleans['ok']);
        AssertEquals(4, TJSONObject(InnerJson).Integers['affectedTransforms']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    AssertSameValue(0.6 + 7.0, Crate2.Translation.Y, 1e-4);
  finally
    TEditorMacroRecorder.SharedRecorder.ClearSteps;
    FreeAndNil(Server);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolMacroRecorder);
end.
