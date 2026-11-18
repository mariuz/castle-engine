{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Nanite-Style Meshlet Cluster & Normal-Cone Culler (Phase 353). }
unit FormMeshletStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleMeshletCluster, ToolMeshletStudio;

type
  TMeshletStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TMeshletStudioRefreshCallback = procedure of object;

  TMeshletStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMeshletStudioModifiedCallback;
    FOnRefresh: TMeshletStudioRefreshCallback;
    FCamWorldPos: TVector3;
    FPaintClusters: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveClusterer: TCastleMeshletClusterer;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnSphereClick(Sender: TObject);
    procedure BtnTorusClick(Sender: TObject);
    procedure BtnTerrainClick(Sender: TObject);
    procedure BtnCamCloseClick(Sender: TObject);
    procedure BtnCamFarClick(Sender: TObject);
    procedure BtnToggleHideCulledClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintClusterDiagram(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMeshletStudioModifiedCallback;
      const AOnRefresh: TMeshletStudioRefreshCallback);
  end;

implementation

constructor TMeshletStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMeshletStudioModifiedCallback;
  const AOnRefresh: TMeshletStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FCamWorldPos := Vector3(0.0, 0.0, 12.0);
  Caption := 'Nanite Meshlet Cluster Builder & Normal-Cone Backface Culler Studio (Phase 353)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TMeshletStudioForm.BuildUi;
var
  Lbl: TLabel;
  Row1, Row2, BodyPanel: TPanel;

  function MakeBtn(AParent: TWinControl; const ACaption: String; const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Align := alLeft;
    Result.AutoSize := True;
    Result.BorderSpacing.Around := 4;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ Nanite Cluster Parity — 64v / 124t Spatial Meshlets, Bounding Spheres, Normal-Cone Backface Rejection & Pixel-Error LOD';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Meshlet Sphere (1,536 tris)', @BtnSpawnClick);
  MakeBtn(Row1, 'Mesh: UV Sphere', @BtnSphereClick);
  MakeBtn(Row1, 'Mesh: Twisted Torus', @BtnTorusClick);
  MakeBtn(Row1, 'Mesh: Displaced Ridge', @BtnTerrainClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Camera Close (Z=+12m -> LOD 0)', @BtnCamCloseClick);
  MakeBtn(Row2, 'Camera Far (Z=+140m -> Coarse LOD)', @BtnCamFarClick);
  MakeBtn(Row2, 'Toggle Hide Culled Meshlets in 3D', @BtnToggleHideCulledClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintClusters := TPaintBox.Create(Self);
  FPaintClusters.Parent := BodyPanel;
  FPaintClusters.Align := alLeft;
  FPaintClusters.Width := 520;
  FPaintClusters.OnPaint := @PaintClusterDiagram;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TMeshletStudioForm.ActiveClusterer: TCastleMeshletClusterer;
begin
  Result := TMeshletStudioHelper.FindClustererInHierarchy(FDesignRoot);
end;

procedure TMeshletStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TMeshletStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TMeshletStudioHelper.GenerateMeshletReport(ActiveClusterer);
  FPaintClusters.Invalidate;
end;

procedure TMeshletStudioForm.BtnSpawnClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  if TMeshletStudioHelper.SpawnMeshletClusterDemo(FDesignRoot, FDesignOwner, C) then
  begin
    C.EvaluateViewMeshletCulling(FCamWorldPos, 1080, 60.0);
    NotifyChange('Spawn Nanite Meshlet Clusterer');
  end;
end;

procedure TMeshletStudioForm.BtnSphereClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  C := ActiveClusterer;
  if C = nil then Exit;
  C.Preset := mspHighPolyUvSphere;
  C.EvaluateViewMeshletCulling(FCamWorldPos, 1080, 60.0);
  NotifyChange('Switch Meshlet Source to High-Poly UV Sphere');
end;

procedure TMeshletStudioForm.BtnTorusClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  C := ActiveClusterer;
  if C = nil then Exit;
  C.Preset := mspTwistedTorusRing;
  C.EvaluateViewMeshletCulling(FCamWorldPos, 1080, 60.0);
  NotifyChange('Switch Meshlet Source to Twisted Torus');
end;

procedure TMeshletStudioForm.BtnTerrainClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  C := ActiveClusterer;
  if C = nil then Exit;
  C.Preset := mspDisplacedTerrainPatch;
  C.EvaluateViewMeshletCulling(FCamWorldPos, 1080, 60.0);
  NotifyChange('Switch Meshlet Source to Displaced Ridge');
end;

procedure TMeshletStudioForm.BtnCamCloseClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  FCamWorldPos := Vector3(0.0, 0.0, 12.0);
  C := ActiveClusterer;
  if C <> nil then
    C.EvaluateViewMeshletCulling(FCamWorldPos, 1080, 60.0);
  NotifyChange('Evaluate Meshlet Culling at Close Camera (Z=+12m)');
end;

procedure TMeshletStudioForm.BtnCamFarClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  FCamWorldPos := Vector3(0.0, 0.0, 140.0);
  C := ActiveClusterer;
  if C <> nil then
    C.EvaluateViewMeshletCulling(FCamWorldPos, 1080, 60.0);
  NotifyChange('Evaluate Meshlet Culling at Far Camera (Z=+140m)');
end;

procedure TMeshletStudioForm.BtnToggleHideCulledClick(Sender: TObject);
var
  C: TCastleMeshletClusterer;
begin
  C := ActiveClusterer;
  if C = nil then Exit;
  C.HideCulledClustersInPreview := not C.HideCulledClustersInPreview;
  NotifyChange('Toggle Hide Backface-Culled Meshlets');
end;

procedure TMeshletStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TMeshletStudioHelper.GenerateMeshletReport(ActiveClusterer);
end;

procedure TMeshletStudioForm.PaintClusterDiagram(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, RadPx, CX, CY, NX, NY: Integer;
  Cl: TCastleMeshletClusterer;
  Info: TMeshletClusterInfo;
  Col: TVector3;
  S: TMeshletViewStats;
begin
  Cv := FPaintClusters.Canvas;
  W := FPaintClusters.Width;
  H := FPaintClusters.Height;
  Cv.Brush.Color := RGBToColor(20, 24, 32);
  Cv.FillRect(0, 0, W, H);

  Cl := ActiveClusterer;
  if Cl = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Meshlet Sphere" to inspect ZY Bounding Spheres & Normal Cones.');
    Exit;
  end;

  for I := 0 to Cl.ClusterCount - 1 do
  begin
    Info := Cl.GetClusterInfo(I);
    CX := Round(W * 0.50 + (Info.BoundingCenterLocal.Z / 7.5) * (W * 0.36));
    CY := Round(H * 0.52 - (Info.BoundingCenterLocal.Y / 7.5) * (H * 0.36));
    RadPx := Max(6, Round((Info.BoundingRadius / 7.5) * (W * 0.30)));
    Col := MeshletClusterColorRGB(I);

    Cv.Brush.Style := bsClear;
    if Info.LastCulledByBackfaceCone then
    begin
      Cv.Pen.Color := RGBToColor(120, 55, 55);
      Cv.Pen.Style := psDot;
    end else
    begin
      Cv.Pen.Color := RGBToColor(Round(Col.X * 255), Round(Col.Y * 255), Round(Col.Z * 255));
      Cv.Pen.Style := psSolid;
    end;
    Cv.Ellipse(CX - RadPx, CY - RadPx, CX + RadPx, CY + RadPx);

    NX := CX + Round(Info.NormalConeAxisLocal.Z * 22.0);
    NY := CY - Round(Info.NormalConeAxisLocal.Y * 22.0);
    Cv.Pen.Style := psSolid;
    Cv.Line(CX, CY, NX, NY);
  end;

  S := Cl.LastViewStats;
  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('ZY Cluster Cross-Section (Cam Z=+%.0fm) | Visible=%d/%d | Culled=%.1f%% | LOD %d', [
    FCamWorldPos.Z, S.VisibleClusters, S.TotalClusters, S.CulledTrianglePercent, S.RecommendedLodTier]));
end;

end.
