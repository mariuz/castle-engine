{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ AI Sensory Perception Sight, Wall-Muffled Hearing & Decaying Scent (Phase 378).
  Provides UE UAIPerceptionComponent-style dual-cone (foveal + peripheral)
  WorldRay line-of-sight vision, inverse-distance acoustic decibel hearing with
  solid-wall transmission muffling, and decaying scent breadcrumb tracking. }
unit CastleSensoryPerception;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions, CastleColors,
  CastleClassUtils, CastleComponentSerialize;

const
  MaxScentBreadcrumbs = 24;

type
  TSensoryPreset = (
    sppHumanGuardPatrol,
    sppBloodhoundTracker,
    sppSecurityTurretOptic,
    sppCustom
  );

  TSensoryVisionZone = (
    svzOutOfView,
    svzOccludedByWall,
    svzPeripheralGlimpse,
    svzFovealLock
  );

  TSightEvaluation = record
    Detected: Boolean;
    Zone: TSensoryVisionZone;
    DistanceMeters: Single;
    OffAxisAngleDeg: Single;
    LineOfSightClear: Boolean;
    AwarenessWeight: Single;
  end;

  THearingEvaluation = record
    Audible: Boolean;
    DistanceMeters: Single;
    WallOccluded: Boolean;
    EffectiveDecibels: Single;
    AwarenessWeight: Single;
  end;

  TScentBreadcrumb = record
    Active: Boolean;
    SourceTag: String;
    WorldPos: TVector3;
    Intensity01: Single;
    RemainingSec: Single;
    InitialSec: Single;
  end;

  { Multi-modal AI Sight, Hearing & Scent perception sensor component. }
  TCastleSensoryPerception = class(TCastleTransform)
  private
    FPreset: TSensoryPreset;
    FSensorYawDeg: Single;
    FEyeHeightMeters: Single;
    FSightRangeMeters: Single;
    FFovealHalfAngleDeg: Single;
    FPeripheralHalfAngleDeg: Single;
    FHearingThresholdDb: Single;
    FWallMufflePenaltyDb: Single;
    FScentSniffRadiusMeters: Single;
    FScentLifetimeSec: Single;
    FShowPreviewGizmo: Boolean;
    FAwareness01: Single;
    FLastStimulusPos: TVector3;
    FLastStimulusSummary: String;
    FScentRingCursor: Integer;
    FCrumbs: array[0..MaxScentBreadcrumbs - 1] of TScentBreadcrumb;
    FPreviewRoot: TCastleTransform;
    FEyeSphere, FFoveaBeam: TCastleBox;
    procedure SetPreset(const Value: TSensoryPreset);
    procedure SetSensorYawDeg(const Value: Single);
    procedure SetEyeHeightMeters(const Value: Single);
    procedure SetSightRangeMeters(const Value: Single);
    procedure SetFovealHalfAngleDeg(const Value: Single);
    procedure SetPeripheralHalfAngleDeg(const Value: Single);
    procedure SetHearingThresholdDb(const Value: Single);
    procedure SetWallMufflePenaltyDb(const Value: Single);
    procedure SetScentSniffRadiusMeters(const Value: Single);
    procedure SetScentLifetimeSec(const Value: Single);
    procedure SetShowPreviewGizmo(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure RebuildPreviewGizmo;
    function IsRayBlockedBySolidWall(const AWorldRoot: TCastleAbstractRootTransform;
      const RayOrigin, TargetPoint: TVector3; const IgnoreTarget: TCastleTransform): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    function SensorForwardDir: TVector3;
    function SensorEyeWorldPos: TVector3;

    { Evaluate foveal vs. peripheral cone and WorldRay line-of-sight occlusion. }
    function EvaluateSightTarget(const AWorldRoot: TCastleAbstractRootTransform;
      const TargetPos: TVector3; const TargetTransform: TCastleTransform = nil): TSightEvaluation;

    { Evaluate acoustic loudness with spherical distance loss and WorldRay wall muffling. }
    function EvaluateAcousticEvent(const AWorldRoot: TCastleAbstractRootTransform;
      const SoundPos: TVector3; const SourceLoudnessDb: Single): THearingEvaluation;

    { Scent breadcrumb management and sniffing. }
    procedure DropScentBreadcrumb(const ASourceTag: String; const AWorldPos: TVector3;
      const AInitialIntensity01: Single = 1.0);
    procedure StepSensoryDecay(const DtSec: Single);
    function SampleStrongestScent(out BestPos: TVector3; out BestSourceTag: String): Single;
    procedure ClearAllStimuli;

    function ActiveScentCount: Integer;
    function SensorySummaryBadge: String;

    property Awareness01: Single read FAwareness01;
    property LastStimulusPos: TVector3 read FLastStimulusPos;
    property LastStimulusSummary: String read FLastStimulusSummary;
  published
    property Preset: TSensoryPreset read FPreset write SetPreset default sppHumanGuardPatrol;
    property SensorYawDeg: Single read FSensorYawDeg write SetSensorYawDeg {$ifdef FPC}default 0.0{$endif};
    property EyeHeightMeters: Single read FEyeHeightMeters write SetEyeHeightMeters {$ifdef FPC}default 1.65{$endif};
    property SightRangeMeters: Single read FSightRangeMeters write SetSightRangeMeters {$ifdef FPC}default 26.0{$endif};
    property FovealHalfAngleDeg: Single read FFovealHalfAngleDeg write SetFovealHalfAngleDeg {$ifdef FPC}default 30.0{$endif};
    property PeripheralHalfAngleDeg: Single read FPeripheralHalfAngleDeg write SetPeripheralHalfAngleDeg {$ifdef FPC}default 75.0{$endif};
    property HearingThresholdDb: Single read FHearingThresholdDb write SetHearingThresholdDb {$ifdef FPC}default 35.0{$endif};
    property WallMufflePenaltyDb: Single read FWallMufflePenaltyDb write SetWallMufflePenaltyDb {$ifdef FPC}default 18.0{$endif};
    property ScentSniffRadiusMeters: Single read FScentSniffRadiusMeters write SetScentSniffRadiusMeters {$ifdef FPC}default 4.0{$endif};
    property ScentLifetimeSec: Single read FScentLifetimeSec write SetScentLifetimeSec {$ifdef FPC}default 12.0{$endif};
    property ShowPreviewGizmo: Boolean read FShowPreviewGizmo write SetShowPreviewGizmo default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

implementation

uses fpjson, jsonparser;

constructor TCastleSensoryPerception.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := sppHumanGuardPatrol;
  FSensorYawDeg := 0.0;
  FEyeHeightMeters := 1.65;
  FSightRangeMeters := 26.0;
  FFovealHalfAngleDeg := 30.0;
  FPeripheralHalfAngleDeg := 75.0;
  FHearingThresholdDb := 35.0;
  FWallMufflePenaltyDb := 18.0;
  FScentSniffRadiusMeters := 4.0;
  FScentLifetimeSec := 12.0;
  FShowPreviewGizmo := True;
  FAwareness01 := 0.0;
  FLastStimulusPos := TVector3.Zero;
  FLastStimulusSummary := 'Idle';
  FScentRingCursor := 0;
  FillChar(FCrumbs, SizeOf(FCrumbs), 0);
  RebuildPreviewGizmo;
end;

destructor TCastleSensoryPerception.Destroy;
begin
  inherited Destroy;
end;

function TCastleSensoryPerception.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'SensorYawDeg') or
     (PropertyName = 'EyeHeightMeters') or
     (PropertyName = 'SightRangeMeters') or
     (PropertyName = 'FovealHalfAngleDeg') or
     (PropertyName = 'PeripheralHalfAngleDeg') or
     (PropertyName = 'HearingThresholdDb') or
     (PropertyName = 'WallMufflePenaltyDb') or
     (PropertyName = 'ScentSniffRadiusMeters') or
     (PropertyName = 'ScentLifetimeSec') or
     (PropertyName = 'ShowPreviewGizmo') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleSensoryPerception.SensorForwardDir: TVector3;
var
  S, C: Single;
begin
  SinCos(DegToRad(FSensorYawDeg), S, C);
  Result := Vector3(S, 0.0, C);
end;

function TCastleSensoryPerception.SensorEyeWorldPos: TVector3;
begin
  if Parent <> nil then
    Result := WorldTranslation + Vector3(0.0, FEyeHeightMeters, 0.0)
  else
    Result := Translation + Vector3(0.0, FEyeHeightMeters, 0.0);
end;

function TCastleSensoryPerception.IsRayBlockedBySolidWall(
  const AWorldRoot: TCastleAbstractRootTransform;
  const RayOrigin, TargetPoint: TVector3;
  const IgnoreTarget: TCastleTransform): Boolean;
var
  Delta, RayDir: TVector3;
  TargetDist: Single;
  RayHit: TRayCollision;
  K: Integer;
  HitT: TCastleTransform;
begin
  Result := False;
  if AWorldRoot = nil then Exit;
  Delta := TargetPoint - RayOrigin;
  TargetDist := Delta.Length;
  if TargetDist < 0.25 then Exit;
  RayDir := Delta / TargetDist;

  RayHit := AWorldRoot.WorldRay(RayOrigin, RayDir);
  try
    if (RayHit = nil) or (RayHit.Distance >= TargetDist - 0.15) then
      Exit(False);
    for K := 0 to RayHit.Count - 1 do
    begin
      HitT := RayHit[K].Item;
      if (HitT = nil) or (HitT = AWorldRoot) or (HitT = Self) or (HitT = IgnoreTarget) then
        Continue;
      if csTransient in HitT.ComponentStyle then
        Continue;
      Exit(True);
    end;
  finally
    FreeAndNil(RayHit);
  end;
end;

function TCastleSensoryPerception.EvaluateSightTarget(
  const AWorldRoot: TCastleAbstractRootTransform;
  const TargetPos: TVector3;
  const TargetTransform: TCastleTransform): TSightEvaluation;
var
  EyePos, Delta, DirNorm, Fwd: TVector3;
  Dist, CosAng, AngleDeg, PeripheralMaxDist: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Zone := svzOutOfView;
  EyePos := SensorEyeWorldPos;
  Delta := TargetPos - EyePos;
  Dist := Delta.Length;
  Result.DistanceMeters := Dist;

  if Dist > FSightRangeMeters then
    Exit;

  if Dist < 1e-4 then
  begin
    AngleDeg := 0.0;
  end else
  begin
    DirNorm := Delta / Dist;
    Fwd := SensorForwardDir;
    CosAng := EnsureRange(TVector3.DotProduct(DirNorm, Fwd), -1.0, 1.0);
    AngleDeg := RadToDeg(ArcCos(CosAng));
  end;
  Result.OffAxisAngleDeg := AngleDeg;

  PeripheralMaxDist := FSightRangeMeters * 0.80;
  if AngleDeg > FPeripheralHalfAngleDeg then
    Exit;
  if (AngleDeg > FFovealHalfAngleDeg) and (Dist > PeripheralMaxDist) then
    Exit;

  if IsRayBlockedBySolidWall(AWorldRoot, EyePos, TargetPos, TargetTransform) then
  begin
    Result.Zone := svzOccludedByWall;
    Result.LineOfSightClear := False;
    Exit;
  end;

  Result.LineOfSightClear := True;
  Result.Detected := True;
  if AngleDeg <= FFovealHalfAngleDeg then
  begin
    Result.Zone := svzFovealLock;
    Result.AwarenessWeight := EnsureRange(1.0 - (Dist / Max(1.0, FSightRangeMeters)) * 0.35, 0.40, 1.0);
  end else
  begin
    Result.Zone := svzPeripheralGlimpse;
    Result.AwarenessWeight := 0.42 * EnsureRange(1.0 - (Dist / Max(1.0, PeripheralMaxDist)) * 0.5, 0.20, 1.0);
  end;

  FAwareness01 := EnsureRange(Max(FAwareness01, Result.AwarenessWeight), 0.0, 1.0);
  FLastStimulusPos := TargetPos;
  if Result.Zone = svzFovealLock then
    FLastStimulusSummary := Format('SIGHT_FOVEAL (%.1fm, %.1f deg)', [Dist, AngleDeg])
  else
    FLastStimulusSummary := Format('SIGHT_PERIPHERAL (%.1fm, %.1f deg)', [Dist, AngleDeg]);
end;

function TCastleSensoryPerception.EvaluateAcousticEvent(
  const AWorldRoot: TCastleAbstractRootTransform;
  const SoundPos: TVector3; const SourceLoudnessDb: Single): THearingEvaluation;
var
  EyePos: TVector3;
  Dist, AttenDb: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  EyePos := SensorEyeWorldPos;
  Dist := PointsDistance(EyePos, SoundPos);
  Result.DistanceMeters := Dist;

  { Inverse-square spherical spreading loss: -20 * log10(max(1m, r)) }
  AttenDb := SourceLoudnessDb - 20.0 * Log10(Max(1.0, Dist));
  Result.WallOccluded := IsRayBlockedBySolidWall(AWorldRoot, EyePos, SoundPos, nil);
  if Result.WallOccluded then
    AttenDb := AttenDb - FWallMufflePenaltyDb;

  Result.EffectiveDecibels := AttenDb;
  Result.Audible := AttenDb >= FHearingThresholdDb;
  if Result.Audible then
  begin
    Result.AwarenessWeight := EnsureRange((AttenDb - FHearingThresholdDb) / 35.0 + 0.25, 0.25, 1.0);
    FAwareness01 := EnsureRange(Max(FAwareness01, Result.AwarenessWeight), 0.0, 1.0);
    FLastStimulusPos := SoundPos;
    FLastStimulusSummary := Format('HEARING_DB (%.1f dB at %.1fm%s)', [
      AttenDb, Dist, BoolToStr(Result.WallOccluded, ' MUFFLED', '')]);
  end;
end;

procedure TCastleSensoryPerception.DropScentBreadcrumb(const ASourceTag: String;
  const AWorldPos: TVector3; const AInitialIntensity01: Single);
var
  Idx: Integer;
begin
  Idx := FScentRingCursor mod MaxScentBreadcrumbs;
  FCrumbs[Idx].Active := True;
  FCrumbs[Idx].SourceTag := Trim(ASourceTag);
  FCrumbs[Idx].WorldPos := AWorldPos;
  FCrumbs[Idx].Intensity01 := EnsureRange(AInitialIntensity01, 0.05, 1.0);
  FCrumbs[Idx].InitialSec := Max(0.5, FScentLifetimeSec);
  FCrumbs[Idx].RemainingSec := FCrumbs[Idx].InitialSec;
  FScentRingCursor := (Idx + 1) mod MaxScentBreadcrumbs;
end;

procedure TCastleSensoryPerception.StepSensoryDecay(const DtSec: Single);
var
  I: Integer;
  StepDt: Single;
begin
  StepDt := Max(0.0, DtSec);
  if StepDt <= 0.0 then Exit;

  FAwareness01 := Max(0.0, FAwareness01 - StepDt * 0.12);
  for I := 0 to MaxScentBreadcrumbs - 1 do
    if FCrumbs[I].Active then
    begin
      FCrumbs[I].RemainingSec := FCrumbs[I].RemainingSec - StepDt;
      if FCrumbs[I].RemainingSec <= 1e-4 then
      begin
        FCrumbs[I].Active := False;
        FCrumbs[I].RemainingSec := 0.0;
        FCrumbs[I].Intensity01 := 0.0;
      end else
        FCrumbs[I].Intensity01 := EnsureRange(
          FCrumbs[I].RemainingSec / Max(0.5, FCrumbs[I].InitialSec), 0.0, 1.0);
    end;
end;

function TCastleSensoryPerception.SampleStrongestScent(out BestPos: TVector3;
  out BestSourceTag: String): Single;
var
  I: Integer;
  OriginPos: TVector3;
  Dist, Score: Single;
begin
  Result := 0.0;
  BestPos := TVector3.Zero;
  BestSourceTag := '';
  if FScentSniffRadiusMeters <= 0.05 then Exit;

  if Parent <> nil then
    OriginPos := WorldTranslation
  else
    OriginPos := Translation;

  for I := 0 to MaxScentBreadcrumbs - 1 do
    if FCrumbs[I].Active then
    begin
      Dist := PointsDistance(OriginPos, FCrumbs[I].WorldPos);
      if Dist <= FScentSniffRadiusMeters then
      begin
        Score := FCrumbs[I].Intensity01 * (1.0 - (Dist / FScentSniffRadiusMeters) * 0.5);
        if Score > Result then
        begin
          Result := Score;
          BestPos := FCrumbs[I].WorldPos;
          BestSourceTag := FCrumbs[I].SourceTag;
        end;
      end;
    end;

  if Result > 0.0 then
  begin
    FAwareness01 := EnsureRange(Max(FAwareness01, Result * 0.65), 0.0, 1.0);
    FLastStimulusPos := BestPos;
    FLastStimulusSummary := Format('SCENT_TRAIL (%s strength=%.2f)', [BestSourceTag, Result]);
  end;
end;

procedure TCastleSensoryPerception.ClearAllStimuli;
begin
  FillChar(FCrumbs, SizeOf(FCrumbs), 0);
  FScentRingCursor := 0;
  FAwareness01 := 0.0;
  FLastStimulusSummary := 'Idle';
end;

function TCastleSensoryPerception.ActiveScentCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to MaxScentBreadcrumbs - 1 do
    if FCrumbs[I].Active then
      Inc(Result);
end;

function TCastleSensoryPerception.SensorySummaryBadge: String;
begin
  Result := Format('[Sense:Sight=%.0fm/%.0fdeg Hear>=%.0fdB Alert=%.0f%%]', [
    FSightRangeMeters, FFovealHalfAngleDeg, FHearingThresholdDb, FAwareness01 * 100.0]);
end;

procedure TCastleSensoryPerception.RebuildPreviewGizmo;
begin
  if FPreviewRoot = nil then
  begin
    FPreviewRoot := TCastleTransform.Create(Self);
    FPreviewRoot.SetTransient;
    FPreviewRoot.Pickable := False;
    FPreviewRoot.Name := 'SensoryGizmoTransient';
    Add(FPreviewRoot);

    FEyeSphere := TCastleBox.Create(FPreviewRoot);
    FEyeSphere.SetTransient;
    FEyeSphere.Pickable := False;
    FEyeSphere.Material := pmUnlit;
    FEyeSphere.Size := Vector3(0.32, 0.24, 0.32);
    FEyeSphere.Color := Vector4(1.0, 0.84, 0.18, 0.90);
    FPreviewRoot.Add(FEyeSphere);

    FFoveaBeam := TCastleBox.Create(FPreviewRoot);
    FFoveaBeam.SetTransient;
    FFoveaBeam.Pickable := False;
    FFoveaBeam.Material := pmUnlit;
    FFoveaBeam.Color := Vector4(0.20, 0.90, 0.55, 0.35);
    FPreviewRoot.Add(FFoveaBeam);
  end;

  FPreviewRoot.Exists := FShowPreviewGizmo;
  FPreviewRoot.Rotation := Vector4(0.0, 1.0, 0.0, DegToRad(FSensorYawDeg));
  FEyeSphere.Translation := Vector3(0.0, FEyeHeightMeters, 0.0);
  FFoveaBeam.Size := Vector3(0.18, 0.08, Min(6.0, FSightRangeMeters * 0.35));
  FFoveaBeam.Translation := Vector3(0.0, FEyeHeightMeters, FFoveaBeam.Size.Z * 0.5);
end;

procedure TCastleSensoryPerception.SetPreset(const Value: TSensoryPreset);
begin
  if FPreset = Value then Exit;
  FPreset := Value;
  case Value of
    sppHumanGuardPatrol:
      begin
        FEyeHeightMeters := 1.65;
        FSightRangeMeters := 26.0;
        FFovealHalfAngleDeg := 30.0;
        FPeripheralHalfAngleDeg := 75.0;
        FHearingThresholdDb := 35.0;
        FWallMufflePenaltyDb := 18.0;
        FScentSniffRadiusMeters := 2.0;
        FScentLifetimeSec := 8.0;
      end;
    sppBloodhoundTracker:
      begin
        FEyeHeightMeters := 0.55;
        FSightRangeMeters := 16.0;
        FFovealHalfAngleDeg := 22.0;
        FPeripheralHalfAngleDeg := 65.0;
        FHearingThresholdDb := 24.0;
        FWallMufflePenaltyDb := 12.0;
        FScentSniffRadiusMeters := 18.0;
        FScentLifetimeSec := 25.0;
      end;
    sppSecurityTurretOptic:
      begin
        FEyeHeightMeters := 2.10;
        FSightRangeMeters := 42.0;
        FFovealHalfAngleDeg := 45.0;
        FPeripheralHalfAngleDeg := 55.0;
        FHearingThresholdDb := 80.0;
        FWallMufflePenaltyDb := 25.0;
        FScentSniffRadiusMeters := 0.0;
        FScentLifetimeSec := 2.0;
      end;
    sppCustom: ;
  end;
  RebuildPreviewGizmo;
end;

procedure TCastleSensoryPerception.SetSensorYawDeg(const Value: Single);
begin
  if SameValue(FSensorYawDeg, Value, 1e-4) then Exit;
  FSensorYawDeg := Value;
  RebuildPreviewGizmo;
end;

procedure TCastleSensoryPerception.SetEyeHeightMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.1, 10.0);
  if SameValue(FEyeHeightMeters, Clamped, 1e-4) then Exit;
  FEyeHeightMeters := Clamped;
  FPreset := sppCustom;
  RebuildPreviewGizmo;
end;

procedure TCastleSensoryPerception.SetSightRangeMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 1.0, 250.0);
  if SameValue(FSightRangeMeters, Clamped, 1e-4) then Exit;
  FSightRangeMeters := Clamped;
  FPreset := sppCustom;
  RebuildPreviewGizmo;
end;

procedure TCastleSensoryPerception.SetFovealHalfAngleDeg(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 2.0, 175.0);
  if SameValue(FFovealHalfAngleDeg, Clamped, 1e-4) then Exit;
  FFovealHalfAngleDeg := Clamped;
  if FPeripheralHalfAngleDeg < Clamped then
    FPeripheralHalfAngleDeg := Clamped;
  FPreset := sppCustom;
end;

procedure TCastleSensoryPerception.SetPeripheralHalfAngleDeg(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, FFovealHalfAngleDeg, 179.0);
  if SameValue(FPeripheralHalfAngleDeg, Clamped, 1e-4) then Exit;
  FPeripheralHalfAngleDeg := Clamped;
  FPreset := sppCustom;
end;

procedure TCastleSensoryPerception.SetHearingThresholdDb(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 5.0, 130.0);
  if SameValue(FHearingThresholdDb, Clamped, 1e-4) then Exit;
  FHearingThresholdDb := Clamped;
  FPreset := sppCustom;
end;

procedure TCastleSensoryPerception.SetWallMufflePenaltyDb(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 60.0);
  if SameValue(FWallMufflePenaltyDb, Clamped, 1e-4) then Exit;
  FWallMufflePenaltyDb := Clamped;
  FPreset := sppCustom;
end;

procedure TCastleSensoryPerception.SetScentSniffRadiusMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 100.0);
  if SameValue(FScentSniffRadiusMeters, Clamped, 1e-4) then Exit;
  FScentSniffRadiusMeters := Clamped;
  FPreset := sppCustom;
end;

procedure TCastleSensoryPerception.SetScentLifetimeSec(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.5, 120.0);
  if SameValue(FScentLifetimeSec, Clamped, 1e-4) then Exit;
  FScentLifetimeSec := Clamped;
  FPreset := sppCustom;
end;

procedure TCastleSensoryPerception.SetShowPreviewGizmo(const Value: Boolean);
begin
  if FShowPreviewGizmo = Value then Exit;
  FShowPreviewGizmo := Value;
  RebuildPreviewGizmo;
end;

function TCastleSensoryPerception.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('sensorYawDeg', FSensorYawDeg);
    Obj.Add('eyeHeightMeters', FEyeHeightMeters);
    Obj.Add('sightRangeMeters', FSightRangeMeters);
    Obj.Add('fovealHalfAngleDeg', FFovealHalfAngleDeg);
    Obj.Add('peripheralHalfAngleDeg', FPeripheralHalfAngleDeg);
    Obj.Add('hearingThresholdDb', FHearingThresholdDb);
    Obj.Add('wallMufflePenaltyDb', FWallMufflePenaltyDb);
    Obj.Add('scentSniffRadiusMeters', FScentSniffRadiusMeters);
    Obj.Add('scentLifetimeSec', FScentLifetimeSec);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleSensoryPerception.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  SavedPreset: Integer;
begin
  if Trim(Value) = '' then Exit;
  try
    Data := GetJSON(Value);
  except
    Exit;
  end;
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    FSensorYawDeg := Obj.Get('sensorYawDeg', FSensorYawDeg);
    FEyeHeightMeters := EnsureRange(Obj.Get('eyeHeightMeters', FEyeHeightMeters), 0.1, 10.0);
    FSightRangeMeters := EnsureRange(Obj.Get('sightRangeMeters', FSightRangeMeters), 1.0, 250.0);
    FFovealHalfAngleDeg := EnsureRange(Obj.Get('fovealHalfAngleDeg', FFovealHalfAngleDeg), 2.0, 175.0);
    FPeripheralHalfAngleDeg := EnsureRange(Obj.Get('peripheralHalfAngleDeg', FPeripheralHalfAngleDeg), FFovealHalfAngleDeg, 179.0);
    FHearingThresholdDb := EnsureRange(Obj.Get('hearingThresholdDb', FHearingThresholdDb), 5.0, 130.0);
    FWallMufflePenaltyDb := EnsureRange(Obj.Get('wallMufflePenaltyDb', FWallMufflePenaltyDb), 0.0, 60.0);
    FScentSniffRadiusMeters := EnsureRange(Obj.Get('scentSniffRadiusMeters', FScentSniffRadiusMeters), 0.0, 100.0);
    FScentLifetimeSec := EnsureRange(Obj.Get('scentLifetimeSec', FScentLifetimeSec), 0.5, 120.0);
    SavedPreset := Obj.Get('preset', Ord(FPreset));
    if (SavedPreset >= Ord(Low(TSensoryPreset))) and (SavedPreset <= Ord(High(TSensoryPreset))) then
      FPreset := TSensoryPreset(SavedPreset);
    RebuildPreviewGizmo;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleSensoryPerception, 'AI Sensory Perception (Sight/Hearing/Scent)');
end.
