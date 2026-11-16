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

{ MassEntity-Style Data-Oriented SoA Crowd Simulation, Spatial Hash Grid,
  Dijkstra Flow-Field & 4-Tier Representation LOD Studio Dialog
  (@link(TMassEntityForm))
  (Phase 328 — UE 6.0+ MassEntity & MassCrowd Parity). }
unit FormMassEntity;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleMassEntity, ToolMassEntity;

type
  TMassEntityModifyCallback = procedure(const AUndoComment: String) of object;
  TMassEntityRefreshCallback = procedure of object;

  TMassEntityForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TMassEntityModifyCallback;
    FOnRefresh: TMassEntityRefreshCallback;

    FSwarms: TMassSwarmArray;

    LblHeader: TLabel;
    ListSwarms: TListBox;
    LblDetails: TLabel;
    PaintArena: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromDesign;
    function SelectedSwarm: TCastleMassEntityManager;
    procedure NotifyModified(const AComment: String);

    procedure ListSwarmsClick(Sender: TObject);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnPresetCityClick(Sender: TObject);
    procedure BtnPresetBoidsClick(Sender: TObject);
    procedure BtnPresetSiegeClick(Sender: TObject);
    procedure BtnCycleGoalClick(Sender: TObject);
    procedure BtnStep50msClick(Sender: TObject);
    procedure BtnBurst1sClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintArenaPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TMassEntityModifyCallback;
      const AOnRefresh: TMassEntityRefreshCallback);
  end;

implementation

constructor TMassEntityForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TMassEntityModifyCallback;
  const AOnRefresh: TMassEntityRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;

  Caption := 'Castle Game Engine — MassEntity Data-Oriented SoA Crowd & Flow-Field Studio';
  Width := 1180;
  Height := 730;
  Position := poMainFormCenter;

  BuildUi;
  RefreshFromDesign;
end;

procedure TMassEntityForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TMassEntityForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
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
  LblHeader.Caption := 'MassEntity ECS Crowd Studio — SoA Archetypes, O(1) Spatial Hash Grid, Dijkstra Flow-Field & 4-Tier Representation LOD';

  MakeBtn(PanelTop, '+ Spawn 250-Agent Plaza Swarm', 12, 34, 214, @BtnSpawnDemoClick);
  MakeBtn(PanelTop, 'City Flow (250)', 232, 34, 124, @BtnPresetCityClick);
  MakeBtn(PanelTop, 'Boids Flock (400)', 362, 34, 134, @BtnPresetBoidsClick);
  MakeBtn(PanelTop, 'Siege Charge (600)', 502, 34, 144, @BtnPresetSiegeClick);
  MakeBtn(PanelTop, 'Cycle Goal + Rebake', 652, 34, 152, @BtnCycleGoalClick);
  MakeBtn(PanelTop, 'Step +0.05s', 810, 34, 114, @BtnStep50msClick);
  MakeBtn(PanelTop, 'Burst +1.0s (20x)', 930, 34, 146, @BtnBurst1sClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Telemetry Markdown', 12, 6, 210, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 6, 380, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'MassEntity SoA Swarm Managers:';

  ListSwarms := TListBox.Create(Self);
  ListSwarms.Parent := PanelLeft;
  ListSwarms.SetBounds(12, 26, 396, 240);
  ListSwarms.OnClick := @ListSwarmsClick;

  LblDetails := TLabel.Create(Self);
  LblDetails.Parent := PanelLeft;
  LblDetails.SetBounds(12, 276, 396, 130);
  LblDetails.WordWrap := True;
  LblDetails.Caption := '';

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintArena := TPaintBox.Create(Self);
  PaintArena.Parent := PanelCenter;
  PaintArena.Align := alTop;
  PaintArena.Height := 300;
  PaintArena.OnPaint := @PaintArenaPaint;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := PanelCenter;
  MemoReport.Align := alClient;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssAutoBoth;
  MemoReport.Font.Name := 'Monospace';
end;

function TMassEntityForm.SelectedSwarm: TCastleMassEntityManager;
var
  Idx: Integer;
begin
  Idx := ListSwarms.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FSwarms)) then
    Result := FSwarms[Idx]
  else if Length(FSwarms) > 0 then
    Result := FSwarms[0]
  else
    Result := nil;
end;

procedure TMassEntityForm.RefreshFromDesign;
var
  I, PrevIdx: Integer;
  S: TCastleMassEntityManager;
begin
  PrevIdx := ListSwarms.ItemIndex;
  TMassEntityHelper.ScanSwarms(FDesignRoot, FDesignOwner, FSwarms);

  ListSwarms.Items.BeginUpdate;
  try
    ListSwarms.Items.Clear;
    for I := 0 to High(FSwarms) do
      ListSwarms.Items.Add(Format('%s  %s',
        [FSwarms[I].Name, FSwarms[I].SwarmSummaryBadge]));
    if ListSwarms.Items.Count > 0 then
      ListSwarms.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListSwarms.Items.Count - 1);
  finally
    ListSwarms.Items.EndUpdate;
  end;

  S := SelectedSwarm;
  if S <> nil then
    LblDetails.Caption := Format(
      'Preset: %s  |  Entities: %d  |  Step CPU: %.2f ms' + LineEnding +
      'LOD Tiers: High=%d | Med=%d | Low=%d | Culled=%d' + LineEnding +
      'Goal XZ: (%.1f, %.1f)  |  Obstacles: %d',
      [TCastleMassEntityManager.PresetDisplayName(S.Preset),
       S.ActiveEntityCount, S.LastStepTimeMs,
       S.GetTierCount(mrtHighMesh), S.GetTierCount(mrtMediumProxy),
       S.GetTierCount(mrtLowBatchedPoint), S.GetTierCount(mrtCulledOffscreen),
       S.GoalPosXZ.X, S.GoalPosXZ.Y, S.ObstacleCount])
  else
    LblDetails.Caption := 'Click "+ Spawn 250-Agent Plaza Swarm" to populate a MassEntity crowd.';

  MemoReport.Lines.Text := TMassEntityHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintArena.Invalidate;
end;

procedure TMassEntityForm.ListSwarmsClick(Sender: TObject);
begin
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnSpawnDemoClick(Sender: TObject);
begin
  TMassEntityHelper.SpawnMassSwarmArenaDemo(FDesignRoot, FDesignOwner);
  NotifyModified('Spawn MassEntity SoA Crowd Demo');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnPresetCityClick(Sender: TObject);
var
  S: TCastleMassEntityManager;
begin
  S := SelectedSwarm;
  if S = nil then Exit;
  S.ApplyPreset(mspCityPedestrianFlow);
  S.BakeGoalFlowField;
  S.UpdateRepresentationLods(Vector3(0.0, 8.0, 18.0));
  NotifyModified('Apply MassEntity City Flow Preset');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnPresetBoidsClick(Sender: TObject);
var
  S: TCastleMassEntityManager;
begin
  S := SelectedSwarm;
  if S = nil then Exit;
  S.ApplyPreset(mspBoidsMurmurationSwarm);
  S.BakeGoalFlowField;
  S.UpdateRepresentationLods(Vector3(0.0, 8.0, 18.0));
  NotifyModified('Apply MassEntity Boids Flock Preset');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnPresetSiegeClick(Sender: TObject);
var
  S: TCastleMassEntityManager;
begin
  S := SelectedSwarm;
  if S = nil then Exit;
  S.ApplyPreset(mspSiegeInfantryCharge);
  S.BakeGoalFlowField;
  S.UpdateRepresentationLods(Vector3(0.0, 8.0, 18.0));
  NotifyModified('Apply MassEntity Siege Charge Preset');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnCycleGoalClick(Sender: TObject);
var
  S: TCastleMassEntityManager;
begin
  S := SelectedSwarm;
  if S = nil then Exit;
  if S.GoalPosXZ.Y < -5.0 then
    S.GoalPosXZ := Vector2(14.0, 14.0)
  else if S.GoalPosXZ.X > 5.0 then
    S.GoalPosXZ := Vector2(-14.0, 14.0)
  else
    S.GoalPosXZ := Vector2(0.0, -16.0);
  S.BakeGoalFlowField;
  NotifyModified('Relocate MassEntity Flow-Field Goal');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnStep50msClick(Sender: TObject);
begin
  TMassEntityHelper.StepAllSwarms(FDesignRoot, FDesignOwner, 0.05);
  NotifyModified('Step MassEntity Swarms (+0.05s)');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnBurst1sClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 1 to 20 do
    TMassEntityHelper.StepAllSwarms(FDesignRoot, FDesignOwner, 0.05);
  NotifyModified('Burst MassEntity Swarms (+1.0s)');
  RefreshFromDesign;
end;

procedure TMassEntityForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := MemoReport.Lines.Text;
end;

procedure TMassEntityForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TMassEntityForm.PaintArenaPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, MapCX, MapCY, MapHalfPx, I, GX, GZ, PX, PZ, RadPx: Integer;
  S: TCastleMassEntityManager;
  HalfExt, ScalePx, WX, WZ: Single;
  FlowV: TVector2;
  Obs: TMassCircularObstacle;
  Snap: TMassEntitySnapshot;
begin
  C := PaintArena.Canvas;
  W := PaintArena.Width;
  H := PaintArena.Height;

  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  S := SelectedSwarm;
  if S = nil then
    Exit;

  MapCX := W div 2;
  MapCY := H div 2 + 8;
  MapHalfPx := Min(W div 2 - 40, H div 2 - 26);
  HalfExt := Max(4.0, S.ArenaHalfExtent);
  ScalePx := MapHalfPx / HalfExt;

  C.Brush.Color := RGBToColor(11, 15, 22);
  C.Pen.Color := RGBToColor(52, 64, 84);
  C.Rectangle(MapCX - MapHalfPx, MapCY - MapHalfPx, MapCX + MapHalfPx, MapCY + MapHalfPx);

  { Draw coarse Dijkstra flow-field vectors }
  C.Pen.Color := RGBToColor(44, 68, 92);
  for GZ := -5 to 5 do
    for GX := -5 to 5 do
    begin
      WX := (GX / 5.5) * HalfExt;
      WZ := (GZ / 5.5) * HalfExt;
      FlowV := S.SampleFlowDirectionXZ(WX, WZ);
      PX := MapCX + Round(WX * ScalePx);
      PZ := MapCY + Round(WZ * ScalePx);
      C.MoveTo(PX, PZ);
      C.LineTo(PX + Round(FlowV.X * 10.0), PZ + Round(FlowV.Y * 10.0));
    end;

  { Draw circular obstacles }
  C.Brush.Color := RGBToColor(132, 74, 58);
  C.Pen.Color := RGBToColor(215, 120, 92);
  for I := 0 to S.ObstacleCount - 1 do
  begin
    Obs := S.GetObstacle(I);
    PX := MapCX + Round(Obs.CenterX * ScalePx);
    PZ := MapCY + Round(Obs.CenterZ * ScalePx);
    RadPx := Max(3, Round(Obs.Radius * ScalePx));
    C.Ellipse(PX - RadPx, PZ - RadPx, PX + RadPx, PZ + RadPx);
  end;

  { Draw Goal Beacon }
  PX := MapCX + Round(S.GoalPosXZ.X * ScalePx);
  PZ := MapCY + Round(S.GoalPosXZ.Y * ScalePx);
  C.Brush.Color := RGBToColor(56, 224, 118);
  C.Pen.Color := clWhite;
  C.Ellipse(PX - 6, PZ - 6, PX + 6, PZ + 6);

  { Draw SoA entities color-coded by 4-tier Representation LOD }
  for I := 0 to Min(S.ActiveEntityCount - 1, 1200) do
  begin
    Snap := S.GetEntitySnapshot(I);
    PX := MapCX + Round(Snap.PosX * ScalePx);
    PZ := MapCY + Round(Snap.PosZ * ScalePx);
    case Snap.LodTier of
      mrtHighMesh:         C.Brush.Color := RGBToColor(84, 218, 255);
      mrtMediumProxy:      C.Brush.Color := RGBToColor(250, 198, 72);
      mrtLowBatchedPoint:  C.Brush.Color := RGBToColor(168, 124, 245);
      mrtCulledOffscreen:  C.Brush.Color := RGBToColor(92, 100, 114);
    end;
    C.Pen.Color := C.Brush.Color;
    C.Ellipse(PX - 2, PZ - 2, PX + 2, PZ + 2);
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(195, 210, 232);
  C.Font.Style := [fsBold];
  C.TextOut(14, 6, 'Top-Down XZ Flow-Field & 4-Tier MassRepresentation Swarm Map (Cyan=High | Gold=Med | Violet=Low | Green=Goal)');
  C.Font.Style := [];
end;

end.
