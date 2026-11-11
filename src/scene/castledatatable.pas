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

{ Schema-typed gameplay DataTables (@link(TCastleDataTable)), hierarchical
  dot-segmented Gameplay Tags (@link(TCastleGameplayTagBehavior)), progression
  balance curves, RFC-4180 CSV sync, and RTTI row-to-component binding
  (Phase 300 — UE 6.0 UDataTable, FGameplayTag & UCurveTable Parity). }
unit CastleDataTable;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleClassUtils, CastleUtils, CastleTransform;

type
  { Schema column value type inside @link(TCastleDataTable). }
  TDataColumnType = (
    dctFloat,
    dctInt,
    dctBool,
    dctString,
    dctTag
  );

  { Mathematical progression formula for level scaling & balance curves. }
  TBalanceCurveKind = (
    bckLinear,
    bckExponential,
    bckPolynomial,
    bckDiminishingReturns
  );

  TDataRowKeyArray = array of String;

  { Column definition in @link(TCastleDataTable). }
  TDataTableColumn = record
    ColumnName: String;
    ColumnType: TDataColumnType;
    DefaultValue: String;
  end;
  TDataTableColumnArray = array of TDataTableColumn;

  { Named row in @link(TCastleDataTable). }
  TDataTableRow = record
    RowKey: String;
    Values: array of String;
  end;
  TDataTableRowArray = array of TDataTableRow;

  { Behavior attaching UE 6.0-style hierarchical Gameplay Tags
    (e.g. @code('Enemy.Boss.Dragon, Status.Burning')) to any @link(TCastleTransform)
    with dot-prefix and wildcard @code('Enemy.Boss.*') query support. }
  TCastleGameplayTagBehavior = class(TCastleBehavior)
  strict private
    FTagsText: String;
    procedure SetTagsText(const Value: String);
  public
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Match a single hierarchical tag @code(ATag) (e.g. @code('Enemy.Boss.Dragon'))
      against a query @code(APattern) (e.g. @code('Enemy.Boss'),
      @code('Enemy.Boss.*'), or @code('Enemy.Boss.Dragon')).
      Enforces strict dot boundaries so @code('Enemy.Boss') never false-matches
      @code('Enemy.Bossy'). }
    class function MatchesSingleTag(const ATag, APattern: String): Boolean; static;

    { Match a comma/semicolon-separated tag list against @code(APattern). }
    class function TagListMatches(const ATagsCsv, APattern: String): Boolean; static;

    { Extract normalized non-empty tags from @link(TagsText). }
    function GetTagsArray: TDataRowKeyArray;
    function TagCount: Integer;

    function HasTag(const APattern: String): Boolean;
    function HasAnyTags(const APatterns: array of String): Boolean;
    function HasAllTags(const APatterns: array of String): Boolean;
    procedure AddTag(const ATag: String);
    procedure RemoveTag(const ATag: String);

    function TagSummaryBadge: String;
  published
    property TagsText: String read FTagsText write SetTagsText;
  end;

  { Non-visual typed gameplay spreadsheet storing named rows, schema-validated
    columns, RFC-4180 CSV import/export, and level progression curve formulas. }
  TCastleDataTable = class(TCastleComponent)
  strict private
    FTableTitle: String;
    FColumns: TDataTableColumnArray;
    FRows: TDataTableRowArray;
    FCurveKind: TBalanceCurveKind;
    FCurveBaseValue: Single;
    FCurveGrowthRate: Single;
    FCurveMaxLevel: Integer;

    function GetTableJson: String;
    procedure SetTableJson(const Value: String);
    procedure SetCurveBaseValue(const Value: Single);
    procedure SetCurveGrowthRate(const Value: Single);
    procedure SetCurveMaxLevel(const Value: Integer);
  public
    const
      DefaultCurveBaseValue = 100.0;
      DefaultCurveGrowthRate = 1.15;
      DefaultCurveMaxLevel = 20;

    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function ColumnTypeToName(const AType: TDataColumnType): String; static;
    class function NameToColumnType(const AName: String): TDataColumnType; static;
    class function CurveKindDisplayName(const AKind: TBalanceCurveKind): String; static;

    { Pure mathematical progression curve evaluator for level @code(ALevel >= 1). }
    class function EvaluateCurveValue(const AKind: TBalanceCurveKind;
      const ABase, AGrowth: Single; const ALevel: Integer): Single; static;

    procedure ClearTable;
    function ColumnCount: Integer;
    function GetColumn(const AIndex: Integer): TDataTableColumn;
    function FindColumnIndex(const AColumnName: String): Integer;
    function AddColumn(const AColumnName: String; const AType: TDataColumnType;
      const ADefaultValue: String = ''): Integer;

    function RowCount: Integer;
    function GetRowKey(const ARowIndex: Integer): String;
    function FindRowIndex(const ARowKey: String): Integer;
    function AddOrUpdateRow(const ARowKey: String): Integer;
    function RemoveRow(const ARowKey: String): Boolean;

    function SetCellString(const ARowKey, AColumnName, AValue: String): Boolean;
    function GetCellString(const ARowKey, AColumnName: String;
      const ADefault: String = ''): String;
    function GetCellFloat(const ARowKey, AColumnName: String;
      const ADefault: Single = 0.0): Single;
    function GetCellInt(const ARowKey, AColumnName: String;
      const ADefault: Integer = 0): Integer;
    function GetCellBool(const ARowKey, AColumnName: String;
      const ADefault: Boolean = false): Boolean;

    { Return all @code(RowKey)s whose @code(ATagColumnName) cell matches
      hierarchical Gameplay Tag query @code(ATagPattern). }
    function FindRowsMatchingTag(const ATagColumnName, ATagPattern: String): TDataRowKeyArray;

    { Validate every cell against its column's @link(TDataColumnType). }
    function ValidateSchemaCells(out OutIssues: TDataRowKeyArray): Boolean;

    { RFC-4180 CSV export with typed header (@code(RowKey,ColName:Type,...)) and import. }
    function ExportCsv: String;
    procedure ImportCsv(const ACsvText: String);

    { Evaluate this table's configured progression curve at @code(ALevel >= 1). }
    function EvaluateProgressionCurve(const ALevel: Integer): Single;

    { Populate @code(Level_01 .. Level_NN) rows into column @code(AColumnName)
      using @link(EvaluateProgressionCurve). }
    procedure BakeProgressionCurveIntoColumn(const AColumnName: String;
      const ADesignOwner: TComponent = nil);

    { Apply matching column values from @code(ARowKey) onto published RTTI
      properties of @code(ATarget) (plus @link(TCastleGameplayTagBehavior) when
      a @code(dctTag) column is present on a @link(TCastleTransform)).
      Returns the number of properties/tags applied. }
    function ApplyRowToComponent(const ARowKey: String; const ATarget: TObject;
      const ADesignOwner: TComponent = nil): Integer;

    { Populate built-in starter templates:
      @code(0) = RPG Enemy Archetypes, @code(1) = Weapon & Loot Balance,
      @code(2) = Level Progression Curve Table. }
    procedure LoadStarterTemplate(const ATemplateIndex: Integer);

    function DataTableSummaryBadge: String;
  published
    property TableTitle: String read FTableTitle write FTableTitle;
    property TableJson: String read GetTableJson write SetTableJson;
    property CurveKind: TBalanceCurveKind
      read FCurveKind write FCurveKind default bckExponential;
    property CurveBaseValue: Single
      read FCurveBaseValue write SetCurveBaseValue {$ifdef FPC}default DefaultCurveBaseValue{$endif};
    property CurveGrowthRate: Single
      read FCurveGrowthRate write SetCurveGrowthRate {$ifdef FPC}default DefaultCurveGrowthRate{$endif};
    property CurveMaxLevel: Integer
      read FCurveMaxLevel write SetCurveMaxLevel default DefaultCurveMaxLevel;
  end;

implementation

uses
  TypInfo, StrUtils, fpjson, jsonparser,
  CastleComponentSerialize;

function InvariantFormatSettings: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function SplitTagTokens(const S: String): TDataRowKeyArray;
var
  OutArr: TDataRowKeyArray;
  Cur: String;
  I: Integer;
  Ch: Char;

  procedure FlushToken;
  var
    Trimmed: String;
    N: Integer;
  begin
    Trimmed := Trim(Cur);
    Cur := '';
    if Trimmed = '' then
      Exit;
    N := Length(OutArr);
    SetLength(OutArr, N + 1);
    OutArr[N] := Trimmed;
  end;

begin
  OutArr := nil;
  Cur := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if (Ch = ',') or (Ch = ';') or (Ch = #10) or (Ch = #13) then
      FlushToken
    else
      Cur := Cur + Ch;
  end;
  FlushToken;
  Result := OutArr;
end;

function DefaultStringForColumnType(const AType: TDataColumnType): String;
begin
  case AType of
    dctFloat: Result := '0.0';
    dctInt: Result := '0';
    dctBool: Result := 'false';
    dctString: Result := '';
    dctTag: Result := '';
  end;
end;

{ TCastleGameplayTagBehavior ------------------------------------------------- }

function TCastleGameplayTagBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if PropertyName = 'TagsText' then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleGameplayTagBehavior.SetTagsText(const Value: String);
begin
  FTagsText := Trim(Value);
end;

class function TCastleGameplayTagBehavior.MatchesSingleTag(
  const ATag, APattern: String): Boolean;
var
  NormTag, NormPat: String;
begin
  Result := false;
  NormTag := LowerCase(Trim(ATag));
  NormPat := LowerCase(Trim(APattern));
  if (NormTag = '') or (NormPat = '') then
    Exit;

  if NormPat = '*' then
    Exit(true);

  if RightStr(NormPat, 2) = '.*' then
    NormPat := LeftStr(NormPat, Length(NormPat) - 2);

  if NormTag = NormPat then
    Exit(true);

  { Strict dot-segment ancestor prefix match: 'enemy.boss' matches 'enemy.boss.dragon' }
  if (Length(NormTag) > Length(NormPat) + 1) and
     (LeftStr(NormTag, Length(NormPat) + 1) = NormPat + '.') then
    Result := true;
end;

class function TCastleGameplayTagBehavior.TagListMatches(
  const ATagsCsv, APattern: String): Boolean;
var
  Tokens: TDataRowKeyArray;
  I: Integer;
begin
  Result := false;
  Tokens := SplitTagTokens(ATagsCsv);
  for I := 0 to High(Tokens) do
    if MatchesSingleTag(Tokens[I], APattern) then
      Exit(true);
end;

function TCastleGameplayTagBehavior.GetTagsArray: TDataRowKeyArray;
begin
  Result := SplitTagTokens(FTagsText);
end;

function TCastleGameplayTagBehavior.TagCount: Integer;
begin
  Result := Length(GetTagsArray);
end;

function TCastleGameplayTagBehavior.HasTag(const APattern: String): Boolean;
begin
  Result := TagListMatches(FTagsText, APattern);
end;

function TCastleGameplayTagBehavior.HasAnyTags(
  const APatterns: array of String): Boolean;
var
  I: Integer;
begin
  Result := false;
  for I := Low(APatterns) to High(APatterns) do
    if HasTag(APatterns[I]) then
      Exit(true);
end;

function TCastleGameplayTagBehavior.HasAllTags(
  const APatterns: array of String): Boolean;
var
  I: Integer;
begin
  if Length(APatterns) = 0 then
    Exit(false);
  for I := Low(APatterns) to High(APatterns) do
    if not HasTag(APatterns[I]) then
      Exit(false);
  Result := true;
end;

procedure TCastleGameplayTagBehavior.AddTag(const ATag: String);
var
  Clean: String;
  Existing: TDataRowKeyArray;
  I: Integer;
begin
  Clean := Trim(ATag);
  if Clean = '' then
    Exit;
  Existing := GetTagsArray;
  for I := 0 to High(Existing) do
    if SameText(Existing[I], Clean) then
      Exit;
  if FTagsText = '' then
    FTagsText := Clean
  else
    FTagsText := FTagsText + ', ' + Clean;
end;

procedure TCastleGameplayTagBehavior.RemoveTag(const ATag: String);
var
  Existing: TDataRowKeyArray;
  I: Integer;
  Rebuilt: String;
begin
  Existing := GetTagsArray;
  Rebuilt := '';
  for I := 0 to High(Existing) do
    if not SameText(Existing[I], Trim(ATag)) then
    begin
      if Rebuilt = '' then
        Rebuilt := Existing[I]
      else
        Rebuilt := Rebuilt + ', ' + Existing[I];
    end;
  FTagsText := Rebuilt;
end;

function TCastleGameplayTagBehavior.TagSummaryBadge: String;
var
  Arr: TDataRowKeyArray;
begin
  Arr := GetTagsArray;
  if Length(Arr) = 0 then
    Result := '[Tags:empty]'
  else if Length(Arr) = 1 then
    Result := Format('[Tags:%s]', [Arr[0]])
  else
    Result := Format('[Tags:%s +%d]', [Arr[0], Length(Arr) - 1]);
end;

{ TCastleDataTable ----------------------------------------------------------- }

constructor TCastleDataTable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTableTitle := 'GameplayBalance';
  FCurveKind := bckExponential;
  FCurveBaseValue := DefaultCurveBaseValue;
  FCurveGrowthRate := DefaultCurveGrowthRate;
  FCurveMaxLevel := DefaultCurveMaxLevel;
end;

function TCastleDataTable.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'TableTitle', 'TableJson', 'CurveKind',
       'CurveBaseValue', 'CurveGrowthRate', 'CurveMaxLevel'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleDataTable.ColumnTypeToName(
  const AType: TDataColumnType): String;
begin
  case AType of
    dctFloat: Result := 'Float';
    dctInt: Result := 'Int';
    dctBool: Result := 'Bool';
    dctString: Result := 'String';
    dctTag: Result := 'Tag';
  end;
end;

class function TCastleDataTable.NameToColumnType(
  const AName: String): TDataColumnType;
var
  S: String;
begin
  S := LowerCase(Trim(AName));
  if (S = 'float') or (S = 'single') or (S = 'number') then
    Result := dctFloat
  else if (S = 'int') or (S = 'integer') then
    Result := dctInt
  else if (S = 'bool') or (S = 'boolean') then
    Result := dctBool
  else if (S = 'tag') or (S = 'gameplaytag') then
    Result := dctTag
  else
    Result := dctString;
end;

class function TCastleDataTable.CurveKindDisplayName(
  const AKind: TBalanceCurveKind): String;
begin
  case AKind of
    bckLinear: Result := 'Linear (Base + Rate * (L-1))';
    bckExponential: Result := 'Exponential (Base * Rate^(L-1))';
    bckPolynomial: Result := 'Polynomial (Base * L^Rate)';
    bckDiminishingReturns: Result := 'Diminishing Returns (Asymptotic Cap)';
  end;
end;

class function TCastleDataTable.EvaluateCurveValue(
  const AKind: TBalanceCurveKind; const ABase, AGrowth: Single;
  const ALevel: Integer): Single;
var
  L: Integer;
begin
  L := Max(1, ALevel);
  case AKind of
    bckLinear:
      Result := ABase + AGrowth * (L - 1);
    bckExponential:
      Result := ABase * Power(Max(0.001, AGrowth), L - 1);
    bckPolynomial:
      Result := ABase * Power(L, AGrowth);
    bckDiminishingReturns:
      Result := ABase * (1.0 - 1.0 / (1.0 + Max(0.001, AGrowth) * L));
  end;
end;

procedure TCastleDataTable.SetCurveBaseValue(const Value: Single);
begin
  FCurveBaseValue := Value;
end;

procedure TCastleDataTable.SetCurveGrowthRate(const Value: Single);
begin
  FCurveGrowthRate := Value;
end;

procedure TCastleDataTable.SetCurveMaxLevel(const Value: Integer);
begin
  FCurveMaxLevel := Clamped(Value, 2, 200);
end;

procedure TCastleDataTable.ClearTable;
begin
  SetLength(FColumns, 0);
  SetLength(FRows, 0);
end;

function TCastleDataTable.ColumnCount: Integer;
begin
  Result := Length(FColumns);
end;

function TCastleDataTable.GetColumn(const AIndex: Integer): TDataTableColumn;
begin
  if (AIndex >= 0) and (AIndex <= High(FColumns)) then
    Result := FColumns[AIndex]
  else
    Result := Default(TDataTableColumn);
end;

function TCastleDataTable.FindColumnIndex(const AColumnName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FColumns) do
    if SameText(FColumns[I].ColumnName, Trim(AColumnName)) then
      Exit(I);
  Result := -1;
end;

function TCastleDataTable.AddColumn(const AColumnName: String;
  const AType: TDataColumnType; const ADefaultValue: String): Integer;
var
  CleanName, DefVal: String;
  R: Integer;
begin
  CleanName := Trim(AColumnName);
  if CleanName = '' then
    Exit(-1);
  Result := FindColumnIndex(CleanName);
  if Result >= 0 then
  begin
    FColumns[Result].ColumnType := AType;
    if ADefaultValue <> '' then
      FColumns[Result].DefaultValue := ADefaultValue;
    Exit;
  end;

  if ADefaultValue <> '' then
    DefVal := ADefaultValue
  else
    DefVal := DefaultStringForColumnType(AType);

  Result := Length(FColumns);
  SetLength(FColumns, Result + 1);
  FColumns[Result].ColumnName := CleanName;
  FColumns[Result].ColumnType := AType;
  FColumns[Result].DefaultValue := DefVal;

  for R := 0 to High(FRows) do
  begin
    SetLength(FRows[R].Values, Length(FColumns));
    FRows[R].Values[Result] := DefVal;
  end;
end;

function TCastleDataTable.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TCastleDataTable.GetRowKey(const ARowIndex: Integer): String;
begin
  if (ARowIndex >= 0) and (ARowIndex <= High(FRows)) then
    Result := FRows[ARowIndex].RowKey
  else
    Result := '';
end;

function TCastleDataTable.FindRowIndex(const ARowKey: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FRows) do
    if SameText(FRows[I].RowKey, Trim(ARowKey)) then
      Exit(I);
  Result := -1;
end;

function TCastleDataTable.AddOrUpdateRow(const ARowKey: String): Integer;
var
  CleanKey: String;
  C: Integer;
begin
  CleanKey := Trim(ARowKey);
  if CleanKey = '' then
    Exit(-1);
  Result := FindRowIndex(CleanKey);
  if Result >= 0 then
    Exit;

  Result := Length(FRows);
  SetLength(FRows, Result + 1);
  FRows[Result].RowKey := CleanKey;
  SetLength(FRows[Result].Values, Length(FColumns));
  for C := 0 to High(FColumns) do
    FRows[Result].Values[C] := FColumns[C].DefaultValue;
end;

function TCastleDataTable.RemoveRow(const ARowKey: String): Boolean;
var
  Idx, I: Integer;
begin
  Idx := FindRowIndex(ARowKey);
  if Idx < 0 then
    Exit(false);
  for I := Idx to High(FRows) - 1 do
    FRows[I] := FRows[I + 1];
  SetLength(FRows, Length(FRows) - 1);
  Result := true;
end;

function TCastleDataTable.SetCellString(const ARowKey, AColumnName,
  AValue: String): Boolean;
var
  RIdx, CIdx: Integer;
begin
  CIdx := FindColumnIndex(AColumnName);
  if CIdx < 0 then
    Exit(false);
  RIdx := AddOrUpdateRow(ARowKey);
  if RIdx < 0 then
    Exit(false);
  FRows[RIdx].Values[CIdx] := Trim(AValue);
  Result := true;
end;

function TCastleDataTable.GetCellString(const ARowKey, AColumnName: String;
  const ADefault: String): String;
var
  RIdx, CIdx: Integer;
begin
  RIdx := FindRowIndex(ARowKey);
  CIdx := FindColumnIndex(AColumnName);
  if (RIdx < 0) or (CIdx < 0) or (CIdx > High(FRows[RIdx].Values)) then
    Exit(ADefault);
  Result := FRows[RIdx].Values[CIdx];
end;

function TCastleDataTable.GetCellFloat(const ARowKey, AColumnName: String;
  const ADefault: Single): Single;
var
  S: String;
begin
  S := GetCellString(ARowKey, AColumnName, '');
  if not TryStrToFloat(S, Result, InvariantFormatSettings) then
    Result := ADefault;
end;

function TCastleDataTable.GetCellInt(const ARowKey, AColumnName: String;
  const ADefault: Integer): Integer;
begin
  Result := StrToIntDef(GetCellString(ARowKey, AColumnName, ''), ADefault);
end;

function TCastleDataTable.GetCellBool(const ARowKey, AColumnName: String;
  const ADefault: Boolean): Boolean;
var
  S: String;
begin
  S := LowerCase(Trim(GetCellString(ARowKey, AColumnName, '')));
  if (S = 'true') or (S = '1') or (S = 'yes') then
    Result := true
  else if (S = 'false') or (S = '0') or (S = 'no') then
    Result := false
  else
    Result := ADefault;
end;

function TCastleDataTable.FindRowsMatchingTag(
  const ATagColumnName, ATagPattern: String): TDataRowKeyArray;
var
  OutKeys: TDataRowKeyArray;
  CIdx, R, N: Integer;
begin
  OutKeys := nil;
  CIdx := FindColumnIndex(ATagColumnName);
  if CIdx < 0 then
    Exit(OutKeys);
  for R := 0 to High(FRows) do
    if (CIdx <= High(FRows[R].Values)) and
       TCastleGameplayTagBehavior.TagListMatches(FRows[R].Values[CIdx], ATagPattern) then
    begin
      N := Length(OutKeys);
      SetLength(OutKeys, N + 1);
      OutKeys[N] := FRows[R].RowKey;
    end;
  Result := OutKeys;
end;

function TCastleDataTable.ValidateSchemaCells(out OutIssues: TDataRowKeyArray): Boolean;
var
  Issues: TDataRowKeyArray;
  R, C: Integer;
  Val: String;
  DummyF: Single;
  DummyI: Integer;
  LowVal: String;

  procedure PushIssue(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(Issues);
    SetLength(Issues, N + 1);
    Issues[N] := Msg;
  end;

begin
  Issues := nil;
  for R := 0 to High(FRows) do
    for C := 0 to High(FColumns) do
    begin
      if C <= High(FRows[R].Values) then
        Val := Trim(FRows[R].Values[C])
      else
        Val := '';

      case FColumns[C].ColumnType of
        dctFloat:
          if not TryStrToFloat(Val, DummyF, InvariantFormatSettings) then
            PushIssue(Format('Row "%s", Column "%s" (Float): invalid value "%s".',
              [FRows[R].RowKey, FColumns[C].ColumnName, Val]));
        dctInt:
          if not TryStrToInt(Val, DummyI) then
            PushIssue(Format('Row "%s", Column "%s" (Int): invalid value "%s".',
              [FRows[R].RowKey, FColumns[C].ColumnName, Val]));
        dctBool:
          begin
            LowVal := LowerCase(Val);
            if (LowVal <> 'true') and (LowVal <> 'false') and
               (LowVal <> '1') and (LowVal <> '0') and
               (LowVal <> 'yes') and (LowVal <> 'no') then
              PushIssue(Format('Row "%s", Column "%s" (Bool): invalid value "%s".',
                [FRows[R].RowKey, FColumns[C].ColumnName, Val]));
          end;
        dctTag:
          if Pos(' ', Trim(ReplaceStr(Val, ', ', ','))) > 0 then
            PushIssue(Format('Row "%s", Column "%s" (Tag): tag "%s" contains whitespace inside segment.',
              [FRows[R].RowKey, FColumns[C].ColumnName, Val]));
      end;
    end;
  OutIssues := Issues;
  Result := Length(Issues) = 0;
end;

function EscapeCsvCell(const S: String): String;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

function ParseCsvLineCells(const ALine: String): TDataRowKeyArray;
var
  Cells: TDataRowKeyArray;
  Cur: String;
  I, N: Integer;
  InQuotes: Boolean;
begin
  Cells := nil;
  Cur := '';
  InQuotes := false;
  I := 1;
  while I <= Length(ALine) do
  begin
    if InQuotes then
    begin
      if ALine[I] = '"' then
      begin
        if (I < Length(ALine)) and (ALine[I + 1] = '"') then
        begin
          Cur := Cur + '"';
          Inc(I, 2);
          Continue;
        end else
          InQuotes := false;
      end else
        Cur := Cur + ALine[I];
    end else
    begin
      if ALine[I] = '"' then
        InQuotes := true
      else if ALine[I] = ',' then
      begin
        N := Length(Cells);
        SetLength(Cells, N + 1);
        Cells[N] := Cur;
        Cur := '';
      end else
        Cur := Cur + ALine[I];
    end;
    Inc(I);
  end;
  N := Length(Cells);
  SetLength(Cells, N + 1);
  Cells[N] := Cur;
  Result := Cells;
end;

function TCastleDataTable.ExportCsv: String;
var
  SB: TStringBuilder;
  C, R: Integer;
  LineStr: String;
begin
  SB := TStringBuilder.Create;
  try
    LineStr := 'RowKey';
    for C := 0 to High(FColumns) do
      LineStr := LineStr + ',' + EscapeCsvCell(
        FColumns[C].ColumnName + ':' + ColumnTypeToName(FColumns[C].ColumnType));
    SB.AppendLine(LineStr);

    for R := 0 to High(FRows) do
    begin
      LineStr := EscapeCsvCell(FRows[R].RowKey);
      for C := 0 to High(FColumns) do
      begin
        if C <= High(FRows[R].Values) then
          LineStr := LineStr + ',' + EscapeCsvCell(FRows[R].Values[C])
        else
          LineStr := LineStr + ',';
      end;
      SB.AppendLine(LineStr);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

procedure TCastleDataTable.ImportCsv(const ACsvText: String);
var
  Lines: TStringList;
  HeaderCells, RowCells: TDataRowKeyArray;
  I, C, ColonPos, RIdx: Integer;
  ColSpec, ColNameStr, ColTypeStr: String;
  ColT: TDataColumnType;
begin
  ClearTable;
  if Trim(ACsvText) = '' then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := ACsvText;
    if Lines.Count = 0 then
      Exit;

    HeaderCells := ParseCsvLineCells(Lines[0]);
    for C := 1 to High(HeaderCells) do
    begin
      ColSpec := Trim(HeaderCells[C]);
      ColonPos := Pos(':', ColSpec);
      if ColonPos > 0 then
      begin
        ColNameStr := Copy(ColSpec, 1, ColonPos - 1);
        ColTypeStr := Copy(ColSpec, ColonPos + 1, MaxInt);
        ColT := NameToColumnType(ColTypeStr);
      end else
      begin
        ColNameStr := ColSpec;
        ColT := dctString;
      end;
      AddColumn(ColNameStr, ColT);
    end;

    for I := 1 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;
      RowCells := ParseCsvLineCells(Lines[I]);
      if Length(RowCells) = 0 then
        Continue;
      RIdx := AddOrUpdateRow(RowCells[0]);
      if RIdx < 0 then
        Continue;
      for C := 1 to Min(High(RowCells), Length(FColumns)) do
        FRows[RIdx].Values[C - 1] := Trim(RowCells[C]);
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

function TCastleDataTable.GetTableJson: String;
var
  RootObj, ColObj, RowObj, CellsObj: TJSONObject;
  ColsArr, RowsArr: TJSONArray;
  C, R: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    ColsArr := TJSONArray.Create;
    RootObj.Add('columns', ColsArr);
    for C := 0 to High(FColumns) do
    begin
      ColObj := TJSONObject.Create;
      ColObj.Add('name', FColumns[C].ColumnName);
      ColObj.Add('type', ColumnTypeToName(FColumns[C].ColumnType));
      ColObj.Add('default', FColumns[C].DefaultValue);
      ColsArr.Add(ColObj);
    end;

    RowsArr := TJSONArray.Create;
    RootObj.Add('rows', RowsArr);
    for R := 0 to High(FRows) do
    begin
      RowObj := TJSONObject.Create;
      RowObj.Add('key', FRows[R].RowKey);
      CellsObj := TJSONObject.Create;
      RowObj.Add('cells', CellsObj);
      for C := 0 to High(FColumns) do
        if C <= High(FRows[R].Values) then
          CellsObj.Add(FColumns[C].ColumnName, FRows[R].Values[C]);
      RowsArr.Add(RowObj);
    end;

    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleDataTable.SetTableJson(const Value: String);
var
  Parsed: TJSONData;
  RootObj, ColObj, RowObj, CellsObj: TJSONObject;
  ColsArr, RowsArr: TJSONArray;
  C, R, RIdx: Integer;
  ColName: String;
begin
  ClearTable;
  if Trim(Value) = '' then
    Exit;

  Parsed := nil;
  try
    try
      Parsed := GetJSON(Value);
    except
      Exit;
    end;
    if not (Parsed is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Parsed);

    ColsArr := RootObj.Find('columns', jtArray) as TJSONArray;
    if ColsArr <> nil then
      for C := 0 to ColsArr.Count - 1 do
        if ColsArr.Items[C] is TJSONObject then
        begin
          ColObj := TJSONObject(ColsArr.Items[C]);
          AddColumn(
            ColObj.Get('name', ''),
            NameToColumnType(ColObj.Get('type', 'String')),
            ColObj.Get('default', ''));
        end;

    RowsArr := RootObj.Find('rows', jtArray) as TJSONArray;
    if RowsArr <> nil then
      for R := 0 to RowsArr.Count - 1 do
        if RowsArr.Items[R] is TJSONObject then
        begin
          RowObj := TJSONObject(RowsArr.Items[R]);
          RIdx := AddOrUpdateRow(RowObj.Get('key', ''));
          CellsObj := RowObj.Find('cells', jtObject) as TJSONObject;
          if (RIdx >= 0) and (CellsObj <> nil) then
            for C := 0 to High(FColumns) do
            begin
              ColName := FColumns[C].ColumnName;
              if CellsObj.IndexOfName(ColName) >= 0 then
                FRows[RIdx].Values[C] := CellsObj.Get(ColName, FColumns[C].DefaultValue);
            end;
        end;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleDataTable.EvaluateProgressionCurve(const ALevel: Integer): Single;
begin
  Result := EvaluateCurveValue(FCurveKind, FCurveBaseValue, FCurveGrowthRate, ALevel);
end;

procedure TCastleDataTable.BakeProgressionCurveIntoColumn(
  const AColumnName: String; const ADesignOwner: TComponent);
var
  ColName: String;
  L: Integer;
  KeyStr, ValStr: String;
begin
  ColName := Trim(AColumnName);
  if ColName = '' then
    ColName := 'ScaledValue';
  AddColumn('Level', dctInt, '1');
  AddColumn(ColName, dctFloat, '0.0');

  for L := 1 to FCurveMaxLevel do
  begin
    KeyStr := Format('Level_%.2d', [L]);
    ValStr := FormatFloat('0.00', EvaluateProgressionCurve(L), InvariantFormatSettings);
    SetCellString(KeyStr, 'Level', IntToStr(L));
    SetCellString(KeyStr, ColName, ValStr);
  end;
end;

function TCastleDataTable.ApplyRowToComponent(const ARowKey: String;
  const ATarget: TObject; const ADesignOwner: TComponent): Integer;
var
  RIdx, C: Integer;
  ColName, CellVal: String;
  PInfo: PPropInfo;
  TagBeh: TCastleGameplayTagBehavior;
  T: TCastleTransform;
  OwnerToUse: TComponent;
begin
  Result := 0;
  if ATarget = nil then
    Exit;
  RIdx := FindRowIndex(ARowKey);
  if RIdx < 0 then
    Exit;

  for C := 0 to High(FColumns) do
  begin
    if C > High(FRows[RIdx].Values) then
      Continue;
    ColName := FColumns[C].ColumnName;
    CellVal := FRows[RIdx].Values[C];

    if (FColumns[C].ColumnType = dctTag) and (ATarget is TCastleTransform) then
    begin
      T := TCastleTransform(ATarget);
      TagBeh := T.FindBehavior(TCastleGameplayTagBehavior) as TCastleGameplayTagBehavior;
      if TagBeh = nil then
      begin
        if ADesignOwner <> nil then
          OwnerToUse := ADesignOwner
        else
          OwnerToUse := T.Owner;
        TagBeh := TCastleGameplayTagBehavior.Create(OwnerToUse);
        T.AddBehavior(TagBeh);
      end;
      TagBeh.TagsText := CellVal;
      Inc(Result);
      Continue;
    end;

    PInfo := GetPropInfo(ATarget.ClassInfo, ColName);
    if (PInfo = nil) or (PInfo^.SetProc = nil) then
      Continue;

    case PInfo^.PropType^.Kind of
      tkFloat:
        begin
          SetFloatProp(ATarget, PInfo, GetCellFloat(ARowKey, ColName, GetFloatProp(ATarget, PInfo)));
          Inc(Result);
        end;
      tkInteger, tkInt64:
        begin
          SetOrdProp(ATarget, PInfo, GetCellInt(ARowKey, ColName, GetOrdProp(ATarget, PInfo)));
          Inc(Result);
        end;
      tkBool:
        begin
          SetOrdProp(ATarget, PInfo, Ord(GetCellBool(ARowKey, ColName, GetOrdProp(ATarget, PInfo) <> 0)));
          Inc(Result);
        end;
      tkAString, tkString, tkUString:
        begin
          SetStrProp(ATarget, PInfo, CellVal);
          Inc(Result);
        end;
    end;
  end;
end;

procedure TCastleDataTable.LoadStarterTemplate(const ATemplateIndex: Integer);
begin
  ClearTable;
  case ATemplateIndex of
    0:
      begin
        FTableTitle := 'EnemyArchetypes';
        FCurveKind := bckExponential;
        FCurveBaseValue := 120.0;
        FCurveGrowthRate := 1.22;
        FCurveMaxLevel := 20;

        AddColumn('MaxLife', dctFloat, '100.0');
        AddColumn('MoveSpeed', dctFloat, '4.5');
        AddColumn('XPReward', dctInt, '25');
        AddColumn('IsBoss', dctBool, 'false');
        AddColumn('GameplayTag', dctTag, 'Enemy.Minion');

        SetCellString('Goblin_Scout', 'MaxLife', '85.0');
        SetCellString('Goblin_Scout', 'MoveSpeed', '6.2');
        SetCellString('Goblin_Scout', 'XPReward', '30');
        SetCellString('Goblin_Scout', 'IsBoss', 'false');
        SetCellString('Goblin_Scout', 'GameplayTag', 'Enemy.Minion.Goblin, Faction.Horde');

        SetCellString('Orc_Berserker', 'MaxLife', '240.0');
        SetCellString('Orc_Berserker', 'MoveSpeed', '5.0');
        SetCellString('Orc_Berserker', 'XPReward', '95');
        SetCellString('Orc_Berserker', 'IsBoss', 'false');
        SetCellString('Orc_Berserker', 'GameplayTag', 'Enemy.Elite.Orc, Faction.Horde');

        SetCellString('Elder_Dragon', 'MaxLife', '2500.0');
        SetCellString('Elder_Dragon', 'MoveSpeed', '8.5');
        SetCellString('Elder_Dragon', 'XPReward', '1500');
        SetCellString('Elder_Dragon', 'IsBoss', 'true');
        SetCellString('Elder_Dragon', 'GameplayTag', 'Enemy.Boss.Dragon, Element.Fire');

        SetCellString('Lich_Sovereign', 'MaxLife', '1850.0');
        SetCellString('Lich_Sovereign', 'MoveSpeed', '4.2');
        SetCellString('Lich_Sovereign', 'XPReward', '1350');
        SetCellString('Lich_Sovereign', 'IsBoss', 'true');
        SetCellString('Lich_Sovereign', 'GameplayTag', 'Enemy.Boss.Lich, Faction.Undead');
      end;
    1:
      begin
        FTableTitle := 'WeaponLootBalance';
        FCurveKind := bckPolynomial;
        FCurveBaseValue := 15.0;
        FCurveGrowthRate := 1.35;
        FCurveMaxLevel := 15;

        AddColumn('BaseDamage', dctFloat, '12.0');
        AddColumn('CritChance', dctFloat, '0.05');
        AddColumn('GoldValue', dctInt, '50');
        AddColumn('IsLegendary', dctBool, 'false');
        AddColumn('ItemTag', dctTag, 'Item.Weapon.Melee');

        SetCellString('Rusty_Sword', 'BaseDamage', '14.0');
        SetCellString('Rusty_Sword', 'CritChance', '0.05');
        SetCellString('Rusty_Sword', 'GoldValue', '35');
        SetCellString('Rusty_Sword', 'IsLegendary', 'false');
        SetCellString('Rusty_Sword', 'ItemTag', 'Item.Weapon.Melee.Sword');

        SetCellString('Elven_Longbow', 'BaseDamage', '28.5');
        SetCellString('Elven_Longbow', 'CritChance', '0.18');
        SetCellString('Elven_Longbow', 'GoldValue', '280');
        SetCellString('Elven_Longbow', 'IsLegendary', 'false');
        SetCellString('Elven_Longbow', 'ItemTag', 'Item.Weapon.Ranged.Bow');

        SetCellString('Sunblade_Relic', 'BaseDamage', '92.0');
        SetCellString('Sunblade_Relic', 'CritChance', '0.30');
        SetCellString('Sunblade_Relic', 'GoldValue', '2400');
        SetCellString('Sunblade_Relic', 'IsLegendary', 'true');
        SetCellString('Sunblade_Relic', 'ItemTag', 'Item.Weapon.Melee.Sword, Rarity.Legendary');
      end;
  else
    begin
      FTableTitle := 'LevelProgressionXP';
      FCurveKind := bckExponential;
      FCurveBaseValue := 100.0;
      FCurveGrowthRate := 1.25;
      FCurveMaxLevel := 12;
      BakeProgressionCurveIntoColumn('RequiredXP');
    end;
  end;
end;

function TCastleDataTable.DataTableSummaryBadge: String;
begin
  Result := Format('[DataTable:%s %drx%dc]',
    [FTableTitle, Length(FRows), Length(FColumns)]);
end;

initialization
  RegisterSerializableComponent(TCastleDataTable,
    ['Data & Gameplay', 'DataTable & Balance Sheet']);
  RegisterSerializableComponent(TCastleGameplayTagBehavior,
    ['Data & Gameplay', 'Gameplay Tag Behavior']);
end.
