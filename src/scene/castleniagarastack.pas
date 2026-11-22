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

{ Unreal Engine 5.5-style Niagara Modular Emitter Stack & Curve Editor runtime
  (@link(TCastleNiagaraSystem)) featuring a reorderable 4-stage module stack
  (Emitter Spawn, Emitter Update, Particle Spawn, Particle Update), 3D
  divergence-free Curl Noise, Point Attractor, Drag, Size/Color-over-Life LUT
  curves, floor collision bounce + secondary spark sub-events, and transient 3D
  particle visualization (Phase 385 — UE 5.5 UNiagaraSystem Parity). }
unit CastleNiagaraStack;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Four execution stages inside a UE5 Niagara Emitter Stack. }
  TNiagaraStackStage = (
    nssEmitterSpawn,
    nssEmitterUpdate,
    nssParticleSpawn,
    nssParticleUpdate
  );

  { Composable Niagara module kinds. }
  TNiagaraModuleKind = (
    { Emitter Spawn / Emitter Update }
    nmkSpawnBurstInstantaneous,
    nmkSpawnRate,
    { Particle Spawn }
    nmkInitializeParticle,
    nmkSphereLocation,
    nmkAddVelocityCone,
    { Particle Update }
    nmkGravityForce,
    nmkDragForce,
    nmkCurlNoiseForce,
    nmkPointAttractor,
    nmkScaleSizeByLifeCurve,
    nmkColorOverLifeLut,
    nmkFloorCollisionBounce
  );

  { Built-in UE 5.5 Niagara starter system presets. }
  TNiagaraSystemPreset = (
    nspCustom,
    nspArcaneVortexPortal,
    nspAnvilSparksCollisionBurst,
    nspCampfireEmberColumn
  );

  { 4-key piecewise curve over NormalizedAge [0..1] (UE5 FloatFromCurve parity). }
  TNiagaraFloatCurve = record
    KeyTimes: array[0..3] of Single;
    KeyValues: array[0..3] of Single;
    class function DefaultBellCurve: TNiagaraFloatCurve; static;
    function Evaluate(const ANormAge: Single): Single;
  end;

  { Single reorderable module row inside the 4-stage Niagara Emitter Stack. }
  TNiagaraModule = record
    ModuleId: String;
    Stage: TNiagaraStackStage;
    Kind: TNiagaraModuleKind;
    Enabled: Boolean;
    ParamA: Single;
    ParamB: Single;
    ParamC: Single;
    BoolFlag: Boolean;
    VecA: TVector3;
    VecB: TVector3;
    Curve: TNiagaraFloatCurve;
  end;
  TNiagaraModuleArray = array of TNiagaraModule;

  { Live simulated particle state in the Niagara SoA/AoS pool. }
  TNiagaraParticle = record
    Alive: Boolean;
    IsSubSpark: Boolean;
    Position: TVector3;
    Velocity: TVector3;
    AgeSec: Single;
    LifetimeSec: Single;
    NormalizedAge: Single;
    BaseSize: Single;
    CurrentSize: Single;
    ColorRGBA: TVector4;
  end;
  TNiagaraParticleArray = array of TNiagaraParticle;

  { Unreal Engine 5.5-style Niagara Modular Emitter System component. }
  TCastleNiagaraSystem = class(TCastleTransform)
  public
    const
      DefaultMaxParticles = 256;
  private
    FPreset: TNiagaraSystemPreset;
    FSystemSeed: Integer;
    FMaxParticles: Integer;
    FShowPreviewSprites: Boolean;
    FModules: TNiagaraModuleArray;

    { Transient simulation state }
    FParticles: TNiagaraParticleArray;
    FEmitterAgeSec: Single;
    FSpawnRateAccum: Single;
    FBurstSpawnFired: Boolean;
    FRngState: Cardinal;
    FActiveParticleCount: Integer;
    FTotalSpawnedCount: Integer;
    FCollisionEventCount: Integer;
    FSubSparkSpawnCount: Integer;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TNiagaraSystemPreset);
    procedure SetMaxParticles(const AValue: Integer);
    procedure SetShowPreviewSprites(const AValue: Boolean);
    function GetStackJson: String;
    procedure SetStackJson(const AValue: String);

    function NextRandom01: Single;
    function NextRandomSigned: Single;
    class function SampleCurlNoise3D(const P: TVector3; const ATimeSec: Single): TVector3; static;

    procedure SpawnSingleParticle(const AIsSubSpark: Boolean;
      const AOverrideOrigin, AOverrideVel: TVector3);
    procedure ClearPreviewContainer;
    procedure SyncPreviewSprites;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Metadata helpers }
    class function StageTitle(const AStage: TNiagaraStackStage): String; static;
    class function ModuleKindTitle(const AKind: TNiagaraModuleKind): String; static;
    class function DefaultStageForModule(const AKind: TNiagaraModuleKind): TNiagaraStackStage; static;
    class function MakeDefaultModule(const AId: String;
      const AKind: TNiagaraModuleKind): TNiagaraModule; static;

    { Stack authoring & reordering API }
    procedure ClearStack;
    procedure ApplyPreset(const APreset: TNiagaraSystemPreset);
    function FindModuleIndex(const AModuleId: String): Integer;
    function AddOrUpdateModule(const AModule: TNiagaraModule): Integer;
    function ToggleModuleEnabled(const AModuleId: String): Boolean;
    function MoveModuleOrder(const AModuleId: String; const ADelta: Integer): Boolean;

    { Deterministic simulation stepping }
    procedure ResetSimulation;
    procedure StepSystem(const ADeltaSeconds: Single);

    function NiagaraSummaryBadge: String;

    property Modules: TNiagaraModuleArray read FModules;
    property Particles: TNiagaraParticleArray read FParticles;
    property EmitterAgeSec: Single read FEmitterAgeSec;
    property ActiveParticleCount: Integer read FActiveParticleCount;
    property TotalSpawnedCount: Integer read FTotalSpawnedCount;
    property CollisionEventCount: Integer read FCollisionEventCount;
    property SubSparkSpawnCount: Integer read FSubSparkSpawnCount;
  published
    property SystemSeed: Integer read FSystemSeed write FSystemSeed default 2026;
    property MaxParticles: Integer read FMaxParticles write SetMaxParticles default DefaultMaxParticles;
    property ShowPreviewSprites: Boolean read FShowPreviewSprites write SetShowPreviewSprites default True;
    property StackJson: String read GetStackJson write SetStackJson;
    property Preset: TNiagaraSystemPreset read FPreset write SetPreset default nspArcaneVortexPortal;
  end;

implementation

uses
  fpjson, jsonparser;

{ TNiagaraFloatCurve --------------------------------------------------------- }

class function TNiagaraFloatCurve.DefaultBellCurve: TNiagaraFloatCurve;
begin
  Result.KeyTimes[0] := 0.0;  Result.KeyValues[0] := 0.35;
  Result.KeyTimes[1] := 0.20; Result.KeyValues[1] := 1.25;
  Result.KeyTimes[2] := 0.65; Result.KeyValues[2] := 0.85;
  Result.KeyTimes[3] := 1.00; Result.KeyValues[3] := 0.05;
end;

function TNiagaraFloatCurve.Evaluate(const ANormAge: Single): Single;
var
  T, SegSpan, LocalT, SmoothT: Single;
  I: Integer;
begin
  T := EnsureRange(ANormAge, 0.0, 1.0);
  if T <= KeyTimes[0] then Exit(KeyValues[0]);
  if T >= KeyTimes[3] then Exit(KeyValues[3]);

  for I := 0 to 2 do
    if (T >= KeyTimes[I]) and (T <= KeyTimes[I + 1]) then
    begin
      SegSpan := Max(1e-5, KeyTimes[I + 1] - KeyTimes[I]);
      LocalT := EnsureRange((T - KeyTimes[I]) / SegSpan, 0.0, 1.0);
      SmoothT := LocalT * LocalT * (3.0 - 2.0 * LocalT);
      Exit(Lerp(SmoothT, KeyValues[I], KeyValues[I + 1]));
    end;
  Result := KeyValues[3];
end;

{ TCastleNiagaraSystem ------------------------------------------------------- }

constructor TCastleNiagaraSystem.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSystemSeed := 2026;
  FMaxParticles := DefaultMaxParticles;
  FShowPreviewSprites := True;
  SetLength(FParticles, FMaxParticles);
  ApplyPreset(nspArcaneVortexPortal);
end;

destructor TCastleNiagaraSystem.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleNiagaraSystem.Loaded;
begin
  inherited;
  ResetSimulation;
end;

function TCastleNiagaraSystem.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'SystemSeed') or
     (PropertyName = 'MaxParticles') or
     (PropertyName = 'ShowPreviewSprites') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleNiagaraSystem.SetPreset(const AValue: TNiagaraSystemPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleNiagaraSystem.SetMaxParticles(const AValue: Integer);
begin
  FMaxParticles := EnsureRange(AValue, 8, 2048);
  SetLength(FParticles, FMaxParticles);
  ResetSimulation;
end;

procedure TCastleNiagaraSystem.SetShowPreviewSprites(const AValue: Boolean);
begin
  if FShowPreviewSprites <> AValue then
  begin
    FShowPreviewSprites := AValue;
    if not FShowPreviewSprites then
      ClearPreviewContainer
    else
      SyncPreviewSprites;
  end;
end;

function TCastleNiagaraSystem.NextRandom01: Single;
begin
  {$PUSH}{$R-}{$Q-}
  FRngState := FRngState xor (FRngState shl 13);
  FRngState := FRngState xor (FRngState shr 17);
  FRngState := FRngState xor (FRngState shl 5);
  {$POP}
  Result := (FRngState and $00FFFFFF) / 16777215.0;
end;

function TCastleNiagaraSystem.NextRandomSigned: Single;
begin
  Result := NextRandom01 * 2.0 - 1.0;
end;

class function TCastleNiagaraSystem.SampleCurlNoise3D(const P: TVector3;
  const ATimeSec: Single): TVector3;

  function PotentialField(const Q: TVector3): TVector3;
  begin
    Result := Vector3(
      Sin(Q.Y * 1.7 + ATimeSec * 1.9) + Cos(Q.Z * 1.3 - ATimeSec * 1.1),
      Sin(Q.Z * 1.5 + ATimeSec * 1.7) + Cos(Q.X * 1.9 + ATimeSec * 1.3),
      Sin(Q.X * 1.6 - ATimeSec * 1.4) + Cos(Q.Y * 1.8 + ATimeSec * 1.6));
  end;

const
  Eps = 0.05;
var
  DxP, DxM, DyP, DyM, DzP, DzM: TVector3;
  dFz_dy, dFy_dz, dFx_dz, dFz_dx, dFy_dx, dFx_dy: Single;
begin
  DxP := PotentialField(P + Vector3(Eps, 0, 0));
  DxM := PotentialField(P - Vector3(Eps, 0, 0));
  DyP := PotentialField(P + Vector3(0, Eps, 0));
  DyM := PotentialField(P - Vector3(0, Eps, 0));
  DzP := PotentialField(P + Vector3(0, 0, Eps));
  DzM := PotentialField(P - Vector3(0, 0, Eps));

  dFz_dy := (DyP.Z - DyM.Z) / (2.0 * Eps);
  dFy_dz := (DzP.Y - DzM.Y) / (2.0 * Eps);
  dFx_dz := (DzP.X - DzM.X) / (2.0 * Eps);
  dFz_dx := (DxP.Z - DxM.Z) / (2.0 * Eps);
  dFy_dx := (DxP.Y - DxM.Y) / (2.0 * Eps);
  dFx_dy := (DyP.X - DyM.X) / (2.0 * Eps);

  Result := Vector3(dFz_dy - dFy_dz, dFx_dz - dFz_dx, dFy_dx - dFx_dy);
end;

class function TCastleNiagaraSystem.StageTitle(
  const AStage: TNiagaraStackStage): String;
begin
  case AStage of
    nssEmitterSpawn:   Result := 'Emitter Spawn';
    nssEmitterUpdate:  Result := 'Emitter Update';
    nssParticleSpawn:  Result := 'Particle Spawn';
    nssParticleUpdate: Result := 'Particle Update';
  end;
end;

class function TCastleNiagaraSystem.ModuleKindTitle(
  const AKind: TNiagaraModuleKind): String;
begin
  case AKind of
    nmkSpawnBurstInstantaneous: Result := 'Spawn Burst Instantaneous';
    nmkSpawnRate:               Result := 'Spawn Rate';
    nmkInitializeParticle:      Result := 'Initialize Particle';
    nmkSphereLocation:          Result := 'Sphere Location';
    nmkAddVelocityCone:         Result := 'Add Velocity in Cone';
    nmkGravityForce:            Result := 'Gravity Force';
    nmkDragForce:               Result := 'Aerodynamic Drag';
    nmkCurlNoiseForce:          Result := 'Curl Noise Force';
    nmkPointAttractor:          Result := 'Point Attractor';
    nmkScaleSizeByLifeCurve:    Result := 'Scale Size by Life Curve';
    nmkColorOverLifeLut:        Result := 'Color Over Life';
    nmkFloorCollisionBounce:    Result := 'Collision Bounce & Event';
  end;
end;

class function TCastleNiagaraSystem.DefaultStageForModule(
  const AKind: TNiagaraModuleKind): TNiagaraStackStage;
begin
  case AKind of
    nmkSpawnBurstInstantaneous: Result := nssEmitterSpawn;
    nmkSpawnRate:               Result := nssEmitterUpdate;
    nmkInitializeParticle,
    nmkSphereLocation,
    nmkAddVelocityCone:         Result := nssParticleSpawn;
  else
    Result := nssParticleUpdate;
  end;
end;

class function TCastleNiagaraSystem.MakeDefaultModule(const AId: String;
  const AKind: TNiagaraModuleKind): TNiagaraModule;
begin
  Result := Default(TNiagaraModule);
  Result.ModuleId := AId;
  Result.Stage := DefaultStageForModule(AKind);
  Result.Kind := AKind;
  Result.Enabled := True;
  Result.Curve := TNiagaraFloatCurve.DefaultBellCurve;

  case AKind of
    nmkSpawnBurstInstantaneous:
      Result.ParamA := 24.0; { Burst count }
    nmkSpawnRate:
      Result.ParamA := 40.0; { Particles / sec }
    nmkInitializeParticle:
      begin
        Result.ParamA := 1.2;  { MinLifetimeSec }
        Result.ParamB := 2.0;  { MaxLifetimeSec }
        Result.ParamC := 0.16; { BaseSize }
        Result.VecA := Vector3(0.35, 0.78, 1.00);
      end;
    nmkSphereLocation:
      Result.ParamA := 1.5; { Sphere radius }
    nmkAddVelocityCone:
      begin
        Result.ParamA := 4.5;  { MinSpeed }
        Result.ParamB := 7.5;  { MaxSpeed }
        Result.ParamC := 25.0; { ConeHalfAngleDeg }
        Result.VecA := Vector3(0, 1, 0);
      end;
    nmkGravityForce:
      Result.VecA := Vector3(0, -9.81, 0);
    nmkDragForce:
      Result.ParamA := 1.2; { Linear drag }
    nmkCurlNoiseForce:
      begin
        Result.ParamA := 4.5;  { Noise strength }
        Result.ParamB := 0.65; { Spatial frequency }
      end;
    nmkPointAttractor:
      begin
        Result.ParamA := 18.0; { Strength }
        Result.ParamB := 12.0; { Radius }
        Result.VecA := Vector3(0, 2.0, 0); { Local target }
      end;
    nmkScaleSizeByLifeCurve:
      Result.ParamA := 1.0;
    nmkColorOverLifeLut:
      begin
        Result.VecA := Vector3(0.30, 0.85, 1.00); { Start RGB }
        Result.VecB := Vector3(0.85, 0.20, 0.95); { End RGB }
      end;
    nmkFloorCollisionBounce:
      begin
        Result.ParamA := 0.0;  { Floor local Y }
        Result.ParamB := 0.62; { Restitution }
        Result.BoolFlag := True; { Spawn secondary spark on first impact }
      end;
  end;
end;

procedure TCastleNiagaraSystem.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
    FreeAndNil(FPreviewContainer);
end;

procedure TCastleNiagaraSystem.SyncPreviewSprites;
var
  I, Shown: Integer;
  B: TCastleBox;
begin
  ClearPreviewContainer;
  if (not FShowPreviewSprites) or (FActiveParticleCount = 0) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  FPreviewContainer.Pickable := False;
  FPreviewContainer.Collides := False;
  FPreviewContainer.Name := 'Niagara_PreviewSprites';
  Add(FPreviewContainer);

  Shown := 0;
  for I := 0 to High(FParticles) do
    if FParticles[I].Alive then
    begin
      B := TCastleBox.Create(FPreviewContainer);
      B.SetTransient;
      B.Pickable := False;
      B.Collides := False;
      B.Size := Vector3(
        Max(0.03, FParticles[I].CurrentSize),
        Max(0.03, FParticles[I].CurrentSize),
        Max(0.03, FParticles[I].CurrentSize));
      B.Translation := FParticles[I].Position;
      B.Color := FParticles[I].ColorRGBA;
      FPreviewContainer.Add(B);
      Inc(Shown);
      if Shown >= 64 then Break;
    end;
end;

procedure TCastleNiagaraSystem.ClearStack;
begin
  FModules := nil;
  ResetSimulation;
end;

function TCastleNiagaraSystem.FindModuleIndex(const AModuleId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FModules) do
    if SameText(FModules[I].ModuleId, AModuleId) then
      Exit(I);
  Result := -1;
end;

function TCastleNiagaraSystem.AddOrUpdateModule(
  const AModule: TNiagaraModule): Integer;
begin
  Result := FindModuleIndex(AModule.ModuleId);
  if Result < 0 then
  begin
    Result := Length(FModules);
    SetLength(FModules, Result + 1);
  end;
  FModules[Result] := AModule;
end;

function TCastleNiagaraSystem.ToggleModuleEnabled(const AModuleId: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindModuleIndex(AModuleId);
  if Idx < 0 then Exit(False);
  FModules[Idx].Enabled := not FModules[Idx].Enabled;
  Result := FModules[Idx].Enabled;
end;

function TCastleNiagaraSystem.MoveModuleOrder(const AModuleId: String;
  const ADelta: Integer): Boolean;
var
  Idx, TargetIdx: Integer;
  Temp: TNiagaraModule;
begin
  Idx := FindModuleIndex(AModuleId);
  TargetIdx := Idx + ADelta;
  if (Idx < 0) or (TargetIdx < 0) or (TargetIdx > High(FModules)) then
    Exit(False);
  if FModules[Idx].Stage <> FModules[TargetIdx].Stage then
    Exit(False);
  Temp := FModules[Idx];
  FModules[Idx] := FModules[TargetIdx];
  FModules[TargetIdx] := Temp;
  Result := True;
end;

procedure TCastleNiagaraSystem.ResetSimulation;
var
  I: Integer;
begin
  SetLength(FParticles, FMaxParticles);
  for I := 0 to High(FParticles) do
    FParticles[I].Alive := False;

  FEmitterAgeSec := 0.0;
  FSpawnRateAccum := 0.0;
  FBurstSpawnFired := False;
  {$PUSH}{$R-}{$Q-}
  FRngState := Cardinal(FSystemSeed) xor Cardinal($A53C9E21);
  {$POP}
  if FRngState = 0 then FRngState := 1;
  FActiveParticleCount := 0;
  FTotalSpawnedCount := 0;
  FCollisionEventCount := 0;
  FSubSparkSpawnCount := 0;
  ClearPreviewContainer;
end;

procedure TCastleNiagaraSystem.SpawnSingleParticle(const AIsSubSpark: Boolean;
  const AOverrideOrigin, AOverrideVel: TVector3);
var
  SlotIdx, I, M: Integer;
  P: TNiagaraParticle;
  Dir, RandDir: TVector3;
  Spd, ConeRad: Single;
begin
  SlotIdx := -1;
  for I := 0 to High(FParticles) do
    if not FParticles[I].Alive then
    begin
      SlotIdx := I;
      Break;
    end;
  if SlotIdx < 0 then Exit;

  P := Default(TNiagaraParticle);
  P.Alive := True;
  P.IsSubSpark := AIsSubSpark;
  P.LifetimeSec := 1.2;
  P.BaseSize := 0.14;
  P.CurrentSize := 0.14;
  P.ColorRGBA := Vector4(1.0, 0.85, 0.35, 1.0);

  if AIsSubSpark then
  begin
    P.Position := AOverrideOrigin;
    P.Velocity := AOverrideVel;
    P.LifetimeSec := 0.45;
    P.BaseSize := 0.07;
    P.CurrentSize := 0.07;
    Inc(FSubSparkSpawnCount);
  end else
  begin
    { Execute Particle Spawn stage modules in stack order! }
    for M := 0 to High(FModules) do
      if FModules[M].Enabled and (FModules[M].Stage = nssParticleSpawn) then
        case FModules[M].Kind of
          nmkInitializeParticle:
            begin
              P.LifetimeSec := Max(0.05, Lerp(NextRandom01, FModules[M].ParamA, FModules[M].ParamB));
              P.BaseSize := Max(0.02, FModules[M].ParamC);
              P.CurrentSize := P.BaseSize;
              P.ColorRGBA := Vector4(FModules[M].VecA.X, FModules[M].VecA.Y, FModules[M].VecA.Z, 1.0);
            end;

          nmkSphereLocation:
            begin
              RandDir := Vector3(NextRandomSigned, NextRandomSigned, NextRandomSigned);
              if RandDir.LengthSqr > 1e-6 then
                RandDir := RandDir.Normalize * (NextRandom01 * FModules[M].ParamA);
              P.Position := P.Position + RandDir;
            end;

          nmkAddVelocityCone:
            begin
              Dir := FModules[M].VecA;
              if Dir.LengthSqr < 1e-6 then Dir := Vector3(0, 1, 0) else Dir := Dir.Normalize;
              ConeRad := DegToRad(EnsureRange(FModules[M].ParamC, 0.0, 89.0));
              RandDir := (Dir + Vector3(NextRandomSigned, NextRandomSigned, NextRandomSigned) * Sin(ConeRad)).Normalize;
              Spd := Lerp(NextRandom01, FModules[M].ParamA, FModules[M].ParamB);
              P.Velocity := P.Velocity + RandDir * Spd;
            end;
        end;
  end;

  FParticles[SlotIdx] := P;
  Inc(FTotalSpawnedCount);
end;

procedure TCastleNiagaraSystem.StepSystem(const ADeltaSeconds: Single);
var
  Dt, ToPullLen: Single;
  M, I, BurstCnt, SpawnCnt, K: Integer;
  ToTarget, CurlV, SparkVel: TVector3;
begin
  Dt := Max(0.0, ADeltaSeconds);
  if Dt <= 0.0 then Exit;

  { 1. Emitter Spawn stage (runs once at EmitterAge = 0) }
  if not FBurstSpawnFired then
  begin
    FBurstSpawnFired := True;
    for M := 0 to High(FModules) do
      if FModules[M].Enabled and (FModules[M].Stage = nssEmitterSpawn) and
         (FModules[M].Kind = nmkSpawnBurstInstantaneous) then
      begin
        BurstCnt := Round(Max(0.0, FModules[M].ParamA));
        for K := 1 to BurstCnt do
          SpawnSingleParticle(False, TVector3.Zero, TVector3.Zero);
      end;
  end;

  FEmitterAgeSec := FEmitterAgeSec + Dt;

  { 2. Emitter Update stage (continuous SpawnRate) }
  for M := 0 to High(FModules) do
    if FModules[M].Enabled and (FModules[M].Stage = nssEmitterUpdate) and
       (FModules[M].Kind = nmkSpawnRate) then
    begin
      FSpawnRateAccum := FSpawnRateAccum + Max(0.0, FModules[M].ParamA) * Dt;
      SpawnCnt := Floor(FSpawnRateAccum);
      if SpawnCnt > 0 then
      begin
        FSpawnRateAccum := FSpawnRateAccum - SpawnCnt;
        for K := 1 to SpawnCnt do
          SpawnSingleParticle(False, TVector3.Zero, TVector3.Zero);
      end;
    end;

  { 3. Particle Update stage (advance age, run ordered update modules, integrate) }
  FActiveParticleCount := 0;
  for I := 0 to High(FParticles) do
    if FParticles[I].Alive then
    begin
      FParticles[I].AgeSec := FParticles[I].AgeSec + Dt;
      if FParticles[I].AgeSec >= FParticles[I].LifetimeSec then
      begin
        FParticles[I].Alive := False;
        Continue;
      end;

      FParticles[I].NormalizedAge :=
        EnsureRange(FParticles[I].AgeSec / Max(0.01, FParticles[I].LifetimeSec), 0.0, 1.0);

      for M := 0 to High(FModules) do
        if FModules[M].Enabled and (FModules[M].Stage = nssParticleUpdate) then
          case FModules[M].Kind of
            nmkGravityForce:
              FParticles[I].Velocity := FParticles[I].Velocity + FModules[M].VecA * Dt;

            nmkDragForce:
              FParticles[I].Velocity := FParticles[I].Velocity *
                Max(0.0, 1.0 - Max(0.0, FModules[M].ParamA) * Dt);

            nmkCurlNoiseForce:
              begin
                CurlV := SampleCurlNoise3D(
                  FParticles[I].Position * Max(0.05, FModules[M].ParamB), FEmitterAgeSec);
                FParticles[I].Velocity := FParticles[I].Velocity +
                  CurlV * (FModules[M].ParamA * Dt);
              end;

            nmkPointAttractor:
              begin
                ToTarget := FModules[M].VecA - FParticles[I].Position;
                ToPullLen := ToTarget.Length;
                if (ToPullLen > 1e-4) and (ToPullLen <= Max(0.1, FModules[M].ParamB)) then
                  FParticles[I].Velocity := FParticles[I].Velocity +
                    (ToTarget / ToPullLen) * (FModules[M].ParamA * Dt);
              end;

            nmkScaleSizeByLifeCurve:
              FParticles[I].CurrentSize := Max(0.01,
                FParticles[I].BaseSize *
                FModules[M].ParamA *
                FModules[M].Curve.Evaluate(FParticles[I].NormalizedAge));

            nmkColorOverLifeLut:
              begin
                FParticles[I].ColorRGBA := Vector4(
                  Lerp(FParticles[I].NormalizedAge, FModules[M].VecA.X, FModules[M].VecB.X),
                  Lerp(FParticles[I].NormalizedAge, FModules[M].VecA.Y, FModules[M].VecB.Y),
                  Lerp(FParticles[I].NormalizedAge, FModules[M].VecA.Z, FModules[M].VecB.Z),
                  1.0 - FParticles[I].NormalizedAge * 0.85);
              end;
          end;

      { Integrate position }
      FParticles[I].Position := FParticles[I].Position + FParticles[I].Velocity * Dt;

      { Floor collision module pass post-integration }
      for M := 0 to High(FModules) do
        if FModules[M].Enabled and (FModules[M].Stage = nssParticleUpdate) and
           (FModules[M].Kind = nmkFloorCollisionBounce) then
        begin
          if (FParticles[I].Position.Y < FModules[M].ParamA) and
             (FParticles[I].Velocity.Y < 0.0) then
          begin
            FParticles[I].Position.Y := FModules[M].ParamA;
            FParticles[I].Velocity.Y := -FParticles[I].Velocity.Y *
              EnsureRange(FModules[M].ParamB, 0.0, 1.0);
            Inc(FCollisionEventCount);
            if FModules[M].BoolFlag and (not FParticles[I].IsSubSpark) then
            begin
              SparkVel := Vector3(NextRandomSigned * 2.0, 2.5 + NextRandom01 * 1.5, NextRandomSigned * 2.0);
              SpawnSingleParticle(True, FParticles[I].Position, SparkVel);
            end;
          end;
        end;

      Inc(FActiveParticleCount);
    end;

  { Recount active including any sub-sparks spawned on collision }
  FActiveParticleCount := 0;
  for I := 0 to High(FParticles) do
    if FParticles[I].Alive then
      Inc(FActiveParticleCount);

  SyncPreviewSprites;
end;

{ Built-In UE 5.5 Niagara Presets -------------------------------------------- }

procedure TCastleNiagaraSystem.ApplyPreset(const APreset: TNiagaraSystemPreset);
var
  M: TNiagaraModule;
begin
  FPreset := APreset;
  if APreset = nspCustom then Exit;

  ClearStack;
  FPreset := APreset;

  case APreset of
    nspArcaneVortexPortal:
      begin
        M := MakeDefaultModule('EU_SpawnRate', nmkSpawnRate);
        M.ParamA := 45.0;
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PS_Init', nmkInitializeParticle);
        M.ParamA := 1.4;
        M.ParamB := 2.2;
        M.ParamC := 0.16;
        M.VecA := Vector3(0.28, 0.86, 1.00);
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PS_Sphere', nmkSphereLocation);
        M.ParamA := 2.2;
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PU_CurlNoise', nmkCurlNoiseForce);
        M.ParamA := 3.8;
        M.ParamB := 0.65;
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PU_Attractor', nmkPointAttractor);
        M.ParamA := 16.0;
        M.ParamB := 15.0;
        M.VecA := Vector3(0, 2.5, 0);
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PU_Drag', nmkDragForce);
        M.ParamA := 0.85;
        AddOrUpdateModule(M);

        AddOrUpdateModule(MakeDefaultModule('PU_SizeCurve', nmkScaleSizeByLifeCurve));
        AddOrUpdateModule(MakeDefaultModule('PU_ColorLut', nmkColorOverLifeLut));
      end;

    nspAnvilSparksCollisionBurst:
      begin
        M := MakeDefaultModule('ES_Burst', nmkSpawnBurstInstantaneous);
        M.ParamA := 24.0;
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PS_Init', nmkInitializeParticle);
        M.ParamA := 1.5;
        M.ParamB := 2.0;
        M.ParamC := 0.10;
        M.VecA := Vector3(1.00, 0.82, 0.28);
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PS_ConeVel', nmkAddVelocityCone);
        M.ParamA := 3.5;
        M.ParamB := 5.5;
        M.ParamC := 28.0;
        M.VecA := Vector3(0, 1, 0);
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PU_Gravity', nmkGravityForce);
        M.VecA := Vector3(0, -14.0, 0);
        AddOrUpdateModule(M);

        M := MakeDefaultModule('PU_FloorBounce', nmkFloorCollisionBounce);
        M.ParamA := 0.0;
        M.ParamB := 0.60;
        M.BoolFlag := True;
        AddOrUpdateModule(M);

        AddOrUpdateModule(MakeDefaultModule('PU_SizeCurve', nmkScaleSizeByLifeCurve));
      end;

    nspCampfireEmberColumn:
      begin
        M := MakeDefaultModule('EU_SpawnRate', nmkSpawnRate);
        M.ParamA := 30.0;
        AddOrUpdateModule(M);

        AddOrUpdateModule(MakeDefaultModule('PS_Init', nmkInitializeParticle));
        M := MakeDefaultModule('PU_Buoyancy', nmkGravityForce);
        M.VecA := Vector3(0, 3.2, 0);
        AddOrUpdateModule(M);
        AddOrUpdateModule(MakeDefaultModule('PU_Curl', nmkCurlNoiseForce));
        AddOrUpdateModule(MakeDefaultModule('PU_ColorLut', nmkColorOverLifeLut));
      end;
  end;

  ResetSimulation;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleNiagaraSystem.GetStackJson: String;
var
  Root, Obj: TJSONObject;
  ModsArr, VecArr, KtArr, KvArr: TJSONArray;
  I, K: Integer;
begin
  Root := TJSONObject.Create;
  try
    ModsArr := TJSONArray.Create;
    for I := 0 to High(FModules) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FModules[I].ModuleId);
      Obj.Add('stage', Ord(FModules[I].Stage));
      Obj.Add('kind', Ord(FModules[I].Kind));
      Obj.Add('en', FModules[I].Enabled);
      Obj.Add('pa', FModules[I].ParamA);
      Obj.Add('pb', FModules[I].ParamB);
      Obj.Add('pc', FModules[I].ParamC);
      Obj.Add('bf', FModules[I].BoolFlag);
      VecArr := TJSONArray.Create;
      VecArr.Add(FModules[I].VecA.X);
      VecArr.Add(FModules[I].VecA.Y);
      VecArr.Add(FModules[I].VecA.Z);
      Obj.Add('va', VecArr);
      VecArr := TJSONArray.Create;
      VecArr.Add(FModules[I].VecB.X);
      VecArr.Add(FModules[I].VecB.Y);
      VecArr.Add(FModules[I].VecB.Z);
      Obj.Add('vb', VecArr);
      KtArr := TJSONArray.Create;
      KvArr := TJSONArray.Create;
      for K := 0 to 3 do
      begin
        KtArr.Add(FModules[I].Curve.KeyTimes[K]);
        KvArr.Add(FModules[I].Curve.KeyValues[K]);
      end;
      Obj.Add('kt', KtArr);
      Obj.Add('kv', KvArr);
      ModsArr.Add(Obj);
    end;
    Root.Add('modules', ModsArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleNiagaraSystem.SetStackJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr, VecArr, KtArr, KvArr: TJSONArray;
  I, K: Integer;
  M: TNiagaraModule;
begin
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;
  try
    if not (Parsed is TJSONObject) then Exit;
    Root := TJSONObject(Parsed);
    ClearStack;
    FPreset := nspCustom;

    Arr := Root.Find('modules', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          M := MakeDefaultModule(
            Obj.Get('id', 'Mod_' + IntToStr(I)),
            TNiagaraModuleKind(EnsureRange(Obj.Get('kind', 0), 0, Ord(High(TNiagaraModuleKind)))));
          M.Stage := TNiagaraStackStage(EnsureRange(Obj.Get('stage', Ord(M.Stage)), 0, Ord(High(TNiagaraStackStage))));
          M.Enabled := Obj.Get('en', True);
          M.ParamA := Obj.Get('pa', M.ParamA);
          M.ParamB := Obj.Get('pb', M.ParamB);
          M.ParamC := Obj.Get('pc', M.ParamC);
          M.BoolFlag := Obj.Get('bf', M.BoolFlag);
          VecArr := Obj.Find('va', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            M.VecA := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          VecArr := Obj.Find('vb', jtArray) as TJSONArray;
          if (VecArr <> nil) and (VecArr.Count >= 3) then
            M.VecB := Vector3(VecArr.Floats[0], VecArr.Floats[1], VecArr.Floats[2]);
          KtArr := Obj.Find('kt', jtArray) as TJSONArray;
          KvArr := Obj.Find('kv', jtArray) as TJSONArray;
          if (KtArr <> nil) and (KvArr <> nil) and (KtArr.Count >= 4) and (KvArr.Count >= 4) then
            for K := 0 to 3 do
            begin
              M.Curve.KeyTimes[K] := KtArr.Floats[K];
              M.Curve.KeyValues[K] := KvArr.Floats[K];
            end;
          AddOrUpdateModule(M);
        end;
    ResetSimulation;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleNiagaraSystem.NiagaraSummaryBadge: String;
begin
  Result := Format('[Niagara:Mods=%d Alive=%d/%d Coll=%d]',
    [Length(FModules), FActiveParticleCount, FMaxParticles, FCollisionEventCount]);
end;

initialization
  RegisterSerializableComponent(TCastleNiagaraSystem, 'Niagara Modular Emitter System');
end.
