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

{ Automated tests for Phase 336 Unreal Insights-Style Live Telemetry Ring-Buffer,
  Hierarchical Flame-Graph Spans, Chrome Trace Exporter, 56-Studio Hub Catalog
  & MCP cge_capture_telemetry_trace Parity. }
unit TestToolTelemetryInsights;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolTelemetryInsights = class(TCastleTestCase)
  published
    procedure TestRingBufferEvictionNestedFlameGraphPercentilesHitchDetectionAndChromeTraceJson;
    procedure TestMultiSystemHierarchyCapture56StudioHubCatalogAndMcpTelemetryTool;
  end;

implementation

uses
  fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform,
  CastleRibbonTrail, CastlePcgSettlement,
  ToolRibbonStudio, ToolSettlementStudio,
  ToolTelemetryInsights, ToolStudioHub, ToolMcpServer;

procedure TTestToolTelemetryInsights.TestRingBufferEvictionNestedFlameGraphPercentilesHitchDetectionAndChromeTraceJson;
var
  Prof: TTelemetryInsightsProfiler;
  I: Integer;
  Stats: TTelemetryAggregateStats;
  JsonStr, CsvStr, MdStr: String;
  ParsedRoot: TJSONData;
  EventsArr: TJSONArray;
begin
  Prof := TTelemetryInsightsProfiler.Create(10);
  try
    { Push 14 smooth 10.0ms frames (2000*5 us) + 1 28.0ms hitch spike -> 15 frames into 10-slot ring }
    for I := 0 to 13 do
      Prof.RecordSyntheticFrame(2000, 2000, 2000, 2000, 2000);
    Prof.RecordSyntheticFrame(4000, 11000, 3000, 4000, 6000);

    { Ring buffer must retain exactly 10 newest frames (FrameIndex 5..14) }
    AssertEquals(10, Prof.RetainedFrameCount);
    AssertEquals(5, Prof.GetFrame(0).FrameIndex);
    AssertEquals(14, Prof.GetFrame(9).FrameIndex);
    AssertEquals(9, Prof.FindWorstFrameLogicalIndex);

    { Verify nested Depth 0 / 1 / 2 flame-graph spans on each frame (1 root + 5 sub + 2 leaf = 8 spans) }
    AssertEquals(8, Prof.GetFrame(9).SpanCount);
    AssertEquals(0, Prof.GetFrame(9).Spans[0].Depth);

    Stats := Prof.ComputeAggregateStats(16.67);
    AssertEquals(10, Stats.CapturedFrames);
    AssertEquals(80, Stats.TotalSpansRecorded);
    AssertSameValue(10.0, Stats.MinFrameMs, 0.01);
    AssertSameValue(28.0, Stats.MaxFrameMs, 0.01);
    AssertSameValue(10.0, Stats.P50FrameMs, 0.01);
    AssertSameValue(28.0, Stats.P95FrameMs, 0.01);
    AssertSameValue(28.0, Stats.P99FrameMs, 0.01);
    AssertEquals(1, Stats.HitchSpikeCount);
    AssertEquals('MassECS', Stats.TopHotspotCategory);

    { Validate Chrome about://tracing / Perfetto traceEvents JSON }
    JsonStr := Prof.ExportChromeTraceJson;
    ParsedRoot := GetJSON(JsonStr);
    try
      AssertTrue(ParsedRoot is TJSONObject);
      EventsArr := TJSONObject(ParsedRoot).Arrays['traceEvents'];
      AssertEquals(80, EventsArr.Count);
      AssertEquals('X', EventsArr.Objects[0].Strings['ph']);
      AssertTrue(EventsArr.Objects[0].Int64s['dur'] > 0);
    finally
      FreeAndNil(ParsedRoot);
    end;

    CsvStr := Prof.ExportFrameMetricsCsv;
    AssertTrue(Pos('frame_index,total_ms,span_count', CsvStr) > 0);
    MdStr := Prof.BuildMarkdownReport(16.67);
    AssertTrue(Pos('Unreal Insights Live Telemetry', MdStr) > 0);
  finally
    FreeAndNil(Prof);
  end;
end;

procedure TTestToolTelemetryInsights.TestMultiSystemHierarchyCapture56StudioHubCatalogAndMcpTelemetryTool;
const
  Horizon7Ids: array[0..9] of String = (
    'motion_matching', 'mass_entity', 'voxel_studio', 'fluid_studio',
    'ragdoll_studio', 'commonui_mvvm', 'hlod_studio', 'ribbon_studio',
    'settlement_studio', 'telemetry_insights'
  );
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Rib: TCastleRibbonTrail;
  Beam: TCastleLightningBeam;
  Pillar: TCastleTransform;
  Settl: TCastlePcgSettlement;
  Prof: TTelemetryInsightsProfiler;
  Entry: TStudioCatalogEntry;
  Server: TCastleMcpServer;
  RespStr, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  I: Integer;
begin
  { 1. Verify all 96 Horizon 2-11 studios are cataloged in TStudioHubManager }
  AssertEquals(114, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon7Ids) do
    AssertTrue('Missing studio id: ' + Horizon7Ids[I],
      TStudioHubManager.FindStudioById(Horizon7Ids[I], Entry));

  DesignOwner := TComponent.Create(nil);
  Prof := TTelemetryInsightsProfiler.Create(64);
  Server := TCastleMcpServer.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TRibbonStudioHelper.SpawnKatanaSlashAndLightningDemo(Vp, DesignOwner, Rib, Beam, Pillar));
    AssertTrue(TSettlementStudioHelper.SpawnCrossroadsVillageDemo(Vp, DesignOwner, Settl));

    Prof.CaptureLiveHierarchyProfileRun(Vp, DesignOwner, 24);
    AssertEquals(24, Prof.RetainedFrameCount);
    AssertTrue(Prof.ComputeAggregateStats(16.67).TotalSpansRecorded >= 24 * 6);

    { 2. Verify MCP 15th tool: cge_capture_telemetry_trace }
    Server.AutonomyMode := mamReadOnly;
    Server.StandaloneDesignRoot := Vp;
    Server.StandaloneDesignOwner := DesignOwner;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":36,"method":"tools/call","params":{"name":"cge_capture_telemetry_trace","arguments":{"frames":12,"includeChromeTrace":true}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertEquals(12, TJSONObject(InnerJson).Integers['capturedFrames']);
        AssertTrue(TJSONObject(InnerJson).Floats['p95FrameMs'] > 0.0);
        AssertTrue(TJSONObject(InnerJson).Arrays['traceEvents'].Count >= 12 * 6);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Server);
    FreeAndNil(Prof);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolTelemetryInsights);

end.
