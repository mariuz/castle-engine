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

{ Skeletal Footstep Decal, Terrain-Matched Dust/Splash & Acoustic Surface Studio (Phase 380).
  Detects left/right stride phase crossings (0.25 Left, 0.75 Right), probes ground
  contact height and surface material via downward WorldRay, computes speed- and
  material-scaled acoustic impact gain + particle bursts, and manages a transient
  24-slot footprint decal ring buffer. }
unit CastleFootstepDirector;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions, CastleColors,
  CastleClassUtils, CastleComponentSerialize;

const
  MaxFootprintDecals = 24;

type
  TFootstepPreset = (
    fdpArmoredKnightMarch,
    fdpStealthRogueSneak,
    fdpSprintingRangerSplash,
    fdpCustom
  );

  TFootSide = (
    fsLeftFoot,
    fsRightFoot
  );

  TFootSurfaceMaterial = (
    fsmStoneCobble,
    fsmSoftSnow,
    fsmShallowPuddle,
    fsmForestLoam,
    fsmMetalGrating
  );

  TFootprintDecalEntry = record
    Active: Boolean;
    FootSide: TFootSide;
    SurfaceMaterial: TFootSurfaceMaterial;
    WorldPos: TVector3;
    YawRad: Single;
    AcousticGain01: Single;
    ParticleCount: Integer;
    RemainingLifeSec: Single;
  end;

  { Stride-phase footstep detector, WorldRay surface matcher & footprint decal ring. }
  TCastleFootstepDirector = class(TCastleTransform)
  private
    FPreset: TFootstepPreset;
    FStrideLengthMeters: Single;
    FStanceWidthMeters: Single;
    FDecalLifetimeSec: Single;
    FArmorWeightAcousticMult: Single;
    FMinMoveSpeedMps: Single;
    FShowFootprintDecals: Boolean;
    FGaitPhase01: Single;
    FDecalRingCursor: Integer;
    FTotalFootstepsTriggered: Integer;
    FDecals: array[0..MaxFootprintDecals - 1] of TFootprintDecalEntry;
    FLastFootstep: TFootprintDecalEntry;
    FPreviewRoot: TCastleTransform;
    FDecalBoxes: array[0..MaxFootprintDecals - 1] of TCastleBox;
    procedure SetPreset(const Value: TFootstepPreset);
    procedure SetStrideLengthMeters(const Value: Single);
    procedure SetStanceWidthMeters(const Value: Single);
    procedure SetDecalLifetimeSec(const Value: Single);
    procedure SetArmorWeightAcousticMult(const Value: Single);
    procedure SetMinMoveSpeedMps(const Value: Single);
    procedure SetShowFootprintDecals(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure RebuildDecalMeshes;
    procedure TriggerSingleFootStrike(const AWorldRoot: TCastleAbstractRootTransform;
      const ASide: TFootSide; const ActorPos: TVector3;
      const ActorYawDeg, MoveSpeedMps: Single);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function SurfaceMaterialName(const AMat: TFootSurfaceMaterial): String;

    { Probe ground height and surface material tag directly under ProbeXZ via WorldRay. }
    function SampleGroundSurfaceAt(const AWorldRoot: TCastleAbstractRootTransform;
      const ProbePos: TVector3; out GroundY: Single): TFootSurfaceMaterial;

    { Advance gait cycle and fire Left (0.25) / Right (0.75) foot strikes. Returns strikes fired. }
    function AdvanceLocomotionCycle(const AWorldRoot: TCastleAbstractRootTransform;
      const ActorPos: TVector3; const ActorYawDeg, HorizontalSpeedMps, DtSec: Single): Integer;

    procedure ClearFootprints;
    function ActiveDecalCount: Integer;
    function GetDecalSlot(const Index: Integer): TFootprintDecalEntry;
    function FootstepSummaryBadge: String;

    property GaitPhase01: Single read FGaitPhase01;
    property TotalFootstepsTriggered: Integer read FTotalFootstepsTriggered;
    property LastFootstep: TFootprintDecalEntry read FLastFootstep;
  published
    property Preset: TFootstepPreset read FPreset write SetPreset default fdpArmoredKnightMarch;
    property StrideLengthMeters: Single read FStrideLengthMeters write SetStrideLengthMeters {$ifdef FPC}default 1.80{$endif};
    property StanceWidthMeters: Single read FStanceWidthMeters write SetStanceWidthMeters {$ifdef FPC}default 0.34{$endif};
    property DecalLifetimeSec: Single read FDecalLifetimeSec write SetDecalLifetimeSec {$ifdef FPC}default 8.0{$endif};
    property ArmorWeightAcousticMult: Single read FArmorWeightAcousticMult write SetArmorWeightAcousticMult {$ifdef FPC}default 1.15{$endif};
    property MinMoveSpeedMps: Single read FMinMoveSpeedMps write SetMinMoveSpeedMps {$ifdef FPC}default 0.25{$endif};
    property ShowFootprintDecals: Boolean read FShowFootprintDecals write SetShowFootprintDecals default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

implementation

uses fpjson, jsonparser;

constructor TCastleFootstepDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := fdpArmoredKnightMarch;
  FStrideLengthMeters := 1.80;
  FStanceWidthMeters := 0.34;
  FDecalLifetimeSec := 8.0;
  FArmorWeightAcousticMult := 1.15;
  FMinMoveSpeedMps := 0.25;
  FShowFootprintDecals := True;
  FGaitPhase01 := 0.0;
  FDecalRingCursor := 0;
  FTotalFootstepsTriggered := 0;
  FillChar(FDecals, SizeOf(FDecals), 0);
  FillChar(FLastFootstep, SizeOf(FLastFootstep), 0);
  RebuildDecalMeshes;
end;

destructor TCastleFootstepDirector.Destroy;
begin
  inherited Destroy;
end;

function TCastleFootstepDirector.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'StrideLengthMeters') or
     (PropertyName = 'StanceWidthMeters') or
     (PropertyName = 'DecalLifetimeSec') or
     (PropertyName = 'ArmorWeightAcousticMult') or
     (PropertyName = 'MinMoveSpeedMps') or
     (PropertyName = 'ShowFootprintDecals') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleFootstepDirector.SurfaceMaterialName(
  const AMat: TFootSurfaceMaterial): String;
begin
  case AMat of
    fsmStoneCobble: Result := 'StoneCobble';
    fsmSoftSnow: Result := 'SoftSnow';
    fsmShallowPuddle: Result := 'ShallowPuddle';
    fsmForestLoam: Result := 'ForestLoam';
    fsmMetalGrating: Result := 'MetalGrating';
  end;
end;

function TCastleFootstepDirector.SampleGroundSurfaceAt(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ProbePos: TVector3; out GroundY: Single): TFootSurfaceMaterial;
var
  RayOrigin: TVector3;
  RayHit: TRayCollision;
  K: Integer;
  HitT: TCastleTransform;
  LowerName: String;
begin
  Result := fsmStoneCobble;
  GroundY := ProbePos.Y;
  if AWorldRoot = nil then Exit;

  RayOrigin := ProbePos + Vector3(0.0, 1.50, 0.0);
  RayHit := AWorldRoot.WorldRay(RayOrigin, Vector3(0.0, -1.0, 0.0));
  try
    if (RayHit = nil) or (RayHit.Distance > 6.0) then
      Exit;
    for K := 0 to RayHit.Count - 1 do
    begin
      HitT := RayHit[K].Item;
      if (HitT = nil) or (HitT = AWorldRoot) or (HitT = Self) then Continue;
      if csTransient in HitT.ComponentStyle then Continue;

      GroundY := RayOrigin.Y - RayHit.Distance;
      LowerName := LowerCase(HitT.Name);
      if Pos('snow', LowerName) > 0 then
        Exit(fsmSoftSnow)
      else if (Pos('puddle', LowerName) > 0) or (Pos('water', LowerName) > 0) then
        Exit(fsmShallowPuddle)
      else if (Pos('metal', LowerName) > 0) or (Pos('grate', LowerName) > 0) then
        Exit(fsmMetalGrating)
      else if (Pos('grass', LowerName) > 0) or (Pos('loam', LowerName) > 0) or (Pos('dirt', LowerName) > 0) then
        Exit(fsmForestLoam)
      else
        Exit(fsmStoneCobble);
    end;
  finally
    FreeAndNil(RayHit);
  end;
end;

procedure TCastleFootstepDirector.TriggerSingleFootStrike(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ASide: TFootSide; const ActorPos: TVector3;
  const ActorYawDeg, MoveSpeedMps: Single);
var
  YawRad, S, C, SideSign, GroundY, MatAcousticMult, RawGain: Single;
  RightVec, FootWorld: TVector3;
  Surf: TFootSurfaceMaterial;
  SlotIdx, Particles: Integer;
begin
  YawRad := DegToRad(ActorYawDeg);
  SinCos(YawRad, S, C);
  RightVec := Vector3(C, 0.0, -S);
  if ASide = fsLeftFoot then
    SideSign := -0.5
  else
    SideSign := +0.5;

  FootWorld := ActorPos + RightVec * (FStanceWidthMeters * SideSign);
  Surf := SampleGroundSurfaceAt(AWorldRoot, FootWorld, GroundY);
  FootWorld.Y := GroundY + 0.015;

  case Surf of
    fsmSoftSnow:
      begin
        MatAcousticMult := 0.45;
        Particles := 10;
      end;
    fsmShallowPuddle:
      begin
        MatAcousticMult := 0.95;
        Particles := 18;
      end;
    fsmMetalGrating:
      begin
        MatAcousticMult := 1.35;
        Particles := 3;
      end;
    fsmForestLoam:
      begin
        MatAcousticMult := 0.65;
        Particles := 7;
      end;
  else
    MatAcousticMult := 0.85;
    Particles := 5;
  end;

  RawGain := (MoveSpeedMps / 6.0) * FArmorWeightAcousticMult * MatAcousticMult;
  SlotIdx := FDecalRingCursor mod MaxFootprintDecals;
  FDecals[SlotIdx].Active := True;
  FDecals[SlotIdx].FootSide := ASide;
  FDecals[SlotIdx].SurfaceMaterial := Surf;
  FDecals[SlotIdx].WorldPos := FootWorld;
  FDecals[SlotIdx].YawRad := YawRad;
  FDecals[SlotIdx].AcousticGain01 := EnsureRange(RawGain, 0.05, 1.0);
  FDecals[SlotIdx].ParticleCount := Max(1, Round(Particles * EnsureRange(MoveSpeedMps / 4.0, 0.4, 2.0)));
  FDecals[SlotIdx].RemainingLifeSec := FDecalLifetimeSec;

  FLastFootstep := FDecals[SlotIdx];
  FDecalRingCursor := (SlotIdx + 1) mod MaxFootprintDecals;
  Inc(FTotalFootstepsTriggered);
end;

function TCastleFootstepDirector.AdvanceLocomotionCycle(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ActorPos: TVector3; const ActorYawDeg, HorizontalSpeedMps, DtSec: Single): Integer;
var
  I, StartWrap, EndWrap, W: Integer;
  StepDt, OldUnwrapped, NewUnwrapped, DeltaCycles: Single;
begin
  Result := 0;
  StepDt := Max(0.0, DtSec);
  if StepDt <= 0.0 then Exit;

  { Decay existing footprint decals }
  for I := 0 to MaxFootprintDecals - 1 do
    if FDecals[I].Active then
    begin
      FDecals[I].RemainingLifeSec := FDecals[I].RemainingLifeSec - StepDt;
      if FDecals[I].RemainingLifeSec <= 1e-4 then
        FDecals[I].Active := False;
    end;

  if HorizontalSpeedMps < FMinMoveSpeedMps then
  begin
    RebuildDecalMeshes;
    Exit(0);
  end;

  DeltaCycles := (HorizontalSpeedMps / Max(0.35, FStrideLengthMeters)) * StepDt;
  OldUnwrapped := FGaitPhase01;
  NewUnwrapped := OldUnwrapped + DeltaCycles;

  StartWrap := Floor(OldUnwrapped);
  EndWrap := Floor(NewUnwrapped);
  for W := StartWrap to EndWrap do
  begin
    if (OldUnwrapped < W + 0.25) and (NewUnwrapped >= W + 0.25) then
    begin
      TriggerSingleFootStrike(AWorldRoot, fsLeftFoot, ActorPos, ActorYawDeg, HorizontalSpeedMps);
      Inc(Result);
    end;
    if (OldUnwrapped < W + 0.75) and (NewUnwrapped >= W + 0.75) then
    begin
      TriggerSingleFootStrike(AWorldRoot, fsRightFoot, ActorPos, ActorYawDeg, HorizontalSpeedMps);
      Inc(Result);
    end;
  end;

  FGaitPhase01 := Frac(NewUnwrapped);
  RebuildDecalMeshes;
end;

procedure TCastleFootstepDirector.ClearFootprints;
begin
  FillChar(FDecals, SizeOf(FDecals), 0);
  FillChar(FLastFootstep, SizeOf(FLastFootstep), 0);
  FGaitPhase01 := 0.0;
  FDecalRingCursor := 0;
  FTotalFootstepsTriggered := 0;
  RebuildDecalMeshes;
end;

function TCastleFootstepDirector.ActiveDecalCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to MaxFootprintDecals - 1 do
    if FDecals[I].Active then
      Inc(Result);
end;

function TCastleFootstepDirector.GetDecalSlot(const Index: Integer): TFootprintDecalEntry;
begin
  if (Index >= 0) and (Index < MaxFootprintDecals) then
    Result := FDecals[Index]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleFootstepDirector.FootstepSummaryBadge: String;
begin
  Result := Format('[Steps:%d total (%d decals) %s]', [
    FTotalFootstepsTriggered, ActiveDecalCount,
    SurfaceMaterialName(FLastFootstep.SurfaceMaterial)]);
end;

procedure TCastleFootstepDirector.RebuildDecalMeshes;
var
  I: Integer;
  OriginW: TVector3;
begin
  if FPreviewRoot = nil then
  begin
    FPreviewRoot := TCastleTransform.Create(Self);
    FPreviewRoot.SetTransient;
    FPreviewRoot.Pickable := False;
    FPreviewRoot.Name := 'FootstepDecalsTransient';
    Add(FPreviewRoot);

    for I := 0 to MaxFootprintDecals - 1 do
    begin
      FDecalBoxes[I] := TCastleBox.Create(FPreviewRoot);
      FDecalBoxes[I].SetTransient;
      FDecalBoxes[I].Pickable := False;
      FDecalBoxes[I].Material := pmUnlit;
      FDecalBoxes[I].Size := Vector3(0.13, 0.02, 0.28);
      FDecalBoxes[I].Exists := False;
      FPreviewRoot.Add(FDecalBoxes[I]);
    end;
  end;

  if Parent <> nil then
    OriginW := WorldTranslation
  else
    OriginW := Translation;

  FPreviewRoot.Exists := FShowFootprintDecals;
  for I := 0 to MaxFootprintDecals - 1 do
    if FShowFootprintDecals and FDecals[I].Active then
    begin
      FDecalBoxes[I].Exists := True;
      FDecalBoxes[I].Translation := FDecals[I].WorldPos - OriginW;
      FDecalBoxes[I].Rotation := Vector4(0.0, 1.0, 0.0, FDecals[I].YawRad);
      case FDecals[I].SurfaceMaterial of
        fsmSoftSnow: FDecalBoxes[I].Color := Vector4(0.75, 0.88, 1.0, 0.85);
        fsmShallowPuddle: FDecalBoxes[I].Color := Vector4(0.18, 0.62, 0.96, 0.85);
        fsmMetalGrating: FDecalBoxes[I].Color := Vector4(0.95, 0.72, 0.22, 0.85);
        fsmForestLoam: FDecalBoxes[I].Color := Vector4(0.46, 0.34, 0.20, 0.85);
      else
        FDecalBoxes[I].Color := Vector4(0.35, 0.35, 0.38, 0.85);
      end;
    end else
      FDecalBoxes[I].Exists := False;
end;

procedure TCastleFootstepDirector.SetPreset(const Value: TFootstepPreset);
begin
  if FPreset = Value then Exit;
  FPreset := Value;
  case Value of
    fdpArmoredKnightMarch:
      begin
        FStrideLengthMeters := 1.80;
        FStanceWidthMeters := 0.34;
        FDecalLifetimeSec := 8.0;
        FArmorWeightAcousticMult := 1.25;
        FMinMoveSpeedMps := 0.25;
      end;
    fdpStealthRogueSneak:
      begin
        FStrideLengthMeters := 1.35;
        FStanceWidthMeters := 0.26;
        FDecalLifetimeSec := 5.0;
        FArmorWeightAcousticMult := 0.35;
        FMinMoveSpeedMps := 0.20;
      end;
    fdpSprintingRangerSplash:
      begin
        FStrideLengthMeters := 2.30;
        FStanceWidthMeters := 0.32;
        FDecalLifetimeSec := 10.0;
        FArmorWeightAcousticMult := 0.90;
        FMinMoveSpeedMps := 0.25;
      end;
    fdpCustom: ;
  end;
end;

procedure TCastleFootstepDirector.SetStrideLengthMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.35, 6.0);
  if SameValue(FStrideLengthMeters, Clamped, 1e-4) then Exit;
  FStrideLengthMeters := Clamped;
  FPreset := fdpCustom;
end;

procedure TCastleFootstepDirector.SetStanceWidthMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.08, 2.0);
  if SameValue(FStanceWidthMeters, Clamped, 1e-4) then Exit;
  FStanceWidthMeters := Clamped;
  FPreset := fdpCustom;
end;

procedure TCastleFootstepDirector.SetDecalLifetimeSec(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.5, 60.0);
  if SameValue(FDecalLifetimeSec, Clamped, 1e-4) then Exit;
  FDecalLifetimeSec := Clamped;
  FPreset := fdpCustom;
end;

procedure TCastleFootstepDirector.SetArmorWeightAcousticMult(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.1, 3.0);
  if SameValue(FArmorWeightAcousticMult, Clamped, 1e-4) then Exit;
  FArmorWeightAcousticMult := Clamped;
  FPreset := fdpCustom;
end;

procedure TCastleFootstepDirector.SetMinMoveSpeedMps(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.05, 5.0);
  if SameValue(FMinMoveSpeedMps, Clamped, 1e-4) then Exit;
  FMinMoveSpeedMps := Clamped;
  FPreset := fdpCustom;
end;

procedure TCastleFootstepDirector.SetShowFootprintDecals(const Value: Boolean);
begin
  if FShowFootprintDecals = Value then Exit;
  FShowFootprintDecals := Value;
  RebuildDecalMeshes;
end;

function TCastleFootstepDirector.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('strideLengthMeters', FStrideLengthMeters);
    Obj.Add('stanceWidthMeters', FStanceWidthMeters);
    Obj.Add('decalLifetimeSec', FDecalLifetimeSec);
    Obj.Add('armorWeightAcousticMult', FArmorWeightAcousticMult);
    Obj.Add('minMoveSpeedMps', FMinMoveSpeedMps);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleFootstepDirector.SetConfigJson(const Value: String);
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
    FStrideLengthMeters := EnsureRange(Obj.Get('strideLengthMeters', FStrideLengthMeters), 0.35, 6.0);
    FStanceWidthMeters := EnsureRange(Obj.Get('stanceWidthMeters', FStanceWidthMeters), 0.08, 2.0);
    FDecalLifetimeSec := EnsureRange(Obj.Get('decalLifetimeSec', FDecalLifetimeSec), 0.5, 60.0);
    FArmorWeightAcousticMult := EnsureRange(Obj.Get('armorWeightAcousticMult', FArmorWeightAcousticMult), 0.1, 3.0);
    FMinMoveSpeedMps := EnsureRange(Obj.Get('minMoveSpeedMps', FMinMoveSpeedMps), 0.05, 5.0);
    SavedPreset := Obj.Get('preset', Ord(FPreset));
    if (SavedPreset >= Ord(Low(TFootstepPreset))) and (SavedPreset <= Ord(High(TFootstepPreset))) then
      FPreset := TFootstepPreset(SavedPreset);
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleFootstepDirector, 'Skeletal Footstep & Surface Decal Director');
end.
