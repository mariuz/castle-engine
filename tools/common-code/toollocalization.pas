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

{ Design-time UI & 3D string extractor, missing-translation & fixed-width label/
  button overflow auditor, and Markdown localization reporter for
  @link(TCastleLocalizationManager) (Phase 294). }
unit ToolLocalization;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleLocalizationTable;

type
  TLocalizationIssueKind = (
    likMissingTranslation,
    likPotentialOverflow
  );

  TLocalizationAuditIssue = record
    Kind: TLocalizationIssueKind;
    Key: String;
    Locale: String;
    ComponentName: String;
    Message: String;
  end;
  TLocalizationAuditIssueArray = array of TLocalizationAuditIssue;

  TLocalizationAuditReport = record
    Manager: TCastleLocalizationManager;
    EntryCount: Integer;
    MissingTranslationCount: Integer;
    OverflowWarningCount: Integer;
    Issues: TLocalizationAuditIssueArray;
  end;

  TLocalizationHelper = class
  public
    { Find existing @link(TCastleLocalizationManager) in @code(ARoot) or create
      one in @code(ARoot)'s non-visual components. }
    class function FindManagerInDesign(const ARoot: TComponent): TCastleLocalizationManager;
    class function EnsureManagerInDesign(const ARoot, ADesignOwner: TComponent): TCastleLocalizationManager;

    { Walk @code(ARoot) (both 2D @code(TCastleUserInterface) controls via
      @code(TranslateProperties) and 3D @code(TCastleTransform) /
      @link(TCastleLocalizedBehavior) nodes) and populate missing source keys
      into @code(AManager.FallbackLocale). Returns number of newly added keys. }
    class function ExtractTranslatableStringsFromHierarchy(
      const ARoot: TComponent;
      const AManager: TCastleLocalizationManager): Integer;

    { Audit @code(ARoot)'s localization table across @code(ATargetLocales)
      for missing translations AND fixed-width UI control text overflow
      (including @code('pseudo') stress expansion). }
    class function AuditHierarchyLocalization(
      const ARoot: TComponent;
      const ATargetLocales: array of String): TLocalizationAuditReport;

    { Format a Markdown localization coverage & overflow audit report. }
    class function FormatLocalizationMarkdown(
      const ARoot: TComponent;
      const ATargetLocales: array of String): String;
  end;

implementation

uses
  Math, StrUtils, TypInfo,
  CastleClassUtils, CastleUIControls, CastleControls, CastleTransform, CastleViewport;

function ProposeUniqueL10nName(const AOwner: TComponent;
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

type
  TExtractorCollector = class
  public
    Manager: TCastleLocalizationManager;
    AddedCount: Integer;
    procedure OnTranslateProp(const ASender: TCastleComponent;
      const APropertyName: String; var APropertyValue: String);
  end;

procedure TExtractorCollector.OnTranslateProp(const ASender: TCastleComponent;
  const APropertyName: String; var APropertyValue: String);
var
  KeyName: String;
  FoundExact: Boolean;
begin
  if (ASender = nil) or (ASender.Name = '') or (Trim(APropertyValue) = '') then
    Exit;
  { Skip previously applied pseudo-localized or missing-placeholder strings }
  if StartsStr('[!! ', APropertyValue) or StartsStr('[MISSING:', APropertyValue) then
    Exit;

  KeyName := 'ui.' + ASender.Name + '.' + APropertyName;
  if Manager.HasComponentPropertyBinding(ASender.Name, APropertyName) then
    Exit;
  Manager.GetExactTranslation(KeyName, Manager.FallbackLocale, FoundExact);
  if not FoundExact then
  begin
    Manager.SetTranslation(KeyName, Manager.FallbackLocale, APropertyValue,
      ASender.Name, APropertyName);
    Inc(AddedCount);
  end;
end;

function FindNamedComponentInHierarchy(const ARoot: TComponent;
  const AName: String): TComponent;
var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  VP: TCastleViewport;
begin
  Result := nil;
  if (ARoot = nil) or (AName = '') or (csTransient in ARoot.ComponentStyle) then
    Exit;
  if SameText(ARoot.Name, AName) then
    Exit(ARoot);

  if (ARoot.Owner <> nil) then
  begin
    Result := ARoot.Owner.FindComponent(AName);
    if Result <> nil then
      Exit;
  end;

  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindNamedComponentInHierarchy(T[I], AName);
      if Result <> nil then
        Exit;
    end;
  end else
  if ARoot is TCastleUserInterface then
  begin
    if ARoot is TCastleViewport then
    begin
      VP := TCastleViewport(ARoot);
      if VP.Items <> nil then
      begin
        Result := FindNamedComponentInHierarchy(VP.Items, AName);
        if Result <> nil then
          Exit;
      end;
    end;
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindNamedComponentInHierarchy(UI.Controls[I], AName);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function EstimateFixedBoxOverflow(const AComp: TComponent;
  const ATranslatedText: String; out OutBoxWidthPx, OutEstTextWidthPx: Single): Boolean;
var
  FontPx, PadPx, AvailPx, GlyphAvgPx: Single;
  Btn: TCastleButton;
  Lbl: TCastleLabel;
begin
  Result := false;
  OutBoxWidthPx := 0.0;
  OutEstTextWidthPx := 0.0;
  if (AComp = nil) or (ATranslatedText = '') then
    Exit;

  if AComp is TCastleButton then
  begin
    Btn := TCastleButton(AComp);
    if Btn.AutoSize and Btn.AutoSizeWidth then
      Exit(false);
    if Btn.Width <= 1.0 then
      Exit(false);
    OutBoxWidthPx := Btn.Width;
    if Btn.FontSize > 1.0 then
      FontPx := Btn.FontSize
    else
      FontPx := 20.0;
    PadPx := Btn.PaddingHorizontal * 2.0;
    GlyphAvgPx := FontPx * 0.56;
    OutEstTextWidthPx := Length(ATranslatedText) * GlyphAvgPx + PadPx;
    AvailPx := Max(1.0, OutBoxWidthPx);
    Result := OutEstTextWidthPx > AvailPx;
  end else
  if AComp is TCastleLabel then
  begin
    Lbl := TCastleLabel(AComp);
    if Lbl.AutoSize then
      Exit(false);
    if Lbl.Width <= 1.0 then
      Exit(false);
    OutBoxWidthPx := Lbl.Width;
    if Lbl.FontSize > 1.0 then
      FontPx := Lbl.FontSize
    else
      FontPx := 20.0;
    GlyphAvgPx := FontPx * 0.56;
    OutEstTextWidthPx := Length(ATranslatedText) * GlyphAvgPx;
    Result := OutEstTextWidthPx > OutBoxWidthPx;
  end;
end;

{ TLocalizationHelper -------------------------------------------------------- }

class function TLocalizationHelper.FindManagerInDesign(
  const ARoot: TComponent): TCastleLocalizationManager;
var
  I: Integer;
  CC: TCastleComponent;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleLocalizationManager then
    Exit(TCastleLocalizationManager(ARoot));

  if ARoot is TCastleComponent then
  begin
    CC := TCastleComponent(ARoot);
    for I := 0 to CC.NonVisualComponentsCount - 1 do
      if CC.NonVisualComponents[I] is TCastleLocalizationManager then
        Exit(TCastleLocalizationManager(CC.NonVisualComponents[I]));
  end;

  if ARoot.Owner <> nil then
    for I := 0 to ARoot.Owner.ComponentCount - 1 do
      if ARoot.Owner.Components[I] is TCastleLocalizationManager then
        Exit(TCastleLocalizationManager(ARoot.Owner.Components[I]));
end;

class function TLocalizationHelper.EnsureManagerInDesign(
  const ARoot, ADesignOwner: TComponent): TCastleLocalizationManager;
var
  OwnerToUse: TComponent;
begin
  Result := FindManagerInDesign(ARoot);
  if Result <> nil then
    Exit;
  if ARoot = nil then
    Exit(nil);

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastleLocalizationManager.Create(OwnerToUse);
  Result.Name := ProposeUniqueL10nName(OwnerToUse, 'LocalizationManager');
  if ARoot is TCastleComponent then
    TCastleComponent(ARoot).AddNonVisualComponent(Result);
end;

class function TLocalizationHelper.ExtractTranslatableStringsFromHierarchy(
  const ARoot: TComponent;
  const AManager: TCastleLocalizationManager): Integer;
var
  Collector: TExtractorCollector;
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

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
    Beh: TCastleLocalizedBehavior;
    PI: PPropInfo;
    CurStr: String;
    FoundExact: Boolean;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) or (not MarkSeen(C)) then
      Exit;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      Beh := T.FindBehavior(TCastleLocalizedBehavior) as TCastleLocalizedBehavior;
      if (Beh <> nil) and (Beh.TranslationKey <> '') then
      begin
        PI := GetPropInfo(T.ClassInfo, Beh.TargetProperty);
        if (PI <> nil) and (PI^.PropType^.Kind in [tkSString, tkLString, tkAString, tkUString]) then
        begin
          CurStr := GetStrProp(T, PI);
          AManager.GetExactTranslation(Beh.TranslationKey, AManager.FallbackLocale, FoundExact);
          if (CurStr <> '') and (not FoundExact) then
          begin
            AManager.SetTranslation(Beh.TranslationKey, AManager.FallbackLocale,
              CurStr, T.Name, Beh.TargetProperty);
            Inc(Collector.AddedCount);
          end;
        end;
      end;

      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      if C is TCastleViewport then
      begin
        VP := TCastleViewport(C);
        if VP.Items <> nil then
          Walk(VP.Items);
      end;
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Walk(UI.Controls[I]);
    end;
  end;

begin
  Result := 0;
  if (ARoot = nil) or (AManager = nil) then
    Exit;

  Collector := TExtractorCollector.Create;
  try
    Collector.Manager := AManager;
    Collector.AddedCount := 0;
    SetLength(Visited, 0);
    Walk(ARoot);
    CastleClassUtils.TranslateProperties(ARoot, @Collector.OnTranslateProp);
    Result := Collector.AddedCount;
  finally
    FreeAndNil(Collector);
  end;
end;

class function TLocalizationHelper.AuditHierarchyLocalization(
  const ARoot: TComponent;
  const ATargetLocales: array of String): TLocalizationAuditReport;

  procedure AppendIssue(const AKind: TLocalizationIssueKind;
    const AKey, ALoc, AComp, AMsg: String);
  var
    N: Integer;
  begin
    N := Length(Result.Issues);
    SetLength(Result.Issues, N + 1);
    Result.Issues[N].Kind := AKind;
    Result.Issues[N].Key := AKey;
    Result.Issues[N].Locale := ALoc;
    Result.Issues[N].ComponentName := AComp;
    Result.Issues[N].Message := AMsg;
  end;

var
  I, L: Integer;
  Entry: TLocalizationStringEntry;
  Loc, ExactVal, PseudoVal: String;
  FoundExact, UsedFb: Boolean;
  Comp: TComponent;
  BoxW, EstW: Single;
begin
  Result := Default(TLocalizationAuditReport);
  Result.Manager := FindManagerInDesign(ARoot);
  if Result.Manager = nil then
    Exit;

  Result.EntryCount := Result.Manager.EntryCount;
  for I := 0 to Result.EntryCount - 1 do
  begin
    Entry := Result.Manager.GetEntry(I);
    Comp := FindNamedComponentInHierarchy(ARoot, Entry.ComponentName);

    for L := 0 to High(ATargetLocales) do
    begin
      Loc := LowerCase(Trim(ATargetLocales[L]));
      if Loc = '' then
        Continue;

      if SameText(Loc, TCastleLocalizationManager.PseudoLocaleCode) then
      begin
        PseudoVal := Result.Manager.ResolveTranslation(Entry.Key, Loc, UsedFb);
        if EstimateFixedBoxOverflow(Comp, PseudoVal, BoxW, EstW) then
        begin
          Inc(Result.OverflowWarningCount);
          AppendIssue(likPotentialOverflow, Entry.Key, Loc, Entry.ComponentName,
            Format('Fixed-width control "%s" (%.0f px) overflows under Pseudo-L10n (~%.0f px). Enable AutoSize or widen control.',
              [Entry.ComponentName, BoxW, EstW]));
        end;
      end else
      begin
        ExactVal := Result.Manager.GetExactTranslation(Entry.Key, Loc, FoundExact);
        if (not FoundExact) and (not SameText(Loc, Result.Manager.FallbackLocale)) then
        begin
          Inc(Result.MissingTranslationCount);
          AppendIssue(likMissingTranslation, Entry.Key, Loc, Entry.ComponentName,
            Format('Missing "%s" translation for key "%s".', [Loc, Entry.Key]));
        end else
        if FoundExact and EstimateFixedBoxOverflow(Comp, ExactVal, BoxW, EstW) then
        begin
          Inc(Result.OverflowWarningCount);
          AppendIssue(likPotentialOverflow, Entry.Key, Loc, Entry.ComponentName,
            Format('Fixed-width control "%s" (%.0f px) may clip "%s" text (~%.0f px).',
              [Entry.ComponentName, BoxW, Loc, EstW]));
        end;
      end;
    end;
  end;
end;

class function TLocalizationHelper.FormatLocalizationMarkdown(
  const ARoot: TComponent;
  const ATargetLocales: array of String): String;
var
  Rep: TLocalizationAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  Rep := AuditHierarchyLocalization(ARoot, ATargetLocales);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Localization (i18n) & Pseudo-L10n Audit Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Total Keys**: `%d` | **Missing Translations**: `%d` | **Overflow Warnings**: `%d`',
      [Rep.EntryCount, Rep.MissingTranslationCount, Rep.OverflowWarningCount]));
    SB.AppendLine;

    if Length(Rep.Issues) > 0 then
    begin
      SB.AppendLine('## Audit Findings');
      SB.AppendLine;
      for I := 0 to High(Rep.Issues) do
        SB.AppendLine(Format('- **[%s / `%s`]** `%s` — %s',
          [IfThen(Rep.Issues[I].Kind = likMissingTranslation, 'MISSING', 'OVERFLOW'),
           Rep.Issues[I].Locale, Rep.Issues[I].Key, Rep.Issues[I].Message]));
      SB.AppendLine;
    end;

    if Rep.Manager <> nil then
    begin
      SB.AppendLine('## String Table CSV Preview');
      SB.AppendLine;
      SB.AppendLine('```csv');
      SB.Append(Rep.Manager.ExportCsv);
      SB.AppendLine('```');
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
