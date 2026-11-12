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

{ Automated unit tests for Phase 316 Unified Editor Studio Hub, Categorized
  Quick-Launch Dock & Cross-Studio World Integration Auditor
  (@link(ToolStudioHub)). }
unit TestToolStudioHub;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolStudioHub = class(TCastleTestCase)
  published
    procedure TestFullStudioCatalogCategoriesMultiTokenSearchAndPhaseLookup;
    procedure TestCrossStudioWorldReadinessAuditWarningDetectionAndFullRemediation;
  end;

implementation

uses
  CastleVectors, CastleTransform, CastleViewport,
  CastleDesignAnnotations, CastleTimeOfDayWeather, CastleWaterSystem,
  CastleEnhancedInput, CastleVirtualCamera, CastleClothRope, CastleUtilityAi,
  ToolTimeOfDayStudio, ToolWaterStudio, ToolVirtualCamera, ToolUtilityAi,
  ToolStudioHub;

procedure TTestToolStudioHub.TestFullStudioCatalogCategoriesMultiTokenSearchAndPhaseLookup;
var
  Cat: TStudioHubCategory;
  Matches: TStudioCatalogEntryArray;
  Entry: TStudioCatalogEntry;
begin
  { Verify all 36 Horizon 2-5 studios are indexed across all 6 domain categories }
  AssertEquals(36, TStudioHubManager.StudioCount);

  for Cat in TStudioHubCategory do
  begin
    TStudioHubManager.FilterStudios(Ord(Cat), '', Matches);
    AssertTrue(Length(Matches) >= 4);
  end;

  { Multi-token case-insensitive search queries }
  TStudioHubManager.FilterStudios(-1, 'gerstner buoyancy', Matches);
  AssertEquals(1, Length(Matches));
  AssertEquals('water_studio', Matches[0].StudioId);

  TStudioHubManager.FilterStudios(-1, 'verlet cloth', Matches);
  AssertEquals(1, Length(Matches));
  AssertEquals('cloth_studio', Matches[0].StudioId);

  TStudioHubManager.FilterStudios(-1, 'gas cooldown', Matches);
  AssertEquals(1, Length(Matches));
  AssertEquals('ability_studio', Matches[0].StudioId);

  TStudioHubManager.FilterStudios(-1, 'phase 315', Matches);
  AssertEquals(1, Length(Matches));
  AssertEquals('save_replay', Matches[0].StudioId);

  AssertTrue(TStudioHubManager.FindStudioById('material_graph', Entry));
  AssertEquals(307, Entry.PhaseNumber);
end;

procedure TTestToolStudioHub.TestCrossStudioWorldReadinessAuditWarningDetectionAndFullRemediation;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  VCam: TCastleVirtualCamera;
  Cape: TCastleClothSurface;
  Crate: TCastleTransform;
  Buoy: TCastleBuoyancyBehavior;
  InputMgr: TCastleInputMapManager;
  DupBind: TInputBindingDef;
  BugPin: TCastleDesignAnnotation;
  Report: TStudioWorldHealthReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    { 1. VirtualCamera without a Brain }
    VCam := TCastleVirtualCamera.Create(DesignOwner);
    VCam.Name := 'OrphanVCam';
    Vp.Items.Add(VCam);

    { 2. Cloth with SyncWithWeather=True without TimeOfDayWeather }
    Cape := TCastleClothSurface.Create(DesignOwner);
    Cape.Name := 'WeatherCape';
    Cape.SyncWithWeather := True;
    Vp.Items.Add(Cape);

    { 3. BuoyancyBehavior without WaterVolume }
    Crate := TCastleTransform.Create(DesignOwner);
    Crate.Name := 'FloatingCrate';
    Vp.Items.Add(Crate);
    Buoy := TCastleBuoyancyBehavior.Create(DesignOwner);
    Buoy.Name := 'CrateBuoyancy';
    Crate.AddBehavior(Buoy);

    { 4. UtilityAI NPC without any SmartObject stations }
    TUtilityAiHelper.SpawnUtilityAgentInDesign(
      Vp, DesignOwner, uapVillagerArtisan, Vector3(0, 0, 0), 'LoneVillager');

    { 5. Enhanced Input duplicate binding conflict in GameplayDefault }
    InputMgr := TCastleInputMapManager.Create(DesignOwner);
    InputMgr.Name := 'InputMgrConflict';
    DupBind := TInputBindingDef.CreateDigital('GameplayDefault', 'DuplicateInteract', 'KeyE');
    InputMgr.AddBinding(DupBind);

    { 6. Open dacBug Review Pin }
    BugPin := TCastleDesignAnnotation.Create(DesignOwner);
    BugPin.Name := 'BlockerBugPin';
    BugPin.Category := dacBug;
    BugPin.Status := dasOpen;
    BugPin.Title := 'Missing collider on bridge';
    Vp.Items.Add(BugPin);

    { Audit broken world -> detects all 6 cross-studio integration issues! }
    Report := TStudioHubManager.AuditEntireDesign(Vp, DesignOwner);
    try
      AssertEquals(6, Length(Report.Issues));
      AssertTrue(Report.ReadinessScore <= 15);
    finally
      FreeAndNil(Report);
    end;

    { Remediate all 6 issues using the studio helpers }
    TVirtualCameraHelper.EnsureBrainOnViewportCamera(Vp, DesignOwner, 0.8);
    TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(Vp, DesignOwner);
    TWaterStudioHelper.SpawnWaterVolume(Vp, DesignOwner, wbpCalmLake, TVector3.Zero);
    TUtilityAiHelper.SpawnSmartObjectInDesign(
      Vp, DesignOwner, sopCampfireRestBench, Vector3(3, 0, 0), 'CampfireFix');
    InputMgr.RebindAtIndex(InputMgr.Bindings.Count - 1, 'KeyG');
    BugPin.Status := dasResolved;

    { Re-audit remediated world -> 0 issues and 100/100 A+ Ship-Ready! }
    Report := TStudioHubManager.AuditEntireDesign(Vp, DesignOwner);
    try
      AssertEquals(0, Length(Report.Issues));
      AssertEquals(100, Report.ReadinessScore);
      AssertEquals('A+ Ship-Ready', Report.ReadinessGrade);
      AssertTrue(Report.TotalModernSubsystems >= 10);
    finally
      FreeAndNil(Report);
    end;

    Md := TStudioHubManager.BuildExecutiveMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('100 / 100', Md) > 0);
    AssertTrue(Pos('0 issues detected', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolStudioHub);
end.
