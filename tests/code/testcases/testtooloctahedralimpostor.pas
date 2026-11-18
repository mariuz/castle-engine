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

{ Automated tests for Phase 374 Octahedral Billboard Impostor Atlas Studio. }
unit TestToolOctahedralImpostor;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolOctahedralImpostor = class(TCastleTestCase)
  published
    procedure TestHemiOctahedralReversibleEncodingAndExactGridVertexKroneckerWeights;
    procedure TestBarycentricSimplexInterpolationDistanceSwitchoverAndConfigJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleOctahedralImpostor, ToolOctahedralImpostor;

procedure TTestToolOctahedralImpostor.TestHemiOctahedralReversibleEncodingAndExactGridVertexKroneckerWeights;
const
  TestDirs: array[0..5] of TVector3 = (
    (X:  0.0; Y: 1.0; Z:  0.0),
    (X:  1.0; Y: 0.0; Z:  0.0),
    (X: -1.0; Y: 0.0; Z:  0.0),
    (X:  0.0; Y: 0.0; Z:  1.0),
    (X:  0.37; Y: 0.82; Z: -0.44),
    (X: -0.65; Y: 0.21; Z:  0.73)
  );
var
  I: Integer;
  InDir, OutDir: TVector3;
  Uv: TVector2;
  RootOwner: TComponent;
  Imp: TCastleOctahedralImpostor;
  SamplePole, SampleGridNode: TOctahedralBlendSample;
begin
  { 1. Verify bijective upper-hemisphere encode/decode roundtrip (< 1e-4 error) }
  for I := Low(TestDirs) to High(TestDirs) do
  begin
    InDir := TestDirs[I].Normalize;
    Uv := TCastleOctahedralImpostor.EncodeHemiOctahedralUv(InDir);
    AssertTrue((Uv.X >= 0.0) and (Uv.X <= 1.0));
    AssertTrue((Uv.Y >= 0.0) and (Uv.Y <= 1.0));
    OutDir := TCastleOctahedralImpostor.DecodeHemiOctahedralDir(Uv);
    AssertSameValue(InDir.X, OutDir.X, 1e-4);
    AssertSameValue(InDir.Y, OutDir.Y, 1e-4);
    AssertSameValue(InDir.Z, OutDir.Z, 1e-4);
  end;

  { 2. Top pole (0, 1, 0) encodes to exact center (0.5, 0.5) }
  Uv := TCastleOctahedralImpostor.EncodeHemiOctahedralUv(Vector3(0.0, 1.0, 0.0));
  AssertSameValue(0.5, Uv.X, 1e-5);
  AssertSameValue(0.5, Uv.Y, 1e-5);

  { 3. Exact grid node (3 / 7, 5 / 7) on 8x8 grid yields Kronecker delta weight 1.0 on tile (3, 5) }
  RootOwner := TComponent.Create(nil);
  try
    Imp := TCastleOctahedralImpostor.Create(RootOwner);
    Imp.Preset := oipPineCanopy8x8;
    SampleGridNode := Imp.SampleAtlasBarycentric(Vector2(3.0 / 7.0, 5.0 / 7.0));
    AssertEquals(3, SampleGridNode.Cell0X);
    AssertEquals(5, SampleGridNode.Cell0Y);
    AssertEquals(5 * 8 + 3, SampleGridNode.TileIndex0);
    AssertSameValue(1.0, SampleGridNode.Weight0, 1e-5);
    AssertSameValue(0.0, SampleGridNode.Weight1, 1e-5);
    AssertSameValue(0.0, SampleGridNode.Weight2, 1e-5);

    SamplePole := Imp.SampleAtlasBarycentric(Vector2(0.5, 0.5));
    AssertSameValue(1.0, SamplePole.Weight0 + SamplePole.Weight1 + SamplePole.Weight2, 1e-5);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolOctahedralImpostor.TestBarycentricSimplexInterpolationDistanceSwitchoverAndConfigJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Imp, Restored: TCastleOctahedralImpostor;
  NearSample, FarSample: TOctahedralBlendSample;
  JsonStr, ReportMd: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TOctahedralImpostorHelper.SpawnPineCanopyImpostorDemo(Vp, RootOwner, Imp));
    AssertEquals(64, Imp.TotalAtlasViews);
    AssertEquals(256, Imp.TileResolutionPx);

    { 1. Near observer (18m < 45m SwitchDistanceMeters) stays on high-poly mesh }
    NearSample := Imp.EvaluateCameraObserver(Vector3(0.0, 8.0, 16.0));
    AssertFalse(NearSample.UseImpostorCard);
    AssertSameValue(1.0, NearSample.Weight0 + NearSample.Weight1 + NearSample.Weight2, 1e-5);

    { 2. Far observer (> 45m) switches to octahedral billboard card with 3 non-negative weights summing to 1.0 }
    FarSample := Imp.EvaluateCameraObserver(Vector3(52.0, 28.0, 64.0));
    AssertTrue(FarSample.UseImpostorCard);
    AssertTrue((FarSample.Weight0 >= 0.0) and (FarSample.Weight1 >= 0.0) and (FarSample.Weight2 >= 0.0));
    AssertSameValue(1.0, FarSample.Weight0 + FarSample.Weight1 + FarSample.Weight2, 1e-5);

    ReportMd := TOctahedralImpostorHelper.GenerateImpostorReport(Imp);
    AssertTrue(Pos('IMPOSTOR BILLBOARD CARD', ReportMd) > 0);

    { 3. Preset + custom properties survive JSON roundtrip without transient child duplication }
    Imp.Preset := oipCliffspire12x12;
    JsonStr := ComponentToString(Imp);
    AssertEquals('csTransient preview must not serialize into JSON', 0, Pos('ImpostorPreviewTransient', JsonStr));

    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastleOctahedralImpostor;
    AssertEquals(Ord(oipCliffspire12x12), Ord(Restored.Preset));
    AssertEquals(12, Restored.AtlasGridSize);
    AssertEquals(144, Restored.TotalAtlasViews);
    AssertSameValue(80.0, Restored.SwitchDistanceMeters, 1e-3);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolOctahedralImpostor);
end.
