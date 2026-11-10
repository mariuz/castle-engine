{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for @link(TCastleStreamingZone),
  @link(TWorldStreamingInspector), and @link(TBehaviorCompositionHelper)
  (Phase 286 — UE 6.0 Composable Entities & Streaming Parity). }
unit TestToolWorldStreaming;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolWorldStreaming = class(TCastleTestCase)
  published
    procedure TestStreamingZoneHysteresisTransientSerializationAndWorldScan;
    procedure TestBehaviorCompositionAttachSummarizeResolveAndDetach;
  end;

implementation

uses
  CastleVectors, CastleFilesUtils, CastleUriUtils, CastleComponentSerialize,
  CastleTransform, CastleViewport, CastleScene, CastleBehaviors,
  CastleNprShader, CastleStreamingZone, ToolWorldStreaming;

procedure TTestToolWorldStreaming.TestStreamingZoneHysteresisTransientSerializationAndWorldScan;
var
  TempDir, SectorFile, SectorUrl, WorldJson: String;
  SectorOwner, WorldOwner, LoadedOwner: TComponent;
  SectorRoot: TCastleTransform;
  NorthKeep: TCastleBox;
  NorthTorch: TCastlePointLight;
  Vp: TCastleViewport;
  ZoneNorth, ZoneSouth, RestoredNorth: TCastleStreamingZone;
  Report: TWorldStreamingReport;
  LoadedCount: Integer;
begin
  TempDir := IncludeTrailingPathDelimiter(GetTempDir(false)) +
    'cge_stream_zone_test_' + IntToStr(Random(1000000));
  ForceDirectories(TempDir);
  SectorFile := IncludeTrailingPathDelimiter(TempDir) + 'sector_north.castle-transform';
  SectorUrl := FilenameToUriSafe(SectorFile);
  try
    { 1. Author a reusable open-world sector sub-design }
    SectorOwner := TComponent.Create(nil);
    try
      SectorRoot := TCastleTransform.Create(SectorOwner);
      SectorRoot.Name := 'NorthSectorRoot';

      NorthKeep := TCastleBox.Create(SectorOwner);
      NorthKeep.Name := 'NorthKeepMesh';
      NorthKeep.Size := Vector3(12, 18, 12);
      SectorRoot.Add(NorthKeep);

      NorthTorch := TCastlePointLight.Create(SectorOwner);
      NorthTorch.Name := 'NorthGateTorch';
      NorthTorch.Intensity := 2.5;
      SectorRoot.Add(NorthTorch);

      TransformSave(SectorRoot, SectorUrl);
    finally
      FreeAndNil(SectorOwner);
    end;

    { 2. Create a world viewport with two TCastleStreamingZone sectors }
    WorldOwner := TComponent.Create(nil);
    try
      Vp := TCastleViewport.Create(WorldOwner);
      Vp.Name := 'OpenWorldViewport';

      ZoneNorth := TWorldStreamingInspector.CreateStreamingZoneAtPosition(
        Vp.Items, WorldOwner, Vector3(0, 0, -100), SectorUrl, 50.0, 75.0);
      ZoneNorth.Name := 'ZoneNorth';
      ZoneNorth.ZoneLabel := 'Northern Keep';

      ZoneSouth := TWorldStreamingInspector.CreateStreamingZoneAtPosition(
        Vp.Items, WorldOwner, Vector3(0, 0, 100), SectorUrl, 40.0, 60.0);
      ZoneSouth.Name := 'ZoneSouth';
      ZoneSouth.ZoneLabel := 'Southern Outpost';

      AssertFalse(ZoneNorth.IsZoneLoaded);
      AssertFalse(ZoneSouth.IsZoneLoaded);

      { Observer at origin (0,0,0): Dist to North = 100 > 50 -> stays unloaded }
      LoadedCount := TWorldStreamingInspector.SimulateObserverAcrossWorld(
        Vp, Vector3(0, 0, 0));
      AssertEquals(0, LoadedCount);
      AssertFalse(ZoneNorth.IsZoneLoaded);

      { Observer approaches North (0,0,-60): Dist = 40 <= 50 -> streams in! }
      LoadedCount := TWorldStreamingInspector.SimulateObserverAcrossWorld(
        Vp, Vector3(0, 0, -60));
      AssertEquals(1, LoadedCount);
      AssertTrue(ZoneNorth.IsZoneLoaded);
      AssertFalse(ZoneSouth.IsZoneLoaded);
      AssertEquals(1, ZoneNorth.LoadCount);
      AssertTrue(ZoneNorth.LoadedDesignRoot <> nil);
      AssertEquals('NorthSectorRoot', ZoneNorth.LoadedDesignRoot.Name);
      AssertTrue(Pos('LOADED', ZoneNorth.ZoneSummaryBadge) > 0);

      { Observer retreats into hysteresis band (0,0,-35): Dist = 65 (50 < 65 <= 75)
        -> must remain loaded without thrashing! }
      LoadedCount := TWorldStreamingInspector.SimulateObserverAcrossWorld(
        Vp, Vector3(0, 0, -35));
      AssertEquals(1, LoadedCount);
      AssertTrue(ZoneNorth.IsZoneLoaded);
      AssertEquals(1, ZoneNorth.LoadCount);
      AssertEquals(0, ZoneNorth.UnloadCount);

      { Observer moves past UnloadRadius (0,0,-15): Dist = 85 > 75 -> unloads! }
      LoadedCount := TWorldStreamingInspector.SimulateObserverAcrossWorld(
        Vp, Vector3(0, 0, -15));
      AssertEquals(0, LoadedCount);
      AssertFalse(ZoneNorth.IsZoneLoaded);
      AssertTrue(ZoneNorth.LoadedDesignRoot = nil);
      AssertEquals(1, ZoneNorth.UnloadCount);

      { Verify ScanWorld & Markdown report }
      Report := TWorldStreamingInspector.ScanWorld(Vp, Vector3(0, 0, -60), true);
      try
        AssertEquals(2, Report.TotalZones);
        AssertEquals(0, Report.LoadedZones);
        AssertEquals(2, Report.UnloadedZones);
        AssertTrue(Report.Zones[0].WouldChangeAtObserver);
        AssertTrue(Pos('Northern Keep', Report.FormatMarkdownSummary) > 0);
      finally
        FreeAndNil(Report);
      end;

      { 3. Enable PreviewLoadedInEditor on ZoneNorth and roundtrip via JSON:
        streamed children (NorthKeepMesh) MUST NOT be baked into WorldJson! }
      ZoneNorth.PreviewLoadedInEditor := true;
      AssertTrue(ZoneNorth.IsZoneLoaded);

      WorldJson := ComponentToString(Vp);
      AssertTrue(Pos('NorthKeepMesh', WorldJson) = 0);
      AssertTrue(Pos('ZoneNorth', WorldJson) > 0);

      LoadedOwner := TComponent.Create(nil);
      try
        StringToComponent(WorldJson, LoadedOwner);
        RestoredNorth := LoadedOwner.FindRequiredComponent('ZoneNorth') as TCastleStreamingZone;
        AssertSameValue(50.0, RestoredNorth.LoadRadius, 0.001);
        AssertSameValue(75.0, RestoredNorth.UnloadRadius, 0.001);
        AssertTrue(RestoredNorth.PreviewLoadedInEditor);
        AssertTrue(RestoredNorth.IsZoneLoaded);
        AssertTrue(RestoredNorth.LoadedDesignRoot <> nil);
        AssertEquals('NorthSectorRoot', RestoredNorth.LoadedDesignRoot.Name);
      finally
        FreeAndNil(LoadedOwner);
      end;
    finally
      FreeAndNil(WorldOwner);
    end;
  finally
    if FileExists(SectorFile) then
      DeleteFile(SectorFile);
    RemoveDir(TempDir);
  end;
end;

procedure TTestToolWorldStreaming.TestBehaviorCompositionAttachSummarizeResolveAndDetach;
var
  OwnerComp: TComponent;
  Hero: TCastleScene;
  RegList: TRegisteredBehaviorEntryArray;
  FoundBillboard, FoundStylized: Boolean;
  B1, B2, InspectingB: TCastleBehavior;
  Cards: TBehaviorCardSummaryArray;
  ResolvedT: TCastleTransform;
  I: Integer;
begin
  RegList := TBehaviorCompositionHelper.ListRegisteredBehaviorClasses;
  FoundBillboard := false;
  FoundStylized := false;
  for I := 0 to High(RegList) do
  begin
    if RegList[I].BehaviorClass = TCastleBillboard then
      FoundBillboard := true;
    if RegList[I].BehaviorClass = TCastleStylizedShaderBehavior then
      FoundStylized := true;
  end;
  AssertTrue(FoundBillboard);
  AssertTrue(FoundStylized);

  OwnerComp := TComponent.Create(nil);
  try
    Hero := TCastleScene.Create(OwnerComp);
    Hero.Name := 'HeroEntity';

    B1 := TBehaviorCompositionHelper.AttachNewBehavior(
      Hero, OwnerComp, TCastleBillboard);
    AssertTrue(B1 is TCastleBillboard);
    AssertEquals(1, Hero.BehaviorsCount);

    B2 := TBehaviorCompositionHelper.AttachNewBehavior(
      Hero, OwnerComp, TCastleStylizedShaderBehavior);
    AssertTrue(B2 is TCastleStylizedShaderBehavior);
    TCastleStylizedShaderBehavior(B2).Preset := sspGoochTechnical;
    AssertEquals(2, Hero.BehaviorsCount);

    Cards := TBehaviorCompositionHelper.DescribeAttachedBehaviors(Hero);
    AssertEquals(2, Length(Cards));
    AssertEquals('TCastleBillboard', Cards[0].BehaviorClassName);
    AssertEquals('TCastleStylizedShaderBehavior', Cards[1].BehaviorClassName);
    AssertTrue(Pos('sspGoochTechnical', Cards[1].PropertyPreview) > 0);

    { ResolveSelectedTransformForBehaviors works for both Hero and child Behavior }
    ResolvedT := TBehaviorCompositionHelper.ResolveSelectedTransformForBehaviors(
      Hero, InspectingB);
    AssertTrue(ResolvedT = Hero);
    AssertTrue(InspectingB = nil);

    ResolvedT := TBehaviorCompositionHelper.ResolveSelectedTransformForBehaviors(
      B2, InspectingB);
    AssertTrue(ResolvedT = Hero);
    AssertTrue(InspectingB = B2);

    { Detach B1 cleanly }
    AssertTrue(TBehaviorCompositionHelper.DetachAndFreeBehavior(Hero, B1));
    AssertEquals(1, Hero.BehaviorsCount);
    AssertTrue(Hero.Behaviors[0] = B2);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolWorldStreaming);
end.
