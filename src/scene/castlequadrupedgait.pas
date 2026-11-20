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

{ Procedural 4/6/8-legged quadruped, hexapod, and arachnid gait phase scheduler
  with diagonal-trot / alternating-tripod / octopod duty-factor timing,
  parabolic swing arcs, WorldRay uneven terrain foot planting, 2-bone knee
  out-rigging, and least-squares body pitch/roll slope adaptation (Phase 398). }
unit CastleQuadrupedGait;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset 4-leg canine trot, 6-leg insect tripod, and 8-leg spider gaits. }
  TMultiLegGaitPreset = (
    mgpCanineDiagonalTrot4Leg,
    mgpHexapodInsectTripod6Leg,
    mgpArachnidOctopod8Leg
  );

  { Computed kinematic & terrain-contact state of a single leg. }
  TLegFootSample = record
    LegIndex: Integer;
    HipLocalOffset: TVector3;
    RestFootLocalXZ: TVector2;
    PhaseOffset01: Single;
    LocalCyclePhase01: Single;
    IsStanceGrounded: Boolean;
    SwingProgress01: Single;
    GroundElevationY: Single;
    HipWorldPos: TVector3;
    KneeWorldPos: TVector3;
    FootWorldPos: TVector3;
  end;

  { Multi-legged procedural locomotion rig solving gait phase coordination,
    WorldRay terrain foot-planting, and body slope pitch/roll adaptation. }
  TCastleMultiLegGaitRig = class(TCastleTransform)
  private
    FPreset: TMultiLegGaitPreset;
    FLegCount: Integer;
    FBodyClearanceHeightMeters: Single;
    FLegLateralSpreadMeters: Single;
    FStrideLengthMeters: Single;
    FSwingStepHeightMeters: Single;
    FDutyFactor01: Single;
    FMoveSpeedMps: Single;
    FTerrainConformWeight01: Single;
    FShowPreview: Boolean;
    FGaitCycle01: Single;
    FGroundedLegCount: Integer;
    FBodyPitchDeg: Single;
    FBodyRollDeg: Single;
    FLegs: array of TLegFootSample;
    FPreviewRoot: TCastleTransform;
    FPreviewLimbsScene: TCastleScene;
    procedure SetPreset(const AValue: TMultiLegGaitPreset);
    procedure SetLegCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
    procedure RebuildLegLayout;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TMultiLegGaitPreset);

    { Evaluate all legs at explicit normalized gait cycle ACycle01 in [0..1]
      against terrain geometry in AWorldRoot. }
    procedure EvaluateAtNormalizedCycle(
      const AWorldRoot: TCastleAbstractRootTransform;
      const ACycle01: Single);

    { Advance procedural locomotion by ADtSec and update foot/body poses. }
    procedure StepGaitLocomotion(
      const AWorldRoot: TCastleAbstractRootTransform;
      const ADtSec: Single);

    function GetLegSample(const AIndex: Integer): TLegFootSample;
    procedure RebuildPreview;
    procedure ClearPreview;
    function GaitSummaryBadge: String;

    property GaitCycle01: Single read FGaitCycle01 write FGaitCycle01;
    property GroundedLegCount: Integer read FGroundedLegCount;
    property BodyPitchDeg: Single read FBodyPitchDeg;
    property BodyRollDeg: Single read FBodyRollDeg;
  published
    property Preset: TMultiLegGaitPreset
      read FPreset write SetPreset default mgpCanineDiagonalTrot4Leg;
    property LegCount: Integer
      read FLegCount write SetLegCount default 4;
    property BodyClearanceHeightMeters: Single
      read FBodyClearanceHeightMeters write FBodyClearanceHeightMeters;
    property LegLateralSpreadMeters: Single
      read FLegLateralSpreadMeters write FLegLateralSpreadMeters;
    property StrideLengthMeters: Single
      read FStrideLengthMeters write FStrideLengthMeters;
    property SwingStepHeightMeters: Single
      read FSwingStepHeightMeters write FSwingStepHeightMeters;
    property DutyFactor01: Single
      read FDutyFactor01 write FDutyFactor01;
    property MoveSpeedMps: Single
      read FMoveSpeedMps write FMoveSpeedMps;
    property TerrainConformWeight01: Single
      read FTerrainConformWeight01 write FTerrainConformWeight01;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function MultiLegPresetToString(const APreset: TMultiLegGaitPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function MultiLegPresetToString(const APreset: TMultiLegGaitPreset): String;
begin
  case APreset of
    mgpCanineDiagonalTrot4Leg:  Result := 'CanineDiagonalTrot4Leg';
    mgpHexapodInsectTripod6Leg: Result := 'HexapodInsectTripod6Leg';
    mgpArachnidOctopod8Leg:     Result := 'ArachnidOctopod8Leg';
  end;
end;

{ TCastleMultiLegGaitRig ----------------------------------------------------- }

constructor TCastleMultiLegGaitRig.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLegCount := 4;
  FShowPreview := True;
  FGaitCycle01 := 0.0;
  FGroundedLegCount := 0;
  FBodyPitchDeg := 0.0;
  FBodyRollDeg := 0.0;
  ApplyPreset(mgpCanineDiagonalTrot4Leg);
end;

destructor TCastleMultiLegGaitRig.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleMultiLegGaitRig.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'LegCount', 'BodyClearanceHeightMeters',
       'LegLateralSpreadMeters', 'StrideLengthMeters',
       'SwingStepHeightMeters', 'DutyFactor01',
       'MoveSpeedMps', 'TerrainConformWeight01', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMultiLegGaitRig.SetPreset(const AValue: TMultiLegGaitPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleMultiLegGaitRig.SetLegCount(const AValue: Integer);
var
  Sanitized: Integer;
begin
  if AValue <= 4 then Sanitized := 4
  else if AValue <= 6 then Sanitized := 6
  else Sanitized := 8;
  if FLegCount = Sanitized then Exit;
  FLegCount := Sanitized;
  RebuildLegLayout;
  EvaluateAtNormalizedCycle(nil, FGaitCycle01);
end;

procedure TCastleMultiLegGaitRig.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleMultiLegGaitRig.RebuildLegLayout;
const
  PhaseTrot4: array[0..3] of Single = (0.00, 0.50, 0.50, 0.00);
  PhaseTripod6: array[0..5] of Single = (0.00, 0.50, 0.50, 0.00, 0.00, 0.50);
  PhaseOctopod8: array[0..7] of Single = (0.00, 0.50, 0.25, 0.75, 0.50, 0.00, 0.75, 0.25);
var
  Pairs, PairIdx, SideIdx, Idx: Integer;
  SideSign, LongitudinalSpan, ZOff, Spread: Single;
begin
  Pairs := Max(2, FLegCount div 2);
  SetLength(FLegs, Pairs * 2);
  Spread := Max(0.20, FLegLateralSpreadMeters);
  LongitudinalSpan := 0.55 * Pairs;

  for PairIdx := 0 to Pairs - 1 do
    for SideIdx := 0 to 1 do
    begin
      Idx := PairIdx * 2 + SideIdx;
      SideSign := IfThen(SideIdx = 0, -1.0, 1.0);
      ZOff := (0.5 - (PairIdx / Max(1, Pairs - 1))) * (-LongitudinalSpan);
      { PairIdx=0 is front (-Z), PairIdx=Pairs-1 is rear (+Z) }
      ZOff := -0.5 * LongitudinalSpan + (PairIdx / Max(1, Pairs - 1)) * LongitudinalSpan;

      FLegs[Idx] := Default(TLegFootSample);
      FLegs[Idx].LegIndex := Idx;
      FLegs[Idx].HipLocalOffset := Vector3(SideSign * Spread * 0.42, 0.0, ZOff * 0.75);
      FLegs[Idx].RestFootLocalXZ := Vector2(SideSign * Spread, ZOff);
      if Pairs = 2 then
        FLegs[Idx].PhaseOffset01 := PhaseTrot4[Idx]
      else if Pairs = 3 then
        FLegs[Idx].PhaseOffset01 := PhaseTripod6[Idx]
      else
        FLegs[Idx].PhaseOffset01 := PhaseOctopod8[Idx];
    end;
end;

procedure TCastleMultiLegGaitRig.ApplyPreset(const APreset: TMultiLegGaitPreset);
begin
  FPreset := APreset;
  case APreset of
    mgpCanineDiagonalTrot4Leg:
      begin
        FLegCount := 4;
        FBodyClearanceHeightMeters := 0.68;
        FLegLateralSpreadMeters := 0.38;
        FStrideLengthMeters := 0.90;
        FSwingStepHeightMeters := 0.22;
        FDutyFactor01 := 0.58;
        FMoveSpeedMps := 2.7;
        FTerrainConformWeight01 := 0.85;
      end;
    mgpHexapodInsectTripod6Leg:
      begin
        FLegCount := 6;
        FBodyClearanceHeightMeters := 0.44;
        FLegLateralSpreadMeters := 0.78;
        FStrideLengthMeters := 0.72;
        FSwingStepHeightMeters := 0.18;
        FDutyFactor01 := 0.56;
        FMoveSpeedMps := 2.2;
        FTerrainConformWeight01 := 0.90;
      end;
    mgpArachnidOctopod8Leg:
      begin
        FLegCount := 8;
        FBodyClearanceHeightMeters := 0.52;
        FLegLateralSpreadMeters := 1.18;
        FStrideLengthMeters := 0.80;
        FSwingStepHeightMeters := 0.26;
        FDutyFactor01 := 0.62;
        FMoveSpeedMps := 2.4;
        FTerrainConformWeight01 := 0.92;
      end;
  end;
  RebuildLegLayout;
  EvaluateAtNormalizedCycle(nil, FGaitCycle01);
end;

procedure TCastleMultiLegGaitRig.EvaluateAtNormalizedCycle(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ACycle01: Single);

  function ProbeGroundHeightAt(const AWX, AWZ, ARefY: Single): Single;
  var
    ProbeOrig: TVector3;
    RH: TRayCollision;
    K: Integer;
    HitItem: TCastleTransform;
    BestY, HitY: Single;
    Found: Boolean;
  begin
    Result := ARefY - FBodyClearanceHeightMeters;
    if AWorldRoot = nil then Exit;
    ProbeOrig := Vector3(AWX, ARefY + 4.0, AWZ);
    RH := AWorldRoot.WorldRay(ProbeOrig, Vector3(0.0, -1.0, 0.0));
    try
      if RH = nil then Exit;
      Found := False;
      BestY := -1e9;
      for K := 0 to RH.Count - 1 do
      begin
        HitItem := RH[K].Item;
        if (HitItem = nil) or (HitItem = AWorldRoot) or (HitItem = Self) then
          Continue;
        if csTransient in HitItem.ComponentStyle then
          Continue;
        HitY := RH[K].Point.Y;
        if (HitY <= ARefY + 2.5) and ((not Found) or (HitY > BestY)) then
        begin
          BestY := HitY;
          Found := True;
        end;
      end;
      if Found then
        Result := BestY;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  WT: TMatrix4;
  BodyOrigin, FootCandidateWorld, MidHipFoot, OutRigDir: TVector3;
  Duty, StrideHalf, LocalPhase, StanceT, SwingS, LiftY, StrideZOffset: Single;
  FrontY, RearY, LeftY, RightY, ConformW, SpanZ, SpanX: Single;
  FrontCnt, RearCnt, LeftCnt, RightCnt, I: Integer;
begin
  RebuildLegLayout;
  FGaitCycle01 := Frac(ACycle01);
  if FGaitCycle01 < 0.0 then
    FGaitCycle01 := FGaitCycle01 + 1.0;

  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  BodyOrigin := WT.MultPoint(TVector3.Zero);

  Duty := Clamped(FDutyFactor01, 0.50, 0.85);
  StrideHalf := Max(0.05, FStrideLengthMeters) * 0.5;
  FGroundedLegCount := 0;

  FrontY := 0.0; RearY := 0.0; LeftY := 0.0; RightY := 0.0;
  FrontCnt := 0; RearCnt := 0; LeftCnt := 0; RightCnt := 0;

  for I := 0 to High(FLegs) do
  begin
    LocalPhase := Frac(FGaitCycle01 + FLegs[I].PhaseOffset01);
    FLegs[I].LocalCyclePhase01 := LocalPhase;
    FLegs[I].HipWorldPos := WT.MultPoint(FLegs[I].HipLocalOffset);

    if LocalPhase < Duty then
    begin
      { Stance phase: foot sweeps backward from -StrideHalf (front) to +StrideHalf (rear) }
      StanceT := LocalPhase / Duty;
      FLegs[I].IsStanceGrounded := True;
      FLegs[I].SwingProgress01 := 0.0;
      StrideZOffset := Lerp(StanceT, -StrideHalf, StrideHalf);
      LiftY := 0.0;
      Inc(FGroundedLegCount);
    end else
    begin
      { Swing phase: foot lifts along parabolic arc forward from +StrideHalf to -StrideHalf }
      SwingS := (LocalPhase - Duty) / Max(0.05, 1.0 - Duty);
      FLegs[I].IsStanceGrounded := False;
      FLegs[I].SwingProgress01 := SwingS;
      StrideZOffset := Lerp(SwingS, StrideHalf, -StrideHalf);
      LiftY := 4.0 * Max(0.02, FSwingStepHeightMeters) * SwingS * (1.0 - SwingS);
    end;

    FootCandidateWorld := WT.MultPoint(Vector3(
      FLegs[I].RestFootLocalXZ.X,
      -FBodyClearanceHeightMeters,
      FLegs[I].RestFootLocalXZ.Y + StrideZOffset));
    FLegs[I].GroundElevationY := ProbeGroundHeightAt(
      FootCandidateWorld.X, FootCandidateWorld.Z, BodyOrigin.Y);
    FLegs[I].FootWorldPos := Vector3(
      FootCandidateWorld.X,
      FLegs[I].GroundElevationY + LiftY,
      FootCandidateWorld.Z);

    { Elevated arachnid/canine 2-bone knee out-rigged laterally & upward }
    MidHipFoot := (FLegs[I].HipWorldPos + FLegs[I].FootWorldPos) * 0.5;
    OutRigDir := FLegs[I].FootWorldPos - BodyOrigin;
    OutRigDir.Y := 0.0;
    if OutRigDir.LengthSqr > 1e-6 then
      OutRigDir := OutRigDir.Normalize;
    FLegs[I].KneeWorldPos := MidHipFoot +
      Vector3(0.0, 0.28 + 0.18 * FLegLateralSpreadMeters, 0.0) +
      OutRigDir * (0.18 * FLegLateralSpreadMeters);

    if FLegs[I].RestFootLocalXZ.Y < 0.0 then
    begin
      FrontY := FrontY + FLegs[I].GroundElevationY;
      Inc(FrontCnt);
    end else
    begin
      RearY := RearY + FLegs[I].GroundElevationY;
      Inc(RearCnt);
    end;
    if FLegs[I].RestFootLocalXZ.X < 0.0 then
    begin
      LeftY := LeftY + FLegs[I].GroundElevationY;
      Inc(LeftCnt);
    end else
    begin
      RightY := RightY + FLegs[I].GroundElevationY;
      Inc(RightCnt);
    end;
  end;

  ConformW := Clamped(FTerrainConformWeight01, 0.0, 1.0);
  SpanZ := Max(0.4, 0.55 * (FLegCount div 2));
  SpanX := Max(0.4, FLegLateralSpreadMeters * 2.0);
  if (FrontCnt > 0) and (RearCnt > 0) then
    FBodyPitchDeg := ConformW * RadToDeg(ArcTan2(
      (FrontY / FrontCnt) - (RearY / RearCnt), SpanZ))
  else
    FBodyPitchDeg := 0.0;

  if (LeftCnt > 0) and (RightCnt > 0) then
    FBodyRollDeg := ConformW * RadToDeg(ArcTan2(
      (LeftY / LeftCnt) - (RightY / RightCnt), SpanX))
  else
    FBodyRollDeg := 0.0;

  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleMultiLegGaitRig.StepGaitLocomotion(
  const AWorldRoot: TCastleAbstractRootTransform; const ADtSec: Single);
var
  CyclesDelta: Single;
begin
  CyclesDelta := (Max(0.0, FMoveSpeedMps) / Max(0.15, FStrideLengthMeters)) *
    Max(0.0, ADtSec);
  EvaluateAtNormalizedCycle(AWorldRoot, FGaitCycle01 + CyclesDelta);
end;

function TCastleMultiLegGaitRig.GetLegSample(
  const AIndex: Integer): TLegFootSample;
begin
  if (AIndex >= 0) and (AIndex < Length(FLegs)) then
    Result := FLegs[AIndex]
  else
    Result := Default(TLegFootSample);
end;

procedure TCastleMultiLegGaitRig.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewLimbsScene := nil;
  end;
end;

procedure TCastleMultiLegGaitRig.RebuildPreview;
var
  InvWT, WT: TMatrix4;
  TorsoBox: TCastleBox;
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  Counts: array of Int32;
  I: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if (not FShowPreview) or (Length(FLegs) = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'MultiLegGaitPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  TorsoBox := TCastleBox.Create(FPreviewRoot);
  TorsoBox.SetTransient;
  TorsoBox.Pickable := False;
  TorsoBox.Collides := False;
  TorsoBox.Size := Vector3(FLegLateralSpreadMeters * 0.72, 0.24, 0.45 * (FLegCount div 2));
  TorsoBox.Color := Vector4(0.32, 0.36, 0.42, 1.0);
  FPreviewRoot.Add(TorsoBox);

  FPreviewLimbsScene := TCastleScene.Create(FPreviewRoot);
  FPreviewLimbsScene.SetTransient;
  FPreviewLimbsScene.Pickable := False;
  FPreviewLimbsScene.Collides := False;
  FPreviewRoot.Add(FPreviewLimbsScene);

  SetLength(Pts, Length(FLegs) * 3);
  SetLength(Counts, Length(FLegs));
  for I := 0 to High(FLegs) do
  begin
    Pts[I * 3]     := InvWT.MultPoint(FLegs[I].HipWorldPos);
    Pts[I * 3 + 1] := InvWT.MultPoint(FLegs[I].KneeWorldPos);
    Pts[I * 3 + 2] := InvWT.MultPoint(FLegs[I].FootWorldPos);
    Counts[I] := 3;
  end;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  case FPreset of
    mgpCanineDiagonalTrot4Leg:  MatNode.EmissiveColor := Vector3(0.96, 0.72, 0.28);
    mgpHexapodInsectTripod6Leg: MatNode.EmissiveColor := Vector3(0.32, 0.94, 0.56);
    mgpArachnidOctopod8Leg:     MatNode.EmissiveColor := Vector3(0.88, 0.36, 0.96);
  end;
  ShapeNode.Material := MatNode;
  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewLimbsScene.Load(RootNode, True);

  Add(FPreviewRoot);
end;

function TCastleMultiLegGaitRig.GaitSummaryBadge: String;
begin
  Result := FormatDot('[Gait:%d/%d grounded Pitch=%.1fdeg]', [
    FGroundedLegCount, FLegCount, FBodyPitchDeg]);
end;

initialization
  RegisterSerializableComponent(TCastleMultiLegGaitRig, 'Multi-Leg Quadruped/Spider Gait Rig');

end.
