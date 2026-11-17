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

{ MegaLights 3D clustered frustum/world tile light-grid culler, hotspot budget
  auditor, procedural Light-Function Gobo cookie generator, and deterministic
  torch/neon/siren intensity flicker behaviors
  (Phase 341 — Unreal Engine 6.0+ MegaLights & Light Functions parity). }
unit CastleMegaLights;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene;

type
  { Temporal intensity modulation curves for TCastleLightFunctionBehavior. }
  TLightFlickerProfile = (
    lfpSteadyNone,
    lfpTorchCampfirePerlin,
    lfpBrokenFluorescentStrobe,
    lfpSirenPulseBeacon
  );

  { Procedural 2D gobo cookie mask patterns. }
  TLightGoboPattern = (
    lgpNone,
    lgpWindowVenetianBlinds,
    lgpUnderwaterCaustics,
    lgpCathedralRoseGrate,
    lgpIndustrialFanBlades
  );

  { Light-Function behavior attachable to any TCastlePunctualLight to drive
    deterministic temporal flicker and procedural gobo cookie patterns. }
  TCastleLightFunctionBehavior = class(TCastleBehavior)
  private
    FFlickerProfile: TLightFlickerProfile;
    FGoboPattern: TLightGoboPattern;
    FBaseIntensity: Single;
    FFlickerAmplitude: Single;
    FFlickerSpeedHz: Single;
    FPhaseOffsetSec: Single;
    FElapsedSec: Single;
    FLastEvaluatedIntensity: Single;

    procedure SetBaseIntensity(const AValue: Single);
    procedure SetFlickerAmplitude(const AValue: Single);
    procedure SetFlickerSpeedHz(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Advance flicker clock by Dt and apply modulated intensity onto Parent
      if Parent is a TCastlePunctualLight. }
    function StepLightFunction(const Dt: Single): Single;

    function SampleCookieAtUv(const U, V: Single): Single;
    function LightFunctionSummaryBadge: String;

    property ElapsedSec: Single read FElapsedSec write FElapsedSec;
    property LastEvaluatedIntensity: Single read FLastEvaluatedIntensity;
  published
    property FlickerProfile: TLightFlickerProfile read FFlickerProfile write FFlickerProfile default lfpTorchCampfirePerlin;
    property GoboPattern: TLightGoboPattern read FGoboPattern write FGoboPattern default lgpNone;
    property BaseIntensity: Single read FBaseIntensity write SetBaseIntensity {$ifdef FPC}default 12.0{$endif};
    property FlickerAmplitude: Single read FFlickerAmplitude write SetFlickerAmplitude {$ifdef FPC}default 0.35{$endif};
    property FlickerSpeedHz: Single read FFlickerSpeedHz write SetFlickerSpeedHz {$ifdef FPC}default 4.0{$endif};
    property PhaseOffsetSec: Single read FPhaseOffsetSec write FPhaseOffsetSec {$ifdef FPC}default 0.0{$endif};
  end;

  { 3D clustered light-grid manager that bins punctual lights into a
    TilesX x TilesY x TilesZ spatial grid, enforces distance culling, and
    identifies over-budget tile hotspots. }
  TCastleMegaLightsManager = class(TCastleTransform)
  private
    FTilesX: Integer;
    FTilesY: Integer;
    FTilesZ: Integer;
    FVolumeHalfExtentXZ: Single;
    FVolumeHeightY: Single;
    FMaxLightsPerCluster: Integer;
    FDistanceCullMeters: Single;
    FEnableDistanceCulling: Boolean;

    FTileLightCounts: array of Integer;
    FTotalSceneLights: Integer;
    FActiveUnculledLights: Integer;
    FCulledDistantLights: Integer;
    FHotspotMaxLightsInAnyTile: Integer;
    FOverflowTileCount: Integer;

    procedure SetTilesX(const AValue: Integer);
    procedure SetTilesY(const AValue: Integer);
    procedure SetTilesZ(const AValue: Integer);
    procedure SetVolumeHalfExtentXZ(const AValue: Single);
    procedure SetVolumeHeightY(const AValue: Single);
    procedure SetMaxLightsPerCluster(const AValue: Integer);
    procedure SetDistanceCullMeters(const AValue: Single);
    function TileIndex(const AX, AY, AZ: Integer): Integer; inline;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Scan ARootTransform, apply optional camera-distance culling, and bin all
      active punctual lights into the 3D clustered tile grid. }
    procedure RebuildLightClusters(const ARootTransform: TCastleTransform;
      const ACameraWorldPos: TVector3);

    { Restore Exists := True on all punctual lights in ARootTransform. }
    procedure RestoreAllLightsVisible(const ARootTransform: TCastleTransform);

    function SampleTileLightCount(const AX, AY, AZ: Integer): Integer;
    function MaxColumnLightCountXZ(const AX, AZ: Integer): Integer;
    function MegaLightsSummaryBadge: String;

    property TotalSceneLights: Integer read FTotalSceneLights;
    property ActiveUnculledLights: Integer read FActiveUnculledLights;
    property CulledDistantLights: Integer read FCulledDistantLights;
    property HotspotMaxLightsInAnyTile: Integer read FHotspotMaxLightsInAnyTile;
    property OverflowTileCount: Integer read FOverflowTileCount;
  published
    property TilesX: Integer read FTilesX write SetTilesX default 16;
    property TilesY: Integer read FTilesY write SetTilesY default 8;
    property TilesZ: Integer read FTilesZ write SetTilesZ default 16;
    property VolumeHalfExtentXZ: Single read FVolumeHalfExtentXZ write SetVolumeHalfExtentXZ {$ifdef FPC}default 36.0{$endif};
    property VolumeHeightY: Single read FVolumeHeightY write SetVolumeHeightY {$ifdef FPC}default 16.0{$endif};
    property MaxLightsPerCluster: Integer read FMaxLightsPerCluster write SetMaxLightsPerCluster default 6;
    property DistanceCullMeters: Single read FDistanceCullMeters write SetDistanceCullMeters {$ifdef FPC}default 65.0{$endif};
    property EnableDistanceCulling: Boolean read FEnableDistanceCulling write FEnableDistanceCulling default True;
  end;

function EvaluateGoboCookieMask(const APattern: TLightGoboPattern;
  const U, V, ATimeSec: Single): Single;
function GoboPatternToDisplayName(const APattern: TLightGoboPattern): String;
function SphereIntersectsBox(const ACenter: TVector3; const ARadius: Single;
  const BMin, BMax: TVector3): Boolean;

implementation

uses
  CastleComponentSerialize;

function GoboPatternToDisplayName(const APattern: TLightGoboPattern): String;
begin
  case APattern of
    lgpNone:                 Result := 'Open Unmasked Cone';
    lgpWindowVenetianBlinds: Result := 'Venetian Window Blinds';
    lgpUnderwaterCaustics:   Result := 'Underwater Caustic Web';
    lgpCathedralRoseGrate:   Result := 'Cathedral Iron Grate';
    lgpIndustrialFanBlades:  Result := 'Rotating Industrial Fan';
  end;
end;

function EvaluateGoboCookieMask(const APattern: TLightGoboPattern;
  const U, V, ATimeSec: Single): Single;
var
  Dx, Dy, R, Ang, Wave: Single;
begin
  case APattern of
    lgpNone:
      Result := 1.0;
    lgpWindowVenetianBlinds:
      begin
        if Frac(Abs(V) * 8.0) < 0.52 then
          Result := 1.0
        else
          Result := 0.08;
      end;
    lgpUnderwaterCaustics:
      begin
        Wave := 0.5 + 0.25 * Sin(U * 18.0 + ATimeSec * 2.4) * Cos(V * 16.0 - ATimeSec * 1.9)
                    + 0.25 * Sin((U + V) * 24.0 - ATimeSec * 3.1);
        Result := EnsureRange(Sqr(Wave) * 1.35, 0.05, 1.0);
      end;
    lgpCathedralRoseGrate:
      begin
        if (Frac(Abs(U) * 6.0) < 0.16) or (Frac(Abs(V) * 6.0) < 0.16) then
          Result := 0.10
        else
          Result := 0.95;
      end;
    lgpIndustrialFanBlades:
      begin
        Dx := U - 0.5;
        Dy := V - 0.5;
        R := Sqrt(Dx * Dx + Dy * Dy);
        if R > 0.48 then
          Exit(0.0);
        Ang := ArcTan2(Dy, Dx) + ATimeSec * 3.2;
        if Sin(Ang * 4.0) > 0.0 then
          Result := 0.12
        else
          Result := 0.96;
      end;
  end;
end;

function SphereIntersectsBox(const ACenter: TVector3; const ARadius: Single;
  const BMin, BMax: TVector3): Boolean;
var
  ClampedPt, Diff: TVector3;
begin
  ClampedPt := Vector3(
    EnsureRange(ACenter.X, BMin.X, BMax.X),
    EnsureRange(ACenter.Y, BMin.Y, BMax.Y),
    EnsureRange(ACenter.Z, BMin.Z, BMax.Z));
  Diff := ACenter - ClampedPt;
  Result := Diff.LengthSqr <= Sqr(Max(0.0, ARadius));
end;

{ TCastleLightFunctionBehavior ----------------------------------------------- }

constructor TCastleLightFunctionBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFlickerProfile := lfpTorchCampfirePerlin;
  FGoboPattern := lgpNone;
  FBaseIntensity := 12.0;
  FFlickerAmplitude := 0.35;
  FFlickerSpeedHz := 4.0;
  FPhaseOffsetSec := 0.0;
  FLastEvaluatedIntensity := FBaseIntensity;
end;

function TCastleLightFunctionBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'FlickerProfile', 'GoboPattern', 'BaseIntensity',
       'FlickerAmplitude', 'FlickerSpeedHz', 'PhaseOffsetSec'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLightFunctionBehavior.SetBaseIntensity(const AValue: Single);
begin
  FBaseIntensity := Max(0.0, AValue);
end;

procedure TCastleLightFunctionBehavior.SetFlickerAmplitude(const AValue: Single);
begin
  FFlickerAmplitude := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleLightFunctionBehavior.SetFlickerSpeedHz(const AValue: Single);
begin
  FFlickerSpeedHz := Max(0.1, AValue);
end;

function TCastleLightFunctionBehavior.StepLightFunction(const Dt: Single): Single;
var
  T, ModFactor, HashVal: Single;
begin
  FElapsedSec := FElapsedSec + Max(0.0, Dt);
  T := (FElapsedSec + FPhaseOffsetSec) * FFlickerSpeedHz;

  case FFlickerProfile of
    lfpSteadyNone:
      ModFactor := 1.0;
    lfpTorchCampfirePerlin:
      ModFactor := 1.0 + FFlickerAmplitude * (
        0.55 * Sin(T * 2.0 * Pi) +
        0.30 * Sin(T * 4.73 * Pi + 1.3) +
        0.15 * Cos(T * 9.17 * Pi + 0.7));
    lfpBrokenFluorescentStrobe:
      begin
        HashVal := Frac(Sin(Floor(T * 6.0) * 12.9898) * 43758.5453);
        if HashVal < (0.28 * FFlickerAmplitude * 2.0) then
          ModFactor := 0.08
        else
          ModFactor := 1.0;
      end;
    lfpSirenPulseBeacon:
      ModFactor := Max(0.05, 1.0 - FFlickerAmplitude + FFlickerAmplitude * (0.5 + 0.5 * Sin(T * 2.0 * Pi)));
  end;

  FLastEvaluatedIntensity := Max(0.0, FBaseIntensity * ModFactor);
  if Parent is TCastlePointLight then
    TCastlePointLight(Parent).Intensity := FLastEvaluatedIntensity
  else if Parent is TCastleSpotLight then
    TCastleSpotLight(Parent).Intensity := FLastEvaluatedIntensity
  else if Parent is TCastleDirectionalLight then
    TCastleDirectionalLight(Parent).Intensity := FLastEvaluatedIntensity;
  Result := FLastEvaluatedIntensity;
end;

procedure TCastleLightFunctionBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  StepLightFunction(Min(SecondsPassed, 0.1));
end;

function TCastleLightFunctionBehavior.SampleCookieAtUv(
  const U, V: Single): Single;
begin
  Result := EvaluateGoboCookieMask(FGoboPattern, U, V, FElapsedSec + FPhaseOffsetSec);
end;

function TCastleLightFunctionBehavior.LightFunctionSummaryBadge: String;
begin
  Result := Format('[LightFn:I=%.1f Gobo=%s]', [
    FLastEvaluatedIntensity, GoboPatternToDisplayName(FGoboPattern)
  ]);
end;

{ TCastleMegaLightsManager --------------------------------------------------- }

constructor TCastleMegaLightsManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTilesX := 16;
  FTilesY := 8;
  FTilesZ := 16;
  FVolumeHalfExtentXZ := 36.0;
  FVolumeHeightY := 16.0;
  FMaxLightsPerCluster := 6;
  FDistanceCullMeters := 65.0;
  FEnableDistanceCulling := True;
  SetLength(FTileLightCounts, FTilesX * FTilesY * FTilesZ);
end;

destructor TCastleMegaLightsManager.Destroy;
begin
  SetLength(FTileLightCounts, 0);
  inherited Destroy;
end;

function TCastleMegaLightsManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'TilesX', 'TilesY', 'TilesZ', 'VolumeHalfExtentXZ', 'VolumeHeightY',
       'MaxLightsPerCluster', 'DistanceCullMeters', 'EnableDistanceCulling'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMegaLightsManager.SetTilesX(const AValue: Integer);
begin
  FTilesX := EnsureRange(AValue, 2, 64);
end;

procedure TCastleMegaLightsManager.SetTilesY(const AValue: Integer);
begin
  FTilesY := EnsureRange(AValue, 2, 32);
end;

procedure TCastleMegaLightsManager.SetTilesZ(const AValue: Integer);
begin
  FTilesZ := EnsureRange(AValue, 2, 64);
end;

procedure TCastleMegaLightsManager.SetVolumeHalfExtentXZ(const AValue: Single);
begin
  FVolumeHalfExtentXZ := Max(4.0, AValue);
end;

procedure TCastleMegaLightsManager.SetVolumeHeightY(const AValue: Single);
begin
  FVolumeHeightY := Max(2.0, AValue);
end;

procedure TCastleMegaLightsManager.SetMaxLightsPerCluster(const AValue: Integer);
begin
  FMaxLightsPerCluster := Max(1, AValue);
end;

procedure TCastleMegaLightsManager.SetDistanceCullMeters(const AValue: Single);
begin
  FDistanceCullMeters := Max(5.0, AValue);
end;

function TCastleMegaLightsManager.TileIndex(const AX, AY, AZ: Integer): Integer;
begin
  Result := (AZ * FTilesY + AY) * FTilesX + AX;
end;

procedure TCastleMegaLightsManager.RebuildLightClusters(
  const ARootTransform: TCastleTransform; const ACameraWorldPos: TVector3);
var
  Origin, VolMin, StepSize: TVector3;
  TotalTiles, I: Integer;

  procedure BinPunctualLight(const L: TCastlePunctualLight);
  var
    LPos, TMin, TMax: TVector3;
    LRad, CamDist: Single;
    MinTX, MaxTX, MinTY, MaxTY, MinTZ, MaxTZ, TX, TY, TZ: Integer;
  begin
    Inc(FTotalSceneLights);
    if L.HasParent then
      LPos := L.WorldTranslation
    else
      LPos := L.Translation;

    if L is TCastlePointLight then
      LRad := TCastlePointLight(L).Radius
    else if L is TCastleSpotLight then
      LRad := TCastleSpotLight(L).Radius
    else
      LRad := 10.0;
    if LRad <= 0.0 then
      LRad := 14.0;

    CamDist := PointsDistance(ACameraWorldPos, LPos);
    if FEnableDistanceCulling and (CamDist > FDistanceCullMeters + LRad) then
    begin
      L.Exists := False;
      Inc(FCulledDistantLights);
      Exit;
    end;

    L.Exists := True;
    Inc(FActiveUnculledLights);

    MinTX := EnsureRange(Floor(((LPos.X - LRad) - VolMin.X) / StepSize.X), 0, FTilesX - 1);
    MaxTX := EnsureRange(Floor(((LPos.X + LRad) - VolMin.X) / StepSize.X), 0, FTilesX - 1);
    MinTY := EnsureRange(Floor(((LPos.Y - LRad) - VolMin.Y) / StepSize.Y), 0, FTilesY - 1);
    MaxTY := EnsureRange(Floor(((LPos.Y + LRad) - VolMin.Y) / StepSize.Y), 0, FTilesY - 1);
    MinTZ := EnsureRange(Floor(((LPos.Z - LRad) - VolMin.Z) / StepSize.Z), 0, FTilesZ - 1);
    MaxTZ := EnsureRange(Floor(((LPos.Z + LRad) - VolMin.Z) / StepSize.Z), 0, FTilesZ - 1);

    for TZ := MinTZ to MaxTZ do
      for TY := MinTY to MaxTY do
        for TX := MinTX to MaxTX do
        begin
          TMin := Vector3(
            VolMin.X + TX * StepSize.X,
            VolMin.Y + TY * StepSize.Y,
            VolMin.Z + TZ * StepSize.Z);
          TMax := TMin + StepSize;
          if SphereIntersectsBox(LPos, LRad, TMin, TMax) then
            Inc(FTileLightCounts[TileIndex(TX, TY, TZ)]);
        end;
  end;

  procedure ScanRec(const Node: TCastleTransform);
  var
    CIdx: Integer;
  begin
    if (Node = nil) or (Node = Self) then
      Exit;
    if (Node <> ARootTransform) and (csTransient in Node.ComponentStyle) then
      Exit;
    if Node is TCastlePunctualLight then
      BinPunctualLight(TCastlePunctualLight(Node));
    for CIdx := 0 to Node.Count - 1 do
      ScanRec(Node[CIdx]);
  end;

begin
  TotalTiles := FTilesX * FTilesY * FTilesZ;
  SetLength(FTileLightCounts, TotalTiles);
  for I := 0 to TotalTiles - 1 do
    FTileLightCounts[I] := 0;

  FTotalSceneLights := 0;
  FActiveUnculledLights := 0;
  FCulledDistantLights := 0;
  FHotspotMaxLightsInAnyTile := 0;
  FOverflowTileCount := 0;

  if ARootTransform = nil then
    Exit;

  if HasParent then
    Origin := WorldTranslation
  else
    Origin := Translation;

  VolMin := Vector3(
    Origin.X - FVolumeHalfExtentXZ,
    Origin.Y,
    Origin.Z - FVolumeHalfExtentXZ);
  StepSize := Vector3(
    (2.0 * FVolumeHalfExtentXZ) / FTilesX,
    FVolumeHeightY / FTilesY,
    (2.0 * FVolumeHalfExtentXZ) / FTilesZ);

  ScanRec(ARootTransform);

  for I := 0 to TotalTiles - 1 do
  begin
    if FTileLightCounts[I] > FHotspotMaxLightsInAnyTile then
      FHotspotMaxLightsInAnyTile := FTileLightCounts[I];
    if FTileLightCounts[I] > FMaxLightsPerCluster then
      Inc(FOverflowTileCount);
  end;
end;

procedure TCastleMegaLightsManager.RestoreAllLightsVisible(
  const ARootTransform: TCastleTransform);

  procedure ScanRec(const Node: TCastleTransform);
  var
    I: Integer;
  begin
    if Node = nil then Exit;
    if Node is TCastlePunctualLight then
      Node.Exists := True;
    for I := 0 to Node.Count - 1 do
      ScanRec(Node[I]);
  end;

begin
  ScanRec(ARootTransform);
end;

function TCastleMegaLightsManager.SampleTileLightCount(
  const AX, AY, AZ: Integer): Integer;
var
  Idx: Integer;
begin
  if (AX >= 0) and (AX < FTilesX) and
     (AY >= 0) and (AY < FTilesY) and
     (AZ >= 0) and (AZ < FTilesZ) then
  begin
    Idx := TileIndex(AX, AY, AZ);
    if Idx <= High(FTileLightCounts) then
      Exit(FTileLightCounts[Idx]);
  end;
  Result := 0;
end;

function TCastleMegaLightsManager.MaxColumnLightCountXZ(
  const AX, AZ: Integer): Integer;
var
  Y, C: Integer;
begin
  Result := 0;
  for Y := 0 to FTilesY - 1 do
  begin
    C := SampleTileLightCount(AX, Y, AZ);
    if C > Result then
      Result := C;
  end;
end;

function TCastleMegaLightsManager.MegaLightsSummaryBadge: String;
begin
  Result := Format('[MegaLights:%d/%d active PeakTile=%d Over=%d]', [
    FActiveUnculledLights, FTotalSceneLights,
    FHotspotMaxLightsInAnyTile, FOverflowTileCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleLightFunctionBehavior,
    ['Lighting & PostFX', 'Light-Function Gobo & Flicker (TCastleLightFunctionBehavior)']);
  RegisterSerializableComponent(TCastleMegaLightsManager,
    ['Lighting & PostFX', 'MegaLights Clustered Light-Grid Culler (TCastleMegaLightsManager)']);

end.
