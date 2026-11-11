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

{ Automated tests for @link(TCastleLocalizationManager),
  @link(TCastleLocalizedBehavior), and @link(TLocalizationHelper)
  (Phase 294 — UE 5.9 / 6.0 Localization Dashboard Parity). }
unit TestToolLocalization;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolLocalization = class(TCastleTestCase)
  published
    procedure TestStringExtractionLiveLocaleSwitchingJsonAndCsvRoundtrip;
    procedure TestPseudoLocalizationTokenPreservationAndOverflowAudit;
  end;

implementation

uses
  StrUtils,
  CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleTransform, CastleScene, CastleViewport,
  CastleLocalizationTable, ToolLocalization;

procedure TTestToolLocalization.TestStringExtractionLiveLocaleSwitchingJsonAndCsvRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  RootUi, ReloadRoot: TCastleUserInterface;
  Vp: TCastleViewport;
  BtnPlay: TCastleButton;
  LblTitle: TCastleLabel;
  Sign3D: TCastleText;
  LocBeh: TCastleLocalizedBehavior;
  Mgr, ReloadMgr: TCastleLocalizationManager;
  ExtractedCount, AppliedCount, ImportedRows: Integer;
  CsvText, JsonStr: String;
  FoundExact: Boolean;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';

    BtnPlay := TCastleButton.Create(DesignOwner);
    BtnPlay.Name := 'ButtonPlay';
    BtnPlay.Caption := 'Start Adventure';
    RootUi.InsertFront(BtnPlay);

    LblTitle := TCastleLabel.Create(DesignOwner);
    LblTitle.Name := 'LabelTitle';
    LblTitle.Caption := 'Castle Chronicles';
    RootUi.InsertFront(LblTitle);

    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    RootUi.InsertFront(Vp);

    Sign3D := TCastleText.Create(DesignOwner);
    Sign3D.Name := 'TavernSign';
    Sign3D.Caption := 'Dragon Inn';
    LocBeh := TCastleLocalizedBehavior.Create(DesignOwner);
    LocBeh.TranslationKey := 'world.tavern_sign';
    Sign3D.AddBehavior(LocBeh);
    Vp.Items.Add(Sign3D);

    Mgr := TLocalizationHelper.EnsureManagerInDesign(RootUi, DesignOwner);
    AssertTrue(Mgr <> nil);

    { 1. Extract 2D UI + 3D LocalizedBehavior strings }
    ExtractedCount := TLocalizationHelper.ExtractTranslatableStringsFromHierarchy(RootUi, Mgr);
    AssertEquals(3, ExtractedCount);
    AssertEquals('Start Adventure', Mgr.GetExactTranslation('ui.ButtonPlay.Caption', 'en', FoundExact));
    AssertTrue(FoundExact);
    AssertEquals('Dragon Inn', Mgr.GetExactTranslation('world.tavern_sign', 'en', FoundExact));
    AssertTrue(FoundExact);

    { 2. Author German ('de') translations for ButtonPlay and TavernSign (leave LabelTitle missing to test fallback) }
    Mgr.SetTranslation('ui.ButtonPlay.Caption', 'de', 'Abenteuer starten', 'ButtonPlay', 'Caption');
    Mgr.SetTranslation('world.tavern_sign', 'de', 'Gasthaus zum Drachen', 'TavernSign', 'Caption');

    AppliedCount := Mgr.ApplyLocaleToHierarchy(RootUi, 'de');
    AssertTrue(AppliedCount >= 3);
    AssertEquals('Abenteuer starten', BtnPlay.Caption);
    AssertEquals('Gasthaus zum Drachen', Sign3D.Caption);
    { Missing German translation on LabelTitle gracefully falls back to English ('en') }
    AssertEquals('Castle Chronicles', LblTitle.Caption);

    { 3. Switch back to 'en' }
    Mgr.ApplyLocaleToHierarchy(RootUi, 'en');
    AssertEquals('Start Adventure', BtnPlay.Caption);
    AssertEquals('Dragon Inn', Sign3D.Caption);

    { 4. CSV Export & Import roundtrip }
    CsvText := Mgr.ExportCsv;
    AssertTrue(Pos('Abenteuer starten', CsvText) > 0);
    Mgr.ClearEntries;
    AssertEquals(0, Mgr.EntryCount);
    ImportedRows := Mgr.ImportCsv(CsvText);
    AssertEquals(3, ImportedRows);
    AssertEquals('Gasthaus zum Drachen', Mgr.GetExactTranslation('world.tavern_sign', 'de', FoundExact));
    AssertTrue(FoundExact);

    { 5. ComponentToString / StringToComponent JSON roundtrip }
    JsonStr := ComponentToString(RootUi);
    ReloadRoot := StringToComponent(JsonStr, ReloadOwner) as TCastleUserInterface;
    AssertTrue(ReloadRoot <> nil);
    ReloadMgr := TLocalizationHelper.FindManagerInDesign(ReloadRoot);
    AssertTrue(ReloadMgr <> nil);
    AssertEquals(3, ReloadMgr.EntryCount);
    ReloadMgr.ApplyLocaleToHierarchy(ReloadRoot, 'de');
    AssertEquals('Abenteuer starten',
      (ReloadOwner.FindComponent('ButtonPlay') as TCastleButton).Caption);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolLocalization.TestPseudoLocalizationTokenPreservationAndOverflowAudit;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  NarrowBtn, AutoBtn: TCastleButton;
  Mgr: TCastleLocalizationManager;
  PseudoSample, MdReport: String;
  AuditRep: TLocalizationAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  try
    { 1. Verify format-placeholder preservation in GeneratePseudoLocalizedText }
    PseudoSample := TCastleLocalizationManager.GeneratePseudoLocalizedText(
      'Hello {player}, score: %d%% (%s)');
    AssertTrue(StartsText('[!! ', PseudoSample));
    AssertTrue(Pos('{player}', PseudoSample) > 0);
    AssertTrue(Pos('%d', PseudoSample) > 0);
    AssertTrue(Pos('%s', PseudoSample) > 0);
    AssertTrue(Length(PseudoSample) > Length('Hello {player}, score: %d%% (%s)'));

    { 2. Fixed-width button overflow detection vs AutoSize button safety }
    RootUi := TCastleUserInterface.Create(DesignOwner);

    NarrowBtn := TCastleButton.Create(DesignOwner);
    NarrowBtn.Name := 'NarrowFixedButton';
    NarrowBtn.AutoSize := false;
    NarrowBtn.Width := 70;
    NarrowBtn.Caption := 'Confirm Equipment Loadout';
    RootUi.InsertFront(NarrowBtn);

    AutoBtn := TCastleButton.Create(DesignOwner);
    AutoBtn.Name := 'AutoSizedButton';
    AutoBtn.AutoSize := true;
    AutoBtn.Caption := 'Back';
    RootUi.InsertFront(AutoBtn);

    Mgr := TLocalizationHelper.EnsureManagerInDesign(RootUi, DesignOwner);
    TLocalizationHelper.ExtractTranslatableStringsFromHierarchy(RootUi, Mgr);

    { Apply live pseudo-locale to hierarchy }
    Mgr.ApplyLocaleToHierarchy(RootUi, 'pseudo');
    AssertTrue(Pos('[!! ', NarrowBtn.Caption) = 1);

    { Audit against ['de', 'pseudo']:
      - 2 missing 'de' translations
      - 1 overflow warning on NarrowFixedButton (AutoSizedButton is AutoSize=true -> 0 overflow) }
    AuditRep := TLocalizationHelper.AuditHierarchyLocalization(RootUi, ['de', 'pseudo']);
    AssertEquals(2, AuditRep.MissingTranslationCount);
    AssertEquals(1, AuditRep.OverflowWarningCount);

    MdReport := TLocalizationHelper.FormatLocalizationMarkdown(RootUi, ['de', 'pseudo']);
    AssertTrue(Pos('# Castle Localization (i18n) & Pseudo-L10n Audit Report', MdReport) > 0);
    AssertTrue(Pos('NarrowFixedButton', MdReport) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolLocalization);
end.
