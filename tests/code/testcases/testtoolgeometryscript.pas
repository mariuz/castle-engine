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

{ Automated unit tests for Phase 325 Geometry Script Non-Destructive Procedural
  Mesh Operator Stack & Parametric 3D Turtle L-System Botanical Studio
  (@link(TCastleGeometryScriptMesh), @link(TCastleLSystemBotanical),
  @link(TGeometryScriptHelper)). }
unit TestToolGeometryScript;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolGeometryScript = class(TCastleTestCase)
  published
    procedure TestGeometryScriptModifierStackSubdivide4xTwistSolidifyNonDestructiveToggleAndJson;
    procedure TestLSystemStringRewriting3DTurtleBranchingTropismAndCanopyBounds;
  end;

implementation

uses
  CastleViewport, CastleComponentSerialize,
  CastleGeometryScript, ToolGeometryScript;

procedure TTestToolGeometryScript.TestGeometryScriptModifierStackSubdivide4xTwistSolidifyNonDestructiveToggleAndJson;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Mesh, LoadedMesh: TCastleGeometryScriptMesh;
  Tree: TCastleLSystemBotanical;
  BaseTris, SubdivTris, SolidTris: Integer;
  BaseArea: Single;
  SubIdx, SolidIdx: Integer;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TGeometryScriptHelper.SpawnGeometryAndTreeShowcaseDemo(Vp, OwnerComp, Mesh, Tree);

    { 1. Clean base mesh -> Subdivide 4x -> Solidify 2x -> Non-destructive disable }
    Mesh.ClearModifiers;
    Mesh.BaseShape := gbsSubdividedBox;
    Mesh.HeightRings := 2;
    Mesh.RebuildProceduralMesh;
    BaseTris := Mesh.TriangleCount; // 6 faces * 2*2 quads * 2 tris = 48 triangles
    BaseArea := Mesh.ComputedSurfaceArea;
    AssertEquals(48, BaseTris);
    AssertTrue(BaseArea > 10.0);

    SubIdx := Mesh.AddModifier(gmkLinearSubdivide4x, 1.0, 0.0, True);
    SubdivTris := Mesh.TriangleCount;
    AssertEquals(BaseTris * 4, SubdivTris); // Exact 4x triangle subdivision (192 tris)!

    SolidIdx := Mesh.AddModifier(gmkSolidifyShell, 0.08, 0.0, True);
    SolidTris := Mesh.TriangleCount;
    AssertEquals(SubdivTris * 2, SolidTris); // Exact 2x inner+outer shell (384 tris)!

    { Non-destructively toggling both stages OFF restores exact 48 base triangles & area }
    Mesh.SetModifierEnabled(SolidIdx, False);
    Mesh.SetModifierEnabled(SubIdx, False);
    AssertEquals(BaseTris, Mesh.TriangleCount);
    AssertSameValue(BaseArea, Mesh.ComputedSurfaceArea, 1e-3);
    AssertEquals(2, Mesh.ModifierCount); // Stages remain intact in stack!

    Mesh.SetModifierEnabled(SubIdx, True);
    JsonStr := ComponentToString(Mesh);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleGeometryScriptMesh);
    LoadedMesh := TCastleGeometryScriptMesh(LoadedComp);
    AssertEquals(BaseTris * 4, LoadedMesh.TriangleCount);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolGeometryScript.TestLSystemStringRewriting3DTurtleBranchingTropismAndCanopyBounds;
var
  Expanded: String;
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Mesh: TCastleGeometryScriptMesh;
  Tree: TCastleLSystemBotanical;
  SunlitMaxY, WeepingMaxY: Single;
  Rep: TGeometryScriptAuditReport;
begin
  { 1. Deterministic L-System string expansion }
  Expanded := ExpandLSystemString('FX', 'FF', 'F+X', 2);
  { Iter 1: 'FX' -> 'FFF+X'; Iter 2: 'FF' + 'FF' + 'FF' + '+' + 'F+X' = 'FFFFFF+F+X' }
  AssertEquals('FFFFFF+F+X', Expanded);

  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TGeometryScriptHelper.SpawnGeometryAndTreeShowcaseDemo(Vp, OwnerComp, Mesh, Tree);

    { 2. Broadleaf Oak 3D yaw/pitch/roll turtle produces volumetric X and Z spread }
    Tree.ApplyPreset(lspBroadleafOakTree);
    AssertTrue(Tree.BranchSegmentCount > 15);
    AssertTrue(Tree.LeafCardCount > 8);
    AssertTrue(Tree.BoundsSpanX > 0.8);
    AssertTrue(Tree.BoundsSpanZ > 0.8);

    { 3. Positive upward phototropism (+0.30) yields taller crown than weeping gravitropism (-0.30) }
    Tree.TropismY := 0.30;
    SunlitMaxY := Tree.CrownBoundsMaxY;
    Tree.TropismY := -0.30;
    WeepingMaxY := Tree.CrownBoundsMaxY;
    AssertTrue(SunlitMaxY > WeepingMaxY + 0.5);

    Rep := TGeometryScriptHelper.AuditGeometryScript(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.GeoMeshCount);
      AssertEquals(1, Rep.BotanicalCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolGeometryScript);
end.
