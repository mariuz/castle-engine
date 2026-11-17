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

{ Interactive World Partition Runtime Data Layers, Scenario Visibility/Load
  States & Sub-Layer Inheritance Studio dialog (Phase 343). }
unit FormDataLayers;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleDataLayers, ToolDataLayers;

type
  TDataLayersModifyCallback = procedure(const AUndoComment: String) of object;
  TDataLayersRefreshCallback = procedure of object;

  TDataLayersForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TDataLayersModifyCallback;
    FOnRefreshViewport: TDataLayersRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintHierarchy: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure BtnSpawnFortressClick(Sender: TObject);
    procedure BtnScenarioPeaceClick(Sender: TObject);
    procedure BtnScenarioSiegeClick(Sender: TObject);
    procedure BtnScenarioRuinsClick(Sender: TObject);
    procedure BtnCycleSiegeParentClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintHierarchyPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TDataLayersModifyCallback;
      const AOnRefreshViewport: TDataLayersRefreshCallback);
  end;

implementation

constructor TDataLayersForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TDataLayersModifyCallback;
  const AOnRefreshViewport: TDataLayersRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'World Partition Runtime Data Layers & Scenario Switcher Studio (UE 6.0+ Data Layers Parity)';
  Width := 1040;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TDataLayersForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 165): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Align := alLeft;
    Result.BorderSpacing.Around := 4;
    Result.OnClick := AOnClick;
  end;

begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 128;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'World Partition Data Layers — Parent/Sub-Layer State Inheritance (Unloaded / LoadedHidden / Activated) & 1-Click World Scenarios';

  LabelTelemetry := TLabel.Create(Self);
  LabelTelemetry.Parent := TopBar;
  LabelTelemetry.Align := alTop;
  LabelTelemetry.BorderSpacing.Left := 6;
  LabelTelemetry.Caption := 'Telemetry: ready';

  BtnRow1 := TPanel.Create(Self);
  BtnRow1.Parent := TopBar;
  BtnRow1.Align := alTop;
  BtnRow1.Height := 38;
  BtnRow1.BevelOuter := bvNone;
  MakeBtn(BtnRow1, '+ Spawn Fortress Scenarios', @BtnSpawnFortressClick, 192);
  MakeBtn(BtnRow1, 'Scenario: Peacetime Town', @BtnScenarioPeaceClick, 182);
  MakeBtn(BtnRow1, 'Scenario: Active Siege', @BtnScenarioSiegeClick, 174);
  MakeBtn(BtnRow1, 'Scenario: Post-War Ruins', @BtnScenarioRuinsClick, 182);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Cycle CitySiege Parent State', @BtnCycleSiegeParentClick, 205);
  MakeBtn(BtnRow2, 'Export Markdown + Mermaid...', @BtnExportClick, 198);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 410;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintHierarchy := TPaintBox.Create(Self);
  PaintHierarchy.Parent := BodyPanel;
  PaintHierarchy.Align := alClient;
  PaintHierarchy.BorderSpacing.Around := 6;
  PaintHierarchy.OnPaint := @PaintHierarchyPaint;
end;

procedure TDataLayersForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TDataLayersForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TDataLayersStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TDataLayersHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Defined Layers: %d | Tagged Actors Activated / Hidden / Unloaded: %d / %d / %d (Total %d) | Warnings: %d',
      [Sum.DefinedLayersCount, Sum.ActivatedActorsCount, Sum.LoadedHiddenActorsCount,
       Sum.UnloadedActorsCount, Sum.TaggedActorsCount, Sum.WarningsCount]);
    MemoReport.Lines.Text := TDataLayersHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintHierarchy.Invalidate;
end;

procedure TDataLayersForm.BtnSpawnFortressClick(Sender: TObject);
var
  Mgr: TCastleDataLayerManager;
begin
  if TDataLayersHelper.SpawnFortressScenarioDataLayersDemo(FDesignRoot, FDesignOwner, Mgr) then
    NotifyChange('Spawn Fortress World Partition Data Layers');
end;

procedure TDataLayersForm.BtnScenarioPeaceClick(Sender: TObject);
begin
  if TDataLayersHelper.SwitchScenarioAndApply(FDesignRoot, dlspPeacetimeTown) then
    NotifyChange('Switch Data Layers: Peacetime Town');
end;

procedure TDataLayersForm.BtnScenarioSiegeClick(Sender: TObject);
begin
  if TDataLayersHelper.SwitchScenarioAndApply(FDesignRoot, dlspActiveSiegeBattle) then
    NotifyChange('Switch Data Layers: Active Siege Battle');
end;

procedure TDataLayersForm.BtnScenarioRuinsClick(Sender: TObject);
begin
  if TDataLayersHelper.SwitchScenarioAndApply(FDesignRoot, dlspPostWarRuins) then
    NotifyChange('Switch Data Layers: Post-War Ruins');
end;

procedure TDataLayersForm.BtnCycleSiegeParentClick(Sender: TObject);
var
  Mgr: TCastleDataLayerManager;
  RootT: TCastleTransform;
  Cur, NextState: TDataLayerRuntimeState;
begin
  Mgr := TDataLayersHelper.FindFirstManager(FDesignRoot);
  RootT := TDataLayersHelper.ResolveRootTransform(FDesignRoot);
  if (Mgr = nil) or (RootT = nil) then Exit;
  Cur := Mgr.GetLayerDesiredState('CitySiege');
  case Cur of
    dlrsUnloaded:     NextState := dlrsLoadedHidden;
    dlrsLoadedHidden: NextState := dlrsActivated;
    dlrsActivated:    NextState := dlrsUnloaded;
  end;
  Mgr.SetLayerState('CitySiege', NextState);
  Mgr.ApplyDataLayersToWorld(RootT);
  NotifyChange('Cycle CitySiege Data Layer State');
end;

procedure TDataLayersForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'world_partition_data_layers.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TDataLayersHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TDataLayersForm.PaintHierarchyPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y, IndentX: Integer;
  Mgr: TCastleDataLayerManager;
  Def: TDataLayerDefinition;
  Eff: TDataLayerRuntimeState;
begin
  Cv := PaintHierarchy.Canvas;
  W := Max(200, PaintHierarchy.Width);
  H := Max(200, PaintHierarchy.Height);

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, 'Hierarchical Data Layers (Desired vs. Inherited Effective State)');
  Cv.Font.Style := [];

  Mgr := TDataLayersHelper.FindFirstManager(FDesignRoot);
  if Mgr = nil then Exit;

  Y := 42;
  for I := 0 to Mgr.LayerCount - 1 do
  begin
    Def := Mgr.GetLayer(I);
    Eff := Mgr.EvaluateEffectiveLayerState(Def.Name);
    if Def.ParentLayerName <> '' then
      IndentX := 48
    else
      IndentX := 18;

    case Eff of
      dlrsActivated:    Cv.Brush.Color := RGBToColor(38, 128, 76);
      dlrsLoadedHidden: Cv.Brush.Color := RGBToColor(156, 118, 36);
      dlrsUnloaded:     Cv.Brush.Color := RGBToColor(46, 52, 66);
    end;
    Cv.Pen.Color := RGBToColor(88, 102, 128);
    Cv.Rectangle(IndentX, Y, W - 20, Y + 42);

    Cv.Brush.Style := bsClear;
    Cv.Font.Color := clWhite;
    Cv.TextOut(IndentX + 12, Y + 12, Format('%s  [Desired: %s -> Effective: %s]', [
      Def.Name,
      DataLayerStateToDisplayName(Def.DesiredState),
      DataLayerStateToDisplayName(Eff)]));
    Y := Y + 52;
  end;
end;

end.
