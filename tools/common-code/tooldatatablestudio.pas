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

{ Hierarchy discovery, starter template instantiation, Gameplay Tag scene
  filtering, schema auditing, and Markdown spreadsheet export for
  @link(TCastleDataTable) and @link(TCastleGameplayTagBehavior)
  (Phase 300 — UE 6.0 UDataTable, FGameplayTag & UCurveTable Studio). }
unit ToolDataTableStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleClassUtils, CastleTransform, CastleUiControls, CastleViewport,
  CastleDataTable;

type
  TDataTableComponentArray = array of TCastleDataTable;
  TGameplayTagBehaviorArray = array of TCastleGameplayTagBehavior;
  TDataTableTransformArray = array of TCastleTransform;

  { Hierarchy scan & validation summary for DataTable & Gameplay Tag Studio. }
  TDataTableStudioSummary = record
    Tables: TDataTableComponentArray;
    TagBehaviors: TGameplayTagBehaviorArray;
    TotalRows: Integer;
    TotalColumns: Integer;
    Warnings: array of String;
  end;

  { Stateless editor helper for @link(TCastleDataTable) and Gameplay Tags. }
  TDataTableStudioHelper = class
  public
    class function ScanDataTablesAndTags(
      const ARoot: TComponent): TDataTableStudioSummary;

    class function CreateDataTableInDesign(
      const ARoot, ADesignOwner: TComponent;
      const AStarterTemplate: Integer = 0): TCastleDataTable;

    class function AttachGameplayTagsToTransform(
      const ATarget: TCastleTransform; const ADesignOwner: TComponent;
      const ATagsText: String): TCastleGameplayTagBehavior;

    { Find every @link(TCastleTransform) in @code(ARoot) whose attached
      @link(TCastleGameplayTagBehavior) matches @code(ATagPattern). }
    class function FindTransformsMatchingGameplayTag(
      const ARoot: TComponent; const ATagPattern: String): TDataTableTransformArray;

    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

function ProposeUniqueDataTableName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

{ TDataTableStudioHelper ----------------------------------------------------- }

class function TDataTableStudioHelper.ScanDataTablesAndTags(
  const ARoot: TComponent): TDataTableStudioSummary;
var
  OutSum: TDataTableStudioSummary;
  Visited: TList;

  procedure AppendWarning(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(OutSum.Warnings);
    SetLength(OutSum.Warnings, N + 1);
    OutSum.Warnings[N] := Msg;
  end;

  procedure AddTable(const DT: TCastleDataTable);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Tables) do
      if OutSum.Tables[I] = DT then
        Exit;
    SetLength(OutSum.Tables, Length(OutSum.Tables) + 1);
    OutSum.Tables[High(OutSum.Tables)] := DT;
    Inc(OutSum.TotalRows, DT.RowCount);
    Inc(OutSum.TotalColumns, DT.ColumnCount);
  end;

  procedure AddTagBehavior(const TB: TCastleGameplayTagBehavior);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.TagBehaviors) do
      if OutSum.TagBehaviors[I] = TB then
        Exit;
    SetLength(OutSum.TagBehaviors, Length(OutSum.TagBehaviors) + 1);
    OutSum.TagBehaviors[High(OutSum.TagBehaviors)] := TB;
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleDataTable then
      AddTable(TCastleDataTable(C));
    if C is TCastleGameplayTagBehavior then
      AddTagBehavior(TCastleGameplayTagBehavior(C));

    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        Visit(VP.Items);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Visit(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Visit(TCastleComponent(C).NonVisualComponents[I]);
  end;

var
  I, J: Integer;
  CellIssues: TDataRowKeyArray;
begin
  OutSum := Default(TDataTableStudioSummary);
  if ARoot = nil then
  begin
    Result := OutSum;
    Exit;
  end;

  Visited := TList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  for I := 0 to High(OutSum.Tables) do
  begin
    if OutSum.Tables[I].ColumnCount = 0 then
      AppendWarning(Format('DataTable "%s" has 0 columns defined.', [OutSum.Tables[I].Name]));
    if not OutSum.Tables[I].ValidateSchemaCells(CellIssues) then
      for J := 0 to High(CellIssues) do
        AppendWarning(Format('[%s] %s', [OutSum.Tables[I].Name, CellIssues[J]]));
  end;

  for I := 0 to High(OutSum.TagBehaviors) do
    if OutSum.TagBehaviors[I].TagCount = 0 then
      AppendWarning(Format('GameplayTagBehavior "%s" has an empty TagsText.',
        [OutSum.TagBehaviors[I].Name]));

  Result := OutSum;
end;

class function TDataTableStudioHelper.CreateDataTableInDesign(
  const ARoot, ADesignOwner: TComponent;
  const AStarterTemplate: Integer): TCastleDataTable;
var
  OwnerToUse: TComponent;
  BaseName: String;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  case AStarterTemplate of
    0: BaseName := 'EnemyDataTable';
    1: BaseName := 'WeaponDataTable';
  else
    BaseName := 'ProgressionDataTable';
  end;

  Result := TCastleDataTable.Create(OwnerToUse);
  Result.Name := ProposeUniqueDataTableName(OwnerToUse, BaseName);
  Result.LoadStarterTemplate(AStarterTemplate);

  if ARoot is TCastleComponent then
    TCastleComponent(ARoot).AddNonVisualComponent(Result);
end;

class function TDataTableStudioHelper.AttachGameplayTagsToTransform(
  const ATarget: TCastleTransform; const ADesignOwner: TComponent;
  const ATagsText: String): TCastleGameplayTagBehavior;
var
  OwnerToUse: TComponent;
begin
  Result := nil;
  if ATarget = nil then
    Exit;

  Result := ATarget.FindBehavior(TCastleGameplayTagBehavior) as TCastleGameplayTagBehavior;
  if Result = nil then
  begin
    if ADesignOwner <> nil then
      OwnerToUse := ADesignOwner
    else
      OwnerToUse := ATarget.Owner;
    Result := TCastleGameplayTagBehavior.Create(OwnerToUse);
    Result.Name := ProposeUniqueDataTableName(OwnerToUse, 'GameplayTags');
    ATarget.AddBehavior(Result);
  end;
  Result.TagsText := ATagsText;
end;

class function TDataTableStudioHelper.FindTransformsMatchingGameplayTag(
  const ARoot: TComponent; const ATagPattern: String): TDataTableTransformArray;
var
  Sum: TDataTableStudioSummary;
  OutArr: TDataTableTransformArray;
  I, N: Integer;
  TB: TCastleGameplayTagBehavior;
begin
  OutArr := nil;
  Sum := ScanDataTablesAndTags(ARoot);
  for I := 0 to High(Sum.TagBehaviors) do
  begin
    TB := Sum.TagBehaviors[I];
    if (TB.Parent <> nil) and TB.HasTag(ATagPattern) then
    begin
      N := Length(OutArr);
      SetLength(OutArr, N + 1);
      OutArr[N] := TB.Parent;
    end;
  end;
  Result := OutArr;
end;

class function TDataTableStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Sum: TDataTableStudioSummary;
  SB: TStringBuilder;
  I, C, R, L: Integer;
  DT: TCastleDataTable;
  Col: TDataTableColumn;
  HeaderStr, SepStr, RowStr, KeyStr: String;
begin
  Sum := ScanDataTablesAndTags(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Gameplay DataTables, Hierarchical Tags & Balance Curves Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **DataTables**: `%d` (`%d` total rows, `%d` total columns) | **Tagged Entities**: `%d`',
      [Length(Sum.Tables), Sum.TotalRows, Sum.TotalColumns, Length(Sum.TagBehaviors)]));
    SB.AppendLine;

    for I := 0 to High(Sum.Tables) do
    begin
      DT := Sum.Tables[I];
      SB.AppendLine(Format('## DataTable `%s` (`%s`)', [DT.Name, DT.TableTitle]));
      SB.AppendLine(Format('- **Progression Curve**: `%s` (`Base = %.2f`, `Rate = %.3f`, `MaxLevel = %d`, `L1->L10 = %.1f -> %.1f`)',
        [TCastleDataTable.CurveKindDisplayName(DT.CurveKind),
         DT.CurveBaseValue, DT.CurveGrowthRate, DT.CurveMaxLevel,
         DT.EvaluateProgressionCurve(1), DT.EvaluateProgressionCurve(10)]));
      SB.AppendLine;

      if DT.ColumnCount > 0 then
      begin
        HeaderStr := '| RowKey |';
        SepStr := '| :--- |';
        for C := 0 to DT.ColumnCount - 1 do
        begin
          Col := DT.GetColumn(C);
          HeaderStr := HeaderStr + Format(' %s (`%s`) |',
            [Col.ColumnName, TCastleDataTable.ColumnTypeToName(Col.ColumnType)]);
          SepStr := SepStr + ' :--- |';
        end;
        SB.AppendLine(HeaderStr);
        SB.AppendLine(SepStr);

        for R := 0 to DT.RowCount - 1 do
        begin
          KeyStr := DT.GetRowKey(R);
          RowStr := Format('| `%s` |', [KeyStr]);
          for C := 0 to DT.ColumnCount - 1 do
          begin
            Col := DT.GetColumn(C);
            RowStr := RowStr + Format(' `%s` |', [DT.GetCellString(KeyStr, Col.ColumnName, '')]);
          end;
          SB.AppendLine(RowStr);
        end;
        SB.AppendLine;
      end;

      SB.AppendLine('### Sample Progression Curve Preview (`L1, L5, L10, L15, L20`)');
      RowStr := '- ';
      for L in [1, 5, 10, 15, 20] do
        if L <= DT.CurveMaxLevel then
          RowStr := RowStr + Format('`L%d = %.2f`  ', [L, DT.EvaluateProgressionCurve(L)]);
      SB.AppendLine(RowStr);
      SB.AppendLine;
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Schema & Tag Diagnostics');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- [!] ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
