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

{ Automated tests for Phase 389: Modeling Mode UV Editor & Texel-Density Studio
  (UE 5.5 UVEditor Parity: 6-Face Box Triplanar & Cylindrical Seam-Cut Unwrap,
  Rectilinear Shelf Island Packing with Zero Overlap & Full [0..1] Containment,
  Stacked Overlapping UV Detection & 1-Click Repair, World-Space Texel Density
  Scaling, 109-Studio Hub & 32nd MCP Tool cge_unwrap_pack_uvs). }
unit TestToolUvEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolUvEditor = class(TCastleTestCase)
  published
    procedure TestBox6FaceShelfPackingZeroOverlapTexelDensityAndCleanJsonRoundtrip;
    procedure TestOverlappingStackedUvDetectionRepairAndCylindricalSeamContinuity;
    procedure TestUnified109StudioHubAnd32ndMcpUnwrapPackUvsTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleUvEditor, ToolUvEditor, ToolStudioHub, ToolMcpServer;

procedure TTestToolUvEditor.TestBox6FaceShelfPackingZeroOverlapTexelDensityAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  VP: TCastleViewport;
  Crate, LoadedCrate: TCastleUvEditorMesh;
  Audit1024, Audit2048: TUvLayoutAudit;
  JsonStr: String;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Crate := TUvEditorHelper.SpawnUvMeshPresetInDesign(
      VP, Root, umpArchitecturalCrate6Islands, Vector3(0, 0, 0));
    AssertTrue(Crate <> nil);

    { 1. 2.0m x 1.5m x 1.2m box has exact surface area 2*(3.0 + 2.4 + 1.8) = 14.40 m^2,
         6 distinct packed UV islands, 0 overlapping pairs, 0 inverted triangles, 0 out-of-bounds! }
    Crate.TextureResolution := 1024;
    Audit1024 := Crate.AuditUvLayout;
    AssertEquals(12, Audit1024.TriangleCount);
    AssertEquals(6, Audit1024.IslandCount);
    AssertEquals(0, Audit1024.OverlappingPairCount);
    AssertEquals(0, Audit1024.InvertedTriangleCount);
    AssertEquals(0, Audit1024.OutOfUnitBoundsCount);
    AssertSameValue(14.40, Audit1024.TotalWorldAreaM2, 1e-3);
    AssertTrue('Shelf packing achieves healthy UV coverage (> 35%)',
      Audit1024.UvCoveragePercent > 35.0);

    { 2. Doubling TextureResolution (1024 -> 2048) doubles world-space TexelsPerMeter! }
    Crate.TextureResolution := 2048;
    Audit2048 := Crate.AuditUvLayout;
    AssertSameValue(Audit1024.MeasuredTexelsPerMeter * 2.0,
      Audit2048.MeasuredTexelsPerMeter, 1e-2);
    AssertSameValue(512.0 / Audit2048.MeasuredTexelsPerMeter,
      Crate.ComputeTexelDensityScaleForTarget(512.0), 1e-4);

    { 3. SetTransient-clean JSON serialization roundtrip }
    JsonStr := ComponentToString(Crate);
    AssertTrue('SetTransient UV_CheckerPreview must not leak into serialized JSON',
      Pos('UV_CheckerPreview', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedCrate := StringToComponent(JsonStr, LoadOwner) as TCastleUvEditorMesh;
      AssertTrue(LoadedCrate <> nil);
      AssertEquals(12, Length(LoadedCrate.Triangles));
      AssertEquals(6, LoadedCrate.AuditUvLayout.IslandCount);
      AssertEquals(0, LoadedCrate.LastAudit.OverlappingPairCount);
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolUvEditor.TestOverlappingStackedUvDetectionRepairAndCylindricalSeamContinuity;
var
  Root: TComponent;
  VP: TCastleViewport;
  Stacked, Col: TCastleUvEditorMesh;
  AuditBefore, AuditAfter, ColAudit: TUvLayoutAudit;
  I: Integer;
  SpanU: Single;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    { 1. Stacked overlapping box faces trigger >= 15 overlapping triangle pairs,
         and 1-click AutoUnwrapAndPack(upmConformalSeamRelax) repairs it to 0 overlaps! }
    Stacked := TUvEditorHelper.SpawnUvMeshPresetInDesign(
      VP, Root, umpOverlappingStackedUvRepairDemo, Vector3(0, 0, 0));
    AuditBefore := Stacked.AuditUvLayout;
    AssertTrue('Stacked faces detected by 2D triangle-triangle overlap auditor',
      AuditBefore.OverlappingPairCount >= 15);

    Stacked.AutoUnwrapAndPack(upmConformalSeamRelax);
    AuditAfter := Stacked.AuditUvLayout;
    AssertEquals(0, AuditAfter.OverlappingPairCount);
    AssertEquals(0, AuditAfter.InvertedTriangleCount);
    AssertEquals(0, AuditAfter.OutOfUnitBoundsCount);

    { 2. 12-sided Cylindrical Column unwraps into 3 islands (Side wrap + Top cap + Bottom cap)
         with 0 overlaps, 0 inverted triangles, and no seam wrap-around stretch across [-Pi..+Pi]! }
    Col := TUvEditorHelper.SpawnUvMeshPresetInDesign(
      VP, Root, umpCylindricalColumnSeamUnwrap, Vector3(3, 0, 0));
    ColAudit := Col.AuditUvLayout;
    AssertEquals(48, ColAudit.TriangleCount);
    AssertEquals(3, ColAudit.IslandCount);
    AssertEquals(0, ColAudit.OverlappingPairCount);
    AssertEquals(0, ColAudit.InvertedTriangleCount);
    AssertEquals(0, ColAudit.OutOfUnitBoundsCount);

    for I := 0 to High(Col.Triangles) do
    begin
      SpanU := Max(Col.Triangles[I].UV[0].X, Max(Col.Triangles[I].UV[1].X, Col.Triangles[I].UV[2].X)) -
               Min(Col.Triangles[I].UV[0].X, Min(Col.Triangles[I].UV[1].X, Col.Triangles[I].UV[2].X));
      AssertTrue('No cylindrical triangle stretches across the whole seam width', SpanU < 0.35);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolUvEditor.TestUnified109StudioHubAnd32ndMcpUnwrapPackUvsTool;
var
  Root: TComponent;
  VP: TCastleViewport;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify 109 UE Studios in Studio Hub (Phase 389 uv_editor) }
  AssertEquals(111, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('uv_editor', Entry));
  AssertEquals(389, Entry.PhaseNumber);

  { 2. Verify 32nd MCP tool cge_unwrap_pack_uvs }
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';

    Srv := TCastleMcpServer.Create(Root);
    Srv.AutonomyMode := mamEditWithUndo;
    Srv.StandaloneDesignRoot := VP;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    OuterJson := GetJSON(ListResp);
    try
      ToolsArr := OuterJson.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(34, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_unwrap_pack_uvs","arguments":{"action":"spawn_preset","preset":"overlap_demo"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['meshCount']);
        AssertTrue(PayloadObj.Integers['totalOverlappingPairs'] >= 15);
        AssertEquals(111, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_unwrap_pack_uvs","arguments":{"action":"unwrap_pack","projection":"box6"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(0, PayloadObj.Integers['totalOverlappingPairs']);
        AssertEquals(6, PayloadObj.Integers['totalIslands']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolUvEditor);
end.
