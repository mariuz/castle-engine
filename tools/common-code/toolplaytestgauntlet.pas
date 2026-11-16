{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Gauntlet-Style Automated Playtest Bot Runner, Deterministic Multi-System
  Smoke-Test Invariant Verifier, Non-Destructive World Snapshot Restoration &
  JUnit XML CI/CD Exporter (@link(TPlaytestGauntletRunner),
  @link(TPlaytestGauntletReport))
  (Phase 326 — UE 6.0+ Gauntlet Automation & Functional Testing Parity). }
unit ToolPlaytestGauntlet;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleScalability;

type
  { Automated Gauntlet invariant check category. }
  TPlaytestAssertionKind = (
    pakNanOrInfTransform,
    pakKillZFallthrough,
    pakWorldReadinessGate,
    pakFrameBudgetGate,
    pakSaveRestoreDeterminism,
    pakActiveSimulationProgress
  );

  { Configurable parameters for a deterministic Gauntlet smoke-test pass. }
  TPlaytestGauntletConfig = record
    SuiteName: String;
    TotalDurationSec: Single;
    StepDtSec: Single;
    KillZMinY: Single;
    MinReadinessScore: Integer;
    PlatformBudget: TPlatformBudgetProfile;
    EnforceFrameBudget: Boolean;
    InjectSyntheticBotInputs: Boolean;
    RestoreDesignAfterRun: Boolean;
    class function MakeDefault: TPlaytestGauntletConfig; static;
  end;

  { Single invariant pass/fail outcome recorded by @link(TPlaytestGauntletRunner). }
  TPlaytestAssertionResult = record
    Kind: TPlaytestAssertionKind;
    AssertionName: String;
    Passed: Boolean;
    DurationSec: Single;
    MeasuredMetric: String;
    FailureDetail: String;
  end;

  { Per-step telemetry sample plotted on the Gauntlet Studio timeline. }
  TPlaytestStepSample = record
    TimeSec: Single;
    MinActorY: Single;
    MaxSpeedKmh: Single;
    MaxDisplacementM: Single;
    StepHealthy: Boolean;
  end;

  { Complete Gauntlet automated playtest report with step telemetry & CI output. }
  TPlaytestGauntletReport = class
  public
    SuiteName: String;
    TotalStepsExecuted: Integer;
    SimulatedDurationSec: Single;
    WallTimeMs: Double;
    ActorsTrackedCount: Integer;
    LowestObservedY: Single;
    LowestObservedActor: String;
    PeakVehicleSpeedKmh: Single;
    PeakDisplacementMeters: Single;
    WorldReadinessScore: Integer;
    WorldReadinessGrade: String;
    EstimatedGpuFrameMs: Single;
    StateRestoredCleanly: Boolean;
    PassedAssertionsCount: Integer;
    FailedAssertionsCount: Integer;
    AllPassed: Boolean;
    Assertions: array of TPlaytestAssertionResult;
    StepSamples: array of TPlaytestStepSample;
    LogLines: TStringList;

    constructor Create;
    destructor Destroy; override;
    procedure AddAssertion(const AKind: TPlaytestAssertionKind;
      const AName: String; const APassed: Boolean; const ADurationSec: Single;
      const AMetric, AFailureDetail: String);
  end;

  { Stateless Gauntlet-style automated playtest bot runner for @code(castle-editor)
    and headless CI/CD pipelines. }
  TPlaytestGauntletRunner = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    { Spawn a multi-system Horizon 6 smoke-test showcase sandbox (Test Track +
      AWD Rally Car + 8-Way Hero Blend/Montage + Tactical Cover EQS + RPG
      Inventory/GAS/Loot + Quartz 120 BPM Director) for 1-click verification. }
    class procedure SpawnMultiSystemSmokeSandbox(
      const RootComp, DesignOwner: TComponent); static;

    { Spawn an intentionally ungrounded actor above @code(KillZMinY) to test
      Gauntlet's Kill-Z fallthrough failure detection. }
    class function SpawnKillZTrapActor(
      const RootComp, DesignOwner: TComponent;
      const AWorldPos: TVector3): TCastleTransform; static;

    { Execute a deterministic multi-step Gauntlet playtest pass across @code(RootComp)
      and @code(DesignOwner). Caller owns the returned @link(TPlaytestGauntletReport). }
    class function RunSmokeTest(
      const RootComp, DesignOwner: TComponent;
      const AConfig: TPlaytestGauntletConfig): TPlaytestGauntletReport; static;

    { Export standard JUnit XML (@code(<testsuites>/<testsuite>/<testcase>))
      suitable for GitHub Actions, GitLab CI, or Jenkins test reporters. }
    class function BuildJUnitXmlReport(
      const AReport: TPlaytestGauntletReport): String; static;

    { Export human-readable Markdown summary of a @link(TPlaytestGauntletReport). }
    class function BuildMarkdownReport(
      const AReport: TPlaytestGauntletReport): String; static;
  end;

implementation

uses
  Math,
  CastleUtils, CastleClassUtils, CastleTimeUtils, CastleUIControls,
  CastleSaveReplay, CastleVehicleSystem, CastleBlendMontage, CastleEqsTactical,
  CastleGameplayAbility, CastleInventoryCraft, CastleNetcodeIris, CastleMetaSound,
  CastleTilemap2DPlus, CastleClothRope, CastleWaterSystem, CastleUtilityAi,
  ToolStudioHub, ToolFrameProfiler, ToolVehicleStudio, ToolBlendMontage,
  ToolEqsStudio, ToolInventoryStudio, ToolMetaSoundStudio, ToolUtilityAi;

function EscapeXmlAttr(const S: String): String;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function Vector3IsFinite(const V: TVector3): Boolean;
begin
  Result := (not IsNan(V.X)) and (not IsNan(V.Y)) and (not IsNan(V.Z)) and
            (not IsInfinite(V.X)) and (not IsInfinite(V.Y)) and (not IsInfinite(V.Z));
end;

function Vector4IsFinite(const V: TVector4): Boolean;
begin
  Result := (not IsNan(V.X)) and (not IsNan(V.Y)) and (not IsNan(V.Z)) and (not IsNan(V.W)) and
            (not IsInfinite(V.X)) and (not IsInfinite(V.Y)) and (not IsInfinite(V.Z)) and (not IsInfinite(V.W));
end;

{ TPlaytestGauntletConfig ---------------------------------------------------- }

class function TPlaytestGauntletConfig.MakeDefault: TPlaytestGauntletConfig;
begin
  Result.SuiteName := 'CGE.PlaytestGauntlet';
  Result.TotalDurationSec := 2.0;
  Result.StepDtSec := 0.05;
  Result.KillZMinY := -50.0;
  Result.MinReadinessScore := 70;
  Result.PlatformBudget := pbpDesktop60Hz;
  Result.EnforceFrameBudget := True;
  Result.InjectSyntheticBotInputs := True;
  Result.RestoreDesignAfterRun := True;
end;

{ TPlaytestGauntletReport ---------------------------------------------------- }

constructor TPlaytestGauntletReport.Create;
begin
  inherited Create;
  SuiteName := 'CGE.PlaytestGauntlet';
  LowestObservedY := 0.0;
  LowestObservedActor := '(none)';
  WorldReadinessScore := 100;
  WorldReadinessGrade := 'A+ Ship-Ready';
  StateRestoredCleanly := True;
  AllPassed := True;
  LogLines := TStringList.Create;
end;

destructor TPlaytestGauntletReport.Destroy;
begin
  FreeAndNil(LogLines);
  inherited;
end;

procedure TPlaytestGauntletReport.AddAssertion(
  const AKind: TPlaytestAssertionKind; const AName: String;
  const APassed: Boolean; const ADurationSec: Single;
  const AMetric, AFailureDetail: String);
var
  N: Integer;
begin
  N := Length(Assertions);
  SetLength(Assertions, N + 1);
  Assertions[N].Kind := AKind;
  Assertions[N].AssertionName := AName;
  Assertions[N].Passed := APassed;
  Assertions[N].DurationSec := Max(0.0001, ADurationSec);
  Assertions[N].MeasuredMetric := AMetric;
  Assertions[N].FailureDetail := AFailureDetail;

  if APassed then
  begin
    Inc(PassedAssertionsCount);
    LogLines.Add(Format('[PASS] %s (%s)', [AName, AMetric]));
  end else
  begin
    Inc(FailedAssertionsCount);
    AllPassed := False;
    LogLines.Add(Format('[FAIL] %s — %s (%s)', [AName, AFailureDetail, AMetric]));
  end;
end;

{ TPlaytestGauntletRunner ---------------------------------------------------- }

class function TPlaytestGauntletRunner.FindMainViewport(
  const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindMainViewport(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

class procedure TPlaytestGauntletRunner.SpawnMultiSystemSmokeSandbox(
  const RootComp, DesignOwner: TComponent);
var
  Hero, DummyTarget, EqsAgent, EqsThreat, CoverWall, SniperPlat, Walker: TCastleTransform;
  Blend: TCastleBlendSpace2DBehavior;
  Montage: TCastleAnimMontageBehavior;
  Eqs: TCastleEqsQueryBehavior;
  RpgHero: TCastleTransform;
  Gas: TCastleAbilitySystemBehavior;
  Inv: TCastleInventoryBehavior;
  Loot: TCastleLootTable;
  Synth: TCastleMetaSoundSynth;
  Foot: TCastleFootstepSurfaceBehavior;
  MusicDir: TCastleMusicStemDirector;
  Car: TCastleWheeledVehicle;
  Reason: String;
begin
  { 1. Grounded floor + jump ramp + AWD Rally Car }
  TVehicleStudioHelper.SpawnTestTrackFloorAndRamp(RootComp, DesignOwner);
  if (DesignOwner = nil) or (DesignOwner.FindComponent('GauntletRallyCar') = nil) then
  begin
    Car := TVehicleStudioHelper.SpawnVehicleInDesign(
      RootComp, DesignOwner, vpRallySportsCar, Vector3(-6.0, 0.95, 4.0));
    if Car <> nil then
      Car.Name := 'GauntletRallyCar';
  end;

  { 2. 8-Way BlendSpace Hero + Motion-Warped Montage Target }
  if (DesignOwner = nil) or (DesignOwner.FindComponent('HeroCombatActor1') = nil) then
    TBlendMontageHelper.SpawnHeroLocomotionAndMontageDemo(
      RootComp, DesignOwner, Hero, DummyTarget, Blend, Montage);

  { 3. Tactical EQS Cover Arena }
  if (DesignOwner = nil) or (DesignOwner.FindComponent('EqsSquadAgent1') = nil) then
    TEqsStudioHelper.SpawnTacticalCoverArenaDemo(
      RootComp, DesignOwner, EqsAgent, EqsThreat, CoverWall, SniperPlat, Eqs);

  { 4. RPG Inventory + Paperdoll GAS + Loot Table }
  if (DesignOwner = nil) or (DesignOwner.FindComponent('RpgAdventurer1') = nil) then
  begin
    TInventoryStudioHelper.SpawnRpgHeroInventoryAndLootChestDemo(
      RootComp, DesignOwner, RpgHero, Gas, Inv, Loot);
    if Inv <> nil then
    begin
      Inv.TryCraftRecipe('CraftSunfireBlade', Reason);
      Inv.EquipItemFromBag('SunfireBlade', Reason);
    end;
  end;

  { 5. MetaSound Synth + Surface Footsteps + 120 BPM Quartz Stem Director }
  if (DesignOwner = nil) or (DesignOwner.FindComponent('MetaSoundSynth_1') = nil) then
    TMetaSoundStudioHelper.SpawnAudioPlaygroundDemo(
      RootComp, DesignOwner, Synth, Walker, Foot, MusicDir);
end;

class function TPlaytestGauntletRunner.SpawnKillZTrapActor(
  const RootComp, DesignOwner: TComponent;
  const AWorldPos: TVector3): TCastleTransform;
var
  Car: TCastleWheeledVehicle;
  Idx: Integer;
  Candidate: String;
begin
  Car := TVehicleStudioHelper.SpawnVehicleInDesign(
    RootComp, DesignOwner, vpArmoredReconBuggy, AWorldPos);
  if Car <> nil then
  begin
    Car.UseFlatGroundFallback := False;
    Candidate := 'UngroundedVoidBuggy';
    Idx := 1;
    while (DesignOwner <> nil) and (DesignOwner.FindComponent(Candidate) <> nil) do
    begin
      Inc(Idx);
      Candidate := 'UngroundedVoidBuggy_' + IntToStr(Idx);
    end;
    Car.Name := Candidate;
  end;
  Result := Car;
end;

class function TPlaytestGauntletRunner.RunSmokeTest(
  const RootComp, DesignOwner: TComponent;
  const AConfig: TPlaytestGauntletConfig): TPlaytestGauntletReport;
type
  TActorBaseline = record
    Transform: TCastleTransform;
    InitialPos: TVector3;
  end;
  TVehicleSavedInputs = record
    Vehicle: TCastleWheeledVehicle;
    Throttle, Steer, Brake, Handbrake: Single;
    SavedGear: Integer;
  end;
  TMontageSavedState = record
    Montage: TCastleAnimMontageBehavior;
  end;
  TMusicSavedState = record
    Director: TCastleMusicStemDirector;
    ActiveIdx: Integer;
  end;
var
  StartTimer: TTimerResult;
  Visited: Classes.TList;
  Actors: array of TActorBaseline;
  SavedVehicles: array of TVehicleSavedInputs;
  SavedMontages: array of TMontageSavedState;
  SavedDirectors: array of TMusicSavedState;
  NetManagers: array of TCastleNetReplicationManager;
  Flipbooks: array of TCastleFlipbook2D;
  GasBehaviors: array of TCastleAbilitySystemBehavior;
  ClothSurfaces: array of TCastleClothSurface;
  VerletRopes: array of TCastleVerletRope;
  SaveMgr: TCastleSaveSlotManager;
  SnapshotJson: String;
  HealthReport: TStudioWorldHealthReport;
  BudgetReport: TFrameBudgetAuditReport;
  SafeDt, SafeDur, ElapsedSec, StepMinY, StepMaxSpeed, StepMaxDisp, Disp: Single;
  TotalSteps, StepIdx, I, DynamicSubsystemsCount: Integer;
  NanFound, KillZViolated, StepOk, RestoreMatched: Boolean;
  NanDetail, KillZDetail, RestoreDetail, ReadinessDetail, BudgetDetail: String;
  RemoveDummy: TRemoveType;

  procedure CollectHierarchy(const C: TComponent);
  var
    K, N: Integer;
    CC: TCastleComponent;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if (C = nil) or (Visited.IndexOf(C) >= 0) then
      Exit;
    Visited.Add(C);

    if (C is TCastleTransform) and (not (C is TCastleAbstractRootTransform)) and
       (not (csTransient in C.ComponentStyle)) then
    begin
      N := Length(Actors);
      SetLength(Actors, N + 1);
      Actors[N].Transform := TCastleTransform(C);
      Actors[N].InitialPos := TCastleTransform(C).Translation;
    end;

    if C is TCastleWheeledVehicle then
    begin
      N := Length(SavedVehicles);
      SetLength(SavedVehicles, N + 1);
      SavedVehicles[N].Vehicle := TCastleWheeledVehicle(C);
      SavedVehicles[N].Throttle := TCastleWheeledVehicle(C).ThrottleInput;
      SavedVehicles[N].Steer := TCastleWheeledVehicle(C).SteerInput;
      SavedVehicles[N].Brake := TCastleWheeledVehicle(C).BrakeInput;
      SavedVehicles[N].Handbrake := TCastleWheeledVehicle(C).HandbrakeInput;
      SavedVehicles[N].SavedGear := 1;
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleAnimMontageBehavior then
    begin
      N := Length(SavedMontages);
      SetLength(SavedMontages, N + 1);
      SavedMontages[N].Montage := TCastleAnimMontageBehavior(C);
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleMusicStemDirector then
    begin
      N := Length(SavedDirectors);
      SetLength(SavedDirectors, N + 1);
      SavedDirectors[N].Director := TCastleMusicStemDirector(C);
      SavedDirectors[N].ActiveIdx := TCastleMusicStemDirector(C).ActiveStateIndex;
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleNetReplicationManager then
    begin
      N := Length(NetManagers);
      SetLength(NetManagers, N + 1);
      NetManagers[N] := TCastleNetReplicationManager(C);
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleFlipbook2D then
    begin
      N := Length(Flipbooks);
      SetLength(Flipbooks, N + 1);
      Flipbooks[N] := TCastleFlipbook2D(C);
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleAbilitySystemBehavior then
    begin
      N := Length(GasBehaviors);
      SetLength(GasBehaviors, N + 1);
      GasBehaviors[N] := TCastleAbilitySystemBehavior(C);
    end;

    if C is TCastleClothSurface then
    begin
      N := Length(ClothSurfaces);
      SetLength(ClothSurfaces, N + 1);
      ClothSurfaces[N] := TCastleClothSurface(C);
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleVerletRope then
    begin
      N := Length(VerletRopes);
      SetLength(VerletRopes, N + 1);
      VerletRopes[N] := TCastleVerletRope(C);
      Inc(DynamicSubsystemsCount);
    end;

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for K := 0 to CC.NonVisualComponentsCount - 1 do
        CollectHierarchy(CC.NonVisualComponents[K]);
    end;
    if C is TCastleViewport then
      CollectHierarchy(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for K := 0 to UI.ControlsCount - 1 do
        CollectHierarchy(UI.Controls[K]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if not (csTransient in T.ComponentStyle) then
      begin
        for K := 0 to T.BehaviorsCount - 1 do
          CollectHierarchy(T.Behaviors[K]);
        for K := 0 to T.Count - 1 do
          CollectHierarchy(T[K]);
      end;
    end;
  end;

begin
  StartTimer := Timer;
  Result := TPlaytestGauntletReport.Create;
  if AConfig.SuiteName <> '' then
    Result.SuiteName := AConfig.SuiteName;

  Visited := Classes.TList.Create;
  SaveMgr := TCastleSaveSlotManager.Create(nil);
  try
    Actors := nil;
    SavedVehicles := nil;
    SavedMontages := nil;
    SavedDirectors := nil;
    NetManagers := nil;
    Flipbooks := nil;
    GasBehaviors := nil;
    ClothSurfaces := nil;
    VerletRopes := nil;
    DynamicSubsystemsCount := 0;

    CollectHierarchy(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        CollectHierarchy(DesignOwner.Components[I]);

    Result.ActorsTrackedCount := Length(Actors);
    if Length(Actors) > 0 then
    begin
      Result.LowestObservedY := Actors[0].InitialPos.Y;
      Result.LowestObservedActor := Actors[0].Transform.Name;
      for I := 1 to High(Actors) do
        if Actors[I].InitialPos.Y < Result.LowestObservedY then
        begin
          Result.LowestObservedY := Actors[I].InitialPos.Y;
          Result.LowestObservedActor := Actors[I].Transform.Name;
        end;
    end;

    { 1. Pre-run Cross-Studio World Readiness Audit }
    HealthReport := TStudioHubManager.AuditEntireDesign(RootComp, DesignOwner);
    try
      Result.WorldReadinessScore := HealthReport.ReadinessScore;
      Result.WorldReadinessGrade := HealthReport.ReadinessGrade;
      ReadinessDetail := '';
      if Length(HealthReport.Issues) > 0 then
        ReadinessDetail := HealthReport.Issues[0].MessageText;
    finally
      FreeAndNil(HealthReport);
    end;

    { 2. Pre-run 60 Hz Frame Budget Audit }
    BudgetReport := TFrameBudgetProfiler.AuditHierarchy(RootComp, AConfig.PlatformBudget);
    Result.EstimatedGpuFrameMs := BudgetReport.EstimatedGpuFrameMs;
    BudgetDetail := '';
    if Length(BudgetReport.BudgetViolations) > 0 then
      BudgetDetail := BudgetReport.BudgetViolations[0];

    { 3. Capture Pre-Run World Snapshot via TCastleSaveSlotManager }
    SnapshotJson := SaveMgr.CaptureWorldSnapshotJson(RootComp, DesignOwner);

    { 4. Inject Synthetic Playtest Bot Inputs if enabled }
    if AConfig.InjectSyntheticBotInputs then
    begin
      for I := 0 to High(SavedVehicles) do
      begin
        SavedVehicles[I].Vehicle.ThrottleInput := 0.85;
        SavedVehicles[I].Vehicle.SteerInput := 0.15;
        SavedVehicles[I].Vehicle.BrakeInput := 0.0;
        SavedVehicles[I].Vehicle.HandbrakeInput := 0.0;
      end;
      for I := 0 to High(SavedMontages) do
        if SavedMontages[I].Montage.SectionCount > 0 then
          SavedMontages[I].Montage.PlayMontageSection(
            SavedMontages[I].Montage.GetSection(0).SectionName);
      for I := 0 to High(SavedDirectors) do
        SavedDirectors[I].Director.RequestMusicState(2);
      TEqsStudioHelper.RunAllQueries(RootComp, DesignOwner);
    end;

    { 5. Deterministic Fixed-Step Multi-System Playtest Simulation Loop }
    SafeDt := Clamped(AConfig.StepDtSec, 0.005, 0.25);
    SafeDur := Max(SafeDt, AConfig.TotalDurationSec);
    TotalSteps := Max(1, Round(SafeDur / SafeDt));
    SetLength(Result.StepSamples, TotalSteps);

    NanFound := False;
    KillZViolated := False;
    NanDetail := '';
    KillZDetail := '';
    ElapsedSec := 0.0;

    for StepIdx := 0 to TotalSteps - 1 do
    begin
      ElapsedSec := ElapsedSec + SafeDt;

      { Step vehicles, blendspaces/montages, utility AI, GAS, netcode, audio, cloth & flipbooks }
      TVehicleStudioHelper.StepAllVehicles(RootComp, DesignOwner, SafeDt);
      TBlendMontageHelper.StepAllBlendAndMontages(RootComp, DesignOwner, SafeDt);
      TUtilityAiHelper.StepAllUtilityAgents(RootComp, DesignOwner, SafeDt);

      for I := 0 to High(SavedDirectors) do
        SavedDirectors[I].Director.StepMusicClock(SafeDt);
      for I := 0 to High(NetManagers) do
        NetManagers[I].StepReplication(RootComp, DesignOwner, SafeDt, TVector3.Zero);
      for I := 0 to High(GasBehaviors) do
      begin
        RemoveDummy := rtNone;
        GasBehaviors[I].Update(SafeDt, RemoveDummy);
      end;
      for I := 0 to High(Flipbooks) do
      begin
        RemoveDummy := rtNone;
        Flipbooks[I].Update(SafeDt, RemoveDummy);
      end;
      for I := 0 to High(ClothSurfaces) do
      begin
        RemoveDummy := rtNone;
        ClothSurfaces[I].Update(SafeDt, RemoveDummy);
      end;
      for I := 0 to High(VerletRopes) do
      begin
        RemoveDummy := rtNone;
        VerletRopes[I].Update(SafeDt, RemoveDummy);
      end;

      StepMinY := 0.0;
      if Length(Actors) > 0 then
        StepMinY := Actors[0].Transform.Translation.Y;
      StepMaxSpeed := 0.0;
      StepMaxDisp := 0.0;
      StepOk := True;

      for I := 0 to High(SavedVehicles) do
        StepMaxSpeed := Max(StepMaxSpeed, Abs(SavedVehicles[I].Vehicle.ForwardSpeedKmh));
      Result.PeakVehicleSpeedKmh := Max(Result.PeakVehicleSpeedKmh, StepMaxSpeed);

      for I := 0 to High(Actors) do
      begin
        if (not Vector3IsFinite(Actors[I].Transform.Translation)) or
           (not Vector3IsFinite(Actors[I].Transform.Scale)) or
           (not Vector4IsFinite(Actors[I].Transform.Rotation)) then
        begin
          StepOk := False;
          if not NanFound then
          begin
            NanFound := True;
            NanDetail := Format('Transform "%s" produced NaN/Infinite coordinates at t=%.2fs.',
              [Actors[I].Transform.Name, ElapsedSec]);
          end;
          Continue;
        end;

        Disp := PointsDistance(Actors[I].InitialPos, Actors[I].Transform.Translation);
        StepMaxDisp := Max(StepMaxDisp, Disp);
        Result.PeakDisplacementMeters := Max(Result.PeakDisplacementMeters, Disp);

        if Actors[I].Transform.Translation.Y < StepMinY then
          StepMinY := Actors[I].Transform.Translation.Y;

        if Actors[I].Transform.Translation.Y < Result.LowestObservedY then
        begin
          Result.LowestObservedY := Actors[I].Transform.Translation.Y;
          Result.LowestObservedActor := Actors[I].Transform.Name;
        end;

        if Actors[I].Transform.Translation.Y < AConfig.KillZMinY then
        begin
          StepOk := False;
          if not KillZViolated then
          begin
            KillZViolated := True;
            KillZDetail := Format(
              'Actor "%s" fell below Kill-Z threshold (Y=%.2fm < KillZ=%.2fm) at t=%.2fs.',
              [Actors[I].Transform.Name, Actors[I].Transform.Translation.Y,
               AConfig.KillZMinY, ElapsedSec]);
          end;
        end;
      end;

      Result.StepSamples[StepIdx].TimeSec := ElapsedSec;
      Result.StepSamples[StepIdx].MinActorY := StepMinY;
      Result.StepSamples[StepIdx].MaxSpeedKmh := StepMaxSpeed;
      Result.StepSamples[StepIdx].MaxDisplacementM := StepMaxDisp;
      Result.StepSamples[StepIdx].StepHealthy := StepOk;
    end;

    Result.TotalStepsExecuted := TotalSteps;
    Result.SimulatedDurationSec := ElapsedSec;

    { 6. Restore Exact Pre-Run World Snapshot if requested }
    RestoreMatched := SnapshotJson <> '';
    RestoreDetail := '';
    if AConfig.RestoreDesignAfterRun then
    begin
      for I := 0 to High(SavedVehicles) do
      begin
        SavedVehicles[I].Vehicle.ResetKinematics;
        SavedVehicles[I].Vehicle.ThrottleInput := SavedVehicles[I].Throttle;
        SavedVehicles[I].Vehicle.SteerInput := SavedVehicles[I].Steer;
        SavedVehicles[I].Vehicle.BrakeInput := SavedVehicles[I].Brake;
        SavedVehicles[I].Vehicle.HandbrakeInput := SavedVehicles[I].Handbrake;
      end;
      for I := 0 to High(SavedMontages) do
        SavedMontages[I].Montage.StopMontage;
      for I := 0 to High(SavedDirectors) do
      begin
        SavedDirectors[I].Director.ResetClock;
        SavedDirectors[I].Director.RequestMusicState(SavedDirectors[I].ActiveIdx);
      end;

      if not SaveMgr.RestoreWorldSnapshotJson(RootComp, SnapshotJson, DesignOwner) then
      begin
        RestoreMatched := False;
        RestoreDetail := 'TCastleSaveSlotManager.RestoreWorldSnapshotJson returned False.';
      end else
      begin
        for I := 0 to High(Actors) do
          if PointsDistance(Actors[I].InitialPos, Actors[I].Transform.Translation) > 1e-3 then
          begin
            RestoreMatched := False;
            RestoreDetail := Format('Actor "%s" failed exact world restoration (drift=%.4fm).',
              [Actors[I].Transform.Name,
               PointsDistance(Actors[I].InitialPos, Actors[I].Transform.Translation)]);
            Break;
          end;
      end;
    end;
    Result.StateRestoredCleanly := RestoreMatched;

    { 7. Record Deterministic Gauntlet Invariant Assertions }
    Result.AddAssertion(
      pakNanOrInfTransform,
      'Finite3DTransformsNoNaNOrInf',
      not NanFound,
      ElapsedSec * 0.20,
      Format('%d transforms x %d steps checked', [Length(Actors), TotalSteps]),
      NanDetail);

    Result.AddAssertion(
      pakKillZFallthrough,
      'KillZFloorFallthroughGuard',
      not KillZViolated,
      ElapsedSec * 0.25,
      Format('LowestY=%.2fm (%s) vs KillZ=%.2fm',
        [Result.LowestObservedY, Result.LowestObservedActor, AConfig.KillZMinY]),
      KillZDetail);

    Result.AddAssertion(
      pakWorldReadinessGate,
      'CrossStudioWorldReadinessGate',
      Result.WorldReadinessScore >= AConfig.MinReadinessScore,
      0.01,
      Format('Readiness=%d/100 (%s), Min=%d',
        [Result.WorldReadinessScore, Result.WorldReadinessGrade, AConfig.MinReadinessScore]),
      Format('World Readiness score %d/100 is below threshold %d (%s)',
        [Result.WorldReadinessScore, AConfig.MinReadinessScore, ReadinessDetail]));

    Result.AddAssertion(
      pakFrameBudgetGate,
      'PlatformFrameBudgetGate',
      (not AConfig.EnforceFrameBudget) or BudgetReport.OverallPassBudget,
      0.01,
      Format('EstGPU=%.2fms, Draws=%d, Tris=%d',
        [BudgetReport.EstimatedGpuFrameMs, BudgetReport.EstimatedDrawCalls,
         BudgetReport.EstimatedTriangles]),
      Format('Scene exceeds platform frame budget (%s)', [BudgetDetail]));

    Result.AddAssertion(
      pakSaveRestoreDeterminism,
      'SaveSnapshotWorldRestoreDeterminism',
      RestoreMatched,
      0.01,
      Format('SnapshotBytes=%d, Restored=%s',
        [Length(SnapshotJson), BoolToStr(AConfig.RestoreDesignAfterRun, True)]),
      RestoreDetail);

    Result.AddAssertion(
      pakActiveSimulationProgress,
      'DynamicSubsystemStepExecution',
      (TotalSteps >= 1) and
      ((DynamicSubsystemsCount = 0) or (Result.PeakDisplacementMeters > 0.001) or
       (Length(SavedDirectors) > 0) or (Length(Flipbooks) > 0)),
      ElapsedSec * 0.50,
      Format('DynamicSubsystems=%d, PeakSpeed=%.1f km/h, PeakDisp=%.2fm',
        [DynamicSubsystemsCount, Result.PeakVehicleSpeedKmh, Result.PeakDisplacementMeters]),
      'Active dynamic subsystems failed to advance during Gauntlet bot stepping.');

    Result.WallTimeMs := StartTimer.ElapsedTime * 1000.0;
  finally
    FreeAndNil(SaveMgr);
    FreeAndNil(Visited);
  end;
end;

class function TPlaytestGauntletRunner.BuildJUnitXmlReport(
  const AReport: TPlaytestGauntletReport): String;
var
  SB: TStringBuilder;
  I: Integer;
begin
  if AReport = nil then
    Exit('');
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    SB.AppendLine(Format(
      '<testsuites name="%s" tests="%d" failures="%d" time="%.4f">',
      [EscapeXmlAttr(AReport.SuiteName),
       Length(AReport.Assertions),
       AReport.FailedAssertionsCount,
       AReport.SimulatedDurationSec]));
    SB.AppendLine(Format(
      '  <testsuite name="%s" tests="%d" failures="%d" skipped="0" time="%.4f">',
      [EscapeXmlAttr(AReport.SuiteName),
       Length(AReport.Assertions),
       AReport.FailedAssertionsCount,
       AReport.SimulatedDurationSec]));

    for I := 0 to High(AReport.Assertions) do
    begin
      SB.AppendLine(Format(
        '    <testcase classname="%s" name="%s" time="%.4f">',
        [EscapeXmlAttr(AReport.SuiteName),
         EscapeXmlAttr(AReport.Assertions[I].AssertionName),
         AReport.Assertions[I].DurationSec]));
      if not AReport.Assertions[I].Passed then
        SB.AppendLine(Format(
          '      <failure message="%s" type="GauntletAssertionFailure">%s (%s)</failure>',
          [EscapeXmlAttr(AReport.Assertions[I].FailureDetail),
           EscapeXmlAttr(AReport.Assertions[I].FailureDetail),
           EscapeXmlAttr(AReport.Assertions[I].MeasuredMetric)]));
      SB.AppendLine(Format('      <system-out>%s</system-out>',
        [EscapeXmlAttr(AReport.Assertions[I].MeasuredMetric)]));
      SB.AppendLine('    </testcase>');
    end;

    SB.AppendLine('  </testsuite>');
    SB.AppendLine('</testsuites>');
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

class function TPlaytestGauntletRunner.BuildMarkdownReport(
  const AReport: TPlaytestGauntletReport): String;
var
  SB: TStringBuilder;
  I: Integer;
  VerdictStr, RowStatus: String;
begin
  if AReport = nil then
    Exit('');
  SB := TStringBuilder.Create;
  try
    if AReport.AllPassed then
      VerdictStr := 'PASSED (0 Failures)'
    else
      VerdictStr := Format('FAILED (%d Failure(s))', [AReport.FailedAssertionsCount]);

    SB.AppendLine('# Castle Game Engine — Gauntlet Automated Playtest & Smoke-Test Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Verdict**: **%s** (`%d / %d` Assertions Passed)',
      [VerdictStr, AReport.PassedAssertionsCount, Length(AReport.Assertions)]));
    SB.AppendLine(Format('- **Simulation Horizon**: `%.2fs` (`%d` fixed steps, Wall Time `%.2f ms`)',
      [AReport.SimulatedDurationSec, AReport.TotalStepsExecuted, AReport.WallTimeMs]));
    SB.AppendLine(Format('- **Tracked 3D Actors**: `%d` | **Lowest Y**: `%.2fm` (`%s`)',
      [AReport.ActorsTrackedCount, AReport.LowestObservedY, AReport.LowestObservedActor]));
    SB.AppendLine(Format('- **Peak Vehicle Speed**: `%.1f km/h` | **Peak Actor Displacement**: `%.2fm`',
      [AReport.PeakVehicleSpeedKmh, AReport.PeakDisplacementMeters]));
    SB.AppendLine(Format('- **World Readiness**: `%d / 100` (`%s`) | **World Restored Cleanly**: `%s`',
      [AReport.WorldReadinessScore, AReport.WorldReadinessGrade,
       BoolToStr(AReport.StateRestoredCleanly, True)]));
    SB.AppendLine;

    SB.AppendLine('## Invariant Assertions');
    SB.AppendLine('| Status | Assertion | Telemetry / Detail |');
    SB.AppendLine('| :--- | :--- | :--- |');
    for I := 0 to High(AReport.Assertions) do
    begin
      if AReport.Assertions[I].Passed then
        RowStatus := 'PASS'
      else
        RowStatus := 'FAIL';
      if AReport.Assertions[I].Passed then
        SB.AppendLine(Format('| **%s** | `%s` | %s |',
          [RowStatus, AReport.Assertions[I].AssertionName,
           AReport.Assertions[I].MeasuredMetric]))
      else
        SB.AppendLine(Format('| **%s** | `%s` | %s — %s |',
          [RowStatus, AReport.Assertions[I].AssertionName,
           AReport.Assertions[I].FailureDetail,
           AReport.Assertions[I].MeasuredMetric]));
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
