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

{ Automated unit tests for Phase 283 Spatial Viewport Annotations ("Canvas Pins")
  and Design Review Bookmarks (CastleDesignAnnotations & ToolDesignAnnotations). }
unit TestToolDesignAnnotations;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolDesignAnnotations = class(TCastleTestCase)
  published
    procedure TestPinRuntimeZeroFootprintCameraBookmarksAndJsonRoundtrip;
    procedure TestScanFilterAuditChecklistAndBatchLifecycle;
  end;

implementation

uses
  CastleUtils, CastleVectors, CastleBoxes, CastleTransform, CastleUIControls,
  CastleViewport, CastleComponentSerialize,
  CastleDesignAnnotations, ToolDesignAnnotations;

procedure TTestToolDesignAnnotations.TestPinRuntimeZeroFootprintCameraBookmarksAndJsonRoundtrip;
var
  OwnerComp, LoadedOwner: TComponent;
  Vp: TCastleViewport;
  Pin3D, LoadedPin3D: TCastleDesignAnnotation;
  LoadedRoot: TComponent;
  JsonStr: String;
  OldMode: TCastleApplicationMode;
  CamP, CamD, CamU: TVector3;
begin
  OwnerComp := TComponent.Create(nil);
  LoadedOwner := TComponent.Create(nil);
  OldMode := InternalCastleApplicationMode;
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'ViewportReview';
    Vp.Camera.SetWorldView(Vector3(12, 8, 20), Vector3(0, -0.3, -1).Normalize, Vector3(0, 1, 0));

    Pin3D := TCastleDesignAnnotation.Create(OwnerComp);
    Pin3D.Name := 'PinBridgeCrack';
    Pin3D.Category := dacBug;
    Pin3D.Status := dasOpen;
    Pin3D.Title := 'Seam gap on bridge arch';
    Pin3D.Author := 'mariuz';
    Pin3D.Comment := 'Snap modular arch piece flush along X.';
    Pin3D.Priority := 99; // clamped to 5
    AssertEquals(5, Pin3D.Priority);
    AssertTrue(Pin3D.IsUnresolvedActionable);
    Vp.Items.Add(Pin3D);

    { Game runtime (appRunning): zero bounding-box footprint }
    InternalCastleApplicationMode := appRunning;
    AssertTrue(Pin3D.LocalBoundingBox.IsEmpty);

    { Editor design mode (appDesign): pickable 0.35 half-extent box }
    InternalCastleApplicationMode := appDesign;
    AssertTrue(not Pin3D.LocalBoundingBox.IsEmpty);
    AssertSameValue(0.70, Pin3D.LocalBoundingBox.SizeX, 1e-4);

    { Capture & restore camera viewpoint bookmark }
    AssertTrue(Pin3D.CaptureCameraFrom(Vp.Camera));
    AssertTrue(Pin3D.HasCameraBookmark);
    AssertTrue(Pos('[Cam]', Pin3D.PinSummaryBadge) > 0);
    AssertTrue(Pos('[BUG]', Pin3D.PinSummaryBadge) > 0);

    { Move camera elsewhere, then jump back via bookmark }
    Vp.Camera.SetWorldView(Vector3(-50, 1, -50), Vector3(1, 0, 0), Vector3(0, 1, 0));
    AssertTrue(Pin3D.ApplyCameraTo(Vp.Camera));
    Vp.Camera.GetWorldView(CamP, CamD, CamU);
    AssertVectorEquals(Vector3(12, 8, 20), CamP, 1e-4);
    AssertVectorEquals(Vector3(0, -0.3, -1).Normalize, CamD, 1e-4);

    { JSON serialization roundtrip }
    JsonStr := ComponentToString(Pin3D);
    LoadedRoot := StringToComponent(JsonStr, LoadedOwner);
    AssertTrue(LoadedRoot is TCastleDesignAnnotation);
    LoadedPin3D := TCastleDesignAnnotation(LoadedRoot);
    AssertTrue(LoadedPin3D.Category = dacBug);
    AssertTrue(LoadedPin3D.Status = dasOpen);
    AssertEquals('Seam gap on bridge arch', LoadedPin3D.Title);
    AssertEquals('mariuz', LoadedPin3D.Author);
    AssertEquals(5, LoadedPin3D.Priority);
    AssertTrue(LoadedPin3D.HasCameraBookmark);
    AssertVectorEquals(Vector3(12, 8, 20), LoadedPin3D.CameraPosition, 1e-4);
  finally
    InternalCastleApplicationMode := OldMode;
    FreeAndNil(LoadedOwner);
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolDesignAnnotations.TestScanFilterAuditChecklistAndBatchLifecycle;
var
  OwnerComp: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  PinBug3D, PinTodo3D, PinAi3D: TCastleDesignAnnotation;
  PinNote2D, PinBug2D: TCastleDesignAnnotationUi;
  Report: TDesignAnnotationAuditReport;
  ChecklistMd: String;
  MatchCount, I: Integer;
begin
  OwnerComp := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    RootUi.Name := 'RootView';

    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    Vp.Camera.SetWorldView(Vector3(0, 4, 10), Vector3(0, 0, -1), Vector3(0, 1, 0));
    RootUi.InsertFront(Vp);

    PinBug3D := TDesignAnnotationManager.Create3DPinInViewport(
      Vp, OwnerComp, dacBug, 'Collider missing on pillar', true, 6.0);
    PinBug3D.Priority := 5;
    PinBug3D.Author := 'qa_lead';

    PinTodo3D := TDesignAnnotationManager.Create3DPinInViewport(
      Vp, OwnerComp, dacTodo, 'Add torch sconces', false, 4.0);
    PinTodo3D.Status := dasInProgress;
    PinTodo3D.Priority := 3;

    PinAi3D := TDesignAnnotationManager.Create3DPinInViewport(
      Vp, OwnerComp, dacAiPrompt, 'Scatter 12 mossy rocks around well', true, 8.0);
    PinAi3D.Priority := 4;

    PinNote2D := TDesignAnnotationManager.Create2DPinInUi(
      RootUi, OwnerComp, dacNote, 'Minimap safe-zone margin');
    PinNote2D.Status := dasResolved;

    PinBug2D := TDesignAnnotationManager.Create2DPinInUi(
      RootUi, OwnerComp, dacBug, 'Health bar overlaps boss subtitle');
    PinBug2D.Priority := 4;

    { Verify placement ahead of camera at Z = 10 - 6 = 4 }
    AssertVectorEquals(Vector3(0, 4, 4), PinBug3D.Translation, 1e-4);
    AssertTrue(PinBug3D.HasCameraBookmark);

    Report := TDesignAnnotationManager.ScanDesign(RootUi);
    try
      AssertEquals(5, Report.TotalPins);
      AssertEquals(3, Report.Pins3DCount);
      AssertEquals(2, Report.Pins2DCount);
      AssertEquals(3, Report.OpenCount);
      AssertEquals(1, Report.InProgressCount);
      AssertEquals(1, Report.ResolvedCount);
      AssertEquals(2, Report.UnresolvedBugCount);
      AssertEquals(1, Report.UnresolvedTodoCount);
      AssertEquals(1, Report.AiPromptCount);
      AssertEquals(2, Report.Bookmarked3DPins);
      AssertEquals(3, Report.AuditWarnings.Count);

      { Highest-priority unresolved bug sorts first }
      AssertEquals(PinBug3D.Name, Report.Items[0].ComponentName);
      { Resolved pin sorts last }
      AssertEquals(PinNote2D.Name, Report.Items[High(Report.Items)].ComponentName);

      { Filter: Unresolved (-2) + Bug category + text query }
      MatchCount := 0;
      for I := 0 to High(Report.Items) do
        if TDesignAnnotationManager.MatchesFilter(Report.Items[I], Ord(dacBug), -2, 'subtitle') then
          Inc(MatchCount);
      AssertEquals(1, MatchCount);

      ChecklistMd := Report.FormatMarkdownChecklist('DungeonCourtyard');
      AssertTrue(Pos('DungeonCourtyard', ChecklistMd) > 0);
      AssertTrue(Pos('Collider missing on pillar', ChecklistMd) > 0);
      AssertTrue(Pos('- [x]', ChecklistMd) > 0);
    finally
      FreeAndNil(Report);
    end;

    { Batch resolve all Bug pins (2 bugs -> resolved), then delete all resolved pins (1 note + 2 bugs = 3 deleted) }
    AssertEquals(2, TDesignAnnotationManager.MarkAllResolved(RootUi, Ord(dacBug)));
    AssertEquals(3, TDesignAnnotationManager.DeleteResolvedPins(RootUi));

    Report := TDesignAnnotationManager.ScanDesign(RootUi);
    try
      AssertEquals(2, Report.TotalPins);
      AssertEquals(0, Report.UnresolvedBugCount);
      AssertEquals(1, Report.UnresolvedTodoCount);
      AssertEquals(1, Report.AiPromptCount);
    finally
      FreeAndNil(Report);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolDesignAnnotations);
end.
