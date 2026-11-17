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

{ Interactive StateTree Hierarchical AI Decision Tree, Spatial Evaluators,
  Ancestor Preemption & Mermaid Studio dialog (Phase 337). }
unit FormStateTree;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Dialogs,
  CastleVectors, CastleTransform,
  CastleStateTree, ToolStateTree;

type
  TStateTreeModifyCallback = procedure(const AUndoComment: String) of object;
  TStateTreeRefreshCallback = procedure of object;

  TStateTreeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TStateTreeModifyCallback;
    FOnRefreshViewport: TStateTreeRefreshCallback;

    LabelHeader: TLabel;
    LabelTelemetry: TLabel;
    PaintTree: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshUi;
    procedure NotifyChange(const AComment: String);
    procedure MoveIntruderAndStep(const AZ, AHealth: Single; const AComment: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnFarPatrolClick(Sender: TObject);
    procedure BtnMidRangedClick(Sender: TObject);
    procedure BtnCloseMeleeClick(Sender: TObject);
    procedure BtnCritFleeClick(Sender: TObject);
    procedure BtnTickStepClick(Sender: TObject);
    procedure BtnCyclePresetClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure PaintTreePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TStateTreeModifyCallback;
      const AOnRefreshViewport: TStateTreeRefreshCallback);
  end;

implementation

constructor TStateTreeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TStateTreeModifyCallback;
  const AOnRefreshViewport: TStateTreeRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'StateTree Hierarchical AI, Evaluators & Ancestor Preemption Studio (UE 6.0+ StateTree Parity)';
  Width := 1020;
  Height := 650;
  Position := poMainFormCenter;

  BuildUi;
  RefreshUi;
end;

procedure TStateTreeForm.BuildUi;
var
  TopBar, BtnRow1, BtnRow2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const AOnClick: TNotifyEvent; const AWidth: Integer = 152): TButton;
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
  TopBar.Height := 126;
  TopBar.BevelOuter := bvNone;

  LabelHeader := TLabel.Create(Self);
  LabelHeader.Parent := TopBar;
  LabelHeader.Align := alTop;
  LabelHeader.BorderSpacing.Around := 6;
  LabelHeader.Font.Style := [fsBold];
  LabelHeader.Caption := 'StateTree Hierarchical AI — Nested Selector Paths, Spatial Evaluators, Root-to-Leaf Preemption & Mermaid Export';

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
  MakeBtn(BtnRow1, '+ Spawn Guard + Intruder', @BtnSpawnDemoClick, 178);
  MakeBtn(BtnRow1, 'Intruder Far (22m: Patrol)', @BtnFarPatrolClick, 175);
  MakeBtn(BtnRow1, 'Intruder Mid (9m: Ranged)', @BtnMidRangedClick, 175);
  MakeBtn(BtnRow1, 'Intruder Close (2m: Melee)', @BtnCloseMeleeClick, 180);
  MakeBtn(BtnRow1, 'Critical HP (15%: Flee!)', @BtnCritFleeClick, 175);

  BtnRow2 := TPanel.Create(Self);
  BtnRow2.Parent := TopBar;
  BtnRow2.Align := alTop;
  BtnRow2.Height := 38;
  BtnRow2.BevelOuter := bvNone;
  MakeBtn(BtnRow2, 'Tick +0.50s', @BtnTickStepClick, 120);
  MakeBtn(BtnRow2, 'Cycle AI Preset', @BtnCyclePresetClick, 145);
  MakeBtn(BtnRow2, 'Export Report / Mermaid...', @BtnExportClick, 185);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := BodyPanel;
  MemoReport.Align := alLeft;
  MemoReport.Width := 380;
  MemoReport.BorderSpacing.Around := 6;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssVertical;

  PaintTree := TPaintBox.Create(Self);
  PaintTree.Parent := BodyPanel;
  PaintTree.Align := alClient;
  PaintTree.BorderSpacing.Around := 6;
  PaintTree.OnPaint := @PaintTreePaint;
end;

procedure TStateTreeForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshUi;
end;

procedure TStateTreeForm.RefreshUi;
var
  ST: TCastleStateTreeBehavior;
begin
  ST := TStateTreeHelper.FindFirstStateTree(FDesignRoot);
  if ST <> nil then
    LabelTelemetry.Caption := Format(
      '%s (%s) | Active Path: %s | Task: %s | Dist=%.1fm HP=%.0f%% | Transitions: %d',
      [ST.Name, StateTreePresetToDisplayName(ST.Preset), ST.ActiveStatePath,
       ST.ActiveTaskAction, ST.GetParam('ThreatDistance', 0.0),
       ST.GetParam('HealthRatio', 1.0) * 100.0, ST.TransitionCount])
  else
    LabelTelemetry.Caption := 'No TCastleStateTreeBehavior in design — click "+ Spawn Guard + Intruder" to create a demo rig.';

  MemoReport.Lines.Text := TStateTreeHelper.BuildMarkdownReport(FDesignRoot);
  PaintTree.Invalidate;
end;

procedure TStateTreeForm.MoveIntruderAndStep(const AZ, AHealth: Single;
  const AComment: String);
var
  ST: TCastleStateTreeBehavior;
  TargetComp: TComponent;
begin
  ST := TStateTreeHelper.FindFirstStateTree(FDesignRoot);
  if ST = nil then Exit;
  if (FDesignOwner <> nil) and (ST.TargetTransformName <> '') then
  begin
    TargetComp := FDesignOwner.FindComponent(ST.TargetTransformName);
    if TargetComp is TCastleTransform then
      TCastleTransform(TargetComp).Translation := Vector3(0.0, 0.9, AZ);
  end;
  ST.SetParam('HealthRatio', AHealth);
  ST.StepTree(0.05);
  NotifyChange(AComment);
end;

procedure TStateTreeForm.BtnSpawnDemoClick(Sender: TObject);
var
  Guard, Intruder: TCastleTransform;
  ST: TCastleStateTreeBehavior;
begin
  if TStateTreeHelper.SpawnTacticalGuardStateTreeDemo(FDesignRoot, FDesignOwner, Guard, Intruder, ST) then
    NotifyChange('Spawn StateTree Tactical Guard');
end;

procedure TStateTreeForm.BtnFarPatrolClick(Sender: TObject);
begin
  MoveIntruderAndStep(22.0, 1.0, 'StateTree Patrol Context');
end;

procedure TStateTreeForm.BtnMidRangedClick(Sender: TObject);
begin
  MoveIntruderAndStep(9.0, 1.0, 'StateTree Ranged Combat');
end;

procedure TStateTreeForm.BtnCloseMeleeClick(Sender: TObject);
begin
  MoveIntruderAndStep(2.0, 1.0, 'StateTree Melee Combat');
end;

procedure TStateTreeForm.BtnCritFleeClick(Sender: TObject);
begin
  MoveIntruderAndStep(2.0, 0.15, 'StateTree Critical HP Preemption');
end;

procedure TStateTreeForm.BtnTickStepClick(Sender: TObject);
var
  ST: TCastleStateTreeBehavior;
begin
  ST := TStateTreeHelper.FindFirstStateTree(FDesignRoot);
  if ST = nil then Exit;
  ST.StepTree(0.50);
  NotifyChange('Tick StateTree +0.50s');
end;

procedure TStateTreeForm.BtnCyclePresetClick(Sender: TObject);
var
  ST: TCastleStateTreeBehavior;
begin
  ST := TStateTreeHelper.FindFirstStateTree(FDesignRoot);
  if ST = nil then Exit;
  case ST.Preset of
    stpTacticalGuardSquad:    ST.Preset := stpBossPhaseController;
    stpBossPhaseController:   ST.Preset := stpCompanionUtilityMedic;
    stpCompanionUtilityMedic: ST.Preset := stpTacticalGuardSquad;
  end;
  NotifyChange('Cycle StateTree Preset');
end;

procedure TStateTreeForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  SL: TStringList;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Filter := 'Markdown Report (*.md)|*.md';
    Dlg.DefaultExt := 'md';
    Dlg.FileName := 'statetree_ai_report.md';
    if Dlg.Execute then
    begin
      SL := TStringList.Create;
      try
        SL.Text := TStateTreeHelper.BuildMarkdownReport(FDesignRoot);
        SL.SaveToFile(Dlg.FileName);
      finally
        FreeAndNil(SL);
      end;
    end;
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TStateTreeForm.PaintTreePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Depth, CurIdx, RowY, BoxX, BoxW, BoxH: Integer;
  ST: TCastleStateTreeBehavior;
  N: TStateTreeNode;
  IsActive: Boolean;
begin
  Cv := PaintTree.Canvas;
  W := Max(120, PaintTree.Width);
  H := Max(120, PaintTree.Height);
  Cv.Brush.Color := RGBToColor(18, 22, 28);
  Cv.FillRect(0, 0, W, H);

  ST := TStateTreeHelper.FindFirstStateTree(FDesignRoot);
  if ST <> nil then
  begin
    BoxH := 34;
    for I := 0 to ST.NodeCount - 1 do
    begin
      N := ST.GetNode(I);
      Depth := 0;
      CurIdx := N.ParentIndex;
      while (CurIdx >= 0) and (Depth < 8) do
      begin
        Inc(Depth);
        CurIdx := ST.GetNode(CurIdx).ParentIndex;
      end;

      IsActive := ST.IsNodeInActivePath(I);
      BoxX := 20 + Depth * 52;
      RowY := 36 + I * (BoxH + 8);
      BoxW := Max(180, W - BoxX - 24);

      if IsActive then
      begin
        Cv.Brush.Color := RGBToColor(44, 118, 72);
        Cv.Pen.Color := RGBToColor(135, 245, 165);
      end else
      begin
        Cv.Brush.Color := RGBToColor(38, 46, 58);
        Cv.Pen.Color := RGBToColor(90, 106, 128);
      end;
      Cv.Rectangle(BoxX, RowY, BoxX + BoxW, RowY + BoxH);

      Cv.Brush.Style := bsClear;
      Cv.Font.Color := clWhite;
      if N.TaskAction <> '' then
        Cv.TextOut(BoxX + 8, RowY + 8, Format('%s  ->  [%s]', [N.Name, N.TaskAction]))
      else
        Cv.TextOut(BoxX + 8, RowY + 8, Format('%s  (Selector)', [N.Name]));
      Cv.Brush.Style := bsSolid;
    end;
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(14, 8, 'Hierarchical StateTree Lineage (Emerald = Active Ancestors & Active Leaf Task)');
end;

end.
