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

{ Interactive Smart Objects, RVO Crowd Separation & Response-Curve Utility AI
  Studio (@link(TUtilityAiForm)) featuring 1-click Village Simulation Demo,
  need urgency injection, interactive crowd/station stepping, a live Top-Down XZ
  arena + Response-Curve visualizer canvas, and Markdown export (Phase 314). }
unit FormUtilityAi;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleUtils, CastleTransform,
  CastleUtilityAi, ToolUtilityAi;

type
  TUtilityAiModifiedCallback = procedure(const AComment: String) of object;
  TUtilityAiRefreshViewportCallback = procedure of object;

  TUtilityAiForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TUtilityAiModifiedCallback;
    FOnRefreshViewport: TUtilityAiRefreshViewportCallback;

    FReport: TUtilityAiAuditReport;

    LblHeader: TLabel;
    ListStations: TListBox;
    ListAgents: TListBox;
    ListNeeds: TListBox;
    PaintArena: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function CurrentAgent: TCastleUtilityAiBehavior;
    procedure RefreshAll;
    procedure RefreshAgentNeeds;
    procedure NotifyChanged(const AComment: String);

    procedure ListAgentsClick(Sender: TObject);
    procedure BtnSpawnVillageDemoClick(Sender: TObject);
    procedure BtnSpawnCampfireClick(Sender: TObject);
    procedure BtnSpawnTavernClick(Sender: TObject);
    procedure BtnSpawnVillagerClick(Sender: TObject);
    procedure BtnDrainSelectedNeedClick(Sender: TObject);
    procedure BtnStepAiClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintArenaPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TUtilityAiModifiedCallback;
      const AOnRefreshViewport: TUtilityAiRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TUtilityAiForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TUtilityAiModifiedCallback;
  const AOnRefreshViewport: TUtilityAiRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Smart Objects, RVO Crowd Separation & Response-Curve Utility AI Studio';
  Width := 1120;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TUtilityAiForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TUtilityAiForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Utility AI & Smart Objects Studio — Response Curves, Slot Claiming & Crowd Separation';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 30, 1100, 38);
  RowTop.BevelOuter := bvNone;

  MakeBtn(RowTop, '+ Spawn Village Demo (3 Stations + 3 Agents)', 4, 4, 290, @BtnSpawnVillageDemoClick);
  MakeBtn(RowTop, '+ Campfire Station', 300, 4, 150, @BtnSpawnCampfireClick);
  MakeBtn(RowTop, '+ Tavern Table', 456, 4, 140, @BtnSpawnTavernClick);
  MakeBtn(RowTop, '+ Villager NPC', 602, 4, 140, @BtnSpawnVillagerClick);
  MakeBtn(RowTop, 'Step AI & Crowd (+0.25s)', 748, 4, 198, @BtnStepAiClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 6, 190, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 990, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 365;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Smart Object Stations:';

  ListStations := TListBox.Create(Self);
  ListStations.Parent := PanelLeft;
  ListStations.SetBounds(10, 26, 345, 136);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 170, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Utility AI Crowd Agents:';

  ListAgents := TListBox.Create(Self);
  ListAgents.Parent := PanelLeft;
  ListAgents.SetBounds(10, 190, 345, 150);
  ListAgents.OnClick := @ListAgentsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 348, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Selected Agent Needs & Action Scores:';

  ListNeeds := TListBox.Create(Self);
  ListNeeds.Parent := PanelLeft;
  ListNeeds.SetBounds(10, 368, 345, 136);

  MakeBtn(PanelLeft, 'Make Selected Need Urgent (0.10)!', 10, 512, 345, @BtnDrainSelectedNeedClick);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintArena := TPaintBox.Create(Self);
  PaintArena.Parent := PanelCenter;
  PaintArena.Align := alTop;
  PaintArena.Height := 330;
  PaintArena.OnPaint := @PaintArenaPaint;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TUtilityAiForm.CurrentAgent: TCastleUtilityAiBehavior;
var
  Idx: Integer;
begin
  Result := nil;
  if (FReport = nil) or (Length(FReport.Agents) = 0) then
    Exit;
  Idx := ListAgents.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Agents)) then
    Result := FReport.Agents[Idx];
end;

procedure TUtilityAiForm.RefreshAll;
var
  PrevAgent: TCastleUtilityAiBehavior;
  I, TargetIdx: Integer;
  ActorName: String;
begin
  PrevAgent := CurrentAgent;
  FreeAndNil(FReport);
  FReport := TUtilityAiHelper.ScanDesign(FDesignRoot, FDesignOwner);

  ListStations.Items.BeginUpdate;
  try
    ListStations.Items.Clear;
    for I := 0 to High(FReport.Stations) do
      ListStations.Items.Add(Format('%s %s',
        [FReport.Stations[I].Name, FReport.Stations[I].SmartObjectSummaryBadge]));
  finally
    ListStations.Items.EndUpdate;
  end;

  ListAgents.Items.BeginUpdate;
  try
    ListAgents.Items.Clear;
    TargetIdx := 0;
    for I := 0 to High(FReport.Agents) do
    begin
      if FReport.Agents[I].Parent <> nil then
        ActorName := FReport.Agents[I].Parent.Name
      else
        ActorName := FReport.Agents[I].Name;
      ListAgents.Items.Add(Format('%s %s',
        [ActorName, FReport.Agents[I].UtilitySummaryBadge]));
      if FReport.Agents[I] = PrevAgent then
        TargetIdx := I;
    end;
    if ListAgents.Items.Count > 0 then
      ListAgents.ItemIndex := TargetIdx;
  finally
    ListAgents.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'Utility AI & Smart Objects Studio — %d Station(s) (%d/%d Slots Occupied) | %d Agent(s)',
    [Length(FReport.Stations), FReport.OccupiedSlots,
     FReport.TotalSlots, Length(FReport.Agents)]);

  RefreshAgentNeeds;
  MemoDiag.Lines.Text := TUtilityAiHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintArena.Invalidate;
end;

procedure TUtilityAiForm.RefreshAgentNeeds;
var
  AI: TCastleUtilityAiBehavior;
  I, PrevN: Integer;
begin
  PrevN := ListNeeds.ItemIndex;
  ListNeeds.Items.BeginUpdate;
  try
    ListNeeds.Items.Clear;
    AI := CurrentAgent;
    if AI <> nil then
    begin
      for I := 0 to AI.Needs.Count - 1 do
        ListNeeds.Items.Add(Format('Need: %s = %.2f (decay %.2f/s)',
          [AI.Needs[I].NeedName, AI.Needs[I].Value, AI.Needs[I].DecayPerSec]));
      for I := 0 to AI.Actions.Count - 1 do
        ListNeeds.Items.Add(Format('Action: %s -> Score %.2f (%s)',
          [AI.Actions[I].ActionId, AI.EvaluateActionScore(I),
           UtilityCurveToString(AI.Actions[I].Curve)]));
      if ListNeeds.Items.Count > 0 then
        ListNeeds.ItemIndex := Clamped(Max(0, PrevN), 0, ListNeeds.Items.Count - 1);
    end;
  finally
    ListNeeds.Items.EndUpdate;
  end;
end;

procedure TUtilityAiForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TUtilityAiForm.ListAgentsClick(Sender: TObject);
begin
  RefreshAgentNeeds;
  PaintArena.Invalidate;
end;

procedure TUtilityAiForm.BtnSpawnVillageDemoClick(Sender: TObject);
begin
  TUtilityAiHelper.SpawnVillageSimulationDemo(FDesignRoot, FDesignOwner);
  TUtilityAiHelper.StepAllUtilityAgents(FDesignRoot, FDesignOwner, 0.15);
  NotifyChanged('Spawn Utility AI Village Simulation Demo');
end;

procedure TUtilityAiForm.BtnSpawnCampfireClick(Sender: TObject);
begin
  TUtilityAiHelper.SpawnSmartObjectInDesign(
    FDesignRoot, FDesignOwner, sopCampfireRestBench, Vector3(-4.0, 0.0, 0.0), 'CampfireRest');
  NotifyChanged('Spawn SmartObject Campfire Station');
end;

procedure TUtilityAiForm.BtnSpawnTavernClick(Sender: TObject);
begin
  TUtilityAiHelper.SpawnSmartObjectInDesign(
    FDesignRoot, FDesignOwner, sopTavernMealTable, Vector3(4.0, 0.0, 0.0), 'TavernTable');
  NotifyChanged('Spawn SmartObject Tavern Table');
end;

procedure TUtilityAiForm.BtnSpawnVillagerClick(Sender: TObject);
begin
  TUtilityAiHelper.SpawnUtilityAgentInDesign(
    FDesignRoot, FDesignOwner, uapVillagerArtisan, Vector3(0.0, 0.0, 2.0), 'VillagerNpc');
  NotifyChanged('Spawn Utility AI Villager Agent');
end;

procedure TUtilityAiForm.BtnDrainSelectedNeedClick(Sender: TObject);
var
  AI: TCastleUtilityAiBehavior;
  Idx: Integer;
begin
  AI := CurrentAgent;
  Idx := ListNeeds.ItemIndex;
  if (AI = nil) or (Idx < 0) or (Idx >= AI.Needs.Count) then
    Exit;
  AI.Needs[Idx].Value := 0.10;
  AI.StepUtilityAi(0.05);
  NotifyChanged('Drain Utility AI Need ' + AI.Needs[Idx].NeedName);
end;

procedure TUtilityAiForm.BtnStepAiClick(Sender: TObject);
begin
  TUtilityAiHelper.StepAllUtilityAgents(FDesignRoot, FDesignOwner, 0.25);
  NotifyChanged('Step Utility AI & RVO Crowd Simulation (+0.25s)');
end;

procedure TUtilityAiForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TUtilityAiHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TUtilityAiForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TUtilityAiForm.PaintArenaPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, ArenaW, CX, CY, I, SX, SY, GX, GY, PlotX, PlotW, PlotY, PlotH, PX, PY: Integer;
  ScalePx, U: Single;
  SO: TCastleSmartObject;
  AI: TCastleUtilityAiBehavior;
  P, SlotP: TVector3;
begin
  Cv := PaintArena.Canvas;
  W := PaintArena.Width;
  H := PaintArena.Height;

  Cv.Brush.Color := RGBToColor(18, 22, 30);
  Cv.FillRect(0, 0, W, H);

  { Left panel: Top-Down XZ Crowd & SmartObject Slot Map }
  ArenaW := Min(380, (W div 2) - 16);
  CX := 16 + ArenaW div 2;
  CY := 34 + (H - 50) div 2;
  ScalePx := 20.0;

  Cv.Pen.Color := RGBToColor(58, 74, 98);
  Cv.Brush.Color := RGBToColor(14, 17, 23);
  Cv.Rectangle(16, 34, 16 + ArenaW, H - 16);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := RGBToColor(220, 232, 248);
  Cv.TextOut(16, 10, 'Top-Down XZ SmartObjects & RVO Crowd Map');

  if FReport <> nil then
  begin
    for I := 0 to High(FReport.Stations) do
    begin
      SO := FReport.Stations[I];
      P := SO.Translation;
      SX := CX + Round(P.X * ScalePx);
      SY := CY + Round(P.Z * ScalePx);
      Cv.Brush.Style := bsSolid;
      Cv.Brush.Color := RGBToColor(235, 138, 52);
      Cv.Pen.Color := RGBToColor(255, 210, 120);
      Cv.Rectangle(SX - 8, SY - 8, SX + 8, SY + 8);
    end;

    for I := 0 to High(FReport.Agents) do
    begin
      AI := FReport.Agents[I];
      if AI.Parent = nil then
        Continue;
      P := AI.Parent.Translation;
      SX := CX + Round(P.X * ScalePx);
      SY := CY + Round(P.Z * ScalePx);

      if AI.ClaimedSmartObject <> nil then
      begin
        SlotP := AI.ClaimedSmartObject.GetSlotWorldPos(AI.ClaimedSlotIndex);
        GX := CX + Round(SlotP.X * ScalePx);
        GY := CY + Round(SlotP.Z * ScalePx);
        Cv.Pen.Color := RGBToColor(78, 212, 148);
        Cv.Line(SX, SY, GX, GY);
      end;

      Cv.Brush.Style := bsSolid;
      Cv.Brush.Color := RGBToColor(78, 178, 248);
      Cv.Pen.Color := clWhite;
      Cv.Ellipse(SX - 6, SY - 6, SX + 6, SY + 6);
    end;
  end;

  { Right panel: Utility Response Curves (Linear, Quadratic, Logistic) }
  PlotX := ArenaW + 38;
  PlotW := Max(120, W - PlotX - 20);
  PlotY := 38;
  PlotH := H - 64;

  Cv.Brush.Style := bsSolid;
  Cv.Brush.Color := RGBToColor(14, 17, 23);
  Cv.Pen.Color := RGBToColor(58, 74, 98);
  Cv.Rectangle(PlotX, PlotY, PlotX + PlotW, PlotY + PlotH);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := RGBToColor(220, 232, 248);
  Cv.TextOut(PlotX, 10, 'Utility Response Curves (Linear / Quadratic / Logistic)');

  { Quadratic Urgency }
  Cv.Pen.Color := RGBToColor(245, 118, 92);
  for I := 0 to PlotW do
  begin
    U := I / PlotW;
    PX := PlotX + I;
    PY := PlotY + PlotH - Round(EvaluateUtilityCurve(U, urcQuadraticUrgency, 2.0) * PlotH);
    if I = 0 then Cv.MoveTo(PX, PY) else Cv.LineTo(PX, PY);
  end;

  { Logistic Sigmoid }
  Cv.Pen.Color := RGBToColor(86, 214, 152);
  for I := 0 to PlotW do
  begin
    U := I / PlotW;
    PX := PlotX + I;
    PY := PlotY + PlotH - Round(EvaluateUtilityCurve(U, urcLogisticSigmoid, 2.0) * PlotH);
    if I = 0 then Cv.MoveTo(PX, PY) else Cv.LineTo(PX, PY);
  end;
end;

end.
