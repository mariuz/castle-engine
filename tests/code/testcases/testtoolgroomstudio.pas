{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 348 Groom Strand Hair / Fur Clump Cards,
  Root-to-Tip Clumping, Head-Sphere Anti-Clipping & Verlet Wind Sway. }
unit TestToolGroomStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolGroomStudio = class(TCastleTestCase)
  published
    procedure TestGuideStrandClumpConvergenceHeadSphereAntiClipAndWindDeflection;
    procedure TestStylePresetsTriangleCountAndTransientCleanJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform,
  CastleComponentSerialize,
  CastleGroomHair, ToolGroomStudio;

procedure TTestToolGroomStudio.TestGuideStrandClumpConvergenceHeadSphereAntiClipAndWindDeflection;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Head: TCastleTransform;
  Groom: TCastleGroomComponent;
  TipGuide, TipChildLoose, TipChildTight: TVector3;
  LooseSpread, TightSpread, BaseDeflectX: Single;
  I: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TGroomStudioHelper.SpawnScalpHeadGroomDemo(Vp, DesignOwner, Head, Groom));
    AssertTrue(Groom <> nil);

    { 1. ClumpTightness = 1.0 pulls child tips strictly tighter to guide tip than 0.0 }
    Groom.CurlAmplitude := 0.0;
    Groom.FrizzAmount := 0.0;
    Groom.ClumpTightness := 0.0;
    TipGuide := Groom.EvaluateChildStrandPointLocal(0, 0, Groom.SegmentsPerStrand);
    TipChildLoose := Groom.EvaluateChildStrandPointLocal(0, 1, Groom.SegmentsPerStrand);
    LooseSpread := PointsDistance(TipGuide, TipChildLoose);
    AssertTrue(LooseSpread > 0.03);

    Groom.ClumpTightness := 1.0;
    TipChildTight := Groom.EvaluateChildStrandPointLocal(0, 1, Groom.SegmentsPerStrand);
    TightSpread := PointsDistance(TipGuide, TipChildTight);
    AssertSameValue(0.0, TightSpread, 0.001);

    { 2. Lateral +X wind deflects hair tips toward +X while scalp sphere prevents clipping }
    BaseDeflectX := Groom.MeanTipDeflectionX;
    Groom.WindVelocity := Vector3(7.5, 0.0, 0.0);
    for I := 1 to 25 do
      Groom.StepGroomPhysics(0.025);

    AssertTrue(Groom.MeanTipDeflectionX > BaseDeflectX + 0.04);
    AssertTrue(Groom.MinDistanceFromScalpCenter >= Groom.ScalpRadius * 1.0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolGroomStudio.TestStylePresetsTriangleCountAndTransientCleanJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  Head: TCastleTransform;
  Groom, RestoredGroom: TCastleGroomComponent;
  Warnings: TStringList;
  Sum: TGroomStudioSummary;
  JsonStr, ReportMd: String;
begin
  DesignOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  Warnings := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);
    AssertTrue(TGroomStudioHelper.SpawnScalpHeadGroomDemo(Vp, DesignOwner, Head, Groom));

    { 1. Verify exact card triangle formula: GuideCount * StrandsPerClump * SegmentsPerStrand * 2 }
    Groom.ApplyStylePreset(gspCurlyRinglets);
    AssertEquals(14 * 6 * 8 * 2, Groom.GeneratedTriangleCount);

    Groom.ApplyStylePreset(gspWolfManeFur);
    AssertEquals(20 * 5 * 4 * 2, Groom.GeneratedTriangleCount);

    Sum := TGroomStudioHelper.CollectSummary(Vp, Warnings);
    AssertEquals(1, Sum.GroomCount);
    AssertEquals(100, Sum.TotalStrands);
    ReportMd := TGroomStudioHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Groom Strand Hair & Fur Clump Cards Report', ReportMd) > 0);

    { 2. Transient hair card scene is never serialized into JSON }
    Groom.ClumpTightness := 0.64;
    JsonStr := ComponentToString(Groom);
    AssertEquals(0, Pos('TransientGroomCards', JsonStr));

    RestoredGroom := StringToComponent(JsonStr, RestoredOwner) as TCastleGroomComponent;
    AssertTrue(RestoredGroom <> nil);
    AssertTrue(RestoredGroom.Preset = gspCustom);
    AssertSameValue(0.64, RestoredGroom.ClumpTightness, 0.01);
    AssertEquals(1, RestoredGroom.Count);
    AssertTrue(csTransient in RestoredGroom[0].ComponentStyle);
  finally
    FreeAndNil(Warnings);
    FreeAndNil(RestoredOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolGroomStudio);

end.
