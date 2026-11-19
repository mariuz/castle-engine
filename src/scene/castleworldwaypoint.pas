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

{ Diegetic 3D world-space waypoint & objective ping component with perspective
  viewport projection, behind-camera hemisphere-safe offscreen edge clamping,
  ADS center-reticle declutter fade, and WorldRay X-Ray wall occlusion state
  (Phase 390). }
unit CastleWorldWaypoint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors;

type
  { Preset HUD & 3D beacon styles for world-space waypoints. }
  TWaypointPreset = (
    wwpQuestObjectiveDiamond,
    wwpSquadPingTactical,
    wwpLootRarityBeacon
  );

  { Visibility & clamping classification in camera screen space. }
  TWaypointScreenState = (
    wssOnScreenClear,
    wssOnScreenOccludedWall,
    wssOffScreenClampedEdge,
    wssCulledByRange
  );

  { Computed 2D HUD placement and visual state for a given camera view. }
  TWaypointHudProjection = record
    State: TWaypointScreenState;
    ScreenUv: TVector2;
    DistanceMeters: Single;
    IsBehindCamera: Boolean;
    IsOccludedByWall: Boolean;
    EdgeArrowAngleRad: Single;
    IconScale: Single;
    IconOpacity01: Single;
  end;

  { 3D world-space objective/ping marker projecting cleanly to 2D HUD coordinates
    with offscreen safe-area clamping and WorldRay occlusion detection. }
  TCastleWorldWaypoint = class(TCastleTransform)
  private
    FPreset: TWaypointPreset;
    FLabelCaption: String;
    FVerticalAnchorOffsetY: Single;
    FMinVisibleDistMeters: Single;
    FMaxVisibleDistMeters: Single;
    FSafeEdgeMargin01: Single;
    FOccludedWallOpacity01: Single;
    FAdsCenterFadeConeDeg: Single;
    FAdsMinCenterOpacity01: Single;
    FClampOffscreenToEdge: Boolean;
    FShowPreview: Boolean;
    FLastProjection: TWaypointHudProjection;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TWaypointPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TWaypointPreset);

    { Project the 3D waypoint into normalized [0..1]^2 screen coordinates for
      camera (ACamPos, ACamDir, ACamUp), testing WorldRay wall occlusion and
      clamping off-frustum / behind-camera targets to the safe margin border. }
    function EvaluateForCamera(const AWorldRoot: TCastleAbstractRootTransform;
      const ACamPos, ACamDir, ACamUp: TVector3;
      const AFovYDeg, AAspectRatio: Single;
      const AIsAimingDownSights: Boolean): TWaypointHudProjection;

    procedure RebuildPreview;
    procedure ClearPreview;
    function WaypointSummaryBadge: String;

    property LastProjection: TWaypointHudProjection read FLastProjection;
  published
    property Preset: TWaypointPreset
      read FPreset write SetPreset default wwpQuestObjectiveDiamond;
    property LabelCaption: String
      read FLabelCaption write FLabelCaption;
    property VerticalAnchorOffsetY: Single
      read FVerticalAnchorOffsetY write FVerticalAnchorOffsetY;
    property MinVisibleDistMeters: Single
      read FMinVisibleDistMeters write FMinVisibleDistMeters;
    property MaxVisibleDistMeters: Single
      read FMaxVisibleDistMeters write FMaxVisibleDistMeters;
    property SafeEdgeMargin01: Single
      read FSafeEdgeMargin01 write FSafeEdgeMargin01;
    property OccludedWallOpacity01: Single
      read FOccludedWallOpacity01 write FOccludedWallOpacity01;
    property AdsCenterFadeConeDeg: Single
      read FAdsCenterFadeConeDeg write FAdsCenterFadeConeDeg;
    property AdsMinCenterOpacity01: Single
      read FAdsMinCenterOpacity01 write FAdsMinCenterOpacity01;
    property ClampOffscreenToEdge: Boolean
      read FClampOffscreenToEdge write FClampOffscreenToEdge default True;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function WaypointPresetToString(const APreset: TWaypointPreset): String;
function WaypointStateToString(const AState: TWaypointScreenState): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function WaypointPresetToString(const APreset: TWaypointPreset): String;
begin
  case APreset of
    wwpQuestObjectiveDiamond: Result := 'QuestObjectiveDiamond';
    wwpSquadPingTactical:     Result := 'SquadPingTactical';
    wwpLootRarityBeacon:      Result := 'LootRarityBeacon';
  end;
end;

function WaypointStateToString(const AState: TWaypointScreenState): String;
begin
  case AState of
    wssOnScreenClear:        Result := 'OnScreenClear';
    wssOnScreenOccludedWall: Result := 'OnScreenOccludedWall';
    wssOffScreenClampedEdge: Result := 'OffScreenClampedEdge';
    wssCulledByRange:        Result := 'CulledByRange';
  end;
end;

{ TCastleWorldWaypoint ------------------------------------------------------- }

constructor TCastleWorldWaypoint.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLabelCaption := 'Main Objective';
  FClampOffscreenToEdge := True;
  FShowPreview := True;
  FLastProjection := Default(TWaypointHudProjection);
  FLastProjection.ScreenUv := Vector2(0.5, 0.5);
  ApplyPreset(wwpQuestObjectiveDiamond);
end;

destructor TCastleWorldWaypoint.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleWorldWaypoint.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'LabelCaption', 'VerticalAnchorOffsetY',
       'MinVisibleDistMeters', 'MaxVisibleDistMeters',
       'SafeEdgeMargin01', 'OccludedWallOpacity01',
       'AdsCenterFadeConeDeg', 'AdsMinCenterOpacity01',
       'ClampOffscreenToEdge', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleWorldWaypoint.SetPreset(const AValue: TWaypointPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleWorldWaypoint.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleWorldWaypoint.ApplyPreset(const APreset: TWaypointPreset);
begin
  FPreset := APreset;
  case APreset of
    wwpQuestObjectiveDiamond:
      begin
        FVerticalAnchorOffsetY := 1.85;
        FMinVisibleDistMeters := 1.0;
        FMaxVisibleDistMeters := 500.0;
        FSafeEdgeMargin01 := 0.06;
        FOccludedWallOpacity01 := 0.45;
        FAdsCenterFadeConeDeg := 6.0;
        FAdsMinCenterOpacity01 := 0.18;
        FClampOffscreenToEdge := True;
      end;
    wwpSquadPingTactical:
      begin
        FVerticalAnchorOffsetY := 1.20;
        FMinVisibleDistMeters := 0.5;
        FMaxVisibleDistMeters := 250.0;
        FSafeEdgeMargin01 := 0.05;
        FOccludedWallOpacity01 := 0.55;
        FAdsCenterFadeConeDeg := 8.0;
        FAdsMinCenterOpacity01 := 0.12;
        FClampOffscreenToEdge := True;
      end;
    wwpLootRarityBeacon:
      begin
        FVerticalAnchorOffsetY := 0.90;
        FMinVisibleDistMeters := 0.5;
        FMaxVisibleDistMeters := 45.0;
        FSafeEdgeMargin01 := 0.08;
        FOccludedWallOpacity01 := 0.25;
        FAdsCenterFadeConeDeg := 5.0;
        FAdsMinCenterOpacity01 := 0.20;
        FClampOffscreenToEdge := False;
      end;
  end;
  RebuildPreview;
end;

function TCastleWorldWaypoint.EvaluateForCamera(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ACamPos, ACamDir, ACamUp: TVector3;
  const AFovYDeg, AAspectRatio: Single;
  const AIsAimingDownSights: Boolean): TWaypointHudProjection;
var
  WT: TMatrix4;
  AnchorPos, Delta, Fwd, RightAxis, UpAxis, RayDir, UpFallback: TVector3;
  Dist, XV, YV, ZV, TanHalfY, TanHalfX, NX, NY, Margin, BoundNdc: Single;
  DirX, DirY, MaxComp, ScaleClamp, AngleFromCenterDeg, AdsFactor, HitD: Single;
  InsideSafeBox: Boolean;
  RH: TRayCollision;
  K: Integer;
  HitItem: TCastleTransform;
begin
  Result := Default(TWaypointHudProjection);
  Result.ScreenUv := Vector2(0.5, 0.5);

  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  AnchorPos := WT.MultPoint(Vector3(0.0, FVerticalAnchorOffsetY, 0.0));

  Delta := AnchorPos - ACamPos;
  Dist := Delta.Length;
  Result.DistanceMeters := Dist;

  if (Dist < FMinVisibleDistMeters) or (Dist > FMaxVisibleDistMeters) then
  begin
    Result.State := wssCulledByRange;
    Result.IconScale := 0.0;
    Result.IconOpacity01 := 0.0;
    FLastProjection := Result;
    Exit;
  end;

  if ACamDir.LengthSqr < 1e-8 then
    Fwd := Vector3(0.0, 0.0, -1.0)
  else
    Fwd := ACamDir.Normalize;
  if ACamUp.LengthSqr < 1e-8 then
    UpFallback := Vector3(0.0, 1.0, 0.0)
  else
    UpFallback := ACamUp.Normalize;

  RightAxis := TVector3.CrossProduct(Fwd, UpFallback);
  if RightAxis.LengthSqr < 1e-6 then
    RightAxis := Vector3(1.0, 0.0, 0.0)
  else
    RightAxis := RightAxis.Normalize;
  UpAxis := TVector3.CrossProduct(RightAxis, Fwd).Normalize;

  XV := TVector3.DotProduct(Delta, RightAxis);
  YV := TVector3.DotProduct(Delta, UpAxis);
  ZV := TVector3.DotProduct(Delta, Fwd);
  Result.IsBehindCamera := ZV <= 0.05;

  TanHalfY := Tan(DegToRad(Clamped(AFovYDeg, 15.0, 150.0)) * 0.5);
  TanHalfX := TanHalfY * Max(0.25, AAspectRatio);
  Margin := Clamped(FSafeEdgeMargin01, 0.01, 0.35);
  BoundNdc := 1.0 - 2.0 * Margin;

  Result.IconScale := Clamped(14.0 / Max(4.0, Dist), 0.55, 1.35);

  InsideSafeBox := False;
  NX := 0.0;
  NY := 0.0;
  if not Result.IsBehindCamera then
  begin
    NX := XV / (ZV * TanHalfX);
    NY := YV / (ZV * TanHalfY);
    InsideSafeBox := (Abs(NX) <= BoundNdc) and (Abs(NY) <= BoundNdc);
  end;

  if InsideSafeBox then
  begin
    Result.ScreenUv := Vector2(0.5 + 0.5 * NX, 0.5 + 0.5 * NY);
    Result.EdgeArrowAngleRad := ArcTan2(NY, NX);

    { WorldRay occlusion check between ACamPos and AnchorPos }
    Result.IsOccludedByWall := False;
    if (AWorldRoot <> nil) and (Dist > 0.2) then
    begin
      RayDir := Delta / Dist;
      RH := AWorldRoot.WorldRay(ACamPos, RayDir);
      try
        if RH <> nil then
          for K := 0 to RH.Count - 1 do
          begin
            HitItem := RH[K].Item;
            if (HitItem = nil) or (HitItem = AWorldRoot) or (HitItem = Self) then
              Continue;
            if csTransient in HitItem.ComponentStyle then
              Continue;
            HitD := PointsDistance(ACamPos, RH[K].Point);
            if (HitD > 0.08) and (HitD < Dist - 0.18) then
            begin
              Result.IsOccludedByWall := True;
              Break;
            end;
          end;
      finally
        FreeAndNil(RH);
      end;
    end;

    if Result.IsOccludedByWall then
    begin
      Result.State := wssOnScreenOccludedWall;
      Result.IconOpacity01 := Clamped(FOccludedWallOpacity01, 0.05, 1.0);
    end else
    begin
      Result.State := wssOnScreenClear;
      Result.IconOpacity01 := 1.0;
    end;

    { ADS center-reticle declutter fade }
    if AIsAimingDownSights and (FAdsCenterFadeConeDeg > 0.1) then
    begin
      AngleFromCenterDeg := RadToDeg(ArcCos(Clamped(ZV / Max(0.001, Dist), -1.0, 1.0)));
      if AngleFromCenterDeg < FAdsCenterFadeConeDeg then
      begin
        AdsFactor := Lerp(AngleFromCenterDeg / FAdsCenterFadeConeDeg,
          Clamped(FAdsMinCenterOpacity01, 0.0, 1.0), 1.0);
        Result.IconOpacity01 := Result.IconOpacity01 * AdsFactor;
      end;
    end;
  end else
  begin
    if not FClampOffscreenToEdge then
    begin
      Result.State := wssCulledByRange;
      Result.IconOpacity01 := 0.0;
      FLastProjection := Result;
      Exit;
    end;

    { Hemisphere-safe view-plane XY direction: never flips sign when ZV < 0! }
    DirX := XV / TanHalfX;
    DirY := YV / TanHalfY;
    if (Abs(DirX) < 1e-5) and (Abs(DirY) < 1e-5) then
    begin
      DirX := 0.0;
      DirY := -1.0;
    end;
    MaxComp := Max(Abs(DirX), Abs(DirY));
    ScaleClamp := BoundNdc / Max(1e-5, MaxComp);
    NX := DirX * ScaleClamp;
    NY := DirY * ScaleClamp;
    Result.State := wssOffScreenClampedEdge;
    Result.ScreenUv := Vector2(0.5 + 0.5 * NX, 0.5 + 0.5 * NY);
    Result.EdgeArrowAngleRad := ArcTan2(DirY, DirX);
    Result.IconOpacity01 := 0.88;
  end;

  FLastProjection := Result;
end;

procedure TCastleWorldWaypoint.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
  end;
end;

procedure TCastleWorldWaypoint.RebuildPreview;
var
  DiamondBox, PillarStem: TCastleBox;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'WorldWaypointPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  DiamondBox := TCastleBox.Create(FPreviewRoot);
  DiamondBox.SetTransient;
  DiamondBox.Pickable := False;
  DiamondBox.Collides := False;
  DiamondBox.Size := Vector3(0.42, 0.42, 0.42);
  DiamondBox.Translation := Vector3(0.0, FVerticalAnchorOffsetY, 0.0);
  DiamondBox.Rotation := Vector4(0.0, 0.0, 1.0, Pi * 0.25);
  case FPreset of
    wwpQuestObjectiveDiamond: DiamondBox.Color := Vector4(1.0, 0.82, 0.22, 1.0);
    wwpSquadPingTactical:     DiamondBox.Color := Vector4(0.24, 0.86, 1.0, 1.0);
    wwpLootRarityBeacon:      DiamondBox.Color := Vector4(0.78, 0.34, 1.0, 1.0);
  end;
  FPreviewRoot.Add(DiamondBox);

  PillarStem := TCastleBox.Create(FPreviewRoot);
  PillarStem.SetTransient;
  PillarStem.Pickable := False;
  PillarStem.Collides := False;
  PillarStem.Size := Vector3(0.06, Max(0.2, FVerticalAnchorOffsetY), 0.06);
  PillarStem.Translation := Vector3(0.0, FVerticalAnchorOffsetY * 0.5, 0.0);
  PillarStem.Color := DiamondBox.Color;
  FPreviewRoot.Add(PillarStem);

  Add(FPreviewRoot);
end;

function TCastleWorldWaypoint.WaypointSummaryBadge: String;
begin
  Result := FormatDot('[Waypoint:%s %.1fm Op=%.0f%%]', [
    WaypointStateToString(FLastProjection.State),
    FLastProjection.DistanceMeters,
    FLastProjection.IconOpacity01 * 100.0]);
end;

initialization
  RegisterSerializableComponent(TCastleWorldWaypoint, 'Diegetic 3D World Waypoint');

end.
