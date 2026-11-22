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

{ Automated tests for Phase 356 Live Coding RTTI Broker, Package Cook Auditor,
  76-Studio Hub & 17-Tool MCP Upgrade. }
unit TestToolLiveCookAuditor;

{$I castleconf.inc}

interface

uses Classes, SysUtils, CastleTester;

type
  TTestToolLiveCookAuditor = class(TCastleTestCase)
  published
    procedure TestLiveCodingRttiSnapshotHotReloadRestoreAndFieldAliasRedirect;
    procedure TestPackageCookAuditorBrokenUrlChooserHazard76StudioHubAnd17thMcpTool;
  end;

implementation

uses fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleUIControls, CastleControls,
  CastleStreamingZone, CastleChooserTable, CastleMassTraffic,
  ToolLiveCookAuditor, ToolStudioHub, ToolMcpServer;

procedure TTestToolLiveCookAuditor.TestLiveCodingRttiSnapshotHotReloadRestoreAndFieldAliasRedirect;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  HeroBox: TCastleBox;
  BannerLabel: TCastleLabel;
  Traffic: TCastleMassTrafficManager;
  Snap, ReloadedSnap: TLiveRttiSnapshot;
  SnapJson: String;
  Stats: TLiveRehydrateStats;
begin
  DesignOwner := TComponent.Create(nil);
  Snap := nil;
  ReloadedSnap := TLiveRttiSnapshot.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    HeroBox := TCastleBox.Create(DesignOwner);
    HeroBox.Name := 'HeroBox';
    HeroBox.Translation := Vector3(4.5, 2.0, -6.25);
    Vp.Items.Add(HeroBox);

    BannerLabel := TCastleLabel.Create(DesignOwner);
    BannerLabel.Name := 'BannerLabel';
    BannerLabel.Caption := 'Horizon 9 Live Coding Ready';
    Vp.InsertFront(BannerLabel);

    Traffic := TCastleMassTrafficManager.Create(DesignOwner);
    Traffic.Name := 'CityTraffic';
    Traffic.DesiredSpeedMps := 18.5;
    Vp.Items.Add(Traffic);

    { 1. Capture live RTTI state before hot-reload }
    Snap := TLiveCodingCookBroker.CaptureLiveRttiSnapshot(Vp, DesignOwner);
    AssertTrue(Snap.CapturedComponentCount >= 4);
    AssertTrue(Snap.CapturedPropertyCount >= 20);

    { Inject a renamed legacy field ('LegacyCruiseSpeed' -> 'DesiredSpeedMps') }
    Snap.SetLegacyPropertyForComponent('CityTraffic', 'LegacyCruiseSpeed',
      TJSONFloatNumber.Create(22.0));

    SnapJson := Snap.ExportSnapshotJson;
    AssertTrue(ReloadedSnap.ImportSnapshotJson(SnapJson));

    { 2. Simulate C++/Pascal hot-reload resetting live instances to defaults }
    HeroBox.Translation := Vector3(99.0, -50.0, 42.0);
    BannerLabel.Caption := 'WIPED_ON_RELOAD';
    Traffic.DesiredSpeedMps := 5.0;

    { 3. Rehydrate snapshot with CoreRedirect field alias rule }
    Stats := TLiveCodingCookBroker.RehydrateLiveRttiSnapshot(ReloadedSnap, Vp, DesignOwner, [
      TRttiFieldAliasRule.Make('LegacyCruiseSpeed', 'DesiredSpeedMps')
    ]);

    AssertTrue(Stats.ComponentsMatched >= 3);
    AssertTrue(Stats.PropertiesRestored >= 10);
    AssertEquals('CoreRedirect field alias must redirect LegacyCruiseSpeed -> DesiredSpeedMps',
      1, Stats.AliasesApplied);
    AssertVectorEquals(Vector3(4.5, 2.0, -6.25), HeroBox.Translation, 0.01);
    AssertEquals('Horizon 9 Live Coding Ready', BannerLabel.Caption);
    AssertSameValue(22.0, Traffic.DesiredSpeedMps, 0.01);
  finally
    FreeAndNil(ReloadedSnap);
    FreeAndNil(Snap);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolLiveCookAuditor.TestPackageCookAuditorBrokenUrlChooserHazard76StudioHubAnd17thMcpTool;
const
  Horizon9Ids: array [0..9] of String = (
    'chooser_table', 'groom_studio', 'traversal_studio', 'rvt_studio', 'mover_studio',
    'camera_rail', 'meshlet_studio', 'tet_softbody', 'mass_traffic', 'live_cook_auditor'
  );
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  BadZone: TCastleStreamingZone;
  EmptyChooser: TCastleChooserTable;
  Entry: TStudioCatalogEntry;
  DirtyCook, CleanCook: TCookAuditReport;
  Server: TCastleMcpServer;
  RespStr, InnerText, MdReport: String;
  OuterJson, InnerJson: TJSONData;
  I: Integer;
begin
  { 1. Verify unified 96-Studio Hub across Horizons 2-11 }
  AssertEquals(105, TStudioHubManager.StudioCount);
  for I := 0 to High(Horizon9Ids) do
    AssertTrue('Missing Horizon 9 studio in Hub: ' + Horizon9Ids[I],
      TStudioHubManager.FindStudioById(Horizon9Ids[I], Entry));

  DesignOwner := TComponent.Create(nil);
  Server := TCastleMcpServer.Create(nil);
  DirtyCook := nil;
  CleanCook := nil;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    { 2. Introduce two release cook blockers: lazy-streamed traversal-unsafe DesignUrl + empty ChooserTable }
    BadZone := TCastleStreamingZone.Create(DesignOwner);
    BadZone.Name := 'BrokenNorthSector';
    BadZone.DesignUrl := 'castle-data:/../unpacked_outside_tree/sector_north.castle-transform';
    Vp.Items.Add(BadZone);

    EmptyChooser := TCastleChooserTable.Create(DesignOwner);
    EmptyChooser.Name := 'EmptyChooser';
    EmptyChooser.ClearRows;
    Vp.AddNonVisualComponent(EmptyChooser);

    DirtyCook := TLiveCodingCookBroker.AuditPackageCookReadiness(Vp, DesignOwner, False);
    AssertFalse('Cook auditor must block shipping when broken URL & empty Chooser exist',
      DirtyCook.CookReadyToShip);
    AssertEquals(1, DirtyCook.BrokenAssetUrlCount);
    AssertEquals(1, DirtyCook.ChooserIssueCount);
    AssertTrue(DirtyCook.CookReadinessScore <= 55);

    { 3. Remediate both hazards -> 100/100 Ship-Ready }
    BadZone.DesignUrl := '';
    EmptyChooser.Preset := chpMeleeComboMontage;

    CleanCook := TLiveCodingCookBroker.AuditPackageCookReadiness(Vp, DesignOwner, False);
    AssertTrue(CleanCook.CookReadyToShip);
    AssertEquals(100, CleanCook.CookReadinessScore);
    AssertEquals(0, CleanCook.BrokenAssetUrlCount);
    AssertEquals(0, CleanCook.ChooserIssueCount);

    MdReport := TLiveCodingCookBroker.GenerateCookAndLiveCodingMarkdown(Vp, DesignOwner);
    AssertTrue(Pos('105` Studios', MdReport) > 0);

    { 4. Verify 17th MCP Tool: cge_audit_package_cook }
    Server.AutonomyMode := mamReadOnly;
    Server.StandaloneDesignRoot := Vp;
    Server.StandaloneDesignOwner := DesignOwner;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":56,"method":"tools/call","params":{"name":"cge_audit_package_cook","arguments":{"checkDiskUrls":false}}}');
    OuterJson := GetJSON(RespStr);
    try
      InnerText := TJSONObject(OuterJson).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerJson := GetJSON(InnerText);
      try
        AssertTrue(TJSONObject(InnerJson).Booleans['cookReadyToShip']);
        AssertEquals(100, TJSONObject(InnerJson).Integers['cookReadinessScore']);
        AssertEquals(105, TJSONObject(InnerJson).Integers['studioCatalogCount']);
        AssertEquals(0, TJSONObject(InnerJson).Integers['brokenAssetUrlCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(CleanCook);
    FreeAndNil(DirtyCook);
    FreeAndNil(Server);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolLiveCookAuditor);
end.
