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

{ Design-time helper for Diegetic 3D World-Space Hologram, Offscreen Edge
  Clamping & WorldRay X-Ray Occluded Waypoint Studio (Phase 390). }
unit ToolWorldWaypoint;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleWorldWaypoint;

type
  TWorldWaypointHelper = class
  public
    class function FindFirstWaypoint(const ARoot: TComponent): TCastleWorldWaypoint;
    class function SpawnCourtyardWaypointDemo(const ARoot, AOwner: TComponent;
      out AWaypoint: TCastleWorldWaypoint): Boolean;
    class function ExportWaypointJson(const AWaypoint: TCastleWorldWaypoint): String;
    class function ImportWaypointJson(const AWaypoint: TCastleWorldWaypoint;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AWaypoint: TCastleWorldWaypoint): String;
  end;

implementation

uses
  CastleUtils;

function FindViewportInTree(const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleViewport then Exit(TCastleViewport(ARoot));
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindViewportInTree(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TWorldWaypointHelper.FindFirstWaypoint(
  const ARoot: TComponent): TCastleWorldWaypoint;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleWorldWaypoint;
  var
    J: Integer;
  begin
    if T is TCastleWorldWaypoint then
      Exit(TCastleWorldWaypoint(T));
    for J := 0 to T.Count - 1 do
    begin
      Result := SearchTransform(T[J]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleWorldWaypoint then
    Exit(TCastleWorldWaypoint(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleWorldWaypoint then
      Exit(TCastleWorldWaypoint(ARoot.Components[I]));
end;

class function TWorldWaypointHelper.SpawnCourtyardWaypointDemo(
  const ARoot, AOwner: TComponent; out AWaypoint: TCastleWorldWaypoint): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  BunkerWall: TCastleBox;
begin
  Result := False;
  AWaypoint := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  BunkerWall := TCastleBox.Create(Own);
  BunkerWall.Name := 'CourtyardOccluderWall';
  BunkerWall.Size := Vector3(5.0, 4.0, 0.6);
  BunkerWall.Translation := Vector3(0.0, 2.0, -8.0);
  BunkerWall.Color := Vector4(0.42, 0.44, 0.48, 1.0);
  VP.Items.Add(BunkerWall);

  AWaypoint := TCastleWorldWaypoint.Create(Own);
  AWaypoint.Name := 'RelicShrineObjective';
  AWaypoint.LabelCaption := 'Extract Sunfire Relic';
  AWaypoint.Translation := Vector3(0.0, 0.0, -16.0);
  AWaypoint.ApplyPreset(wwpQuestObjectiveDiamond);
  VP.Items.Add(AWaypoint);

  AWaypoint.EvaluateForCamera(
    VP.Items, Vector3(6.0, 2.0, 0.0),
    (Vector3(0.0, 1.85, -16.0) - Vector3(6.0, 2.0, 0.0)).Normalize,
    Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, False);
  Result := True;
end;

class function TWorldWaypointHelper.ExportWaypointJson(
  const AWaypoint: TCastleWorldWaypoint): String;
var
  Obj: TJSONObject;
begin
  if AWaypoint = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AWaypoint.Preset));
    Obj.Add('labelCaption', AWaypoint.LabelCaption);
    Obj.Add('verticalAnchorOffsetY', AWaypoint.VerticalAnchorOffsetY);
    Obj.Add('minVisibleDistMeters', AWaypoint.MinVisibleDistMeters);
    Obj.Add('maxVisibleDistMeters', AWaypoint.MaxVisibleDistMeters);
    Obj.Add('safeEdgeMargin01', AWaypoint.SafeEdgeMargin01);
    Obj.Add('occludedWallOpacity01', AWaypoint.OccludedWallOpacity01);
    Obj.Add('adsCenterFadeConeDeg', AWaypoint.AdsCenterFadeConeDeg);
    Obj.Add('clampOffscreenToEdge', AWaypoint.ClampOffscreenToEdge);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TWorldWaypointHelper.ImportWaypointJson(
  const AWaypoint: TCastleWorldWaypoint; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AWaypoint = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AWaypoint.Preset));
    if (POrd >= Ord(Low(TWaypointPreset))) and (POrd <= Ord(High(TWaypointPreset))) then
      AWaypoint.Preset := TWaypointPreset(POrd);
    AWaypoint.LabelCaption := Obj.Get('labelCaption', AWaypoint.LabelCaption);
    AWaypoint.VerticalAnchorOffsetY := Obj.Get('verticalAnchorOffsetY', AWaypoint.VerticalAnchorOffsetY);
    AWaypoint.MinVisibleDistMeters := Obj.Get('minVisibleDistMeters', AWaypoint.MinVisibleDistMeters);
    AWaypoint.MaxVisibleDistMeters := Obj.Get('maxVisibleDistMeters', AWaypoint.MaxVisibleDistMeters);
    AWaypoint.SafeEdgeMargin01 := Obj.Get('safeEdgeMargin01', AWaypoint.SafeEdgeMargin01);
    AWaypoint.OccludedWallOpacity01 := Obj.Get('occludedWallOpacity01', AWaypoint.OccludedWallOpacity01);
    AWaypoint.AdsCenterFadeConeDeg := Obj.Get('adsCenterFadeConeDeg', AWaypoint.AdsCenterFadeConeDeg);
    AWaypoint.ClampOffscreenToEdge := Obj.Get('clampOffscreenToEdge', AWaypoint.ClampOffscreenToEdge);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TWorldWaypointHelper.GenerateMarkdownReport(
  const AWaypoint: TCastleWorldWaypoint): String;
var
  SL: TStringList;
  P: TWaypointHudProjection;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Diegetic 3D World Waypoint & Offscreen HUD Clamping Report');
    SL.Add('');
    if AWaypoint = nil then
    begin
      SL.Add('_No `TCastleWorldWaypoint` found in the active design._');
      Exit(SL.Text);
    end;
    P := AWaypoint.LastProjection;
    SL.Add('- **Waypoint**: `' + AWaypoint.Name + '` ("' + AWaypoint.LabelCaption + '")');
    SL.Add('- **Preset / State**: `' + WaypointPresetToString(AWaypoint.Preset) +
      '` / `' + WaypointStateToString(P.State) + '`');
    SL.Add(FormatDot('- **Screen UV / Distance**: `(%.3f, %.3f)` at `%.1f m` (BehindCam=`%s`, WallOccluded=`%s`)',
      [P.ScreenUv.X, P.ScreenUv.Y, P.DistanceMeters,
       BoolToStr(P.IsBehindCamera, True), BoolToStr(P.IsOccludedByWall, True)]));
    SL.Add(FormatDot('- **Icon Scale / Opacity**: `%.2fx` / `%.0f%%` (Edge Arrow `%.1f deg`)',
      [P.IconScale, P.IconOpacity01 * 100.0, RadToDeg(P.EdgeArrowAngleRad)]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
