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

{ Interactive 3D Catmull-Rom Spline Path, Ribbon/Tube Extruder, Knot Canvas &
  Spline-Mesh Scatter Studio (@link(TSplineStudioForm))
  (Phase 297 — UE 6.0 USplineComponent & Landscape Splines Parity). }
unit FormSplineStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  Dialogs, Clipbrd,
  CastleVectors, CastleColors, CastleUtils, CastleTransform,
  CastleSplinePath, ToolSplineStudio;

type
  TSplineStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TSplineStudioRefreshViewportCallback = procedure of object;

  TSplineStudioForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FSelectedComponent: TComponent;
    FSpawnPosition: TVector3;
    FOnModified: TSplineStudioModifiedCallback;
    FOnRefreshViewport: TSplineStudioRefreshViewportCallback;

    FSplines: TSplinePathArray;
    FDraggingKnotIdx: Integer;
    FCanvasScale: Single;
    FCanvasCenterXZ: TVector2;

    ButtonSpawnRoad: TButton;
    ButtonSpawnRiver: TButton;
    ButtonSpawnCable: TButton;
    ButtonSpawnTrack: TButton;
    ButtonSnapGround: TButton;
    ButtonAttachFollower: TButton;
    ButtonToggleSim: TButton;
    ButtonCopyMarkdown: TButton;

    ListBoxSplines: TListBox;
    ComboMeshMode: TComboBox;
    CheckClosedLoop: TCheckBox;
    EditRibbonWidth: TEdit;
    EditTension: TEdit;
    ButtonApplySplineProps: TButton;

    EditScatterSpacing: TEdit;
    EditScatterOffset: TEdit;
    EditScatterUrl: TEdit;
    ButtonPopulateSpline: TButton;
    ButtonClearPopulated: TButton;

    PaintBoxCanvas: TPaintBox;

    ListBoxKnots: TListBox;
    EditKnotX: TEdit;
    EditKnotY: TEdit;
    EditKnotZ: TEdit;
    EditKnotRoll: TEdit;
    EditKnotWidthScale: TEdit;
    ButtonUpdateKnot: TButton;
    ButtonAddKnot: TButton;
    ButtonDeleteKnot: TButton;

    LabelStatus: TLabel;
    ButtonClose: TButton;
    TimerSim: TTimer;

    procedure BuildUi;
    function ActiveSpline: TCastleSplinePath;
    procedure RefreshSplineList(const ASelectSpline: TCastleSplinePath = nil);
    procedure LoadActiveSplineIntoControls;
    procedure RefreshKnotList(const AKeepIdx: Integer = -1);
    procedure RecenterCanvasOnSpline(const ASpline: TCastleSplinePath);
    function WorldXZToCanvas(const AX, AZ: Single): TPoint;
    function CanvasToWorldXZ(const AX, AY: Integer): TVector2;
    procedure NotifyModified(const AComment: String);

    procedure SpawnPreset(const APreset: TSplinePreset; const ALabel: String);
    procedure ButtonSpawnRoadClick(Sender: TObject);
    procedure ButtonSpawnRiverClick(Sender: TObject);
    procedure ButtonSpawnCableClick(Sender: TObject);
    procedure ButtonSpawnTrackClick(Sender: TObject);
    procedure ButtonSnapGroundClick(Sender: TObject);
    procedure ButtonAttachFollowerClick(Sender: TObject);
    procedure ButtonToggleSimClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);

    procedure ListBoxSplinesClick(Sender: TObject);
    procedure ButtonApplySplinePropsClick(Sender: TObject);
    procedure ButtonPopulateSplineClick(Sender: TObject);
    procedure ButtonClearPopulatedClick(Sender: TObject);

    procedure PaintBoxCanvasPaint(Sender: TObject);
    procedure PaintBoxCanvasMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxCanvasMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBoxCanvasMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure ListBoxKnotsClick(Sender: TObject);
    procedure ButtonUpdateKnotClick(Sender: TObject);
    procedure ButtonAddKnotClick(Sender: TObject);
    procedure ButtonDeleteKnotClick(Sender: TObject);
    procedure TimerSimTimer(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
      const ASpawnPosition: TVector3;
      const AOnModified: TSplineStudioModifiedCallback;
      const AOnRefreshViewport: TSplineStudioRefreshViewportCallback);
  end;

implementation

constructor TSplineStudioForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
  const ASpawnPosition: TVector3;
  const AOnModified: TSplineStudioModifiedCallback;
  const AOnRefreshViewport: TSplineStudioRefreshViewportCallback);
var
  InitialSpline: TCastleSplinePath;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FSelectedComponent := ASelectedComponent;
  FSpawnPosition := ASpawnPosition;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FDraggingKnotIdx := -1;
  FCanvasScale := 10.0;
  FCanvasCenterXZ := Vector2(0.0, -14.0);

  BuildUi;

  if FSelectedComponent is TCastleSplinePath then
    InitialSpline := TCastleSplinePath(FSelectedComponent)
  else
    InitialSpline := nil;
  RefreshSplineList(InitialSpline);
end;

procedure TSplineStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelLeft, PanelRight, PanelCanvasWrap: TPanel;
  Lbl: TLabel;
begin
  Caption := '3D Spline Paths, Ribbon Road/River Extruder & Scatter Studio (UE 6.0 Parity)';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;
  Constraints.MinWidth := 980;
  Constraints.MinHeight := 600;

  TimerSim := TTimer.Create(Self);
  TimerSim.Interval := 33;
  TimerSim.Enabled := false;
  TimerSim.OnTimer := @TimerSimTimer;

  { Top Toolbar }
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  ButtonSpawnRoad := TButton.Create(Self);
  ButtonSpawnRoad.Parent := PanelTop;
  ButtonSpawnRoad.SetBounds(8, 8, 118, 28);
  ButtonSpawnRoad.Caption := '+ Winding Road';
  ButtonSpawnRoad.OnClick := @ButtonSpawnRoadClick;

  ButtonSpawnRiver := TButton.Create(Self);
  ButtonSpawnRiver.Parent := PanelTop;
  ButtonSpawnRiver.SetBounds(132, 8, 128, 28);
  ButtonSpawnRiver.Caption := '+ Meandering River';
  ButtonSpawnRiver.OnClick := @ButtonSpawnRiverClick;

  ButtonSpawnCable := TButton.Create(Self);
  ButtonSpawnCable.Parent := PanelTop;
  ButtonSpawnCable.SetBounds(266, 8, 122, 28);
  ButtonSpawnCable.Caption := '+ Hanging Cable';
  ButtonSpawnCable.OnClick := @ButtonSpawnCableClick;

  ButtonSpawnTrack := TButton.Create(Self);
  ButtonSpawnTrack.Parent := PanelTop;
  ButtonSpawnTrack.SetBounds(394, 8, 124, 28);
  ButtonSpawnTrack.Caption := '+ Closed Track';
  ButtonSpawnTrack.OnClick := @ButtonSpawnTrackClick;

  ButtonSnapGround := TButton.Create(Self);
  ButtonSnapGround.Parent := PanelTop;
  ButtonSnapGround.SetBounds(526, 8, 136, 28);
  ButtonSnapGround.Caption := 'Snap Knots to Floor';
  ButtonSnapGround.OnClick := @ButtonSnapGroundClick;

  ButtonAttachFollower := TButton.Create(Self);
  ButtonAttachFollower.Parent := PanelTop;
  ButtonAttachFollower.SetBounds(668, 8, 150, 28);
  ButtonAttachFollower.Caption := '+ Attach Follower';
  ButtonAttachFollower.OnClick := @ButtonAttachFollowerClick;

  ButtonToggleSim := TButton.Create(Self);
  ButtonToggleSim.Parent := PanelTop;
  ButtonToggleSim.SetBounds(824, 8, 138, 28);
  ButtonToggleSim.Caption := 'Start Follower Sim';
  ButtonToggleSim.OnClick := @ButtonToggleSimClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(968, 8, 158, 28);
  ButtonCopyMarkdown.Caption := 'Copy Markdown Report';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  { Bottom Status Bar }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.SetBounds(12, 12, 920, 18);
  LabelStatus.Caption := 'Tip: LMB-drag knots on the XZ canvas to sculpt curves in real time; RMB-click canvas to append a new knot.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.SetBounds(1030, 6, 96, 28);
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  { Left Splines + Extrusion & Scatter Panel }
  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 270;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 240, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Spline Paths in Design';

  ListBoxSplines := TListBox.Create(Self);
  ListBoxSplines.Parent := PanelLeft;
  ListBoxSplines.SetBounds(10, 26, 250, 150);
  ListBoxSplines.OnClick := @ListBoxSplinesClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 186, 90, 18);
  Lbl.Caption := 'Mesh Mode:';

  ComboMeshMode := TComboBox.Create(Self);
  ComboMeshMode.Parent := PanelLeft;
  ComboMeshMode.SetBounds(104, 182, 156, 24);
  ComboMeshMode.Style := csDropDownList;
  ComboMeshMode.Items.Add('None (Curve Only)');
  ComboMeshMode.Items.Add('Road Ribbon (PBR)');
  ComboMeshMode.Items.Add('River Ribbon (Alpha)');
  ComboMeshMode.Items.Add('Cable Tube (3D)');
  ComboMeshMode.ItemIndex := 1;

  CheckClosedLoop := TCheckBox.Create(Self);
  CheckClosedLoop.Parent := PanelLeft;
  CheckClosedLoop.SetBounds(10, 214, 220, 22);
  CheckClosedLoop.Caption := 'Closed Loop Spline';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 244, 100, 18);
  Lbl.Caption := 'Width (m):';

  EditRibbonWidth := TEdit.Create(Self);
  EditRibbonWidth.Parent := PanelLeft;
  EditRibbonWidth.SetBounds(104, 240, 66, 24);
  EditRibbonWidth.Text := '4.0';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(176, 244, 52, 18);
  Lbl.Caption := 'Tension:';

  EditTension := TEdit.Create(Self);
  EditTension.Parent := PanelLeft;
  EditTension.SetBounds(226, 240, 34, 24);
  EditTension.Text := '0.5';

  ButtonApplySplineProps := TButton.Create(Self);
  ButtonApplySplineProps.Parent := PanelLeft;
  ButtonApplySplineProps.SetBounds(10, 272, 250, 28);
  ButtonApplySplineProps.Caption := 'Apply Extrusion Settings';
  ButtonApplySplineProps.OnClick := @ButtonApplySplinePropsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 314, 250, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Spline-Mesh Post / Prop Scatter';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 338, 92, 18);
  Lbl.Caption := 'Spacing (m):';

  EditScatterSpacing := TEdit.Create(Self);
  EditScatterSpacing.Parent := PanelLeft;
  EditScatterSpacing.SetBounds(104, 334, 58, 24);
  EditScatterSpacing.Text := '4.0';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(168, 338, 48, 18);
  Lbl.Caption := 'Offset:';

  EditScatterOffset := TEdit.Create(Self);
  EditScatterOffset.Parent := PanelLeft;
  EditScatterOffset.SetBounds(214, 334, 46, 24);
  EditScatterOffset.Text := '2.2';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 368, 250, 18);
  Lbl.Caption := 'Optional Asset URL (blank = Marker Posts):';

  EditScatterUrl := TEdit.Create(Self);
  EditScatterUrl.Parent := PanelLeft;
  EditScatterUrl.SetBounds(10, 388, 250, 24);
  EditScatterUrl.Text := '';

  ButtonPopulateSpline := TButton.Create(Self);
  ButtonPopulateSpline.Parent := PanelLeft;
  ButtonPopulateSpline.SetBounds(10, 418, 152, 28);
  ButtonPopulateSpline.Caption := 'Populate Along Spline';
  ButtonPopulateSpline.OnClick := @ButtonPopulateSplineClick;

  ButtonClearPopulated := TButton.Create(Self);
  ButtonClearPopulated.Parent := PanelLeft;
  ButtonClearPopulated.SetBounds(166, 418, 94, 28);
  ButtonClearPopulated.Caption := 'Clear Posts';
  ButtonClearPopulated.OnClick := @ButtonClearPopulatedClick;

  { Right Knot Inspector }
  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := Self;
  PanelRight.Align := alRight;
  PanelRight.Width := 260;
  PanelRight.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.SetBounds(10, 6, 240, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Control Knots (Local Space)';

  ListBoxKnots := TListBox.Create(Self);
  ListBoxKnots.Parent := PanelRight;
  ListBoxKnots.SetBounds(10, 26, 240, 240);
  ListBoxKnots.OnClick := @ListBoxKnotsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.SetBounds(10, 276, 80, 18);
  Lbl.Caption := 'Local X / Y / Z:';

  EditKnotX := TEdit.Create(Self);
  EditKnotX.Parent := PanelRight;
  EditKnotX.SetBounds(10, 296, 74, 24);

  EditKnotY := TEdit.Create(Self);
  EditKnotY.Parent := PanelRight;
  EditKnotY.SetBounds(92, 296, 74, 24);

  EditKnotZ := TEdit.Create(Self);
  EditKnotZ.Parent := PanelRight;
  EditKnotZ.SetBounds(174, 296, 76, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.SetBounds(10, 328, 110, 18);
  Lbl.Caption := 'Bank Roll (deg):';

  EditKnotRoll := TEdit.Create(Self);
  EditKnotRoll.Parent := PanelRight;
  EditKnotRoll.SetBounds(130, 324, 120, 24);
  EditKnotRoll.Text := '0.0';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.SetBounds(10, 358, 110, 18);
  Lbl.Caption := 'Width Scale:';

  EditKnotWidthScale := TEdit.Create(Self);
  EditKnotWidthScale.Parent := PanelRight;
  EditKnotWidthScale.SetBounds(130, 354, 120, 24);
  EditKnotWidthScale.Text := '1.0';

  ButtonUpdateKnot := TButton.Create(Self);
  ButtonUpdateKnot.Parent := PanelRight;
  ButtonUpdateKnot.SetBounds(10, 388, 240, 28);
  ButtonUpdateKnot.Caption := 'Update Selected Knot';
  ButtonUpdateKnot.OnClick := @ButtonUpdateKnotClick;

  ButtonAddKnot := TButton.Create(Self);
  ButtonAddKnot.Parent := PanelRight;
  ButtonAddKnot.SetBounds(10, 422, 116, 28);
  ButtonAddKnot.Caption := '+ Append Knot';
  ButtonAddKnot.OnClick := @ButtonAddKnotClick;

  ButtonDeleteKnot := TButton.Create(Self);
  ButtonDeleteKnot.Parent := PanelRight;
  ButtonDeleteKnot.SetBounds(134, 422, 116, 28);
  ButtonDeleteKnot.Caption := '- Delete Knot';
  ButtonDeleteKnot.OnClick := @ButtonDeleteKnotClick;

  { Center Interactive XZ Spline Canvas }
  PanelCanvasWrap := TPanel.Create(Self);
  PanelCanvasWrap.Parent := Self;
  PanelCanvasWrap.Align := alClient;
  PanelCanvasWrap.BevelOuter := bvLowered;

  PaintBoxCanvas := TPaintBox.Create(Self);
  PaintBoxCanvas.Parent := PanelCanvasWrap;
  PaintBoxCanvas.Align := alClient;
  PaintBoxCanvas.OnPaint := @PaintBoxCanvasPaint;
  PaintBoxCanvas.OnMouseDown := @PaintBoxCanvasMouseDown;
  PaintBoxCanvas.OnMouseMove := @PaintBoxCanvasMouseMove;
  PaintBoxCanvas.OnMouseUp := @PaintBoxCanvasMouseUp;
end;

function TSplineStudioForm.ActiveSpline: TCastleSplinePath;
var
  Idx: Integer;
begin
  Idx := ListBoxSplines.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FSplines)) then
    Result := FSplines[Idx]
  else
    Result := nil;
end;

procedure TSplineStudioForm.RefreshSplineList(
  const ASelectSpline: TCastleSplinePath);
var
  Sum: TSplineStudioSummary;
  I, SelIdx: Integer;
begin
  Sum := TSplineStudioHelper.ScanSplines(FRootComponent);
  FSplines := Sum.Splines;
  ListBoxSplines.Items.BeginUpdate;
  try
    ListBoxSplines.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FSplines) do
    begin
      ListBoxSplines.Items.Add(Format('%s  (%.1fm, %d pts)', [
        FSplines[I].Name, FSplines[I].TotalLength, FSplines[I].ControlPointCount]));
      if FSplines[I] = ASelectSpline then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FSplines) > 0) then
      SelIdx := 0;
    ListBoxSplines.ItemIndex := SelIdx;
  finally
    ListBoxSplines.Items.EndUpdate;
  end;

  LoadActiveSplineIntoControls;
  LabelStatus.Caption := Format(
    'Splines: %d | Total Arc Length: %.1f m | Generated Triangles: %d | Followers: %d | Posts: %d',
    [Sum.SplineCount, Sum.TotalArcLengthMeters, Sum.TotalGeneratedTriangles,
     Sum.FollowerCount, Sum.GeneratedInstanceCount]);
end;

procedure TSplineStudioForm.LoadActiveSplineIntoControls;
var
  Sp: TCastleSplinePath;
begin
  Sp := ActiveSpline;
  if Sp = nil then
  begin
    ListBoxKnots.Items.Clear;
    PaintBoxCanvas.Invalidate;
    Exit;
  end;

  ComboMeshMode.ItemIndex := Ord(Sp.MeshMode);
  CheckClosedLoop.Checked := Sp.ClosedLoop;
  EditRibbonWidth.Text := FormatFloat('0.##', Sp.RibbonWidth);
  EditTension.Text := FormatFloat('0.##', Sp.Tension);
  RecenterCanvasOnSpline(Sp);
  RefreshKnotList(0);
  PaintBoxCanvas.Invalidate;
end;

procedure TSplineStudioForm.RefreshKnotList(const AKeepIdx: Integer);
var
  Sp: TCastleSplinePath;
  I: Integer;
  Pt: TSplineControlPoint;
begin
  ListBoxKnots.Items.BeginUpdate;
  try
    ListBoxKnots.Items.Clear;
    Sp := ActiveSpline;
    if Sp <> nil then
    begin
      for I := 0 to Sp.ControlPointCount - 1 do
      begin
        Pt := Sp.GetControlPoint(I);
        ListBoxKnots.Items.Add(Format('#%d  (%.1f, %.1f, %.1f)  Roll=%.0f° W=%.2fx', [
          I, Pt.Position.X, Pt.Position.Y, Pt.Position.Z, Pt.RollDeg, Pt.WidthScale]));
      end;
      if Sp.ControlPointCount > 0 then
        ListBoxKnots.ItemIndex := Clamped(AKeepIdx, 0, Sp.ControlPointCount - 1);
    end;
  finally
    ListBoxKnots.Items.EndUpdate;
  end;
  ListBoxKnotsClick(nil);
end;

procedure TSplineStudioForm.RecenterCanvasOnSpline(const ASpline: TCastleSplinePath);
var
  I: Integer;
  MinX, MaxX, MinZ, MaxZ, Span: Single;
  Pt: TVector3;
begin
  if (ASpline = nil) or (ASpline.ControlPointCount = 0) then
    Exit;
  Pt := ASpline.GetControlPoint(0).Position;
  MinX := Pt.X; MaxX := Pt.X;
  MinZ := Pt.Z; MaxZ := Pt.Z;
  for I := 1 to ASpline.ControlPointCount - 1 do
  begin
    Pt := ASpline.GetControlPoint(I).Position;
    MinX := Min(MinX, Pt.X); MaxX := Max(MaxX, Pt.X);
    MinZ := Min(MinZ, Pt.Z); MaxZ := Max(MaxZ, Pt.Z);
  end;
  FCanvasCenterXZ := Vector2((MinX + MaxX) * 0.5, (MinZ + MaxZ) * 0.5);
  Span := Max(8.0, Max(MaxX - MinX, MaxZ - MinZ) * 1.35);
  FCanvasScale := Max(2.5, Min(PaintBoxCanvas.Width, PaintBoxCanvas.Height) / Span);
  if FCanvasScale <= 2.6 then
    FCanvasScale := 9.0;
end;

function TSplineStudioForm.WorldXZToCanvas(const AX, AZ: Single): TPoint;
begin
  Result.X := Round(PaintBoxCanvas.Width * 0.5 + (AX - FCanvasCenterXZ.X) * FCanvasScale);
  Result.Y := Round(PaintBoxCanvas.Height * 0.5 + (AZ - FCanvasCenterXZ.Y) * FCanvasScale);
end;

function TSplineStudioForm.CanvasToWorldXZ(const AX, AY: Integer): TVector2;
begin
  Result.X := FCanvasCenterXZ.X + (AX - PaintBoxCanvas.Width * 0.5) / Max(0.5, FCanvasScale);
  Result.Y := FCanvasCenterXZ.Y + (AY - PaintBoxCanvas.Height * 0.5) / Max(0.5, FCanvasScale);
end;

procedure TSplineStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TSplineStudioForm.SpawnPreset(const APreset: TSplinePreset;
  const ALabel: String);
var
  Sp: TCastleSplinePath;
begin
  Sp := TSplineStudioHelper.CreateSplineInDesign(
    FRootComponent, FDesignOwner, APreset, FSpawnPosition);
  if Sp <> nil then
  begin
    NotifyModified('Add ' + ALabel);
    RefreshSplineList(Sp);
  end;
end;

procedure TSplineStudioForm.ButtonSpawnRoadClick(Sender: TObject);
begin
  SpawnPreset(spWindingRoad, 'Winding Road Spline');
end;

procedure TSplineStudioForm.ButtonSpawnRiverClick(Sender: TObject);
begin
  SpawnPreset(spMeanderingRiver, 'Meandering River Spline');
end;

procedure TSplineStudioForm.ButtonSpawnCableClick(Sender: TObject);
begin
  SpawnPreset(spHangingCable, 'Hanging Cable Spline');
end;

procedure TSplineStudioForm.ButtonSpawnTrackClick(Sender: TObject);
begin
  SpawnPreset(spClosedRaceTrack, 'Closed Race Track Spline');
end;

procedure TSplineStudioForm.ButtonSnapGroundClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  Snapped: Integer;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;
  Snapped := Sp.ProjectControlPointsToWorld(60.0, 0.04);
  NotifyModified('Project Spline Knots to Floor');
  RefreshKnotList(ListBoxKnots.ItemIndex);
  PaintBoxCanvas.Invalidate;
  LabelStatus.Caption := Format('Projected %d / %d knots of "%s" onto underlying world geometry.',
    [Snapped, Sp.ControlPointCount, Sp.Name]);
end;

procedure TSplineStudioForm.ButtonAttachFollowerClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  TargetT: TCastleTransform;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;
  if (FSelectedComponent is TCastleTransform) and (FSelectedComponent <> Sp) then
  begin
    TargetT := TCastleTransform(FSelectedComponent);
    TSplineStudioHelper.AttachFollowerToTransform(TargetT, FDesignOwner, Sp.Name, 5.0);
    NotifyModified('Attach Spline Follower');
    RefreshSplineList(Sp);
    LabelStatus.Caption := Format('Attached TCastleSplineFollowerBehavior onto "%s" -> "%s".',
      [TargetT.Name, Sp.Name]);
  end else
    LabelStatus.Caption := 'Select a non-spline TCastleTransform in the Hierarchy first, then click "+ Attach Follower".';
end;

procedure TSplineStudioForm.ButtonToggleSimClick(Sender: TObject);
begin
  TimerSim.Enabled := not TimerSim.Enabled;
  if TimerSim.Enabled then
    ButtonToggleSim.Caption := 'Stop Follower Sim'
  else
    ButtonToggleSim.Caption := 'Start Follower Sim';
end;

procedure TSplineStudioForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TSplineStudioHelper.FormatSplineStudioMarkdown(FRootComponent);
  LabelStatus.Caption := 'Copied Spline Studio Markdown report to clipboard.';
end;

procedure TSplineStudioForm.ListBoxSplinesClick(Sender: TObject);
begin
  LoadActiveSplineIntoControls;
end;

procedure TSplineStudioForm.ButtonApplySplinePropsClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;
  Sp.MeshMode := TSplineMeshMode(Clamped(ComboMeshMode.ItemIndex, 0, Ord(High(TSplineMeshMode))));
  Sp.ClosedLoop := CheckClosedLoop.Checked;
  Sp.RibbonWidth := StrToFloatDefDot(EditRibbonWidth.Text, Sp.RibbonWidth);
  Sp.Tension := StrToFloatDefDot(EditTension.Text, Sp.Tension);
  Sp.RebuildTransientMesh;
  NotifyModified('Update Spline Extrusion Settings');
  RefreshSplineList(Sp);
end;

procedure TSplineStudioForm.ButtonPopulateSplineClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  Cnt: Integer;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;
  Cnt := TSplineStudioHelper.PopulateInstancesAlongSpline(
    Sp, FDesignOwner, Trim(EditScatterUrl.Text),
    StrToFloatDefDot(EditScatterSpacing.Text, 4.0),
    StrToFloatDefDot(EditScatterOffset.Text, 2.2),
    true);
  NotifyModified('Populate Instances Along Spline');
  RefreshSplineList(Sp);
  LabelStatus.Caption := Format('Spawned %d evenly-spaced instances along "%s".', [Cnt, Sp.Name]);
end;

procedure TSplineStudioForm.ButtonClearPopulatedClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  Removed: Integer;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;
  Removed := TSplineStudioHelper.ClearGeneratedSplineInstances(Sp);
  NotifyModified('Clear Generated Spline Instances');
  RefreshSplineList(Sp);
  LabelStatus.Caption := Format('Cleared %d generated instances from "%s".', [Removed, Sp.Name]);
end;

procedure TSplineStudioForm.PaintBoxCanvasPaint(Sender: TObject);
const
  CurveSamples = 96;
var
  C: TCanvas;
  W, H, G, I, SelKnot: Integer;
  Sp: TCastleSplinePath;
  S0, S1: TSplineSample;
  P0, P1, L0, R0, L1, R1: TPoint;
  Knot: TSplineControlPoint;
begin
  C := PaintBoxCanvas.Canvas;
  W := PaintBoxCanvas.Width;
  H := PaintBoxCanvas.Height;

  C.Brush.Color := $00241E1A;
  C.FillRect(0, 0, W, H);

  { Subtle grid }
  C.Pen.Color := $0038302A;
  C.Pen.Width := 1;
  G := 40;
  while G < W do
  begin
    C.MoveTo(G, 0);
    C.LineTo(G, H);
    Inc(G, 40);
  end;
  G := 40;
  while G < H do
  begin
    C.MoveTo(0, G);
    C.LineTo(W, G);
    Inc(G, 40);
  end;

  Sp := ActiveSpline;
  if (Sp = nil) or (Sp.ControlPointCount = 0) then
  begin
    C.Font.Color := $00C8C8C8;
    C.Brush.Style := bsClear;
    C.TextOut(20, 20, 'Click "+ Winding Road", "+ Meandering River", or "+ Hanging Cable" above to start.');
    Exit;
  end;

  if Sp.ControlPointCount >= 2 then
  begin
    { Ribbon width edges }
    C.Pen.Color := $006A5B44;
    C.Pen.Width := 1;
    for I := 0 to CurveSamples - 1 do
    begin
      S0 := Sp.EvaluateLocalAtNormalizedT(I / CurveSamples);
      S1 := Sp.EvaluateLocalAtNormalizedT((I + 1) / CurveSamples);
      L0 := WorldXZToCanvas(S0.Position.X - S0.Right.X * S0.Width * 0.5,
                            S0.Position.Z - S0.Right.Z * S0.Width * 0.5);
      R0 := WorldXZToCanvas(S0.Position.X + S0.Right.X * S0.Width * 0.5,
                            S0.Position.Z + S0.Right.Z * S0.Width * 0.5);
      L1 := WorldXZToCanvas(S1.Position.X - S1.Right.X * S1.Width * 0.5,
                            S1.Position.Z - S1.Right.Z * S1.Width * 0.5);
      R1 := WorldXZToCanvas(S1.Position.X + S1.Right.X * S1.Width * 0.5,
                            S1.Position.Z + S1.Right.Z * S1.Width * 0.5);
      C.MoveTo(L0.X, L0.Y); C.LineTo(L1.X, L1.Y);
      C.MoveTo(R0.X, R0.Y); C.LineTo(R1.X, R1.Y);
    end;

    { Center Catmull-Rom curve }
    C.Pen.Color := $0048D8FF;
    C.Pen.Width := 3;
    for I := 0 to CurveSamples - 1 do
    begin
      S0 := Sp.EvaluateLocalAtNormalizedT(I / CurveSamples);
      S1 := Sp.EvaluateLocalAtNormalizedT((I + 1) / CurveSamples);
      P0 := WorldXZToCanvas(S0.Position.X, S0.Position.Z);
      P1 := WorldXZToCanvas(S1.Position.X, S1.Position.Z);
      C.MoveTo(P0.X, P0.Y);
      C.LineTo(P1.X, P1.Y);
    end;
  end;

  { Control knots }
  SelKnot := ListBoxKnots.ItemIndex;
  for I := 0 to Sp.ControlPointCount - 1 do
  begin
    Knot := Sp.GetControlPoint(I);
    P0 := WorldXZToCanvas(Knot.Position.X, Knot.Position.Z);
    if I = SelKnot then
      C.Brush.Color := $0050FF78
    else
      C.Brush.Color := $00FFE066;
    C.Pen.Color := $00121212;
    C.Pen.Width := 2;
    C.Ellipse(P0.X - 6, P0.Y - 6, P0.X + 6, P0.Y + 6);
    C.Brush.Style := bsClear;
    C.Font.Color := $00F0F0F0;
    C.TextOut(P0.X + 8, P0.Y - 8, '#' + IntToStr(I));
    C.Brush.Style := bsSolid;
  end;
end;

procedure TSplineStudioForm.PaintBoxCanvasMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Sp: TCastleSplinePath;
  I, HitIdx: Integer;
  P: TPoint;
  XZ: TVector2;
  LastY: Single;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;

  if Button = mbRight then
  begin
    XZ := CanvasToWorldXZ(X, Y);
    if Sp.ControlPointCount > 0 then
      LastY := Sp.GetControlPoint(Sp.ControlPointCount - 1).Position.Y
    else
      LastY := 0.0;
    HitIdx := Sp.AddControlPoint(Vector3(XZ.X, LastY, XZ.Y), 0.0, 1.0);
    NotifyModified('Append Spline Knot');
    RefreshKnotList(HitIdx);
    PaintBoxCanvas.Invalidate;
    Exit;
  end;

  if Button = mbLeft then
  begin
    HitIdx := -1;
    for I := 0 to Sp.ControlPointCount - 1 do
    begin
      P := WorldXZToCanvas(Sp.GetControlPoint(I).Position.X,
                           Sp.GetControlPoint(I).Position.Z);
      if Sqr(X - P.X) + Sqr(Y - P.Y) <= 100 then
      begin
        HitIdx := I;
        Break;
      end;
    end;
    if HitIdx >= 0 then
    begin
      FDraggingKnotIdx := HitIdx;
      ListBoxKnots.ItemIndex := HitIdx;
      ListBoxKnotsClick(nil);
      PaintBoxCanvas.Invalidate;
    end;
  end;
end;

procedure TSplineStudioForm.PaintBoxCanvasMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  Sp: TCastleSplinePath;
  Knot: TSplineControlPoint;
  XZ: TVector2;
begin
  if FDraggingKnotIdx < 0 then
    Exit;
  Sp := ActiveSpline;
  if (Sp = nil) or (FDraggingKnotIdx >= Sp.ControlPointCount) then
    Exit;
  XZ := CanvasToWorldXZ(X, Y);
  Knot := Sp.GetControlPoint(FDraggingKnotIdx);
  Knot.Position.X := XZ.X;
  Knot.Position.Z := XZ.Y;
  Sp.SetControlPoint(FDraggingKnotIdx, Knot);
  RefreshKnotList(FDraggingKnotIdx);
  PaintBoxCanvas.Invalidate;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TSplineStudioForm.PaintBoxCanvasMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingKnotIdx >= 0 then
  begin
    FDraggingKnotIdx := -1;
    NotifyModified('Move Spline Control Knot');
  end;
end;

procedure TSplineStudioForm.ListBoxKnotsClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  Idx: Integer;
  Pt: TSplineControlPoint;
begin
  Sp := ActiveSpline;
  Idx := ListBoxKnots.ItemIndex;
  if (Sp = nil) or (Idx < 0) or (Idx >= Sp.ControlPointCount) then
    Exit;
  Pt := Sp.GetControlPoint(Idx);
  EditKnotX.Text := FormatFloat('0.##', Pt.Position.X);
  EditKnotY.Text := FormatFloat('0.##', Pt.Position.Y);
  EditKnotZ.Text := FormatFloat('0.##', Pt.Position.Z);
  EditKnotRoll.Text := FormatFloat('0.#', Pt.RollDeg);
  EditKnotWidthScale.Text := FormatFloat('0.##', Pt.WidthScale);
  PaintBoxCanvas.Invalidate;
end;

procedure TSplineStudioForm.ButtonUpdateKnotClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  Idx: Integer;
  Pt: TSplineControlPoint;
begin
  Sp := ActiveSpline;
  Idx := ListBoxKnots.ItemIndex;
  if (Sp = nil) or (Idx < 0) or (Idx >= Sp.ControlPointCount) then
    Exit;
  Pt := Sp.GetControlPoint(Idx);
  Pt.Position := Vector3(
    StrToFloatDefDot(EditKnotX.Text, Pt.Position.X),
    StrToFloatDefDot(EditKnotY.Text, Pt.Position.Y),
    StrToFloatDefDot(EditKnotZ.Text, Pt.Position.Z));
  Pt.RollDeg := StrToFloatDefDot(EditKnotRoll.Text, Pt.RollDeg);
  Pt.WidthScale := Max(0.05, StrToFloatDefDot(EditKnotWidthScale.Text, Pt.WidthScale));
  Sp.SetControlPoint(Idx, Pt);
  NotifyModified('Edit Spline Knot');
  RefreshSplineList(Sp);
  RefreshKnotList(Idx);
end;

procedure TSplineStudioForm.ButtonAddKnotClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  NewPos: TVector3;
  Idx: Integer;
begin
  Sp := ActiveSpline;
  if Sp = nil then
    Exit;
  if Sp.ControlPointCount > 0 then
    NewPos := Sp.GetControlPoint(Sp.ControlPointCount - 1).Position + Vector3(0.0, 0.0, -8.0)
  else
    NewPos := TVector3.Zero;
  Idx := Sp.AddControlPoint(NewPos, 0.0, 1.0);
  NotifyModified('Append Spline Knot');
  RefreshSplineList(Sp);
  RefreshKnotList(Idx);
end;

procedure TSplineStudioForm.ButtonDeleteKnotClick(Sender: TObject);
var
  Sp: TCastleSplinePath;
  Idx: Integer;
begin
  Sp := ActiveSpline;
  Idx := ListBoxKnots.ItemIndex;
  if (Sp = nil) or (Idx < 0) or (Idx >= Sp.ControlPointCount) then
    Exit;
  Sp.DeleteControlPoint(Idx);
  NotifyModified('Delete Spline Knot');
  RefreshSplineList(Sp);
  RefreshKnotList(Max(0, Idx - 1));
end;

procedure TSplineStudioForm.TimerSimTimer(Sender: TObject);
var
  Sum: TSplineStudioSummary;
  I: Integer;
  AnyMoved: Boolean;
begin
  Sum := TSplineStudioHelper.ScanSplines(FRootComponent);
  AnyMoved := false;
  for I := 0 to High(Sum.Followers) do
    if Sum.Followers[I].StepFollow(0.033, FRootComponent) then
      AnyMoved := true;
  if AnyMoved and Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TSplineStudioForm.ButtonCloseClick(Sender: TObject);
begin
  TimerSim.Enabled := false;
  Close;
end;

end.
