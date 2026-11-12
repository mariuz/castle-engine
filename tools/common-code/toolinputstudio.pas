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

{ Stateless editor & headless test helpers for the Enhanced Input Action
  Mapping, Chord/Combo Triggers & Rebinding Studio (@link(TInputStudioHelper))
  (Phase 311 — UE 6.0+ Enhanced Input Parity). }
unit ToolInputStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleViewport,
  CastleUIControls, CastleEnhancedInput;

type
  { Audit report summarizing all @link(TCastleInputMapManager) nodes in a design. }
  TInputStudioAuditReport = class
  public
    Managers: array of TCastleInputMapManager;
    TotalContexts: Integer;
    TotalBindings: Integer;
    ConflictCount: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring, conflict auditing & Markdown helper for Enhanced Input. }
  TInputStudioHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TInputStudioAuditReport; static;

    class function CreateInputManagerInDesign(
      const RootComp, DesignOwner: TComponent;
      const APreset: TInputPresetKind;
      const ABaseName: String = 'InputMapManager'): TCastleInputMapManager; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils;

function MakeUniqueInputName(const OwnerComp: TComponent; const Base: String): String;
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

{ TInputStudioAuditReport ---------------------------------------------------- }

constructor TInputStudioAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TInputStudioAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TInputStudioHelper --------------------------------------------------------- }

class function TInputStudioHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TInputStudioAuditReport;
var
  Found: TList;

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    CC: TCastleComponent;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if C = nil then
      Exit;
    if (C is TCastleInputMapManager) and (Found.IndexOf(C) < 0) then
      Found.Add(C);

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
  I, J, Cnt: Integer;
  M: TCastleInputMapManager;
  SubWarnings: TStringList;
begin
  Result := TInputStudioAuditReport.Create;
  Found := TList.Create;
  SubWarnings := TStringList.Create;
  try
    Traverse(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        Traverse(DesignOwner.Components[I]);

    SetLength(Result.Managers, Found.Count);
    for I := 0 to Found.Count - 1 do
    begin
      M := TCastleInputMapManager(Found[I]);
      Result.Managers[I] := M;
      Inc(Result.TotalContexts, M.Contexts.Count);
      Inc(Result.TotalBindings, M.Bindings.Count);

      Cnt := M.DetectBindingConflicts(SubWarnings);
      Inc(Result.ConflictCount, Cnt);
      for J := 0 to SubWarnings.Count - 1 do
        Result.Warnings.Add(M.Name + ': ' + SubWarnings[J]);
    end;
  finally
    FreeAndNil(SubWarnings);
    FreeAndNil(Found);
  end;
end;

class function TInputStudioHelper.CreateInputManagerInDesign(
  const RootComp, DesignOwner: TComponent;
  const APreset: TInputPresetKind;
  const ABaseName: String): TCastleInputMapManager;
var
  OwnerToUse: TComponent;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleInputMapManager.Create(OwnerToUse);
  Result.Name := MakeUniqueInputName(OwnerToUse, ABaseName);
  Result.ApplyPreset(APreset);

  if RootComp is TCastleComponent then
    TCastleComponent(RootComp).AddNonVisualComponent(Result);
end;

class function TInputStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TInputStudioAuditReport;
  SB: TStringBuilder;
  I, J: Integer;
  M: TCastleInputMapManager;
  C: TInputMappingContextDef;
  B: TInputBindingDef;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Enhanced Input Action Mapping & Rebinding Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Input Managers**: %d | **Contexts**: %d | **Bindings**: %d | **Conflicts**: %d',
      [Length(Report.Managers), Report.TotalContexts, Report.TotalBindings, Report.ConflictCount]));
    SB.AppendLine;

    for I := 0 to High(Report.Managers) do
    begin
      M := Report.Managers[I];
      SB.AppendLine(Format('## `%s` %s', [M.Name, M.InputSummaryBadge]));
      SB.AppendLine('| Context | Priority | Active | Consume Keys |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for J := 0 to M.Contexts.Count - 1 do
      begin
        C := M.Contexts[J];
        SB.AppendLine(Format('| `%s` | %d | %s | %s |',
          [C.ContextId, C.Priority, BoolToStr(C.Active, True), BoolToStr(C.ConsumeMappedKeys, True)]));
      end;
      SB.AppendLine;

      SB.AppendLine('| Context | Action | Type | Key | Trigger | Chord / Threshold |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- |');
      for J := 0 to M.Bindings.Count - 1 do
      begin
        B := M.Bindings[J];
        SB.AppendLine(Format('| `%s` | `%s` | %s | `%s` | %s | `%s` (`%.2fs`) |',
          [B.ContextId, B.ActionId, InputValueKindToString(B.ValueKind),
           B.KeyName, InputTriggerToString(B.TriggerKind), B.ChordKeyName, B.ThresholdSec]));
      end;
      SB.AppendLine;
    end;

    if Report.Warnings.Count > 0 then
    begin
      SB.AppendLine('## Binding Conflicts & Warnings');
      for I := 0 to Report.Warnings.Count - 1 do
        SB.AppendLine('- ' + Report.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
