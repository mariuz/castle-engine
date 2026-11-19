{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 392: Procedural Spiderweb, Radial WorldRay Wall
  Mooring, Logarithmic Capture Spiral & Dewdrop Silk Studio. }
unit TestToolSpiderweb;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSpiderweb = class(TCastleTestCase)
  published
    procedure TestArchwayWorldRayWallMooringCornerTensionPullAndIntactSpiral;
    procedure TestTornCryptDecayDewdropBeadsDeterminismAndTransientCleanJson;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleSpiderweb, ToolSpiderweb;

procedure TTestToolSpiderweb.TestArchwayWorldRayWallMooringCornerTensionPullAndIntactSpiral;
var
  Root: TComponent;
  VP: TCastleViewport;
  Web: TCastleSpiderwebGenerator;
  ExpectedIntactSegs: Integer;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSpiderwebHelper.SpawnDungeonArchwayWebDemo(Root, Root, Web));

    { Inside the enclosed 3.6m x 3.4m stone archway, all 12 radial spokes lock
      onto ArchwayFloorSill / ArchwayCeilingLintel / ArchwayPillarWest / East! }
    AssertEquals(12, Web.AnchoredSpokeCount);

    { Untorn symmetric orb web produces 12 spokes + 12 * 8 * 2 sagged spiral halves }
    ExpectedIntactSegs := 12 + (12 * 8 * 2);
    AssertEquals(ExpectedIntactSegs, Web.SilkSegmentCount);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolSpiderweb.TestTornCryptDecayDewdropBeadsDeterminismAndTransientCleanJson;
var
  Web, Restored: TCastleSpiderwebGenerator;
  SegsTorn1, SegsTorn2, SegsPristine: Integer;
  SerializedScene, JsonCfg, Md: String;
begin
  Web := TCastleSpiderwebGenerator.Create(nil);
  Restored := TCastleSpiderwebGenerator.Create(nil);
  try
    Web.ApplyPreset(swpSymmetricGardenOrbWeb);
    Web.SpokeCount := 14;
    Web.SpiralTurnCount := 9;
    SegsPristine := Web.WeaveSpiderwebOnWorld(nil);

    { Torn crypt preset removes ~34% of capture spiral sectors deterministically
      and spawns 0 dewdrops }
    Web.ApplyPreset(swpTornDungeonCornerCobweb);
    SegsTorn1 := Web.WeaveSpiderwebOnWorld(nil);
    SegsTorn2 := Web.WeaveSpiderwebOnWorld(nil);
    AssertEquals(SegsTorn1, SegsTorn2);
    AssertTrue('Torn crypt cobweb removes spiral segments vs pristine web',
      (SegsTorn1 > Web.SpokeCount) and (SegsTorn1 < SegsPristine - 20));
    AssertEquals(0, Web.DewdropCount);

    { Forest morning dew preset populates glistening dewdrop beads }
    Web.ApplyPreset(swpDewdropForestCanopySilk);
    Web.WeaveSpiderwebOnWorld(nil);
    AssertTrue('Morning dew preset places > 20 dewdrop beads', Web.DewdropCount > 20);

    SerializedScene := ComponentToString(Web);
    AssertTrue(Pos('SpiderwebPreview', SerializedScene) = 0);

    JsonCfg := TSpiderwebHelper.ExportWebJson(Web);
    AssertTrue(TSpiderwebHelper.ImportWebJson(Restored, JsonCfg));
    AssertEquals(Ord(swpDewdropForestCanopySilk), Ord(Restored.Preset));
    Md := TSpiderwebHelper.GenerateMarkdownReport(Web);
    AssertTrue(Pos('DewdropForestCanopySilk', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Web);
  end;
end;

initialization
  RegisterTest(TTestToolSpiderweb);

end.
