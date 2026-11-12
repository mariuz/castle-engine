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

{ Stateless editor & headless test helpers for the SaveGame Slot Manager,
  Versioned World-State Snapshot & Deterministic Replay Recorder Studio
  (@link(TSaveReplayHelper)) (Phase 315 — UE 6.0+ SaveGame & Replay Parity). }
unit ToolSaveReplay;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleViewport,
  CastleUIControls, CastleSaveReplay;

type
  { Audit report summarizing SaveGame managers & Replay recorders in a design. }
  TSaveReplayAuditReport = class
  public
    SaveManagers: array of TCastleSaveSlotManager;
    ReplayRecorders: array of TCastleReplayRecorder;
    TotalSaveSlots: Integer;
    TotalReplayFrames: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring, checkpoint capture & replay helper. }
  TSaveReplayHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TSaveReplayAuditReport; static;

    class function EnsureSaveSlotManagerInDesign(
      const RootComp, DesignOwner: TComponent): TCastleSaveSlotManager; static;
    class function EnsureReplayRecorderInDesign(
      const RootComp, DesignOwner: TComponent): TCastleReplayRecorder; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

function MakeUniqueSaveReplayName(const OwnerComp: TComponent; const Base: String): String;
var
  Idx: Integer;
begin
  if (OwnerComp = nil) or (OwnerComp.FindComponent(Base) = nil) then
    Exit(Base);
  Idx := 1;
  repeat
    Result := Base + IntToStr(Idx);
    Inc(Idx);
  until OwnerComp.FindComponent(Result) = nil;
end;

procedure AttachNonVisualIfPossible(const RootComp: TComponent; const NonVis: TCastleComponent);
begin
  if RootComp is TCastleUserInterface then
    TCastleUserInterface(RootComp).AddNonVisualComponent(NonVis)
  else if RootComp is TCastleTransform then
    TCastleTransform(RootComp).AddNonVisualComponent(NonVis);
end;

{ TSaveReplayAuditReport ----------------------------------------------------- }

constructor TSaveReplayAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TSaveReplayAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TSaveReplayHelper ---------------------------------------------------------- }

class function TSaveReplayHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TSaveReplayAuditReport;
var
  FoundSave, FoundReplay: TList;

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    UI: TCastleUserInterface;
    T: TCastleTransform;
    CC: TCastleComponent;
  begin
    if C = nil then
      Exit;
    if (C is TCastleSaveSlotManager) and (FoundSave.IndexOf(C) < 0) then
      FoundSave.Add(C);
    if (C is TCastleReplayRecorder) and (FoundReplay.IndexOf(C) < 0) then
      FoundReplay.Add(C);

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
      if not (csTransient in T.ComponentStyle) then
        for I := 0 to T.Count - 1 do
          Traverse(T[I]);
    end;
  end;

var
  I: Integer;
begin
  Result := TSaveReplayAuditReport.Create;
  FoundSave := TList.Create;
  FoundReplay := TList.Create;
  try
    Traverse(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        Traverse(DesignOwner.Components[I]);

    SetLength(Result.SaveManagers, FoundSave.Count);
    for I := 0 to FoundSave.Count - 1 do
    begin
      Result.SaveManagers[I] := TCastleSaveSlotManager(FoundSave[I]);
      Inc(Result.TotalSaveSlots, Result.SaveManagers[I].Slots.Count);
    end;

    SetLength(Result.ReplayRecorders, FoundReplay.Count);
    for I := 0 to FoundReplay.Count - 1 do
    begin
      Result.ReplayRecorders[I] := TCastleReplayRecorder(FoundReplay[I]);
      Inc(Result.TotalReplayFrames, Result.ReplayRecorders[I].FrameCount);
    end;

    if Length(Result.SaveManagers) > 1 then
      Result.Warnings.Add('Multiple TCastleSaveSlotManager components exist in the same design; consolidate into a single manager.');
  finally
    FreeAndNil(FoundReplay);
    FreeAndNil(FoundSave);
  end;
end;

class function TSaveReplayHelper.EnsureSaveSlotManagerInDesign(
  const RootComp, DesignOwner: TComponent): TCastleSaveSlotManager;
var
  Report: TSaveReplayAuditReport;
  OwnerToUse: TComponent;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    if Length(Report.SaveManagers) > 0 then
      Exit(Report.SaveManagers[0]);
  finally
    FreeAndNil(Report);
  end;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleSaveSlotManager.Create(OwnerToUse);
  Result.Name := MakeUniqueSaveReplayName(OwnerToUse, 'SaveSlotManager');
  AttachNonVisualIfPossible(RootComp, Result);
end;

class function TSaveReplayHelper.EnsureReplayRecorderInDesign(
  const RootComp, DesignOwner: TComponent): TCastleReplayRecorder;
var
  Report: TSaveReplayAuditReport;
  OwnerToUse: TComponent;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    if Length(Report.ReplayRecorders) > 0 then
      Exit(Report.ReplayRecorders[0]);
  finally
    FreeAndNil(Report);
  end;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleReplayRecorder.Create(OwnerToUse);
  Result.Name := MakeUniqueSaveReplayName(OwnerToUse, 'ReplayRecorder');
  AttachNonVisualIfPossible(RootComp, Result);
end;

class function TSaveReplayHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TSaveReplayAuditReport;
  SB: TStringBuilder;
  I, J: Integer;
  SM: TCastleSaveSlotManager;
  RR: TCastleReplayRecorder;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# SaveGame Slot Manager & Deterministic Replay Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Save Managers**: %d (`%d` slots) | **Replay Recorders**: %d (`%d` keyframes)',
      [Length(Report.SaveManagers), Report.TotalSaveSlots,
       Length(Report.ReplayRecorders), Report.TotalReplayFrames]));
    SB.AppendLine;

    for I := 0 to High(Report.SaveManagers) do
    begin
      SM := Report.SaveManagers[I];
      SB.AppendLine(Format('## Save Manager `%s` (Schema `v%d`, Playtime `%.1fs`)',
        [SM.Name, SM.SchemaVersion, SM.PlaytimeSec]));
      if SM.Slots.Count > 0 then
      begin
        SB.AppendLine('| Slot ID | Title | Schema | Timestamp | Playtime (s) |');
        SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
        for J := 0 to SM.Slots.Count - 1 do
          SB.AppendLine(Format('| `%s` | %s | v%d | `%s` | %.1f |',
            [SM.Slots[J].SlotId, SM.Slots[J].SlotTitle,
             SM.Slots[J].SchemaVersion, SM.Slots[J].TimestampIso,
             SM.Slots[J].PlaytimeSec]));
      end else
        SB.AppendLine('_No checkpoint slots captured yet._');
      SB.AppendLine;
    end;

    for I := 0 to High(Report.ReplayRecorders) do
    begin
      RR := Report.ReplayRecorders[I];
      SB.AppendLine(Format('## Replay Recorder `%s` (`%d` frames, `%.2fs` duration, `%d` cues)',
        [RR.Name, RR.FrameCount, RR.DurationSec, RR.CueEvents.Count]));
      SB.AppendLine;
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
