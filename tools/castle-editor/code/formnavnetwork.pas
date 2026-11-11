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

{ Interactive AI Waypoint Patrol Networks, 2D XZ A* NavGrid Baker & Perception
  Studio (@link(TNavNetworkForm)) (Phase 290 — UE 5.9 / 6.0 MassAI Parity). }
unit FormNavNetwork;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Spin, Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleNavNetwork, ToolNavNetwork;

type
  TNavStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TNavStudioRefreshViewportCallback = procedure of object;

  TNavNetworkForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FInitialSelected: TComponent;
    FOnModified: TNavStudioModifiedCallback;
    FOnRefreshViewport: TNavStudioRefreshViewportCallback;

    FSummary: TNavNetworkSummary;
    FTestPath: TVector3List;
    FTestStartCol, FTestStartRow: Integer;
    FTestGoalCol, FTestGoalRow: Integer;
    FSimTimer: TTimer;

    { Top bar }
    ButtonCreateLoop: TButton;
    ButtonBakeGrid: TButton;
    ButtonAttachAgent: TButton;
    ButtonSimToggle: TButton;
    ButtonSimStep: TButton;
    ButtonCopyMarkdown: TButton;

    { Center 2D NavGrid & A* Path Canvas }
    PaintBoxGrid: TPaintBox;
    LabelHint: TLabel;

    { Right inspector tabs }
    PanelRight: TPanel;
    PageRight: TPageControl;

    TabGrid: TTabSheet;
    ComboGrid: TComboBox;
    SpinCols: TSpinEdit;
    SpinRows: TSpinEdit;
    SpinCellSize: TFloatSpinEdit;
    SpinAgentRadius: TFloatSpinEdit;
    ButtonApplyAndBake: TButton;
    ButtonClearGrid: TButton;
    LabelPathReadout: TLabel;

    TabAgents: TTabSheet;
    ComboAgent: TComboBox;
    SpinMoveSpeed: TFloatSpinEdit;
    SpinSightRadius: TFloatSpinEdit;
    SpinSightHalfAngle: TFloatSpinEdit;
    SpinHearingRadius: TFloatSpinEdit;
    ComboStartWaypoint: TComboBox;
    ButtonApplyAgent: TButton;
    ListWaypoints: TListBox;

    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveGrid: TCastleNavGrid;
    function ActiveAgent: TCastlePatrolAgentBehavior;
    procedure RefreshAll;
    procedure RecomputeTestPath;
    procedure LoadGridControls;
    procedure LoadAgentControls;
    procedure NotifyModified(const Comment: String);
    procedure NotifyViewportRefresh;

    function GridDrawRect: TRect;
    procedure PaintBoxGridPaint(Sender: TObject);
    procedure PaintBoxGridMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure ButtonCreateLoopClick(Sender: TObject);
    procedure ButtonBakeGridClick(Sender: TObject);
    procedure ButtonAttachAgentClick(Sender: TObject);
    procedure ButtonSimToggleClick(Sender: TObject);
    procedure ButtonSimStepClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure SimTimerTick(Sender: TObject);

    procedure ComboGridChange(Sender: TObject);
    procedure ButtonApplyAndBakeClick(Sender: TObject);
    procedure ButtonClearGridClick(Sender: TObject);
    procedure ComboAgentChange(Sender: TObject);
    procedure ButtonApplyAgentClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
      const AOnModified: TNavStudioModifiedCallback;
      const AOnRefreshViewport: TNavStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

uses
  CastleViewport;

constructor TNavNetworkForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, AInitialSelected: TComponent;
  const AOnModified: TNavStudioModifiedCallback;
  const AOnRefreshViewport: TNavStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FInitialSelected := AInitialSelected;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  FTestPath := TVector3List.Create;
  FTestStartCol := 2;
  FTestStartRow := 2;
  FTestGoalCol := 28;
  FTestGoalRow := 28;

  FSimTimer := TTimer.Create(Self);
  FSimTimer.Interval := 33;
  FSimTimer.Enabled := false;
  FSimTimer.OnTimer := @SimTimerTick;

  BuildUi;
  RefreshAll;
end;

destructor TNavNetworkForm.Destroy;
begin
  if FSimTimer <> nil then
    FSimTimer.Enabled := false;
  FreeAndNil(FTestPath);
  inherited Destroy;
end;

procedure TNavNetworkForm.BuildUi;
var
  PanelTop, PanelBottom, PanelCanvasWrap: TPanel;
  Lbl: TLabel;
begin
  Caption := 'AI Waypoint Patrol Networks, A* NavGrid & Perception Studio';
  Position := poScreenCenter;
  Width := 1120;
  Height := 690;
  Constraints.MinWidth := 940;
  Constraints.MinHeight := 580;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  ButtonCreateLoop := TButton.Create(Self);
  ButtonCreateLoop.Parent := PanelTop;
  ButtonCreateLoop.Caption := '+ 4-Point Patrol Loop';
  ButtonCreateLoop.SetBounds(10, 8, 156, 28);
  ButtonCreateLoop.OnClick := @ButtonCreateLoopClick;

  ButtonBakeGrid := TButton.Create(Self);
  ButtonBakeGrid.Parent := PanelTop;
  ButtonBakeGrid.Caption := '+ Add / Bake NavGrid';
  ButtonBakeGrid.SetBounds(174, 8, 156, 28);
  ButtonBakeGrid.OnClick := @ButtonBakeGridClick;

  ButtonAttachAgent := TButton.Create(Self);
  ButtonAttachAgent.Parent := PanelTop;
  ButtonAttachAgent.Caption := '+ Attach Patrol AI';
  ButtonAttachAgent.SetBounds(338, 8, 142, 28);
  ButtonAttachAgent.OnClick := @ButtonAttachAgentClick;

  ButtonSimToggle := TButton.Create(Self);
  ButtonSimToggle.Parent := PanelTop;
  ButtonSimToggle.Caption := 'Start Live Patrol';
  ButtonSimToggle.SetBounds(488, 8, 132, 28);
  ButtonSimToggle.OnClick := @ButtonSimToggleClick;

  ButtonSimStep := TButton.Create(Self);
  ButtonSimStep.Parent := PanelTop;
  ButtonSimStep.Caption := 'Step +0.25s';
  ButtonSimStep.SetBounds(626, 8, 98, 28);
  ButtonSimStep.OnClick := @ButtonSimStepClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.Caption := 'Copy Nav Report MD';
  ButtonCopyMarkdown.SetBounds(732, 8, 148, 28);
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  LabelHint := TLabel.Create(Self);
  LabelHint.Parent := PanelBottom;
  LabelHint.Left := 12;
  LabelHint.Top := 12;
  LabelHint.Caption :=
    'LMB on NavGrid cell: toggle blocked obstacle | RMB on cell: move A* Goal (Shift+RMB: move Start) | Emerald = A* Path';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Caption := 'Close';
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.SetBounds(Width - 102, 6, 88, 28);
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := Self;
  PanelRight.Align := alRight;
  PanelRight.Width := 370;
  PanelRight.BevelOuter := bvNone;
  PanelRight.BorderSpacing.Around := 4;

  PageRight := TPageControl.Create(Self);
  PageRight.Parent := PanelRight;
  PageRight.Align := alClient;

  { Tab 1: NavGrid }
  TabGrid := TTabSheet.Create(PageRight);
  TabGrid.PageControl := PageRight;
  TabGrid.Caption := 'A* NavGrid';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabGrid;
  Lbl.Caption := 'Active NavGrid:';
  Lbl.SetBounds(10, 12, 110, 18);

  ComboGrid := TComboBox.Create(Self);
  ComboGrid.Parent := TabGrid;
  ComboGrid.Style := csDropDownList;
  ComboGrid.SetBounds(10, 32, 336, 26);
  ComboGrid.OnChange := @ComboGridChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabGrid;
  Lbl.Caption := 'Cols x Rows:';
  Lbl.SetBounds(10, 74, 90, 18);

  SpinCols := TSpinEdit.Create(Self);
  SpinCols.Parent := TabGrid;
  SpinCols.MinValue := 4;
  SpinCols.MaxValue := 256;
  SpinCols.SetBounds(118, 70, 96, 26);

  SpinRows := TSpinEdit.Create(Self);
  SpinRows.Parent := TabGrid;
  SpinRows.MinValue := 4;
  SpinRows.MaxValue := 256;
  SpinRows.SetBounds(226, 70, 96, 26);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabGrid;
  Lbl.Caption := 'Cell Size (m):';
  Lbl.SetBounds(10, 110, 96, 18);

  SpinCellSize := TFloatSpinEdit.Create(Self);
  SpinCellSize.Parent := TabGrid;
  SpinCellSize.DecimalPlaces := 2;
  SpinCellSize.MinValue := 0.2;
  SpinCellSize.MaxValue := 20.0;
  SpinCellSize.Increment := 0.25;
  SpinCellSize.SetBounds(118, 106, 96, 26);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabGrid;
  Lbl.Caption := 'Agent Radius (m):';
  Lbl.SetBounds(10, 146, 104, 18);

  SpinAgentRadius := TFloatSpinEdit.Create(Self);
  SpinAgentRadius.Parent := TabGrid;
  SpinAgentRadius.DecimalPlaces := 2;
  SpinAgentRadius.MinValue := 0.0;
  SpinAgentRadius.MaxValue := 10.0;
  SpinAgentRadius.Increment := 0.1;
  SpinAgentRadius.SetBounds(118, 142, 96, 26);

  ButtonApplyAndBake := TButton.Create(Self);
  ButtonApplyAndBake.Parent := TabGrid;
  ButtonApplyAndBake.Caption := 'Apply & Re-Bake World Obstacles';
  ButtonApplyAndBake.SetBounds(10, 184, 226, 30);
  ButtonApplyAndBake.OnClick := @ButtonApplyAndBakeClick;

  ButtonClearGrid := TButton.Create(Self);
  ButtonClearGrid.Parent := TabGrid;
  ButtonClearGrid.Caption := 'Clear Cells';
  ButtonClearGrid.SetBounds(244, 184, 102, 30);
  ButtonClearGrid.OnClick := @ButtonClearGridClick;

  LabelPathReadout := TLabel.Create(Self);
  LabelPathReadout.Parent := TabGrid;
  LabelPathReadout.SetBounds(10, 228, 336, 48);
  LabelPathReadout.AutoSize := false;
  LabelPathReadout.WordWrap := true;
  LabelPathReadout.Font.Style := [Graphics.fsBold];

  { Tab 2: Agents & Waypoints }
  TabAgents := TTabSheet.Create(PageRight);
  TabAgents.PageControl := PageRight;
  TabAgents.Caption := 'Patrol & Perception';

  ComboAgent := TComboBox.Create(Self);
  ComboAgent.Parent := TabAgents;
  ComboAgent.Style := csDropDownList;
  ComboAgent.SetBounds(10, 10, 336, 26);
  ComboAgent.OnChange := @ComboAgentChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAgents;
  Lbl.Caption := 'Target Waypoint:';
  Lbl.SetBounds(10, 48, 110, 18);

  ComboStartWaypoint := TComboBox.Create(Self);
  ComboStartWaypoint.Parent := TabAgents;
  ComboStartWaypoint.SetBounds(136, 44, 210, 26);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAgents;
  Lbl.Caption := 'Move Speed (m/s):';
  Lbl.SetBounds(10, 84, 120, 18);

  SpinMoveSpeed := TFloatSpinEdit.Create(Self);
  SpinMoveSpeed.Parent := TabAgents;
  SpinMoveSpeed.DecimalPlaces := 2;
  SpinMoveSpeed.MinValue := 0.0;
  SpinMoveSpeed.MaxValue := 100.0;
  SpinMoveSpeed.Increment := 0.5;
  SpinMoveSpeed.SetBounds(156, 80, 100, 26);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAgents;
  Lbl.Caption := 'Sight Radius (m):';
  Lbl.SetBounds(10, 118, 120, 18);

  SpinSightRadius := TFloatSpinEdit.Create(Self);
  SpinSightRadius.Parent := TabAgents;
  SpinSightRadius.DecimalPlaces := 1;
  SpinSightRadius.MinValue := 0.0;
  SpinSightRadius.MaxValue := 500.0;
  SpinSightRadius.Increment := 1.0;
  SpinSightRadius.SetBounds(156, 114, 100, 26);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAgents;
  Lbl.Caption := 'Sight Half-Angle (deg):';
  Lbl.SetBounds(10, 152, 140, 18);

  SpinSightHalfAngle := TFloatSpinEdit.Create(Self);
  SpinSightHalfAngle.Parent := TabAgents;
  SpinSightHalfAngle.DecimalPlaces := 1;
  SpinSightHalfAngle.MinValue := 1.0;
  SpinSightHalfAngle.MaxValue := 180.0;
  SpinSightHalfAngle.Increment := 5.0;
  SpinSightHalfAngle.SetBounds(156, 148, 100, 26);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAgents;
  Lbl.Caption := 'Hearing Radius (m):';
  Lbl.SetBounds(10, 186, 130, 18);

  SpinHearingRadius := TFloatSpinEdit.Create(Self);
  SpinHearingRadius.Parent := TabAgents;
  SpinHearingRadius.DecimalPlaces := 1;
  SpinHearingRadius.MinValue := 0.0;
  SpinHearingRadius.MaxValue := 500.0;
  SpinHearingRadius.Increment := 1.0;
  SpinHearingRadius.SetBounds(156, 182, 100, 26);

  ButtonApplyAgent := TButton.Create(Self);
  ButtonApplyAgent.Parent := TabAgents;
  ButtonApplyAgent.Caption := 'Apply Agent & Perception Settings';
  ButtonApplyAgent.SetBounds(10, 218, 250, 30);
  ButtonApplyAgent.OnClick := @ButtonApplyAgentClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := TabAgents;
  Lbl.Caption := 'Patrol Waypoints in Scene:';
  Lbl.Font.Style := [Graphics.fsBold];
  Lbl.SetBounds(10, 258, 220, 18);

  ListWaypoints := TListBox.Create(Self);
  ListWaypoints.Parent := TabAgents;
  ListWaypoints.SetBounds(10, 280, 336, 250);
  ListWaypoints.Anchors := [akTop, akLeft, akBottom];

  { Center 2D XZ radar/grid canvas }
  PanelCanvasWrap := TPanel.Create(Self);
  PanelCanvasWrap.Parent := Self;
  PanelCanvasWrap.Align := alClient;
  PanelCanvasWrap.BevelOuter := bvLowered;
  PanelCanvasWrap.BorderSpacing.Around := 4;

  PaintBoxGrid := TPaintBox.Create(Self);
  PaintBoxGrid.Parent := PanelCanvasWrap;
  PaintBoxGrid.Align := alClient;
  PaintBoxGrid.OnPaint := @PaintBoxGridPaint;
  PaintBoxGrid.OnMouseDown := @PaintBoxGridMouseDown;
end;

function TNavNetworkForm.ActiveGrid: TCastleNavGrid;
var
  Idx: Integer;
begin
  Idx := ComboGrid.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FSummary.NavGrids)) then
    Result := FSummary.NavGrids[Idx]
  else
    Result := nil;
end;

function TNavNetworkForm.ActiveAgent: TCastlePatrolAgentBehavior;
var
  Idx: Integer;
begin
  Idx := ComboAgent.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FSummary.Agents)) then
    Result := FSummary.Agents[Idx]
  else
    Result := nil;
end;

procedure TNavNetworkForm.RefreshAll;
var
  I: Integer;
  ParentName: String;
begin
  FSummary := TNavNetworkHelper.ScanNavNetwork(FRootComponent);

  ComboGrid.Items.BeginUpdate;
  try
    ComboGrid.Items.Clear;
    for I := 0 to High(FSummary.NavGrids) do
      ComboGrid.Items.Add(Format('%s (%dx%d)',
        [FSummary.NavGrids[I].Name, FSummary.NavGrids[I].Cols, FSummary.NavGrids[I].Rows]));
    if (ComboGrid.ItemIndex < 0) and (ComboGrid.Items.Count > 0) then
      ComboGrid.ItemIndex := 0;
  finally
    ComboGrid.Items.EndUpdate;
  end;

  ComboStartWaypoint.Items.BeginUpdate;
  ListWaypoints.Items.BeginUpdate;
  try
    ComboStartWaypoint.Items.Clear;
    ListWaypoints.Items.Clear;
    for I := 0 to High(FSummary.Waypoints) do
    begin
      ComboStartWaypoint.Items.Add(FSummary.Waypoints[I].Name);
      ListWaypoints.Items.Add(Format('%s -> %s (Wait %.1fs)',
        [FSummary.Waypoints[I].Name, FSummary.Waypoints[I].NextWaypointName,
         FSummary.Waypoints[I].WaitTimeSec]));
    end;
  finally
    ListWaypoints.Items.EndUpdate;
    ComboStartWaypoint.Items.EndUpdate;
  end;

  ComboAgent.Items.BeginUpdate;
  try
    ComboAgent.Items.Clear;
    for I := 0 to High(FSummary.Agents) do
    begin
      if FSummary.Agents[I].Parent <> nil then
        ParentName := FSummary.Agents[I].Parent.Name
      else
        ParentName := '<detached>';
      ComboAgent.Items.Add(Format('%s on %s', [FSummary.Agents[I].Name, ParentName]));
    end;
    if (ComboAgent.ItemIndex < 0) and (ComboAgent.Items.Count > 0) then
      ComboAgent.ItemIndex := 0;
  finally
    ComboAgent.Items.EndUpdate;
  end;

  LoadGridControls;
  LoadAgentControls;
  RecomputeTestPath;
  PaintBoxGrid.Invalidate;
end;

procedure TNavNetworkForm.LoadGridControls;
var
  G: TCastleNavGrid;
begin
  G := ActiveGrid;
  if G = nil then
    Exit;
  SpinCols.Value := G.Cols;
  SpinRows.Value := G.Rows;
  SpinCellSize.Value := G.CellSize;
  SpinAgentRadius.Value := G.AgentRadius;
  FTestStartCol := Clamped(FTestStartCol, 0, G.Cols - 1);
  FTestStartRow := Clamped(FTestStartRow, 0, G.Rows - 1);
  FTestGoalCol := Clamped(FTestGoalCol, 0, G.Cols - 1);
  FTestGoalRow := Clamped(FTestGoalRow, 0, G.Rows - 1);
end;

procedure TNavNetworkForm.LoadAgentControls;
var
  A: TCastlePatrolAgentBehavior;
begin
  A := ActiveAgent;
  if A = nil then
    Exit;
  ComboStartWaypoint.Text := A.CurrentWaypointName;
  SpinMoveSpeed.Value := A.MoveSpeed;
  SpinSightRadius.Value := A.SightRadius;
  SpinSightHalfAngle.Value := A.SightHalfAngleDeg;
  SpinHearingRadius.Value := A.HearingRadius;
end;

procedure TNavNetworkForm.RecomputeTestPath;
var
  G: TCastleNavGrid;
  Found: Boolean;
begin
  FTestPath.Clear;
  G := ActiveGrid;
  if G = nil then
  begin
    LabelPathReadout.Caption := 'Click "+ Add / Bake NavGrid" to inspect 2D A* pathfinding.';
    Exit;
  end;
  Found := G.FindPathWorld(
    G.CellToWorldCenter(FTestStartCol, FTestStartRow),
    G.CellToWorldCenter(FTestGoalCol, FTestGoalRow),
    FTestPath);
  if Found then
    LabelPathReadout.Caption := Format(
      'A* Path Found: %d waypoints from (%d,%d) to (%d,%d) | Blocked Cells: %d',
      [FTestPath.Count, FTestStartCol, FTestStartRow,
       FTestGoalCol, FTestGoalRow, G.BlockedCellCount])
  else
    LabelPathReadout.Caption := Format(
      'No Path Available between (%d,%d) and (%d,%d)!',
      [FTestStartCol, FTestStartRow, FTestGoalCol, FTestGoalRow]);
end;

function TNavNetworkForm.GridDrawRect: TRect;
var
  Pad, AvailW, AvailH, Side: Integer;
begin
  Pad := 18;
  AvailW := Max(64, PaintBoxGrid.Width - Pad * 2);
  AvailH := Max(64, PaintBoxGrid.Height - Pad * 2);
  Side := Min(AvailW, AvailH);
  Result := Rect(
    (PaintBoxGrid.Width - Side) div 2,
    (PaintBoxGrid.Height - Side) div 2,
    (PaintBoxGrid.Width - Side) div 2 + Side,
    (PaintBoxGrid.Height - Side) div 2 + Side);
end;

procedure TNavNetworkForm.PaintBoxGridPaint(Sender: TObject);
var
  C: TCanvas;
  G: TCastleNavGrid;
  R: TRect;
  Col, Row, I, X1, Y1, X2, Y2: Integer;
  CellW, CellH: Single;
  NextWP: TCastleWaypointNode;

  function WorldToCanvasPt(const WPt: TVector3): TPoint;
  var
    OriginW: TVector3;
    SpanX, SpanZ, UX, UZ: Single;
  begin
    if G <> nil then
    begin
      OriginW := G.WorldTranslation;
      SpanX := Max(1.0, G.Cols * G.CellSize);
      SpanZ := Max(1.0, G.Rows * G.CellSize);
    end else
    begin
      OriginW := TVector3.Zero;
      SpanX := 32.0;
      SpanZ := 32.0;
    end;
    UX := (WPt.X - (OriginW.X - SpanX * 0.5)) / SpanX;
    UZ := (WPt.Z - (OriginW.Z - SpanZ * 0.5)) / SpanZ;
    Result := Point(
      R.Left + Round(UX * (R.Right - R.Left)),
      R.Top + Round(UZ * (R.Bottom - R.Top)));
  end;

begin
  C := PaintBoxGrid.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := $1C1A17;
  C.FillRect(0, 0, PaintBoxGrid.Width, PaintBoxGrid.Height);

  R := GridDrawRect;
  G := ActiveGrid;

  if G <> nil then
  begin
    CellW := (R.Right - R.Left) / G.Cols;
    CellH := (R.Bottom - R.Top) / G.Rows;
    for Row := 0 to G.Rows - 1 do
      for Col := 0 to G.Cols - 1 do
      begin
        X1 := R.Left + Round(Col * CellW);
        Y1 := R.Top + Round(Row * CellH);
        X2 := R.Left + Round((Col + 1) * CellW);
        Y2 := R.Top + Round((Row + 1) * CellH);
        if G.IsCellBlocked(Col, Row) then
          C.Brush.Color := $38329E // Crimson blocked cell
        else
          C.Brush.Color := $2A2723;
        C.Pen.Color := $38332E;
        C.Rectangle(X1, Y1, X2, Y2);
      end;

    { Draw Start (S) & Goal (G) cells }
    C.Brush.Color := $D89830;
    C.FillRect(
      R.Left + Round(FTestStartCol * CellW) + 2,
      R.Top + Round(FTestStartRow * CellH) + 2,
      R.Left + Round((FTestStartCol + 1) * CellW) - 2,
      R.Top + Round((FTestStartRow + 1) * CellH) - 2);

    C.Brush.Color := $48D858;
    C.FillRect(
      R.Left + Round(FTestGoalCol * CellW) + 2,
      R.Top + Round(FTestGoalRow * CellH) + 2,
      R.Left + Round((FTestGoalCol + 1) * CellW) - 2,
      R.Top + Round((FTestGoalRow + 1) * CellH) - 2);

    { Draw live A* path polyline }
    if FTestPath.Count > 0 then
    begin
      C.Pen.Color := $68F058;
      C.Pen.Width := 3;
      for I := 0 to FTestPath.Count - 1 do
      begin
        if I = 0 then
        begin
          C.MoveTo(
            WorldToCanvasPt(G.CellToWorldCenter(FTestStartCol, FTestStartRow)).X,
            WorldToCanvasPt(G.CellToWorldCenter(FTestStartCol, FTestStartRow)).Y);
        end;
        C.LineTo(WorldToCanvasPt(FTestPath.L[I]).X, WorldToCanvasPt(FTestPath.L[I]).Y);
      end;
      C.Pen.Width := 1;
    end;
  end else
  begin
    C.Pen.Color := $443E38;
    C.Rectangle(R);
  end;

  { Draw Waypoints & Links }
  C.Pen.Color := $F0C848;
  C.Pen.Width := 2;
  for I := 0 to High(FSummary.Waypoints) do
  begin
    X1 := WorldToCanvasPt(FSummary.Waypoints[I].WorldTranslation).X;
    Y1 := WorldToCanvasPt(FSummary.Waypoints[I].WorldTranslation).Y;
    NextWP := FSummary.Waypoints[I].ResolveNextWaypoint(FRootComponent);
    if NextWP <> nil then
    begin
      X2 := WorldToCanvasPt(NextWP.WorldTranslation).X;
      Y2 := WorldToCanvasPt(NextWP.WorldTranslation).Y;
      C.Line(X1, Y1, X2, Y2);
    end;
    C.Brush.Color := $F0C848;
    C.Ellipse(X1 - 5, Y1 - 5, X1 + 5, Y1 + 5);
  end;

  { Draw AI Patrol Agents }
  for I := 0 to High(FSummary.Agents) do
    if FSummary.Agents[I].Parent <> nil then
    begin
      X1 := WorldToCanvasPt(FSummary.Agents[I].Parent.WorldTranslation).X;
      Y1 := WorldToCanvasPt(FSummary.Agents[I].Parent.WorldTranslation).Y;
      C.Brush.Color := $4888FF;
      C.Pen.Color := clWhite;
      C.Ellipse(X1 - 6, Y1 - 6, X1 + 6, Y1 + 6);
    end;
  C.Pen.Width := 1;
end;

procedure TNavNetworkForm.PaintBoxGridMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  G: TCastleNavGrid;
  R: TRect;
  Col, Row: Integer;
begin
  G := ActiveGrid;
  if G = nil then
    Exit;
  R := GridDrawRect;
  if not PtInRect(R, Point(X, Y)) then
    Exit;

  Col := Clamped(Floor(((X - R.Left) / Max(1, R.Right - R.Left)) * G.Cols), 0, G.Cols - 1);
  Row := Clamped(Floor(((Y - R.Top) / Max(1, R.Bottom - R.Top)) * G.Rows), 0, G.Rows - 1);

  if Button = mbLeft then
  begin
    G.SetCellBlocked(Col, Row, not G.IsCellBlocked(Col, Row));
    RecomputeTestPath;
    PaintBoxGrid.Invalidate;
    NotifyModified(Format('Toggle NavGrid cell (%d,%d)', [Col, Row]));
  end else
  if Button = mbRight then
  begin
    if ssShift in Shift then
    begin
      FTestStartCol := Col;
      FTestStartRow := Row;
    end else
    begin
      FTestGoalCol := Col;
      FTestGoalRow := Row;
    end;
    RecomputeTestPath;
    PaintBoxGrid.Invalidate;
  end;
end;

procedure TNavNetworkForm.NotifyModified(const Comment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(Comment);
  NotifyViewportRefresh;
end;

procedure TNavNetworkForm.NotifyViewportRefresh;
begin
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport;
end;

procedure TNavNetworkForm.ButtonCreateLoopClick(Sender: TObject);
var
  FirstWP: TCastleWaypointNode;
begin
  FirstWP := TNavNetworkHelper.CreatePatrolLoop(
    FRootComponent, FDesignOwner, Vector3(0, 0, 0), 8.0, 4);
  if FirstWP = nil then
    Exit;
  NotifyModified('Create 4-point AI patrol waypoint loop');
  RefreshAll;
end;

procedure TNavNetworkForm.ButtonBakeGridClick(Sender: TObject);
var
  G: TCastleNavGrid;
begin
  G := TNavNetworkHelper.CreateOrBakeNavGrid(FRootComponent, FDesignOwner, 32, 32, 1.0);
  if G = nil then
    Exit;
  NotifyModified('Create/Bake 3D world A* NavGrid ' + G.Name);
  RefreshAll;
end;

procedure TNavNetworkForm.ButtonAttachAgentClick(Sender: TObject);
var
  TargetT: TCastleTransform;
  FirstWpName, GridName: String;
begin
  if FInitialSelected is TCastleTransform then
    TargetT := TCastleTransform(FInitialSelected)
  else
    TargetT := nil;
  if (TargetT = nil) or (TargetT is TCastleWaypointNode) or (TargetT is TCastleNavGrid) then
  begin
    MessageDlg('Attach Patrol AI',
      'Select a character/entity TCastleTransform in the Hierarchy first, then open AI Nav Studio.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  if Length(FSummary.Waypoints) > 0 then
    FirstWpName := FSummary.Waypoints[0].Name
  else
    FirstWpName := '';
  if Length(FSummary.NavGrids) > 0 then
    GridName := FSummary.NavGrids[0].Name
  else
    GridName := '';

  TNavNetworkHelper.AttachPatrolAgent(TargetT, FDesignOwner, FirstWpName, GridName);
  NotifyModified('Attach TCastlePatrolAgentBehavior to ' + TargetT.Name);
  RefreshAll;
end;

procedure TNavNetworkForm.ButtonSimToggleClick(Sender: TObject);
begin
  FSimTimer.Enabled := not FSimTimer.Enabled;
  if FSimTimer.Enabled then
    ButtonSimToggle.Caption := 'Pause Live Patrol'
  else
    ButtonSimToggle.Caption := 'Start Live Patrol';
end;

procedure TNavNetworkForm.ButtonSimStepClick(Sender: TObject);
begin
  TNavNetworkHelper.StepAllPatrolAgents(FRootComponent, 0.25);
  PaintBoxGrid.Invalidate;
  NotifyViewportRefresh;
end;

procedure TNavNetworkForm.SimTimerTick(Sender: TObject);
begin
  TNavNetworkHelper.StepAllPatrolAgents(FRootComponent, 0.033);
  PaintBoxGrid.Invalidate;
  NotifyViewportRefresh;
end;

procedure TNavNetworkForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  FSummary := TNavNetworkHelper.ScanNavNetwork(FRootComponent);
  Clipboard.AsText := TNavNetworkHelper.FormatNavReportMarkdown(FSummary, FRootComponent);
  MessageDlg('Copied AI Nav Report',
    'Markdown AI navigation & perception report copied to clipboard.',
    mtInformation, [mbOK], 0);
end;

procedure TNavNetworkForm.ComboGridChange(Sender: TObject);
begin
  LoadGridControls;
  RecomputeTestPath;
  PaintBoxGrid.Invalidate;
end;

procedure TNavNetworkForm.ButtonApplyAndBakeClick(Sender: TObject);
var
  G: TCastleNavGrid;
  WorldItems: TCastleTransform;
begin
  G := ActiveGrid;
  if G = nil then
    Exit;
  G.Cols := SpinCols.Value;
  G.Rows := SpinRows.Value;
  G.CellSize := SpinCellSize.Value;
  G.AgentRadius := SpinAgentRadius.Value;
  WorldItems := TNavNetworkHelper.FindWorldItemsRoot(FRootComponent);
  G.BakeObstaclesFromWorld(WorldItems);
  RecomputeTestPath;
  PaintBoxGrid.Invalidate;
  NotifyModified('Re-bake A* NavGrid ' + G.Name);
end;

procedure TNavNetworkForm.ButtonClearGridClick(Sender: TObject);
var
  G: TCastleNavGrid;
begin
  G := ActiveGrid;
  if G = nil then
    Exit;
  G.ClearBlockedCells;
  RecomputeTestPath;
  PaintBoxGrid.Invalidate;
  NotifyModified('Clear blocked cells in ' + G.Name);
end;

procedure TNavNetworkForm.ComboAgentChange(Sender: TObject);
begin
  LoadAgentControls;
end;

procedure TNavNetworkForm.ButtonApplyAgentClick(Sender: TObject);
var
  A: TCastlePatrolAgentBehavior;
begin
  A := ActiveAgent;
  if A = nil then
    Exit;
  A.CurrentWaypointName := ComboStartWaypoint.Text;
  A.MoveSpeed := SpinMoveSpeed.Value;
  A.SightRadius := SpinSightRadius.Value;
  A.SightHalfAngleDeg := SpinSightHalfAngle.Value;
  A.HearingRadius := SpinHearingRadius.Value;
  A.InvalidateCachedPath;
  NotifyModified('Update AI Patrol & Perception settings on ' + A.Name);
  RefreshAll;
end;

procedure TNavNetworkForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
