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

{ Interactive 2D Top-Down World Partition & Streaming Zones Minimap Studio
  (@link(TWorldMinimapForm)) for @link(TCastleStreamingZone) sectors
  (Phase 286 — UE 6.0 Composable Entities & Streaming Parity). }
unit FormWorldMinimap;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, Graphics, Clipbrd, Types,
  CastleVectors, CastleTransform, CastleViewport,
  CastleStreamingZone, ToolWorldStreaming;

type
  TWorldMinimapModifiedCallback = procedure (const UndoComment: String) of object;
  TWorldMinimapSelectCallback = procedure (const AComp: TComponent) of object;

  TWorldMinimapForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FViewport: TCastleViewport;
    FSelectedComponent: TComponent;
    FOnModified: TWorldMinimapModifiedCallback;
    FOnSelectComponent: TWorldMinimapSelectCallback;
    FReport: TWorldStreamingReport;

    { Minimap view state (world XZ center + meters-per-pixel scale) }
    FViewCenterX: Single;
    FViewCenterZ: Single;
    FWorldUnitsPerPixel: Single;
    FHasCustomView: Boolean;
    FLeftDraggingCamera: Boolean;
    FRightPanning: Boolean;
    FPanLastMouse: TPoint;

    { Top bar }
    LabelSummary: TLabel;
    CheckAutoSimOnTeleport: TCheckBox;
    CheckShowViewportRings: TCheckBox;

    { Split main area }
    PanelMinimapHost: TPanel;
    PaintBoxMinimap: TPaintBox;
    LabelMinimapHint: TLabel;

    PanelRightControls: TPanel;
    ListZones: TListView;

    { Selected zone quick editor }
    GroupZoneProps: TGroupBox;
    EditZoneLabel: TEdit;
    EditDesignUrl: TEdit;
    ButtonBrowseUrl: TButton;
    SpinLoadRadius: TFloatSpinEdit;
    SpinUnloadRadius: TFloatSpinEdit;
    ButtonApplyZoneProps: TButton;

    { Bottom action buttons }
    ButtonSimulateAtCam: TButton;
    ButtonLoadSelected: TButton;
    ButtonUnloadSelected: TButton;
    ButtonLoadAll: TButton;
    ButtonUnloadAll: TButton;
    ButtonNewZoneAtCam: TButton;
    ButtonJumpCamToZone: TButton;
    ButtonFitWorld: TButton;
    ButtonCopyMarkdown: TButton;
    ButtonClose: TButton;

    procedure BuildUi;
    procedure RefreshSnapshot(const AutoFitIfNeeded: Boolean = false);
    procedure FitWorldBounds;
    function SelectedZoneFromList: TCastleStreamingZone;
    procedure PopulateZoneEditorFromSelection;

    function WorldToCanvasPoint(const WX, WZ: Single): TPoint;
    procedure CanvasToWorldXZ(const PX, PY: Integer; out WX, WZ: Single);
    procedure TeleportCameraToWorldXZ(const WX, WZ: Single);

    procedure PaintBoxMinimapPaint(Sender: TObject);
    procedure PaintBoxMinimapMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMinimapMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBoxMinimapMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxMinimapMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);

    procedure ListZonesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListZonesDblClick(Sender: TObject);
    procedure ButtonBrowseUrlClick(Sender: TObject);
    procedure ButtonApplyZonePropsClick(Sender: TObject);
    procedure ButtonSimulateAtCamClick(Sender: TObject);
    procedure ButtonLoadSelectedClick(Sender: TObject);
    procedure ButtonUnloadSelectedClick(Sender: TObject);
    procedure ButtonLoadAllClick(Sender: TObject);
    procedure ButtonUnloadAllClick(Sender: TObject);
    procedure ButtonNewZoneAtCamClick(Sender: TObject);
    procedure ButtonJumpCamToZoneClick(Sender: TObject);
    procedure ButtonFitWorldClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    ShowStreamingRingsIn3D: Boolean;
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner: TComponent;
      const AViewport: TCastleViewport;
      const ASelectedComponent: TComponent;
      const AInitialShowRings: Boolean;
      const AOnModified: TWorldMinimapModifiedCallback;
      const AOnSelectComponent: TWorldMinimapSelectCallback);
    destructor Destroy; override;
  end;

implementation

uses
  Math,
  CastleUriUtils, CastleFilesUtils;

{ TWorldMinimapForm ---------------------------------------------------------- }

constructor TWorldMinimapForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner: TComponent;
  const AViewport: TCastleViewport;
  const ASelectedComponent: TComponent;
  const AInitialShowRings: Boolean;
  const AOnModified: TWorldMinimapModifiedCallback;
  const AOnSelectComponent: TWorldMinimapSelectCallback);
begin
  inherited CreateNew(AOwner);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FViewport := AViewport;
  FSelectedComponent := ASelectedComponent;
  ShowStreamingRingsIn3D := AInitialShowRings;
  FOnModified := AOnModified;
  FOnSelectComponent := AOnSelectComponent;
  FWorldUnitsPerPixel := 0.5;

  Caption := 'World Partition 2D Minimap & Streaming Zones Studio (UE 6.0 Streaming Parity)';
  Width := 1040;
  Height := 660;
  Position := poMainFormCenter;

  BuildUi;
  RefreshSnapshot(true);
end;

destructor TWorldMinimapForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TWorldMinimapForm.BuildUi;
var
  PanelTop, PanelMain, PanelBottom, Row1, Row2, RowZoneBtns: TPanel;
  SplitterMid: TSplitter;
  LblL, LblU, LblR1, LblR2: TLabel;
  Col: TListColumn;
begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Align := alTop;
  PanelTop.AutoSize := true;
  PanelTop.BevelOuter := bvNone;
  PanelTop.BorderSpacing.Around := 8;
  PanelTop.Parent := Self;

  LabelSummary := TLabel.Create(Self);
  LabelSummary.Align := alTop;
  LabelSummary.Font.Style := [fsBold];
  LabelSummary.Caption := 'Scanning World Partition...';
  LabelSummary.Parent := PanelTop;

  Row1 := TPanel.Create(Self);
  Row1.Align := alTop;
  Row1.AutoSize := true;
  Row1.BevelOuter := bvNone;
  Row1.BorderSpacing.Top := 4;
  Row1.Parent := PanelTop;

  CheckAutoSimOnTeleport := TCheckBox.Create(Self);
  CheckAutoSimOnTeleport.Align := alLeft;
  CheckAutoSimOnTeleport.Caption := 'Live-evaluate zone streaming when dragging/teleporting camera on Minimap';
  CheckAutoSimOnTeleport.Checked := true;
  CheckAutoSimOnTeleport.Parent := Row1;

  CheckShowViewportRings := TCheckBox.Create(Self);
  CheckShowViewportRings.Align := alLeft;
  CheckShowViewportRings.BorderSpacing.Left := 18;
  CheckShowViewportRings.Caption := 'Draw Load/Unload Rings in 3D Viewport';
  CheckShowViewportRings.Checked := ShowStreamingRingsIn3D;
  CheckShowViewportRings.Parent := Row1;

  { Bottom bar }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 46;
  PanelBottom.BevelOuter := bvNone;
  PanelBottom.BorderSpacing.Around := 8;
  PanelBottom.Parent := Self;

  ButtonSimulateAtCam := TButton.Create(Self);
  ButtonSimulateAtCam.Align := alLeft;
  ButtonSimulateAtCam.AutoSize := true;
  ButtonSimulateAtCam.Caption := 'Simulate Streaming at Camera';
  ButtonSimulateAtCam.OnClick := @ButtonSimulateAtCamClick;
  ButtonSimulateAtCam.Parent := PanelBottom;

  ButtonNewZoneAtCam := TButton.Create(Self);
  ButtonNewZoneAtCam.Align := alLeft;
  ButtonNewZoneAtCam.AutoSize := true;
  ButtonNewZoneAtCam.BorderSpacing.Left := 6;
  ButtonNewZoneAtCam.Caption := '+ New Zone at Camera';
  ButtonNewZoneAtCam.OnClick := @ButtonNewZoneAtCamClick;
  ButtonNewZoneAtCam.Parent := PanelBottom;

  ButtonFitWorld := TButton.Create(Self);
  ButtonFitWorld.Align := alLeft;
  ButtonFitWorld.AutoSize := true;
  ButtonFitWorld.BorderSpacing.Left := 6;
  ButtonFitWorld.Caption := 'Fit World';
  ButtonFitWorld.OnClick := @ButtonFitWorldClick;
  ButtonFitWorld.Parent := PanelBottom;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Align := alLeft;
  ButtonCopyMarkdown.AutoSize := true;
  ButtonCopyMarkdown.BorderSpacing.Left := 6;
  ButtonCopyMarkdown.Caption := 'Copy Markdown Report';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;
  ButtonCopyMarkdown.Parent := PanelBottom;

  ButtonClose := TButton.Create(Self);
  ButtonClose.Align := alRight;
  ButtonClose.Width := 92;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;
  ButtonClose.Parent := PanelBottom;

  { Center split area }
  PanelMain := TPanel.Create(Self);
  PanelMain.Align := alClient;
  PanelMain.BevelOuter := bvNone;
  PanelMain.BorderSpacing.Around := 8;
  PanelMain.Parent := Self;

  PanelRightControls := TPanel.Create(Self);
  PanelRightControls.Align := alRight;
  PanelRightControls.Width := 460;
  PanelRightControls.BevelOuter := bvNone;
  PanelRightControls.Parent := PanelMain;

  SplitterMid := TSplitter.Create(Self);
  SplitterMid.Align := alRight;
  SplitterMid.ResizeAnchor := akRight;
  SplitterMid.Parent := PanelMain;

  PanelMinimapHost := TPanel.Create(Self);
  PanelMinimapHost.Align := alClient;
  PanelMinimapHost.BevelOuter := bvLowered;
  PanelMinimapHost.Parent := PanelMain;

  LabelMinimapHint := TLabel.Create(Self);
  LabelMinimapHint.Align := alBottom;
  LabelMinimapHint.BorderSpacing.Around := 4;
  LabelMinimapHint.Caption := 'Left-Click/Drag: Teleport 3D Camera XZ  |  Right-Drag: Pan Map  |  Wheel: Zoom  |  Green=Loaded, Amber=Unloaded';
  LabelMinimapHint.Parent := PanelMinimapHost;

  PaintBoxMinimap := TPaintBox.Create(Self);
  PaintBoxMinimap.Align := alClient;
  PaintBoxMinimap.OnPaint := @PaintBoxMinimapPaint;
  PaintBoxMinimap.OnMouseDown := @PaintBoxMinimapMouseDown;
  PaintBoxMinimap.OnMouseMove := @PaintBoxMinimapMouseMove;
  PaintBoxMinimap.OnMouseUp := @PaintBoxMinimapMouseUp;
  PaintBoxMinimap.OnMouseWheel := @PaintBoxMinimapMouseWheel;
  PaintBoxMinimap.Parent := PanelMinimapHost;

  { Right controls: Zones table + quick editor + load/unload buttons }
  RowZoneBtns := TPanel.Create(Self);
  RowZoneBtns.Align := alBottom;
  RowZoneBtns.Height := 36;
  RowZoneBtns.BevelOuter := bvNone;
  RowZoneBtns.BorderSpacing.Top := 6;
  RowZoneBtns.Parent := PanelRightControls;

  ButtonLoadSelected := TButton.Create(Self);
  ButtonLoadSelected.Align := alLeft;
  ButtonLoadSelected.AutoSize := true;
  ButtonLoadSelected.Caption := 'Load Zone';
  ButtonLoadSelected.OnClick := @ButtonLoadSelectedClick;
  ButtonLoadSelected.Parent := RowZoneBtns;

  ButtonUnloadSelected := TButton.Create(Self);
  ButtonUnloadSelected.Align := alLeft;
  ButtonUnloadSelected.AutoSize := true;
  ButtonUnloadSelected.BorderSpacing.Left := 4;
  ButtonUnloadSelected.Caption := 'Unload Zone';
  ButtonUnloadSelected.OnClick := @ButtonUnloadSelectedClick;
  ButtonUnloadSelected.Parent := RowZoneBtns;

  ButtonLoadAll := TButton.Create(Self);
  ButtonLoadAll.Align := alLeft;
  ButtonLoadAll.AutoSize := true;
  ButtonLoadAll.BorderSpacing.Left := 4;
  ButtonLoadAll.Caption := 'Load All';
  ButtonLoadAll.OnClick := @ButtonLoadAllClick;
  ButtonLoadAll.Parent := RowZoneBtns;

  ButtonUnloadAll := TButton.Create(Self);
  ButtonUnloadAll.Align := alLeft;
  ButtonUnloadAll.AutoSize := true;
  ButtonUnloadAll.BorderSpacing.Left := 4;
  ButtonUnloadAll.Caption := 'Unload All';
  ButtonUnloadAll.OnClick := @ButtonUnloadAllClick;
  ButtonUnloadAll.Parent := RowZoneBtns;

  ButtonJumpCamToZone := TButton.Create(Self);
  ButtonJumpCamToZone.Align := alRight;
  ButtonJumpCamToZone.AutoSize := true;
  ButtonJumpCamToZone.Caption := 'Jump to Zone';
  ButtonJumpCamToZone.OnClick := @ButtonJumpCamToZoneClick;
  ButtonJumpCamToZone.Parent := RowZoneBtns;

  GroupZoneProps := TGroupBox.Create(Self);
  GroupZoneProps.Align := alBottom;
  GroupZoneProps.AutoSize := true;
  GroupZoneProps.Caption := 'Selected Streaming Zone Properties';
  GroupZoneProps.BorderSpacing.Top := 6;
  GroupZoneProps.Parent := PanelRightControls;

  Row1 := TPanel.Create(Self);
  Row1.Align := alTop;
  Row1.AutoSize := true;
  Row1.BevelOuter := bvNone;
  Row1.BorderSpacing.Around := 4;
  Row1.Parent := GroupZoneProps;

  LblL := TLabel.Create(Self);
  LblL.Align := alLeft;
  LblL.Caption := 'Label:';
  LblL.BorderSpacing.Right := 4;
  LblL.Parent := Row1;

  EditZoneLabel := TEdit.Create(Self);
  EditZoneLabel.Align := alLeft;
  EditZoneLabel.Width := 130;
  EditZoneLabel.Parent := Row1;

  LblU := TLabel.Create(Self);
  LblU.Align := alLeft;
  LblU.BorderSpacing.Left := 8;
  LblU.BorderSpacing.Right := 4;
  LblU.Caption := 'DesignUrl:';
  LblU.Parent := Row1;

  ButtonBrowseUrl := TButton.Create(Self);
  ButtonBrowseUrl.Align := alRight;
  ButtonBrowseUrl.Width := 32;
  ButtonBrowseUrl.Caption := '...';
  ButtonBrowseUrl.OnClick := @ButtonBrowseUrlClick;
  ButtonBrowseUrl.Parent := Row1;

  EditDesignUrl := TEdit.Create(Self);
  EditDesignUrl.Align := alClient;
  EditDesignUrl.Parent := Row1;

  Row2 := TPanel.Create(Self);
  Row2.Align := alTop;
  Row2.AutoSize := true;
  Row2.BevelOuter := bvNone;
  Row2.BorderSpacing.Around := 4;
  Row2.Parent := GroupZoneProps;

  LblR1 := TLabel.Create(Self);
  LblR1.Align := alLeft;
  LblR1.Caption := 'Load Radius (m):';
  LblR1.BorderSpacing.Right := 4;
  LblR1.Parent := Row2;

  SpinLoadRadius := TFloatSpinEdit.Create(Self);
  SpinLoadRadius.Align := alLeft;
  SpinLoadRadius.Width := 78;
  SpinLoadRadius.MinValue := 1.0;
  SpinLoadRadius.MaxValue := 100000.0;
  SpinLoadRadius.Increment := 5.0;
  SpinLoadRadius.DecimalPlaces := 1;
  SpinLoadRadius.Value := 60.0;
  SpinLoadRadius.Parent := Row2;

  LblR2 := TLabel.Create(Self);
  LblR2.Align := alLeft;
  LblR2.BorderSpacing.Left := 8;
  LblR2.BorderSpacing.Right := 4;
  LblR2.Caption := 'Unload Radius (m):';
  LblR2.Parent := Row2;

  SpinUnloadRadius := TFloatSpinEdit.Create(Self);
  SpinUnloadRadius.Align := alLeft;
  SpinUnloadRadius.Width := 78;
  SpinUnloadRadius.MinValue := 1.0;
  SpinUnloadRadius.MaxValue := 100000.0;
  SpinUnloadRadius.Increment := 5.0;
  SpinUnloadRadius.DecimalPlaces := 1;
  SpinUnloadRadius.Value := 80.0;
  SpinUnloadRadius.Parent := Row2;

  ButtonApplyZoneProps := TButton.Create(Self);
  ButtonApplyZoneProps.Align := alRight;
  ButtonApplyZoneProps.AutoSize := true;
  ButtonApplyZoneProps.Caption := 'Apply';
  ButtonApplyZoneProps.OnClick := @ButtonApplyZonePropsClick;
  ButtonApplyZoneProps.Parent := Row2;

  ListZones := TListView.Create(Self);
  ListZones.Align := alClient;
  ListZones.ViewStyle := vsReport;
  ListZones.RowSelect := true;
  ListZones.ReadOnly := true;
  ListZones.OnSelectItem := @ListZonesSelectItem;
  ListZones.OnDblClick := @ListZonesDblClick;
  ListZones.Parent := PanelRightControls;

  Col := ListZones.Columns.Add;
  Col.Caption := 'Zone';
  Col.Width := 105;

  Col := ListZones.Columns.Add;
  Col.Caption := 'Label';
  Col.Width := 95;

  Col := ListZones.Columns.Add;
  Col.Caption := 'State';
  Col.Width := 72;

  Col := ListZones.Columns.Add;
  Col.Caption := 'Load/Unload';
  Col.Width := 82;

  Col := ListZones.Columns.Add;
  Col.Caption := 'Dist';
  Col.Width := 56;

  Col := ListZones.Columns.Add;
  Col.Caption := 'DesignUrl';
  Col.Width := 150;
end;

procedure TWorldMinimapForm.FitWorldBounds;
var
  SpanX, SpanZ, MaxSpan: Single;
  W, H: Integer;
begin
  if (FReport = nil) or (not FReport.HasBounds) then
  begin
    FViewCenterX := 0;
    FViewCenterZ := 0;
    FWorldUnitsPerPixel := 0.5;
    Exit;
  end;

  FViewCenterX := (FReport.WorldMinX + FReport.WorldMaxX) * 0.5;
  FViewCenterZ := (FReport.WorldMinZ + FReport.WorldMaxZ) * 0.5;
  SpanX := Max(20.0, (FReport.WorldMaxX - FReport.WorldMinX) * 1.25);
  SpanZ := Max(20.0, (FReport.WorldMaxZ - FReport.WorldMinZ) * 1.25);
  W := Max(240, PaintBoxMinimap.Width);
  H := Max(240, PaintBoxMinimap.Height);
  MaxSpan := Max(SpanX / W, SpanZ / H);
  FWorldUnitsPerPixel := Max(0.02, MaxSpan);
  FHasCustomView := true;
end;

procedure TWorldMinimapForm.RefreshSnapshot(const AutoFitIfNeeded: Boolean);
var
  CamP, CamD, CamU: TVector3;
  HasCam: Boolean;
  PrevSelected: TCastleStreamingZone;
  Item: TListItem;
  I, SelIdx: Integer;
begin
  PrevSelected := SelectedZoneFromList;
  if (PrevSelected = nil) and (FSelectedComponent is TCastleStreamingZone) then
    PrevSelected := TCastleStreamingZone(FSelectedComponent);

  HasCam := (FViewport <> nil) and (FViewport.InternalCamera <> nil);
  if HasCam then
    FViewport.InternalCamera.GetWorldView(CamP, CamD, CamU)
  else
    CamP := TVector3.Zero;

  FreeAndNil(FReport);
  FReport := TWorldStreamingInspector.ScanWorld(FRootComponent, CamP, HasCam);

  if AutoFitIfNeeded or (not FHasCustomView) then
    FitWorldBounds;

  if HasCam then
    LabelSummary.Caption := Format(
      'Streaming Zones: %d (%d Loaded, %d Unloaded)  |  3D Footprints: %d  |  Camera XZ: (%.1f, %.1f) Y=%.1f',
      [FReport.TotalZones, FReport.LoadedZones, FReport.UnloadedZones,
       Length(FReport.Footprints), CamP.X, CamP.Z, CamP.Y])
  else
    LabelSummary.Caption := Format(
      'Streaming Zones: %d (%d Loaded, %d Unloaded)  |  3D Footprints: %d',
      [FReport.TotalZones, FReport.LoadedZones, FReport.UnloadedZones,
       Length(FReport.Footprints)]);

  SelIdx := -1;
  ListZones.Items.BeginUpdate;
  try
    ListZones.Items.Clear;
    for I := 0 to High(FReport.Zones) do
    begin
      Item := ListZones.Items.Add;
      Item.Caption := FReport.Zones[I].Name;
      Item.Data := FReport.Zones[I].Zone;
      Item.SubItems.Add(FReport.Zones[I].ZoneLabel);
      if FReport.Zones[I].IsLoaded then
        Item.SubItems.Add('LOADED')
      else
        Item.SubItems.Add('UNLOADED');
      Item.SubItems.Add(Format('%.0f / %.0fm',
        [FReport.Zones[I].LoadRadius, FReport.Zones[I].UnloadRadius]));
      if FReport.Zones[I].DistanceToObserver >= 0 then
        Item.SubItems.Add(Format('%.1fm', [FReport.Zones[I].DistanceToObserver]))
      else
        Item.SubItems.Add('-');
      Item.SubItems.Add(FReport.Zones[I].DesignUrl);

      if FReport.Zones[I].Zone = PrevSelected then
        SelIdx := I;
    end;
  finally
    ListZones.Items.EndUpdate;
  end;

  if (SelIdx < 0) and (ListZones.Items.Count > 0) then
    SelIdx := 0;
  if (SelIdx >= 0) and (SelIdx < ListZones.Items.Count) then
    ListZones.ItemIndex := SelIdx;

  PopulateZoneEditorFromSelection;
  PaintBoxMinimap.Invalidate;
end;

function TWorldMinimapForm.SelectedZoneFromList: TCastleStreamingZone;
begin
  if (ListZones <> nil) and (ListZones.Selected <> nil) and
     (TObject(ListZones.Selected.Data) is TCastleStreamingZone) then
    Result := TCastleStreamingZone(ListZones.Selected.Data)
  else
    Result := nil;
end;

procedure TWorldMinimapForm.PopulateZoneEditorFromSelection;
var
  Z: TCastleStreamingZone;
begin
  Z := SelectedZoneFromList;
  GroupZoneProps.Enabled := Z <> nil;
  ButtonLoadSelected.Enabled := Z <> nil;
  ButtonUnloadSelected.Enabled := Z <> nil;
  ButtonJumpCamToZone.Enabled := (Z <> nil) and (FViewport <> nil);
  if Z <> nil then
  begin
    EditZoneLabel.Text := Z.ZoneLabel;
    EditDesignUrl.Text := Z.DesignUrl;
    SpinLoadRadius.Value := Z.LoadRadius;
    SpinUnloadRadius.Value := Z.EffectiveUnloadRadius;
  end;
end;

function TWorldMinimapForm.WorldToCanvasPoint(const WX, WZ: Single): TPoint;
var
  CX, CY: Single;
begin
  CX := PaintBoxMinimap.Width * 0.5 + (WX - FViewCenterX) / FWorldUnitsPerPixel;
  CY := PaintBoxMinimap.Height * 0.5 + (WZ - FViewCenterZ) / FWorldUnitsPerPixel;
  Result := Point(Round(CX), Round(CY));
end;

procedure TWorldMinimapForm.CanvasToWorldXZ(const PX, PY: Integer;
  out WX, WZ: Single);
begin
  WX := FViewCenterX + (PX - PaintBoxMinimap.Width * 0.5) * FWorldUnitsPerPixel;
  WZ := FViewCenterZ + (PY - PaintBoxMinimap.Height * 0.5) * FWorldUnitsPerPixel;
end;

procedure TWorldMinimapForm.TeleportCameraToWorldXZ(const WX, WZ: Single);
var
  CamP, CamD, CamU: TVector3;
begin
  if (FViewport = nil) or (FViewport.InternalCamera = nil) then
    Exit;
  FViewport.InternalCamera.GetWorldView(CamP, CamD, CamU);
  CamP.X := WX;
  CamP.Z := WZ;
  FViewport.InternalCamera.SetWorldView(CamP, CamD, CamU);

  if CheckAutoSimOnTeleport.Checked then
    TWorldStreamingInspector.SimulateObserverAcrossWorld(FRootComponent, CamP);

  RefreshSnapshot(false);
end;

procedure TWorldMinimapForm.PaintBoxMinimapPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, I, LoadPix, UnloadPix: Integer;
  GridStep, StartX, StartZ, GX, GZ: Single;
  P1, P2, PCam, PDirL, PDirR: TPoint;
  CamP, CamD, CamU, FlatDir, RightDir: TVector3;
  SelZone: TCastleStreamingZone;
  ZoneTitle: String;
begin
  C := PaintBoxMinimap.Canvas;
  W := PaintBoxMinimap.Width;
  H := PaintBoxMinimap.Height;

  { Dark slate radar background }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(18, 23, 32);
  C.FillRect(0, 0, W, H);

  { Adaptive XZ coordinate grid }
  GridStep := Power(10, Floor(Log10(Max(1.0, FWorldUnitsPerPixel * 90.0))));
  if (GridStep / FWorldUnitsPerPixel) < 45 then
    GridStep := GridStep * 2.0;
  if (GridStep / FWorldUnitsPerPixel) > 180 then
    GridStep := GridStep * 0.5;

  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(34, 43, 58);

  StartX := Floor((FViewCenterX - W * 0.5 * FWorldUnitsPerPixel) / GridStep) * GridStep;
  GX := StartX;
  while GX <= FViewCenterX + W * 0.5 * FWorldUnitsPerPixel do
  begin
    P1 := WorldToCanvasPoint(GX, FViewCenterZ);
    if Abs(GX) < 0.001 then
      C.Pen.Color := RGBToColor(90, 50, 55)
    else
      C.Pen.Color := RGBToColor(34, 43, 58);
    C.Line(P1.X, 0, P1.X, H);
    GX := GX + GridStep;
  end;

  StartZ := Floor((FViewCenterZ - H * 0.5 * FWorldUnitsPerPixel) / GridStep) * GridStep;
  GZ := StartZ;
  while GZ <= FViewCenterZ + H * 0.5 * FWorldUnitsPerPixel do
  begin
    P1 := WorldToCanvasPoint(FViewCenterX, GZ);
    if Abs(GZ) < 0.001 then
      C.Pen.Color := RGBToColor(45, 70, 105)
    else
      C.Pen.Color := RGBToColor(34, 43, 58);
    C.Line(0, P1.Y, W, P1.Y);
    GZ := GZ + GridStep;
  end;

  if FReport <> nil then
  begin
    { 1. Draw 3D Transform top-down XZ bounding boxes }
    for I := 0 to High(FReport.Footprints) do
    begin
      if FReport.Footprints[I].IsStreamingZone then
        Continue;
      P1 := WorldToCanvasPoint(
        FReport.Footprints[I].WorldBox.Data[0].X,
        FReport.Footprints[I].WorldBox.Data[0].Z);
      P2 := WorldToCanvasPoint(
        FReport.Footprints[I].WorldBox.Data[1].X,
        FReport.Footprints[I].WorldBox.Data[1].Z);

      if FReport.Footprints[I].Transform = FSelectedComponent then
      begin
        C.Brush.Style := bsSolid;
        C.Brush.Color := RGBToColor(40, 110, 155);
        C.Pen.Color := RGBToColor(95, 220, 255);
      end else
      begin
        C.Brush.Style := bsSolid;
        C.Brush.Color := RGBToColor(42, 54, 72);
        C.Pen.Color := RGBToColor(78, 96, 124);
      end;
      C.Rectangle(Min(P1.X, P2.X) - 1, Min(P1.Y, P2.Y) - 1,
        Max(P1.X, P2.X) + 2, Max(P1.Y, P2.Y) + 2);
    end;

    { 2. Draw TCastleStreamingZone LoadRadius & UnloadRadius hysteresis rings }
    SelZone := SelectedZoneFromList;
    for I := 0 to High(FReport.Zones) do
    begin
      P1 := WorldToCanvasPoint(FReport.Zones[I].WorldPos.X, FReport.Zones[I].WorldPos.Z);
      LoadPix := Max(4, Round(FReport.Zones[I].LoadRadius / FWorldUnitsPerPixel));
      UnloadPix := Max(LoadPix, Round(FReport.Zones[I].UnloadRadius / FWorldUnitsPerPixel));

      { Outer UnloadRadius hysteresis dashed circle }
      C.Brush.Style := bsClear;
      C.Pen.Style := psDash;
      C.Pen.Width := 1;
      C.Pen.Color := RGBToColor(110, 145, 185);
      C.Ellipse(P1.X - UnloadPix, P1.Y - UnloadPix, P1.X + UnloadPix, P1.Y + UnloadPix);

      { Inner LoadRadius solid circle }
      C.Pen.Style := psSolid;
      if FReport.Zones[I].Zone = SelZone then
        C.Pen.Width := 3
      else
        C.Pen.Width := 2;

      if FReport.Zones[I].IsLoaded then
        C.Pen.Color := RGBToColor(46, 230, 155)
      else
        C.Pen.Color := RGBToColor(240, 172, 56);
      C.Ellipse(P1.X - LoadPix, P1.Y - LoadPix, P1.X + LoadPix, P1.Y + LoadPix);

      { Zone center anchor & label }
      C.Brush.Style := bsSolid;
      C.Brush.Color := C.Pen.Color;
      C.FillRect(P1.X - 3, P1.Y - 3, P1.X + 4, P1.Y + 4);

      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(225, 236, 248);
      if Trim(FReport.Zones[I].ZoneLabel) <> '' then
        ZoneTitle := FReport.Zones[I].ZoneLabel
      else
        ZoneTitle := FReport.Zones[I].Name;
      C.TextOut(P1.X + 6, P1.Y - 8, ZoneTitle);
    end;
  end;

  { 3. Draw Live 3D Viewport Camera + Forward View Frustum Cone }
  if (FViewport <> nil) and (FViewport.InternalCamera <> nil) then
  begin
    FViewport.InternalCamera.GetWorldView(CamP, CamD, CamU);
    PCam := WorldToCanvasPoint(CamP.X, CamP.Z);
    FlatDir := Vector3(CamD.X, 0, CamD.Z);
    if FlatDir.LengthSqr < 0.0001 then
      FlatDir := Vector3(0, 0, -1)
    else
      FlatDir := FlatDir.Normalize;
    RightDir := Vector3(-FlatDir.Z, 0, FlatDir.X);

    PDirL := Point(
      PCam.X + Round((FlatDir.X * 28 - RightDir.X * 16)),
      PCam.Y + Round((FlatDir.Z * 28 - RightDir.Z * 16)));
    PDirR := Point(
      PCam.X + Round((FlatDir.X * 28 + RightDir.X * 16)),
      PCam.Y + Round((FlatDir.Z * 28 + RightDir.Z * 16)));

    C.Pen.Style := psSolid;
    C.Pen.Width := 2;
    C.Pen.Color := RGBToColor(90, 210, 255);
    C.Line(PCam.X, PCam.Y, PDirL.X, PDirL.Y);
    C.Line(PCam.X, PCam.Y, PDirR.X, PDirR.Y);
    C.Line(PDirL.X, PDirL.Y, PDirR.X, PDirR.Y);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(255, 255, 255);
    C.Ellipse(PCam.X - 5, PCam.Y - 5, PCam.X + 5, PCam.Y + 5);
  end;

  { Scale legend in top-left corner }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(14, 18, 25);
  C.FillRect(8, 8, 178, 30);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(180, 205, 230);
  C.TextOut(14, 12, Format('Grid: %.0fm  (%.2fm/px)', [GridStep, FWorldUnitsPerPixel]));
end;

procedure TWorldMinimapForm.PaintBoxMinimapMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  WX, WZ: Single;
begin
  if Button = mbLeft then
  begin
    FLeftDraggingCamera := true;
    CanvasToWorldXZ(X, Y, WX, WZ);
    TeleportCameraToWorldXZ(WX, WZ);
  end else
  if Button in [mbRight, mbMiddle] then
  begin
    FRightPanning := true;
    FPanLastMouse := Point(X, Y);
  end;
end;

procedure TWorldMinimapForm.PaintBoxMinimapMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  WX, WZ: Single;
begin
  if FLeftDraggingCamera then
  begin
    CanvasToWorldXZ(X, Y, WX, WZ);
    TeleportCameraToWorldXZ(WX, WZ);
  end else
  if FRightPanning then
  begin
    FViewCenterX := FViewCenterX - (X - FPanLastMouse.X) * FWorldUnitsPerPixel;
    FViewCenterZ := FViewCenterZ - (Y - FPanLastMouse.Y) * FWorldUnitsPerPixel;
    FPanLastMouse := Point(X, Y);
    FHasCustomView := true;
    PaintBoxMinimap.Invalidate;
  end;
end;

procedure TWorldMinimapForm.PaintBoxMinimapMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    FLeftDraggingCamera := false;
  if Button in [mbRight, mbMiddle] then
    FRightPanning := false;
end;

procedure TWorldMinimapForm.PaintBoxMinimapMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
  var Handled: Boolean);
begin
  if WheelDelta > 0 then
    FWorldUnitsPerPixel := Max(0.01, FWorldUnitsPerPixel * 0.82)
  else
    FWorldUnitsPerPixel := Min(200.0, FWorldUnitsPerPixel * 1.22);
  FHasCustomView := true;
  Handled := true;
  PaintBoxMinimap.Invalidate;
end;

procedure TWorldMinimapForm.ListZonesSelectItem(Sender: TObject;
  Item: TListItem; Selected: Boolean);
begin
  PopulateZoneEditorFromSelection;
  PaintBoxMinimap.Invalidate;
  if Selected and (SelectedZoneFromList <> nil) and Assigned(FOnSelectComponent) then
    FOnSelectComponent(SelectedZoneFromList);
end;

procedure TWorldMinimapForm.ListZonesDblClick(Sender: TObject);
begin
  ButtonJumpCamToZoneClick(Sender);
end;

procedure TWorldMinimapForm.ButtonBrowseUrlClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Choose Sub-Design (.castle-transform) or 3D Model to Stream';
    Dlg.Filter := 'Castle Transform Designs (*.castle-transform)|*.castle-transform|All Files (*.*)|*.*';
    Dlg.InitialDir := UriToFilenameSafe('castle-data:/');
    if Dlg.Execute then
      EditDesignUrl.Text := MaybeUseDataProtocol(FilenameToUriSafe(Dlg.FileName));
  finally
    FreeAndNil(Dlg);
  end;
end;

procedure TWorldMinimapForm.ButtonApplyZonePropsClick(Sender: TObject);
var
  Z: TCastleStreamingZone;
begin
  Z := SelectedZoneFromList;
  if Z = nil then
    Exit;
  Z.ZoneLabel := Trim(EditZoneLabel.Text);
  Z.LoadRadius := SpinLoadRadius.Value;
  Z.UnloadRadius := Max(SpinLoadRadius.Value, SpinUnloadRadius.Value);
  Z.DesignUrl := Trim(EditDesignUrl.Text);
  if Assigned(FOnModified) then
    FOnModified('Configure Streaming Zone ' + Z.Name);
  RefreshSnapshot(false);
end;

procedure TWorldMinimapForm.ButtonSimulateAtCamClick(Sender: TObject);
var
  CamP, CamD, CamU: TVector3;
begin
  if (FViewport = nil) or (FViewport.InternalCamera = nil) then
    Exit;
  FViewport.InternalCamera.GetWorldView(CamP, CamD, CamU);
  TWorldStreamingInspector.SimulateObserverAcrossWorld(FRootComponent, CamP);
  RefreshSnapshot(false);
end;

procedure TWorldMinimapForm.ButtonLoadSelectedClick(Sender: TObject);
var
  Z: TCastleStreamingZone;
begin
  Z := SelectedZoneFromList;
  if Z <> nil then
  begin
    Z.LoadZoneNow;
    RefreshSnapshot(false);
  end;
end;

procedure TWorldMinimapForm.ButtonUnloadSelectedClick(Sender: TObject);
var
  Z: TCastleStreamingZone;
begin
  Z := SelectedZoneFromList;
  if Z <> nil then
  begin
    Z.UnloadZoneNow;
    RefreshSnapshot(false);
  end;
end;

procedure TWorldMinimapForm.ButtonLoadAllClick(Sender: TObject);
begin
  TWorldStreamingInspector.LoadAllZonesForPreview(FRootComponent);
  RefreshSnapshot(false);
end;

procedure TWorldMinimapForm.ButtonUnloadAllClick(Sender: TObject);
begin
  TWorldStreamingInspector.UnloadAllZones(FRootComponent);
  RefreshSnapshot(false);
end;

procedure TWorldMinimapForm.ButtonNewZoneAtCamClick(Sender: TObject);
var
  ParentT: TCastleTransform;
  CamP, CamD, CamU, SpawnPos: TVector3;
  NewZone: TCastleStreamingZone;
begin
  ParentT := nil;
  if (FViewport <> nil) and (FViewport.Items <> nil) then
    ParentT := FViewport.Items
  else if FRootComponent is TCastleTransform then
    ParentT := TCastleTransform(FRootComponent);
  if ParentT = nil then
    Exit;

  if (FViewport <> nil) and (FViewport.InternalCamera <> nil) then
  begin
    FViewport.InternalCamera.GetWorldView(CamP, CamD, CamU);
    SpawnPos := Vector3(CamP.X, 0.0, CamP.Z);
  end else
    SpawnPos := TVector3.Zero;

  NewZone := TWorldStreamingInspector.CreateStreamingZoneAtPosition(
    ParentT, FDesignOwner, SpawnPos, '', 60.0, 80.0);
  if NewZone <> nil then
  begin
    NewZone.ZoneLabel := NewZone.Name;
    FSelectedComponent := NewZone;
    if Assigned(FOnModified) then
      FOnModified('Create Streaming Zone ' + NewZone.Name);
    if Assigned(FOnSelectComponent) then
      FOnSelectComponent(NewZone);
    RefreshSnapshot(true);
  end;
end;

procedure TWorldMinimapForm.ButtonJumpCamToZoneClick(Sender: TObject);
var
  Z: TCastleStreamingZone;
  WPos: TVector3;
begin
  Z := SelectedZoneFromList;
  if Z = nil then
    Exit;
  if Z.World <> nil then
    WPos := Z.LocalToWorld(TVector3.Zero)
  else
    WPos := Z.Translation;
  TeleportCameraToWorldXZ(WPos.X, WPos.Z);
end;

procedure TWorldMinimapForm.ButtonFitWorldClick(Sender: TObject);
begin
  FitWorldBounds;
  PaintBoxMinimap.Invalidate;
end;

procedure TWorldMinimapForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  if FReport <> nil then
    Clipboard.AsText := FReport.FormatMarkdownSummary;
end;

procedure TWorldMinimapForm.ButtonCloseClick(Sender: TObject);
begin
  ShowStreamingRingsIn3D := CheckShowViewportRings.Checked;
  ModalResult := mrOk;
end;

end.