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

{ Procedural torch, sconce, campfire & storm-lantern combustion solver with
  1800K..2900K Planckian blackbody RGB shift, dancing shadow-origin jitter,
  wind-draft flame tilt, gust blowout/re-ignition, and WorldRay wall/ceiling
  soot darkening (Phase 404). }
unit CastleFlameFlicker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset combustion & wind-shielding profiles. }
  TFlameFlickerPreset = (
    ffpDungeonWallSconceTorch,
    ffpHearthCampfireBrazier,
    ffpStormLanternShielded
  );

  { Instantaneous combustion, blackbody color, wind tilt & blowout state. }
  TFlameFlickerSample = record
    IsLit: Boolean;
    ExtinguishedThisStep: Boolean;
    CurrentKelvin: Single;
    BlackbodyRgb: TVector3;
    IntensityMultiplier: Single;
    FlameTipLocalOffset: TVector3;
    ShadowOriginLocalOffset: TVector3;
    SmokePuffAlpha01: Single;
  end;

  { Nearby masonry wall & ceiling soot deposition evaluation via WorldRay. }
  TWallSootProbeResult = record
    CeilingHit: Boolean;
    CeilingDistMeters: Single;
    CeilingSootDarkening01: Single;
    WallHit: Boolean;
    NearestWallDistMeters: Single;
    WallSootDarkening01: Single;
    SootSurfaceCount: Integer;
  end;

  { Procedural torch & campfire blackbody combustion rig component. }
  TCastleFlameFlickerRig = class(TCastleTransform)
  private
    FPreset: TFlameFlickerPreset;
    FIsLit: Boolean;
    FBaseKelvin: Single;
    FKelvinFlickerSpan: Single;
    FBaseIntensity: Single;
    FFlickerAmplitude01: Single;
    FFlameHeightMeters: Single;
    FShadowJitterRadiusMeters: Single;
    FWindTiltCompliance: Single;
    FBlowoutWindSpeedMps: Single;
    FMaxWallSootRadiusMeters: Single;
    FMaxCeilingSootHeightMeters: Single;
    FShowPreview: Boolean;
    FPhaseSec: Single;
    FSmokePuffAlpha01: Single;
    FLastSample: TFlameFlickerSample;
    FLastSoot: TWallSootProbeResult;
    FPreviewRoot: TCastleTransform;
    FPreviewFlameScene: TCastleScene;
    procedure SetPreset(const AValue: TFlameFlickerPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TFlameFlickerPreset);
    procedure ReigniteFlame;
    procedure ExtinguishFlame;

    { Convert color temperature [1200K .. 6500K] to normalized Planckian RGB. }
    class function KelvinToBlackbodyRgb(const AKelvin: Single): TVector3;

    { Advance multi-octave combustion turbulence, blackbody shift, wind tilt,
      and gust blowout extinguishing. }
    function StepFlameCombustion(const ADtSec: Single;
      const AWindVelocityMps: TVector3): TFlameFlickerSample;

    { Cast upward +Y and 4 cardinal horizontal WorldRay probes to compute
      nearby wall and ceiling soot darkening. }
    function ProbeWallAndCeilingSoot(
      const AWorldRoot: TCastleAbstractRootTransform): TWallSootProbeResult;

    procedure RebuildPreview;
    procedure ClearPreview;
    function FlameSummaryBadge: String;

    property IsLit: Boolean read FIsLit;
    property LastSample: TFlameFlickerSample read FLastSample;
    property LastSoot: TWallSootProbeResult read FLastSoot;
  published
    property Preset: TFlameFlickerPreset
      read FPreset write SetPreset default ffpDungeonWallSconceTorch;
    property BaseKelvin: Single read FBaseKelvin write FBaseKelvin;
    property KelvinFlickerSpan: Single read FKelvinFlickerSpan write FKelvinFlickerSpan;
    property BaseIntensity: Single read FBaseIntensity write FBaseIntensity;
    property FlickerAmplitude01: Single read FFlickerAmplitude01 write FFlickerAmplitude01;
    property FlameHeightMeters: Single read FFlameHeightMeters write FFlameHeightMeters;
    property ShadowJitterRadiusMeters: Single
      read FShadowJitterRadiusMeters write FShadowJitterRadiusMeters;
    property WindTiltCompliance: Single read FWindTiltCompliance write FWindTiltCompliance;
    property BlowoutWindSpeedMps: Single read FBlowoutWindSpeedMps write FBlowoutWindSpeedMps;
    property MaxWallSootRadiusMeters: Single
      read FMaxWallSootRadiusMeters write FMaxWallSootRadiusMeters;
    property MaxCeilingSootHeightMeters: Single
      read FMaxCeilingSootHeightMeters write FMaxCeilingSootHeightMeters;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function FlameFlickerPresetToString(const APreset: TFlameFlickerPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function FlameFlickerPresetToString(const APreset: TFlameFlickerPreset): String;
begin
  case APreset of
    ffpDungeonWallSconceTorch: Result := 'DungeonWallSconceTorch';
    ffpHearthCampfireBrazier:  Result := 'HearthCampfireBrazier';
    ffpStormLanternShielded:   Result := 'StormLanternShielded';
  end;
end;

class function TCastleFlameFlickerRig.KelvinToBlackbodyRgb(
  const AKelvin: Single): TVector3;
var
  T, R, G, B: Single;
begin
  { Tanner Helland Planckian locus approximation (valid 1200K .. 6500K) }
  T := Clamped(AKelvin, 1200.0, 6500.0) * 0.01;
  R := 1.0;
  G := Clamped((99.4708025861 * Ln(Max(1.01, T)) - 161.1195681661) / 255.0, 0.0, 1.0);
  if T <= 19.0 then
    B := 0.0
  else
    B := Clamped((138.5177312231 * Ln(Max(1.01, T - 10.0)) - 305.0447927307) / 255.0,
      0.0, 1.0);
  Result := Vector3(R, G, B);
end;

constructor TCastleFlameFlickerRig.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FIsLit := True;
  FPhaseSec := 0.0;
  FSmokePuffAlpha01 := 0.0;
  FLastSample := Default(TFlameFlickerSample);
  FLastSoot := Default(TWallSootProbeResult);
  ApplyPreset(ffpDungeonWallSconceTorch);
end;

destructor TCastleFlameFlickerRig.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleFlameFlickerRig.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'BaseKelvin', 'KelvinFlickerSpan', 'BaseIntensity',
       'FlickerAmplitude01', 'FlameHeightMeters', 'ShadowJitterRadiusMeters',
       'WindTiltCompliance', 'BlowoutWindSpeedMps', 'MaxWallSootRadiusMeters',
       'MaxCeilingSootHeightMeters', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleFlameFlickerRig.SetPreset(const AValue: TFlameFlickerPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleFlameFlickerRig.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleFlameFlickerRig.ApplyPreset(const APreset: TFlameFlickerPreset);
begin
  FPreset := APreset;
  FIsLit := True;
  FSmokePuffAlpha01 := 0.0;
  case APreset of
    ffpDungeonWallSconceTorch:
      begin
        FBaseKelvin := 2050.0;
        FKelvinFlickerSpan := 320.0;
        FBaseIntensity := 1.8;
        FFlickerAmplitude01 := 0.28;
        FFlameHeightMeters := 0.36;
        FShadowJitterRadiusMeters := 0.055;
        FWindTiltCompliance := 0.045;
        FBlowoutWindSpeedMps := 9.5;
        FMaxWallSootRadiusMeters := 1.35;
        FMaxCeilingSootHeightMeters := 2.60;
      end;
    ffpHearthCampfireBrazier:
      begin
        FBaseKelvin := 2350.0;
        FKelvinFlickerSpan := 420.0;
        FBaseIntensity := 3.4;
        FFlickerAmplitude01 := 0.34;
        FFlameHeightMeters := 0.72;
        FShadowJitterRadiusMeters := 0.095;
        FWindTiltCompliance := 0.055;
        FBlowoutWindSpeedMps := 19.0;
        FMaxWallSootRadiusMeters := 1.80;
        FMaxCeilingSootHeightMeters := 3.50;
      end;
    ffpStormLanternShielded:
      begin
        FBaseKelvin := 2750.0;
        FKelvinFlickerSpan := 110.0;
        FBaseIntensity := 1.5;
        FFlickerAmplitude01 := 0.07;
        FFlameHeightMeters := 0.14;
        FShadowJitterRadiusMeters := 0.012;
        FWindTiltCompliance := 0.008;
        FBlowoutWindSpeedMps := 38.0;
        FMaxWallSootRadiusMeters := 0.65;
        FMaxCeilingSootHeightMeters := 1.40;
      end;
  end;
  StepFlameCombustion(0.01, TVector3.Zero);
end;

procedure TCastleFlameFlickerRig.ReigniteFlame;
begin
  FIsLit := True;
  FSmokePuffAlpha01 := 0.0;
  StepFlameCombustion(0.01, TVector3.Zero);
end;

procedure TCastleFlameFlickerRig.ExtinguishFlame;
begin
  FIsLit := False;
  FSmokePuffAlpha01 := 1.0;
  FLastSample.IsLit := False;
  FLastSample.IntensityMultiplier := 0.0;
  FLastSample.CurrentKelvin := 0.0;
  FLastSample.BlackbodyRgb := TVector3.Zero;
  FLastSample.FlameTipLocalOffset := TVector3.Zero;
  FLastSample.ShadowOriginLocalOffset := TVector3.Zero;
  FLastSample.SmokePuffAlpha01 := 1.0;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleFlameFlickerRig.StepFlameCombustion(const ADtSec: Single;
  const AWindVelocityMps: TVector3): TFlameFlickerSample;
var
  WSpeed, Turb, RiseY: Single;
begin
  Result := Default(TFlameFlickerSample);
  if ADtSec > 0.0 then
    FPhaseSec := FPhaseSec + ADtSec;

  WSpeed := AWindVelocityMps.Length;
  if FIsLit and (FBlowoutWindSpeedMps > 0.1) and (WSpeed >= FBlowoutWindSpeedMps) then
  begin
    FIsLit := False;
    FSmokePuffAlpha01 := 1.0;
    Result.ExtinguishedThisStep := True;
  end;

  if not FIsLit then
  begin
    if (not Result.ExtinguishedThisStep) and (ADtSec > 0.0) then
      FSmokePuffAlpha01 := Max(0.0, FSmokePuffAlpha01 - 0.75 * ADtSec);
    Result.IsLit := False;
    Result.SmokePuffAlpha01 := FSmokePuffAlpha01;
    FLastSample := Result;
    if FShowPreview then
      RebuildPreview;
    Exit;
  end;

  Turb := 0.55 * Sin(FPhaseSec * 7.3) +
          0.30 * Sin(FPhaseSec * 17.9 + 1.1) +
          0.15 * Cos(FPhaseSec * 31.4);

  Result.IsLit := True;
  Result.CurrentKelvin := Clamped(
    FBaseKelvin + FKelvinFlickerSpan * Turb, 1200.0, 6500.0);
  Result.BlackbodyRgb := KelvinToBlackbodyRgb(Result.CurrentKelvin);
  Result.IntensityMultiplier := Max(0.05,
    FBaseIntensity * (1.0 + FFlickerAmplitude01 * Turb));

  RiseY := Max(0.05, FFlameHeightMeters) / Sqrt(1.0 + 0.08 * WSpeed * WSpeed);
  Result.FlameTipLocalOffset := Vector3(
    AWindVelocityMps.X * FWindTiltCompliance,
    RiseY,
    AWindVelocityMps.Z * FWindTiltCompliance);

  Result.ShadowOriginLocalOffset := Result.FlameTipLocalOffset * 0.35 +
    Vector3(
      Sin(FPhaseSec * 13.7),
      0.5 * Cos(FPhaseSec * 19.3),
      Cos(FPhaseSec * 11.1)) * FShadowJitterRadiusMeters;
  Result.SmokePuffAlpha01 := 0.0;

  FLastSample := Result;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleFlameFlickerRig.ProbeWallAndCeilingSoot(
  const AWorldRoot: TCastleAbstractRootTransform): TWallSootProbeResult;
var
  ActiveRoot: TCastleAbstractRootTransform;

  function NearestRayDist(const AOrig, ADir: TVector3;
    const AMaxDist: Single; out AHitDist: Single): Boolean;
  var
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
    D: Single;
  begin
    Result := False;
    AHitDist := AMaxDist + 1.0;
    if ActiveRoot = nil then Exit;
    RH := ActiveRoot.WorldRay(AOrig, ADir);
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        D := PointsDistance(AOrig, RH[K].Point);
        if (D >= 0.04) and (D <= AMaxDist) and (D < AHitDist) then
        begin
          AHitDist := D;
          Result := True;
        end;
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

const
  Dirs4: array[0..3] of TVector3 = (
    (X:  1.0; Y: 0.0; Z:  0.0),
    (X: -1.0; Y: 0.0; Z:  0.0),
    (X:  0.0; Y: 0.0; Z:  1.0),
    (X:  0.0; Y: 0.0; Z: -1.0)
  );
var
  WT: TMatrix4;
  Orig: TVector3;
  CeilD, WallD, BestWall, MaxW, MaxC: Single;
  I: Integer;
begin
  Result := Default(TWallSootProbeResult);
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;
  if ActiveRoot = nil then Exit;

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  Orig := WT.MultPoint(TVector3.Zero);
  MaxC := Max(0.25, FMaxCeilingSootHeightMeters);
  MaxW := Max(0.20, FMaxWallSootRadiusMeters);

  if NearestRayDist(Orig, Vector3(0.0, 1.0, 0.0), MaxC, CeilD) then
  begin
    Result.CeilingHit := True;
    Result.CeilingDistMeters := CeilD;
    Result.CeilingSootDarkening01 := Sqr(Clamped(1.0 - (CeilD / MaxC), 0.0, 1.0));
    Inc(Result.SootSurfaceCount);
  end;

  BestWall := MaxW + 1.0;
  for I := 0 to 3 do
    if NearestRayDist(Orig, Dirs4[I], MaxW, WallD) then
    begin
      Inc(Result.SootSurfaceCount);
      if WallD < BestWall then
        BestWall := WallD;
    end;

  if BestWall <= MaxW then
  begin
    Result.WallHit := True;
    Result.NearestWallDistMeters := BestWall;
    Result.WallSootDarkening01 := Sqr(Clamped(1.0 - (BestWall / MaxW), 0.0, 1.0));
  end;

  FLastSoot := Result;
end;

procedure TCastleFlameFlickerRig.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewFlameScene := nil;
  end;
end;

procedure TCastleFlameFlickerRig.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  Tip: TVector3;
  Pts: array[0..5] of TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'FlameFlickerPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewFlameScene := TCastleScene.Create(FPreviewRoot);
  FPreviewFlameScene.SetTransient;
  FPreviewFlameScene.Name := 'FlameFlickerPreviewTongue';
  FPreviewFlameScene.Pickable := False;
  FPreviewFlameScene.Collides := False;
  FPreviewRoot.Add(FPreviewFlameScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FIsLit then
    MatNode.EmissiveColor := FLastSample.BlackbodyRgb
  else
    MatNode.EmissiveColor := Vector3(0.45, 0.45, 0.48);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  if FIsLit then
    Tip := FLastSample.FlameTipLocalOffset
  else
    Tip := Vector3(0.0, 0.22, 0.0);

  CoordNode := TCoordinateNode.Create;
  Pts[0] := Vector3(-0.08, 0.0, 0.0);
  Pts[1] := Tip;
  Pts[2] := Vector3(0.08, 0.0, 0.0);
  Pts[3] := Vector3(0.0, 0.0, -0.08);
  Pts[4] := Tip;
  Pts[5] := Vector3(0.0, 0.0, 0.08);
  CoordNode.SetPoint(Pts);

  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([3, 3]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewFlameScene.Load(RootNode, True);
end;

function TCastleFlameFlickerRig.FlameSummaryBadge: String;
begin
  if FIsLit then
    Result := FormatDot('[Torch:%dK %.2fx Soot=%d]', [
      Round(FLastSample.CurrentKelvin),
      FLastSample.IntensityMultiplier,
      FLastSoot.SootSurfaceCount])
  else
    Result := '[Torch:BLOWN OUT]';
end;

initialization
  RegisterSerializableComponent(TCastleFlameFlickerRig, 'Flame Blackbody Flicker Rig');

end.
