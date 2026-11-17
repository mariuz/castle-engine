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

{ Deterministic Golden-Snapshot 64-Bit FNV-1a World-State Hasher, Dual-Run
  Seeded Replay Verifier & Per-Actor Drift Auditor
  (Phase 346 — Unreal Engine 6.0+ Golden Automation & Determinism Parity). }
unit ToolRegressionHarness;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils, fpjson, jsonparser,
  CastleVectors, CastleViewport, CastleTransform, CastleUIControls,
  CastleStateTree, CastleControlRig, CastleSpringArm, CastleGameplayCue,
  CastleDataLayers, CastleJiggleBone, CastleSoundscape;

type
  { Quantized state digest for a single hierarchy actor. }
  TActorStateDigest = record
    ActorPath: String;
    ClassNameStr: String;
    ExistsFlag: Boolean;
    Translation: TVector3;
    Rotation: TVector4;
    Scale: TVector3;
    SubsystemTag: String;
    ActorHash64: QWord;
  end;

  { Golden world-state snapshot with 64-bit FNV-1a digest & JSON persistence. }
  TGoldenWorldSnapshot = class
  public
    LabelName: String;
    StepCount: Integer;
    SeedUsed: Integer;
    WorldHash64: QWord;
    WorldHashHex: String;
    Digests: array of TActorStateDigest;

    constructor Create;
    destructor Destroy; override;
    function ActorCount: Integer;
    function FindActorIndex(const AActorPath: String): Integer;
    function ExportJson: String;
    function LoadFromJson(const AJson: String): Boolean;
  end;

  { Per-actor drift entry discovered when comparing two world snapshots. }
  TRegressionDriftEntry = record
    ActorPath: String;
    DriftKind: String;
    PositionDeltaMeters: Single;
    Details: String;
  end;

  { Result of a dual-run determinism check or Golden vs. Live diff. }
  TDeterminismAuditResult = record
    BitExactMatch: Boolean;
    RunAHashHex: String;
    RunBHashHex: String;
    ActorsCompared: Integer;
    DriftedActorCount: Integer;
    MaxPositionDriftMeters: Single;
    StateRestoredCleanly: Boolean;
    Drifts: array of TRegressionDriftEntry;
  end;

  { Stateless 64-bit FNV-1a world-state hasher, dual-run determinism verifier,
    and per-actor drift auditor. }
  TDeterminismRegressionHarness = class
  public
    class function HashInit64: QWord; static;
    class function HashMixByte(const AHash: QWord; const AByte: Byte): QWord; static;
    class function HashMixInt64(const AHash: QWord; const AValue: Int64): QWord; static;
    class function HashMixString(const AHash: QWord; const AText: String): QWord; static;
    class function HashMixQuantizedFloat(const AHash: QWord; const AVal: Single): QWord; static;

    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;

    { Capture a canonically sorted 64-bit FNV-1a snapshot of all non-transient
      transforms and simulation subsystems under ARoot. }
    class function CaptureWorldSnapshot(const ARoot, ADesignOwner: TComponent;
      const ALabel: String = 'Live'; const ASteps: Integer = 0;
      const ASeed: Integer = 0): TGoldenWorldSnapshot; static;

    { Compare Expected (Golden) vs. Actual (Candidate) snapshots and pinpoint
      every added, missing, visibility-flipped, or position/subsystem-drifted actor. }
    class function CompareSnapshots(
      const AExpected, AActual: TGoldenWorldSnapshot): TDeterminismAuditResult; static;

    { Reset seeded simulation subsystems and step fixed-dt frames deterministically. }
    class procedure StepDeterministicSimulation(const ARoot: TComponent;
      const ASteps: Integer; const ADt: Single; const ASeed: Integer); static;

    { Execute two independent fixed-timestep runs from the exact same initial
      state & seed, verify bit-exact 64-bit FNV-1a hash parity, and restore the
      live editor design non-destructively. }
    class function VerifyDualRunDeterminism(const ARoot, ADesignOwner: TComponent;
      const ASteps: Integer = 20; const ADt: Single = 1.0 / 60.0;
      const ASeed: Integer = 20260346): TDeterminismAuditResult; static;

    class function BuildMarkdownReport(const AAudit: TDeterminismAuditResult;
      const ASnapshot: TGoldenWorldSnapshot = nil): String; static;
  end;

implementation

const
  FnvOffsetBasis64: QWord = QWord($CBF29CE484222325);
  FnvPrime64: QWord       = QWord($00000100000001B3);

type
  TSavedTransformPose = record
    Target: TCastleTransform;
    ExistsFlag: Boolean;
    Translation: TVector3;
    Rotation: TVector4;
    Scale: TVector3;
  end;

{ TGoldenWorldSnapshot ------------------------------------------------------- }

constructor TGoldenWorldSnapshot.Create;
begin
  inherited Create;
  LabelName := 'Snapshot';
  WorldHash64 := FnvOffsetBasis64;
  WorldHashHex := IntToHex(WorldHash64, 16);
end;

destructor TGoldenWorldSnapshot.Destroy;
begin
  SetLength(Digests, 0);
  inherited Destroy;
end;

function TGoldenWorldSnapshot.ActorCount: Integer;
begin
  Result := Length(Digests);
end;

function TGoldenWorldSnapshot.FindActorIndex(const AActorPath: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Digests) do
    if Digests[I].ActorPath = AActorPath then
      Exit(I);
  Result := -1;
end;

function TGoldenWorldSnapshot.ExportJson: String;
var
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('label', LabelName);
    RootObj.Add('stepCount', StepCount);
    RootObj.Add('seedUsed', SeedUsed);
    RootObj.Add('worldHashHex', WorldHashHex);
    Arr := TJSONArray.Create;
    RootObj.Add('actors', Arr);
    for I := 0 to High(Digests) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('path', Digests[I].ActorPath);
      ItemObj.Add('className', Digests[I].ClassNameStr);
      ItemObj.Add('exists', Digests[I].ExistsFlag);
      ItemObj.Add('tx', Digests[I].Translation.X);
      ItemObj.Add('ty', Digests[I].Translation.Y);
      ItemObj.Add('tz', Digests[I].Translation.Z);
      ItemObj.Add('rx', Digests[I].Rotation.X);
      ItemObj.Add('ry', Digests[I].Rotation.Y);
      ItemObj.Add('rz', Digests[I].Rotation.Z);
      ItemObj.Add('rw', Digests[I].Rotation.W);
      ItemObj.Add('sx', Digests[I].Scale.X);
      ItemObj.Add('sy', Digests[I].Scale.Y);
      ItemObj.Add('sz', Digests[I].Scale.Z);
      ItemObj.Add('sub', Digests[I].SubsystemTag);
      ItemObj.Add('hashHex', IntToHex(Digests[I].ActorHash64, 16));
      Arr.Add(ItemObj);
    end;
    Result := RootObj.FormatJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

function TGoldenWorldSnapshot.LoadFromJson(const AJson: String): Boolean;
var
  Data: TJSONData;
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := False;
  if Trim(AJson) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AJson);
    except
      Exit(False);
    end;
    if not (Data is TJSONObject) then Exit(False);
    RootObj := TJSONObject(Data);
    LabelName := RootObj.Get('label', 'LoadedGolden');
    StepCount := RootObj.Get('stepCount', 0);
    SeedUsed := RootObj.Get('seedUsed', 0);
    WorldHashHex := RootObj.Get('worldHashHex', '');
    WorldHash64 := StrToQWordDef('$' + WorldHashHex, FnvOffsetBasis64);

    Arr := RootObj.Find('actors', jtArray) as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(Digests, Arr.Count);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then Continue;
        ItemObj := TJSONObject(Arr.Items[I]);
        Digests[I].ActorPath := ItemObj.Get('path', '');
        Digests[I].ClassNameStr := ItemObj.Get('className', '');
        Digests[I].ExistsFlag := ItemObj.Get('exists', True);
        Digests[I].Translation := Vector3(ItemObj.Get('tx', 0.0), ItemObj.Get('ty', 0.0), ItemObj.Get('tz', 0.0));
        Digests[I].Rotation := Vector4(ItemObj.Get('rx', 0.0), ItemObj.Get('ry', 1.0), ItemObj.Get('rz', 0.0), ItemObj.Get('rw', 0.0));
        Digests[I].Scale := Vector3(ItemObj.Get('sx', 1.0), ItemObj.Get('sy', 1.0), ItemObj.Get('sz', 1.0));
        Digests[I].SubsystemTag := ItemObj.Get('sub', '');
        Digests[I].ActorHash64 := StrToQWordDef('$' + ItemObj.Get('hashHex', '0'), 0);
      end;
    end;
    Result := True;
  finally
    FreeAndNil(Data);
  end;
end;

{ TDeterminismRegressionHarness ---------------------------------------------- }

class function TDeterminismRegressionHarness.HashInit64: QWord;
begin
  Result := FnvOffsetBasis64;
end;

{$PUSH}{$Q-}{$R-}
class function TDeterminismRegressionHarness.HashMixByte(
  const AHash: QWord; const AByte: Byte): QWord;
begin
  Result := (AHash xor QWord(AByte)) * FnvPrime64;
end;

class function TDeterminismRegressionHarness.HashMixInt64(
  const AHash: QWord; const AValue: Int64): QWord;
var
  U: QWord;
  I: Integer;
begin
  U := QWord(AValue);
  Result := AHash;
  for I := 0 to 7 do
  begin
    Result := (Result xor (U and $FF)) * FnvPrime64;
    U := U shr 8;
  end;
end;
{$POP}

class function TDeterminismRegressionHarness.HashMixString(
  const AHash: QWord; const AText: String): QWord;
var
  I: Integer;
begin
  Result := HashMixInt64(AHash, Length(AText));
  for I := 1 to Length(AText) do
    Result := HashMixByte(Result, Byte(AText[I]));
end;

class function TDeterminismRegressionHarness.HashMixQuantizedFloat(
  const AHash: QWord; const AVal: Single): QWord;
var
  Q: Int64;
begin
  if IsNan(AVal) then
    Q := High(Int64)
  else if IsInfinite(AVal) then
    Q := Low(Int64) + 1
  else
    Q := Round(Double(AVal) * 1000.0);
  Result := HashMixInt64(AHash, Q);
end;

class function TDeterminismRegressionHarness.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

function ExtractSubsystemDeterminismTag(const T: TCastleTransform): String;
var
  I: Integer;
  B: TCastleBehavior;
  TipPos: TVector3;
  Parts: String;
begin
  Parts := '';
  if T is TCastleSpringArm then
    Parts := Parts + Format('SpringArm=%.3f;', [TCastleSpringArm(T).CurrentArmLength]);
  if T is TCastleGameplayCueDirector then
    Parts := Parts + Format('CuePool=%d/%.2f;', [
      TCastleGameplayCueDirector(T).ActivePopupCount,
      TCastleGameplayCueDirector(T).EffectiveWorldTimeScale]);
  if T is TCastleDataLayerManager then
    Parts := Parts + Format('DataLayers=%d/%d;', [
      TCastleDataLayerManager(T).ActivatedActorCount,
      TCastleDataLayerManager(T).TaggedActorCount]);
  if T is TCastleSoundscapeDirector then
    Parts := Parts + Format('Soundscape=%d/%d/%s;', [
      TCastleSoundscapeDirector(T).ActiveCallCount,
      TCastleSoundscapeDirector(T).OccludedCallCount,
      SoundscapeLayerToDisplayName(TCastleSoundscapeDirector(T).DominantBiomeLayer)]);

  for I := 0 to T.BehaviorsCount - 1 do
  begin
    B := T.Behaviors[I];
    if B is TCastleStateTreeBehavior then
      Parts := Parts + Format('StateTree=%s;', [TCastleStateTreeBehavior(B).ActiveStatePath])
    else if (B is TCastleControlRigBehavior) and (TCastleControlRigBehavior(B).JointCount > 0) then
    begin
      TipPos := TCastleControlRigBehavior(B).JointWorldPos(TCastleControlRigBehavior(B).JointCount - 1);
      Parts := Parts + Format('CtrlRig=(%.3f,%.3f,%.3f);', [TipPos.X, TipPos.Y, TipPos.Z]);
    end
    else if B is TCastleJiggleBoneBehavior then
      Parts := Parts + Format('Jiggle=(%.3f,%.3f,%.3f);', [
        TCastleJiggleBoneBehavior(B).CurrentTipWorld.X,
        TCastleJiggleBoneBehavior(B).CurrentTipWorld.Y,
        TCastleJiggleBoneBehavior(B).CurrentTipWorld.Z]);
  end;
  Result := Parts;
end;

class function TDeterminismRegressionHarness.CaptureWorldSnapshot(
  const ARoot, ADesignOwner: TComponent;
  const ALabel: String; const ASteps: Integer;
  const ASeed: Integer): TGoldenWorldSnapshot;
var
  RootT: TCastleTransform;
  CountDig: Integer;

  procedure CollectRec(const T: TCastleTransform; const APrefix: String);
  var
    I: Integer;
    NodeName, CurPath: String;
    D: TActorStateDigest;
    H: QWord;
  begin
    if T = nil then Exit;
    if (T <> RootT) and (csTransient in T.ComponentStyle) then
      Exit;

    if T <> RootT then
    begin
      NodeName := IfThen(T.Name <> '', T.Name, T.ClassName + '_' + IntToStr(CountDig));
      CurPath := IfThen(APrefix <> '', APrefix + '/' + NodeName, NodeName);

      D := Default(TActorStateDigest);
      D.ActorPath := CurPath;
      D.ClassNameStr := T.ClassName;
      D.ExistsFlag := T.Exists;
      D.Translation := T.Translation;
      D.Rotation := T.Rotation;
      D.Scale := T.Scale;
      D.SubsystemTag := ExtractSubsystemDeterminismTag(T);

      H := HashInit64;
      H := HashMixString(H, D.ActorPath);
      H := HashMixString(H, D.ClassNameStr);
      H := HashMixByte(H, Byte(Ord(D.ExistsFlag)));
      H := HashMixQuantizedFloat(H, D.Translation.X);
      H := HashMixQuantizedFloat(H, D.Translation.Y);
      H := HashMixQuantizedFloat(H, D.Translation.Z);
      H := HashMixQuantizedFloat(H, D.Rotation.X);
      H := HashMixQuantizedFloat(H, D.Rotation.Y);
      H := HashMixQuantizedFloat(H, D.Rotation.Z);
      H := HashMixQuantizedFloat(H, D.Rotation.W);
      H := HashMixQuantizedFloat(H, D.Scale.X);
      H := HashMixQuantizedFloat(H, D.Scale.Y);
      H := HashMixQuantizedFloat(H, D.Scale.Z);
      H := HashMixString(H, D.SubsystemTag);
      D.ActorHash64 := H;

      if CountDig >= Length(Result.Digests) then
        SetLength(Result.Digests, Max(16, CountDig * 2));
      Result.Digests[CountDig] := D;
      Inc(CountDig);
    end else
      CurPath := '';

    for I := 0 to T.Count - 1 do
      CollectRec(T[I], CurPath);
  end;

var
  I, J: Integer;
  Tmp: TActorStateDigest;
  WorldH: QWord;
begin
  Result := TGoldenWorldSnapshot.Create;
  Result.LabelName := ALabel;
  Result.StepCount := ASteps;
  Result.SeedUsed := ASeed;

  CountDig := 0;
  RootT := ResolveRootTransform(ARoot);
  if RootT <> nil then
    CollectRec(RootT, '');
  SetLength(Result.Digests, CountDig);

  { Canonical lexicographical sort by ActorPath }
  for I := 0 to CountDig - 2 do
    for J := I + 1 to CountDig - 1 do
      if CompareStr(Result.Digests[J].ActorPath, Result.Digests[I].ActorPath) < 0 then
      begin
        Tmp := Result.Digests[I];
        Result.Digests[I] := Result.Digests[J];
        Result.Digests[J] := Tmp;
      end;

  WorldH := HashInit64;
  WorldH := HashMixInt64(WorldH, CountDig);
  for I := 0 to CountDig - 1 do
    WorldH := HashMixInt64(WorldH, Int64(Result.Digests[I].ActorHash64));

  Result.WorldHash64 := WorldH;
  Result.WorldHashHex := IntToHex(WorldH, 16);
end;

class function TDeterminismRegressionHarness.CompareSnapshots(
  const AExpected, AActual: TGoldenWorldSnapshot): TDeterminismAuditResult;

  procedure AppendDrift(const APath, AKind: String; const APosDelta: Single;
    const ADetails: String);
  var
    N: Integer;
  begin
    N := Length(Result.Drifts);
    SetLength(Result.Drifts, N + 1);
    Result.Drifts[N].ActorPath := APath;
    Result.Drifts[N].DriftKind := AKind;
    Result.Drifts[N].PositionDeltaMeters := APosDelta;
    Result.Drifts[N].Details := ADetails;
    Inc(Result.DriftedActorCount);
    Result.MaxPositionDriftMeters := Max(Result.MaxPositionDriftMeters, APosDelta);
  end;

var
  I, MatchIdx: Integer;
  ExpD, ActD: TActorStateDigest;
  PosDelta: Single;
begin
  Result := Default(TDeterminismAuditResult);
  if (AExpected = nil) or (AActual = nil) then
    Exit;

  Result.RunAHashHex := AExpected.WorldHashHex;
  Result.RunBHashHex := AActual.WorldHashHex;
  Result.ActorsCompared := Max(AExpected.ActorCount, AActual.ActorCount);

  for I := 0 to AExpected.ActorCount - 1 do
  begin
    ExpD := AExpected.Digests[I];
    MatchIdx := AActual.FindActorIndex(ExpD.ActorPath);
    if MatchIdx < 0 then
    begin
      AppendDrift(ExpD.ActorPath, 'MISSING', 0.0, 'Actor present in Golden snapshot is missing in Actual.');
      Continue;
    end;

    ActD := AActual.Digests[MatchIdx];
    if ExpD.ActorHash64 = ActD.ActorHash64 then
      Continue;

    PosDelta := PointsDistance(ExpD.Translation, ActD.Translation);
    if ExpD.ExistsFlag <> ActD.ExistsFlag then
      AppendDrift(ExpD.ActorPath, 'VISIBILITY_DRIFT', PosDelta,
        Format('Exists changed from %s to %s', [
          BoolToStr(ExpD.ExistsFlag, True), BoolToStr(ActD.ExistsFlag, True)]))
    else if PosDelta >= 0.001 then
      AppendDrift(ExpD.ActorPath, 'TRANSFORM_DRIFT', PosDelta,
        Format('Position drifted by %.4fm: (%.3f, %.3f, %.3f) -> (%.3f, %.3f, %.3f)', [
          PosDelta,
          ExpD.Translation.X, ExpD.Translation.Y, ExpD.Translation.Z,
          ActD.Translation.X, ActD.Translation.Y, ActD.Translation.Z]))
    else if ExpD.SubsystemTag <> ActD.SubsystemTag then
      AppendDrift(ExpD.ActorPath, 'SUBSYSTEM_DRIFT', PosDelta,
        Format('Subsystem state "%s" != "%s"', [ExpD.SubsystemTag, ActD.SubsystemTag]))
    else
      AppendDrift(ExpD.ActorPath, 'ROT_SCALE_DRIFT', PosDelta,
        'Rotation or Scale quantized components diverged.');
  end;

  for I := 0 to AActual.ActorCount - 1 do
    if AExpected.FindActorIndex(AActual.Digests[I].ActorPath) < 0 then
      AppendDrift(AActual.Digests[I].ActorPath, 'ADDED', 0.0,
        'Unexpected actor added since Golden snapshot.');

  Result.BitExactMatch := (AExpected.WorldHash64 = AActual.WorldHash64) and
    (Result.DriftedActorCount = 0);
end;

class procedure TDeterminismRegressionHarness.StepDeterministicSimulation(
  const ARoot: TComponent; const ASteps: Integer;
  const ADt: Single; const ASeed: Integer);
var
  RootT: TCastleTransform;

  procedure ResetRec(const T: TCastleTransform);
  var
    I: Integer;
    B: TCastleBehavior;
  begin
    if T = nil then Exit;
    if (T <> RootT) and (csTransient in T.ComponentStyle) then Exit;

    if T is TCastleSoundscapeDirector then
    begin
      TCastleSoundscapeDirector(T).RandomSeed := ASeed;
      TCastleSoundscapeDirector(T).ClearActiveCalls;
    end;
    if T is TCastleGameplayCueDirector then
      TCastleGameplayCueDirector(T).ClearAllPopups;
    if T is TCastleDataLayerManager then
      TCastleDataLayerManager(T).ApplyDataLayersToWorld(RootT);

    for I := 0 to T.BehaviorsCount - 1 do
    begin
      B := T.Behaviors[I];
      if B is TCastleJiggleBoneBehavior then
        TCastleJiggleBoneBehavior(B).ResetSpringToRest
      else if B is TCastleStateTreeBehavior then
        TCastleStateTreeBehavior(B).RestartFromRoot;
    end;

    for I := 0 to T.Count - 1 do
      ResetRec(T[I]);
  end;

  procedure StepFrameRec(const T: TCastleTransform);
  var
    I: Integer;
    B: TCastleBehavior;
  begin
    if T = nil then Exit;
    if (T <> RootT) and (csTransient in T.ComponentStyle) then Exit;

    if T is TCastleSoundscapeDirector then
      TCastleSoundscapeDirector(T).StepSoundscape(RootT, Vector3(0.0, 1.7, 0.0), ADt);
    if T is TCastleGameplayCueDirector then
      TCastleGameplayCueDirector(T).StepDirector(ADt);
    if (T is TCastleSpringArm) and (RootT is TCastleAbstractRootTransform) then
      TCastleSpringArm(T).StepSpringArm(ADt, TCastleAbstractRootTransform(RootT));

    for I := 0 to T.BehaviorsCount - 1 do
    begin
      B := T.Behaviors[I];
      if B is TCastleJiggleBoneBehavior then
        TCastleJiggleBoneBehavior(B).StepSpring(ADt)
      else if B is TCastleControlRigBehavior then
        TCastleControlRigBehavior(B).SolveRig(ADt)
      else if B is TCastleStateTreeBehavior then
        TCastleStateTreeBehavior(B).StepTree(ADt);
    end;

    for I := 0 to T.Count - 1 do
      StepFrameRec(T[I]);
  end;

var
  StepIdx: Integer;
begin
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then Exit;

  ResetRec(RootT);
  for StepIdx := 1 to Max(0, ASteps) do
    StepFrameRec(RootT);
end;

class function TDeterminismRegressionHarness.VerifyDualRunDeterminism(
  const ARoot, ADesignOwner: TComponent;
  const ASteps: Integer; const ADt: Single;
  const ASeed: Integer): TDeterminismAuditResult;
var
  RootT: TCastleTransform;
  SavedPoses: array of TSavedTransformPose;
  PoseCount: Integer;

  procedure CapturePosesRec(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if T = nil then Exit;
    if (T <> RootT) and (csTransient in T.ComponentStyle) then Exit;
    if T <> RootT then
    begin
      if PoseCount >= Length(SavedPoses) then
        SetLength(SavedPoses, Max(16, PoseCount * 2));
      SavedPoses[PoseCount].Target := T;
      SavedPoses[PoseCount].ExistsFlag := T.Exists;
      SavedPoses[PoseCount].Translation := T.Translation;
      SavedPoses[PoseCount].Rotation := T.Rotation;
      SavedPoses[PoseCount].Scale := T.Scale;
      Inc(PoseCount);
    end;
    for I := 0 to T.Count - 1 do
      CapturePosesRec(T[I]);
  end;

  procedure RestorePoses;
  var
    I: Integer;
  begin
    for I := 0 to PoseCount - 1 do
      if SavedPoses[I].Target <> nil then
      begin
        SavedPoses[I].Target.Exists := SavedPoses[I].ExistsFlag;
        SavedPoses[I].Target.Translation := SavedPoses[I].Translation;
        SavedPoses[I].Target.Rotation := SavedPoses[I].Rotation;
        SavedPoses[I].Target.Scale := SavedPoses[I].Scale;
      end;
  end;

var
  PreSnap, SnapA, SnapB, PostRestoreSnap: TGoldenWorldSnapshot;
begin
  Result := Default(TDeterminismAuditResult);
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then Exit;

  PoseCount := 0;
  SavedPoses := nil;
  CapturePosesRec(RootT);
  StepDeterministicSimulation(ARoot, 0, ADt, ASeed);
  PreSnap := CaptureWorldSnapshot(ARoot, ADesignOwner, 'Baseline', 0, ASeed);
  SnapA := nil;
  SnapB := nil;
  PostRestoreSnap := nil;
  try
    { Run Pass A }
    RestorePoses;
    StepDeterministicSimulation(ARoot, ASteps, ADt, ASeed);
    SnapA := CaptureWorldSnapshot(ARoot, ADesignOwner, 'RunA', ASteps, ASeed);

    { Restore & Run Pass B }
    RestorePoses;
    StepDeterministicSimulation(ARoot, ASteps, ADt, ASeed);
    SnapB := CaptureWorldSnapshot(ARoot, ADesignOwner, 'RunB', ASteps, ASeed);

    Result := CompareSnapshots(SnapA, SnapB);

    { Restore live world to exact pre-verification pose }
    RestorePoses;
    StepDeterministicSimulation(ARoot, 0, ADt, ASeed);
    PostRestoreSnap := CaptureWorldSnapshot(ARoot, ADesignOwner, 'Restored', 0, ASeed);
    Result.StateRestoredCleanly := (PreSnap.WorldHash64 = PostRestoreSnap.WorldHash64);
  finally
    FreeAndNil(PostRestoreSnap);
    FreeAndNil(SnapB);
    FreeAndNil(SnapA);
    FreeAndNil(PreSnap);
    SetLength(SavedPoses, 0);
  end;
end;

class function TDeterminismRegressionHarness.BuildMarkdownReport(
  const AAudit: TDeterminismAuditResult;
  const ASnapshot: TGoldenWorldSnapshot): String;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — Deterministic Golden-Snapshot & Drift Regression Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Determinism Verdict**: **%s**', [
      IfThen(AAudit.BitExactMatch, 'BIT-EXACT MATCH (0 Drifts)', 'DRIFT DETECTED')]));
    SB.AppendLine(Format('- **64-Bit FNV-1a Hash (`Run A` vs `Run B`)**: `%s` vs `%s`', [
      AAudit.RunAHashHex, AAudit.RunBHashHex]));
    SB.AppendLine(Format('- **Actors Audited / Drifted / Max Pos Delta**: `%d` / `%d` / `%.4f m`', [
      AAudit.ActorsCompared, AAudit.DriftedActorCount, AAudit.MaxPositionDriftMeters]));
    SB.AppendLine(Format('- **Non-Destructive World Restore**: `%s`', [
      BoolToStr(AAudit.StateRestoredCleanly, True)]));

    if Length(AAudit.Drifts) > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Detected Actor Drifts');
      SB.AppendLine('| Actor Path | Kind | Pos Delta `(m)` | Details |');
      SB.AppendLine('| :--- | :--- | ---: | :--- |');
      for I := 0 to High(AAudit.Drifts) do
        SB.AppendLine(Format('| `%s` | `%s` | `%.4f` | %s |', [
          AAudit.Drifts[I].ActorPath, AAudit.Drifts[I].DriftKind,
          AAudit.Drifts[I].PositionDeltaMeters, AAudit.Drifts[I].Details]));
    end;

    if (ASnapshot <> nil) and (ASnapshot.ActorCount > 0) then
    begin
      SB.AppendLine;
      SB.AppendLine('## Actor Hash Ledger (Top 16)');
      SB.AppendLine('| Actor Path | Class | Hash64 | Subsystem State |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to Min(15, ASnapshot.ActorCount - 1) do
        SB.AppendLine(Format('| `%s` | `%s` | `%s` | `%s` |', [
          ASnapshot.Digests[I].ActorPath,
          ASnapshot.Digests[I].ClassNameStr,
          IntToHex(ASnapshot.Digests[I].ActorHash64, 16),
          IfThen(ASnapshot.Digests[I].SubsystemTag <> '', ASnapshot.Digests[I].SubsystemTag, '-')]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
