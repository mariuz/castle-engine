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

{ Automated tests for Phase 396: Viewport Mesh Vertex Paint Mode & Multi-Layer
  Blend Weights (UMeshPaintMode Parity), 116-Studio Hub & 39th MCP Tool
  (cge_paint_mesh_vertices). }
unit TestToolVertexPaint;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, fpjson, jsonparser,
  CastleTester, CastleVectors, CastleComponentSerialize,
  CastleUIControls, CastleViewport, CastleTransform,
  CastleVertexPaint, ToolVertexPaint, ToolStudioHub, ToolMcpServer;

type
  TTestToolVertexPaint = class(TCastleTestCase)
  published
    procedure TestRadialFalloffChannelMaskIsolationEraseAndNormalFilter;
    procedure TestHeightLerpCreviceFirstMirrorPuddleLaplacianSmoothAndJsonRoundtrip;
    procedure TestUnified116StudioHubAnd39thMcpPaintMeshVertices;
  end;

implementation

procedure TTestToolVertexPaint.TestRadialFalloffChannelMaskIsolationEraseAndNormalFilter;
var
  OwnerComp, RootUi: TComponent;
  VP: TCastleViewport;
  Mesh: TCastleVertexPaintMesh;
  CenterIdx, MidIdx, FarIdx, Affected: Integer;
  OrigBlue, OrigAlpha: Single;
begin
  OwnerComp := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(OwnerComp);
    VP := TCastleViewport.Create(OwnerComp);
    TCastleUserInterface(RootUi).InsertFront(VP);

    Mesh := TVertexPaintHelper.SpawnVertexPaintPresetInDesign(
      RootUi, OwnerComp, vppCobblestoneWallMossPuddles, Vector3(0, 0, 0));
    AssertTrue(Mesh <> nil);
    AssertEquals(221, Mesh.VertexCount);
    AssertEquals(384, Mesh.TriangleCount);

    { Start from exact known channels: R=0, G=0, B=0.37, A=0.61 }
    Mesh.FillVertices(Vector4(0.0, 0.0, 0.37, 0.61), TCastleVertexPaintMesh.AllPaintChannels);
    CenterIdx := Mesh.FindNearestVertexLocal(Vector3(0, -0.25, 0));
    MidIdx := Mesh.FindNearestVertexLocal(Vector3(1.5, 0, 0));
    FarIdx := Mesh.FindNearestVertexLocal(Vector3(4.8, 0, 3.8));
    AssertTrue((CenterIdx >= 0) and (MidIdx >= 0) and (FarIdx >= 0));

    OrigBlue := Mesh.Vertices[CenterIdx].ColorRGBA.Z;
    OrigAlpha := Mesh.Vertices[CenterIdx].ColorRGBA.W;

    { 1. Paint ONLY [vpcGreen] with R=2.5m, Falloff=0.6, Strength=1.0 }
    Affected := Mesh.ApplyBrushStroke(
      Mesh.Vertices[CenterIdx].Position, 2.5, 0.6, 1.0,
      Vector4(0.99, 1.0, 0.99, 0.99), [vpcGreen], False);
    AssertTrue(Affected >= 10);

    { Center vertex inside InnerRadius gets full 1.0 Green; Mid vertex gets smooth falloff; Far vertex untouched }
    AssertSameValue(1.0, Mesh.Vertices[CenterIdx].ColorRGBA.Y, 0.01);
    AssertTrue((Mesh.Vertices[MidIdx].ColorRGBA.Y > 0.05) and
               (Mesh.Vertices[MidIdx].ColorRGBA.Y < 0.98));
    AssertSameValue(0.0, Mesh.Vertices[FarIdx].ColorRGBA.Y, 0.0001);

    { Channel Mask Isolation: Red, Blue, and Alpha MUST remain bit-exact untouched! }
    AssertSameValue(0.0, Mesh.Vertices[CenterIdx].ColorRGBA.X, 0.0001);
    AssertSameValue(OrigBlue, Mesh.Vertices[CenterIdx].ColorRGBA.Z, 0.0001);
    AssertSameValue(OrigAlpha, Mesh.Vertices[CenterIdx].ColorRGBA.W, 0.0001);

    { 2. Normal-Angle Filter: painting downward (-Y) onto upward (+Y) floor slab hits 0 vertices }
    Affected := Mesh.ApplyBrushStroke(
      Mesh.Vertices[CenterIdx].Position, 3.0, 0.5, 1.0,
      Vector4(1, 0, 0, 0), [vpcRed], False, 0.50, Vector3(0, -1, 0));
    AssertEquals(0, Affected);

    { 3. Shift-Erase restores Green toward EraseColor (0.0) without touching Blue/Alpha }
    Mesh.ApplyBrushStroke(
      Mesh.Vertices[CenterIdx].Position, 2.5, 0.2, 1.0,
      Vector4(0, 1, 0, 0), [vpcGreen], True);
    AssertSameValue(0.0, Mesh.Vertices[CenterIdx].ColorRGBA.Y, 0.01);
    AssertSameValue(OrigBlue, Mesh.Vertices[CenterIdx].ColorRGBA.Z, 0.0001);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolVertexPaint.TestHeightLerpCreviceFirstMirrorPuddleLaplacianSmoothAndJsonRoundtrip;
var
  OwnerComp, RehydratedOwner: TComponent;
  Mesh, RehydratedMesh: TCastleVertexPaintMesh;
  CreviceIdx, RaisedIdx, I: Integer;
  SurfDry, SurfCrevice, SurfRaised, SurfWet: TVertexPaintSurfaceSample;
  EnergyBefore, EnergyAfter: Single;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Mesh := TCastleVertexPaintMesh.Create(OwnerComp);
    Mesh.Name := 'TestBastionPaintMesh';
    Mesh.FillVertices(Vector4(0, 0, 0, 0), TCastleVertexPaintMesh.AllPaintChannels);

    { Find a deep mortar crevice vertex vs. a raised stone face vertex }
    CreviceIdx := 0;
    RaisedIdx := 0;
    for I := 1 to Mesh.VertexCount - 1 do
    begin
      if Mesh.Vertices[I].MicroHeight01 < Mesh.Vertices[CreviceIdx].MicroHeight01 then
        CreviceIdx := I;
      if Mesh.Vertices[I].MicroHeight01 > Mesh.Vertices[RaisedIdx].MicroHeight01 then
        RaisedIdx := I;
    end;
    AssertTrue(Mesh.Vertices[CreviceIdx].MicroHeight01 < 0.45);
    AssertTrue(Mesh.Vertices[RaisedIdx].MicroHeight01 > 0.75);

    { At moderate Moss weight (R = 0.45), UE HeightLerp fills the mortar crevice
      significantly stronger than the raised stone brick face! }
    Mesh.FillVertices(Vector4(0.45, 0.0, 0.0, 0.0), [vpcRed]);
    SurfCrevice := Mesh.EvaluateBlendedSurface(CreviceIdx);
    SurfRaised := Mesh.EvaluateBlendedSurface(RaisedIdx);
    AssertTrue(SurfCrevice.EffectiveMoss > SurfRaised.EffectiveMoss + 0.25);

    { Painting full Rain Puddle [G = 1.0] drops PBR Roughness from ~0.80 down to mirror-wet 0.06! }
    Mesh.FillVertices(Vector4(0.0, 0.0, 0.0, 0.0), TCastleVertexPaintMesh.AllPaintChannels);
    SurfDry := Mesh.EvaluateBlendedSurface(CreviceIdx);
    Mesh.FillVertices(Vector4(0.0, 1.0, 0.0, 0.0), [vpcGreen]);
    SurfWet := Mesh.EvaluateBlendedSurface(CreviceIdx);
    AssertTrue(SurfDry.Roughness > 0.70);
    AssertSameValue(0.06, SurfWet.Roughness, 0.02);

    { Paint a harsh sharp-edged Red dot (Falloff = 0.0), then prove 1-ring Laplacian
      Smooth strictly reduces neighbor seam roughness energy! }
    Mesh.FillVertices(Vector4(0, 0, 0, 0), TCastleVertexPaintMesh.AllPaintChannels);
    Mesh.ApplyBrushStroke(Vector3(0, 0, 0), 1.6, 0.0, 1.0,
      Vector4(1, 0, 0, 0), [vpcRed], False);
    EnergyBefore := Mesh.ComputeChannelRoughnessEnergy(vpcRed);
    AssertTrue(EnergyBefore > 0.005);

    Mesh.SmoothVertexColors(Vector3(0, 0, 0), 4.0, 0.85, [vpcRed], True);
    EnergyAfter := Mesh.ComputeChannelRoughnessEnergy(vpcRed);
    AssertTrue(EnergyAfter < EnergyBefore * 0.65);

    { Swap & Invert verification }
    Mesh.PaintColor := Vector4(1, 0.2, 0, 1);
    Mesh.EraseColor := Vector4(0, 0, 0, 0);
    Mesh.SwapPaintAndEraseColors;
    AssertSameValue(1.0, Mesh.EraseColor.X, 0.001);
    Mesh.InvertChannels([vpcAlpha]);
    AssertSameValue(1.0, Mesh.AverageChannelWeight(vpcAlpha), 0.001);

    { Lossless JSON roundtrip with transient preview scene excluded }
    JsonStr := ComponentToString(Mesh);
    AssertEquals(0, Pos('TCastleScene', JsonStr));
    RehydratedOwner := TComponent.Create(nil);
    try
      RehydratedMesh := StringToComponent(JsonStr, RehydratedOwner) as TCastleVertexPaintMesh;
      AssertEquals(Mesh.VertexCount, RehydratedMesh.VertexCount);
      AssertSameValue(Mesh.AverageChannelWeight(vpcRed),
        RehydratedMesh.AverageChannelWeight(vpcRed), 0.002);
      AssertSameValue(1.0, RehydratedMesh.AverageChannelWeight(vpcAlpha), 0.002);
    finally
      FreeAndNil(RehydratedOwner);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolVertexPaint.TestUnified116StudioHubAnd39thMcpPaintMeshVertices;
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
  AssertEquals(116, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('mesh_vertex_paint', Entry));
  AssertEquals(396, Entry.PhaseNumber);

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
      AssertEquals(39, ToolsArr.Count);
      FoundTool := False;
      for I := 0 to ToolsArr.Count - 1 do
        if TJSONObject(ToolsArr.Items[I]).Get('name', '') = 'cge_paint_mesh_vertices' then
          FoundTool := True;
      AssertTrue(FoundTool);
    finally
      FreeAndNil(ParsedResp);
    end;

    { 1. Spawn cobblestone mesh via MCP }
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_paint_mesh_vertices","arguments":{"action":"spawn_preset","preset":"cobblestone_courtyard"}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertEquals(1, TJSONObject(InnerData).Get('paintedMeshCount', 0));
        AssertEquals(221, TJSONObject(InnerData).Get('vertexCount', 0));
        AssertEquals(116, TJSONObject(InnerData).Get('studioCatalogCount', 0));
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    { 2. Paint a Rain Puddle [G] stroke + Smooth via MCP }
    CallResp := Mcp.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_paint_mesh_vertices","arguments":{"action":"paint_stroke","channel":"green","radius":3.2,"strength":1.0}}}');
    ParsedResp := GetJSON(CallResp);
    try
      InnerData := GetJSON((ParsedResp.FindPath('result.content[0].text')).AsString);
      try
        AssertTrue(TJSONObject(InnerData).Get('affectedVertices', 0) >= 20);
        AssertTrue(TJSONObject(InnerData).Get('avgPuddlePct', 0.0) > 15.0);
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(ParsedResp);
    end;

    MdReport := TStudioHubManager.BuildExecutiveMarkdownReport(RootUi, OwnerComp);
    AssertTrue(Pos('`116` across `6` domains', MdReport) > 0);
  finally
    FreeAndNil(Mcp);
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolVertexPaint);

end.
