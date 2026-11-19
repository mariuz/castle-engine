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

{ Automated tests for Phase 390: Diegetic 3D World-Space Hologram, Offscreen
  Edge Clamping & WorldRay X-Ray Occluded Waypoint Studio. }
unit TestToolWorldWaypoint;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolWorldWaypoint = class(TCastleTestCase)
  published
    procedure TestClearVsXRayWallOccludedAndAdsCenterReticleDeclutterFade;
    procedure TestBehindCameraHemisphereSafeEdgeClampingRangeCullAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleComponentSerialize,
  CastleWorldWaypoint, ToolWorldWaypoint;

procedure TTestToolWorldWaypoint.TestClearVsXRayWallOccludedAndAdsCenterReticleDeclutterFade;
var
  Root: TComponent;
  VP: TCastleViewport;
  Waypoint: TCastleWorldWaypoint;
  ProjClear, ProjOcc, ProjAds: TWaypointHudProjection;
begin
  Root := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(Root);
    VP.Name := 'MainViewport';
    AssertTrue(TWorldWaypointHelper.SpawnCourtyardWaypointDemo(Root, Root, Waypoint));

    { 1. Flanking camera at X = +8m bypasses CourtyardOccluderWall -> Clear LoS }
    ProjClear := Waypoint.EvaluateForCamera(
      VP.Items, Vector3(8.0, 1.85, 0.0),
      (Vector3(0.0, 1.85, -16.0) - Vector3(8.0, 1.85, 0.0)).Normalize,
      Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, False);
    AssertEquals(Ord(wssOnScreenClear), Ord(ProjClear.State));
    AssertFalse(ProjClear.IsOccludedByWall);
    AssertSameValue(0.50, ProjClear.ScreenUv.X, 0.01);
    AssertSameValue(0.50, ProjClear.ScreenUv.Y, 0.01);
    AssertSameValue(1.0, ProjClear.IconOpacity01, 0.001);

    { 2. Camera at origin looking straight through CourtyardOccluderWall (Z = -8m)
         toward RelicShrineObjective (Z = -16m) -> X-Ray occluded wall state! }
    ProjOcc := Waypoint.EvaluateForCamera(
      VP.Items, Vector3(0.0, 1.85, 0.0),
      Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, False);
    AssertEquals(Ord(wssOnScreenOccludedWall), Ord(ProjOcc.State));
    AssertTrue(ProjOcc.IsOccludedByWall);
    AssertSameValue(Waypoint.OccludedWallOpacity01, ProjOcc.IconOpacity01, 0.001);

    { 3. Aiming down sights directly at waypoint attenuates center-crosshair opacity }
    ProjAds := Waypoint.EvaluateForCamera(
      VP.Items, Vector3(8.0, 1.85, 0.0),
      (Vector3(0.0, 1.85, -16.0) - Vector3(8.0, 1.85, 0.0)).Normalize,
      Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, True);
    AssertSameValue(Waypoint.AdsMinCenterOpacity01, ProjAds.IconOpacity01, 0.01);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolWorldWaypoint.TestBehindCameraHemisphereSafeEdgeClampingRangeCullAndJsonRoundtrip;
var
  Waypoint, Restored: TCastleWorldWaypoint;
  ProjBehindRight, ProjCulled: TWaypointHudProjection;
  SerializedScene, JsonCfg, Md: String;
begin
  Waypoint := TCastleWorldWaypoint.Create(nil);
  Restored := TCastleWorldWaypoint.Create(nil);
  try
    Waypoint.Translation := Vector3(5.0, 0.0, 12.0);
    { Camera at origin looking -Z: waypoint at (+5, +1.85, +12) is BEHIND camera
      and to the camera's RIGHT (+X). Hemisphere-safe clamping must pin ScreenUv.X
      to the RIGHT safe border (0.94), NEVER inverted to the left (0.06)! }
    ProjBehindRight := Waypoint.EvaluateForCamera(
      nil, Vector3(0.0, 1.85, 0.0),
      Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, False);
    AssertTrue(ProjBehindRight.IsBehindCamera);
    AssertEquals(Ord(wssOffScreenClampedEdge), Ord(ProjBehindRight.State));
    AssertSameValue(1.0 - Waypoint.SafeEdgeMargin01, ProjBehindRight.ScreenUv.X, 0.01);

    { Loot beacon beyond MaxVisibleDistMeters (45m) is culled cleanly }
    Waypoint.ApplyPreset(wwpLootRarityBeacon);
    Waypoint.Translation := Vector3(0.0, 0.0, -120.0);
    ProjCulled := Waypoint.EvaluateForCamera(
      nil, TVector3.Zero, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0),
      60.0, 16.0 / 9.0, False);
    AssertEquals(Ord(wssCulledByRange), Ord(ProjCulled.State));
    AssertSameValue(0.0, ProjCulled.IconOpacity01, 0.001);

    { Transient preview exclusion & JSON roundtrip }
    SerializedScene := ComponentToString(Waypoint);
    AssertTrue(Pos('WorldWaypointPreview', SerializedScene) = 0);

    Waypoint.LabelCaption := 'Boss Vault Key';
    JsonCfg := TWorldWaypointHelper.ExportWaypointJson(Waypoint);
    AssertTrue(TWorldWaypointHelper.ImportWaypointJson(Restored, JsonCfg));
    AssertEquals('Boss Vault Key', Restored.LabelCaption);
    Md := TWorldWaypointHelper.GenerateMarkdownReport(Waypoint);
    AssertTrue(Pos('Boss Vault Key', Md) > 0);
  finally
    FreeAndNil(Restored);
    FreeAndNil(Waypoint);
  end;
end;

initialization
  RegisterTest(TTestToolWorldWaypoint);

end.
