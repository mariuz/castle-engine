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

{ Stateless helper for the Chooser Tables Context-Driven Multi-Column Asset,
  Montage, Audio & VFX Selector Studio (Phase 347). }
unit ToolChooserTable;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils,
  CastleVectors, CastleViewport, CastleTransform,
  CastleChooserTable;

type
  TChooserStudioSummary = record
    TableCount: Integer;
    TotalRows: Integer;
    TotalEvaluations: Integer;
    LastMatchedRow: String;
    LastResolvedAsset: String;
    WarningsCount: Integer;
  end;

  TChooserTableHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstChooser(const ARoot: TComponent): TCastleChooserTable; static;

    class function SpawnFootstepAndBarkChooserDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ATable: TCastleChooserTable): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TChooserStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TChooserTableHelper.ResolveRootTransform(
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

class function TChooserTableHelper.FindFirstChooser(
  const ARoot: TComponent): TCastleChooserTable;

  function ScanRec(const T: TCastleTransform): TCastleChooserTable;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleChooserTable then
      Exit(TCastleChooserTable(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TChooserTableHelper.SpawnFootstepAndBarkChooserDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ATable: TCastleChooserTable): Boolean;
var
  RootT: TCastleTransform;
  Chosen: TChooserRow;
begin
  ATable := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  ATable := TCastleChooserTable.Create(ADesignOwner);
  ATable.Name := MakeUniqueName(ADesignOwner, 'FootstepChooserTable');
  ATable.ApplyPreset(chpFootstepSurfaceStance);
  RootT.Add(ATable);

  ATable.EvaluateChooser(
    TChooserContextQuery.Create('Surface.Stone.Wet', 'Stance.Sprint', 6.2, 0.0, True),
    Chosen);
  Result := True;
end;

class function TChooserTableHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TChooserStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I, BeforeCnt: Integer;
    C: TCastleChooserTable;
  begin
    if T = nil then Exit;
    if T is TCastleChooserTable then
    begin
      C := TCastleChooserTable(T);
      Inc(Result.TableCount);
      Result.TotalRows := Result.TotalRows + C.RowCount;
      Result.TotalEvaluations := Result.TotalEvaluations + C.TotalEvaluations;
      if Result.LastMatchedRow = '' then
      begin
        Result.LastMatchedRow := C.LastMatchedRowId;
        Result.LastResolvedAsset := C.LastResolvedAsset;
      end;
      if AWarnings <> nil then
      begin
        BeforeCnt := AWarnings.Count;
        if not C.ValidateRows(AWarnings) then
          Result.WarningsCount := Result.WarningsCount + (AWarnings.Count - BeforeCnt);
      end else if not C.ValidateRows(nil) then
        Inc(Result.WarningsCount);
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TChooserStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TChooserTableHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TChooserStudioSummary;
  C: TCastleChooserTable;
  SB: TStringBuilder;
  I: Integer;
  R: TChooserRow;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    C := FindFirstChooser(ARoot);
    SB.AppendLine('# Castle Game Engine — Context-Driven Chooser Tables Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Chooser Tables**: `%d` (`%d` total rule rows, `%d` evaluations)', [
      Sum.TableCount, Sum.TotalRows, Sum.TotalEvaluations]));
    SB.AppendLine(Format('- **Last Resolved Match**: `%s` -> `%s`', [
      IfThen(Sum.LastMatchedRow <> '', Sum.LastMatchedRow, 'None'),
      IfThen(Sum.LastResolvedAsset <> '', Sum.LastResolvedAsset, 'None')]));

    if (C <> nil) and (C.RowCount > 0) then
    begin
      SB.AppendLine;
      SB.AppendLine('| Row ID | Prio / Wt | Tag A | Tag B | Num A Range | Asset URL / Montage |');
      SB.AppendLine('| :--- | :---: | :--- | :--- | :---: | :--- |');
      for I := 0 to C.RowCount - 1 do
      begin
        R := C.GetRow(I);
        SB.AppendLine(Format('| `%s` | `%d` / `%.1f` | `%s` | `%s` | `[%.1f..%.1f]` | `%s` |', [
          R.RowId, R.Priority, R.Weight,
          IfThen(R.RequiredTagA <> '', R.RequiredTagA, '*'),
          IfThen(R.RequiredTagB <> '', R.RequiredTagB, '*'),
          R.MinNumericA, R.MaxNumericA, R.ResultAssetUrl]));
      end;
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
