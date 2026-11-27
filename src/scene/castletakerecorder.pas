{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Take Recorder & Live Link Real-Time Streaming Hub
  (UTakeRecorder / UTakeMetaData / ILiveLinkClient) featuring SMPTE timecode
  PIE actor & camera clip recording, auto-incrementing Slate/Take numbering,
  Ramer-Douglas-Peucker ReduceKeys curve simplification with strict error
  bounds, de-jitter buffered LiveLink Transform/Camera/Animation subject
  interpolation,Active/Stale/Dropped connection health monitoring, and lossless
  JSON serialization (Phase 397). }
unit CastleTakeRecorder;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleUtils, CastleClassUtils, CastleVectors,
  CastleComponentSerialize, CastleTransform;

type
  TTakeRecorderPreset = (
    trpMocapDuelAndCineCam,
    trpVehicleChasePhysicsTake,
    trpFacialArkitAndVCamLiveLink
  );

  TLiveLinkRoleKind = (
    llrTransform,
    llrCamera,
    llrAnimationSkeleton
  );

  TLiveLinkSubjectStatus = (
    llsActiveGreen,
    llsStaleYellow,
    llsDroppedRed
  );

  TLiveLinkFrameSample = record
    TimeSec: Double;
    SmpteFrame: Integer;
    Location: TVector3;
    EulerDeg: TVector3;
    FovDeg: Single;
    FocusDistanceM: Single;
  end;

  TLiveLinkSubjectStream = record
    SubjectName: String;
    Role: TLiveLinkRoleKind;
    TargetActorName: String;
    EvaluationOffsetSec: Single;
    LastReceiveTimeSec: Double;
    Frames: array of TLiveLinkFrameSample;
  end;
  TLiveLinkSubjectStreamArray = array of TLiveLinkSubjectStream;

  TTakeKeyframe = record
    TimeSec: Single;
    Location: TVector3;
    EulerDeg: TVector3;
    FovDeg: Single;
  end;
  TTakeKeyframeArray = array of TTakeKeyframe;

  TTakeRecordedTrack = record
    TrackName: String;
    Role: TLiveLinkRoleKind;
    RawKeys: TTakeKeyframeArray;
    ReducedKeys: TTakeKeyframeArray;
    MaxPosErrorM: Single;
  end;
  TTakeRecordedTrackArray = array of TTakeRecordedTrack;

  TCastleTakeRecorder = class(TCastleTransform)
  private
    FPreset: TTakeRecorderPreset;
    FSlateName: String;
    FTakeNumber: Integer;
    FRecordRateFps: Single;
    FPosReduceToleranceM: Single;
    FRotReduceToleranceDeg: Single;
    FStaleTimeoutSec: Single;
    FDroppedTimeoutSec: Single;
    FCurrentWorldTimeSec: Double;
    FIsRecording: Boolean;
    FHasRecordedAtLeastOnce: Boolean;

    FSubjects: TLiveLinkSubjectStreamArray;
    FTracks: TTakeRecordedTrackArray;
    FTakeDataJson: String;

    procedure SetPreset(const AValue: TTakeRecorderPreset);
    procedure SetRecordRateFps(const AValue: Single);
    procedure SetPosReduceToleranceM(const AValue: Single);
    procedure SetRotReduceToleranceDeg(const AValue: Single);
    function GetTakeDataJson: String;
    procedure SetTakeDataJson(const AValue: String);

    procedure BuildPresetStreamsAndTake;
    procedure RecomputeTrackError(var ATrack: TTakeRecordedTrack);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { ILiveLinkClient real-time packet ingestion & buffered de-jitter evaluation }
    function EnsureLiveLinkSubject(const ASubjectName: String;
      const ARole: TLiveLinkRoleKind;
      const ATargetActorName: String = '';
      const AEvalOffsetSec: Single = 0.033): Integer;
    procedure PushLiveLinkFrame(const ASubjectName: String;
      const ARole: TLiveLinkRoleKind;
      const ATimeSec: Double;
      const ALocation, AEulerDeg: TVector3;
      const AFovDeg: Single = 50.0;
      const AFocusDistanceM: Single = 4.5);
    function EvaluateLiveLinkSubject(const ASubjectName: String;
      const AWorldTimeSec: Double;
      out OutSample: TLiveLinkFrameSample;
      out OutStatus: TLiveLinkSubjectStatus): Boolean;
    function SubjectStatusAtTime(const SubjectIdx: Integer;
      const AWorldTimeSec: Double): TLiveLinkSubjectStatus;

    { UTakeRecorder session lifecycle & Ramer-Douglas-Peucker ReduceKeys }
    procedure StartNewTake(const ANewSlateName: String = '');
    procedure AppendTrackRawKey(const ATrackName: String;
      const ARole: TLiveLinkRoleKind;
      const ATimeSec: Single;
      const ALocation, AEulerDeg: TVector3;
      const AFovDeg: Single = 50.0);
    procedure StopAndFinalizeTake;
    procedure ReduceAllTracks(const APosTolM, ARotTolDeg: Single);
    function ReduceSingleTrackKeys(const TrackIdx: Integer;
      const APosTolM, ARotTolDeg: Single): Integer;
    procedure SimulatePresetTakeCapture(const ADurationSec: Single = 4.0);

    function EvaluateTrackAtTime(const TrackIdx: Integer;
      const ATimeSec: Single; const AUseReducedKeys: Boolean;
      out OutKey: TTakeKeyframe): Boolean;
    function FormatSmpteTimecode(const ATimeSec: Double): String;

    function SubjectCount: Integer;
    function ActiveGreenSubjectCount(const AWorldTimeSec: Double): Integer;
    function TrackCount: Integer;
    function TotalRawKeyCount: Integer;
    function TotalReducedKeyCount: Integer;
    function KeyReductionPercent: Single;
    function TakeRecorderSummaryBadge: String;

    property Subjects: TLiveLinkSubjectStreamArray read FSubjects;
    property Tracks: TTakeRecordedTrackArray read FTracks;
    property CurrentWorldTimeSec: Double read FCurrentWorldTimeSec write FCurrentWorldTimeSec;
    property IsRecording: Boolean read FIsRecording;
  published
    property Preset: TTakeRecorderPreset
      read FPreset write SetPreset default trpMocapDuelAndCineCam;
    property SlateName: String read FSlateName write FSlateName;
    property TakeNumber: Integer read FTakeNumber write FTakeNumber default 1;
    property RecordRateFps: Single
      read FRecordRateFps write SetRecordRateFps {$ifdef FPC}default 60.0{$endif};
    property PosReduceToleranceM: Single
      read FPosReduceToleranceM write SetPosReduceToleranceM {$ifdef FPC}default 0.015{$endif};
    property RotReduceToleranceDeg: Single
      read FRotReduceToleranceDeg write SetRotReduceToleranceDeg {$ifdef FPC}default 0.35{$endif};
    property StaleTimeoutSec: Single
      read FStaleTimeoutSec write FStaleTimeoutSec {$ifdef FPC}default 0.25{$endif};
    property DroppedTimeoutSec: Single
      read FDroppedTimeoutSec write FDroppedTimeoutSec {$ifdef FPC}default 1.00{$endif};
    property TakeDataJson: String read GetTakeDataJson write SetTakeDataJson stored True;
  end;

function TakePresetDisplayName(const APreset: TTakeRecorderPreset): String;
function LiveLinkRoleDisplayName(const ARole: TLiveLinkRoleKind): String;
function LiveLinkStatusDisplayName(const AStatus: TLiveLinkSubjectStatus): String;

implementation

function TakePresetDisplayName(const APreset: TTakeRecorderPreset): String;
begin
  case APreset of
    trpMocapDuelAndCineCam:        Result := 'Mocap Sword Duel + Handheld iPhone VCam';
    trpVehicleChasePhysicsTake:    Result := 'Chaos Vehicle Drift Chase + Helicopter RailCam';
    trpFacialArkitAndVCamLiveLink: Result := 'ARKit Facial Performance + crane CineCamera';
  end;
end;

function LiveLinkRoleDisplayName(const ARole: TLiveLinkRoleKind): String;
begin
  case ARole of
    llrTransform:         Result := 'ULiveLinkTransformRole';
    llrCamera:            Result := 'ULiveLinkCameraRole';
    llrAnimationSkeleton: Result := 'ULiveLinkAnimationRole';
  end;
end;

function LiveLinkStatusDisplayName(const AStatus: TLiveLinkSubjectStatus): String;
begin
  case AStatus of
    llsActiveGreen: Result := 'ACTIVE (Green)';
    llsStaleYellow: Result := 'STALE (Yellow)';
    llsDroppedRed:  Result := 'DROPPED (Red)';
  end;
end;

function LerpVec3(const A, B: TVector3; const T: Single): TVector3;
begin
  Result := A + (B - A) * T;
end;

function InterpolateTakeKey(const K0, K1: TTakeKeyframe; const T: Single): TTakeKeyframe;
begin
  Result.TimeSec := K0.TimeSec + (K1.TimeSec - K0.TimeSec) * T;
  Result.Location := LerpVec3(K0.Location, K1.Location, T);
  Result.EulerDeg := LerpVec3(K0.EulerDeg, K1.EulerDeg, T);
  Result.FovDeg := K0.FovDeg + (K1.FovDeg - K0.FovDeg) * T;
end;

{ TCastleTakeRecorder }

constructor TCastleTakeRecorder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := trpMocapDuelAndCineCam;
  FSlateName := 'Slate_BossArenaDuel';
  FTakeNumber := 1;
  FRecordRateFps := 60.0;
  FPosReduceToleranceM := 0.015;
  FRotReduceToleranceDeg := 0.35;
  FStaleTimeoutSec := 0.25;
  FDroppedTimeoutSec := 1.00;
  FCurrentWorldTimeSec := 4.0;
  FIsRecording := False;
  FHasRecordedAtLeastOnce := False;

  BuildPresetStreamsAndTake;
end;

function TCastleTakeRecorder.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'SlateName') or
     (PropertyName = 'TakeNumber') or
     (PropertyName = 'RecordRateFps') or
     (PropertyName = 'PosReduceToleranceM') or
     (PropertyName = 'RotReduceToleranceDeg') or
     (PropertyName = 'StaleTimeoutSec') or
     (PropertyName = 'DroppedTimeoutSec') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleTakeRecorder.SetPreset(const AValue: TTakeRecorderPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  case FPreset of
    trpMocapDuelAndCineCam:        FSlateName := 'Slate_BossArenaDuel';
    trpVehicleChasePhysicsTake:    FSlateName := 'Slate_HighwayPursuit';
    trpFacialArkitAndVCamLiveLink: FSlateName := 'Slate_HeroCloseUpMono';
  end;
  FTakeNumber := 1;
  FHasRecordedAtLeastOnce := False;
  BuildPresetStreamsAndTake;
end;

procedure TCastleTakeRecorder.SetRecordRateFps(const AValue: Single);
begin
  FRecordRateFps := EnsureRange(AValue, 12.0, 240.0);
end;

procedure TCastleTakeRecorder.SetPosReduceToleranceM(const AValue: Single);
begin
  FPosReduceToleranceM := EnsureRange(AValue, 0.0005, 2.0);
end;

procedure TCastleTakeRecorder.SetRotReduceToleranceDeg(const AValue: Single);
begin
  FRotReduceToleranceDeg := EnsureRange(AValue, 0.01, 45.0);
end;

function TCastleTakeRecorder.EnsureLiveLinkSubject(const ASubjectName: String;
  const ARole: TLiveLinkRoleKind;
  const ATargetActorName: String;
  const AEvalOffsetSec: Single): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSubjects) do
    if SameText(FSubjects[I].SubjectName, ASubjectName) then
      Exit(I);

  Result := Length(FSubjects);
  SetLength(FSubjects, Result + 1);
  FSubjects[Result].SubjectName := ASubjectName;
  FSubjects[Result].Role := ARole;
  if ATargetActorName <> '' then
    FSubjects[Result].TargetActorName := ATargetActorName
  else
    FSubjects[Result].TargetActorName := ASubjectName;
  FSubjects[Result].EvaluationOffsetSec := Max(0.0, AEvalOffsetSec);
  FSubjects[Result].LastReceiveTimeSec := 0.0;
  SetLength(FSubjects[Result].Frames, 0);
end;

procedure TCastleTakeRecorder.PushLiveLinkFrame(const ASubjectName: String;
  const ARole: TLiveLinkRoleKind;
  const ATimeSec: Double;
  const ALocation, AEulerDeg: TVector3;
  const AFovDeg: Single;
  const AFocusDistanceM: Single);
const
  MaxRingFrames = 512;
var
  SIdx, N, I: Integer;
  Sample: TLiveLinkFrameSample;
begin
  SIdx := EnsureLiveLinkSubject(ASubjectName, ARole);
  Sample.TimeSec := ATimeSec;
  Sample.SmpteFrame := Round(ATimeSec * FRecordRateFps);
  Sample.Location := ALocation;
  Sample.EulerDeg := AEulerDeg;
  Sample.FovDeg := AFovDeg;
  Sample.FocusDistanceM := AFocusDistanceM;

  N := Length(FSubjects[SIdx].Frames);
  if N >= MaxRingFrames then
  begin
    for I := 0 to N - 2 do
      FSubjects[SIdx].Frames[I] := FSubjects[SIdx].Frames[I + 1];
    FSubjects[SIdx].Frames[N - 1] := Sample;
  end else
  begin
    SetLength(FSubjects[SIdx].Frames, N + 1);
    FSubjects[SIdx].Frames[N] := Sample;
  end;

  if ATimeSec >= FSubjects[SIdx].LastReceiveTimeSec then
    FSubjects[SIdx].LastReceiveTimeSec := ATimeSec;
  if ATimeSec > FCurrentWorldTimeSec then
    FCurrentWorldTimeSec := ATimeSec;
end;

function TCastleTakeRecorder.SubjectStatusAtTime(const SubjectIdx: Integer;
  const AWorldTimeSec: Double): TLiveLinkSubjectStatus;
var
  AgeSec: Double;
begin
  if (SubjectIdx < 0) or (SubjectIdx > High(FSubjects)) or
     (Length(FSubjects[SubjectIdx].Frames) = 0) then
    Exit(llsDroppedRed);

  AgeSec := Max(0.0, AWorldTimeSec - FSubjects[SubjectIdx].LastReceiveTimeSec);
  if AgeSec <= FStaleTimeoutSec + 1e-5 then
    Result := llsActiveGreen
  else if AgeSec <= FDroppedTimeoutSec + 1e-5 then
    Result := llsStaleYellow
  else
    Result := llsDroppedRed;
end;

function TCastleTakeRecorder.EvaluateLiveLinkSubject(const ASubjectName: String;
  const AWorldTimeSec: Double;
  out OutSample: TLiveLinkFrameSample;
  out OutStatus: TLiveLinkSubjectStatus): Boolean;
var
  SIdx, I, N: Integer;
  QueryT, Span, Alpha: Double;
  F0, F1: TLiveLinkFrameSample;
begin
  OutSample := Default(TLiveLinkFrameSample);
  OutStatus := llsDroppedRed;
  SIdx := -1;
  for I := 0 to High(FSubjects) do
    if SameText(FSubjects[I].SubjectName, ASubjectName) then
    begin
      SIdx := I;
      Break;
    end;
  if SIdx < 0 then Exit(False);

  N := Length(FSubjects[SIdx].Frames);
  if N = 0 then Exit(False);

  OutStatus := SubjectStatusAtTime(SIdx, AWorldTimeSec);
  QueryT := AWorldTimeSec - FSubjects[SIdx].EvaluationOffsetSec;

  if QueryT <= FSubjects[SIdx].Frames[0].TimeSec then
  begin
    OutSample := FSubjects[SIdx].Frames[0];
    Exit(True);
  end;
  if QueryT >= FSubjects[SIdx].Frames[N - 1].TimeSec then
  begin
    OutSample := FSubjects[SIdx].Frames[N - 1];
    Exit(True);
  end;

  for I := 0 to N - 2 do
  begin
    F0 := FSubjects[SIdx].Frames[I];
    F1 := FSubjects[SIdx].Frames[I + 1];
    if (QueryT >= F0.TimeSec) and (QueryT <= F1.TimeSec) then
    begin
      Span := Max(1e-6, F1.TimeSec - F0.TimeSec);
      Alpha := EnsureRange((QueryT - F0.TimeSec) / Span, 0.0, 1.0);
      OutSample.TimeSec := QueryT;
      OutSample.SmpteFrame := Round(QueryT * FRecordRateFps);
      OutSample.Location := LerpVec3(F0.Location, F1.Location, Alpha);
      OutSample.EulerDeg := LerpVec3(F0.EulerDeg, F1.EulerDeg, Alpha);
      OutSample.FovDeg := F0.FovDeg + (F1.FovDeg - F0.FovDeg) * Alpha;
      OutSample.FocusDistanceM := F0.FocusDistanceM +
        (F1.FocusDistanceM - F0.FocusDistanceM) * Alpha;
      Exit(True);
    end;
  end;

  OutSample := FSubjects[SIdx].Frames[N - 1];
  Result := True;
end;

procedure TCastleTakeRecorder.StartNewTake(const ANewSlateName: String);
begin
  if (ANewSlateName <> '') and (not SameText(ANewSlateName, FSlateName)) then
  begin
    FSlateName := ANewSlateName;
    FTakeNumber := 1;
  end else
  if FHasRecordedAtLeastOnce then
    Inc(FTakeNumber);

  SetLength(FTracks, 0);
  FIsRecording := True;
  FHasRecordedAtLeastOnce := True;
end;

procedure TCastleTakeRecorder.AppendTrackRawKey(const ATrackName: String;
  const ARole: TLiveLinkRoleKind;
  const ATimeSec: Single;
  const ALocation, AEulerDeg: TVector3;
  const AFovDeg: Single);
var
  TIdx, KIdx: Integer;
begin
  TIdx := -1;
  for KIdx := 0 to High(FTracks) do
    if SameText(FTracks[KIdx].TrackName, ATrackName) then
    begin
      TIdx := KIdx;
      Break;
    end;

  if TIdx < 0 then
  begin
    TIdx := Length(FTracks);
    SetLength(FTracks, TIdx + 1);
    FTracks[TIdx].TrackName := ATrackName;
    FTracks[TIdx].Role := ARole;
    SetLength(FTracks[TIdx].RawKeys, 0);
    SetLength(FTracks[TIdx].ReducedKeys, 0);
    FTracks[TIdx].MaxPosErrorM := 0.0;
  end;

  KIdx := Length(FTracks[TIdx].RawKeys);
  SetLength(FTracks[TIdx].RawKeys, KIdx + 1);
  FTracks[TIdx].RawKeys[KIdx].TimeSec := ATimeSec;
  FTracks[TIdx].RawKeys[KIdx].Location := ALocation;
  FTracks[TIdx].RawKeys[KIdx].EulerDeg := AEulerDeg;
  FTracks[TIdx].RawKeys[KIdx].FovDeg := AFovDeg;
end;

procedure TCastleTakeRecorder.StopAndFinalizeTake;
begin
  FIsRecording := False;
  ReduceAllTracks(FPosReduceToleranceM, FRotReduceToleranceDeg);
end;

function TCastleTakeRecorder.ReduceSingleTrackKeys(const TrackIdx: Integer;
  const APosTolM, ARotTolDeg: Single): Integer;
var
  Raw: TTakeKeyframeArray;
  Keep: array of Boolean;
  N, I, OutCount: Integer;

  procedure SimplifyRange(const FirstIdx, LastIdx: Integer);
  var
    K, SplitIdx: Integer;
    SpanT, Alpha, PosErr, RotErr, FovErr, NormScore, BestScore: Single;
    Interp: TTakeKeyframe;
  begin
    if LastIdx <= FirstIdx + 1 then Exit;
    SpanT := Max(1e-6, Raw[LastIdx].TimeSec - Raw[FirstIdx].TimeSec);
    BestScore := -1.0;
    SplitIdx := -1;

    for K := FirstIdx + 1 to LastIdx - 1 do
    begin
      Alpha := EnsureRange((Raw[K].TimeSec - Raw[FirstIdx].TimeSec) / SpanT, 0.0, 1.0);
      Interp := InterpolateTakeKey(Raw[FirstIdx], Raw[LastIdx], Alpha);
      PosErr := PointsDistance(Raw[K].Location, Interp.Location);
      RotErr := Max(Abs(Raw[K].EulerDeg.X - Interp.EulerDeg.X),
                Max(Abs(Raw[K].EulerDeg.Y - Interp.EulerDeg.Y),
                    Abs(Raw[K].EulerDeg.Z - Interp.EulerDeg.Z)));
      FovErr := Abs(Raw[K].FovDeg - Interp.FovDeg);

      NormScore := Max(PosErr / Max(0.0001, APosTolM),
                   Max(RotErr / Max(0.001, ARotTolDeg),
                       FovErr / Max(0.05, ARotTolDeg)));
      if NormScore > BestScore then
      begin
        BestScore := NormScore;
        SplitIdx := K;
      end;
    end;

    if (BestScore > 1.0) and (SplitIdx > FirstIdx) then
    begin
      Keep[SplitIdx] := True;
      SimplifyRange(FirstIdx, SplitIdx);
      SimplifyRange(SplitIdx, LastIdx);
    end;
  end;

begin
  Result := 0;
  if (TrackIdx < 0) or (TrackIdx > High(FTracks)) then Exit;
  Raw := FTracks[TrackIdx].RawKeys;
  N := Length(Raw);
  if N = 0 then
  begin
    SetLength(FTracks[TrackIdx].ReducedKeys, 0);
    FTracks[TrackIdx].MaxPosErrorM := 0.0;
    Exit(0);
  end;
  if N <= 2 then
  begin
    SetLength(FTracks[TrackIdx].ReducedKeys, N);
    for I := 0 to N - 1 do
      FTracks[TrackIdx].ReducedKeys[I] := Raw[I];
    FTracks[TrackIdx].MaxPosErrorM := 0.0;
    Exit(N);
  end;

  SetLength(Keep, N);
  for I := 0 to N - 1 do
    Keep[I] := False;
  Keep[0] := True;
  Keep[N - 1] := True;

  SimplifyRange(0, N - 1);

  OutCount := 0;
  for I := 0 to N - 1 do
    if Keep[I] then Inc(OutCount);

  SetLength(FTracks[TrackIdx].ReducedKeys, OutCount);
  OutCount := 0;
  for I := 0 to N - 1 do
    if Keep[I] then
    begin
      FTracks[TrackIdx].ReducedKeys[OutCount] := Raw[I];
      Inc(OutCount);
    end;

  RecomputeTrackError(FTracks[TrackIdx]);
  Result := OutCount;
end;

procedure TCastleTakeRecorder.RecomputeTrackError(var ATrack: TTakeRecordedTrack);
var
  I, J, NR: Integer;
  T, Span, Alpha, ErrM, MaxErr: Single;
  Interp: TTakeKeyframe;
begin
  MaxErr := 0.0;
  NR := Length(ATrack.ReducedKeys);
  if NR >= 2 then
  begin
    J := 0;
    for I := 0 to High(ATrack.RawKeys) do
    begin
      T := ATrack.RawKeys[I].TimeSec;
      while (J < NR - 2) and (ATrack.ReducedKeys[J + 1].TimeSec < T) do
        Inc(J);
      Span := Max(1e-6, ATrack.ReducedKeys[J + 1].TimeSec - ATrack.ReducedKeys[J].TimeSec);
      Alpha := EnsureRange((T - ATrack.ReducedKeys[J].TimeSec) / Span, 0.0, 1.0);
      Interp := InterpolateTakeKey(ATrack.ReducedKeys[J], ATrack.ReducedKeys[J + 1], Alpha);
      ErrM := PointsDistance(ATrack.RawKeys[I].Location, Interp.Location);
      if ErrM > MaxErr then
        MaxErr := ErrM;
    end;
  end;
  ATrack.MaxPosErrorM := MaxErr;
end;

procedure TCastleTakeRecorder.ReduceAllTracks(const APosTolM, ARotTolDeg: Single);
var
  I: Integer;
begin
  FPosReduceToleranceM := EnsureRange(APosTolM, 0.0005, 2.0);
  FRotReduceToleranceDeg := EnsureRange(ARotTolDeg, 0.01, 45.0);
  for I := 0 to High(FTracks) do
    ReduceSingleTrackKeys(I, FPosReduceToleranceM, FRotReduceToleranceDeg);
end;

function TCastleTakeRecorder.EvaluateTrackAtTime(const TrackIdx: Integer;
  const ATimeSec: Single; const AUseReducedKeys: Boolean;
  out OutKey: TTakeKeyframe): Boolean;
var
  Keys: TTakeKeyframeArray;
  I, N: Integer;
  Span, Alpha: Single;
begin
  OutKey := Default(TTakeKeyframe);
  if (TrackIdx < 0) or (TrackIdx > High(FTracks)) then Exit(False);
  if AUseReducedKeys then
    Keys := FTracks[TrackIdx].ReducedKeys
  else
    Keys := FTracks[TrackIdx].RawKeys;

  N := Length(Keys);
  if N = 0 then Exit(False);
  if ATimeSec <= Keys[0].TimeSec then
  begin
    OutKey := Keys[0];
    Exit(True);
  end;
  if ATimeSec >= Keys[N - 1].TimeSec then
  begin
    OutKey := Keys[N - 1];
    Exit(True);
  end;

  for I := 0 to N - 2 do
    if (ATimeSec >= Keys[I].TimeSec) and (ATimeSec <= Keys[I + 1].TimeSec) then
    begin
      Span := Max(1e-6, Keys[I + 1].TimeSec - Keys[I].TimeSec);
      Alpha := EnsureRange((ATimeSec - Keys[I].TimeSec) / Span, 0.0, 1.0);
      OutKey := InterpolateTakeKey(Keys[I], Keys[I + 1], Alpha);
      Exit(True);
    end;

  OutKey := Keys[N - 1];
  Result := True;
end;

procedure TCastleTakeRecorder.BuildPresetStreamsAndTake;
begin
  SetLength(FSubjects, 0);
  SetLength(FTracks, 0);
  FHasRecordedAtLeastOnce := False;
  SimulatePresetTakeCapture(4.0);
end;

procedure TCastleTakeRecorder.SimulatePresetTakeCapture(const ADurationSec: Single);
var
  Steps, I: Integer;
  Dt, T, SegT, Angle: Single;
  HeroPos, HeroRot, CamPos, CamRot, BossPos, BossRot: TVector3;
  CamFov: Single;
begin
  SetLength(FSubjects, 0);
  EnsureLiveLinkSubject('Vicon_HeroPaladin_Pelvis', llrAnimationSkeleton, 'BP_HeroPaladin', 0.033);
  EnsureLiveLinkSubject('ARKit_iPhoneVCam_A', llrCamera, 'CineCamera_Main', 0.033);
  EnsureLiveLinkSubject('OptiTrack_BossWarlord', llrTransform, 'BP_BossWarlord', 0.016);

  StartNewTake('');

  Steps := Max(12, Round(Max(0.5, ADurationSec) * FRecordRateFps));
  Dt := Max(0.5, ADurationSec) / Steps;

  for I := 0 to Steps do
  begin
    T := I * Dt;
    { Segment 1 (0..1.5s): Straight linear sprint along +X (reduces to 2 keys!)
      Segment 2 (1.5..2.5s): Sharp 90-degree dodge lateral cut along +Z (reduces to 2 keys!)
      Segment 3 (2.5..4.0s): Smooth orbital finisher arc (reduces cleanly!) }
    if T <= 1.5 then
    begin
      HeroPos := Vector3(-4.5 + (T / 1.5) * 4.5, 0.95, -2.0);
      HeroRot := Vector3(0.0, 90.0, 0.0);
    end else
    if T <= 2.5 then
    begin
      SegT := (T - 1.5) / 1.0;
      HeroPos := Vector3(0.0, 0.95, -2.0 + SegT * 3.6);
      HeroRot := Vector3(0.0, 0.0, 0.0);
    end else
    begin
      SegT := (T - 2.5) / Max(0.01, ADurationSec - 2.5);
      Angle := SegT * (Pi * 0.65);
      HeroPos := Vector3(Sin(Angle) * 3.2, 0.95 + 0.35 * Sin(SegT * Pi), 1.6 + (1.0 - Cos(Angle)) * 1.8);
      HeroRot := Vector3(0.0, SegT * 115.0, 0.0);
    end;

    { Handheld VCam tracking hero on smooth dolly + zoom-in }
    CamPos := Vector3(-5.0 + T * 1.8, 2.1, -5.2 + 0.4 * Sin(T * 1.6));
    CamRot := Vector3(-12.0, 18.0 + T * 6.0, 0.0);
    CamFov := 54.0 - T * 2.5;

    { Boss steady advance }
    BossPos := Vector3(4.2 - T * 0.65, 1.15, 2.2 - T * 0.25);
    BossRot := Vector3(0.0, -135.0, 0.0);

    PushLiveLinkFrame('Vicon_HeroPaladin_Pelvis', llrAnimationSkeleton, T, HeroPos, HeroRot, 50.0, 3.5);
    PushLiveLinkFrame('ARKit_iPhoneVCam_A', llrCamera, T, CamPos, CamRot, CamFov, 4.2);
    PushLiveLinkFrame('OptiTrack_BossWarlord', llrTransform, T, BossPos, BossRot, 50.0, 5.0);

    AppendTrackRawKey('BP_HeroPaladin', llrAnimationSkeleton, T, HeroPos, HeroRot, 50.0);
    AppendTrackRawKey('CineCamera_Main', llrCamera, T, CamPos, CamRot, CamFov);
    AppendTrackRawKey('BP_BossWarlord', llrTransform, T, BossPos, BossRot, 50.0);
  end;

  FCurrentWorldTimeSec := Steps * Dt;
  StopAndFinalizeTake;
end;

function TCastleTakeRecorder.FormatSmpteTimecode(const ATimeSec: Double): String;
var
  FpsInt, TotalFrames, FF, SS, MM, HH: Integer;
begin
  FpsInt := Max(1, Round(FRecordRateFps));
  TotalFrames := Max(0, Round(ATimeSec * FpsInt));
  FF := TotalFrames mod FpsInt;
  SS := (TotalFrames div FpsInt) mod 60;
  MM := ((TotalFrames div FpsInt) div 60) mod 60;
  HH := 1 + ((TotalFrames div FpsInt) div 3600);
  Result := Format('%.2d:%.2d:%.2d:%.2d', [HH, MM, SS, FF]);
end;

function TCastleTakeRecorder.SubjectCount: Integer;
begin
  Result := Length(FSubjects);
end;

function TCastleTakeRecorder.ActiveGreenSubjectCount(const AWorldTimeSec: Double): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSubjects) do
    if SubjectStatusAtTime(I, AWorldTimeSec) = llsActiveGreen then
      Inc(Result);
end;

function TCastleTakeRecorder.TrackCount: Integer;
begin
  Result := Length(FTracks);
end;

function TCastleTakeRecorder.TotalRawKeyCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FTracks) do
    Inc(Result, Length(FTracks[I].RawKeys));
end;

function TCastleTakeRecorder.TotalReducedKeyCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FTracks) do
    Inc(Result, Length(FTracks[I].ReducedKeys));
end;

function TCastleTakeRecorder.KeyReductionPercent: Single;
var
  RawTotal, RedTotal: Integer;
begin
  RawTotal := TotalRawKeyCount;
  RedTotal := TotalReducedKeyCount;
  if RawTotal <= 0 then Exit(0.0);
  Result := EnsureRange((1.0 - RedTotal / RawTotal) * 100.0, 0.0, 100.0);
end;

function TCastleTakeRecorder.GetTakeDataJson: String;
var
  RootObj, SObj, TObj: TJSONObject;
  SubjArr, TrkArr, KArr, KItem: TJSONArray;
  I, J: Integer;
  K: TTakeKeyframe;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('worldTimeSec', FCurrentWorldTimeSec);
    SubjArr := TJSONArray.Create;
    for I := 0 to High(FSubjects) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('name', FSubjects[I].SubjectName);
      SObj.Add('role', Ord(FSubjects[I].Role));
      SObj.Add('target', FSubjects[I].TargetActorName);
      SObj.Add('offset', FSubjects[I].EvaluationOffsetSec);
      SObj.Add('lastRecv', FSubjects[I].LastReceiveTimeSec);
      SubjArr.Add(SObj);
    end;
    RootObj.Add('subjects', SubjArr);

    TrkArr := TJSONArray.Create;
    for I := 0 to High(FTracks) do
    begin
      TObj := TJSONObject.Create;
      TObj.Add('name', FTracks[I].TrackName);
      TObj.Add('role', Ord(FTracks[I].Role));
      TObj.Add('rawCount', Length(FTracks[I].RawKeys));
      TObj.Add('maxErrM', FTracks[I].MaxPosErrorM);
      KArr := TJSONArray.Create;
      for J := 0 to High(FTracks[I].ReducedKeys) do
      begin
        K := FTracks[I].ReducedKeys[J];
        KItem := TJSONArray.Create;
        KItem.Add(K.TimeSec);
        KItem.Add(K.Location.X);
        KItem.Add(K.Location.Y);
        KItem.Add(K.Location.Z);
        KItem.Add(K.EulerDeg.X);
        KItem.Add(K.EulerDeg.Y);
        KItem.Add(K.EulerDeg.Z);
        KItem.Add(K.FovDeg);
        KArr.Add(KItem);
      end;
      TObj.Add('reducedKeys', KArr);
      TrkArr.Add(TObj);
    end;
    RootObj.Add('tracks', TrkArr);

    FTakeDataJson := RootObj.AsJSON;
    Result := FTakeDataJson;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleTakeRecorder.SetTakeDataJson(const AValue: String);
var
  Parsed: TJSONData;
  RootObj, SObj, TObj: TJSONObject;
  SubjArr, TrkArr, KArr, KItem: TJSONArray;
  I, J: Integer;
begin
  FTakeDataJson := AValue;
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    try
      Parsed := GetJSON(AValue);
    except
      Exit;
    end;
    if not (Parsed is TJSONObject) then Exit;
    RootObj := TJSONObject(Parsed);
    FCurrentWorldTimeSec := RootObj.Get('worldTimeSec', FCurrentWorldTimeSec);

    if RootObj.Find('subjects') is TJSONArray then
    begin
      SubjArr := TJSONArray(RootObj.Find('subjects'));
      for I := 0 to Min(SubjArr.Count - 1, High(FSubjects)) do
        if SubjArr.Items[I] is TJSONObject then
        begin
          SObj := TJSONObject(SubjArr.Items[I]);
          FSubjects[I].EvaluationOffsetSec := SObj.Get('offset', FSubjects[I].EvaluationOffsetSec);
          FSubjects[I].LastReceiveTimeSec := SObj.Get('lastRecv', FSubjects[I].LastReceiveTimeSec);
        end;
    end;

    if RootObj.Find('tracks') is TJSONArray then
    begin
      TrkArr := TJSONArray(RootObj.Find('tracks'));
      SetLength(FTracks, TrkArr.Count);
      for I := 0 to TrkArr.Count - 1 do
        if TrkArr.Items[I] is TJSONObject then
        begin
          TObj := TJSONObject(TrkArr.Items[I]);
          FTracks[I].TrackName := TObj.Get('name', '');
          FTracks[I].Role := TLiveLinkRoleKind(EnsureRange(TObj.Get('role', 0),
            0, Ord(High(TLiveLinkRoleKind))));
          FTracks[I].MaxPosErrorM := TObj.Get('maxErrM', 0.0);
          if TObj.Find('reducedKeys') is TJSONArray then
          begin
            KArr := TJSONArray(TObj.Find('reducedKeys'));
            SetLength(FTracks[I].ReducedKeys, KArr.Count);
            for J := 0 to KArr.Count - 1 do
              if (KArr.Items[J] is TJSONArray) and (TJSONArray(KArr.Items[J]).Count >= 8) then
              begin
                KItem := TJSONArray(KArr.Items[J]);
                FTracks[I].ReducedKeys[J].TimeSec := KItem.Floats[0];
                FTracks[I].ReducedKeys[J].Location := Vector3(
                  KItem.Floats[1], KItem.Floats[2], KItem.Floats[3]);
                FTracks[I].ReducedKeys[J].EulerDeg := Vector3(
                  KItem.Floats[4], KItem.Floats[5], KItem.Floats[6]);
                FTracks[I].ReducedKeys[J].FovDeg := KItem.Floats[7];
              end;
          end;
        end;
    end;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleTakeRecorder.TakeRecorderSummaryBadge: String;
begin
  Result := Format('[Take:%s_T%.2d Keys=%d->%d (-%.0f%%) LiveLink=%d/%d]',
    [FSlateName,
     FTakeNumber,
     TotalRawKeyCount,
     TotalReducedKeyCount,
     KeyReductionPercent,
     ActiveGreenSubjectCount(FCurrentWorldTimeSec),
     SubjectCount]);
end;

initialization
  RegisterSerializableComponent(TCastleTakeRecorder,
    ['Cinematics & Audio', 'Take Recorder & Live Link Hub (TCastleTakeRecorder)']);

end.
