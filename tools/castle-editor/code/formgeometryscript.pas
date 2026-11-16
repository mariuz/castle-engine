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

{ Interactive Geometry Script Procedural Mesh Operator Stack & Parametric 3D
  L-System Botanical Tree Studio (@link(TGeometryScriptForm)) featuring
  1-click Amphora / Asteroid / Obelisk & Oak / Pine / Willow spawners,
  non-destructive modifier toggling, and a dual Silhouette Wireframe +
  L-System Branching Preview canvas (Phase 325). }
unit FormGeometryScript;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleGeometryScript, ToolGeometryScript;

type
  TGeometryScriptModifiedCallback = procedure(const AComment: String) of object;
  TGeometryScriptRefreshViewportCallback = procedure of object;

  TGeometryScriptForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TGeometryScriptModifiedCallback;
    FOnRefreshViewport: TGeometryScriptRefreshViewportCallback;

    FMeshes: TGeoScriptMeshArray;
    FTrees: TLSystemBotanicalArray;
    FReport: TGeometryScriptAuditReport;

    LblHeader: TLabel;
    ListItems: TListBox;
    PaintPreview: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveMesh: TCastleGeometryScriptMesh;
    function ActiveTree: TCastleLSystemBotanical;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnGeoAsteroidClick(Sender: TObject);
    procedure BtnGeoObeliskClick(Sender: TObject);
    procedure BtnToggleTopModClick(Sender: TObject);
    procedure BtnTreePineClick(Sender: TObject);
    procedure BtnTreeWillowClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintPreviewPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TGeometryScriptModifiedCallback;
      const AOnRefreshViewport: TGeometryScriptRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TGeometryScriptForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TGeometryScriptModifiedCallback;
  const AOnRefreshViewport: TGeometryScriptRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Geometry Script Procedural Mesh Stack & 3D L-System Botanical Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TGeometryScriptForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TGeometryScriptForm.BuildUi;
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
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Geometry Script & L-System Botanicals: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn Amphora + Oak Tree', 4, 2, 200, @BtnSpawnDemoClick);
  MakeBtn(RowTop, 'Geo: Asteroid', 210, 2, 120, @BtnGeoAsteroidClick);
  MakeBtn(RowTop, 'Geo: Obelisk', 336, 2, 118, @BtnGeoObeliskClick);
  MakeBtn(RowTop, 'Toggle 1st Mod', 460, 2, 128, @BtnToggleTopModClick);
  MakeBtn(RowTop, 'Tree: Conifer Pine', 594, 2, 148, @BtnTreePineClick);
  MakeBtn(RowTop, 'Tree: Weeping Willow', 748, 2, 162, @BtnTreeWillowClick);
  MakeBtn(RowTop, 'Copy Markdown', 916, 2, 130, @BtnCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Caption := 'Close';
  BtnClose.Width := 110;
  BtnClose.Height := 28;
  BtnClose.Top := 7;
  BtnClose.Left := Width - 130;
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.OnClick := @BtnCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Procedural Meshes & Botanical Trees:';

  ListItems := TListBox.Create(Self);
  ListItems.Parent := PanelLeft;
  ListItems.SetBounds(10, 26, 320, 230);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 264, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Modifier Stack, Surface Area & QA:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 286, 320, 285);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintPreview := TPaintBox.Create(Self);
  PaintPreview.Parent := PanelCenter;
  PaintPreview.Align := alClient;
  PaintPreview.OnPaint := @PaintPreviewPaint;
end;

function TGeometryScriptForm.ActiveMesh: TCastleGeometryScriptMesh;
begin
  if Length(FMeshes) > 0 then Result := FMeshes[0] else Result := nil;
end;

function TGeometryScriptForm.ActiveTree: TCastleLSystemBotanical;
begin
  if Length(FTrees) > 0 then Result := FTrees[0] else Result := nil;
end;

procedure TGeometryScriptForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TGeometryScriptForm.RefreshAll;
var
  I: Integer;
  M: TCastleGeometryScriptMesh;
  T: TCastleLSystemBotanical;
  Stage: TGeoModifierStage;
begin
  TGeometryScriptHelper.ScanGeometryAndBotanicals(FDesignRoot, FDesignOwner, FMeshes, FTrees);
  FreeAndNil(FReport);
  FReport := TGeometryScriptHelper.AuditGeometryScript(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'GeoScript Meshes: %d (%d tris)  |  3D L-System Trees: %d (%d branches)  |  QA Warnings: %d',
    [FReport.GeoMeshCount, FReport.TotalProceduralTriangles, FReport.BotanicalCount,
     FReport.TotalBranches, FReport.Warnings.Count]);

  ListItems.Items.BeginUpdate;
  try
    ListItems.Items.Clear;
    for I := 0 to High(FMeshes) do
      ListItems.Items.Add(FMeshes[I].Name + '  ' + FMeshes[I].GeoSummaryBadge);
    for I := 0 to High(FTrees) do
      ListItems.Items.Add(FTrees[I].Name + '  ' + FTrees[I].BotanicalSummaryBadge);
  finally
    ListItems.Items.EndUpdate;
  end;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    M := ActiveMesh;
    if M <> nil then
    begin
      MemoDiag.Lines.Add(Format('Mesh: %s  Verts=%d  Tris=%d  Area=%.2fm^2',
        [M.Name, M.VertexCount, M.TriangleCount, M.ComputedSurfaceArea]));
      for I := 0 to M.ModifierCount - 1 do
      begin
        Stage := M.GetModifier(I);
        MemoDiag.Lines.Add(Format('  [%s] %s (%.2f)', [
          BoolToStr(Stage.Enabled, 'ON', 'off'),
          TCastleGeometryScriptMesh.ModifierDisplayName(Stage.Kind),
          Stage.ParamA]));
      end;
      MemoDiag.Lines.Add('');
    end;
    T := ActiveTree;
    if T <> nil then
    begin
      MemoDiag.Lines.Add(Format('Tree: %s  Height=%.2fm  CrownSpan=%.2fx%.2fm',
        [T.Name, T.CrownBoundsMaxY, T.BoundsSpanX, T.BoundsSpanZ]));
      MemoDiag.Lines.Add('');
    end;
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] Procedural mesh & L-System budgets healthy.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintPreview.Invalidate;
end;

procedure TGeometryScriptForm.BtnSpawnDemoClick(Sender: TObject);
var
  M: TCastleGeometryScriptMesh;
  T: TCastleLSystemBotanical;
begin
  TGeometryScriptHelper.SpawnGeometryAndTreeShowcaseDemo(FDesignRoot, FDesignOwner, M, T);
  NotifyChanged('Spawn Geometry Script Amphora + 3D L-System Oak Tree');
end;

procedure TGeometryScriptForm.BtnGeoAsteroidClick(Sender: TObject);
var M: TCastleGeometryScriptMesh;
begin
  M := ActiveMesh; if M = nil then Exit;
  M.ApplyPreset(gspDisplacedAsteroidBoulder);
  NotifyChanged('GeoScript Preset: Displaced Asteroid');
end;

procedure TGeometryScriptForm.BtnGeoObeliskClick(Sender: TObject);
var M: TCastleGeometryScriptMesh;
begin
  M := ActiveMesh; if M = nil then Exit;
  M.ApplyPreset(gspTaperedObeliskColumn);
  NotifyChanged('GeoScript Preset: Tapered Obelisk');
end;

procedure TGeometryScriptForm.BtnToggleTopModClick(Sender: TObject);
var M: TCastleGeometryScriptMesh;
begin
  M := ActiveMesh;
  if (M = nil) or (M.ModifierCount = 0) then Exit;
  M.SetModifierEnabled(0, not M.GetModifier(0).Enabled);
  NotifyChanged('Toggle Geometry Script Modifier Stage 0');
end;

procedure TGeometryScriptForm.BtnTreePineClick(Sender: TObject);
var T: TCastleLSystemBotanical;
begin
  T := ActiveTree; if T = nil then Exit;
  T.ApplyPreset(lspAlpineConiferPine);
  NotifyChanged('L-System Preset: Alpine Conifer Pine');
end;

procedure TGeometryScriptForm.BtnTreeWillowClick(Sender: TObject);
var T: TCastleLSystemBotanical;
begin
  T := ActiveTree; if T = nil then Exit;
  T.ApplyPreset(lspWeepingWillowTree);
  NotifyChanged('L-System Preset: Weeping Willow Tree');
end;

procedure TGeometryScriptForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TGeometryScriptHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TGeometryScriptForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TGeometryScriptForm.PaintPreviewPaint(Sender: TObject);
var
  C: TCanvas;
  M: TCastleGeometryScriptMesh;
  T: TCastleLSystemBotanical;
  W, H, MidX, CxL, CxR, BaseY, I, Px, Py, X1, Y1, X2, Y2: Integer;
  Pt: TVector3;
  Seg: TLSystemBranchSeg;
begin
  C := PaintPreview.Canvas;
  W := Max(200, PaintPreview.Width);
  H := Max(200, PaintPreview.Height);
  C.Brush.Color := RGBToColor(20, 24, 31);
  C.FillRect(0, 0, W, H);

  M := ActiveMesh;
  T := ActiveTree;
  if (M = nil) and (T = nil) then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn Amphora + Oak Tree" to preview Geometry Script vertices & 3D L-System branches.');
    Exit;
  end;

  MidX := W div 2;
  BaseY := H - 56;

  { Left panel: Geometry Script X-Y Vertex Silhouette }
  if M <> nil then
  begin
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(232, 240, 250);
    C.TextOut(20, 14, 'Geometry Script Front X-Y Vertex Cloud');
    C.Font.Style := [];
    CxL := MidX div 2;
    C.Brush.Color := RGBToColor(246, 168, 78);
    C.Pen.Color := RGBToColor(255, 210, 140);
    for I := 0 to M.PreviewVertexCount - 1 do
    begin
      Pt := M.GetPreviewVertex(I);
      Px := CxL + Round(Pt.X * 125.0);
      Py := BaseY - Round(Pt.Y * 125.0);
      C.Ellipse(Px - 2, Py - 2, Px + 2, Py + 2);
    end;
  end;

  { Right panel: 3D L-System X-Y Branching Skeleton }
  if T <> nil then
  begin
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(232, 240, 250);
    C.Brush.Style := bsClear;
    C.TextOut(MidX + 20, 14, '3D Turtle L-System Branching Skeleton');
    C.Font.Style := [];
    CxR := MidX + (W - MidX) div 2;
    C.Pen.Color := RGBToColor(92, 224, 128);
    for I := 0 to T.BranchSegmentCount - 1 do
    begin
      Seg := T.GetBranchSegment(I);
      X1 := CxR + Round(Seg.StartPos.X * 72.0);
      Y1 := BaseY - Round(Seg.StartPos.Y * 72.0);
      X2 := CxR + Round(Seg.EndPos.X * 72.0);
      Y2 := BaseY - Round(Seg.EndPos.Y * 72.0);
      C.Pen.Width := Max(1, Round(Seg.Radius * 28.0));
      C.Line(X1, Y1, X2, Y2);
    end;
    C.Pen.Width := 1;
  end;
end;

end.
