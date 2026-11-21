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

{ Tactical boss combat telegraph & AoE hazard director supporting frontal
  pizza-slice cleaves, safe-inner-eye annular donuts, rotated linear charge
  lanes, jump-over expanding shockwave rings, and WorldRay stone-pillar LoS
  supernova shelter (Phase 412). }
unit CastleBossArena;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Canonical boss combat AoE telegraph geometries. }
  TBossTelegraphShape = (
    btsFrontalPizzaCone,
    btsAnnularSafeEyeDonut,
    btsLinearChargeLane,
    btsExpandingJumpShockRing
  );

  { Preset encounter difficulty & telegraph pacing profiles. }
  TBossArenaPreset = (
    bapStoryReadableTelegraphs,
    bapSavageRaidOverlapCombo,
    bapBulletHellShockwaveRing
  );

  { Live AoE telegraph instance tracked by the arena director. }
  TBossActiveTelegraph = record
    Name: String;
    Shape: TBossTelegraphShape;
    OriginWorld: TVector3;
    ForwardXZ: TVector3;
    InnerRadiusMeters: Single;
    OuterRadiusMeters: Single;
    ConeHalfAngleDeg: Single;
    HalfWidthOrBandMeters: Single;
    JumpClearanceHeightMeters: Single;
    AllowPillarLineOfSightShelter: Boolean;
    WindupDurationSec: Single;
    ElapsedSec: Single;
    DamageAmount: Single;
  end;

  { Per-player spatial safety, windup urgency & mitigation result. }
  TBossHazardEvalResult = record
    ThreateningZoneCount: Integer;
    MaxWindupProgress01: Single;
    PotentialDamageSum: Single;
    SavedByInnerDonutEye: Boolean;
    SavedByJumpOverRing: Boolean;
    SavedByPillarShelter: Boolean;
  end;

  { Boss arena AoE telegraph & hazard director component. }
  TCastleBossHazardDirector = class(TCastleTransform)
  private
    FPreset: TBossArenaPreset;
    FWindupSpeedScale: Single;
    FDamageMultiplier: Single;
    FShowPreview: Boolean;
    FTelegraphs: array of TBossActiveTelegraph;
    FLastEval: TBossHazardEvalResult;
    FPreviewRoot: TCastleTransform;
    FPreviewRingsScene: TCastleScene;
    procedure SetPreset(const AValue: TBossArenaPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TBossArenaPreset);
    procedure ClearTelegraphs;

    function SpawnPizzaConeTelegraph(const AName: String;
      const AOrigin, AForward: TVector3;
      const ARadiusM, AHalfAngleDeg, AWindupSec, ADamage: Single;
      const AAllowPillarShelter: Boolean = True): Integer;

    function SpawnSafeEyeDonutTelegraph(const AName: String;
      const AOrigin: TVector3;
      const AInnerSafeRadiusM, AOuterRadiusM, AWindupSec, ADamage: Single): Integer;

    function SpawnLinearChargeLane(const AName: String;
      const AOrigin, AForward: TVector3;
      const ALengthM, AHalfWidthM, AWindupSec, ADamage: Single): Integer;

    function SpawnJumpShockwaveRing(const AName: String;
      const AOrigin: TVector3;
      const AMaxRadiusM, ARingBandHalfWidthM, AJumpClearHeightM,
      AWindupSec, ADamage: Single): Integer;

    procedure StepTelegraphs(const ADtSec: Single);

    { Evaluate whether APlayerFootWorld stands inside any active telegraph,
      accounting for inner donut safe-eyes, airborne jump height, and WorldRay
      arena pillar line-of-sight shelter. }
    function EvaluatePlayerSafety(
      const AWorldRoot: TCastleAbstractRootTransform;
      const APlayerFootWorld: TVector3): TBossHazardEvalResult;

    function TelegraphCount: Integer;
    function GetTelegraph(const AIndex: Integer): TBossActiveTelegraph;

    procedure RebuildPreview;
    procedure ClearPreview;
    function HazardSummaryBadge: String;

    property LastEval: TBossHazardEvalResult read FLastEval;
  published
    property Preset: TBossArenaPreset
      read FPreset write SetPreset default bapStoryReadableTelegraphs;
    property WindupSpeedScale: Single
      read FWindupSpeedScale write FWindupSpeedScale;
    property DamageMultiplier: Single
      read FDamageMultiplier write FDamageMultiplier;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function BossArenaPresetToString(const APreset: TBossArenaPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function BossArenaPresetToString(const APreset: TBossArenaPreset): String;
begin
  case APreset of
    bapStoryReadableTelegraphs: Result := 'StoryReadableTelegraphs';
    bapSavageRaidOverlapCombo:  Result := 'SavageRaidOverlapCombo';
    bapBulletHellShockwaveRing: Result := 'BulletHellShockwaveRing';
  end;
end;

constructor TCastleBossHazardDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FLastEval := Default(TBossHazardEvalResult);
  ApplyPreset(bapStoryReadableTelegraphs);
end;

destructor TCastleBossHazardDirector.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleBossHazardDirector.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'WindupSpeedScale', 'DamageMultiplier', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleBossHazardDirector.SetPreset(const AValue: TBossArenaPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleBossHazardDirector.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleBossHazardDirector.ApplyPreset(const APreset: TBossArenaPreset);
begin
  FPreset := APreset;
  case APreset of
    bapStoryReadableTelegraphs:
      begin
        FWindupSpeedScale := 1.00;
        FDamageMultiplier := 1.00;
      end;
    bapSavageRaidOverlapCombo:
      begin
        FWindupSpeedScale := 1.65;
        FDamageMultiplier := 2.25;
      end;
    bapBulletHellShockwaveRing:
      begin
        FWindupSpeedScale := 1.35;
        FDamageMultiplier := 1.40;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleBossHazardDirector.ClearTelegraphs;
begin
  SetLength(FTelegraphs, 0);
  FLastEval := Default(TBossHazardEvalResult);
  ClearPreview;
end;

function NormForwardXZ(const V: TVector3): TVector3;
begin
  Result := Vector3(V.X, 0.0, V.Z);
  if Result.LengthSqr > 1e-6 then
    Result := Result.Normalize
  else
    Result := Vector3(0.0, 0.0, 1.0);
end;

function TCastleBossHazardDirector.SpawnPizzaConeTelegraph(const AName: String;
  const AOrigin, AForward: TVector3;
  const ARadiusM, AHalfAngleDeg, AWindupSec, ADamage: Single;
  const AAllowPillarShelter: Boolean): Integer;
var
  N: Integer;
begin
  N := Length(FTelegraphs);
  SetLength(FTelegraphs, N + 1);
  FTelegraphs[N] := Default(TBossActiveTelegraph);
  FTelegraphs[N].Name := AName;
  FTelegraphs[N].Shape := btsFrontalPizzaCone;
  FTelegraphs[N].OriginWorld := AOrigin;
  FTelegraphs[N].ForwardXZ := NormForwardXZ(AForward);
  FTelegraphs[N].OuterRadiusMeters := Max(0.5, ARadiusM);
  FTelegraphs[N].ConeHalfAngleDeg := Clamped(AHalfAngleDeg, 5.0, 180.0);
  FTelegraphs[N].AllowPillarLineOfSightShelter := AAllowPillarShelter;
  FTelegraphs[N].WindupDurationSec := Max(0.1, AWindupSec);
  FTelegraphs[N].DamageAmount := Max(0.0, ADamage);
  if FShowPreview then RebuildPreview;
  Result := N;
end;

function TCastleBossHazardDirector.SpawnSafeEyeDonutTelegraph(const AName: String;
  const AOrigin: TVector3;
  const AInnerSafeRadiusM, AOuterRadiusM, AWindupSec, ADamage: Single): Integer;
var
  N: Integer;
begin
  N := Length(FTelegraphs);
  SetLength(FTelegraphs, N + 1);
  FTelegraphs[N] := Default(TBossActiveTelegraph);
  FTelegraphs[N].Name := AName;
  FTelegraphs[N].Shape := btsAnnularSafeEyeDonut;
  FTelegraphs[N].OriginWorld := AOrigin;
  FTelegraphs[N].InnerRadiusMeters := Max(0.25, AInnerSafeRadiusM);
  FTelegraphs[N].OuterRadiusMeters := Max(FTelegraphs[N].InnerRadiusMeters + 0.5, AOuterRadiusM);
  FTelegraphs[N].WindupDurationSec := Max(0.1, AWindupSec);
  FTelegraphs[N].DamageAmount := Max(0.0, ADamage);
  if FShowPreview then RebuildPreview;
  Result := N;
end;

function TCastleBossHazardDirector.SpawnLinearChargeLane(const AName: String;
  const AOrigin, AForward: TVector3;
  const ALengthM, AHalfWidthM, AWindupSec, ADamage: Single): Integer;
var
  N: Integer;
begin
  N := Length(FTelegraphs);
  SetLength(FTelegraphs, N + 1);
  FTelegraphs[N] := Default(TBossActiveTelegraph);
  FTelegraphs[N].Name := AName;
  FTelegraphs[N].Shape := btsLinearChargeLane;
  FTelegraphs[N].OriginWorld := AOrigin;
  FTelegraphs[N].ForwardXZ := NormForwardXZ(AForward);
  FTelegraphs[N].OuterRadiusMeters := Max(0.5, ALengthM);
  FTelegraphs[N].HalfWidthOrBandMeters := Max(0.2, AHalfWidthM);
  FTelegraphs[N].WindupDurationSec := Max(0.1, AWindupSec);
  FTelegraphs[N].DamageAmount := Max(0.0, ADamage);
  if FShowPreview then RebuildPreview;
  Result := N;
end;

function TCastleBossHazardDirector.SpawnJumpShockwaveRing(const AName: String;
  const AOrigin: TVector3;
  const AMaxRadiusM, ARingBandHalfWidthM, AJumpClearHeightM,
  AWindupSec, ADamage: Single): Integer;
var
  N: Integer;
begin
  N := Length(FTelegraphs);
  SetLength(FTelegraphs, N + 1);
  FTelegraphs[N] := Default(TBossActiveTelegraph);
  FTelegraphs[N].Name := AName;
  FTelegraphs[N].Shape := btsExpandingJumpShockRing;
  FTelegraphs[N].OriginWorld := AOrigin;
  FTelegraphs[N].OuterRadiusMeters := Max(1.0, AMaxRadiusM);
  FTelegraphs[N].HalfWidthOrBandMeters := Max(0.2, ARingBandHalfWidthM);
  FTelegraphs[N].JumpClearanceHeightMeters := Max(0.2, AJumpClearHeightM);
  FTelegraphs[N].WindupDurationSec := Max(0.1, AWindupSec);
  FTelegraphs[N].DamageAmount := Max(0.0, ADamage);
  if FShowPreview then RebuildPreview;
  Result := N;
end;

procedure TCastleBossHazardDirector.StepTelegraphs(const ADtSec: Single);
var
  I: Integer;
begin
  if ADtSec <= 0.0 then Exit;
  for I := 0 to High(FTelegraphs) do
    FTelegraphs[I].ElapsedSec := FTelegraphs[I].ElapsedSec +
      ADtSec * Max(0.05, FWindupSpeedScale);
  if FShowPreview then
    RebuildPreview;
end;

function TCastleBossHazardDirector.EvaluatePlayerSafety(
  const AWorldRoot: TCastleAbstractRootTransform;
  const APlayerFootWorld: TVector3): TBossHazardEvalResult;
var
  ActiveRoot: TCastleAbstractRootTransform;

  function BlockedByArenaPillar(const ABossOrigin, APlayerPos: TVector3): Boolean;
  var
    A, B, Dir: TVector3;
    SegLen, D: Single;
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
  begin
    Result := False;
    if ActiveRoot = nil then Exit;
    A := ABossOrigin + Vector3(0.0, 1.1, 0.0);
    B := APlayerPos + Vector3(0.0, 1.1, 0.0);
    SegLen := PointsDistance(A, B);
    if SegLen <= 0.15 then Exit;
    Dir := (B - A) / SegLen;
    RH := ActiveRoot.WorldRay(A, Dir);
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        D := PointsDistance(A, RH[K].Point);
        if (D > 0.08) and (D < SegLen - 0.08) then
          Exit(True);
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  I: Integer;
  T: TBossActiveTelegraph;
  RelXZ, RightXZ: TVector3;
  DistXZ, AngDeg, Prog01, FwdProj, SideProj, RingR: Single;
  InFootprint: Boolean;
begin
  Result := Default(TBossHazardEvalResult);
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  for I := 0 to High(FTelegraphs) do
  begin
    T := FTelegraphs[I];
    Prog01 := Clamped(T.ElapsedSec / Max(0.05, T.WindupDurationSec), 0.0, 1.0);
    RelXZ := Vector3(APlayerFootWorld.X - T.OriginWorld.X, 0.0,
                     APlayerFootWorld.Z - T.OriginWorld.Z);
    DistXZ := RelXZ.Length;
    InFootprint := False;

    case T.Shape of
      btsFrontalPizzaCone:
        if DistXZ <= T.OuterRadiusMeters then
        begin
          if DistXZ < 1e-4 then
            InFootprint := True
          else
          begin
            AngDeg := RadToDeg(ArcCos(Clamped(
              TVector3.DotProduct(RelXZ / DistXZ, T.ForwardXZ), -1.0, 1.0)));
            InFootprint := AngDeg <= T.ConeHalfAngleDeg;
          end;
        end;

      btsAnnularSafeEyeDonut:
        if DistXZ < T.InnerRadiusMeters then
          Result.SavedByInnerDonutEye := True
        else if DistXZ <= T.OuterRadiusMeters then
          InFootprint := True;

      btsLinearChargeLane:
        begin
          RightXZ := Vector3(-T.ForwardXZ.Z, 0.0, T.ForwardXZ.X);
          FwdProj := TVector3.DotProduct(RelXZ, T.ForwardXZ);
          SideProj := Abs(TVector3.DotProduct(RelXZ, RightXZ));
          InFootprint := (FwdProj >= 0.0) and (FwdProj <= T.OuterRadiusMeters) and
                         (SideProj <= T.HalfWidthOrBandMeters);
        end;

      btsExpandingJumpShockRing:
        begin
          RingR := T.OuterRadiusMeters * Prog01;
          if Abs(DistXZ - RingR) <= T.HalfWidthOrBandMeters then
          begin
            if (APlayerFootWorld.Y - T.OriginWorld.Y) > T.JumpClearanceHeightMeters then
              Result.SavedByJumpOverRing := True
            else
              InFootprint := True;
          end;
        end;
    end;

    if InFootprint then
    begin
      if T.AllowPillarLineOfSightShelter and
         BlockedByArenaPillar(T.OriginWorld, APlayerFootWorld) then
        Result.SavedByPillarShelter := True
      else
      begin
        Inc(Result.ThreateningZoneCount);
        Result.MaxWindupProgress01 := Max(Result.MaxWindupProgress01, Prog01);
        Result.PotentialDamageSum := Result.PotentialDamageSum +
          T.DamageAmount * Max(0.1, FDamageMultiplier);
      end;
    end;
  end;

  FLastEval := Result;
end;

function TCastleBossHazardDirector.TelegraphCount: Integer;
begin
  Result := Length(FTelegraphs);
end;

function TCastleBossHazardDirector.GetTelegraph(
  const AIndex: Integer): TBossActiveTelegraph;
begin
  if (AIndex >= 0) and (AIndex < Length(FTelegraphs)) then
    Result := FTelegraphs[AIndex]
  else
    Result := Default(TBossActiveTelegraph);
end;

procedure TCastleBossHazardDirector.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewRingsScene := nil;
  end;
end;

procedure TCastleBossHazardDirector.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  InvWT, WT: TMatrix4;
  Pts: array of TVector3;
  Counts: array of Int32;
  I, Seg, N: Integer;
  R, Ang: Single;
  CWorld: TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  N := Length(FTelegraphs);
  if (not FShowPreview) or (N = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'BossArenaPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewRingsScene := TCastleScene.Create(FPreviewRoot);
  FPreviewRingsScene.SetTransient;
  FPreviewRingsScene.Name := 'BossArenaPreviewTelegraphs';
  FPreviewRingsScene.Pickable := False;
  FPreviewRingsScene.Collides := False;
  FPreviewRoot.Add(FPreviewRingsScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(1.0, 0.32, 0.18);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  SetLength(Pts, N * 17);
  SetLength(Counts, N);
  for I := 0 to N - 1 do
  begin
    R := FTelegraphs[I].OuterRadiusMeters;
    for Seg := 0 to 16 do
    begin
      Ang := 2.0 * Pi * Seg / 16.0;
      CWorld := FTelegraphs[I].OriginWorld + Vector3(Cos(Ang) * R, 0.08, Sin(Ang) * R);
      Pts[I * 17 + Seg] := InvWT.MultPoint(CWorld);
    end;
    Counts[I] := 17;
  end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewRingsScene.Load(RootNode, True);
end;

function TCastleBossHazardDirector.HazardSummaryBadge: String;
begin
  Result := FormatDot('[Hazards:%d zones Threat=%d Dmg=%.0f]', [
    Length(FTelegraphs), FLastEval.ThreateningZoneCount,
    FLastEval.PotentialDamageSum]);
end;

initialization
  RegisterSerializableComponent(TCastleBossHazardDirector, 'Boss Telegraph Hazard Director');

end.
