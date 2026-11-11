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

{ Automated tests for @link(TCastleSplinePath),
  @link(TCastleSplineFollowerBehavior), and @link(TSplineStudioHelper)
  (Phase 297 — UE 6.0 USplineComponent & Landscape Splines Parity). }
unit TestToolSplineStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolSplineStudio = class(TCastleTestCase)
  published
    procedure TestCatmullRomArcLengthLutBankedRollAndTransientJsonRoundtrip;
    procedure TestTerrainProjectionInstanceScatterFollowerModesAndMarkdown;
  end;

implementation

uses
  Math,
  CastleVectors, CastleColors, CastleComponentSerialize,
  CastleTransform, CastleScene, CastleUIControls, CastleViewport,
  CastleSplinePath, ToolSplineStudio;

procedure TTestToolSplineStudio.TestCatmullRomArcLengthLutBankedRollAndTransientJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  Spline, ReloadSpline: TCastleSplinePath;
  Pt: TSplineControlPoint;
  MidSample, KnotSample: TSplineSample;
  NonTransientCount, I: Integer;
  JsonStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Spline := TCastleSplinePath.Create(DesignOwner);
    Spline.Name := 'HighwaySpline';
    Spline.ClearControlPoints;
    Spline.RibbonWidth := 4.0;
    Spline.SubdivisionsPerSegment := 24;

    { Uneven knot spacing: 10m then 20m along -Z -> total 30m }
    Spline.AddControlPoint(Vector3(0.0, 0.0, 0.0), 0.0, 1.0);
    Spline.AddControlPoint(Vector3(0.0, 0.0, -10.0), 30.0, 2.0);
    Spline.AddControlPoint(Vector3(0.0, 0.0, -30.0), 0.0, 1.0);

    AssertSameValue(30.0, Spline.TotalLength, 0.15);

    { Uniform arc-length query at 15.0m must land near Z = -15.0 despite knot #1 being at Z = -10 }
    MidSample := Spline.EvaluateLocalAtDistance(15.0);
    AssertSameValue(-15.0, MidSample.Position.Z, 0.35);
    AssertSameValue(-1.0, MidSample.Tangent.Z, 0.02);

    { At normalized t = 0.5 (knot #1), RollDeg = 30 deg and Width = 4.0 * 2.0 = 8.0 }
    KnotSample := Spline.EvaluateLocalAtNormalizedT(0.5);
    AssertSameValue(-10.0, KnotSample.Position.Z, 0.02);
    AssertSameValue(30.0, KnotSample.RollDeg, 0.05);
    AssertSameValue(8.0, KnotSample.Width, 0.05);
    AssertSameValue(Cos(DegToRad(30.0)), KnotSample.Up.Y, 0.02);
    AssertTrue(Abs(KnotSample.Up.X) > 0.45);

    { Ribbon vs Cable Tube transient mesh triangle generation }
    Spline.MeshMode := smRoadRibbon;
    AssertTrue(Spline.GeneratedTriangleCount > 0);
    Spline.MeshMode := smCableTube;
    Spline.TubeSides := 6;
    AssertTrue(Spline.GeneratedTriangleCount > 100);

    { JSON serialization roundtrip must NOT bake transient X3D mesh children }
    JsonStr := ComponentToString(Spline);
    AssertTrue(Pos('Transient', JsonStr) = 0);

    ReloadSpline := StringToComponent(JsonStr, ReloadOwner) as TCastleSplinePath;
    AssertEquals(3, ReloadSpline.ControlPointCount);
    AssertEquals(Ord(smCableTube), Ord(ReloadSpline.MeshMode));
    AssertSameValue(4.0, ReloadSpline.RibbonWidth, 0.01);
    Pt := ReloadSpline.GetControlPoint(1);
    AssertSameValue(30.0, Pt.RollDeg, 0.01);
    AssertSameValue(2.0, Pt.WidthScale, 0.01);

    NonTransientCount := 0;
    for I := 0 to ReloadSpline.Count - 1 do
      if not (csTransient in ReloadSpline[I].ComponentStyle) then
        Inc(NonTransientCount);
    AssertEquals(0, NonTransientCount);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolSplineStudio.TestTerrainProjectionInstanceScatterFollowerModesAndMarkdown;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  FloorBox, CartBox: TCastleBox;
  Spline: TCastleSplinePath;
  Follower: TCastleSplineFollowerBehavior;
  SnappedCount, Spawned1, Spawned2: Integer;
  Sum: TSplineStudioSummary;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'ViewportMain';
    RootUi.InsertFront(Vp);

    { Solid floor box whose top face sits at world Y = 0.0 }
    FloorBox := TCastleBox.Create(DesignOwner);
    FloorBox.Name := 'GroundFloor';
    FloorBox.Size := Vector3(60.0, 2.0, 80.0);
    FloorBox.Translation := Vector3(0.0, -1.0, -20.0);
    Vp.Items.Add(FloorBox);

    Spline := TSplineStudioHelper.CreateSplineInDesign(
      RootUi, DesignOwner, spCustom, Vector3(0.0, 12.0, 0.0));
    AssertTrue(Spline <> nil);
    Spline.ClearControlPoints;
    Spline.AddControlPoint(Vector3(0.0, 0.0, 0.0));
    Spline.AddControlPoint(Vector3(0.0, 3.0, -10.0));
    Spline.AddControlPoint(Vector3(0.0, -2.0, -20.0));

    { Project elevated knots down onto GroundFloor (world Y = 0.0 + 0.05 offset) }
    SnappedCount := Spline.ProjectControlPointsToWorld(40.0, 0.05);
    AssertEquals(3, SnappedCount);
    AssertSameValue(0.05, Spline.LocalToWorld(Spline.GetControlPoint(0).Position).Y, 0.03);
    AssertSameValue(0.05, Spline.LocalToWorld(Spline.GetControlPoint(1).Position).Y, 0.03);
    AssertSameValue(0.05, Spline.LocalToWorld(Spline.GetControlPoint(2).Position).Y, 0.03);

    { Populate evenly spaced marker posts along 20m spline at 5m spacing -> 5 posts (0, 5, 10, 15, 20) }
    Spawned1 := TSplineStudioHelper.PopulateInstancesAlongSpline(
      Spline, DesignOwner, '', 5.0, 2.0, true);
    AssertEquals(5, Spawned1);

    { Re-populating replaces previous generated posts cleanly without duplicating }
    Spawned2 := TSplineStudioHelper.PopulateInstancesAlongSpline(
      Spline, DesignOwner, '', 10.0, 2.0, true);
    AssertEquals(3, Spawned2);

    { Attach follower behavior onto CartBox and test PingPong bounce }
    CartBox := TCastleBox.Create(DesignOwner);
    CartBox.Name := 'MineCart';
    Vp.Items.Add(CartBox);

    Follower := TSplineStudioHelper.AttachFollowerToTransform(
      CartBox, DesignOwner, Spline.Name, 10.0);
    AssertTrue(Follower <> nil);
    Follower.LoopMode := sflmPingPong;
    AssertSameValue(0.0, CartBox.Translation.Z, 0.05);

    { Step 2.5s at 10 m/s along a 20m spline -> bounces back from 20m to 15m (Z = -15) }
    AssertTrue(Follower.StepFollow(2.5, RootUi));
    AssertSameValue(15.0, Follower.CurrentDistance, 0.25);
    AssertSameValue(-15.0, CartBox.Translation.Z, 0.35);

    { Summary & Markdown report }
    Sum := TSplineStudioHelper.ScanSplines(RootUi);
    AssertEquals(1, Sum.SplineCount);
    AssertEquals(1, Sum.FollowerCount);
    AssertEquals(3, Sum.GeneratedInstanceCount);

    Md := TSplineStudioHelper.FormatSplineStudioMarkdown(RootUi);
    AssertTrue(Pos(Spline.Name, Md) > 0);
    AssertTrue(Pos('Castle Spline Path & Extrusion Studio Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSplineStudio);
end.
