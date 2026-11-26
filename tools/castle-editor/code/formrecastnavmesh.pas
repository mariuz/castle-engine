{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style 3D Polygonal Recast NavMesh Volume & NavLinkProxy
  Studio featuring a Top-Down Multi-Floor P-Key NavMesh Polygon Canvas, an X-Y
  Elevation Stacked Bridge/Underpass Headroom Cross-Section, ANavLinkProxy
  Jump/Drop Inspector, and Portal-Smoothed 3D A* Path Visualizer
  (Phase 393 — 113 UE Studios / 36 MCP). }
unit FormRecastNavMesh;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleRecastNavMesh, ToolRecastNavMesh;

type
  TRecastModifiedCallback = procedure(const UndoComment: String) of object;
  TRecastRefreshCallback = procedure of object;

  TRecastNavMeshForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TRecastModifiedCallback;
    FOnRefresh: TRecastRefreshCallback;

    FActiveNav: TCastleRecastNavMesh;

    FLblStatus: TLabel;
    FPaintTopAndSide: TPaintBox;
    FPaintInspector: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintMultiFloorNavMeshCanvas(Sender: TObject);
    procedure PaintAgentAndNavLinkInspector(Sender: TObject);

    procedure BtnSpawnBridgeClick(Sender: TObject);
    procedure BtnSpawnKeepClick(Sender: TObject);
    procedure BtnPathClimbUpClick(Sender: TObject);
    procedure BtnPathDropDownClick(Sender: TObject);
    procedure BtnHumanHeightClick(Sender: TObject);
    procedure BtnOgreHeightClick(Sender: TObject);
    procedure BtnToggleJumpLinkClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TRecastModifiedCallback;
      const AOnRefresh: TRecastRefreshCallback);
  end;

implementation

constructor TRecastNavMeshForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TRecastModifiedCallback;
  const AOnRefresh: TRecastRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := '3D Polygonal Recast NavMesh Volume & NavLinkProxy Studio (113 UE Studios / 36 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveNav := TRecastNavMeshHelper.FindFirstRecastNavMesh(FDesignRoot);
  RefreshFromScene;
end;

procedure TRecastNavMeshForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnBridge, BtnKeep, BtnClimb, BtnDrop, BtnHuman, BtnOgre,
    BtnToggleLink, BtnCopy, BtnClose: TButton;
  XPos: Integer;

  function MakeToolbarBtn(const ACaption: String; const AWidth: Integer;
    const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PnlToolbar;
    Result.Left := XPos;
    Result.Top := 6;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    Inc(XPos, AWidth + 6);
  end;

begin
  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;
  PnlToolbar.Color := RGBToColor(34, 37, 45);

  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Top := 0;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := RGBToColor(26, 28, 34);
  PnlToolbar.Top := 32;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 12;
  FLblStatus.Top := 8;
  FLblStatus.Font.Color := RGBToColor(225, 232, 245);
  FLblStatus.Font.Style := [fsBold];
  FLblStatus.Caption := '3D Polygonal Recast NavMesh & NavLinkProxy Studio Ready.';

  XPos := 8;
  BtnBridge := MakeToolbarBtn('+ 2-Story Bridge', 136, @BtnSpawnBridgeClick);
  BtnKeep := MakeToolbarBtn('+ 3-Floor Keep', 124, @BtnSpawnKeepClick);
  BtnClimb := MakeToolbarBtn('Path: Ground -> Bastion', 180, @BtnPathClimbUpClick);
  BtnDrop := MakeToolbarBtn('Path: Bastion Drop', 156, @BtnPathDropDownClick);
  BtnHuman := MakeToolbarBtn('Human (H=1.8m)', 132, @BtnHumanHeightClick);
  BtnOgre := MakeToolbarBtn('Ogre H=2.8m (Block)', 166, @BtnOgreHeightClick);
  BtnToggleLink := MakeToolbarBtn('Toggle Jump Link', 142, @BtnToggleJumpLinkClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 102, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 68, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnBridge <> nil) and (BtnKeep <> nil) and (BtnClimb <> nil) and
     (BtnDrop <> nil) and (BtnHuman <> nil) and (BtnOgre <> nil) and
     (BtnToggleLink <> nil) and (BtnCopy <> nil) then ;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 128;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.Font.Name := 'Consolas';
  FMemoReport.Font.Size := 9;
  FMemoReport.Color := RGBToColor(18, 20, 26);
  FMemoReport.Font.Color := RGBToColor(208, 218, 232);

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 574;
  PnlRight.BevelOuter := bvNone;

  FPaintInspector := TPaintBox.Create(Self);
  FPaintInspector.Parent := PnlRight;
  FPaintInspector.Align := alClient;
  FPaintInspector.OnPaint := @PaintAgentAndNavLinkInspector;

  FPaintTopAndSide := TPaintBox.Create(Self);
  FPaintTopAndSide.Parent := Self;
  FPaintTopAndSide.Align := alClient;
  FPaintTopAndSide.OnPaint := @PaintMultiFloorNavMeshCanvas;
end;

procedure TRecastNavMeshForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TRecastNavMeshForm.RefreshFromScene;
begin
  if FActiveNav = nil then
    FActiveNav := TRecastNavMeshHelper.FindFirstRecastNavMesh(FDesignRoot);

  if FActiveNav <> nil then
    FLblStatus.Caption := Format(
      'Active: %s  |  Polys: %d (%d Tris, %.0f m^2)  |  Stacked Floors: %d  |  NavLinks: %d  |  3D Path: %s (%.1fm, %d Links)',
      [FActiveNav.NavVolumeKey,
       Length(FActiveNav.Polys),
       FActiveNav.TotalNavTriangles,
       FActiveNav.TotalWalkableAreaM2,
       FActiveNav.CountStackedMultiFloorPairs,
       Length(FActiveNav.NavLinks),
       BoolToStr(FActiveNav.LastPath.Found, 'FOUND', 'UNREACHABLE'),
       FActiveNav.LastPath.TotalDistanceM,
       FActiveNav.LastPath.UsedLinkCount])
  else
    FLblStatus.Caption := 'No TCastleRecastNavMesh in scene — click "+ 2-Story Bridge" to build multi-floor NavMesh.';

  FMemoReport.Lines.Text := TRecastNavMeshHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveNav);

  FPaintTopAndSide.Invalidate;
  FPaintInspector.Invalidate;
end;

procedure TRecastNavMeshForm.PaintMultiFloorNavMeshCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, SplitY, TopCX, TopCY, SideBaseY, I, X1, Y1, X2, Y2, PX, PY, QX, QY: Integer;
  ScaleXZ, ScaleSideX, ScaleSideY: Single;

  function MapTopX(const WX: Single): Integer;
  begin
    Result := TopCX + Round(WX * ScaleXZ);
  end;

  function MapTopZ(const WZ: Single): Integer;
  begin
    Result := TopCY + Round(WZ * ScaleXZ);
  end;

  function MapSideX(const WX: Single): Integer;
  begin
    Result := TopCX + Round(WX * ScaleSideX);
  end;

  function MapSideY(const WY: Single): Integer;
  begin
    Result := SideBaseY - Round(WY * ScaleSideY);
  end;

begin
  C := FPaintTopAndSide.Canvas;
  W := Max(360, FPaintTopAndSide.Width);
  H := Max(340, FPaintTopAndSide.Height);
  SplitY := Round(H * 0.60);

  C.Brush.Color := RGBToColor(18, 22, 28);
  C.FillRect(0, 0, W, H);

  { Top Pane Header: Top-Down Multi-Floor P-Key Recast NavMesh }
  C.Brush.Color := RGBToColor(28, 36, 44);
  C.FillRect(0, 0, W, 28);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(112, 242, 168);
  C.TextOut(12, 6, 'Top-Down 3D Recast NavMesh  (Floor 0 Green | Upper Deck Teal | Gold = Funnel A*)');
  C.Font.Style := [];

  { Bottom Pane Header: X-Y Side Elevation Multi-Story Headroom Cross-Section }
  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, SplitY, W, SplitY + 28);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(134, 204, 255);
  C.TextOut(12, SplitY + 6, 'X-Y Side Elevation  (Stacked Underpass Headroom + Stair Ramp + One-Way Drop & Jump Links)');
  C.Font.Style := [];

  if FActiveNav = nil then Exit;

  TopCX := W div 2;
  TopCY := 28 + (SplitY - 28) div 2;
  ScaleXZ := Min((W - 72) / 22.0, (SplitY - 56) / 11.5);

  { 1. Rejected steep slopes (> MaxSlopeDeg) shown in dark crimson outline }
  for I := 0 to High(FActiveNav.SourceSlabs) do
    if FActiveNav.SourceSlabs[I].SlopeDeg > FActiveNav.AgentMaxSlopeDeg then
    begin
      X1 := MapTopX(FActiveNav.SourceSlabs[I].BoundsMin.X);
      Y1 := MapTopZ(FActiveNav.SourceSlabs[I].BoundsMin.Z);
      X2 := MapTopX(FActiveNav.SourceSlabs[I].BoundsMax.X);
      Y2 := MapTopZ(FActiveNav.SourceSlabs[I].BoundsMax.Z);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(68, 28, 32);
      C.Pen.Color := RGBToColor(218, 78, 86);
      C.Rectangle(X1, Y1, X2, Y2);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(255, 152, 158);
      C.TextOut(X1 + 4, Y1 + 4, Format('Rejected %.0f deg',
        [FActiveNav.SourceSlabs[I].SlopeDeg]));
    end;

  { 2. Walkable Ground-Floor Polygons first, then Upper-Floor Polygons }
  for I := 0 to High(FActiveNav.Polys) do
    if FActiveNav.Polys[I].FloorTier = 0 then
    begin
      X1 := MapTopX(FActiveNav.Polys[I].MinXZ.X);
      Y1 := MapTopZ(FActiveNav.Polys[I].MinXZ.Y);
      X2 := MapTopX(FActiveNav.Polys[I].MaxXZ.X);
      Y2 := MapTopZ(FActiveNav.Polys[I].MaxXZ.Y);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(28, 92, 54);
      C.Pen.Color := RGBToColor(82, 212, 128);
      C.Rectangle(X1, Y1, X2, Y2);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(186, 242, 204);
      if (X2 - X1 > 70) and (Y2 - Y1 > 20) then
        C.TextOut(X1 + 6, Y2 - 18, FActiveNav.Polys[I].SourceSlabName);
    end;

  for I := 0 to High(FActiveNav.Polys) do
    if FActiveNav.Polys[I].FloorTier > 0 then
    begin
      X1 := MapTopX(FActiveNav.Polys[I].MinXZ.X);
      Y1 := MapTopZ(FActiveNav.Polys[I].MinXZ.Y);
      X2 := MapTopX(FActiveNav.Polys[I].MaxXZ.X);
      Y2 := MapTopZ(FActiveNav.Polys[I].MaxXZ.Y);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(34, 122, 112);
      C.Pen.Color := RGBToColor(112, 252, 224);
      C.Pen.Width := 2;
      C.Rectangle(X1, Y1, X2, Y2);
      C.Pen.Width := 1;
      C.Brush.Style := bsClear;
      C.Font.Style := [fsBold];
      C.Font.Color := RGBToColor(220, 255, 246);
      if (X2 - X1 > 70) and (Y2 - Y1 > 20) then
        C.TextOut(X1 + 6, Y1 + 5, FActiveNav.Polys[I].SourceSlabName +
          Format(' (Y=%.1fm)', [FActiveNav.Polys[I].ElevMaxY]));
      C.Font.Style := [];
    end;

  { 3. ANavLinkProxy Links in Top-Down View }
  for I := 0 to High(FActiveNav.NavLinks) do
  begin
    PX := MapTopX(FActiveNav.NavLinks[I].LeftPos.X);
    PY := MapTopZ(FActiveNav.NavLinks[I].LeftPos.Z);
    QX := MapTopX(FActiveNav.NavLinks[I].RightPos.X);
    QY := MapTopZ(FActiveNav.NavLinks[I].RightPos.Z);
    if not FActiveNav.NavLinks[I].Enabled then
      C.Pen.Color := RGBToColor(110, 115, 128)
    else if FActiveNav.NavLinks[I].Direction = nldBothWays then
      C.Pen.Color := RGBToColor(96, 218, 255)
    else
      C.Pen.Color := RGBToColor(255, 168, 72);
    C.Pen.Width := 3;
    C.MoveTo(PX, PY);
    C.LineTo(QX, QY);
    C.Pen.Width := 1;
    C.Brush.Style := bsSolid;
    C.Brush.Color := C.Pen.Color;
    C.Ellipse(PX - 5, PY - 5, PX + 5, PY + 5);
    C.Ellipse(QX - 5, QY - 5, QX + 5, QY + 5);
  end;

  { 4. Golden Portal-Smoothed 3D A* Path in Top-Down View }
  if FActiveNav.LastPath.Found and (Length(FActiveNav.LastPath.Points) >= 2) then
  begin
    for I := 1 to High(FActiveNav.LastPath.Points) do
    begin
      PX := MapTopX(FActiveNav.LastPath.Points[I - 1].Position.X);
      PY := MapTopZ(FActiveNav.LastPath.Points[I - 1].Position.Z);
      QX := MapTopX(FActiveNav.LastPath.Points[I].Position.X);
      QY := MapTopZ(FActiveNav.LastPath.Points[I].Position.Z);
      if FActiveNav.LastPath.Points[I].ViaNavLink then
        C.Pen.Color := RGBToColor(102, 232, 255)
      else
        C.Pen.Color := RGBToColor(255, 214, 68);
      C.Pen.Width := 3;
      C.MoveTo(PX, PY);
      C.LineTo(QX, QY);
      C.Pen.Width := 1;
    end;
    for I := 0 to High(FActiveNav.LastPath.Points) do
    begin
      PX := MapTopX(FActiveNav.LastPath.Points[I].Position.X);
      PY := MapTopZ(FActiveNav.LastPath.Points[I].Position.Z);
      C.Brush.Style := bsSolid;
      if I = 0 then
        C.Brush.Color := RGBToColor(82, 246, 138)
      else if I = High(FActiveNav.LastPath.Points) then
        C.Brush.Color := RGBToColor(255, 96, 108)
      else
        C.Brush.Color := RGBToColor(255, 224, 92);
      C.Pen.Color := clWhite;
      C.Ellipse(PX - 5, PY - 5, PX + 5, PY + 5);
    end;
  end;

  { 5. Bottom X-Y Side-Elevation Cross-Section (Stacked Bridge Over Underpass) }
  SideBaseY := H - 30;
  ScaleSideX := (W - 72) / 22.0;
  ScaleSideY := Max(18.0, (H - SplitY - 76) / 6.8);

  { Draw architectural slabs in X-Y side profile }
  for I := 0 to High(FActiveNav.SourceSlabs) do
  begin
    X1 := MapSideX(FActiveNav.SourceSlabs[I].BoundsMin.X);
    X2 := MapSideX(FActiveNav.SourceSlabs[I].BoundsMax.X);
    if FActiveNav.SourceSlabs[I].IsRampX then
    begin
      C.Pen.Color := RGBToColor(112, 242, 186);
      C.Pen.Width := 3;
      C.MoveTo(X1, MapSideY(FActiveNav.SourceSlabs[I].RampStartTopY));
      C.LineTo(X2, MapSideY(FActiveNav.SourceSlabs[I].RampEndTopY));
      C.Pen.Width := 1;
    end else
    if FActiveNav.SourceSlabs[I].SlopeDeg <= FActiveNav.AgentMaxSlopeDeg then
    begin
      Y1 := MapSideY(FActiveNav.SourceSlabs[I].BoundsMax.Y);
      Y2 := MapSideY(FActiveNav.SourceSlabs[I].BoundsMin.Y);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(46, 54, 70);
      C.Pen.Color := RGBToColor(96, 224, 152);
      C.Rectangle(X1, Y1, X2, Max(Y1 + 5, Y2));
    end;
  end;

  { Draw Side-Profile 3D Path + NavLink Arcs }
  if FActiveNav.LastPath.Found and (Length(FActiveNav.LastPath.Points) >= 2) then
    for I := 1 to High(FActiveNav.LastPath.Points) do
    begin
      PX := MapSideX(FActiveNav.LastPath.Points[I - 1].Position.X);
      PY := MapSideY(FActiveNav.LastPath.Points[I - 1].Position.Y) - 4;
      QX := MapSideX(FActiveNav.LastPath.Points[I].Position.X);
      QY := MapSideY(FActiveNav.LastPath.Points[I].Position.Y) - 4;
      if FActiveNav.LastPath.Points[I].ViaNavLink then
        C.Pen.Color := RGBToColor(102, 232, 255)
      else
        C.Pen.Color := RGBToColor(255, 214, 68);
      C.Pen.Width := 3;
      C.MoveTo(PX, PY);
      C.LineTo(QX, QY);
      C.Pen.Width := 1;
    end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(190, 208, 232);
  C.TextOut(18, H - 22, Format(
    'Agent Capsule: Radius=%.2fm  Height=%.2fm  MaxSlope=%.0f deg  MaxStep=%.2fm  |  Stacked XZ Overlaps: %d',
    [FActiveNav.AgentRadius, FActiveNav.AgentHeight,
     FActiveNav.AgentMaxSlopeDeg, FActiveNav.AgentMaxStepHeight,
     FActiveNav.CountStackedMultiFloorPairs]));
  C.Brush.Style := bsSolid;
end;

procedure TRecastNavMeshForm.PaintAgentAndNavLinkInspector(Sender: TObject);
var
  C: TCanvas;
  W, H, I, RowY, PathTopY: Integer;
  DirStr, StateStr: String;
begin
  C := FPaintInspector.Canvas;
  W := Max(340, FPaintInspector.Width);
  H := Max(340, FPaintInspector.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 212, 112);
  C.TextOut(12, 7, 'ANavLinkProxy Off-Mesh Links & Recast Agent Parameters');
  C.Font.Style := [];

  if FActiveNav = nil then Exit;

  { Agent Parameter Summary Card }
  C.Brush.Color := RGBToColor(28, 33, 44);
  C.Pen.Color := RGBToColor(68, 82, 108);
  C.RoundRect(12, 40, W - 12, 96, 8, 8);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(225, 234, 248);
  C.TextOut(22, 48, Format(
    'AgentRadius: %.2fm   |   AgentHeight: %.2fm   |   MaxSlope: %.0f deg',
    [FActiveNav.AgentRadius, FActiveNav.AgentHeight, FActiveNav.AgentMaxSlopeDeg]));
  C.Font.Color := RGBToColor(124, 234, 172);
  C.TextOut(22, 71, Format(
    'MaxStepHeight: %.2fm   |   Polys: %d   |   Walkable Area: %.1f m^2',
    [FActiveNav.AgentMaxStepHeight, Length(FActiveNav.Polys), FActiveNav.TotalWalkableAreaM2]));

  { ANavLinkProxy Table }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(30, 34, 44);
  C.FillRect(12, 108, W - 12, 132);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(174, 192, 218);
  C.TextOut(20, 113, 'NavLink Name');
  C.TextOut(228, 113, 'Direction');
  C.TextOut(362, 113, 'Action');
  C.TextOut(494, 113, 'State');
  C.Font.Style := [];

  for I := 0 to High(FActiveNav.NavLinks) do
  begin
    RowY := 134 + I * 34;
    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(12, RowY, W - 12, RowY + 33);

    case FActiveNav.NavLinks[I].Direction of
      nldBothWays:        DirStr := 'BothWays (<->)';
      nldLeftToRightOnly: DirStr := 'OneWay (L->R)';
      nldRightToLeftOnly: DirStr := 'OneWay (R->L)';
    end;
    if FActiveNav.NavLinks[I].Enabled then
      StateStr := 'ACTIVE'
    else
      StateStr := 'DISABLED';

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(116, 218, 255);
    C.TextOut(20, RowY + 8, FActiveNav.NavLinks[I].LinkName);
    C.Font.Style := [];

    C.Font.Color := RGBToColor(255, 206, 118);
    C.TextOut(228, RowY + 8, DirStr);

    C.Font.Color := RGBToColor(216, 224, 240);
    C.TextOut(362, RowY + 8, FActiveNav.NavLinks[I].ActionTag);

    if FActiveNav.NavLinks[I].Enabled then
      C.Font.Color := RGBToColor(112, 238, 162)
    else
      C.Font.Color := RGBToColor(238, 112, 118);
    C.TextOut(494, RowY + 8, StateStr);
  end;

  { 3D Funnel Waypoints Inspector }
  PathTopY := 258;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, PathTopY, W, PathTopY + 30);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 222, 108);
  C.TextOut(12, PathTopY + 7, Format(
    '3D Portal-Smoothed A* Waypoints  (Dist = %.2fm, Visited = %d Polys)',
    [FActiveNav.LastPath.TotalDistanceM, FActiveNav.LastPath.VisitedPolyCount]));
  C.Font.Style := [];

  for I := 0 to High(FActiveNav.LastPath.Points) do
  begin
    RowY := PathTopY + 36 + I * 26;
    if RowY + 24 > H - 6 then Break;

    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(12, RowY, W - 12, RowY + 25);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(210, 220, 238);
    C.TextOut(20, RowY + 5, Format('WP#%d   Poly=%d   Pos=(%.2f, %.2f, %.2f)',
      [I,
       FActiveNav.LastPath.Points[I].PolyId,
       FActiveNav.LastPath.Points[I].Position.X,
       FActiveNav.LastPath.Points[I].Position.Y,
       FActiveNav.LastPath.Points[I].Position.Z]));

    if FActiveNav.LastPath.Points[I].ViaNavLink then
    begin
      C.Font.Style := [fsBold];
      C.Font.Color := RGBToColor(102, 232, 255);
      C.TextOut(356, RowY + 5, '[NavLink: ' + FActiveNav.LastPath.Points[I].LinkActionTag + ']');
      C.Font.Style := [];
    end else
    if I = 0 then
    begin
      C.Font.Color := RGBToColor(112, 238, 162);
      C.TextOut(356, RowY + 5, '[Start Origin]');
    end else
    if I = High(FActiveNav.LastPath.Points) then
    begin
      C.Font.Color := RGBToColor(255, 138, 146);
      C.TextOut(356, RowY + 5, '[Target Goal]');
    end else
    begin
      C.Font.Color := RGBToColor(154, 168, 192);
      C.TextOut(356, RowY + 5, 'Portal Corner');
    end;
  end;
  C.Brush.Style := bsSolid;
end;

procedure TRecastNavMeshForm.BtnSpawnBridgeClick(Sender: TObject);
begin
  FActiveNav := TRecastNavMeshHelper.SpawnRecastPresetInDesign(
    FDesignRoot, FDesignOwner, rnpTwoStoryBridgeAndStairs, Vector3(0, 0, 0));
  NotifyChanged('Spawn 2-Story Overpass Bridge Recast NavMesh');
end;

procedure TRecastNavMeshForm.BtnSpawnKeepClick(Sender: TObject);
begin
  FActiveNav := TRecastNavMeshHelper.SpawnRecastPresetInDesign(
    FDesignRoot, FDesignOwner, rnpMultiFloorDungeonKeep, Vector3(26, 0, 0));
  NotifyChanged('Spawn 3-Floor Dungeon Keep Recast NavMesh');
end;

procedure TRecastNavMeshForm.BtnPathClimbUpClick(Sender: TObject);
begin
  if FActiveNav = nil then Exit;
  FActiveNav.FindPath3D(Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
  RefreshFromScene;
end;

procedure TRecastNavMeshForm.BtnPathDropDownClick(Sender: TObject);
begin
  if FActiveNav = nil then Exit;
  FActiveNav.FindPath3D(Vector3(8.2, 3.0, 2.6), Vector3(6.5, 0.0, -2.5));
  RefreshFromScene;
end;

procedure TRecastNavMeshForm.BtnHumanHeightClick(Sender: TObject);
begin
  if FActiveNav = nil then Exit;
  FActiveNav.AgentHeight := 1.80;
  FActiveNav.FindPath3D(Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
  NotifyChanged('Set Recast AgentHeight = 1.80m (Underpass Open)');
end;

procedure TRecastNavMeshForm.BtnOgreHeightClick(Sender: TObject);
begin
  if FActiveNav = nil then Exit;
  FActiveNav.AgentHeight := 2.80;
  FActiveNav.FindPath3D(Vector3(-9.0, 0.0, 0.0), Vector3(8.2, 3.0, 2.6));
  NotifyChanged('Set Recast AgentHeight = 2.80m (Underpass Blocked by Ceiling)');
end;

procedure TRecastNavMeshForm.BtnToggleJumpLinkClick(Sender: TObject);
begin
  if (FActiveNav = nil) or (Length(FActiveNav.NavLinks) = 0) then Exit;
  FActiveNav.SetNavLinkEnabled(
    FActiveNav.NavLinks[0].LinkName,
    not FActiveNav.NavLinks[0].Enabled);
  FActiveNav.FindPath3D(Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
  NotifyChanged('Toggle Recast NavLinkProxy ' + FActiveNav.NavLinks[0].LinkName);
end;

procedure TRecastNavMeshForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied 3D Recast NavMesh & NavLinkProxy Report to Clipboard.';
end;

end.
