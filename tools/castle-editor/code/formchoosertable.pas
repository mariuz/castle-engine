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

{ Interactive Chooser Tables Context-Driven Multi-Column Asset, Montage, Audio
  & VFX Selector Studio dialog (Phase 347). }
unit FormChooserTable;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, StrUtils,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleChooserTable, ToolChooserTable;

type
  TChooserModifyCallback = procedure(const AUndoComment: String) of object;
  TChooserRefreshCallback = procedure of object;

  TChooserTableForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TChooserModifyCallback;
    FOnRefreshViewport: TChooserRefreshCallback;
    FLastQuery: TChooserContextQuery;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintMatrix: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    function EnsureTable: TCastleChooserTable;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnQueryStoneSprintClick(Sender: TObject);
    procedure BtnQueryMudSneakClick(Sender: TObject);
    procedure BtnPresetMeleeClick(Sender: TObject);
    procedure BtnPresetAiBarksClick(Sender: TObject);
    procedure BtnRollWeightedBarkClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintMatrixPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TChooserModifyCallback;
      const AOnRefreshViewport: TChooserRefreshCallback);
  end;

implementation

constructor TChooserTableForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TChooserModifyCallback;
  const AOnRefreshViewport: TChooserRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FLastQuery := TChooserContextQuery.Create('Surface.Stone.Wet', 'Stance.Sprint', 6.2, 0.0, True);

  Caption := 'Chooser Tables Context-Driven Multi-Column Asset, Montage & Audio Studio (UE 6.0+ UChooserTable Parity)';
  Width := 1060;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TChooserTableForm.BuildUi;
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
  LabelHeader.Caption := 'Chooser Tables — Multi-Column GameplayTag, Numeric Range & Priority/Weighted Asset Resolution Without Branching Code';

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
  MakeBtn(BtnRow1, '+ Spawn Footstep Chooser', @BtnSpawnDemoClick, 184);
  MakeBtn(BtnRow1, 'Query: Stone + Sprint (6.2)', @BtnQueryStoneSprintClick, 188);
  MakeBtn(BtnRow1, 'Query: Mud + Slow (1.8)', @BtnQueryMudSneakClick, 178);
  MakeBtn(BtnRow1, 'Preset: Melee Montages', @BtnPresetMeleeClick, 174);
  MakeBtn(BtnRow1, 'Preset: AI Combat Barks', @BtnPresetAiBarksClick, 176);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Roll Weighted AI Bark', @BtnRollWeightedBarkClick, 174);
  MakeBtn(BtnRow2, 'Export Markdown Report...', @BtnExportClick, 184);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 420;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintMatrix := TPaintBox.Create(Self);
  PaintMatrix.Parent := BodyPanel;
  PaintMatrix.Align := alClient;
  PaintMatrix.BorderSpacing.Around := 6;
  PaintMatrix.OnPaint := @PaintMatrixPaint;
end;

procedure TChooserTableForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

function TChooserTableForm.EnsureTable: TCastleChooserTable;
begin
  Result := TChooserTableHelper.FindFirstChooser(FDesignRoot);
  if Result = nil then
    TChooserTableHelper.SpawnFootstepAndBarkChooserDemo(FDesignRoot, FDesignOwner, Result);
end;

procedure TChooserTableForm.RefreshUi;
var
  Warnings: TStringList;
  Sum: TChooserStudioSummary;
begin
  Warnings := TStringList.Create;
  try
    Sum := TChooserTableHelper.CollectSummary(FDesignRoot, Warnings);
    LabelTelemetry.Caption := Format(
      'Rows: %d | Evaluations: %d | Winner Row: %s -> %s | Warnings: %d',
      [Sum.TotalRows, Sum.TotalEvaluations,
       IfThen(Sum.LastMatchedRow <> '', Sum.LastMatchedRow, 'None'),
       IfThen(Sum.LastResolvedAsset <> '', Sum.LastResolvedAsset, 'None'),
       Sum.WarningsCount]);
    MemoReport.Lines.Text := TChooserTableHelper.BuildMarkdownReport(FDesignRoot);
  finally
    FreeAndNil(Warnings);
  end;
  PaintMatrix.Invalidate;
end;

procedure TChooserTableForm.BtnSpawnDemoClick(Sender: TObject);
var
  T: TCastleChooserTable;
begin
  if TChooserTableHelper.SpawnFootstepAndBarkChooserDemo(FDesignRoot, FDesignOwner, T) then
    NotifyChange('Spawn Chooser Table Demo');
end;

procedure TChooserTableForm.BtnQueryStoneSprintClick(Sender: TObject);
var
  T: TCastleChooserTable;
  Chosen: TChooserRow;
begin
  T := EnsureTable;
  if T = nil then Exit;
  T.ApplyPreset(chpFootstepSurfaceStance);
  FLastQuery := TChooserContextQuery.Create('Surface.Stone.Wet', 'Stance.Sprint', 6.2, 0.0, True);
  T.EvaluateChooser(FLastQuery, Chosen);
  NotifyChange('Evaluate Chooser: Stone Sprint');
end;

procedure TChooserTableForm.BtnQueryMudSneakClick(Sender: TObject);
var
  T: TCastleChooserTable;
  Chosen: TChooserRow;
begin
  T := EnsureTable;
  if T = nil then Exit;
  T.ApplyPreset(chpFootstepSurfaceStance);
  FLastQuery := TChooserContextQuery.Create('Surface.Mud', 'Stance.Walk', 1.8, 0.0, True);
  T.EvaluateChooser(FLastQuery, Chosen);
  NotifyChange('Evaluate Chooser: Mud Slow');
end;

procedure TChooserTableForm.BtnPresetMeleeClick(Sender: TObject);
var
  T: TCastleChooserTable;
  Chosen: TChooserRow;
begin
  T := EnsureTable;
  if T = nil then Exit;
  T.ApplyPreset(chpMeleeComboMontage);
  FLastQuery := TChooserContextQuery.Create('Weapon.Greatsword', '', 3.0, 0.0, True);
  T.EvaluateChooser(FLastQuery, Chosen);
  NotifyChange('Apply Melee Combo Chooser Preset');
end;

procedure TChooserTableForm.BtnPresetAiBarksClick(Sender: TObject);
var
  T: TCastleChooserTable;
  Chosen: TChooserRow;
begin
  T := EnsureTable;
  if T = nil then Exit;
  T.ApplyPreset(chpAiCombatBarkSelector);
  FLastQuery := TChooserContextQuery.Create('Bark.Flank', 'Alert.Combat', 12.0, 0.80, True);
  T.EvaluateChooser(FLastQuery, Chosen);
  NotifyChange('Apply AI Combat Barks Chooser Preset');
end;

procedure TChooserTableForm.BtnRollWeightedBarkClick(Sender: TObject);
var
  T: TCastleChooserTable;
  Chosen: TChooserRow;
begin
  T := EnsureTable;
  if T = nil then Exit;
  if T.Preset <> chpAiCombatBarkSelector then
    T.ApplyPreset(chpAiCombatBarkSelector);
  FLastQuery := TChooserContextQuery.Create('Bark.Flank', 'Alert.Combat', 12.0, 0.80, True);
  T.EvaluateChooser(FLastQuery, Chosen);
  NotifyChange('Roll Weighted AI Combat Bark');
end;

procedure TChooserTableForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'chooser_table_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TChooserTableHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TChooserTableForm.PaintMatrixPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y: Integer;
  T: TCastleChooserTable;
  R: TChooserRow;
  Matched, IsWinner: Boolean;
begin
  Cv := PaintMatrix.Canvas;
  W := Max(200, PaintMatrix.Width);
  H := Max(200, PaintMatrix.Height);

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 10, Format('Live Multi-Column Decision Matrix (Query: %s | %s | NumA=%.1f)', [
    FLastQuery.TagContextA, FLastQuery.TagContextB, FLastQuery.NumericParamA]));
  Cv.Font.Style := [];

  T := TChooserTableHelper.FindFirstChooser(FDesignRoot);
  if T = nil then Exit;

  Y := 40;
  for I := 0 to T.RowCount - 1 do
  begin
    R := T.GetRow(I);
    Matched := T.RowMatchesQuery(I, FLastQuery);
    IsWinner := SameText(R.RowId, T.LastMatchedRowId);

    if IsWinner then
      Cv.Brush.Color := RGBToColor(36, 138, 82)
    else if Matched then
      Cv.Brush.Color := RGBToColor(48, 88, 128)
    else
      Cv.Brush.Color := RGBToColor(32, 36, 46);

    Cv.Pen.Color := RGBToColor(78, 94, 118);
    Cv.Rectangle(16, Y, W - 16, Y + 40);

    Cv.Brush.Style := bsClear;
    Cv.Font.Color := clWhite;
    Cv.TextOut(26, Y + 11, Format('[Prio %2d | Wt %.1f]  %-22s  ->  %s', [
      R.Priority, R.Weight, R.RowId, R.ResultAssetUrl]));
    Y := Y + 48;
  end;
end;

end.
