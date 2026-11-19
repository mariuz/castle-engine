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

{ Automated tests for Phase 395: Procedural Decal Splatter, WorldRay
  Directional Cone Burst & Grazing-Angle Streak Elongation Studio. }
unit TestToolSplatterBurst;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSplatterBurst = class(TCastleTestCase)
  published
    procedure TestHeadOnRoundDropletVsGrazingWallStreakElongation;
    procedure TestLruMaxActiveSplatsRingCapEvaporationFadeAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleSplatterBurst, ToolSplatterBurst;

procedure TTestToolSplatterBurst.TestHeadOnRoundDropletVsGrazingWallStreakElongation;
var
  Root: TComponent;
  VP: TCastleViewport;
  Burst: TCastleSplatterBurst;
  MarkHeadOn, MarkGrazing: TSplatDecalMark;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSplatterBurstHelper.SpawnCornerRoomSplatterDemo(Root, Root, Burst));
    AssertTrue(Burst.ActiveSplatCount >= 12);

    { Single-droplet test: 90 deg perpendicular hit onto SplatterNorthWall (Z=-5) }
    Burst.ClearSplats;
    Burst.DropletRayCount := 1;
    Burst.ConeHalfAngleDeg := 0.0;
    AssertEquals(1, Burst.EmitDirectionalBurst(
      VP.Items, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0)));
    MarkHeadOn := Burst.GetSplatMark(0);
    AssertSameValue(1.0, MarkHeadOn.StreakAspectRatio, 0.02);

    { Shallow ~12 deg grazing hit onto SplatterEastWall (inner West face at X=+2.0) }
    Burst.ClearSplats;
    AssertEquals(1, Burst.EmitDirectionalBurst(
      VP.Items, Vector3(1.5, 1.5, 0.0), Vector3(0.20, 0.0, -0.98).Normalize));
    MarkGrazing := Burst.GetSplatMark(0);
    AssertTrue('Grazing impact stretches streak aspect ratio > 3.0x',
      MarkGrazing.StreakAspectRatio > 3.0);
    AssertTrue('Streak tangent aligns primarily with -Z travel direction',
      MarkGrazing.StreakTangent.Z < -0.90);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolSplatterBurst.TestLruMaxActiveSplatsRingCapEvaporationFadeAndJsonRoundtrip;
var
  Root: TComponent;
  VP: TCastleViewport;
  Burst, Restored: TCastleSplatterBurst;
  SerializedScene, JsonCfg, Md: String;
begin
  Root := TComponent.Create(nil);
  Restored := TCastleSplatterBurst.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TSplatterBurstHelper.SpawnCornerRoomSplatterDemo(Root, Root, Burst));

    { Cap MaxActiveSplats = 16 and fire 3 bursts of 12 droplets -> capped at 16 }
    Burst.ClearSplats;
    Burst.MaxActiveSplats := 16;
    Burst.DropletRayCount := 12;
    Burst.DecalLifetimeSec := 8.0;
    Burst.EmitDirectionalBurst(VP.Items, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0));
    Burst.EmitDirectionalBurst(VP.Items, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0));
    Burst.EmitDirectionalBurst(VP.Items, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0));
    AssertEquals(16, Burst.ActiveSplatCount);

    { Step 4.0s -> Alpha01 fades to ~0.50; Step another 5.0s -> all evaporate to 0 }
    Burst.StepEvaporationFade(4.0);
    AssertEquals(16, Burst.ActiveSplatCount);
    AssertSameValue(0.50, Burst.GetSplatMark(0).Alpha01, 0.03);
    Burst.StepEvaporationFade(5.0);
    AssertEquals(0, Burst.ActiveSplatCount);

    Burst.EmitDirectionalBurst(VP.Items, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0));
    SerializedScene := ComponentToString(Burst);
    AssertTrue(Pos('SplatterBurstPreview', SerializedScene) = 0);

    Burst.ApplyPreset(sbpSlimeAcidBurst);
    JsonCfg := TSplatterBurstHelper.ExportBurstJson(Burst);
    AssertTrue(TSplatterBurstHelper.ImportBurstJson(Restored, JsonCfg));
    AssertEquals(Ord(sbpSlimeAcidBurst), Ord(Restored.Preset));
    Md := TSplatterBurstHelper.GenerateMarkdownReport(Burst);
    AssertTrue(Pos('SlimeAcidBurst', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolSplatterBurst);

end.
