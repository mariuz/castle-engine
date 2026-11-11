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

{ Automated tests for @link(TCastleDecalProjector) and
  @link(TDecalStudioHelper)
  (Phase 298 — UE 6.0 UDecalComponent & Mesh Decals Parity). }
unit TestToolDecalStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolDecalStudio = class(TCastleTestCase)
  published
    procedure TestSurfaceStampConformalProjectionGrazingCutoffAndJsonRoundtrip;
    procedure TestAllPresetsProceduralSamplesSortOrderAndEmptyProjectionAudit;
  end;

implementation

uses
  Math,
  CastleVectors, CastleColors, CastleComponentSerialize,
  CastleTransform, CastleScene, CastleUIControls, CastleViewport,
  CastleDecalProjector, ToolDecalStudio;

procedure TTestToolDecalStudio.TestSurfaceStampConformalProjectionGrazingCutoffAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  FloorBox, SteepCliff: TCastleBox;
  FloorDecal, CliffDecal, ReloadDecal: TCastleDecalProjector;
  NonTransientCount, I: Integer;
  JsonStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'ViewportMain';
    RootUi.InsertFront(Vp);

    { Horizontal floor at world Y = 0.0 }
    FloorBox := TCastleBox.Create(DesignOwner);
    FloorBox.Name := 'CourtyardFloor';
    FloorBox.Size := Vector3(30.0, 2.0, 30.0);
    FloorBox.Translation := Vector3(0.0, -1.0, 0.0);
    Vp.Items.Add(FloorBox);

    { Stamp scorch decal along downward ray onto floor at (-4, 0, 0) }
    FloorDecal := TDecalStudioHelper.StampDecalAlongRay(
      RootUi, DesignOwner, Vp.Items,
      Vector3(-4.0, 6.0, 0.0), Vector3(0.0, -1.0, 0.0), dpScorchMark);
    AssertTrue(FloorDecal <> nil);
    AssertSameValue(-4.0, FloorDecal.Translation.X, 0.03);
    AssertSameValue(0.0, FloorDecal.Translation.Y, 0.03);
    AssertEquals(64, FloorDecal.LastAcceptedCellCount);
    AssertEquals(128, FloorDecal.ProjectedTriangleCount);
    AssertEquals(0, FloorDecal.LastRejectedAngleCellCount);

    { Add a 70-degree steep cliff ramp isolated at X = +40 }
    SteepCliff := TCastleBox.Create(DesignOwner);
    SteepCliff.Name := 'SteepCliff';
    SteepCliff.Size := Vector3(20.0, 1.0, 20.0);
    SteepCliff.Translation := Vector3(40.0, 0.0, 0.0);
    SteepCliff.Rotation := Vector4(0.0, 0.0, 1.0, DegToRad(70.0));
    Vp.Items.Add(SteepCliff);

    CliffDecal := TDecalStudioHelper.CreateDecalInDesign(
      RootUi, DesignOwner, dpPuddleWet,
      Vector3(40.0, 0.5, 0.0), Vector3(0.0, 1.0, 0.0));
    AssertTrue(CliffDecal <> nil);
    CliffDecal.BoxExtents := Vector3(2.0, 8.0, 2.0);
    CliffDecal.GridResolution := 4;
    CliffDecal.SortOrder := 7;

    { Cutoff = 45 deg rejects the 70-degree cliff face }
    CliffDecal.NormalAngleCutoffDeg := 45.0;
    AssertEquals(0, CliffDecal.ProjectedTriangleCount);
    AssertTrue(CliffDecal.LastRejectedAngleCellCount > 0);

    { Relaxing cutoff to 80 deg accepts the 70-degree cliff face }
    CliffDecal.NormalAngleCutoffDeg := 80.0;
    AssertTrue(CliffDecal.ProjectedTriangleCount > 0);
    AssertEquals(0, CliffDecal.LastRejectedAngleCellCount);

    { JSON roundtrip preserves decal properties without baking csTransient mesh }
    JsonStr := ComponentToString(CliffDecal);
    ReloadDecal := StringToComponent(JsonStr, ReloadOwner) as TCastleDecalProjector;
    AssertEquals(7, ReloadDecal.SortOrder);
    AssertSameValue(80.0, ReloadDecal.NormalAngleCutoffDeg, 0.01);
    AssertSameValue(2.0, ReloadDecal.BoxExtents.X, 0.01);
    AssertSameValue(8.0, ReloadDecal.BoxExtents.Y, 0.01);

    NonTransientCount := 0;
    for I := 0 to ReloadDecal.Count - 1 do
      if not (csTransient in ReloadDecal[I].ComponentStyle) then
        Inc(NonTransientCount);
    AssertEquals(0, NonTransientCount);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolDecalStudio.TestAllPresetsProceduralSamplesSortOrderAndEmptyProjectionAudit;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  FloorBox: TCastleBox;
  D1, D2, D3, FloatingDecal: TCastleDecalProjector;
  CenterCol, CornerCol, StripeA, StripeB: TCastleColor;
  Sum: TDecalStudioSummary;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    Vp := TCastleViewport.Create(DesignOwner);
    RootUi.InsertFront(Vp);

    FloorBox := TCastleBox.Create(DesignOwner);
    FloorBox.Size := Vector3(30.0, 2.0, 30.0);
    FloorBox.Translation := Vector3(0.0, -1.0, 0.0);
    Vp.Items.Add(FloorBox);

    D1 := TDecalStudioHelper.CreateDecalInDesign(
      RootUi, DesignOwner, dpPuddleWet, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0));
    D1.SortOrder := 20;

    { Radial edge fade makes center opaque and outer corner transparent }
    CenterCol := D1.EvaluateProceduralSample(0.5, 0.5);
    CornerCol := D1.EvaluateProceduralSample(0.0, 0.0);
    AssertTrue(CenterCol.W > 0.75);
    AssertSameValue(0.0, CornerCol.W, 0.01);

    D2 := TDecalStudioHelper.CreateDecalInDesign(
      RootUi, DesignOwner, dpHazardStripe, Vector3(3.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0));
    D2.SortOrder := -5;
    StripeA := D2.EvaluateProceduralSample(0.05, 0.0);
    StripeB := D2.EvaluateProceduralSample(0.20, 0.0);
    AssertTrue(Abs(StripeA.X - StripeB.X) > 0.5);

    D3 := TDecalStudioHelper.CreateDecalInDesign(
      RootUi, DesignOwner, dpMagicRune, Vector3(-3.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0));
    D3.SortOrder := 10;
    AssertEquals(Ord(dbsAdditiveGlow), Ord(D3.BlendStyle));

    { Floating decal high in sky projects 0 triangles and triggers warning }
    FloatingDecal := TDecalStudioHelper.CreateDecalInDesign(
      RootUi, DesignOwner, dpMossGrowth, Vector3(0.0, 50.0, 0.0), Vector3(0.0, 1.0, 0.0));
    FloatingDecal.SortOrder := 30;
    AssertEquals(0, FloatingDecal.ProjectedTriangleCount);

    Sum := TDecalStudioHelper.ScanDecals(RootUi);
    AssertEquals(4, Sum.DecalCount);
    AssertEquals(1, Sum.EmptyProjectionCount);
    AssertTrue(Length(Sum.Warnings) >= 1);

    { Sorted ascending by SortOrder: -5, 10, 20, 30 }
    AssertEquals(-5, Sum.Decals[0].SortOrder);
    AssertEquals(10, Sum.Decals[1].SortOrder);
    AssertEquals(20, Sum.Decals[2].SortOrder);
    AssertEquals(30, Sum.Decals[3].SortOrder);

    Md := TDecalStudioHelper.FormatDecalStudioMarkdown(RootUi);
    AssertTrue(Pos('Castle Surface Decal & Weathering Studio Report', Md) > 0);
    AssertTrue(Pos(D2.Name, Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolDecalStudio);
end.
