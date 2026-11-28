{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 397: Take Recorder & Live Link Real-Time Streaming
  (UTakeRecorder / ILiveLinkClient Parity), 117-Studio Hub & 40th MCP Tool
  (cge_record_take_livelink). }
unit TestToolTakeRecorder;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, fpjson, jsonparser,
  CastleTester, CastleVectors, CastleComponentSerialize,
  CastleUIControls, CastleViewport, CastleTransform,
  CastleTakeRecorder, ToolTakeRecorder, ToolStudioHub, ToolMcpServer;

type
  TTestToolTakeRecorder = class(TCastleTestCase)
  published
    procedure TestDouglasPeuckerKeyReductionErrorBoundAndAutoIncrementSlateTake;
    procedure TestLiveLinkDeJitterBufferInterpolationHealthTimeoutAndCleanJsonRoundtrip;
    procedure TestUnified117StudioHubAnd40thMcpRecordTakeLiveLink;
  end;

implementation

procedure TTestToolTakeRecorder.TestDouglasPeuckerKeyReductionErrorBoundAndAutoIncrementSlateTake;
var
  OwnerComp, RootUi: TComponent;
  VP: TCastleViewport;
  Rec: TCastleTakeRecorder;
  I: Integer;
  EvalRaw, EvalRed: TTakeKeyframe;
begin
  OwnerComp := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    VP := TCastleViewport.Create(OwnerComp);
    TCastleUserInterface(RootUi).InsertFront(VP);

    Rec := TTakeRecorderHelper.SpawnTakeRecorderPresetInDesign(
      RootUi, OwnerComp, trpMocapDuelAndCineCam, Vector3(0, 0, 0));
    AssertTrue(Rec <> nil);
    AssertEquals(1, Rec.TakeNumber);
    AssertEquals(3, Rec.TrackCount);
    AssertEquals('01:00:04:00', Rec.FormatSmpteTimecode(4.0));

    { 3 tracks * 241 frames @ 60Hz = 723 Raw Keys -> Douglas-Peucker reduces >= 85%! }
    AssertEquals(723, Rec.TotalRawKeyCount);
    AssertTrue(Rec.TotalReducedKeyCount <= 90);
    AssertTrue(Rec.KeyReductionPercent >= 85.0);

    { Every track MUST strictly obey the 1.5 cm PosReduceToleranceM bound across ALL 241 frames! }
    for I := 0 to Rec.TrackCount - 1 do
      AssertTrue(Rec.Tracks[I].MaxPosErrorM <= Rec.PosReduceToleranceM + 0.0002);

    { Sharp corner at t = 1.50s (Hero dodge pivot at X=0, Z=-2) is preserved within 1.5 cm }
    AssertTrue(Rec.EvaluateTrackAtTime(0, 1.50, False, EvalRaw));
    AssertTrue(Rec.EvaluateTrackAtTime(0, 1.50, True, EvalRed));
    AssertTrue(PointsDistance(EvalRaw.Location, EvalRed.Location) <= 0.0152);

    { Starting a second take on the same SlateName auto-increments TakeNumber 1 -> 2 }
    Rec.SimulatePresetTakeCapture(2.0);
    AssertEquals(2, Rec.TakeNumber);

    { Changing SlateName resets TakeNumber back to 1 }
    Rec.StartNewTake('Slate_FinalBossCutscene');
    Rec.StopAndFinalizeTake;
    AssertEquals(1, Rec.TakeNumber);
    AssertEquals('Slate_FinalBossCutscene', Rec.SlateName);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolTakeRecorder.TestLiveLinkDeJitterBufferInterpolationHealthTimeoutAndCleanJsonRoundtrip;
var
  OwnerComp, RehydratedOwner: TComponent;
  Rec, RehydratedRec: TCastleTakeRecorder;
  Sample: TLiveLinkFrameSample;
  Status: TLiveLinkSubjectStatus;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Rec := TCastleTakeRecorder.Create(OwnerComp);
    Rec.Name := 'TestLiveLinkHub';
    Rec.StaleTimeoutSec := 0.25;
    Rec.DroppedTimeoutSec := 1.00;

    { Configure a Camera LiveLink stream with exact 50ms (0.05s) de-jitter buffer offset }
    Rec.EnsureLiveLinkSubject('VCam_Crane_Alpha', llrCamera, 'CineCamCrane', 0.05);
    Rec.PushLiveLinkFrame('VCam_Crane_Alpha', llrCamera, 10.00,
      Vector3(0.0, 2.0, 0.0), Vector3(0, 0, 0), 40.0, 3.0);
    Rec.PushLiveLinkFrame('VCam_Crane_Alpha', llrCamera, 10.10,
      Vector3(10.0, 4.0, 0.0), Vector3(0, 20, 0), 60.0, 7.0);

    { At WorldTime = 10.10s, QueryTime = 10.10 - 0.05 = 10.05s -> exact 50% midpoint! }
    AssertTrue(Rec.EvaluateLiveLinkSubject('VCam_Crane_Alpha', 10.10, Sample, Status));
    AssertTrue(Status = llsActiveGreen);
    AssertSameValue(5.0, Sample.Location.X, 0.001);
    AssertSameValue(3.0, Sample.Location.Y, 0.001);
    AssertSameValue(50.0, Sample.FovDeg, 0.01);
    AssertSameValue(5.0, Sample.FocusDistanceM, 0.01);

    { Packet silence of 0.40s (> 0.25s StaleTimeout, <= 1.00s DroppedTimeout) -> Stale Yellow }
    AssertTrue(Rec.EvaluateLiveLinkSubject('VCam_Crane_Alpha', 10.50, Sample, Status));
    AssertTrue(Status = llsStaleYellow);

    { Packet silence of 1.25s (> 1.00s DroppedTimeout) -> Dropped Red }
    AssertTrue(Rec.EvaluateLiveLinkSubject('VCam_Crane_Alpha', 11.35, Sample, Status));
    AssertTrue(Status = llsDroppedRed);

    { Lossless JSON serialization roundtrip }
    JsonStr := ComponentToString(Rec);
    RehydratedOwner := TComponent.Create(nil);
    try
      RehydratedRec := StringToComponent(JsonStr, RehydratedOwner) as TCastleTakeRecorder;
      AssertEquals(Rec.TrackCount, RehydratedRec.TrackCount);
      AssertEquals(Rec.TotalReducedKeyCount, RehydratedRec.TotalReducedKeyCount);
      AssertEquals(Rec.SlateName, RehydratedRec.SlateName);
    finally
      FreeAndNil(RehydratedOwner);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolTakeRecorder.TestUnified117StudioHubAnd40thMcpRecordTakeLiveLink;
var
  Entry: TStudioCatalogEntry;
  Mcp: TCastleMcpServer;
  OwnerComp, RootUi: TComponent;
  VP: TCastleViewport;
  ListResp, CallResp, MdReport: String;
  ParsedResp, InnerData: TJSONData;
  ToolsArr: TJSONArray;
  FoundTool: Boolean;
  I: Integer;
begin
  AssertEquals(118, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('take_recorder_livelink', Entry));
  AssertEquals(397, Entry.PhaseNumber);

  OwnerComp := TComponent.Create(nil);
  Mcp := TCastleMcpServer.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    RootUi.Name := 'RootUi';
    VP := TCastleViewport.Create(OwnerComp);
    VP.Name := 'ViewportMain';
    TCastleUserInterface(RootUi).InsertFront(VP);

    Mcp.AutonomyMode := mamFullControl;
    Mcp.StandaloneDesignRoot := RootUi;
    Mcp.StandaloneDesignOwner := OwnerComp;

    ListResp := Mcp.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    ParsedResp := GetJSON(ListResp);
    try
      ToolsArr := ParsedResp.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(41, ToolsArr.Count);
      FoundTool := False;
      for I := 0 to ToolsArr.Count - 1 do
        if TJSONObject(ToolsArr.Items[I]).Get('name', '') = 'cge_record_take_livelink' then
          FoundTool := True;
      AssertTrue(FoundTool);
    finally
      FreeAndNil(ParsedResp);
    end;

    { 1. Spawn Take Recorder via MCP }
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_record_take_livelink","arguments":{"action":"spawn_preset","preset":"mocap_duel"}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(1, TJSONObject(InnerData).Get('recorderCount', 0));
        AssertEquals(1, TJSONObject(InnerData).Get('takeNumber', 0));
        AssertEquals(118, TJSONObject(InnerData).Get('studioCatalogCount', 0));
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    { 2. Record Take #2 via MCP }
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_record_take_livelink","arguments":{"action":"record_new_take"}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(2, TJSONObject(InnerData).Get('takeNumber', 0));
        AssertTrue(TJSONObject(InnerData).Get('keyReductionPct', 0.0) >= 85.0);
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    MdReport := TStudioHubManager.BuildExecutiveMarkdownReport(RootUi, OwnerComp);
    AssertTrue(Pos('`118` across `6` domains', MdReport) > 0);
  finally
    FreeAndNil(Mcp);
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolTakeRecorder);

end.
