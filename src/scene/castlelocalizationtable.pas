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

{ Multi-locale string-table manager, CSV/JSON import-export, live hierarchy
  @link(TranslateProperties) + RTTI locale switcher, accented + expanded
  @code([!! Pseudo-L10n !!]) stress-testing, and 3D transform localization
  behavior (@link(TCastleLocalizationManager), @link(TCastleLocalizedBehavior))
  (Phase 294 — UE 5.9 / 6.0 Localization Dashboard Parity). }
unit CastleLocalizationTable;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleClassUtils, CastleTransform;

type
  { Single locale -> translated string pair inside a @link(TLocalizationStringEntry). }
  TLocalizationLocaleValue = record
    Locale: String;
    Value: String;
  end;
  TLocalizationLocaleValueArray = array of TLocalizationLocaleValue;

  { Keyed localization entry bound to an optional component + property. }
  TLocalizationStringEntry = record
    Key: String;
    ComponentName: String;
    PropertyName: String;
    Values: TLocalizationLocaleValueArray;
  end;
  TLocalizationStringEntryArray = array of TLocalizationStringEntry;

  { Non-visual component storing a multi-locale string table serialized as
    diff-friendly JSON (@link(TableDataJson)), with fallback-locale resolution,
    RFC-4180 CSV import/export, live hierarchy switching, and
    @code([!! Pseudo-L10n !!]) UI overflow stress-testing. }
  TCastleLocalizationManager = class(TCastleComponent)
  public const
    DefaultFallbackLocale = 'en';
    PseudoLocaleCode = 'pseudo';
  strict private
    FActiveLocale: String;
    FFallbackLocale: String;
    FEntries: TLocalizationStringEntryArray;
    procedure SetActiveLocale(const AValue: String);
    procedure SetFallbackLocale(const AValue: String);
    function GetTableDataJson: String;
    procedure SetTableDataJson(const AValue: String);
    function FindEntryIndex(const AKey: String): Integer;
    function FindComponentPropertyEntryIndex(const ACompName, APropName: String): Integer;
    procedure ApplyTranslateCallback(const ASender: TCastleComponent;
      const APropertyName: String; var APropertyValue: String);
  strict private
    FApplyTargetLocale: String;
    FAppliedPropertyCount: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearEntries;
    function EntryCount: Integer;
    { Return true if any entry is already bound to @code((ACompName, APropName)). }
    function HasComponentPropertyBinding(const ACompName, APropName: String): Boolean;
    function GetEntry(const AIndex: Integer): TLocalizationStringEntry;

    { Insert or update @code(AValue) for @code((AKey, ALocale)). }
    procedure SetTranslation(const AKey, ALocale, AValue: String;
      const AComponentName: String = '';
      const APropertyName: String = 'Caption');

    { Return exact translation stored for @code((AKey, ALocale)), or @code('')
      with @code(OutFoundExact = false) if absent. }
    function GetExactTranslation(const AKey, ALocale: String;
      out OutFoundExact: Boolean): String;

    { Resolve @code(AKey) for @code(ALocale):
      - When @code(ALocale = 'pseudo'), generates accented + 35%-expanded text
        from @link(FallbackLocale).
      - Otherwise returns exact @code(ALocale) value, falling back to
        @link(FallbackLocale) if missing. }
    function ResolveTranslation(const AKey, ALocale: String;
      out OutUsedFallback: Boolean): String;

    // Deterministic accented + length-expanded pseudo-localization generator
    // preserving %s, %d, and {0} format tokens untouched.
    class function GeneratePseudoLocalizedText(const ASourceText: String;
      const AExpansionRatio: Single = 0.35): String;

    { Collect distinct locale codes present across all entries (always starting
      with @link(FallbackLocale)). }
    function CollectKnownLocales: TStringList;

    { Export the full string table as RFC-4180 CSV
      (@code(Key,Component,Property,<locales...>)). }
    function ExportCsv: String;

    { Import/merge rows from RFC-4180 CSV exported by @link(ExportCsv). }
    function ImportCsv(const ACsvText: String): Integer;

    { Apply @code(ALocale) (or @link(ActiveLocale) when @code(ALocale = ''))
      across @code(ARoot) using CGE @code(TranslateProperties), RTTI string
      properties, and @link(TCastleLocalizedBehavior) bindings.
      Returns the number of translated properties applied. }
    function ApplyLocaleToHierarchy(const ARoot: TComponent;
      const ALocale: String = ''): Integer;

    function LocalizationSummaryBadge: String;
  published
    property ActiveLocale: String read FActiveLocale write SetActiveLocale;
    property FallbackLocale: String read FFallbackLocale write SetFallbackLocale;
    property TableDataJson: String read GetTableDataJson write SetTableDataJson;
  end;

  { Behavior attached to a 3D @link(TCastleTransform) (such as @code(TCastleText))
    binding one of its string properties (default @code('Caption')) to a
    localization key in @link(TCastleLocalizationManager). }
  TCastleLocalizedBehavior = class(TCastleBehavior)
  strict private
    FTranslationKey: String;
    FTargetProperty: String;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalizedSummaryBadge: String;
  published
    property TranslationKey: String read FTranslationKey write FTranslationKey;
    property TargetProperty: String read FTargetProperty write FTargetProperty;
  end;

implementation

uses
  Math, StrUtils, TypInfo, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize, CastleUIControls, CastleViewport;

function NormalizeLocaleCode(const S: String): String;
begin
  Result := LowerCase(Trim(S));
  if Result = '' then
    Result := TCastleLocalizationManager.DefaultFallbackLocale;
end;

function CsvEscapeCell(const S: String): String;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or
     (Pos(#10, S) > 0) or (Pos(#13, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

procedure ParseCsvLineCells(const ALine: String; const AOutCells: TStringList);
var
  I, Len: Integer;
  InQuotes: Boolean;
  Cur: String;
  Ch: Char;
begin
  AOutCells.Clear;
  Len := Length(ALine);
  if Len = 0 then
    Exit;
  I := 1;
  InQuotes := false;
  Cur := '';
  while I <= Len do
  begin
    Ch := ALine[I];
    if InQuotes then
    begin
      if Ch = '"' then
      begin
        if (I < Len) and (ALine[I + 1] = '"') then
        begin
          Cur := Cur + '"';
          Inc(I, 2);
          Continue;
        end else
          InQuotes := false;
      end else
        Cur := Cur + Ch;
    end else
    begin
      if Ch = '"' then
        InQuotes := true
      else if Ch = ',' then
      begin
        AOutCells.Add(Cur);
        Cur := '';
      end else
        Cur := Cur + Ch;
    end;
    Inc(I);
  end;
  AOutCells.Add(Cur);
end;

{ TCastleLocalizationManager ------------------------------------------------- }

constructor TCastleLocalizationManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActiveLocale := DefaultFallbackLocale;
  FFallbackLocale := DefaultFallbackLocale;
  SetLength(FEntries, 0);
end;

function TCastleLocalizationManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ActiveLocale', 'FallbackLocale', 'TableDataJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLocalizationManager.SetActiveLocale(const AValue: String);
begin
  FActiveLocale := NormalizeLocaleCode(AValue);
end;

procedure TCastleLocalizationManager.SetFallbackLocale(const AValue: String);
begin
  FFallbackLocale := NormalizeLocaleCode(AValue);
end;

procedure TCastleLocalizationManager.ClearEntries;
begin
  SetLength(FEntries, 0);
end;

function TCastleLocalizationManager.EntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TCastleLocalizationManager.GetEntry(
  const AIndex: Integer): TLocalizationStringEntry;
begin
  if (AIndex >= 0) and (AIndex < Length(FEntries)) then
    Result := FEntries[AIndex]
  else
    Result := Default(TLocalizationStringEntry);
end;

function TCastleLocalizationManager.FindEntryIndex(const AKey: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].Key, AKey) then
      Exit(I);
  Result := -1;
end;

function TCastleLocalizationManager.FindComponentPropertyEntryIndex(
  const ACompName, APropName: String): Integer;
var
  I: Integer;
begin
  if ACompName = '' then
    Exit(-1);
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].ComponentName, ACompName) and
       SameText(FEntries[I].PropertyName, APropName) then
      Exit(I);
  Result := -1;
end;

function TCastleLocalizationManager.HasComponentPropertyBinding(
  const ACompName, APropName: String): Boolean;
begin
  Result := FindComponentPropertyEntryIndex(ACompName, APropName) >= 0;
end;

procedure TCastleLocalizationManager.SetTranslation(
  const AKey, ALocale, AValue: String;
  const AComponentName: String;
  const APropertyName: String);
var
  Idx, VIdx: Integer;
  NormLoc, PropToUse: String;
begin
  if Trim(AKey) = '' then
    Exit;
  NormLoc := NormalizeLocaleCode(ALocale);
  if Trim(APropertyName) <> '' then
    PropToUse := Trim(APropertyName)
  else
    PropToUse := 'Caption';

  Idx := FindEntryIndex(AKey);
  if Idx < 0 then
  begin
    Idx := Length(FEntries);
    SetLength(FEntries, Idx + 1);
    FEntries[Idx].Key := Trim(AKey);
    FEntries[Idx].ComponentName := Trim(AComponentName);
    FEntries[Idx].PropertyName := PropToUse;
    SetLength(FEntries[Idx].Values, 0);
  end else
  begin
    if (Trim(AComponentName) <> '') and (FEntries[Idx].ComponentName = '') then
      FEntries[Idx].ComponentName := Trim(AComponentName);
    if (Trim(APropertyName) <> '') and (FEntries[Idx].PropertyName = '') then
      FEntries[Idx].PropertyName := PropToUse;
  end;

  for VIdx := 0 to High(FEntries[Idx].Values) do
    if SameText(FEntries[Idx].Values[VIdx].Locale, NormLoc) then
    begin
      FEntries[Idx].Values[VIdx].Value := AValue;
      Exit;
    end;

  VIdx := Length(FEntries[Idx].Values);
  SetLength(FEntries[Idx].Values, VIdx + 1);
  FEntries[Idx].Values[VIdx].Locale := NormLoc;
  FEntries[Idx].Values[VIdx].Value := AValue;
end;

function TCastleLocalizationManager.GetExactTranslation(
  const AKey, ALocale: String; out OutFoundExact: Boolean): String;
var
  Idx, VIdx: Integer;
  NormLoc: String;
begin
  OutFoundExact := false;
  Result := '';
  Idx := FindEntryIndex(AKey);
  if Idx < 0 then
    Exit;
  NormLoc := NormalizeLocaleCode(ALocale);
  for VIdx := 0 to High(FEntries[Idx].Values) do
    if SameText(FEntries[Idx].Values[VIdx].Locale, NormLoc) and
       (FEntries[Idx].Values[VIdx].Value <> '') then
    begin
      OutFoundExact := true;
      Exit(FEntries[Idx].Values[VIdx].Value);
    end;
end;

function TCastleLocalizationManager.ResolveTranslation(
  const AKey, ALocale: String; out OutUsedFallback: Boolean): String;
var
  NormLoc, BaseText: String;
  FoundExact, FoundFallback: Boolean;
begin
  OutUsedFallback := false;
  NormLoc := NormalizeLocaleCode(ALocale);

  if SameText(NormLoc, PseudoLocaleCode) then
  begin
    BaseText := GetExactTranslation(AKey, FFallbackLocale, FoundFallback);
    if not FoundFallback then
      BaseText := AKey;
    Exit(GeneratePseudoLocalizedText(BaseText));
  end;

  Result := GetExactTranslation(AKey, NormLoc, FoundExact);
  if FoundExact then
    Exit;

  if not SameText(NormLoc, FFallbackLocale) then
  begin
    Result := GetExactTranslation(AKey, FFallbackLocale, FoundFallback);
    if FoundFallback then
    begin
      OutUsedFallback := true;
      Exit;
    end;
  end;

  OutUsedFallback := true;
  Result := '[MISSING:' + AKey + ']';
end;

class function TCastleLocalizationManager.GeneratePseudoLocalizedText(
  const ASourceText: String; const AExpansionRatio: Single): String;

  function AccentChar(const Ch: Char): String;
  begin
    case Ch of
      'a': Result := 'á';
      'e': Result := 'ë';
      'i': Result := 'î';
      'o': Result := 'ö';
      'u': Result := 'ü';
      'y': Result := 'ÿ';
      'c': Result := 'ç';
      'n': Result := 'ñ';
      's': Result := 'š';
      'z': Result := 'ž';
      'A': Result := 'Å';
      'E': Result := 'Ë';
      'I': Result := 'Î';
      'O': Result := 'Ö';
      'U': Result := 'Ü';
      'C': Result := 'Ç';
      'N': Result := 'Ñ';
      'S': Result := 'Š';
      else Result := Ch;
    end;
  end;

var
  I, Len, VisibleCount, PadChars: Integer;
  Transformed, PadStr: String;
begin
  if ASourceText = '' then
    Exit('');

  Transformed := '';
  VisibleCount := 0;
  Len := Length(ASourceText);
  I := 1;
  while I <= Len do
  begin
    // Preserve {0}, {player_name} brace placeholders
    if ASourceText[I] = '{' then
    begin
      while (I <= Len) and (ASourceText[I] <> '}') do
      begin
        Transformed := Transformed + ASourceText[I];
        Inc(I);
      end;
      if (I <= Len) and (ASourceText[I] = '}') then
      begin
        Transformed := Transformed + '}';
        Inc(I);
      end;
      Continue;
    end;

    { Preserve %s, %d, %.2f printf placeholders }
    if (ASourceText[I] = '%') and (I < Len) and
       CharInSet(ASourceText[I + 1], ['s', 'd', 'f', 'u', 'x', '0'..'9', '.']) then
    begin
      Transformed := Transformed + ASourceText[I];
      Inc(I);
      while (I <= Len) and CharInSet(ASourceText[I], ['0'..'9', '.']) do
      begin
        Transformed := Transformed + ASourceText[I];
        Inc(I);
      end;
      if I <= Len then
      begin
        Transformed := Transformed + ASourceText[I];
        Inc(I);
      end;
      Continue;
    end;

    Transformed := Transformed + AccentChar(ASourceText[I]);
    Inc(VisibleCount);
    Inc(I);
  end;

  PadChars := Max(0, Round(VisibleCount * Clamped(AExpansionRatio, 0.0, 2.0)) - 6);
  PadStr := '';
  if PadChars > 0 then
    PadStr := ' ' + DupeString('~', PadChars);

  Result := '[!! ' + Transformed + PadStr + ' !!]';
end;

function TCastleLocalizationManager.GetTableDataJson: String;
var
  Arr, EntryObj, TransObj: TJSONData;
  RootArr: TJSONArray;
  ItemObj, MapObj: TJSONObject;
  I, J: Integer;
begin
  if Length(FEntries) = 0 then
    Exit('');

  RootArr := TJSONArray.Create;
  try
    for I := 0 to High(FEntries) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('key', FEntries[I].Key);
      if FEntries[I].ComponentName <> '' then
        ItemObj.Add('component', FEntries[I].ComponentName);
      if FEntries[I].PropertyName <> '' then
        ItemObj.Add('property', FEntries[I].PropertyName);
      MapObj := TJSONObject.Create;
      for J := 0 to High(FEntries[I].Values) do
        MapObj.Add(FEntries[I].Values[J].Locale, FEntries[I].Values[J].Value);
      ItemObj.Add('translations', MapObj);
      RootArr.Add(ItemObj);
    end;
    Result := RootArr.AsJSON;
  finally
    Arr := RootArr;
    EntryObj := nil;
    TransObj := nil;
    if EntryObj <> nil then ;
    if TransObj <> nil then ;
    FreeAndNil(Arr);
  end;
end;

procedure TCastleLocalizationManager.SetTableDataJson(const AValue: String);
var
  Parsed: TJSONData;
  Arr: TJSONArray;
  ItemObj, MapObj: TJSONObject;
  I, J: Integer;
  K, Comp, Prop: String;
begin
  ClearEntries;
  if Trim(AValue) = '' then
    Exit;

  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;

  try
    if not (Parsed is TJSONArray) then
      Exit;
    Arr := TJSONArray(Parsed);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        ItemObj := TJSONObject(Arr.Items[I]);
        K := ItemObj.Get('key', '');
        Comp := ItemObj.Get('component', '');
        Prop := ItemObj.Get('property', 'Caption');
        MapObj := ItemObj.Find('translations', jtObject) as TJSONObject;
        if (K <> '') and (MapObj <> nil) then
          for J := 0 to MapObj.Count - 1 do
            SetTranslation(K, MapObj.Names[J], MapObj.Items[J].AsString, Comp, Prop);
      end;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleLocalizationManager.CollectKnownLocales: TStringList;
var
  I, J: Integer;
  Loc: String;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := false;
  Result.Add(FFallbackLocale);
  for I := 0 to High(FEntries) do
    for J := 0 to High(FEntries[I].Values) do
    begin
      Loc := NormalizeLocaleCode(FEntries[I].Values[J].Locale);
      if Result.IndexOf(Loc) < 0 then
        Result.Add(Loc);
    end;
end;

function TCastleLocalizationManager.ExportCsv: String;
var
  Locales: TStringList;
  SB: TStringBuilder;
  I, L: Integer;
  Found: Boolean;
  HeaderLine, RowLine, Val: String;
begin
  Locales := CollectKnownLocales;
  SB := TStringBuilder.Create;
  try
    HeaderLine := 'Key,Component,Property';
    for L := 0 to Locales.Count - 1 do
      HeaderLine := HeaderLine + ',' + CsvEscapeCell(Locales[L]);
    SB.AppendLine(HeaderLine);

    for I := 0 to High(FEntries) do
    begin
      RowLine := CsvEscapeCell(FEntries[I].Key) + ',' +
                 CsvEscapeCell(FEntries[I].ComponentName) + ',' +
                 CsvEscapeCell(FEntries[I].PropertyName);
      for L := 0 to Locales.Count - 1 do
      begin
        Val := GetExactTranslation(FEntries[I].Key, Locales[L], Found);
        RowLine := RowLine + ',' + CsvEscapeCell(Val);
      end;
      SB.AppendLine(RowLine);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Locales);
  end;
end;

function TCastleLocalizationManager.ImportCsv(const ACsvText: String): Integer;
var
  Lines, HeaderCells, RowCells: TStringList;
  R, C: Integer;
  KeyStr, CompStr, PropStr, LocCode, CellVal: String;
begin
  Result := 0;
  if Trim(ACsvText) = '' then
    Exit;

  Lines := TStringList.Create;
  HeaderCells := TStringList.Create;
  RowCells := TStringList.Create;
  try
    Lines.Text := ACsvText;
    if Lines.Count < 2 then
      Exit;
    ParseCsvLineCells(Lines[0], HeaderCells);
    if HeaderCells.Count < 4 then
      Exit;

    for R := 1 to Lines.Count - 1 do
    begin
      if Trim(Lines[R]) = '' then
        Continue;
      ParseCsvLineCells(Lines[R], RowCells);
      if RowCells.Count < 3 then
        Continue;
      KeyStr := Trim(RowCells[0]);
      if KeyStr = '' then
        Continue;
      CompStr := Trim(RowCells[1]);
      PropStr := Trim(RowCells[2]);
      for C := 3 to Min(HeaderCells.Count, RowCells.Count) - 1 do
      begin
        LocCode := NormalizeLocaleCode(HeaderCells[C]);
        CellVal := RowCells[C];
        if CellVal <> '' then
          SetTranslation(KeyStr, LocCode, CellVal, CompStr, PropStr);
      end;
      Inc(Result);
    end;
  finally
    FreeAndNil(RowCells);
    FreeAndNil(HeaderCells);
    FreeAndNil(Lines);
  end;
end;

procedure TCastleLocalizationManager.ApplyTranslateCallback(
  const ASender: TCastleComponent; const APropertyName: String;
  var APropertyValue: String);
var
  Idx: Integer;
  UsedFb: Boolean;
begin
  if (ASender = nil) or (ASender.Name = '') then
    Exit;
  Idx := FindComponentPropertyEntryIndex(ASender.Name, APropertyName);
  if Idx < 0 then
    Idx := FindEntryIndex('ui.' + ASender.Name + '.' + APropertyName);
  if Idx >= 0 then
  begin
    APropertyValue := ResolveTranslation(FEntries[Idx].Key, FApplyTargetLocale, UsedFb);
    Inc(FAppliedPropertyCount);
  end;
end;

function TCastleLocalizationManager.ApplyLocaleToHierarchy(
  const ARoot: TComponent; const ALocale: String): Integer;
var
  Visited: array of TComponent;

  function MarkSeen(const C: TComponent): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(Visited) do
      if Visited[K] = C then
        Exit(false);
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := C;
    Result := true;
  end;

  procedure ApplyStringPropertySafe(const ATarget: TComponent;
    const APropName, ANewVal: String);
  var
    PI: PPropInfo;
  begin
    if (ATarget = nil) or (APropName = '') then
      Exit;
    PI := GetPropInfo(ATarget.ClassInfo, APropName);
    if (PI <> nil) and (PI^.PropType^.Kind in [tkSString, tkLString, tkAString, tkUString]) then
    begin
      SetStrProp(ATarget, PI, ANewVal);
      Inc(FAppliedPropertyCount);
    end;
  end;

  procedure WalkTransformsAndBehaviors(const C: TComponent);
  var
    I, Idx: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
    Beh: TCastleLocalizedBehavior;
    UsedFb: Boolean;
    Resolved: String;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) or (not MarkSeen(C)) then
      Exit;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      Beh := T.FindBehavior(TCastleLocalizedBehavior) as TCastleLocalizedBehavior;
      if (Beh <> nil) and (Beh.TranslationKey <> '') then
      begin
        Resolved := ResolveTranslation(Beh.TranslationKey, FApplyTargetLocale, UsedFb);
        ApplyStringPropertySafe(T, Beh.TargetProperty, Resolved);
      end else
      if T.Name <> '' then
      begin
        Idx := FindComponentPropertyEntryIndex(T.Name, 'Caption');
        if Idx >= 0 then
        begin
          Resolved := ResolveTranslation(FEntries[Idx].Key, FApplyTargetLocale, UsedFb);
          ApplyStringPropertySafe(T, FEntries[Idx].PropertyName, Resolved);
        end;
      end;

      for I := 0 to T.Count - 1 do
        WalkTransformsAndBehaviors(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      if C is TCastleViewport then
      begin
        VP := TCastleViewport(C);
        if VP.Items <> nil then
          WalkTransformsAndBehaviors(VP.Items);
      end;
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        WalkTransformsAndBehaviors(UI.Controls[I]);
    end;
  end;

begin
  Result := 0;
  if ARoot = nil then
    Exit;

  if Trim(ALocale) <> '' then
    FActiveLocale := NormalizeLocaleCode(ALocale);
  FApplyTargetLocale := FActiveLocale;
  FAppliedPropertyCount := 0;
  CastleClassUtils.TranslateProperties(ARoot, @ApplyTranslateCallback);
  SetLength(Visited, 0);
  WalkTransformsAndBehaviors(ARoot);
  Result := FAppliedPropertyCount;
end;

function TCastleLocalizationManager.LocalizationSummaryBadge: String;
begin
  Result := Format('[i18n:%s %d keys]', [FActiveLocale, Length(FEntries)]);
end;

{ TCastleLocalizedBehavior --------------------------------------------------- }

constructor TCastleLocalizedBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTranslationKey := '';
  FTargetProperty := 'Caption';
end;

function TCastleLocalizedBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, ['TranslationKey', 'TargetProperty']) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleLocalizedBehavior.LocalizedSummaryBadge: String;
begin
  if FTranslationKey <> '' then
    Result := Format('[L10n:%s]', [FTranslationKey])
  else
    Result := '[L10n:unbound]';
end;

initialization
  RegisterSerializableComponent(TCastleLocalizationManager, 'Localization Manager (i18n)');
  RegisterSerializableComponent(TCastleLocalizedBehavior, ['Localization', 'Localized Property Binder']);
end.
