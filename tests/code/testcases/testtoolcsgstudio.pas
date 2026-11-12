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

{ Automated unit tests for Phase 309: CSG / Boolean Greybox Architecture &
  Procedural Room/Arch/Stair Mesh Modeler Studio (@link(CastleCsgModeler),
  @link(ToolCsgStudio)). }
unit TestToolCsgStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolCsgStudio = class(TCastleTestCase)
  published
    procedure TestExactBspBooleanVolumeTriplanarUvAndJsonRoundtrip;
    procedure TestHollowRoomArchDoorwayRaycastWalkthroughStairwellAndAudit;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleComponentSerialize,
  CastleTransform, CastleScene, CastleUIControls, CastleViewport,
  CastleCsgModeler, ToolCsgStudio;

procedure TTestToolCsgStudio.TestExactBspBooleanVolumeTriplanarUvAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  Vp: TCastleViewport;
  Modeler, Reloaded: TCastleCsgModeler;
  ReloadedRoot: TComponent;
  JsonStr: String;
  UvTop, UvSideX, UvSideZ: TVector2;
  NonTransientCount, I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    Modeler := TCsgStudioHelper.SpawnCsgModeler(
      Vp, DesignOwner, capCustom, Vector3(0.0, 0.0, 0.0));
    AssertTrue(Modeler <> nil);
    Modeler.ClearBrushes;
    AssertEquals(0, Modeler.OutputTriangleCount);

    { 1. Union 4x4x4m solid block -> exact polyhedral volume 64.0 m^3 }
    TCsgStudioHelper.AddArchitecturalBrush(
      Modeler, 'OuterCube', cboUnion, cbsBox,
      Vector3(0.0, 2.0, 0.0), Vector3(4.0, 4.0, 4.0));
    AssertEquals(12, Modeler.OutputTriangleCount);
    AssertSameValue(64.0, Modeler.OutputVolumeCubicMeters, 0.05);

    { 2. Subtract 2x6x2m vertical through-shaft -> carves 2x4x2 = 16 m^3 -> 48.0 m^3 }
    TCsgStudioHelper.AddArchitecturalBrush(
      Modeler, 'VerticalShaft', cboSubtract, cbsBox,
      Vector3(0.0, 2.0, 0.0), Vector3(2.0, 6.0, 2.0));
    AssertTrue(Modeler.OutputTriangleCount > 12);
    AssertSameValue(48.0, Modeler.OutputVolumeCubicMeters, 0.05);

    { 3. Intersect with 6x2x6m horizontal slab (Y in [1..3]) -> halves height -> 24.0 m^3 }
    TCsgStudioHelper.AddArchitecturalBrush(
      Modeler, 'SlabClip', cboIntersect, cbsBox,
      Vector3(0.0, 2.0, 0.0), Vector3(6.0, 2.0, 6.0));
    AssertSameValue(24.0, Modeler.OutputVolumeCubicMeters, 0.05);

    { 4. Triplanar real-meter UV scaling (0.5 /m -> 4m maps to 2.0 UV units) }
    Modeler.UvTilingScale := 0.5;
    UvTop := Modeler.ComputeTriplanarUv(Vector3(4.0, 3.0, -6.0), Vector3(0.0, 1.0, 0.0));
    AssertSameValue(2.0, UvTop.X, 1e-4);
    AssertSameValue(-3.0, UvTop.Y, 1e-4);

    UvSideX := Modeler.ComputeTriplanarUv(Vector3(2.0, 3.0, 4.0), Vector3(1.0, 0.0, 0.0));
    AssertSameValue(2.0, UvSideX.X, 1e-4);
    AssertSameValue(1.5, UvSideX.Y, 1e-4);

    UvSideZ := Modeler.ComputeTriplanarUv(Vector3(-4.0, 2.0, 2.0), Vector3(0.0, 0.0, 1.0));
    AssertSameValue(-2.0, UvSideZ.X, 1e-4);
    AssertSameValue(1.0, UvSideZ.Y, 1e-4);

    { 5. JSON roundtrip: BrushesJson persists cleanly without csTransient scene bloat }
    JsonStr := ComponentToString(Vp);
    AssertTrue(Pos('TransientCsgMesh', JsonStr) = 0);

    ReloadedRoot := StringToComponent(JsonStr, ReloadOwner);
    AssertTrue(ReloadedRoot is TCastleViewport);
    Reloaded := ReloadOwner.FindComponent(Modeler.Name) as TCastleCsgModeler;
    AssertTrue(Reloaded <> nil);
    AssertEquals(3, Reloaded.Brushes.Count);
    AssertSameValue(24.0, Reloaded.OutputVolumeCubicMeters, 0.05);

    NonTransientCount := 0;
    for I := 0 to Reloaded.Count - 1 do
      if not (csTransient in Reloaded[I].ComponentStyle) then
        Inc(NonTransientCount);
    AssertEquals(0, NonTransientCount);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolCsgStudio.TestHollowRoomArchDoorwayRaycastWalkthroughStairwellAndAudit;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  HollowRoom, Mezzanine, CrossHall, Cloister: TCastleCsgModeler;
  HitDoorway, HitSolidWall: TRayCollision;
  Report: TCsgStudioAuditReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    { 1. Hollow 10x4x10 room (Z in [-5..+5]), inner 8.8x3.2x8.8 (Z in [-4.4..+4.4]),
         and Roman arched front doorway carved through +Z wall at X=0 }
    HollowRoom := TCsgStudioHelper.SpawnCsgModeler(
      Vp, DesignOwner, capHollowRoomWithArchDoorway, Vector3(0.0, 0.0, 0.0));
    AssertTrue(HollowRoom <> nil);
    AssertTrue(HollowRoom.GenerateCollider);
    AssertTrue(HollowRoom.OutputTriangleCount > 30);
    { Solid masonry volume < 400 m^3 (outer) and > 120 m^3 }
    AssertTrue(HollowRoom.OutputVolumeCubicMeters > 120.0);
    AssertTrue(HollowRoom.OutputVolumeCubicMeters < 160.0);

    { Raycast straight through open arched doorway at X = 0, Y = 1.5 from Z = +8 along -Z:
      Must NOT stop at carved front wall Z = +5.0 (Dist 3.0), must hit interior back wall Z = -4.4 (Dist 12.4)! }
    HitDoorway := Vp.Items.WorldRay(Vector3(0.0, 1.5, 8.0), Vector3(0.0, 0.0, -1.0));
    try
      AssertTrue(HitDoorway <> nil);
      AssertSameValue(12.4, HitDoorway.Distance, 0.08);
    finally
      FreeAndNil(HitDoorway);
    end;

    { Parallel raycast at X = 3.2 (solid stone wall beside doorway) hits outer front wall Z = +5.0 (Dist 3.0)! }
    HitSolidWall := Vp.Items.WorldRay(Vector3(3.2, 1.5, 8.0), Vector3(0.0, 0.0, -1.0));
    try
      AssertTrue(HitSolidWall <> nil);
      AssertSameValue(3.0, HitSolidWall.Distance, 0.08);
    finally
      FreeAndNil(HitSolidWall);
    end;

    { 2. Verify remaining architectural presets (Stairwell, RampWedge, Vaulted Cross, Cylinder Cloister) }
    Mezzanine := TCsgStudioHelper.SpawnCsgModeler(
      Vp, DesignOwner, capMezzanineRampAndStairs, Vector3(25.0, 0.0, 0.0));
    CrossHall := TCsgStudioHelper.SpawnCsgModeler(
      Vp, DesignOwner, capVaultedCrossHallway, Vector3(50.0, 0.0, 0.0));
    Cloister := TCsgStudioHelper.SpawnCsgModeler(
      Vp, DesignOwner, capPillaredCourtyardCloister, Vector3(75.0, 0.0, 0.0));

    AssertTrue(Mezzanine.OutputTriangleCount > 40);
    AssertTrue(Mezzanine.OutputVolumeCubicMeters > 20.0);
    AssertTrue(CrossHall.OutputTriangleCount > 40);
    AssertTrue(Cloister.OutputTriangleCount > 40);

    { 3. Disable collider on Cloister -> Audit flags warning & Markdown report lists all 4 modelers }
    Cloister.GenerateCollider := False;
    Report := TCsgStudioHelper.ScanDesign(Vp, DesignOwner);
    try
      AssertEquals(4, Length(Report.Modelers));
      AssertEquals(1, Report.Warnings.Count);
      AssertTrue(Pos('GenerateCollider = False', Report.Warnings[0]) > 0);
    finally
      FreeAndNil(Report);
    end;

    Md := TCsgStudioHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('CsgHollowRoom', Md) > 0);
    AssertTrue(Pos('LeftStairwell', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolCsgStudio);
end.
