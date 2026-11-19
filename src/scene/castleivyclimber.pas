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

{ Procedural Ivy, Vine & Root Surface Climber with WorldRay Thigmotropism (Phase 379).
  Grows seeded botanical tendrils from a root origin across arbitrary solid scene
  surfaces using 3D WorldRay thigmotropic wall-hugging feelers, upward phototropism,
  parapet ledge wrapping, secondary lateral branching, and transient leaf cards. }
unit CastleIvyClimber;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions, CastleColors,
  CastleClassUtils, CastleComponentSerialize;

const
  MaxIvyNodes = 160;

type
  TIvyPreset = (
    ivpAncientCastleHedera,
    ivpAutumnCrimsonCreeper,
    ivpBioluminescentCaveRoot,
    ivpCustom
  );

  TIvyGrowthNode = record
    WorldPos: TVector3;
    SurfaceNormal: TVector3;
    RadiusMeters: Single;
    AttachedToWall: Boolean;
    BranchGeneration: Integer;
    LeafClusters: Integer;
  end;

  { Seeded WorldRay wall-climbing ivy, creeper & root generator. }
  TCastleIvyClimber = class(TCastleTransform)
  private
    FPreset: TIvyPreset;
    FPrimaryTendrils: Integer;
    FMaxStepsPerTendril: Integer;
    FStepLengthMeters: Single;
    FPhototropismUp: Single;
    FAdhesionRadiusMeters: Single;
    FBranchProbability: Single;
    FRandomSeed: Integer;
    FShowIvyMesh: Boolean;
    FNodes: array of TIvyGrowthNode;
    FAttachedNodeCount: Integer;
    FTotalLeafCount: Integer;
    FMaxReachedHeightY: Single;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const Value: TIvyPreset);
    procedure SetPrimaryTendrils(const Value: Integer);
    procedure SetMaxStepsPerTendril(const Value: Integer);
    procedure SetStepLengthMeters(const Value: Single);
    procedure SetPhototropismUp(const Value: Single);
    procedure SetAdhesionRadiusMeters(const Value: Single);
    procedure SetBranchProbability(const Value: Single);
    procedure SetRandomSeed(const Value: Integer);
    procedure SetShowIvyMesh(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure ClearPreviewMesh;
    procedure RebuildIvyPreviewMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Grow tendrils from this transform's world origin over solid WorldRay geometry. }
    function GrowIvyOnWorld(const AWorldRoot: TCastleAbstractRootTransform): Integer;
    procedure ClearGrownIvy;

    function NodeCount: Integer;
    function GetNode(const Index: Integer): TIvyGrowthNode;
    function IvySummaryBadge: String;

    property AttachedNodeCount: Integer read FAttachedNodeCount;
    property TotalLeafCount: Integer read FTotalLeafCount;
    property MaxReachedHeightY: Single read FMaxReachedHeightY;
  published
    property Preset: TIvyPreset read FPreset write SetPreset default ivpAncientCastleHedera;
    property PrimaryTendrils: Integer read FPrimaryTendrils write SetPrimaryTendrils default 3;
    property MaxStepsPerTendril: Integer read FMaxStepsPerTendril write SetMaxStepsPerTendril default 16;
    property StepLengthMeters: Single read FStepLengthMeters write SetStepLengthMeters {$ifdef FPC}default 0.30{$endif};
    property PhototropismUp: Single read FPhototropismUp write SetPhototropismUp {$ifdef FPC}default 0.90{$endif};
    property AdhesionRadiusMeters: Single read FAdhesionRadiusMeters write SetAdhesionRadiusMeters {$ifdef FPC}default 1.10{$endif};
    property BranchProbability: Single read FBranchProbability write SetBranchProbability {$ifdef FPC}default 0.22{$endif};
    property RandomSeed: Integer read FRandomSeed write SetRandomSeed default 20260379;
    property ShowIvyMesh: Boolean read FShowIvyMesh write SetShowIvyMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

implementation

uses fpjson, jsonparser;

function NextIvyRand01(var State: Cardinal): Single;
begin
  {$PUSH}{$Q-}{$R-}
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := (State and $00FFFFFF) / 16777216.0;
  {$POP}
end;

constructor TCastleIvyClimber.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := ivpAncientCastleHedera;
  FPrimaryTendrils := 3;
  FMaxStepsPerTendril := 16;
  FStepLengthMeters := 0.30;
  FPhototropismUp := 0.90;
  FAdhesionRadiusMeters := 1.10;
  FBranchProbability := 0.22;
  FRandomSeed := 20260379;
  FShowIvyMesh := True;
  FNodes := nil;
  FAttachedNodeCount := 0;
  FTotalLeafCount := 0;
  FMaxReachedHeightY := 0.0;
end;

destructor TCastleIvyClimber.Destroy;
begin
  inherited Destroy;
end;

function TCastleIvyClimber.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'PrimaryTendrils') or
     (PropertyName = 'MaxStepsPerTendril') or
     (PropertyName = 'StepLengthMeters') or
     (PropertyName = 'PhototropismUp') or
     (PropertyName = 'AdhesionRadiusMeters') or
     (PropertyName = 'BranchProbability') or
     (PropertyName = 'RandomSeed') or
     (PropertyName = 'ShowIvyMesh') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleIvyClimber.ClearPreviewMesh;
begin
  if FPreviewRoot <> nil then
    FreeAndNil(FPreviewRoot);
end;

procedure TCastleIvyClimber.ClearGrownIvy;
begin
  FNodes := nil;
  FAttachedNodeCount := 0;
  FTotalLeafCount := 0;
  FMaxReachedHeightY := 0.0;
  ClearPreviewMesh;
end;

function TCastleIvyClimber.GrowIvyOnWorld(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;

  function CastSolidFeeler(const ProbeOrigin, ProbeDir: TVector3;
    const MaxDist: Single; out HitDist: Single): Boolean;
  var
    RayHit: TRayCollision;
    K: Integer;
    HitT: TCastleTransform;
  begin
    Result := False;
    HitDist := MaxDist + 1.0;
    if AWorldRoot = nil then Exit;
    RayHit := AWorldRoot.WorldRay(ProbeOrigin, ProbeDir);
    try
      if (RayHit = nil) or (RayHit.Distance > MaxDist) then
        Exit(False);
      for K := 0 to RayHit.Count - 1 do
      begin
        HitT := RayHit[K].Item;
        if (HitT = nil) or (HitT = AWorldRoot) or (HitT = Self) then Continue;
        if csTransient in HitT.ComponentStyle then Continue;
        HitDist := RayHit.Distance;
        Exit(True);
      end;
    finally
      FreeAndNil(RayHit);
    end;
  end;

  function FindNearestSurface(const ProbePt: TVector3;
    out SurfaceHitPt, OutwardNormal: TVector3): Boolean;
  const
    FeelerDirs: array[0..11] of TVector3 = (
      (X:  0.000; Y:  0.000; Z:  1.000),
      (X:  0.000; Y:  0.000; Z: -1.000),
      (X:  1.000; Y:  0.000; Z:  0.000),
      (X: -1.000; Y:  0.000; Z:  0.000),
      (X:  0.707; Y:  0.000; Z:  0.707),
      (X: -0.707; Y:  0.000; Z:  0.707),
      (X:  0.707; Y:  0.000; Z: -0.707),
      (X: -0.707; Y:  0.000; Z: -0.707),
      (X:  0.000; Y: -0.707; Z:  0.707),
      (X:  0.000; Y: -0.707; Z: -0.707),
      (X:  0.707; Y: -0.707; Z:  0.000),
      (X: -0.707; Y: -0.707; Z:  0.000)
    );
  var
    DIdx: Integer;
    DirNorm: TVector3;
    Dist, BestDist: Single;
  begin
    Result := False;
    BestDist := FAdhesionRadiusMeters + 1.0;
    SurfaceHitPt := ProbePt;
    OutwardNormal := Vector3(0.0, 1.0, 0.0);

    for DIdx := Low(FeelerDirs) to High(FeelerDirs) do
    begin
      DirNorm := FeelerDirs[DIdx].Normalize;
      if CastSolidFeeler(ProbePt, DirNorm, FAdhesionRadiusMeters, Dist) and
         (Dist < BestDist) then
      begin
        BestDist := Dist;
        SurfaceHitPt := ProbePt + DirNorm * Dist;
        OutwardNormal := -DirNorm;
        Result := True;
      end;
    end;
  end;

  procedure AddNodeRecord(const WPos, SurfNorm: TVector3; const Rad: Single;
    const Attached: Boolean; const Gen, Leaves: Integer);
  var
    Idx: Integer;
  begin
    if Length(FNodes) >= MaxIvyNodes then Exit;
    Idx := Length(FNodes);
    SetLength(FNodes, Idx + 1);
    FNodes[Idx].WorldPos := WPos;
    FNodes[Idx].SurfaceNormal := SurfNorm;
    FNodes[Idx].RadiusMeters := Rad;
    FNodes[Idx].AttachedToWall := Attached;
    FNodes[Idx].BranchGeneration := Gen;
    FNodes[Idx].LeafClusters := Leaves;
    if Attached then
      Inc(FAttachedNodeCount);
    Inc(FTotalLeafCount, Leaves);
    if (Idx = 0) or (WPos.Y > FMaxReachedHeightY) then
      FMaxReachedHeightY := WPos.Y;
  end;

  procedure GrowSingleShoot(var SeedState: Cardinal; const StartPos: TVector3;
    const InitialLateralX: Single; const Steps, Generation: Integer);
  var
    CurPos, SurfPt, SurfNorm, RawDrive, Tangent, SideAxis: TVector3;
    StepIdx, UnsupportedRun, LeavesHere: Integer;
    Attached: Boolean;
    Wander: Single;
  begin
    CurPos := StartPos;
    UnsupportedRun := 0;

    for StepIdx := 0 to Steps - 1 do
    begin
      if Length(FNodes) >= MaxIvyNodes then Break;

      Attached := FindNearestSurface(CurPos, SurfPt, SurfNorm);
      if Attached then
      begin
        UnsupportedRun := 0;
        CurPos := SurfPt + SurfNorm * 0.06;
        SideAxis := TVector3.CrossProduct(SurfNorm, Vector3(0.0, 1.0, 0.0));
        if SideAxis.LengthSqr < 1e-4 then
          SideAxis := Vector3(1.0, 0.0, 0.0)
        else
          SideAxis := SideAxis.Normalize;

        Wander := (NextIvyRand01(SeedState) - 0.5) * 0.65 + InitialLateralX * 0.20;
        RawDrive := Vector3(0.0, FPhototropismUp, 0.0) + SideAxis * Wander;
        Tangent := RawDrive - SurfNorm * TVector3.DotProduct(RawDrive, SurfNorm);
        if Tangent.LengthSqr < 1e-5 then
          Tangent := Vector3(0.0, 1.0, 0.0)
        else
          Tangent := Tangent.Normalize;

        LeavesHere := 2 + Ord(NextIvyRand01(SeedState) > 0.45);
        AddNodeRecord(CurPos, SurfNorm, Max(0.02, 0.055 * (1.0 - StepIdx / Max(2, Steps + 2))),
          True, Generation, LeavesHere);

        if (Generation = 0) and (StepIdx >= 2) and
           (NextIvyRand01(SeedState) < FBranchProbability) then
          GrowSingleShoot(SeedState, CurPos,
            IfThen(NextIvyRand01(SeedState) > 0.5, 1.2, -1.2),
            Max(3, (Steps - StepIdx) div 2), 1);

        CurPos := CurPos + Tangent * FStepLengthMeters;
      end else
      begin
        Inc(UnsupportedRun);
        if UnsupportedRun > 3 then
          Break; // Unsupported aerial shoot droops & terminates without a wall!
        AddNodeRecord(CurPos, Vector3(0.0, 1.0, 0.0), 0.025, False, Generation, 1);
        CurPos := CurPos + Vector3(InitialLateralX * 0.12, -0.18, 0.10) * FStepLengthMeters;
      end;
    end;
  end;

var
  SeedState: Cardinal;
  OriginW: TVector3;
  TIdx: Integer;
  SpreadOffset: Single;
begin
  ClearGrownIvy;
  if AWorldRoot = nil then Exit(0);

  {$PUSH}{$Q-}{$R-}
  SeedState := Cardinal(FRandomSeed) xor $85EBCA6B;
  {$POP}
  if SeedState = 0 then SeedState := 1;

  if Parent <> nil then
    OriginW := WorldTranslation
  else
    OriginW := Translation;
  FMaxReachedHeightY := OriginW.Y;

  for TIdx := 0 to FPrimaryTendrils - 1 do
  begin
    if FPrimaryTendrils > 1 then
      SpreadOffset := ((TIdx / (FPrimaryTendrils - 1)) - 0.5) * 1.4
    else
      SpreadOffset := 0.0;
    GrowSingleShoot(SeedState, OriginW + Vector3(SpreadOffset * 0.25, 0.0, 0.0),
      SpreadOffset, FMaxStepsPerTendril, 0);
  end;

  Result := Length(FNodes);
  RebuildIvyPreviewMesh;
end;

function TCastleIvyClimber.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TCastleIvyClimber.GetNode(const Index: Integer): TIvyGrowthNode;
begin
  if (Index >= 0) and (Index < Length(FNodes)) then
    Result := FNodes[Index]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleIvyClimber.IvySummaryBadge: String;
begin
  Result := Format('[Ivy:%d nodes (%d clung) %d leaves]', [
    Length(FNodes), FAttachedNodeCount, FTotalLeafCount]);
end;

procedure TCastleIvyClimber.RebuildIvyPreviewMesh;
var
  I: Integer;
  OriginW: TVector3;
  StemBox, LeafBox: TCastleBox;
  LeafColor: TCastleColor;
begin
  ClearPreviewMesh;
  if (not FShowIvyMesh) or (Length(FNodes) = 0) then
    Exit;

  if Parent <> nil then
    OriginW := WorldTranslation
  else
    OriginW := Translation;

  FPreviewRoot := TCastleTransform.Create(Self);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Name := 'IvyClimberTransientMesh';
  Add(FPreviewRoot);

  case FPreset of
    ivpAutumnCrimsonCreeper: LeafColor := Vector4(0.86, 0.22, 0.16, 1.0);
    ivpBioluminescentCaveRoot: LeafColor := Vector4(0.18, 0.88, 0.92, 1.0);
  else
    LeafColor := Vector4(0.18, 0.66, 0.26, 1.0);
  end;

  for I := 0 to High(FNodes) do
  begin
    StemBox := TCastleBox.Create(FPreviewRoot);
    StemBox.SetTransient;
    StemBox.Pickable := False;
    StemBox.Material := pmPhysical;
    StemBox.Size := Vector3(FNodes[I].RadiusMeters * 2.0, FStepLengthMeters * 0.9, FNodes[I].RadiusMeters * 2.0);
    StemBox.Translation := FNodes[I].WorldPos - OriginW;
    StemBox.Color := Vector4(0.34, 0.25, 0.16, 1.0);
    FPreviewRoot.Add(StemBox);

    if FNodes[I].LeafClusters > 0 then
    begin
      LeafBox := TCastleBox.Create(FPreviewRoot);
      LeafBox.SetTransient;
      LeafBox.Pickable := False;
      LeafBox.Material := pmUnlit;
      LeafBox.Size := Vector3(0.22, 0.16, 0.04);
      LeafBox.Translation := (FNodes[I].WorldPos - OriginW) + FNodes[I].SurfaceNormal * 0.06;
      LeafBox.Color := LeafColor;
      FPreviewRoot.Add(LeafBox);
    end;
  end;
end;

procedure TCastleIvyClimber.SetPreset(const Value: TIvyPreset);
begin
  if FPreset = Value then Exit;
  FPreset := Value;
  case Value of
    ivpAncientCastleHedera:
      begin
        FPrimaryTendrils := 3;
        FMaxStepsPerTendril := 16;
        FStepLengthMeters := 0.30;
        FPhototropismUp := 0.90;
        FAdhesionRadiusMeters := 1.10;
        FBranchProbability := 0.22;
      end;
    ivpAutumnCrimsonCreeper:
      begin
        FPrimaryTendrils := 4;
        FMaxStepsPerTendril := 18;
        FStepLengthMeters := 0.28;
        FPhototropismUp := 0.95;
        FAdhesionRadiusMeters := 1.25;
        FBranchProbability := 0.35;
      end;
    ivpBioluminescentCaveRoot:
      begin
        FPrimaryTendrils := 3;
        FMaxStepsPerTendril := 14;
        FStepLengthMeters := 0.34;
        FPhototropismUp := 0.35;
        FAdhesionRadiusMeters := 1.40;
        FBranchProbability := 0.28;
      end;
    ivpCustom: ;
  end;
  RebuildIvyPreviewMesh;
end;

procedure TCastleIvyClimber.SetPrimaryTendrils(const Value: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(Value, 1, 8);
  if FPrimaryTendrils = Clamped then Exit;
  FPrimaryTendrils := Clamped;
  FPreset := ivpCustom;
end;

procedure TCastleIvyClimber.SetMaxStepsPerTendril(const Value: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(Value, 2, 48);
  if FMaxStepsPerTendril = Clamped then Exit;
  FMaxStepsPerTendril := Clamped;
  FPreset := ivpCustom;
end;

procedure TCastleIvyClimber.SetStepLengthMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.08, 1.50);
  if SameValue(FStepLengthMeters, Clamped, 1e-4) then Exit;
  FStepLengthMeters := Clamped;
  FPreset := ivpCustom;
end;

procedure TCastleIvyClimber.SetPhototropismUp(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, -1.5, 2.5);
  if SameValue(FPhototropismUp, Clamped, 1e-4) then Exit;
  FPhototropismUp := Clamped;
  FPreset := ivpCustom;
end;

procedure TCastleIvyClimber.SetAdhesionRadiusMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.15, 5.0);
  if SameValue(FAdhesionRadiusMeters, Clamped, 1e-4) then Exit;
  FAdhesionRadiusMeters := Clamped;
  FPreset := ivpCustom;
end;

procedure TCastleIvyClimber.SetBranchProbability(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 0.75);
  if SameValue(FBranchProbability, Clamped, 1e-4) then Exit;
  FBranchProbability := Clamped;
  FPreset := ivpCustom;
end;

procedure TCastleIvyClimber.SetRandomSeed(const Value: Integer);
begin
  if FRandomSeed = Value then Exit;
  FRandomSeed := Value;
end;

procedure TCastleIvyClimber.SetShowIvyMesh(const Value: Boolean);
begin
  if FShowIvyMesh = Value then Exit;
  FShowIvyMesh := Value;
  RebuildIvyPreviewMesh;
end;

function TCastleIvyClimber.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('primaryTendrils', FPrimaryTendrils);
    Obj.Add('maxStepsPerTendril', FMaxStepsPerTendril);
    Obj.Add('stepLengthMeters', FStepLengthMeters);
    Obj.Add('phototropismUp', FPhototropismUp);
    Obj.Add('adhesionRadiusMeters', FAdhesionRadiusMeters);
    Obj.Add('branchProbability', FBranchProbability);
    Obj.Add('randomSeed', FRandomSeed);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleIvyClimber.SetConfigJson(const Value: String);
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
    FPrimaryTendrils := EnsureRange(Obj.Get('primaryTendrils', FPrimaryTendrils), 1, 8);
    FMaxStepsPerTendril := EnsureRange(Obj.Get('maxStepsPerTendril', FMaxStepsPerTendril), 2, 48);
    FStepLengthMeters := EnsureRange(Obj.Get('stepLengthMeters', FStepLengthMeters), 0.08, 1.50);
    FPhototropismUp := EnsureRange(Obj.Get('phototropismUp', FPhototropismUp), -1.5, 2.5);
    FAdhesionRadiusMeters := EnsureRange(Obj.Get('adhesionRadiusMeters', FAdhesionRadiusMeters), 0.15, 5.0);
    FBranchProbability := EnsureRange(Obj.Get('branchProbability', FBranchProbability), 0.0, 0.75);
    FRandomSeed := Obj.Get('randomSeed', FRandomSeed);
    SavedPreset := Obj.Get('preset', Ord(FPreset));
    if (SavedPreset >= Ord(Low(TIvyPreset))) and (SavedPreset <= Ord(High(TIvyPreset))) then
      FPreset := TIvyPreset(SavedPreset);
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleIvyClimber, 'Procedural Ivy & Vine Surface Climber');
end.
