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

{ Tactical stealth light-gem meter with multi-torch WorldRay shadow occlusion,
  inverse-square + spot cone falloff, guard-to-player backlight silhouette
  detection, and crouch/stillness concealment multipliers (Phase 402). }
unit CastleStealthLightGem;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset stealth visibility calibration profiles. }
  TStealthLightGemPreset = (
    slpMasterThiefShadowCloak,
    slpNightOpsGoggleCalib,
    slpDaylightGhillieCamouflage
  );

  { Registered point or spot light source evaluated by the light-gem sensor. }
  TStealthTorchEmitter = record
    Name: String;
    WorldPos: TVector3;
    Intensity: Single;
    RadiusMeters: Single;
    SpotDir: TVector3;
    SpotHalfConeDeg: Single;
  end;

  { Per-frame stealth visibility evaluation result. }
  TStealthLightGemSample = record
    DirectIllumination01: Single;
    BacklightSilhouette01: Single;
    StanceConcealmentScale: Single;
    FinalVisibilityGem01: Single;
    VisibleTorchCount: Integer;
    ShadowedTorchCount: Integer;
    GuardSightlineClear: Boolean;
  end;

  { Tactical stealth light-gem visibility sensor and preview transform. }
  TCastleStealthLightGem = class(TCastleTransform)
  private
    FPreset: TStealthLightGemPreset;
    FAmbientMoonlightFloor01: Single;
    FCrouchConcealmentMultiplier: Single;
    FStillnessConcealmentMultiplier: Single;
    FBacklightSilhouetteGain: Single;
    FBacklightAlignmentConeDeg: Single;
    FAlertThreshold01: Single;
    FShowPreview: Boolean;
    FTorches: array of TStealthTorchEmitter;
    FLastSample: TStealthLightGemSample;
    FPreviewRoot: TCastleTransform;
    FPreviewGemScene: TCastleScene;
    procedure SetPreset(const AValue: TStealthLightGemPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TStealthLightGemPreset);
    procedure ClearTorches;
    function AddPointTorch(const AName: String; const AWorldPos: TVector3;
      const AIntensity, ARadiusMeters: Single): Integer;
    function AddSpotTorch(const AName: String;
      const AWorldPos, ASpotDir: TVector3;
      const AIntensity, ARadiusMeters, ASpotHalfConeDeg: Single): Integer;
    function TorchCount: Integer;
    function GetTorch(const AIndex: Integer): TStealthTorchEmitter;

    { Evaluate direct WorldRay-shadowed torch light, guard-sightline backlight
      silhouette contrast, and stance concealment at APlayerTorsoWorld. }
    function EvaluateLightGem(
      const AWorldRoot: TCastleAbstractRootTransform;
      const APlayerTorsoWorld, AGuardEyeWorld: TVector3;
      const AIsCrouching, AIsStill: Boolean): TStealthLightGemSample;

    procedure RebuildPreview;
    procedure ClearPreview;
    function LightGemSummaryBadge: String;

    property LastSample: TStealthLightGemSample read FLastSample;
  published
    property Preset: TStealthLightGemPreset
      read FPreset write SetPreset default slpMasterThiefShadowCloak;
    property AmbientMoonlightFloor01: Single
      read FAmbientMoonlightFloor01 write FAmbientMoonlightFloor01;
    property CrouchConcealmentMultiplier: Single
      read FCrouchConcealmentMultiplier write FCrouchConcealmentMultiplier;
    property StillnessConcealmentMultiplier: Single
      read FStillnessConcealmentMultiplier write FStillnessConcealmentMultiplier;
    property BacklightSilhouetteGain: Single
      read FBacklightSilhouetteGain write FBacklightSilhouetteGain;
    property BacklightAlignmentConeDeg: Single
      read FBacklightAlignmentConeDeg write FBacklightAlignmentConeDeg;
    property AlertThreshold01: Single
      read FAlertThreshold01 write FAlertThreshold01;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function StealthLightGemPresetToString(const APreset: TStealthLightGemPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function StealthLightGemPresetToString(const APreset: TStealthLightGemPreset): String;
begin
  case APreset of
    slpMasterThiefShadowCloak:    Result := 'MasterThiefShadowCloak';
    slpNightOpsGoggleCalib:       Result := 'NightOpsGoggleCalib';
    slpDaylightGhillieCamouflage: Result := 'DaylightGhillieCamouflage';
  end;
end;

function SmoothFalloff01(const X: Single): Single;
var
  T: Single;
begin
  T := Clamped(X, 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

constructor TCastleStealthLightGem.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FLastSample := Default(TStealthLightGemSample);
  ApplyPreset(slpMasterThiefShadowCloak);
end;

destructor TCastleStealthLightGem.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleStealthLightGem.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'AmbientMoonlightFloor01', 'CrouchConcealmentMultiplier',
       'StillnessConcealmentMultiplier', 'BacklightSilhouetteGain',
       'BacklightAlignmentConeDeg', 'AlertThreshold01', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleStealthLightGem.SetPreset(const AValue: TStealthLightGemPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleStealthLightGem.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleStealthLightGem.ApplyPreset(const APreset: TStealthLightGemPreset);
begin
  FPreset := APreset;
  case APreset of
    slpMasterThiefShadowCloak:
      begin
        FAmbientMoonlightFloor01 := 0.04;
        FCrouchConcealmentMultiplier := 0.62;
        FStillnessConcealmentMultiplier := 0.72;
        FBacklightSilhouetteGain := 0.88;
        FBacklightAlignmentConeDeg := 26.0;
        FAlertThreshold01 := 0.55;
      end;
    slpNightOpsGoggleCalib:
      begin
        FAmbientMoonlightFloor01 := 0.14;
        FCrouchConcealmentMultiplier := 0.70;
        FStillnessConcealmentMultiplier := 0.85;
        FBacklightSilhouetteGain := 0.95;
        FBacklightAlignmentConeDeg := 32.0;
        FAlertThreshold01 := 0.45;
      end;
    slpDaylightGhillieCamouflage:
      begin
        FAmbientMoonlightFloor01 := 0.18;
        FCrouchConcealmentMultiplier := 0.48;
        FStillnessConcealmentMultiplier := 0.42;
        FBacklightSilhouetteGain := 0.60;
        FBacklightAlignmentConeDeg := 22.0;
        FAlertThreshold01 := 0.60;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleStealthLightGem.ClearTorches;
begin
  SetLength(FTorches, 0);
end;

function TCastleStealthLightGem.AddPointTorch(const AName: String;
  const AWorldPos: TVector3; const AIntensity, ARadiusMeters: Single): Integer;
begin
  Result := AddSpotTorch(AName, AWorldPos, Vector3(0.0, -1.0, 0.0),
    AIntensity, ARadiusMeters, 180.0);
end;

function TCastleStealthLightGem.AddSpotTorch(const AName: String;
  const AWorldPos, ASpotDir: TVector3;
  const AIntensity, ARadiusMeters, ASpotHalfConeDeg: Single): Integer;
var
  N: Integer;
begin
  N := Length(FTorches);
  SetLength(FTorches, N + 1);
  FTorches[N].Name := AName;
  FTorches[N].WorldPos := AWorldPos;
  FTorches[N].Intensity := Max(0.0, AIntensity);
  FTorches[N].RadiusMeters := Max(0.25, ARadiusMeters);
  if ASpotDir.LengthSqr > 1e-6 then
    FTorches[N].SpotDir := ASpotDir.Normalize
  else
    FTorches[N].SpotDir := Vector3(0.0, -1.0, 0.0);
  FTorches[N].SpotHalfConeDeg := Clamped(ASpotHalfConeDeg, 2.0, 180.0);
  Result := N;
end;

function TCastleStealthLightGem.TorchCount: Integer;
begin
  Result := Length(FTorches);
end;

function TCastleStealthLightGem.GetTorch(const AIndex: Integer): TStealthTorchEmitter;
begin
  if (AIndex >= 0) and (AIndex < Length(FTorches)) then
    Result := FTorches[AIndex]
  else
    Result := Default(TStealthTorchEmitter);
end;

function TCastleStealthLightGem.EvaluateLightGem(
  const AWorldRoot: TCastleAbstractRootTransform;
  const APlayerTorsoWorld, AGuardEyeWorld: TVector3;
  const AIsCrouching, AIsStill: Boolean): TStealthLightGemSample;
var
  ActiveRoot: TCastleAbstractRootTransform;

  function SegmentBlockedBySolid(const AStart, ATarget: TVector3): Boolean;
  var
    SegVec, Dir: TVector3;
    SegLen, HitDist: Single;
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
  begin
    Result := False;
    if ActiveRoot = nil then Exit;
    SegVec := ATarget - AStart;
    SegLen := SegVec.Length;
    if SegLen <= 0.08 then Exit;
    Dir := SegVec / SegLen;
    RH := ActiveRoot.WorldRay(AStart, Dir);
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        HitDist := PointsDistance(AStart, RH[K].Point);
        if (HitDist > 0.05) and (HitDist < SegLen - 0.05) then
          Exit(True);
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  I: Integer;
  T: TStealthTorchEmitter;
  ToLight, GuardToPlayer, GuardToTorch: TVector3;
  Dist, Rad, Atten, AngDeg, SpotWeight, DirectSum: Single;
  G2PLen, G2TLen, CosAlign, AlignDeg, ConeLim, BackPeak, TorchVisibleToGuard: Single;
begin
  Result := Default(TStealthLightGemSample);
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  Result.GuardSightlineClear := not SegmentBlockedBySolid(AGuardEyeWorld, APlayerTorsoWorld);

  DirectSum := Clamped(FAmbientMoonlightFloor01, 0.0, 1.0);
  BackPeak := 0.0;

  GuardToPlayer := APlayerTorsoWorld - AGuardEyeWorld;
  G2PLen := GuardToPlayer.Length;

  for I := 0 to High(FTorches) do
  begin
    T := FTorches[I];
    ToLight := T.WorldPos - APlayerTorsoWorld;
    Dist := ToLight.Length;
    Rad := Max(0.25, T.RadiusMeters);

    { 1. Direct illumination onto player (subject to WorldRay shadow-casting pillars/walls) }
    if (Dist < Rad) and (T.Intensity > 0.001) then
    begin
      SpotWeight := 1.0;
      if (T.SpotHalfConeDeg < 179.5) and (Dist > 0.01) then
      begin
        AngDeg := RadToDeg(ArcCos(Clamped(
          TVector3.DotProduct((-ToLight) / Dist, T.SpotDir), -1.0, 1.0)));
        if AngDeg >= T.SpotHalfConeDeg then
          SpotWeight := 0.0
        else
          SpotWeight := 1.0 - SmoothFalloff01(AngDeg / T.SpotHalfConeDeg);
      end;

      if SpotWeight > 0.001 then
      begin
        if SegmentBlockedBySolid(APlayerTorsoWorld, T.WorldPos) then
          Inc(Result.ShadowedTorchCount)
        else
        begin
          Inc(Result.VisibleTorchCount);
          Atten := Sqr(Clamped(1.0 - (Dist / Rad), 0.0, 1.0)) /
            (1.0 + 0.12 * Dist * Dist);
          DirectSum := DirectSum + T.Intensity * SpotWeight * Atten;
        end;
      end;
    end;

    { 2. Backlight silhouette contrast: even if the player stands inside a dark
         pillar shadow, if Guard->Player sightline is clear AND a bright unoccluded
         torch/window lies BEHIND the player along that sightline, the player''s dark
         outline silhouettes sharply against the bright background! }
    if Result.GuardSightlineClear and (FBacklightSilhouetteGain > 0.001) and
       (G2PLen > 0.25) and (T.Intensity > 0.05) then
    begin
      GuardToTorch := T.WorldPos - AGuardEyeWorld;
      G2TLen := GuardToTorch.Length;
      if G2TLen > G2PLen + 0.35 then
      begin
        CosAlign := Clamped(
          TVector3.DotProduct(GuardToPlayer / G2PLen, GuardToTorch / G2TLen),
          -1.0, 1.0);
        AlignDeg := RadToDeg(ArcCos(CosAlign));
        ConeLim := Max(3.0, FBacklightAlignmentConeDeg);
        if (AlignDeg < ConeLim) and
           (not SegmentBlockedBySolid(AGuardEyeWorld, T.WorldPos)) then
        begin
          TorchVisibleToGuard := Clamped(T.Intensity / (1.0 + 0.02 * G2TLen), 0.0, 1.25);
          BackPeak := Max(BackPeak,
            Clamped(FBacklightSilhouetteGain * TorchVisibleToGuard *
              (1.0 - SmoothFalloff01(AlignDeg / ConeLim)), 0.0, 1.0));
        end;
      end;
    end;
  end;

  Result.DirectIllumination01 := Clamped(DirectSum, 0.0, 1.0);
  Result.BacklightSilhouette01 := Clamped(BackPeak, 0.0, 1.0);

  Result.StanceConcealmentScale := 1.0;
  if AIsCrouching then
    Result.StanceConcealmentScale := Result.StanceConcealmentScale *
      Clamped(FCrouchConcealmentMultiplier, 0.1, 1.5);
  if AIsStill then
    Result.StanceConcealmentScale := Result.StanceConcealmentScale *
      Clamped(FStillnessConcealmentMultiplier, 0.1, 1.5);

  { Backlight silhouette exposes a standing/crouching outline even in deep shadow }
  Result.FinalVisibilityGem01 := Clamped(
    Max(Result.DirectIllumination01 * Result.StanceConcealmentScale,
        Result.BacklightSilhouette01 * (0.55 + 0.45 * Result.StanceConcealmentScale)),
    0.0, 1.0);

  FLastSample := Result;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleStealthLightGem.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewGemScene := nil;
  end;
end;

procedure TCastleStealthLightGem.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  R: Single;
  Pts: array[0..11] of TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  R := 0.45;
  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'StealthLightGemPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewGemScene := TCastleScene.Create(FPreviewRoot);
  FPreviewGemScene.SetTransient;
  FPreviewGemScene.Name := 'StealthLightGemOctahedron';
  FPreviewGemScene.Pickable := False;
  FPreviewGemScene.Collides := False;
  FPreviewRoot.Add(FPreviewGemScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FLastSample.FinalVisibilityGem01 >= FAlertThreshold01 then
    MatNode.EmissiveColor := Vector3(1.0, 0.78, 0.18)
  else
    MatNode.EmissiveColor := Vector3(0.18, 0.55, 0.95);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  CoordNode := TCoordinateNode.Create;
  Pts[0] := Vector3(0, R * 1.4, 0);
  Pts[1] := Vector3(R, 0, 0);
  Pts[2] := Vector3(0, 0, R);
  Pts[3] := Vector3(-R, 0, 0);
  Pts[4] := Vector3(0, 0, -R);
  Pts[5] := Vector3(R, 0, 0);
  Pts[6] := Vector3(0, -R * 1.4, 0);
  Pts[7] := Vector3(-R, 0, 0);
  Pts[8] := Vector3(0, R * 1.4, 0);
  Pts[9] := Vector3(0, 0, R);
  Pts[10] := Vector3(0, -R * 1.4, 0);
  Pts[11] := Vector3(0, 0, -R);
  CoordNode.SetPoint(Pts);

  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([12]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewGemScene.Load(RootNode, True);
end;

function TCastleStealthLightGem.LightGemSummaryBadge: String;
begin
  Result := Format('[LightGem:%d%% Torches=%d Shadow=%d]', [
    Round(FLastSample.FinalVisibilityGem01 * 100.0),
    Length(FTorches),
    FLastSample.ShadowedTorchCount]);
end;

initialization
  RegisterSerializableComponent(TCastleStealthLightGem, 'Stealth Light-Gem Sensor');

end.
