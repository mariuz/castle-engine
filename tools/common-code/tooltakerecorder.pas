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

{ Stateless scene helper, preset spawner, Douglas-Peucker ReduceKeys & LiveLink
  auditor, and Markdown report generator for Take Recorder & Live Link
  (Phase 397). }
unit ToolTakeRecorder;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleClassUtils, CastleVectors, CastleTransform, CastleViewport,
  CastleUIControls, CastleTakeRecorder;

type
  TTakeRecorderSceneAudit = record
    RecorderCount: Integer;
    TotalLiveLinkSubjects: Integer;
    ActiveGreenSubjects: Integer;
    TotalRecordedTracks: Integer;
    TotalRawKeys: Integer;
    TotalReducedKeys: Integer;
    AvgKeyReductionPct: Single;
  end;

  TTakeRecorderHelper = class
  public
    class procedure CollectTakeRecorders(const ARoot: TComponent;
      const AList: TList); static;
    class function FindFirstTakeRecorder(const ARoot: TComponent): TCastleTakeRecorder; static;
    class function FindTakeRecorderByName(const ARoot, AOwner: TComponent;
      const AName: String): TCastleTakeRecorder; static;

    class function SpawnTakeRecorderPresetInDesign(const ARoot, AOwner: TComponent;
      const APreset: TTakeRecorderPreset;
      const APosition: TVector3): TCastleTakeRecorder; static;

    class function AuditTakeRecordersInDesign(const ARoot: TComponent): TTakeRecorderSceneAudit; static;
    class function GenerateMarkdownReport(const ARoot: TComponent;
      const ActiveRec: TCastleTakeRecorder): String; static;
  end;

implementation

class procedure TTakeRecorderHelper.CollectTakeRecorders(
  const ARoot: TComponent; const AList: TList);

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleTakeRecorder) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Traverse(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Traverse(T[I]);
    end;
  end;

begin
  if (ARoot = nil) or (AList = nil) then Exit;
  Traverse(ARoot);
end;

class function TTakeRecorderHelper.FindFirstTakeRecorder(
  const ARoot: TComponent): TCastleTakeRecorder;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectTakeRecorders(ARoot, L);
    if L.Count > 0 then
      Result := TCastleTakeRecorder(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TTakeRecorderHelper.FindTakeRecorderByName(
  const ARoot, AOwner: TComponent; const AName: String): TCastleTakeRecorder;
var
  L: TList;
  I: Integer;
  C: TComponent;
begin
  if Trim(AName) = '' then
    Exit(FindFirstTakeRecorder(ARoot));

  Result := nil;
  if AOwner <> nil then
  begin
    C := AOwner.FindComponent(AName);
    if C is TCastleTakeRecorder then
      Exit(TCastleTakeRecorder(C));
  end;

  L := TList.Create;
  try
    CollectTakeRecorders(ARoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleTakeRecorder(L[I]).Name, AName) then
        Exit(TCastleTakeRecorder(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TTakeRecorderHelper.SpawnTakeRecorderPresetInDesign(
  const ARoot, AOwner: TComponent;
  const APreset: TTakeRecorderPreset;
  const APosition: TVector3): TCastleTakeRecorder;
var
  ParentItems: TCastleTransform;
  VP: TCastleViewport;
  I: Integer;
  BaseName: String;
begin
  Result := nil;
  if ARoot = nil then Exit;

  ParentItems := nil;
  if ARoot is TCastleViewport then
    ParentItems := TCastleViewport(ARoot).Items
  else if ARoot is TCastleTransform then
    ParentItems := TCastleTransform(ARoot)
  else if ARoot is TCastleUserInterface then
  begin
    for I := 0 to TCastleUserInterface(ARoot).ControlsCount - 1 do
      if TCastleUserInterface(ARoot).Controls[I] is TCastleViewport then
      begin
        VP := TCastleViewport(TCastleUserInterface(ARoot).Controls[I]);
        ParentItems := VP.Items;
        Break;
      end;
  end;
  if ParentItems = nil then Exit;

  Result := TCastleTakeRecorder.Create(AOwner);
  case APreset of
    trpMocapDuelAndCineCam:        BaseName := 'TakeRec_MocapBossDuel';
    trpVehicleChasePhysicsTake:    BaseName := 'TakeRec_VehicleChase';
    trpFacialArkitAndVCamLiveLink: BaseName := 'TakeRec_ARKitCloseUp';
  end;
  if AOwner <> nil then
    Result.Name := ProposeComponentName(TCastleTakeRecorder, AOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Preset := APreset;
  Result.Translation := APosition;
  ParentItems.Add(Result);
end;

class function TTakeRecorderHelper.AuditTakeRecordersInDesign(
  const ARoot: TComponent): TTakeRecorderSceneAudit;
var
  L: TList;
  I: Integer;
  R: TCastleTakeRecorder;
begin
  Result := Default(TTakeRecorderSceneAudit);
  L := TList.Create;
  try
    CollectTakeRecorders(ARoot, L);
    Result.RecorderCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      R := TCastleTakeRecorder(L[I]);
      Inc(Result.TotalLiveLinkSubjects, R.SubjectCount);
      Inc(Result.ActiveGreenSubjects, R.ActiveGreenSubjectCount(R.CurrentWorldTimeSec));
      Inc(Result.TotalRecordedTracks, R.TrackCount);
      Inc(Result.TotalRawKeys, R.TotalRawKeyCount);
      Inc(Result.TotalReducedKeys, R.TotalReducedKeyCount);
    end;
    if Result.TotalRawKeys > 0 then
      Result.AvgKeyReductionPct :=
        (1.0 - Result.TotalReducedKeys / Result.TotalRawKeys) * 100.0;
  finally
    FreeAndNil(L);
  end;
end;

class function TTakeRecorderHelper.GenerateMarkdownReport(
  const ARoot: TComponent; const ActiveRec: TCastleTakeRecorder): String;
var
  SB: TStringBuilder;
  I: Integer;
  Subj: TLiveLinkSubjectStream;
  Trk: TTakeRecordedTrack;
  St: TLiveLinkSubjectStatus;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Take Recorder & Live Link Streaming Report (Phase 397 — UE 5.5 UTakeRecorder / ILiveLinkClient Parity)');
    if ActiveRec <> nil then
    begin
      SB.AppendLine(Format('- **Active Slate / Take**: `%s` — **Take #%d** (`%s` @ `%.0f fps`)',
        [ActiveRec.SlateName, ActiveRec.TakeNumber,
         ActiveRec.FormatSmpteTimecode(ActiveRec.CurrentWorldTimeSec),
         ActiveRec.RecordRateFps]));
      SB.AppendLine(Format('- **Douglas-Peucker `ReduceKeys` Compression**: `%d` Raw Keys -> `%d` Sequencer Keys (**`-%.1f%%`** reduction, Tol=`%.3fm` / `%.2f°`)',
        [ActiveRec.TotalRawKeyCount, ActiveRec.TotalReducedKeyCount,
         ActiveRec.KeyReductionPercent,
         ActiveRec.PosReduceToleranceM, ActiveRec.RotReduceToleranceDeg]));
      SB.AppendLine;
      SB.AppendLine('| LiveLink Subject | UE Role | De-Jitter Offset | Status |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to ActiveRec.SubjectCount - 1 do
      begin
        Subj := ActiveRec.Subjects[I];
        St := ActiveRec.SubjectStatusAtTime(I, ActiveRec.CurrentWorldTimeSec);
        SB.AppendLine(Format('| `%s` | `%s` | `%.0f ms` | `%s` |',
          [Subj.SubjectName, LiveLinkRoleDisplayName(Subj.Role),
           Subj.EvaluationOffsetSec * 1000.0, LiveLinkStatusDisplayName(St)]));
      end;
      SB.AppendLine;
      SB.AppendLine('| Recorded Sequencer Track | Raw 60Hz Keys | Reduced Keys | Max Reconstruction Error |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to ActiveRec.TrackCount - 1 do
      begin
        Trk := ActiveRec.Tracks[I];
        SB.AppendLine(Format('| `%s` | `%d` | `%d` | `%.4f m` |',
          [Trk.TrackName, Length(Trk.RawKeys), Length(Trk.ReducedKeys), Trk.MaxPosErrorM]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
