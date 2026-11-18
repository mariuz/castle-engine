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

{ Targeting System Preset Stack with Cone, Distance, WorldRay Line-of-Sight,
  Threat/LowHP Scoring, Aim Magnetism & Right-Stick Flick Switching (Phase 359). }
unit CastleTargetingSystem;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleClassUtils;

type
  { Built-in combat and support targeting preset profiles. }
  TTargetingPresetKind = (
    tpkCustom,
    tpkMeleeSoulsHardLockOn,
    tpkRangedAimMagnetism,
    tpkHealerFriendlyLowestHp
  );

  { Behavior marking a TCastleTransform as a candidate lock-on or aim-assist target. }
  TCastleTargetableBehavior = class(TCastleBehavior)
  private
    FFactionTag: String;
    FThreatPriorityTier: Integer;
    FHealthRatio: Single;
    FAimSocketOffsetY: Single;
    FTargetableEnabled: Boolean;
    procedure SetThreatPriorityTier(const AValue: Integer);
    procedure SetHealthRatio(const AValue: Single);
    procedure SetAimSocketOffsetY(const AValue: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function WorldAimPoint: TVector3;
  published
    property FactionTag: String read FFactionTag write FFactionTag;
    property ThreatPriorityTier: Integer read FThreatPriorityTier write SetThreatPriorityTier default 3;
    property HealthRatio: Single read FHealthRatio write SetHealthRatio {$ifdef FPC}default 1.0{$endif};
    property AimSocketOffsetY: Single read FAimSocketOffsetY write SetAimSocketOffsetY {$ifdef FPC}default 1.20{$endif};
    property TargetableEnabled: Boolean read FTargetableEnabled write FTargetableEnabled default True;
  end;

  { Per-candidate multi-stage filter and weighted score diagnostic record. }
  TTargetCandidateEval = record
    TargetName: String;
    TargetTransform: TCastleTransform;
    WorldAimPoint: TVector3;
    DistanceMeters: Single;
    ViewConeAngleDeg: Single;
    HasLineOfSight: Boolean;
    PassedFilters: Boolean;
    RejectedReason: String;
    TotalWeightedScore: Single;
  end;

  { Player/camera targeting behavior matching Unreal Engine 6.0+ UTargetingPreset
    (Gather -> Faction/Range/Cone/LoS Filter -> Weighted Score -> Stick-Flick Switch). }
  TCastleTargetingBehavior = class(TCastleBehavior)
  private
    FPreset: TTargetingPresetKind;
    FRequiredFactionTag: String;
    FMaxLockRangeMeters: Single;
    FMaxHalfConeAngleDeg: Single;
    FRequireLineOfSight: Boolean;
    FAngleWeight: Single;
    FDistanceWeight: Single;
    FThreatWeight: Single;
    FLowHealthWeight: Single;
    FMagnetismStrength: Single;
    FLockedTarget: TCastleTransform;
    FCandidates: array of TTargetCandidateEval;
    FValidCandidateCount: Integer;
    procedure SetPreset(const AValue: TTargetingPresetKind);
    procedure SetMaxLockRangeMeters(const AValue: Single);
    procedure SetMaxHalfConeAngleDeg(const AValue: Single);
    procedure SetMagnetismStrength(const AValue: Single);
    procedure SetLockedTarget(const AValue: TCastleTransform);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParamsOnly(const APreset: TTargetingPresetKind);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function EvaluateTargetingStack(const AOriginWorldPos, AViewForwardDir: TVector3;
      const AWorldRoot: TCastleAbstractRootTransform): TCastleTransform;
    function SwitchLockedTargetHorizontal(const AStickDirX: Single;
      const AOriginWorldPos, AViewForwardDir: TVector3;
      const AWorldRoot: TCastleAbstractRootTransform): TCastleTransform;
    function ComputeMagnetizedAimDir(const AOriginWorldPos, ARawAimDir: TVector3): TVector3;
    function CandidateCount: Integer;
    function GetCandidateEval(const AIndex: Integer): TTargetCandidateEval;
    function TargetingSummaryBadge: String;
    property LockedTarget: TCastleTransform read FLockedTarget write SetLockedTarget;
    property ValidCandidateCount: Integer read FValidCandidateCount;
  published
    property Preset: TTargetingPresetKind read FPreset write SetPreset default tpkMeleeSoulsHardLockOn;
    property RequiredFactionTag: String read FRequiredFactionTag write FRequiredFactionTag;
    property MaxLockRangeMeters: Single read FMaxLockRangeMeters write SetMaxLockRangeMeters {$ifdef FPC}default 24.0{$endif};
    property MaxHalfConeAngleDeg: Single read FMaxHalfConeAngleDeg write SetMaxHalfConeAngleDeg {$ifdef FPC}default 45.0{$endif};
    property RequireLineOfSight: Boolean read FRequireLineOfSight write FRequireLineOfSight default True;
    property MagnetismStrength: Single read FMagnetismStrength write SetMagnetismStrength {$ifdef FPC}default 0.35{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function TargetingPresetToString(const APreset: TTargetingPresetKind): String;

implementation

uses StrUtils, fpjson, jsonparser,
  CastleComponentSerialize;

function TargetingPresetToString(const APreset: TTargetingPresetKind): String;
begin
  case APreset of
    tpkCustom: Result := 'Custom Targeting Stack';
    tpkMeleeSoulsHardLockOn: Result := 'Melee Hard Lock-On (Enemy Threat+Cone)';
    tpkRangedAimMagnetism: Result := 'Ranged Aim-Assist Magnetism (Narrow Cone)';
    tpkHealerFriendlyLowestHp: Result := 'Healer Friendly Triage (Lowest HP)';
  end;
end;

{ TCastleTargetableBehavior -------------------------------------------------- }

constructor TCastleTargetableBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFactionTag := 'Enemy';
  FThreatPriorityTier := 3;
  FHealthRatio := 1.0;
  FAimSocketOffsetY := 1.20;
  FTargetableEnabled := True;
end;

procedure TCastleTargetableBehavior.SetThreatPriorityTier(const AValue: Integer);
begin
  FThreatPriorityTier := EnsureRange(AValue, 1, 10);
end;

procedure TCastleTargetableBehavior.SetHealthRatio(const AValue: Single);
begin
  FHealthRatio := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleTargetableBehavior.SetAimSocketOffsetY(const AValue: Single);
begin
  FAimSocketOffsetY := EnsureRange(AValue, -5.0, 10.0);
end;

function TCastleTargetableBehavior.WorldAimPoint: TVector3;
begin
  if Parent <> nil then
    Result := Parent.WorldTranslation + Vector3(0.0, FAimSocketOffsetY, 0.0)
  else
    Result := Vector3(0.0, FAimSocketOffsetY, 0.0);
end;

{ TCastleTargetingBehavior --------------------------------------------------- }

constructor TCastleTargetingBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := tpkMeleeSoulsHardLockOn;
  FRequireLineOfSight := True;
  ApplyPresetParamsOnly(tpkMeleeSoulsHardLockOn);
end;

destructor TCastleTargetingBehavior.Destroy;
begin
  LockedTarget := nil;
  inherited Destroy;
end;

procedure TCastleTargetingBehavior.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FLockedTarget) then
    FLockedTarget := nil;
end;

procedure TCastleTargetingBehavior.SetLockedTarget(const AValue: TCastleTransform);
begin
  if FLockedTarget = AValue then Exit;
  if FLockedTarget <> nil then FLockedTarget.RemoveFreeNotification(Self);
  FLockedTarget := AValue;
  if FLockedTarget <> nil then FLockedTarget.FreeNotification(Self);
end;

procedure TCastleTargetingBehavior.ApplyPresetParamsOnly(const APreset: TTargetingPresetKind);
begin
  case APreset of
    tpkMeleeSoulsHardLockOn, tpkCustom:
      begin
        FRequiredFactionTag := 'Enemy';
        FMaxLockRangeMeters := 24.0;
        FMaxHalfConeAngleDeg := 45.0;
        FAngleWeight := 0.35;
        FDistanceWeight := 0.30;
        FThreatWeight := 0.35;
        FLowHealthWeight := 0.0;
        FMagnetismStrength := 0.35;
      end;
    tpkRangedAimMagnetism:
      begin
        FRequiredFactionTag := 'Enemy';
        FMaxLockRangeMeters := 48.0;
        FMaxHalfConeAngleDeg := 22.0;
        FAngleWeight := 0.65;
        FDistanceWeight := 0.20;
        FThreatWeight := 0.15;
        FLowHealthWeight := 0.0;
        FMagnetismStrength := 0.55;
      end;
    tpkHealerFriendlyLowestHp:
      begin
        FRequiredFactionTag := 'Friendly';
        FMaxLockRangeMeters := 30.0;
        FMaxHalfConeAngleDeg := 75.0;
        FAngleWeight := 0.15;
        FDistanceWeight := 0.15;
        FThreatWeight := 0.0;
        FLowHealthWeight := 0.70;
        FMagnetismStrength := 0.25;
      end;
  end;
end;

procedure TCastleTargetingBehavior.SetPreset(const AValue: TTargetingPresetKind);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> tpkCustom then
    ApplyPresetParamsOnly(AValue);
end;

procedure TCastleTargetingBehavior.SetMaxLockRangeMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 1.0, 250.0);
  if SameValue(FMaxLockRangeMeters, V, 1e-4) then Exit;
  FMaxLockRangeMeters := V;
end;

procedure TCastleTargetingBehavior.SetMaxHalfConeAngleDeg(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 2.0, 180.0);
  if SameValue(FMaxHalfConeAngleDeg, V, 1e-4) then Exit;
  FMaxHalfConeAngleDeg := V;
end;

procedure TCastleTargetingBehavior.SetMagnetismStrength(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FMagnetismStrength, V, 1e-4) then Exit;
  FMagnetismStrength := V;
end;

function TCastleTargetingBehavior.EvaluateTargetingStack(
  const AOriginWorldPos, AViewForwardDir: TVector3;
  const AWorldRoot: TCastleAbstractRootTransform): TCastleTransform;
var
  RootWorld: TCastleAbstractRootTransform;
  FwdDir, ToCand, AimPt: TVector3;
  Dist, AngDeg, BestScore, AngTerm, DistTerm, ThreatTerm, HpTerm: Single;
  BestTarget: TCastleTransform;

  function CheckLineOfSight(const TargetActor: TCastleTransform; const TargetAim: TVector3): Boolean;
  var
    RayVec: TVector3;
    RayLen: Single;
    RayHit: TRayCollision;
    K: Integer;
    HitItem: TCastleTransform;
  begin
    Result := True;
    if (not FRequireLineOfSight) or (RootWorld = nil) then Exit;
    RayVec := TargetAim - AOriginWorldPos;
    RayLen := RayVec.Length;
    if RayLen <= 0.15 then Exit;

    RayHit := RootWorld.WorldRay(AOriginWorldPos, RayVec * (1.0 / RayLen));
    try
      if (RayHit <> nil) and (RayHit.Distance < RayLen - 0.15) then
      begin
        for K := 0 to RayHit.Count - 1 do
        begin
          HitItem := RayHit[K].Item;
          if (HitItem = nil) or (HitItem = RootWorld) or
             (HitItem = Parent) or (HitItem = TargetActor) then
            Continue;
          if csTransient in HitItem.ComponentStyle then
            Continue;
          Exit(False);
        end;
      end;
    finally
      FreeAndNil(RayHit);
    end;
  end;

  procedure ScanNode(const Node: TCastleTransform);
  var
    I, Idx: Integer;
    TB: TCastleTargetableBehavior;
    Ev: TTargetCandidateEval;
  begin
    if Node = nil then Exit;
    if (Node <> RootWorld) and (csTransient in Node.ComponentStyle) then Exit;

    if Node <> Parent then
    begin
      TB := Node.FindBehavior(TCastleTargetableBehavior) as TCastleTargetableBehavior;
      if (TB <> nil) and TB.TargetableEnabled then
      begin
        FillChar(Ev, SizeOf(Ev), 0);
        Ev.TargetName := Node.Name;
        Ev.TargetTransform := Node;
        AimPt := TB.WorldAimPoint;
        Ev.WorldAimPoint := AimPt;
        ToCand := AimPt - AOriginWorldPos;
        Dist := ToCand.Length;
        Ev.DistanceMeters := Dist;
        if Dist > 1e-5 then
          AngDeg := RadToDeg(ArcCos(EnsureRange(TVector3.DotProduct(ToCand * (1.0 / Dist), FwdDir), -1.0, 1.0)))
        else
          AngDeg := 0.0;
        Ev.ViewConeAngleDeg := AngDeg;
        Ev.HasLineOfSight := True;

        if (Trim(FRequiredFactionTag) <> '') and (not SameText(TB.FactionTag, FRequiredFactionTag)) then
          Ev.RejectedReason := 'FACTION_FILTER'
        else if Dist > FMaxLockRangeMeters then
          Ev.RejectedReason := 'OUT_OF_RANGE'
        else if AngDeg > FMaxHalfConeAngleDeg then
          Ev.RejectedReason := 'OUTSIDE_VIEW_CONE'
        else if not CheckLineOfSight(Node, AimPt) then
        begin
          Ev.HasLineOfSight := False;
          Ev.RejectedReason := 'BLOCKED_LINE_OF_SIGHT';
        end else
        begin
          Ev.PassedFilters := True;
          AngTerm := 1.0 - (AngDeg / Max(1.0, FMaxHalfConeAngleDeg));
          DistTerm := 1.0 - (Dist / Max(1.0, FMaxLockRangeMeters));
          ThreatTerm := TB.ThreatPriorityTier / 10.0;
          HpTerm := 1.0 - TB.HealthRatio;
          Ev.TotalWeightedScore :=
            FAngleWeight * AngTerm +
            FDistanceWeight * DistTerm +
            FThreatWeight * ThreatTerm +
            FLowHealthWeight * HpTerm;

          Inc(FValidCandidateCount);
          if Ev.TotalWeightedScore > BestScore then
          begin
            BestScore := Ev.TotalWeightedScore;
            BestTarget := Node;
          end;
        end;

        Idx := Length(FCandidates);
        SetLength(FCandidates, Idx + 1);
        FCandidates[Idx] := Ev;
      end;
    end;

    for I := 0 to Node.Count - 1 do
      ScanNode(Node[I]);
  end;

begin
  SetLength(FCandidates, 0);
  FValidCandidateCount := 0;
  BestScore := -1e30;
  BestTarget := nil;

  if AWorldRoot <> nil then
    RootWorld := AWorldRoot
  else if Parent <> nil then
    RootWorld := Parent.World
  else
    RootWorld := nil;

  if AViewForwardDir.LengthSqr > 1e-6 then
    FwdDir := AViewForwardDir.Normalize
  else
    FwdDir := Vector3(0, 0, -1);

  if RootWorld <> nil then
    ScanNode(RootWorld);

  LockedTarget := BestTarget;
  Result := BestTarget;
end;

function TCastleTargetingBehavior.SwitchLockedTargetHorizontal(const AStickDirX: Single;
  const AOriginWorldPos, AViewForwardDir: TVector3;
  const AWorldRoot: TCastleAbstractRootTransform): TCastleTransform;
var
  PrevLocked, BestFlick: TCastleTransform;
  FwdDir, RightAxis, CurDir, CandDir: TVector3;
  CurX, CandX, DeltaX, BestDeltaX: Single;
  I: Integer;
begin
  PrevLocked := FLockedTarget;
  EvaluateTargetingStack(AOriginWorldPos, AViewForwardDir, AWorldRoot);
  if (PrevLocked = nil) or (Abs(AStickDirX) < 0.05) then
    Exit(FLockedTarget);

  if AViewForwardDir.LengthSqr > 1e-6 then
    FwdDir := AViewForwardDir.Normalize
  else
    FwdDir := Vector3(0, 0, -1);
  RightAxis := TVector3.CrossProduct(FwdDir, Vector3(0, 1, 0));
  if RightAxis.LengthSqr < 1e-6 then
    RightAxis := Vector3(1, 0, 0)
  else
    RightAxis := RightAxis.Normalize;

  CurDir := (PrevLocked.WorldTranslation - AOriginWorldPos);
  if CurDir.LengthSqr > 1e-6 then CurDir := CurDir.Normalize;
  CurX := TVector3.DotProduct(CurDir, RightAxis);

  BestFlick := nil;
  BestDeltaX := 1e30;
  for I := 0 to High(FCandidates) do
    if FCandidates[I].PassedFilters and (FCandidates[I].TargetTransform <> PrevLocked) then
    begin
      CandDir := FCandidates[I].WorldAimPoint - AOriginWorldPos;
      if CandDir.LengthSqr > 1e-6 then CandDir := CandDir.Normalize;
      CandX := TVector3.DotProduct(CandDir, RightAxis);
      DeltaX := (CandX - CurX) * Sign(AStickDirX);
      if (DeltaX > 0.02) and (DeltaX < BestDeltaX) then
      begin
        BestDeltaX := DeltaX;
        BestFlick := FCandidates[I].TargetTransform;
      end;
    end;

  if BestFlick <> nil then
    LockedTarget := BestFlick
  else
    LockedTarget := PrevLocked;
  Result := FLockedTarget;
end;

function TCastleTargetingBehavior.ComputeMagnetizedAimDir(
  const AOriginWorldPos, ARawAimDir: TVector3): TVector3;
var
  RawN, ToTarget, Blended: TVector3;
  TB: TCastleTargetableBehavior;
begin
  if ARawAimDir.LengthSqr > 1e-6 then
    RawN := ARawAimDir.Normalize
  else
    RawN := Vector3(0, 0, -1);

  if (FLockedTarget = nil) or (FMagnetismStrength <= 0.001) then
    Exit(RawN);

  TB := FLockedTarget.FindBehavior(TCastleTargetableBehavior) as TCastleTargetableBehavior;
  if TB <> nil then
    ToTarget := TB.WorldAimPoint - AOriginWorldPos
  else
    ToTarget := FLockedTarget.WorldTranslation - AOriginWorldPos;

  if ToTarget.LengthSqr < 1e-6 then
    Exit(RawN);
  Blended := Lerp(FMagnetismStrength, RawN, ToTarget.Normalize);
  if Blended.LengthSqr > 1e-6 then
    Result := Blended.Normalize
  else
    Result := RawN;
end;

function TCastleTargetingBehavior.CandidateCount: Integer;
begin
  Result := Length(FCandidates);
end;

function TCastleTargetingBehavior.GetCandidateEval(const AIndex: Integer): TTargetCandidateEval;
begin
  if (AIndex >= 0) and (AIndex < Length(FCandidates)) then
    Result := FCandidates[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleTargetingBehavior.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('faction', FRequiredFactionTag);
    Obj.Add('range', FMaxLockRangeMeters);
    Obj.Add('cone', FMaxHalfConeAngleDeg);
    Obj.Add('los', FRequireLineOfSight);
    Obj.Add('mag', FMagnetismStrength);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleTargetingBehavior.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      PresetOrd := Obj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TTargetingPresetKind))) and
         (PresetOrd <= Ord(High(TTargetingPresetKind))) then
      begin
        FPreset := TTargetingPresetKind(PresetOrd);
        if FPreset <> tpkCustom then
          ApplyPresetParamsOnly(FPreset);
      end;
      FRequiredFactionTag := Obj.Get('faction', FRequiredFactionTag);
      FMaxLockRangeMeters := EnsureRange(Obj.Get('range', FMaxLockRangeMeters), 1.0, 250.0);
      FMaxHalfConeAngleDeg := EnsureRange(Obj.Get('cone', FMaxHalfConeAngleDeg), 2.0, 180.0);
      FRequireLineOfSight := Obj.Get('los', FRequireLineOfSight);
      FMagnetismStrength := EnsureRange(Obj.Get('mag', FMagnetismStrength), 0.0, 1.0);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleTargetingBehavior.TargetingSummaryBadge: String;
var
  LockName: String;
begin
  if FLockedTarget <> nil then
    LockName := FLockedTarget.Name
  else
    LockName := 'None';
  Result := Format('[Target:%s (%d valid)]', [LockName, FValidCandidateCount]);
end;

initialization
  RegisterSerializableComponent(TCastleTargetableBehavior, ['Combat & AI', 'Targetable Lock-On Candidate']);
  RegisterSerializableComponent(TCastleTargetingBehavior, ['Combat & AI', 'Targeting System Preset Behavior']);
end.
