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

{ Ambient Soundscape Biome Director providing context-reactive biome palettes
  (HourOfDay, ListenerAltitudeY, IndoorEnclosureRatio), seeded 3D hemisphere
  one-shot spatial call scattering, and WorldRay listener-to-emitter acoustic
  wall occlusion gain & low-pass cutoff muffling
  (Phase 345 — Unreal Engine 6.0+ USoundscapeSubsystem Parity). }
unit CastleSoundscape;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Context-reactive ambient biome palette layers. }
  TSoundscapeLayerKind = (
    slkForestDawnBirds,
    slkNocturnalCrickets,
    slkAlpineHowlingWind,
    slkCavernWaterDrips
  );

  { Active spatialized 3D ambient one-shot emitter slot. }
  TSoundscapeActiveCall = record
    Active: Boolean;
    LayerKind: TSoundscapeLayerKind;
    ClipId: String;
    WorldPos: TVector3;
    BaseGain: Single;
    EffectiveGain: Single;
    LowPassCutoffHz: Single;
    Occluded: Boolean;
    AgeSec: Single;
    DurationSec: Single;
  end;

  { Context-reactive 3D Soundscape Director managing biome palette weights,
    hemisphere spatial call scattering, and raycast wall occlusion muffling. }
  TCastleSoundscapeDirector = class(TCastleTransform)
  private
    FHourOfDay: Single;
    FListenerAltitudeY: Single;
    FIndoorEnclosureRatio: Single;
    FSpawnRadiusMin: Single;
    FSpawnRadiusMax: Single;
    FMaxConcurrentCalls: Integer;
    FSpawnIntervalSec: Single;
    FOccludedGainMultiplier: Single;
    FOccludedLowPassHz: Single;
    FClearLowPassHz: Single;
    FRandomSeed: Integer;
    FEnableRayOcclusion: Boolean;
    FBuildDebugEmitterMesh: Boolean;

    FCalls: array of TSoundscapeActiveCall;
    FActiveCallCount: Integer;
    FOccludedCallCount: Integer;
    FTotalSpawnedCalls: Integer;
    FRngState: Cardinal;
    FSpawnAccumSec: Single;

    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;

    procedure SetHourOfDay(const AValue: Single);
    procedure SetIndoorEnclosureRatio(const AValue: Single);
    procedure SetMaxConcurrentCalls(const AValue: Integer);
    procedure SetRandomSeed(const AValue: Integer);
    procedure SetBuildDebugEmitterMesh(const AValue: Boolean);

    function AcquireCallSlotIndex: Integer;
    procedure RecountCalls;
    function SelectDominantLayer(out ADominantWeight: Single): TSoundscapeLayerKind;
    procedure EnsureDebugScene;
    procedure RebuildDebugMesh(const AListenerPos: TVector3);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearActiveCalls;

    { Evaluate context-reactive blend weight [0..1] for ALayer given current
      HourOfDay, ListenerAltitudeY, and IndoorEnclosureRatio. }
    function EvaluatePaletteWeight(const ALayer: TSoundscapeLayerKind): Single;

    { Dominant active biome layer under current environmental conditions. }
    function DominantBiomeLayer: TSoundscapeLayerKind;

    { Raycast from AListenerPos to AEmitterPos on AWorldRoot to test whether
      solid geometry blocks direct acoustic line-of-sight. }
    function ProbeAcousticOcclusion(const AWorldRoot: TCastleTransform;
      const AListenerPos, AEmitterPos: TVector3): Boolean;

    { Spawn a specific ambient call at AEmitterPos and evaluate distance +
      raycast acoustic occlusion gain/LPF muffling. }
    function TriggerCallAtWorldPos(const AWorldRoot: TCastleTransform;
      const AListenerPos, AEmitterPos: TVector3;
      const ALayerKind: TSoundscapeLayerKind): Integer;

    { Deterministically scatter one spatial call on the 3D upper hemisphere
      around AListenerPos using the dominant biome palette. }
    function SpawnScatterCall(const AWorldRoot: TCastleTransform;
      const AListenerPos: TVector3): Integer;

    { Re-evaluate occlusion & aging across active calls and trigger periodic
      hemisphere spawns. }
    procedure StepSoundscape(const AWorldRoot: TCastleTransform;
      const AListenerPos: TVector3; const ADt: Single);

    function CallPoolCapacity: Integer;
    function GetActiveCall(const AIndex: Integer): TSoundscapeActiveCall;
    function SoundscapeSummaryBadge: String;

    property ActiveCallCount: Integer read FActiveCallCount;
    property OccludedCallCount: Integer read FOccludedCallCount;
    property TotalSpawnedCalls: Integer read FTotalSpawnedCalls;
  published
    property HourOfDay: Single read FHourOfDay write SetHourOfDay {$ifdef FPC}default 7.0{$endif};
    property ListenerAltitudeY: Single read FListenerAltitudeY write FListenerAltitudeY {$ifdef FPC}default 4.0{$endif};
    property IndoorEnclosureRatio: Single read FIndoorEnclosureRatio write SetIndoorEnclosureRatio {$ifdef FPC}default 0.0{$endif};
    property SpawnRadiusMin: Single read FSpawnRadiusMin write FSpawnRadiusMin {$ifdef FPC}default 6.0{$endif};
    property SpawnRadiusMax: Single read FSpawnRadiusMax write FSpawnRadiusMax {$ifdef FPC}default 22.0{$endif};
    property MaxConcurrentCalls: Integer read FMaxConcurrentCalls write SetMaxConcurrentCalls default 24;
    property SpawnIntervalSec: Single read FSpawnIntervalSec write FSpawnIntervalSec {$ifdef FPC}default 0.45{$endif};
    property OccludedGainMultiplier: Single read FOccludedGainMultiplier write FOccludedGainMultiplier {$ifdef FPC}default 0.28{$endif};
    property OccludedLowPassHz: Single read FOccludedLowPassHz write FOccludedLowPassHz {$ifdef FPC}default 950.0{$endif};
    property ClearLowPassHz: Single read FClearLowPassHz write FClearLowPassHz {$ifdef FPC}default 20000.0{$endif};
    property RandomSeed: Integer read FRandomSeed write SetRandomSeed default 20260345;
    property EnableRayOcclusion: Boolean read FEnableRayOcclusion write FEnableRayOcclusion default True;
    property BuildDebugEmitterMesh: Boolean read FBuildDebugEmitterMesh write SetBuildDebugEmitterMesh default True;
  end;

function SoundscapeLayerToDisplayName(const ALayer: TSoundscapeLayerKind): String;
function SoundscapeLayerClipId(const ALayer: TSoundscapeLayerKind; const AVariant: Integer): String;

implementation

uses
  CastleComponentSerialize;

function SoundscapeLayerToDisplayName(const ALayer: TSoundscapeLayerKind): String;
begin
  case ALayer of
    slkForestDawnBirds:   Result := 'Forest Dawn Songbirds';
    slkNocturnalCrickets: Result := 'Nocturnal Crickets & Owls';
    slkAlpineHowlingWind: Result := 'High-Peak Alpine Wind';
    slkCavernWaterDrips:  Result := 'Subterranean Cavern Drips';
  end;
end;

function SoundscapeLayerClipId(const ALayer: TSoundscapeLayerKind;
  const AVariant: Integer): String;
var
  V: Integer;
begin
  V := (Abs(AVariant) mod 3) + 1;
  case ALayer of
    slkForestDawnBirds:   Result := Format('sfx_bird_warbler_%d', [V]);
    slkNocturnalCrickets: Result := Format('sfx_night_cricket_%d', [V]);
    slkAlpineHowlingWind: Result := Format('sfx_alpine_gust_%d', [V]);
    slkCavernWaterDrips:  Result := Format('sfx_cavern_drip_%d', [V]);
  end;
end;

{$PUSH}{$Q-}{$R-}
function NextUnitFloat(var State: Cardinal): Single;
begin
  if State = 0 then
    State := 271828183;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := (State and $FFFFFF) / 16777216.0;
end;
{$POP}

{ TCastleSoundscapeDirector -------------------------------------------------- }

constructor TCastleSoundscapeDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHourOfDay := 7.0;
  FListenerAltitudeY := 4.0;
  FIndoorEnclosureRatio := 0.0;
  FSpawnRadiusMin := 6.0;
  FSpawnRadiusMax := 22.0;
  FMaxConcurrentCalls := 24;
  FSpawnIntervalSec := 0.45;
  FOccludedGainMultiplier := 0.28;
  FOccludedLowPassHz := 950.0;
  FClearLowPassHz := 20000.0;
  FRandomSeed := 20260345;
  FRngState := Cardinal(FRandomSeed);
  FEnableRayOcclusion := True;
  FBuildDebugEmitterMesh := True;
  SetLength(FCalls, FMaxConcurrentCalls);
  ClearActiveCalls;
end;

destructor TCastleSoundscapeDirector.Destroy;
begin
  FCoordNode := nil;
  FColorNode := nil;
  FreeAndNil(FTransientScene);
  ClearActiveCalls;
  SetLength(FCalls, 0);
  inherited Destroy;
end;

function TCastleSoundscapeDirector.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'HourOfDay', 'ListenerAltitudeY', 'IndoorEnclosureRatio',
       'SpawnRadiusMin', 'SpawnRadiusMax', 'MaxConcurrentCalls',
       'SpawnIntervalSec', 'OccludedGainMultiplier', 'OccludedLowPassHz',
       'ClearLowPassHz', 'RandomSeed', 'EnableRayOcclusion', 'BuildDebugEmitterMesh'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSoundscapeDirector.SetHourOfDay(const AValue: Single);
begin
  FHourOfDay := AValue - Floor(AValue / 24.0) * 24.0;
end;

procedure TCastleSoundscapeDirector.SetIndoorEnclosureRatio(const AValue: Single);
begin
  FIndoorEnclosureRatio := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleSoundscapeDirector.SetMaxConcurrentCalls(const AValue: Integer);
var
  NewCap, I: Integer;
begin
  NewCap := EnsureRange(AValue, 4, 128);
  if NewCap = FMaxConcurrentCalls then Exit;
  for I := NewCap to High(FCalls) do
    FCalls[I] := Default(TSoundscapeActiveCall);
  FMaxConcurrentCalls := NewCap;
  SetLength(FCalls, FMaxConcurrentCalls);
  RecountCalls;
end;

procedure TCastleSoundscapeDirector.SetRandomSeed(const AValue: Integer);
begin
  FRandomSeed := AValue;
  FRngState := Cardinal(Abs(AValue) + 1);
end;

procedure TCastleSoundscapeDirector.SetBuildDebugEmitterMesh(const AValue: Boolean);
begin
  if FBuildDebugEmitterMesh = AValue then Exit;
  FBuildDebugEmitterMesh := AValue;
  if not FBuildDebugEmitterMesh then
  begin
    FCoordNode := nil;
    FColorNode := nil;
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleSoundscapeDirector.ClearActiveCalls;
var
  I: Integer;
begin
  for I := 0 to High(FCalls) do
    FCalls[I] := Default(TSoundscapeActiveCall);
  FActiveCallCount := 0;
  FOccludedCallCount := 0;
  FSpawnAccumSec := 0.0;
  FRngState := Cardinal(Abs(FRandomSeed) + 1);
  if FCoordNode <> nil then
  begin
    FCoordNode.FdPoint.Count := 0;
    FCoordNode.FdPoint.Changed;
  end;
  if FColorNode <> nil then
  begin
    FColorNode.FdColor.Count := 0;
    FColorNode.FdColor.Changed;
  end;
end;

function TCastleSoundscapeDirector.EvaluatePaletteWeight(
  const ALayer: TSoundscapeLayerKind): Single;
var
  OutdoorFactor, LowAltFactor: Single;
begin
  OutdoorFactor := EnsureRange(1.0 - FIndoorEnclosureRatio * 1.6, 0.0, 1.0);
  LowAltFactor := EnsureRange((55.0 - FListenerAltitudeY) / 20.0, 0.0, 1.0);

  case ALayer of
    slkForestDawnBirds:
      begin
        if (FHourOfDay >= 5.5) and (FHourOfDay <= 19.0) then
          Result := OutdoorFactor * LowAltFactor
        else
          Result := 0.0;
      end;
    slkNocturnalCrickets:
      begin
        if (FHourOfDay < 5.5) or (FHourOfDay > 19.0) then
          Result := OutdoorFactor * LowAltFactor
        else
          Result := 0.0;
      end;
    slkAlpineHowlingWind:
      begin
        if FListenerAltitudeY >= 40.0 then
          Result := OutdoorFactor * EnsureRange((FListenerAltitudeY - 35.0) / 25.0, 0.25, 1.0)
        else
          Result := 0.0;
      end;
    slkCavernWaterDrips:
      begin
        if FIndoorEnclosureRatio >= 0.50 then
          Result := EnsureRange((FIndoorEnclosureRatio - 0.40) / 0.50, 0.2, 1.0)
        else
          Result := 0.0;
      end;
  end;
end;

function TCastleSoundscapeDirector.SelectDominantLayer(
  out ADominantWeight: Single): TSoundscapeLayerKind;
var
  L: TSoundscapeLayerKind;
  W: Single;
begin
  Result := slkForestDawnBirds;
  ADominantWeight := -1.0;
  for L := Low(TSoundscapeLayerKind) to High(TSoundscapeLayerKind) do
  begin
    W := EvaluatePaletteWeight(L);
    if W > ADominantWeight then
    begin
      ADominantWeight := W;
      Result := L;
    end;
  end;
end;

function TCastleSoundscapeDirector.DominantBiomeLayer: TSoundscapeLayerKind;
var
  W: Single;
begin
  Result := SelectDominantLayer(W);
end;

function TCastleSoundscapeDirector.AcquireCallSlotIndex: Integer;
var
  I, OldestIdx: Integer;
  OldestAge: Single;
begin
  if Length(FCalls) <> FMaxConcurrentCalls then
    SetLength(FCalls, FMaxConcurrentCalls);

  for I := 0 to High(FCalls) do
    if not FCalls[I].Active then
      Exit(I);

  OldestIdx := 0;
  OldestAge := -1.0;
  for I := 0 to High(FCalls) do
    if FCalls[I].AgeSec > OldestAge then
    begin
      OldestAge := FCalls[I].AgeSec;
      OldestIdx := I;
    end;
  Result := OldestIdx;
end;

procedure TCastleSoundscapeDirector.RecountCalls;
var
  I: Integer;
begin
  FActiveCallCount := 0;
  FOccludedCallCount := 0;
  for I := 0 to High(FCalls) do
    if FCalls[I].Active then
    begin
      Inc(FActiveCallCount);
      if FCalls[I].Occluded then
        Inc(FOccludedCallCount);
    end;
end;

function TCastleSoundscapeDirector.ProbeAcousticOcclusion(
  const AWorldRoot: TCastleTransform;
  const AListenerPos, AEmitterPos: TVector3): Boolean;
var
  Delta, Dir: TVector3;
  Dist: Single;
  RayHit: TRayCollision;
  SavedDebugExists: Boolean;
begin
  Result := False;
  if (not FEnableRayOcclusion) or (AWorldRoot = nil) then
    Exit;

  Delta := AEmitterPos - AListenerPos;
  Dist := Delta.Length;
  if Dist < 0.25 then
    Exit;
  Dir := Delta / Dist;

  SavedDebugExists := (FTransientScene <> nil) and FTransientScene.Exists;
  if FTransientScene <> nil then
    FTransientScene.Exists := False;
  try
    if AWorldRoot is TCastleAbstractRootTransform then
      RayHit := TCastleAbstractRootTransform(AWorldRoot).WorldRay(AListenerPos, Dir)
    else if AWorldRoot.World <> nil then
      RayHit := AWorldRoot.World.WorldRay(AListenerPos, Dir)
    else
      RayHit := nil;
    try
      if (RayHit <> nil) and (RayHit.Distance > 0.05) and (RayHit.Distance < Dist - 0.15) then
        Result := True;
    finally
      FreeAndNil(RayHit);
    end;
  finally
    if FTransientScene <> nil then
      FTransientScene.Exists := SavedDebugExists;
  end;
end;

function TCastleSoundscapeDirector.TriggerCallAtWorldPos(
  const AWorldRoot: TCastleTransform;
  const AListenerPos, AEmitterPos: TVector3;
  const ALayerKind: TSoundscapeLayerKind): Integer;
var
  Slot: TSoundscapeActiveCall;
  Dist, DistAtten: Single;
begin
  Result := AcquireCallSlotIndex;
  Dist := PointsDistance(AListenerPos, AEmitterPos);
  DistAtten := EnsureRange(1.0 - (Dist / Max(2.0, FSpawnRadiusMax * 1.4)), 0.18, 1.0);

  Slot := Default(TSoundscapeActiveCall);
  Slot.Active := True;
  Slot.LayerKind := ALayerKind;
  Slot.ClipId := SoundscapeLayerClipId(ALayerKind, FTotalSpawnedCalls);
  Slot.WorldPos := AEmitterPos;
  Slot.BaseGain := DistAtten;
  Slot.Occluded := ProbeAcousticOcclusion(AWorldRoot, AListenerPos, AEmitterPos);
  if Slot.Occluded then
  begin
    Slot.EffectiveGain := Slot.BaseGain * FOccludedGainMultiplier;
    Slot.LowPassCutoffHz := FOccludedLowPassHz;
  end else
  begin
    Slot.EffectiveGain := Slot.BaseGain;
    Slot.LowPassCutoffHz := FClearLowPassHz;
  end;
  Slot.AgeSec := 0.0;
  Slot.DurationSec := 2.4;

  FCalls[Result] := Slot;
  Inc(FTotalSpawnedCalls);
  RecountCalls;
  RebuildDebugMesh(AListenerPos);
end;

function TCastleSoundscapeDirector.SpawnScatterCall(
  const AWorldRoot: TCastleTransform; const AListenerPos: TVector3): Integer;
var
  Layer: TSoundscapeLayerKind;
  DomW, Azimuth, ElevRad, Radius: Single;
  EmitPos: TVector3;
begin
  Layer := SelectDominantLayer(DomW);
  if DomW <= 0.01 then
    Exit(-1);

  Azimuth := NextUnitFloat(FRngState) * 2.0 * Pi;
  ElevRad := DegToRad(5.0 + NextUnitFloat(FRngState) * 50.0);
  Radius := Lerp(NextUnitFloat(FRngState), FSpawnRadiusMin, Max(FSpawnRadiusMin + 1.0, FSpawnRadiusMax));

  EmitPos := AListenerPos + Vector3(
    Cos(Azimuth) * Cos(ElevRad) * Radius,
    Sin(ElevRad) * Radius,
    Sin(Azimuth) * Cos(ElevRad) * Radius);

  Result := TriggerCallAtWorldPos(AWorldRoot, AListenerPos, EmitPos, Layer);
end;

procedure TCastleSoundscapeDirector.StepSoundscape(
  const AWorldRoot: TCastleTransform;
  const AListenerPos: TVector3; const ADt: Single);
var
  Dt: Single;
  I: Integer;
begin
  Dt := EnsureRange(ADt, 0.0, 1.0);
  if Dt <= 0.0 then Exit;

  for I := 0 to High(FCalls) do
    if FCalls[I].Active then
    begin
      FCalls[I].AgeSec := FCalls[I].AgeSec + Dt;
      if FCalls[I].AgeSec >= FCalls[I].DurationSec then
        FCalls[I] := Default(TSoundscapeActiveCall)
      else
      begin
        FCalls[I].Occluded := ProbeAcousticOcclusion(AWorldRoot, AListenerPos, FCalls[I].WorldPos);
        if FCalls[I].Occluded then
        begin
          FCalls[I].EffectiveGain := FCalls[I].BaseGain * FOccludedGainMultiplier;
          FCalls[I].LowPassCutoffHz := FOccludedLowPassHz;
        end else
        begin
          FCalls[I].EffectiveGain := FCalls[I].BaseGain;
          FCalls[I].LowPassCutoffHz := FClearLowPassHz;
        end;
      end;
    end;

  FSpawnAccumSec := FSpawnAccumSec + Dt;
  while FSpawnAccumSec >= Max(0.08, FSpawnIntervalSec) do
  begin
    FSpawnAccumSec := FSpawnAccumSec - Max(0.08, FSpawnIntervalSec);
    SpawnScatterCall(AWorldRoot, AListenerPos);
  end;

  RecountCalls;
  RebuildDebugMesh(AListenerPos);
end;

procedure TCastleSoundscapeDirector.EnsureDebugScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  LineSet: TLineSetNode;
begin
  if not FBuildDebugEmitterMesh then Exit;
  if FTransientScene <> nil then Exit;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientSoundscapeRays';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(1, 1, 1);
  App.Material := Mat;
  Shape.Appearance := App;

  LineSet := TLineSetNode.Create;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  LineSet.Coord := FCoordNode;
  LineSet.Color := FColorNode;
  Shape.Geometry := LineSet;
  Root.AddChildren(Shape);

  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleSoundscapeDirector.RebuildDebugMesh(const AListenerPos: TVector3);
var
  InvWorld: TMatrix4;
  Verts, Colors: TVector3List;
  Counts: TInt32List;
  LineSet: TLineSetNode;
  I: Integer;
  P0, P1, Col: TVector3;
begin
  if not FBuildDebugEmitterMesh then Exit;
  EnsureDebugScene;
  if (FTransientScene = nil) or (FTransientScene.RootNode = nil) then Exit;

  if (not HasParent) or (not WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  Counts := TInt32List.Create;
  try
    P0 := InvWorld.MultPoint(AListenerPos);
    for I := 0 to High(FCalls) do
      if FCalls[I].Active then
      begin
        P1 := InvWorld.MultPoint(FCalls[I].WorldPos);
        if FCalls[I].Occluded then
          Col := Vector3(0.95, 0.34, 0.28)
        else
          Col := Vector3(0.28, 0.92, 0.56);
        Verts.Add(P0); Verts.Add(P1);
        Colors.Add(Col); Colors.Add(Col);
        Counts.Add(2);
      end;

    LineSet := (FTransientScene.RootNode.FdChildren[0] as TShapeNode).Geometry as TLineSetNode;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
    LineSet.SetVertexCount(Counts);
  finally
    FreeAndNil(Counts);
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

function TCastleSoundscapeDirector.CallPoolCapacity: Integer;
begin
  Result := Length(FCalls);
end;

function TCastleSoundscapeDirector.GetActiveCall(
  const AIndex: Integer): TSoundscapeActiveCall;
begin
  if (AIndex >= 0) and (AIndex <= High(FCalls)) then
    Result := FCalls[AIndex]
  else
    Result := Default(TSoundscapeActiveCall);
end;

function TCastleSoundscapeDirector.SoundscapeSummaryBadge: String;
begin
  Result := Format('[Soundscape:%s Act=%d Occ=%d]', [
    SoundscapeLayerToDisplayName(DominantBiomeLayer),
    FActiveCallCount, FOccludedCallCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleSoundscapeDirector,
    ['Audio & Soundscape', 'Ambient Soundscape Biome Director (TCastleSoundscapeDirector)']);

end.
