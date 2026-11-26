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

{ Unreal Engine 5.5-style Static & Skeletal Mesh Asset Editor Studio featuring
  a V-HACD / K-DOP Auto-Convex Collision & Socket Gizmo Viewport, 4-Tier LOD
  Screen-Size Strip, Socket Manager Table, and MikkTSpace Orthonormal Tangent
  Auditor (Phase 392 — 112 UE Studios / 35 MCP). }
unit FormMeshEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleMeshEditor, ToolMeshEditor;

type
  TMeshEdModifiedCallback = procedure(const UndoComment: String) of object;
  TMeshEdRefreshCallback = procedure of object;

  TMeshEditorForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMeshEdModifiedCallback;
    FOnRefresh: TMeshEdRefreshCallback;

    FActiveMesh: TCastleMeshEditorAsset;

    FLblStatus: TLabel;
    FPaintViewport: TPaintBox;
    FPaintInspector: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintMeshHullsSocketsAndLods(Sender: TObject);
    procedure PaintSocketsAndTangentInspector(Sender: TObject);

    procedure BtnSpawnArchwayClick(Sender: TObject);
    procedure BtnSpawnHalberdClick(Sender: TObject);
    procedure BtnSpawnTurretClick(Sender: TObject);
    procedure BtnSingleHullClick(Sender: TObject);
    procedure BtnMultiHullClick(Sender: TObject);
    procedure Btn26DopClick(Sender: TObject);
    procedure BtnAttachPropsClick(Sender: TObject);
    procedure BtnRecomputeTangentsClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMeshEdModifiedCallback;
      const AOnRefresh: TMeshEdRefreshCallback);
  end;

implementation

constructor TMeshEditorForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMeshEdModifiedCallback;
  const AOnRefresh: TMeshEdRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Static & Skeletal Mesh Asset Editor — Socket Manager, V-HACD Collision & LODs (112 UE Studios / 35 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActiveMesh := TMeshEditorHelper.FindFirstMeshEditorAsset(FDesignRoot);
  RefreshFromScene;
end;

procedure TMeshEditorForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnArch, BtnHalberd, BtnTurret, BtnHull1, BtnHullN, Btn26Dop,
    BtnAttach, BtnMikk, BtnCopy, BtnClose: TButton;
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
  FLblStatus.Caption := 'Static & Skeletal Mesh Asset Editor Ready.';

  XPos := 8;
  BtnArch := MakeToolbarBtn('+ Gothic Archway', 132, @BtnSpawnArchwayClick);
  BtnHalberd := MakeToolbarBtn('+ Skeletal Halberd', 142, @BtnSpawnHalberdClick);
  BtnTurret := MakeToolbarBtn('+ Aegis Turret', 120, @BtnSpawnTurretClick);
  BtnHull1 := MakeToolbarBtn('1 Hull (Blocked)', 128, @BtnSingleHullClick);
  BtnHullN := MakeToolbarBtn('V-HACD Decompose', 148, @BtnMultiHullClick);
  Btn26Dop := MakeToolbarBtn('Fit 26-DOP', 96, @Btn26DopClick);
  BtnAttach := MakeToolbarBtn('Attach Socket Props', 150, @BtnAttachPropsClick);
  BtnMikk := MakeToolbarBtn('Recompute MikkTSpace', 174, @BtnRecomputeTangentsClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 100, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 68, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnArch <> nil) and (BtnHalberd <> nil) and (BtnTurret <> nil) and
     (BtnHull1 <> nil) and (BtnHullN <> nil) and (Btn26Dop <> nil) and
     (BtnAttach <> nil) and (BtnMikk <> nil) and (BtnCopy <> nil) then ;

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
  PnlRight.Width := 568;
  PnlRight.BevelOuter := bvNone;

  FPaintInspector := TPaintBox.Create(Self);
  FPaintInspector.Parent := PnlRight;
  FPaintInspector.Align := alClient;
  FPaintInspector.OnPaint := @PaintSocketsAndTangentInspector;

  FPaintViewport := TPaintBox.Create(Self);
  FPaintViewport.Parent := Self;
  FPaintViewport.Align := alClient;
  FPaintViewport.OnPaint := @PaintMeshHullsSocketsAndLods;
end;

procedure TMeshEditorForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TMeshEditorForm.RefreshFromScene;
var
  ClearDoor: Boolean;
begin
  if FActiveMesh = nil then
    FActiveMesh := TMeshEditorHelper.FindFirstMeshEditorAsset(FDesignRoot);

  if FActiveMesh <> nil then
  begin
    ClearDoor := not FActiveMesh.PointHitsAnyConvexHull(Vector3(0.0, 1.2, 0.0));
    FLblStatus.Caption := Format(
      'Active: %s (%s)  |  Convex Hulls: %d (Vol=%.2f m^3)  |  Sockets: %d  |  LOD0: %d Tris  |  Center Opening: %s',
      [FActiveMesh.MeshAssetKey,
       BoolToStr(FActiveMesh.IsSkeletalMesh, 'USkeletalMesh', 'UStaticMesh'),
       Length(FActiveMesh.ConvexHulls),
       FActiveMesh.TotalConvexHullVolumeM3,
       Length(FActiveMesh.Sockets),
       FActiveMesh.BaseLod0Triangles,
       BoolToStr(ClearDoor, 'WALKABLE', 'BLOCKED BY HULL')]);
  end else
    FLblStatus.Caption := 'No TCastleMeshEditorAsset in scene — click "+ Gothic Archway" or "+ Skeletal Halberd".';

  FMemoReport.Lines.Text := TMeshEditorHelper.GenerateMarkdownReport(
    FDesignRoot, FActiveMesh);

  FPaintViewport.Invalidate;
  FPaintInspector.Invalidate;
end;

procedure TMeshEditorForm.PaintMeshHullsSocketsAndLods(Sender: TObject);
var
  C: TCanvas;
  W, H, GroundY, OriginX, I, X1, Y1, X2, Y2, SX, SY, LodBoxW, LodX, LodY: Integer;
  ScalePx, MaxSpanX, MaxSpanY, SockYaw: Single;
  MinB, MaxB, SockPos, SockScale: TVector3;
  DoorBlocked: Boolean;
begin
  C := FPaintViewport.Canvas;
  W := Max(360, FPaintViewport.Width);
  H := Max(300, FPaintViewport.Height);

  C.Brush.Color := RGBToColor(19, 22, 29);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(30, 34, 44);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(126, 232, 168);
  C.TextOut(12, 7, 'UE 5.5 Mesh Viewport  (Gray = Mesh Geometry | Green = UCX Convex Hulls | Gold = Sockets)');
  C.Font.Style := [];

  if FActiveMesh = nil then
  begin
    C.Font.Color := RGBToColor(175, 186, 206);
    C.TextOut(24, 60, 'Click "+ Gothic Archway" or "+ Skeletal Halberd" to inspect V-HACD hulls & Sockets.');
    Exit;
  end;

  { Compute 2D front-elevation viewport transform }
  MinB := Vector3(-2.2, 0.0, -1.0);
  MaxB := Vector3(2.2, 3.6, 1.0);
  if Length(FActiveMesh.SubParts) > 0 then
  begin
    MinB := FActiveMesh.SubParts[0].BoundsMin;
    MaxB := FActiveMesh.SubParts[0].BoundsMax;
    for I := 1 to High(FActiveMesh.SubParts) do
    begin
      MinB.X := Min(MinB.X, FActiveMesh.SubParts[I].BoundsMin.X);
      MinB.Y := Min(MinB.Y, FActiveMesh.SubParts[I].BoundsMin.Y);
      MaxB.X := Max(MaxB.X, FActiveMesh.SubParts[I].BoundsMax.X);
      MaxB.Y := Max(MaxB.Y, FActiveMesh.SubParts[I].BoundsMax.Y);
    end;
  end;

  MaxSpanX := Max(1.6, (MaxB.X - MinB.X) * 1.35);
  MaxSpanY := Max(2.2, (MaxB.Y - MinB.Y) * 1.25);
  ScalePx := Min((W - 80) / MaxSpanX, (H - 175) / MaxSpanY);
  OriginX := W div 2;
  GroundY := H - 114;

  { Studio grid lines }
  C.Pen.Color := RGBToColor(32, 36, 46);
  for I := -6 to 6 do
  begin
    SX := OriginX + Round(I * 0.5 * ScalePx);
    if (SX > 12) and (SX < W - 12) then
    begin
      C.MoveTo(SX, 38);
      C.LineTo(SX, GroundY + 12);
    end;
  end;
  for I := 0 to 8 do
  begin
    SY := GroundY - Round(I * 0.5 * ScalePx);
    if (SY > 38) and (SY < GroundY + 12) then
    begin
      C.MoveTo(16, SY);
      C.LineTo(W - 16, SY);
    end;
  end;

  { Ground baseline }
  C.Pen.Color := RGBToColor(84, 96, 120);
  C.Pen.Width := 2;
  C.MoveTo(20, GroundY);
  C.LineTo(W - 20, GroundY);
  C.Pen.Width := 1;

  { 1. Source Mesh Sub-Part Solids }
  for I := 0 to High(FActiveMesh.SubParts) do
  begin
    X1 := OriginX + Round(FActiveMesh.SubParts[I].BoundsMin.X * ScalePx);
    X2 := OriginX + Round(FActiveMesh.SubParts[I].BoundsMax.X * ScalePx);
    Y1 := GroundY - Round(FActiveMesh.SubParts[I].BoundsMax.Y * ScalePx);
    Y2 := GroundY - Round(FActiveMesh.SubParts[I].BoundsMin.Y * ScalePx);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(58, 65, 82);
    C.Pen.Color := RGBToColor(118, 132, 162);
    C.Rectangle(X1, Y1, X2, Y2);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(196, 206, 226);
    if (X2 - X1 > 68) and (Y2 - Y1 > 22) then
      C.TextOut(X1 + 6, Y1 + 5, FActiveMesh.SubParts[I].PartName);
  end;

  { 2. Green UCX Auto-Convex Collision Hull Wireframes (UE Alt+C Style) }
  C.Brush.Style := bsClear;
  for I := 0 to High(FActiveMesh.ConvexHulls) do
  begin
    X1 := OriginX + Round(FActiveMesh.ConvexHulls[I].BoundsMin.X * ScalePx) - 3;
    X2 := OriginX + Round(FActiveMesh.ConvexHulls[I].BoundsMax.X * ScalePx) + 3;
    Y1 := GroundY - Round(FActiveMesh.ConvexHulls[I].BoundsMax.Y * ScalePx) - 3;
    Y2 := GroundY - Round(FActiveMesh.ConvexHulls[I].BoundsMin.Y * ScalePx) + 3;

    C.Pen.Color := RGBToColor(64, 242, 128);
    C.Pen.Width := 2;
    if FActiveMesh.ConvexHulls[I].PlaneCount >= 18 then
      C.RoundRect(X1, Y1, X2, Y2, 14, 14)
    else
      C.Rectangle(X1, Y1, X2, Y2);
    C.Pen.Width := 1;

    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(96, 252, 152);
    C.TextOut(X1 + 6, Max(36, Y1 - 17), Format('%s (%d-DOP)',
      [FActiveMesh.ConvexHulls[I].HullName, FActiveMesh.ConvexHulls[I].PlaneCount]));
    C.Font.Style := [];
  end;

  { Walkable clearance probe indicator for archway-style meshes }
  if FActiveMesh.Preset = mepGothicArchwayConcave3Hulls then
  begin
    DoorBlocked := FActiveMesh.PointHitsAnyConvexHull(Vector3(0.0, 1.2, 0.0));
    SX := OriginX;
    SY := GroundY - Round(1.2 * ScalePx);
    C.Brush.Style := bsSolid;
    if DoorBlocked then
    begin
      C.Brush.Color := RGBToColor(135, 38, 46);
      C.Pen.Color := RGBToColor(255, 108, 118);
      C.RoundRect(SX - 96, SY - 14, SX + 96, SY + 14, 8, 8);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(255, 212, 216);
      C.TextOut(SX - 84, SY - 8, 'PLAYER CAPSULE BLOCKED');
    end else
    begin
      C.Brush.Color := RGBToColor(26, 88, 56);
      C.Pen.Color := RGBToColor(96, 238, 154);
      C.RoundRect(SX - 98, SY - 14, SX + 98, SY + 14, 8, 8);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(210, 255, 228);
      C.TextOut(SX - 84, SY - 8, 'ARCHWAY OPENING CLEAR');
    end;
  end;

  { 3. Golden Attachment Socket Coordinate Gizmos (X=Red, Y=Green + Diamond) }
  for I := 0 to High(FActiveMesh.Sockets) do
    if FActiveMesh.EvaluateSocketLocalMatrix(
         FActiveMesh.Sockets[I].SocketName, SockPos, SockYaw, SockScale) then
    begin
      SX := OriginX + Round(SockPos.X * ScalePx);
      SY := GroundY - Round(SockPos.Y * ScalePx);

      { X / Y coordinate axes }
      C.Pen.Width := 2;
      C.Pen.Color := RGBToColor(255, 92, 92);
      C.MoveTo(SX, SY);
      C.LineTo(SX + 18, SY);
      C.Pen.Color := RGBToColor(92, 242, 128);
      C.MoveTo(SX, SY);
      C.LineTo(SX, SY - 18);
      C.Pen.Width := 1;

      { Golden socket diamond }
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(255, 204, 52);
      C.Pen.Color := RGBToColor(255, 244, 180);
      C.Ellipse(SX - 6, SY - 6, SX + 6, SY + 6);

      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(28, 32, 42);
      C.Pen.Color := RGBToColor(148, 122, 48);
      C.Rectangle(SX + 10, SY - 10, SX + 184, SY + 10);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(255, 222, 118);
      C.TextOut(SX + 15, SY - 8, FActiveMesh.Sockets[I].SocketName);
    end;

  { 4. Bottom 4-Tier LOD Screen-Size Threshold Strip }
  LodY := H - 88;
  LodBoxW := Max(120, (W - 36) div Max(1, Length(FActiveMesh.LodChain)));
  for I := 0 to High(FActiveMesh.LodChain) do
  begin
    LodX := 12 + I * LodBoxW;
    C.Brush.Style := bsSolid;
    if I = 0 then
    begin
      C.Brush.Color := RGBToColor(36, 58, 88);
      C.Pen.Color := RGBToColor(98, 176, 255);
    end else
    begin
      C.Brush.Color := RGBToColor(28, 32, 42);
      C.Pen.Color := RGBToColor(68, 78, 98);
    end;
    C.RoundRect(LodX, LodY, LodX + LodBoxW - 6, H - 12, 8, 8);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(235, 242, 255);
    C.TextOut(LodX + 10, LodY + 7, Format('LOD%d  (Screen >= %.2f)',
      [FActiveMesh.LodChain[I].LodIndex, FActiveMesh.LodChain[I].ScreenSizeThreshold]));
    C.Font.Style := [];
    C.Font.Color := RGBToColor(166, 198, 232);
    C.TextOut(LodX + 10, LodY + 27, Format('%d Tris  |  %d Verts',
      [FActiveMesh.LodChain[I].TriangleCount, FActiveMesh.LodChain[I].VertexCount]));
    C.Font.Color := RGBToColor(118, 224, 162);
    C.TextOut(LodX + 10, LodY + 47, Format('Culled: -%.0f%%',
      [FActiveMesh.LodChain[I].ReductionPercent]));
  end;
  C.Brush.Style := bsSolid;
end;

procedure TMeshEditorForm.PaintSocketsAndTangentInspector(Sender: TObject);
var
  C: TCanvas;
  W, H, I, RowY, TanTopY: Integer;
  SockPos, SockScale: TVector3;
  SockYaw: Single;
  PropStr: String;
  TA: TMeshTangentAudit;
begin
  C := FPaintInspector.Canvas;
  W := Max(340, FPaintInspector.Width);
  H := Max(300, FPaintInspector.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'Socket Manager  (UStaticMeshSocket / USkeletalMeshSocket)');
  C.Font.Style := [];

  if FActiveMesh = nil then Exit;

  { Socket Table Header }
  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(0, 32, W, 56);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 186, 210);
  C.TextOut(12, 37, 'Socket Name');
  C.TextOut(208, 37, 'Bone');
  C.TextOut(268, 37, 'World Offset');
  C.TextOut(408, 37, 'Preview Prop');
  C.Font.Style := [];

  for I := 0 to High(FActiveMesh.Sockets) do
  begin
    RowY := 58 + I * 34;
    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(0, RowY, W, RowY + 33);

    FActiveMesh.EvaluateSocketLocalMatrix(
      FActiveMesh.Sockets[I].SocketName, SockPos, SockYaw, SockScale);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(255, 218, 116);
    C.TextOut(12, RowY + 8, FActiveMesh.Sockets[I].SocketName);
    C.Font.Style := [];

    C.Font.Color := RGBToColor(148, 206, 255);
    C.TextOut(208, RowY + 8, FActiveMesh.Sockets[I].TargetBoneName);

    C.Font.Color := RGBToColor(212, 220, 236);
    C.TextOut(268, RowY + 8, Format('(%.2f, %.2f, %.2f)',
      [SockPos.X, SockPos.Y, SockPos.Z]));

    PropStr := FActiveMesh.Sockets[I].PreviewPropTag;
    if Length(PropStr) > 19 then
      PropStr := Copy(PropStr, 1, 17) + '..';
    C.Font.Color := RGBToColor(134, 232, 174);
    C.TextOut(408, RowY + 8, PropStr);
  end;

  { MikkTSpace Orthonormal Tangent & Normal Audit Section }
  TanTopY := 214;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, TanTopY, W, TanTopY + 30);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(132, 204, 255);
  C.TextOut(12, TanTopY + 7,
    Format('MikkTSpace Orthonormal Tangent Basis  (Hard Threshold = %.0f deg)',
      [FActiveMesh.HardAngleThresholdDeg]));
  C.Font.Style := [];

  TA := FActiveMesh.LastTangentAudit;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(28, 33, 44);
  C.Pen.Color := RGBToColor(68, 82, 106);
  C.RoundRect(12, TanTopY + 40, W - 12, TanTopY + 98, 8, 8);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(225, 234, 248);
  C.TextOut(24, TanTopY + 49, Format(
    'Samples: %d   |   Hard Crease Splits: %d   |   Mirrored UVs (w = -1): %d',
    [TA.SampleVertexCount, TA.HardSeamCount, TA.MirroredUvVertexCount]));
  C.Font.Color := RGBToColor(116, 236, 164);
  C.TextOut(24, TanTopY + 72, Format(
    'Zero-Len Normals: %d  |  Non-Orthogonal: %d  |  Max |N.T|: %.5f',
    [TA.ZeroLengthNormalCount, TA.NonOrthogonalTangentCount, TA.MaxOrthogonalityError]));

  { Sample rows }
  for I := 0 to High(FActiveMesh.TangentSamples) do
  begin
    RowY := TanTopY + 110 + I * 28;
    if RowY + 26 > H - 8 then Break;

    C.Brush.Style := bsSolid;
    if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(27, 30, 39)
    else
      C.Brush.Color := RGBToColor(23, 26, 34);
    C.FillRect(12, RowY, W - 12, RowY + 26);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(198, 210, 230);
    C.TextOut(20, RowY + 5, Format('V%d  N=(%.2f, %.2f, %.2f)   T=(%.2f, %.2f, %.2f)',
      [I,
       FActiveMesh.TangentSamples[I].Normal.X,
       FActiveMesh.TangentSamples[I].Normal.Y,
       FActiveMesh.TangentSamples[I].Normal.Z,
       FActiveMesh.TangentSamples[I].TangentXYZ.X,
       FActiveMesh.TangentSamples[I].TangentXYZ.Y,
       FActiveMesh.TangentSamples[I].TangentXYZ.Z]));

    if FActiveMesh.TangentSamples[I].BitangentSignW < 0 then
    begin
      C.Font.Style := [fsBold];
      C.Font.Color := RGBToColor(255, 168, 112);
      C.TextOut(392, RowY + 5, 'w = -1 (Mirrored)');
      C.Font.Style := [];
    end else
    begin
      C.Font.Color := RGBToColor(124, 228, 168);
      C.TextOut(392, RowY + 5, 'w = +1 (Right-Hand)');
    end;
  end;
  C.Brush.Style := bsSolid;
end;

procedure TMeshEditorForm.BtnSpawnArchwayClick(Sender: TObject);
begin
  FActiveMesh := TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
    FDesignRoot, FDesignOwner, mepGothicArchwayConcave3Hulls, Vector3(0, 0, 0));
  NotifyChanged('Spawn Gothic Archway Mesh Asset');
end;

procedure TMeshEditorForm.BtnSpawnHalberdClick(Sender: TObject);
begin
  FActiveMesh := TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
    FDesignRoot, FDesignOwner, mepSkeletalHalberdWeapon4Sockets, Vector3(3.5, 0, 0));
  NotifyChanged('Spawn Skeletal Halberd Mesh Asset');
end;

procedure TMeshEditorForm.BtnSpawnTurretClick(Sender: TObject);
begin
  FActiveMesh := TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
    FDesignRoot, FDesignOwner, mepSciFiDefenseTurretMultiPart, Vector3(-3.5, 0, 0));
  NotifyChanged('Spawn Sci-Fi Defense Turret Mesh Asset');
end;

procedure TMeshEditorForm.BtnSingleHullClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.GenerateAutoConvexCollision(1, kdmBox6Dop, 8);
  NotifyChanged('Set Mesh Auto-Convex to 1 Bounding Hull');
end;

procedure TMeshEditorForm.BtnMultiHullClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.GenerateAutoConvexCollision(
    Max(3, Length(FActiveMesh.SubParts)), kdm18DopBeveled, 20);
  NotifyChanged('Run V-HACD Multi-Hull Convex Decomposition');
end;

procedure TMeshEditorForm.Btn26DopClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.GenerateAutoConvexCollision(
    Max(3, Length(FActiveMesh.SubParts)), kdm26DopChamfered, 24);
  NotifyChanged('Fit 26-DOP Chamfered Convex Hulls');
end;

procedure TMeshEditorForm.BtnAttachPropsClick(Sender: TObject);
var
  I: Integer;
begin
  if FActiveMesh = nil then Exit;
  for I := 0 to High(FActiveMesh.Sockets) do
    TMeshEditorHelper.SpawnPreviewPropOnSocket(
      FActiveMesh, FDesignOwner, FActiveMesh.Sockets[I].SocketName);
  NotifyChanged('Attach Preview Props to All Mesh Sockets');
end;

procedure TMeshEditorForm.BtnRecomputeTangentsClick(Sender: TObject);
begin
  if FActiveMesh = nil then Exit;
  FActiveMesh.RecomputeNormalsAndMikkTangents(60.0);
  NotifyChanged('Recompute Area-Weighted Normals & MikkTSpace Tangents');
end;

procedure TMeshEditorForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Static & Skeletal Mesh Editor Report to Clipboard.';
end;

end.
