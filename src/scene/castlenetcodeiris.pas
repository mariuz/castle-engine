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

{ Iris-Style Netcode Replication System: Spatial Relevancy Culling,
  Starvation-Protected Priority Bandwidth Scheduler, Quantized Delta Packets,
  Jitter-Buffered Client SLerp Interpolation & Server-Authoritative
  Lag-Compensated Hitbox Rewind
  (@link(TCastleNetReplicationManager), @link(TCastleReplicatedBehavior),
  @link(RayHitsSphere3D))
  (Phase 321 — UE 6.0+ Iris Replication & Lag Compensation Parity). }
unit CastleNetcodeIris;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleBehaviors;

type
  { Timestamped authoritative or client-received pose snapshot. }
  TNetPoseSnapshot = record
    TimeSec: Single;
    ArrivalClientTimeSec: Single;
    PositionW: TVector3;
    RotationAA: TVector4;
    PacketBytes: Integer;
  end;
  TNetPoseSnapshotArray = array of TNetPoseSnapshot;

  { Per-actor multiplayer replication behavior tracking spatial relevancy,
    starvation-free priority accumulation, server rewind history, and
    client jitter-buffered snapshot interpolation. }
  TCastleReplicatedBehavior = class(TCastleBehavior)
  public
    const
      DefaultBasePriority = 1.0;
      DefaultNetCullDistance = 45.0;
      DefaultHitboxRadius = 0.65;
      DefaultHitboxHeightOffset = 0.90;
      QuantizedSnapshotBytes = 18; // 3x int16 delta pos + compressed quat + header
  strict private
    FNetId: Cardinal;
    FBasePriority: Single;
    FNetCullDistance: Single;
    FAlwaysRelevant: Boolean;
    FHitboxRadius: Single;
    FHitboxHeightOffset: Single;

    FTimeSinceLastSentSec: Single;
    FLastPriorityScore: Single;
    FSentPacketCount: Integer;
    FDroppedPacketCount: Integer;
    FLastRelevant: Boolean;

    FServerHistory: TNetPoseSnapshotArray;
    FClientPendingQueue: TNetPoseSnapshotArray;
    FClientReceivedBuffer: TNetPoseSnapshotArray;
    FLastClientInterpPos: TVector3;
    FLastClientInterpRot: TVector4;

    procedure TrimRingBuffer(var Arr: TNetPoseSnapshotArray;
      const MinKeepTimeSec: Single);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ResetNetState;
    procedure RecordServerHistoryPose(const AServerTimeSec: Single;
      const MaxHistorySec: Single);
    procedure EnqueueNetworkPacket(const ASnapshot: TNetPoseSnapshot);
    procedure DeliverArrivedClientPackets(const AClientClockSec, MaxBufferSec: Single);

    { Evaluate historical authoritative pose at @code(ARewindServerTimeSec)
      for server-side lag-compensated hit detection. }
    function SampleServerHistoricalPose(const ARewindServerTimeSec: Single;
      out OutPosW: TVector3; out OutRotAA: TVector4): Boolean;

    { Evaluate smooth jitter-buffered client pose at @code(ARenderServerTimeSec). }
    function EvaluateClientInterpolatedPose(const ARenderServerTimeSec: Single;
      out OutPosW: TVector3; out OutRotAA: TVector4): Boolean;

    function CurrentHitboxCenterW: TVector3;
    function ReplicatedSummaryBadge: String;

    property TimeSinceLastSentSec: Single read FTimeSinceLastSentSec write FTimeSinceLastSentSec;
    property LastPriorityScore: Single read FLastPriorityScore write FLastPriorityScore;
    property SentPacketCount: Integer read FSentPacketCount write FSentPacketCount;
    property DroppedPacketCount: Integer read FDroppedPacketCount write FDroppedPacketCount;
    property LastRelevant: Boolean read FLastRelevant write FLastRelevant;
    property LastClientInterpPos: TVector3 read FLastClientInterpPos;
    property LastClientInterpRot: TVector4 read FLastClientInterpRot;
  published
    property NetId: Cardinal read FNetId write FNetId default 0;
    property BasePriority: Single read FBasePriority write FBasePriority {$ifdef FPC}default DefaultBasePriority{$endif};
    property NetCullDistance: Single read FNetCullDistance write FNetCullDistance {$ifdef FPC}default DefaultNetCullDistance{$endif};
    property AlwaysRelevant: Boolean read FAlwaysRelevant write FAlwaysRelevant default false;
    property HitboxRadius: Single read FHitboxRadius write FHitboxRadius {$ifdef FPC}default DefaultHitboxRadius{$endif};
    property HitboxHeightOffset: Single read FHitboxHeightOffset write FHitboxHeightOffset {$ifdef FPC}default DefaultHitboxHeightOffset{$endif};
  end;

  TReplicatedBehaviorArray = array of TCastleReplicatedBehavior;

  { Iris-style authoritative Replication Graph, Priority Bandwidth Scheduler,
    Latency/Jitter/Packet-Loss Channel Simulator & Lag-Compensated Hitbox
    Rewind Manager. }
  TCastleNetReplicationManager = class(TCastleComponent)
  public
    const
      DefaultServerTickHz = 20.0;
      DefaultMaxBytesPerTick = 180;
      DefaultSimulatedRttMs = 100.0;
      DefaultSimulatedJitterMs = 12.0;
      DefaultSimulatedPacketLossPct = 0.0;
      DefaultClientInterpDelayMs = 100.0;
      DefaultMaxRewindHistorySec = 1.5;
  strict private
    FServerTickHz: Single;
    FMaxBytesPerTick: Integer;
    FSimulatedRttMs: Single;
    FSimulatedJitterMs: Single;
    FSimulatedPacketLossPct: Single;
    FClientInterpDelayMs: Single;
    FMaxRewindHistorySec: Single;
    FSeed: Cardinal;
    FRngState: Cardinal;

    FServerClockSec: Single;
    FTickAccumSec: Single;
    FTotalTicks: Integer;
    FTotalBytesSent: Int64;
    FLastTickBytesSent: Integer;
    FLastRelevantActors: Integer;

    function NextRandom01: Single;
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ResetSimulation;

    { Advance server & client clocks by @code(Dt), scheduling relevant actors
      within @link(MaxBytesPerTick) around @code(ObserverWorldPos). }
    procedure StepReplication(const RootComp, DesignOwner: TComponent;
      const Dt: Single; const ObserverWorldPos: TVector3);

    { Perform a server-authoritative lag-compensated raycast rewound by
      @code(RewindDurationSec) (e.g. @code(0.5 * RTT + InterpDelay)).
      Also computes @code(OutUnrewoundClosestDist) against the unrewound live
      pose so callers/UI can compare Rewind Hit vs. Live Miss! }
    function LagCompensatedRaycast(const RootComp, DesignOwner: TComponent;
      const RayOriginW, RayDirW: TVector3; const RewindDurationSec: Single;
      out OutHitActor: TCastleReplicatedBehavior;
      out OutRewoundHitCenterW: TVector3;
      out OutUnrewoundClosestDist: Single): Boolean;

    function EstimatedBandwidthKbps: Single;
    function ClientRenderServerTimeSec: Single;
    function NetManagerSummaryBadge: String;

    property ServerClockSec: Single read FServerClockSec;
    property TotalTicks: Integer read FTotalTicks;
    property TotalBytesSent: Int64 read FTotalBytesSent;
    property LastTickBytesSent: Integer read FLastTickBytesSent;
    property LastRelevantActors: Integer read FLastRelevantActors;
  published
    property ServerTickHz: Single read FServerTickHz write FServerTickHz {$ifdef FPC}default DefaultServerTickHz{$endif};
    property MaxBytesPerTick: Integer read FMaxBytesPerTick write FMaxBytesPerTick default DefaultMaxBytesPerTick;
    property SimulatedRttMs: Single read FSimulatedRttMs write FSimulatedRttMs {$ifdef FPC}default DefaultSimulatedRttMs{$endif};
    property SimulatedJitterMs: Single read FSimulatedJitterMs write FSimulatedJitterMs {$ifdef FPC}default DefaultSimulatedJitterMs{$endif};
    property SimulatedPacketLossPct: Single read FSimulatedPacketLossPct write FSimulatedPacketLossPct {$ifdef FPC}default DefaultSimulatedPacketLossPct{$endif};
    property ClientInterpDelayMs: Single read FClientInterpDelayMs write FClientInterpDelayMs {$ifdef FPC}default DefaultClientInterpDelayMs{$endif};
    property MaxRewindHistorySec: Single read FMaxRewindHistorySec write FMaxRewindHistorySec {$ifdef FPC}default DefaultMaxRewindHistorySec{$endif};
    property Seed: Cardinal read FSeed write FSeed default 2026;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Analytical 3D ray-sphere intersection + closest approach distance from ray to center. }
function RayHitsSphere3D(const RayOrigin, RayDir, SphereCenter: TVector3;
  const SphereRadius: Single; out OutClosestCenterDist: Single): Boolean;

procedure CollectReplicatedBehaviors(const RootComp, DesignOwner: TComponent;
  out OutActors: TReplicatedBehaviorArray);

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleViewport, CastleQuaternions, CastleComponentSerialize;

function SafeAxisAngle(const R: TVector4): TVector4;
begin
  if Vector3(R.X, R.Y, R.Z).LengthSqr < 1e-8 then
    Result := Vector4(0.0, 1.0, 0.0, 0.0)
  else
    Result := R;
end;

function InterpolateSnapshotArray(const Arr: TNetPoseSnapshotArray;
  const TargetTimeSec: Single; out OutPos: TVector3; out OutRot: TVector4): Boolean;
var
  N, I, Idx0, Idx1: Integer;
  Span, Alpha: Single;
begin
  N := Length(Arr);
  if N = 0 then
  begin
    OutPos := TVector3.Zero;
    OutRot := Vector4(0.0, 1.0, 0.0, 0.0);
    Exit(False);
  end;
  if TargetTimeSec <= Arr[0].TimeSec then
  begin
    OutPos := Arr[0].PositionW;
    OutRot := Arr[0].RotationAA;
    Exit(True);
  end;
  if TargetTimeSec >= Arr[N - 1].TimeSec then
  begin
    OutPos := Arr[N - 1].PositionW;
    OutRot := Arr[N - 1].RotationAA;
    Exit(True);
  end;

  Idx0 := 0;
  Idx1 := N - 1;
  for I := 0 to N - 2 do
    if (TargetTimeSec >= Arr[I].TimeSec) and (TargetTimeSec <= Arr[I + 1].TimeSec) then
    begin
      Idx0 := I;
      Idx1 := I + 1;
      Break;
    end;

  Span := Arr[Idx1].TimeSec - Arr[Idx0].TimeSec;
  if Span > 1e-6 then
    Alpha := Clamped((TargetTimeSec - Arr[Idx0].TimeSec) / Span, 0.0, 1.0)
  else
    Alpha := 0.0;

  OutPos := Lerp(Alpha, Arr[Idx0].PositionW, Arr[Idx1].PositionW);
  OutRot := SLerp(Alpha,
    SafeAxisAngle(Arr[Idx0].RotationAA),
    SafeAxisAngle(Arr[Idx1].RotationAA));
  Result := True;
end;

function RayHitsSphere3D(const RayOrigin, RayDir, SphereCenter: TVector3;
  const SphereRadius: Single; out OutClosestCenterDist: Single): Boolean;
var
  UnitDir, ToCenter, ClosestPt: TVector3;
  ProjT: Single;
begin
  if RayDir.LengthSqr < 1e-10 then
    UnitDir := Vector3(0.0, 0.0, -1.0)
  else
    UnitDir := RayDir.Normalize;

  ToCenter := SphereCenter - RayOrigin;
  ProjT := Max(0.0, TVector3.DotProduct(ToCenter, UnitDir));
  ClosestPt := RayOrigin + UnitDir * ProjT;
  OutClosestCenterDist := (SphereCenter - ClosestPt).Length;
  Result := OutClosestCenterDist <= Max(0.01, SphereRadius);
end;

procedure CollectReplicatedBehaviors(const RootComp, DesignOwner: TComponent;
  out OutActors: TReplicatedBehaviorArray);

  procedure AddUnique(const B: TCastleReplicatedBehavior);
  var
    K: Integer;
  begin
    if (B = nil) or (csTransient in B.ComponentStyle) then
      Exit;
    for K := 0 to High(OutActors) do
      if OutActors[K] = B then
        Exit;
    SetLength(OutActors, Length(OutActors) + 1);
    OutActors[High(OutActors)] := B;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleReplicatedBehavior then
      AddUnique(TCastleReplicatedBehavior(C));
    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutActors := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

{ TCastleReplicatedBehavior -------------------------------------------------- }

constructor TCastleReplicatedBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBasePriority := DefaultBasePriority;
  FNetCullDistance := DefaultNetCullDistance;
  FHitboxRadius := DefaultHitboxRadius;
  FHitboxHeightOffset := DefaultHitboxHeightOffset;
  FLastClientInterpRot := Vector4(0.0, 1.0, 0.0, 0.0);
end;

function TCastleReplicatedBehavior.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'NetId') or
     (PropertyName = 'BasePriority') or
     (PropertyName = 'NetCullDistance') or
     (PropertyName = 'AlwaysRelevant') or
     (PropertyName = 'HitboxRadius') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleReplicatedBehavior.ResetNetState;
begin
  FTimeSinceLastSentSec := 0.0;
  FLastPriorityScore := 0.0;
  FSentPacketCount := 0;
  FDroppedPacketCount := 0;
  FLastRelevant := False;
  FServerHistory := nil;
  FClientPendingQueue := nil;
  FClientReceivedBuffer := nil;
end;

procedure TCastleReplicatedBehavior.TrimRingBuffer(
  var Arr: TNetPoseSnapshotArray; const MinKeepTimeSec: Single);
var
  DropCount, I: Integer;
begin
  DropCount := 0;
  { Keep at least 1 sample older than MinKeepTimeSec so bracket interpolation stays continuous }
  while (DropCount + 2 <= High(Arr)) and (Arr[DropCount + 1].TimeSec < MinKeepTimeSec) do
    Inc(DropCount);
  if DropCount > 0 then
  begin
    for I := DropCount to High(Arr) do
      Arr[I - DropCount] := Arr[I];
    SetLength(Arr, Length(Arr) - DropCount);
  end;
end;

procedure TCastleReplicatedBehavior.RecordServerHistoryPose(
  const AServerTimeSec: Single; const MaxHistorySec: Single);
var
  N: Integer;
begin
  if Parent = nil then
    Exit;
  N := Length(FServerHistory);
  SetLength(FServerHistory, N + 1);
  FServerHistory[N].TimeSec := AServerTimeSec;
  FServerHistory[N].ArrivalClientTimeSec := AServerTimeSec;
  FServerHistory[N].PositionW := Parent.Translation;
  FServerHistory[N].RotationAA := Parent.Rotation;
  FServerHistory[N].PacketBytes := QuantizedSnapshotBytes;

  TrimRingBuffer(FServerHistory, AServerTimeSec - Max(0.2, MaxHistorySec));
end;

procedure TCastleReplicatedBehavior.EnqueueNetworkPacket(const ASnapshot: TNetPoseSnapshot);
var
  N: Integer;
begin
  N := Length(FClientPendingQueue);
  SetLength(FClientPendingQueue, N + 1);
  FClientPendingQueue[N] := ASnapshot;
end;

procedure TCastleReplicatedBehavior.DeliverArrivedClientPackets(
  const AClientClockSec, MaxBufferSec: Single);
var
  I, K, N, InsertIdx: Integer;
  Snap: TNetPoseSnapshot;
begin
  for I := High(FClientPendingQueue) downto 0 do
    if FClientPendingQueue[I].ArrivalClientTimeSec <= AClientClockSec + 1e-5 then
    begin
      Snap := FClientPendingQueue[I];
      for K := I to High(FClientPendingQueue) - 1 do
        FClientPendingQueue[K] := FClientPendingQueue[K + 1];
      SetLength(FClientPendingQueue, Length(FClientPendingQueue) - 1);

      { Insert sorted by authoritative TimeSec (guards against out-of-order jitter) }
      N := Length(FClientReceivedBuffer);
      SetLength(FClientReceivedBuffer, N + 1);
      InsertIdx := N;
      while (InsertIdx > 0) and (FClientReceivedBuffer[InsertIdx - 1].TimeSec > Snap.TimeSec) do
      begin
        FClientReceivedBuffer[InsertIdx] := FClientReceivedBuffer[InsertIdx - 1];
        Dec(InsertIdx);
      end;
      FClientReceivedBuffer[InsertIdx] := Snap;
    end;

  TrimRingBuffer(FClientReceivedBuffer, AClientClockSec - Max(0.3, MaxBufferSec));
end;

function TCastleReplicatedBehavior.SampleServerHistoricalPose(
  const ARewindServerTimeSec: Single;
  out OutPosW: TVector3; out OutRotAA: TVector4): Boolean;
begin
  Result := InterpolateSnapshotArray(FServerHistory, ARewindServerTimeSec, OutPosW, OutRotAA);
end;

function TCastleReplicatedBehavior.EvaluateClientInterpolatedPose(
  const ARenderServerTimeSec: Single;
  out OutPosW: TVector3; out OutRotAA: TVector4): Boolean;
begin
  Result := InterpolateSnapshotArray(FClientReceivedBuffer, ARenderServerTimeSec, OutPosW, OutRotAA);
  if Result then
  begin
    FLastClientInterpPos := OutPosW;
    FLastClientInterpRot := OutRotAA;
  end;
end;

function TCastleReplicatedBehavior.CurrentHitboxCenterW: TVector3;
begin
  if Parent <> nil then
    Result := Parent.Translation + Vector3(0.0, FHitboxHeightOffset, 0.0)
  else
    Result := Vector3(0.0, FHitboxHeightOffset, 0.0);
end;

function TCastleReplicatedBehavior.ReplicatedSummaryBadge: String;
var
  RelLabel: String;
begin
  if FLastRelevant then
    RelLabel := 'Relevant'
  else
    RelLabel := 'Culled';
  Result := Format('[IrisRep:Prio %.1f %s %d pkts]', [
    FBasePriority, RelLabel, FSentPacketCount]);
end;

{ TCastleNetReplicationManager ----------------------------------------------- }

constructor TCastleNetReplicationManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FServerTickHz := DefaultServerTickHz;
  FMaxBytesPerTick := DefaultMaxBytesPerTick;
  FSimulatedRttMs := DefaultSimulatedRttMs;
  FSimulatedJitterMs := DefaultSimulatedJitterMs;
  FSimulatedPacketLossPct := DefaultSimulatedPacketLossPct;
  FClientInterpDelayMs := DefaultClientInterpDelayMs;
  FMaxRewindHistorySec := DefaultMaxRewindHistorySec;
  FSeed := 2026;
  ResetSimulation;
end;

procedure TCastleNetReplicationManager.ResetSimulation;
begin
  FServerClockSec := 0.0;
  FTickAccumSec := 0.0;
  FTotalTicks := 0;
  FTotalBytesSent := 0;
  FLastTickBytesSent := 0;
  FLastRelevantActors := 0;
  if FSeed = 0 then
    FRngState := 2026
  else
    FRngState := FSeed;
end;

{$PUSH}{$Q-}{$R-}
function TCastleNetReplicationManager.NextRandom01: Single;
var
  X: Cardinal;
begin
  X := FRngState;
  if X = 0 then
    X := 1357924681;
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  FRngState := X;
  Result := (X and $00FFFFFF) / 16777216.0;
end;
{$POP}

function TCastleNetReplicationManager.ClientRenderServerTimeSec: Single;
var
  OneWayLagSec, InterpSec: Single;
begin
  OneWayLagSec := Max(0.0, FSimulatedRttMs) * 0.0005;
  InterpSec := Max(0.0, FClientInterpDelayMs) * 0.001;
  Result := Max(0.0, FServerClockSec - OneWayLagSec - InterpSec);
end;

procedure TCastleNetReplicationManager.StepReplication(
  const RootComp, DesignOwner: TComponent;
  const Dt: Single; const ObserverWorldPos: TVector3);
var
  Actors, RelevantList: TReplicatedBehaviorArray;
  B, TmpB: TCastleReplicatedBehavior;
  TickInterval, StepInterval, Dist, DistFactor, OneWayDelaySec, JitterSec: Single;
  I, J, BytesRemaining: Integer;
  Snap: TNetPoseSnapshot;
  DummyP: TVector3;
  DummyR: TVector4;
begin
  if Dt <= 0.0 then
    Exit;

  CollectReplicatedBehaviors(RootComp, DesignOwner, Actors);
  TickInterval := 1.0 / Max(1.0, FServerTickHz);
  FTickAccumSec := FTickAccumSec + Dt;

  { Record continuous server history & advance starvation timers }
  FServerClockSec := FServerClockSec + Dt;
  for I := 0 to High(Actors) do
  begin
    Actors[I].TimeSinceLastSentSec := Actors[I].TimeSinceLastSentSec + Dt;
    Actors[I].RecordServerHistoryPose(FServerClockSec, FMaxRewindHistorySec);
  end;

  while FTickAccumSec >= TickInterval - 1e-6 do
  begin
    StepInterval := TickInterval;
    FTickAccumSec := Max(0.0, FTickAccumSec - StepInterval);
    Inc(FTotalTicks);

    { 1. Spatial relevancy filter + Priority*Starvation score }
    RelevantList := nil;
    for I := 0 to High(Actors) do
    begin
      B := Actors[I];
      if B.Parent = nil then
        Continue;
      Dist := (B.Parent.Translation - ObserverWorldPos).Length;
      if B.AlwaysRelevant or (Dist <= B.NetCullDistance) then
      begin
        B.LastRelevant := True;
        DistFactor := 1.0;
        if (not B.AlwaysRelevant) and (B.NetCullDistance > 0.1) then
          DistFactor := 0.35 + 0.65 * Clamped(1.0 - (Dist / B.NetCullDistance), 0.0, 1.0);
        B.LastPriorityScore := B.BasePriority *
          Max(1e-4, B.TimeSinceLastSentSec) * DistFactor;

        SetLength(RelevantList, Length(RelevantList) + 1);
        RelevantList[High(RelevantList)] := B;
      end else
      begin
        B.LastRelevant := False;
        B.LastPriorityScore := 0.0;
      end;
    end;
    FLastRelevantActors := Length(RelevantList);

    { 2. Sort relevant actors descending by LastPriorityScore }
    for I := 0 to High(RelevantList) - 1 do
      for J := I + 1 to High(RelevantList) do
        if RelevantList[J].LastPriorityScore > RelevantList[I].LastPriorityScore then
        begin
          TmpB := RelevantList[I];
          RelevantList[I] := RelevantList[J];
          RelevantList[J] := TmpB;
        end;

    { 3. Pack quantized snapshots up to MaxBytesPerTick }
    BytesRemaining := Max(TCastleReplicatedBehavior.QuantizedSnapshotBytes, FMaxBytesPerTick);
    FLastTickBytesSent := 0;
    for I := 0 to High(RelevantList) do
    begin
      B := RelevantList[I];
      if BytesRemaining < TCastleReplicatedBehavior.QuantizedSnapshotBytes then
        Break;

      Dec(BytesRemaining, TCastleReplicatedBehavior.QuantizedSnapshotBytes);
      Inc(FLastTickBytesSent, TCastleReplicatedBehavior.QuantizedSnapshotBytes);
      FTotalBytesSent := FTotalBytesSent + TCastleReplicatedBehavior.QuantizedSnapshotBytes;
      B.TimeSinceLastSentSec := 0.0;
      B.SentPacketCount := B.SentPacketCount + 1;

      if (FSimulatedPacketLossPct > 0.0) and
         (NextRandom01 * 100.0 < FSimulatedPacketLossPct) then
      begin
        B.DroppedPacketCount := B.DroppedPacketCount + 1;
        Continue;
      end;

      OneWayDelaySec := Max(0.0, FSimulatedRttMs) * 0.0005;
      JitterSec := (NextRandom01 * 2.0 - 1.0) * Max(0.0, FSimulatedJitterMs) * 0.001;
      Snap.TimeSec := FServerClockSec;
      Snap.ArrivalClientTimeSec := FServerClockSec + Max(0.0, OneWayDelaySec + JitterSec);
      Snap.PositionW := B.Parent.Translation;
      Snap.RotationAA := B.Parent.Rotation;
      Snap.PacketBytes := TCastleReplicatedBehavior.QuantizedSnapshotBytes;
      B.EnqueueNetworkPacket(Snap);
    end;
  end;

  { 4. Deliver arrived packets & evaluate client interpolated poses }
  for I := 0 to High(Actors) do
  begin
    Actors[I].DeliverArrivedClientPackets(FServerClockSec, FMaxRewindHistorySec + 1.0);
    Actors[I].EvaluateClientInterpolatedPose(ClientRenderServerTimeSec, DummyP, DummyR);
  end;
end;

function TCastleNetReplicationManager.LagCompensatedRaycast(
  const RootComp, DesignOwner: TComponent;
  const RayOriginW, RayDirW: TVector3; const RewindDurationSec: Single;
  out OutHitActor: TCastleReplicatedBehavior;
  out OutRewoundHitCenterW: TVector3;
  out OutUnrewoundClosestDist: Single): Boolean;
var
  Actors: TReplicatedBehaviorArray;
  ClampedRewind, RewindTimestamp, DistCenter, UnrewoundDist, BestRayDist, RayDist: Single;
  HistPos, HistCenter: TVector3;
  HistRot: TVector4;
  I: Integer;
begin
  OutHitActor := nil;
  OutRewoundHitCenterW := TVector3.Zero;
  OutUnrewoundClosestDist := MaxSingle;
  Result := False;

  CollectReplicatedBehaviors(RootComp, DesignOwner, Actors);
  ClampedRewind := Clamped(RewindDurationSec, 0.0, FMaxRewindHistorySec);
  RewindTimestamp := Max(0.0, FServerClockSec - ClampedRewind);
  BestRayDist := MaxSingle;

  for I := 0 to High(Actors) do
  begin
    if Actors[I].Parent = nil then
      Continue;

    { Measure unrewound live closest approach for diagnostics }
    RayHitsSphere3D(RayOriginW, RayDirW, Actors[I].CurrentHitboxCenterW,
      Actors[I].HitboxRadius, UnrewoundDist);
    OutUnrewoundClosestDist := Min(OutUnrewoundClosestDist, UnrewoundDist);

    { Rewind actor to exact historical timestamp }
    if Actors[I].SampleServerHistoricalPose(RewindTimestamp, HistPos, HistRot) then
    begin
      HistCenter := HistPos + Vector3(0.0, Actors[I].HitboxHeightOffset, 0.0);
      if RayHitsSphere3D(RayOriginW, RayDirW, HistCenter, Actors[I].HitboxRadius, DistCenter) then
      begin
        RayDist := (HistCenter - RayOriginW).Length;
        if RayDist < BestRayDist then
        begin
          BestRayDist := RayDist;
          OutHitActor := Actors[I];
          OutRewoundHitCenterW := HistCenter;
          Result := True;
        end;
      end;
    end;
  end;
end;

function TCastleNetReplicationManager.EstimatedBandwidthKbps: Single;
begin
  Result := (FLastTickBytesSent * FServerTickHz * 8.0) / 1000.0;
end;

function TCastleNetReplicationManager.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'ServerTickHz') or
     (PropertyName = 'MaxBytesPerTick') or
     (PropertyName = 'SimulatedRttMs') or
     (PropertyName = 'SimulatedJitterMs') or
     (PropertyName = 'SimulatedPacketLossPct') or
     (PropertyName = 'ClientInterpDelayMs') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleNetReplicationManager.NetManagerSummaryBadge: String;
begin
  Result := Format('[IrisNet:%.0fHz RTT %.0fms %.1f kbps]', [
    FServerTickHz, FSimulatedRttMs, EstimatedBandwidthKbps]);
end;

function TCastleNetReplicationManager.GetConfigJson: String;
var
  Root: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('tickHz', FServerTickHz);
    Root.Add('maxBytes', FMaxBytesPerTick);
    Root.Add('rttMs', FSimulatedRttMs);
    Root.Add('jitterMs', FSimulatedJitterMs);
    Root.Add('lossPct', FSimulatedPacketLossPct);
    Root.Add('interpMs', FClientInterpDelayMs);
    Root.Add('rewindSec', FMaxRewindHistorySec);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleNetReplicationManager.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FServerTickHz := Clamped(Root.Get('tickHz', FServerTickHz), 1.0, 240.0);
      FMaxBytesPerTick := Max(18, Root.Get('maxBytes', FMaxBytesPerTick));
      FSimulatedRttMs := Clamped(Root.Get('rttMs', FSimulatedRttMs), 0.0, 2000.0);
      FSimulatedJitterMs := Clamped(Root.Get('jitterMs', FSimulatedJitterMs), 0.0, 500.0);
      FSimulatedPacketLossPct := Clamped(Root.Get('lossPct', FSimulatedPacketLossPct), 0.0, 95.0);
      FClientInterpDelayMs := Clamped(Root.Get('interpMs', FClientInterpDelayMs), 0.0, 1000.0);
      FMaxRewindHistorySec := Clamped(Root.Get('rewindSec', FMaxRewindHistorySec), 0.2, 10.0);
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleReplicatedBehavior,
    ['Multiplayer & Netcode', 'Iris Replicated Actor & Rewind Hitbox']);
  RegisterSerializableComponent(TCastleNetReplicationManager,
    ['Multiplayer & Netcode', 'Iris Replication Graph & Lag Compensation Manager']);
end.
