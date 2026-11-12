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

{ Interactive Visual Node-Based PBR Material & X3D Shader Effect Graph Studio
  (@link(TMaterialGraphForm)) featuring a draggable 2D Bezier-wired DAG canvas,
  live CPU-raytraced PBR sphere preview with animation time stepping, node pin
  & parameter inspector, 5 built-in presets, and live compiled CGE @code(PLUG_*)
  Vertex + Fragment GLSL viewer (Phase 307). }
unit FormMaterialGraph;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Spin, Graphics, Clipbrd,
  CastleVectors, CastleColors, CastleTransform, CastleUtils,
  CastleMaterialGraph, ToolMaterialGraph;

type
  TMaterialGraphModifiedCallback = procedure(const AComment: String) of object;
  TMaterialGraphRefreshViewportCallback = procedure of object;

  TMaterialGraphForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSelectedTransform: TCastleTransform;
    FOnModified: TMaterialGraphModifiedCallback;
    FOnRefreshViewport: TMaterialGraphRefreshViewportCallback;

    FReport: TMaterialGraphAuditReport;
    FSelectedNodeIdx: Integer;
    FDraggingNodeIdx: Integer;
    FDragOffsetX: Single;
    FDragOffsetY: Single;
    FPreviewTimeSec: Single;
    FSyncingUi: Boolean;

    LblHeader: TLabel;
    ListGraphs: TListBox;
    CmbNewNodeKind: TComboBox;
    PaintGraph: TPaintBox;
    PaintSphere: TPaintBox;
    EdtNodeId: TEdit;
    SpinParamA: TFloatSpinEdit;
    SpinParamB: TFloatSpinEdit;
    SpinParamC: TFloatSpinEdit;
    SpinAlphaClip: TFloatSpinEdit;
    CmbPin0: TComboBox;
    CmbPin1: TComboBox;
    CmbPin2: TComboBox;
    MemoGlsl: TMemo;

    procedure BuildUi;
    function CurrentGraph: TCastleMaterialGraph;
    procedure RefreshAll;
    procedure PopulateNodeInspector;
    procedure NotifyChanged(const AComment: String);

    procedure ListGraphsClick(Sender: TObject);
    procedure BtnNewMossyClick(Sender: TObject);
    procedure BtnNewHologramClick(Sender: TObject);
    procedure BtnNewLavaClick(Sender: TObject);
    procedure BtnNewGoldClick(Sender: TObject);
    procedure BtnNewFoliageClick(Sender: TObject);
    procedure BtnSpawnSphereClick(Sender: TObject);
    procedure BtnAttachSelectedClick(Sender: TObject);
    procedure BtnAddNodeClick(Sender: TObject);
    procedure BtnDeleteNodeClick(Sender: TObject);
    procedure BtnStepTimeClick(Sender: TObject);
    procedure BtnApplyNodeParamsClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);

    procedure PaintGraphPaint(Sender: TObject);
    procedure PaintGraphMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintGraphMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PaintGraphMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintSpherePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const ASelectedTransform: TCastleTransform;
      const AOnModified: TMaterialGraphModifiedCallback;
      const AOnRefreshViewport: TMaterialGraphRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

const
  NodeCardW = 152;
  NodeCardH = 74;

constructor TMaterialGraphForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const ASelectedTransform: TCastleTransform;
  const AOnModified: TMaterialGraphModifiedCallback;
  const AOnRefreshViewport: TMaterialGraphRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSelectedTransform := ASelectedTransform;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FSelectedNodeIdx := 0;
  FDraggingNodeIdx := -1;
  FPreviewTimeSec := 0.5;

  Caption := 'Node-Based PBR Material & X3D Shader Effect Graph Studio';
  Position := poScreenCenter;
  Width := 1180;
  Height := 760;

  BuildUi;
  RefreshAll;
end;

destructor TMaterialGraphForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TMaterialGraphForm.BuildUi;
var
  TopBar, MainArea, LeftCol, CenterCol, RightCol, BottomBar, Row, PreviewRow: TPanel;
  Btn: TButton;
  Lbl: TLabel;
  Kind: TMaterialNodeKind;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 42;
  TopBar.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := TopBar;
  LblHeader.Left := 12;
  LblHeader.Top := 12;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Material Graphs: 0';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 44;
  BottomBar.BevelOuter := bvNone;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 12;
  Btn.Top := 8;
  Btn.Width := 230;
  Btn.Height := 28;
  Btn.Caption := 'Copy Markdown + GLSL Report';
  Btn.OnClick := @BtnCopyMarkdownClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 252;
  Btn.Top := 8;
  Btn.Width := 210;
  Btn.Height := 28;
  Btn.Caption := '+ Spawn Preview Sphere & Attach';
  Btn.OnClick := @BtnSpawnSphereClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 472;
  Btn.Top := 8;
  Btn.Width := 220;
  Btn.Height := 28;
  Btn.Caption := 'Attach Graph to Selected 3D Node';
  Btn.Enabled := FSelectedTransform <> nil;
  Btn.OnClick := @BtnAttachSelectedClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 1070;
  Btn.Top := 8;
  Btn.Width := 94;
  Btn.Height := 28;
  Btn.Anchors := [akTop, akRight];
  Btn.Caption := 'Close';
  Btn.OnClick := @BtnCloseClick;

  MainArea := TPanel.Create(Self);
  MainArea.Parent := Self;
  MainArea.Align := alClient;
  MainArea.BevelOuter := bvNone;

  { Left column: Graph list + 1-click preset spawners }
  LeftCol := TPanel.Create(Self);
  LeftCol.Parent := MainArea;
  LeftCol.Align := alLeft;
  LeftCol.Width := 215;
  LeftCol.BevelOuter := bvNone;
  LeftCol.BorderWidth := 6;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := LeftCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Design Material Graphs';

  ListGraphs := TListBox.Create(Self);
  ListGraphs.Parent := LeftCol;
  ListGraphs.Align := alTop;
  ListGraphs.Height := 160;
  ListGraphs.OnClick := @ListGraphsClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Mossy Rock Graph';
  Btn.OnClick := @BtnNewMossyClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Sci-Fi Hologram Graph';
  Btn.OnClick := @BtnNewHologramClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Molten Lava Cracks';
  Btn.OnClick := @BtnNewLavaClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Brushed Gold Metal';
  Btn.OnClick := @BtnNewGoldClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Wind-Wave Foliage';
  Btn.OnClick := @BtnNewFoliageClick;

  PreviewRow := TPanel.Create(Self);
  PreviewRow.Parent := LeftCol;
  PreviewRow.Align := alClient;
  PreviewRow.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PreviewRow;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Live PBR Sphere Preview';

  Btn := TButton.Create(Self);
  Btn.Parent := PreviewRow;
  Btn.Align := alBottom;
  Btn.Height := 26;
  Btn.Caption := 'Step Time (+0.25s)';
  Btn.OnClick := @BtnStepTimeClick;

  PaintSphere := TPaintBox.Create(Self);
  PaintSphere.Parent := PreviewRow;
  PaintSphere.Align := alClient;
  PaintSphere.OnPaint := @PaintSpherePaint;

  { Right column: Selected Node Inspector + Compiled GLSL }
  RightCol := TPanel.Create(Self);
  RightCol.Parent := MainArea;
  RightCol.Align := alRight;
  RightCol.Width := 320;
  RightCol.BevelOuter := bvNone;
  RightCol.BorderWidth := 6;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RightCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Selected Node & Pin Wiring';

  Row := TPanel.Create(Self);
  Row.Parent := RightCol;
  Row.Align := alTop;
  Row.Height := 232;
  Row.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Row;
  Lbl.Left := 4;
  Lbl.Top := 6;
  Lbl.Caption := 'NodeId:';
  EdtNodeId := TEdit.Create(Self);
  EdtNodeId.Parent := Row;
  EdtNodeId.Left := 74;
  EdtNodeId.Top := 2;
  EdtNodeId.Width := 130;
  EdtNodeId.ReadOnly := true;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Row;
  Lbl.Left := 4;
  Lbl.Top := 34;
  Lbl.Caption := 'Param A/B/C:';
  SpinParamA := TFloatSpinEdit.Create(Self);
  SpinParamA.Parent := Row;
  SpinParamA.Left := 82;
  SpinParamA.Top := 30;
  SpinParamA.Width := 70;
  SpinParamA.MinValue := -200;
  SpinParamA.MaxValue := 200;
  SpinParamA.Increment := 0.1;

  SpinParamB := TFloatSpinEdit.Create(Self);
  SpinParamB.Parent := Row;
  SpinParamB.Left := 156;
  SpinParamB.Top := 30;
  SpinParamB.Width := 70;
  SpinParamB.MinValue := -200;
  SpinParamB.MaxValue := 200;
  SpinParamB.Increment := 0.1;

  SpinParamC := TFloatSpinEdit.Create(Self);
  SpinParamC.Parent := Row;
  SpinParamC.Left := 230;
  SpinParamC.Top := 30;
  SpinParamC.Width := 70;
  SpinParamC.MinValue := -200;
  SpinParamC.MaxValue := 200;
  SpinParamC.Increment := 0.1;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Row;
  Lbl.Left := 4;
  Lbl.Top := 64;
  Lbl.Caption := 'Pin 0 Src:';
  CmbPin0 := TComboBox.Create(Self);
  CmbPin0.Parent := Row;
  CmbPin0.Left := 82;
  CmbPin0.Top := 60;
  CmbPin0.Width := 218;
  CmbPin0.Style := csDropDownList;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Row;
  Lbl.Left := 4;
  Lbl.Top := 92;
  Lbl.Caption := 'Pin 1 Src:';
  CmbPin1 := TComboBox.Create(Self);
  CmbPin1.Parent := Row;
  CmbPin1.Left := 82;
  CmbPin1.Top := 88;
  CmbPin1.Width := 218;
  CmbPin1.Style := csDropDownList;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Row;
  Lbl.Left := 4;
  Lbl.Top := 120;
  Lbl.Caption := 'Pin 2 Src:';
  CmbPin2 := TComboBox.Create(Self);
  CmbPin2.Parent := Row;
  CmbPin2.Left := 82;
  CmbPin2.Top := 116;
  CmbPin2.Width := 218;
  CmbPin2.Style := csDropDownList;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Row;
  Lbl.Left := 4;
  Lbl.Top := 150;
  Lbl.Caption := 'AlphaClip:';
  SpinAlphaClip := TFloatSpinEdit.Create(Self);
  SpinAlphaClip.Parent := Row;
  SpinAlphaClip.Left := 82;
  SpinAlphaClip.Top := 146;
  SpinAlphaClip.Width := 85;
  SpinAlphaClip.MinValue := 0.0;
  SpinAlphaClip.MaxValue := 0.99;
  SpinAlphaClip.Increment := 0.05;

  Btn := TButton.Create(Self);
  Btn.Parent := Row;
  Btn.Left := 4;
  Btn.Top := 182;
  Btn.Width := 185;
  Btn.Height := 28;
  Btn.Caption := 'Apply Node & Pin Edits';
  Btn.OnClick := @BtnApplyNodeParamsClick;

  Btn := TButton.Create(Self);
  Btn.Parent := Row;
  Btn.Left := 196;
  Btn.Top := 182;
  Btn.Width := 104;
  Btn.Height := 28;
  Btn.Caption := 'Delete Node';
  Btn.OnClick := @BtnDeleteNodeClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RightCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Compiled CGE PLUG_* Vertex & Fragment GLSL';

  MemoGlsl := TMemo.Create(Self);
  MemoGlsl.Parent := RightCol;
  MemoGlsl.Align := alClient;
  MemoGlsl.ReadOnly := true;
  MemoGlsl.ScrollBars := ssBoth;
  MemoGlsl.Font.Name := 'Monospace';

  { Center column: Interactive 2D DAG Canvas }
  CenterCol := TPanel.Create(Self);
  CenterCol.Parent := MainArea;
  CenterCol.Align := alClient;
  CenterCol.BevelOuter := bvNone;
  CenterCol.BorderWidth := 6;

  Row := TPanel.Create(Self);
  Row.Parent := CenterCol;
  Row.Align := alTop;
  Row.Height := 34;
  Row.BevelOuter := bvNone;

  CmbNewNodeKind := TComboBox.Create(Self);
  CmbNewNodeKind.Parent := Row;
  CmbNewNodeKind.Left := 0;
  CmbNewNodeKind.Top := 4;
  CmbNewNodeKind.Width := 210;
  CmbNewNodeKind.Style := csDropDownList;
  for Kind := Low(TMaterialNodeKind) to High(TMaterialNodeKind) do
    if Kind <> mnkPbrOutput then
      CmbNewNodeKind.Items.AddObject(TCastleMaterialGraph.NodeKindDisplayName(Kind),
        TObject(PtrInt(Ord(Kind))));
  CmbNewNodeKind.ItemIndex := 4;

  Btn := TButton.Create(Self);
  Btn.Parent := Row;
  Btn.Left := 218;
  Btn.Top := 3;
  Btn.Width := 125;
  Btn.Height := 26;
  Btn.Caption := '+ Add Graph Node';
  Btn.OnClick := @BtnAddNodeClick;

  PaintGraph := TPaintBox.Create(Self);
  PaintGraph.Parent := CenterCol;
  PaintGraph.Align := alClient;
  PaintGraph.OnPaint := @PaintGraphPaint;
  PaintGraph.OnMouseDown := @PaintGraphMouseDown;
  PaintGraph.OnMouseMove := @PaintGraphMouseMove;
  PaintGraph.OnMouseUp := @PaintGraphMouseUp;
end;

function TMaterialGraphForm.CurrentGraph: TCastleMaterialGraph;
var
  Idx: Integer;
begin
  Result := nil;
  if FReport = nil then
    Exit;
  Idx := ListGraphs.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Graphs)) then
    Result := FReport.Graphs[Idx];
end;

procedure TMaterialGraphForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TMaterialGraphForm.RefreshAll;
var
  PrevSel: Integer;
  I: Integer;
  G: TCastleMaterialGraph;
begin
  PrevSel := ListGraphs.ItemIndex;
  FreeAndNil(FReport);
  FReport := TMaterialGraphHelper.ScanDesign(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Material Graphs: %d (%d total nodes, %d vertex-offset, %d alpha-clip) | Bound Shaders: %d | Warnings: %d',
    [Length(FReport.Graphs), FReport.TotalNodes, FReport.VertexOffsetGraphs,
     FReport.AlphaClipGraphs, Length(FReport.Behaviors), FReport.Warnings.Count]);

  ListGraphs.Items.BeginUpdate;
  try
    ListGraphs.Items.Clear;
    for I := 0 to High(FReport.Graphs) do
    begin
      G := FReport.Graphs[I];
      ListGraphs.Items.Add(Format('%s (%s, %d nodes)',
        [G.Name, TCastleMaterialGraph.PresetDisplayName(G.Preset), G.NodeCount]));
    end;
    if ListGraphs.Items.Count > 0 then
      ListGraphs.ItemIndex := Clamped(Max(0, PrevSel), 0, ListGraphs.Items.Count - 1);
  finally
    ListGraphs.Items.EndUpdate;
  end;

  PopulateNodeInspector;
  PaintGraph.Invalidate;
  PaintSphere.Invalidate;
end;

procedure TMaterialGraphForm.PopulateNodeInspector;
var
  G: TCastleMaterialGraph;
  N: TMaterialGraphNode;
  I: Integer;

  procedure FillPinCombo(const Cmb: TComboBox; const CurrentSrc: String);
  var
    K, MatchIdx: Integer;
  begin
    Cmb.Items.BeginUpdate;
    try
      Cmb.Items.Clear;
      Cmb.Items.Add('(Disconnected)');
      MatchIdx := 0;
      if G <> nil then
        for K := 0 to G.NodeCount - 1 do
          if K <> FSelectedNodeIdx then
          begin
            Cmb.Items.Add(G.Nodes[K].NodeId);
            if SameText(G.Nodes[K].NodeId, CurrentSrc) then
              MatchIdx := Cmb.Items.Count - 1;
          end;
      Cmb.ItemIndex := MatchIdx;
    finally
      Cmb.Items.EndUpdate;
    end;
  end;

begin
  FSyncingUi := true;
  try
    G := CurrentGraph;
    if G = nil then
    begin
      EdtNodeId.Text := '';
      MemoGlsl.Lines.Text := '// Click "+ Mossy Rock Graph" or another preset on the left to create a TCastleMaterialGraph.';
      Exit;
    end;

    SpinAlphaClip.Value := G.AlphaClipThreshold;
    if (FSelectedNodeIdx < 0) or (FSelectedNodeIdx >= G.NodeCount) then
      FSelectedNodeIdx := Max(0, G.NodeCount - 1);

    if (FSelectedNodeIdx >= 0) and (FSelectedNodeIdx < G.NodeCount) then
    begin
      N := G.Nodes[FSelectedNodeIdx];
      EdtNodeId.Text := N.NodeId + ' [' + TCastleMaterialGraph.NodeKindDisplayName(N.Kind) + ']';
      SpinParamA.Value := N.ParamA;
      SpinParamB.Value := N.ParamB;
      SpinParamC.Value := N.ParamC;
      FillPinCombo(CmbPin0, N.Inputs[0]);
      FillPinCombo(CmbPin1, N.Inputs[1]);
      FillPinCombo(CmbPin2, N.Inputs[2]);
    end;

    MemoGlsl.Lines.BeginUpdate;
    try
      MemoGlsl.Lines.Clear;
      MemoGlsl.Lines.Add(G.BuildVertexShaderSource);
      MemoGlsl.Lines.Add('');
      MemoGlsl.Lines.Add(G.BuildFragmentShaderSource);
      if FReport.Warnings.Count > 0 then
      begin
        MemoGlsl.Lines.Add('');
        MemoGlsl.Lines.Add('/* DAG Warnings:');
        for I := 0 to FReport.Warnings.Count - 1 do
          MemoGlsl.Lines.Add('   - ' + FReport.Warnings[I]);
        MemoGlsl.Lines.Add('*/');
      end;
    finally
      MemoGlsl.Lines.EndUpdate;
    end;
  finally
    FSyncingUi := false;
  end;
end;

procedure TMaterialGraphForm.ListGraphsClick(Sender: TObject);
begin
  FSelectedNodeIdx := 0;
  PopulateNodeInspector;
  PaintGraph.Invalidate;
  PaintSphere.Invalidate;
end;

procedure TMaterialGraphForm.BtnNewMossyClick(Sender: TObject);
begin
  TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
    mgpTriplanarMossyRock, 'MossyRockGraph');
  NotifyChanged('Create Mossy Rock Material Graph');
  RefreshAll;
  ListGraphs.ItemIndex := ListGraphs.Items.Count - 1;
  ListGraphsClick(nil);
end;

procedure TMaterialGraphForm.BtnNewHologramClick(Sender: TObject);
begin
  TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
    mgpHologramScanline, 'HologramGraph');
  NotifyChanged('Create Hologram Material Graph');
  RefreshAll;
  ListGraphs.ItemIndex := ListGraphs.Items.Count - 1;
  ListGraphsClick(nil);
end;

procedure TMaterialGraphForm.BtnNewLavaClick(Sender: TObject);
begin
  TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
    mgpMoltenLavaCracks, 'LavaCracksGraph');
  NotifyChanged('Create Molten Lava Material Graph');
  RefreshAll;
  ListGraphs.ItemIndex := ListGraphs.Items.Count - 1;
  ListGraphsClick(nil);
end;

procedure TMaterialGraphForm.BtnNewGoldClick(Sender: TObject);
begin
  TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
    mgpBrushedGoldMetal, 'BrushedGoldGraph');
  NotifyChanged('Create Brushed Gold Material Graph');
  RefreshAll;
  ListGraphs.ItemIndex := ListGraphs.Items.Count - 1;
  ListGraphsClick(nil);
end;

procedure TMaterialGraphForm.BtnNewFoliageClick(Sender: TObject);
begin
  TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
    mgpAnimatedWindWaveFoliage, 'WindFoliageGraph');
  NotifyChanged('Create Wind-Wave Foliage Material Graph');
  RefreshAll;
  ListGraphs.ItemIndex := ListGraphs.Items.Count - 1;
  ListGraphsClick(nil);
end;

procedure TMaterialGraphForm.BtnSpawnSphereClick(Sender: TObject);
var
  G: TCastleMaterialGraph;
begin
  G := CurrentGraph;
  if G = nil then
    G := TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
      mgpTriplanarMossyRock, 'MossyRockGraph');
  TMaterialGraphHelper.SpawnPreviewSphereWithGraph(FDesignRoot, FDesignOwner, G);
  NotifyChanged('Spawn Material Graph Preview Sphere');
  RefreshAll;
end;

procedure TMaterialGraphForm.BtnAttachSelectedClick(Sender: TObject);
var
  G: TCastleMaterialGraph;
begin
  if FSelectedTransform = nil then
    Exit;
  G := CurrentGraph;
  if G = nil then
    G := TMaterialGraphHelper.CreateMaterialGraphInDesign(FDesignRoot, FDesignOwner,
      mgpTriplanarMossyRock, 'MossyRockGraph');
  TMaterialGraphHelper.AttachGraphToTransform(FSelectedTransform, FDesignOwner, G);
  NotifyChanged('Attach Material Graph Shader');
  RefreshAll;
end;

procedure TMaterialGraphForm.BtnAddNodeClick(Sender: TObject);
var
  G: TCastleMaterialGraph;
  Kind: TMaterialNodeKind;
  NewId: String;
  Seq: Integer;
begin
  G := CurrentGraph;
  if (G = nil) or (CmbNewNodeKind.ItemIndex < 0) then
    Exit;
  Kind := TMaterialNodeKind(PtrInt(CmbNewNodeKind.Items.Objects[CmbNewNodeKind.ItemIndex]));
  Seq := G.NodeCount + 1;
  repeat
    NewId := 'Node' + IntToStr(Seq);
    Inc(Seq);
  until G.FindNodeIndex(NewId) < 0;
  FSelectedNodeIdx := G.AddOrUpdateNode(
    TCastleMaterialGraph.MakeDefaultNode(NewId, Kind, 160, 140));
  NotifyChanged('Add Material Graph Node');
  RefreshAll;
end;

procedure TMaterialGraphForm.BtnDeleteNodeClick(Sender: TObject);
var
  G: TCastleMaterialGraph;
begin
  G := CurrentGraph;
  if (G = nil) or (FSelectedNodeIdx < 0) or (FSelectedNodeIdx >= G.NodeCount) then
    Exit;
  if G.Nodes[FSelectedNodeIdx].Kind = mnkPbrOutput then
    Exit;
  G.RemoveNode(G.Nodes[FSelectedNodeIdx].NodeId);
  FSelectedNodeIdx := 0;
  NotifyChanged('Remove Material Graph Node');
  RefreshAll;
end;

procedure TMaterialGraphForm.BtnStepTimeClick(Sender: TObject);
begin
  FPreviewTimeSec := FPreviewTimeSec + 0.25;
  PaintSphere.Invalidate;
end;

procedure TMaterialGraphForm.BtnApplyNodeParamsClick(Sender: TObject);
var
  G: TCastleMaterialGraph;
  N: TMaterialGraphNode;

  function ComboPinId(const Cmb: TComboBox): String;
  begin
    if Cmb.ItemIndex <= 0 then
      Result := ''
    else
      Result := Cmb.Items[Cmb.ItemIndex];
  end;

begin
  if FSyncingUi then
    Exit;
  G := CurrentGraph;
  if (G = nil) or (FSelectedNodeIdx < 0) or (FSelectedNodeIdx >= G.NodeCount) then
    Exit;
  G.AlphaClipThreshold := SpinAlphaClip.Value;
  N := G.Nodes[FSelectedNodeIdx];
  N.ParamA := SpinParamA.Value;
  N.ParamB := SpinParamB.Value;
  N.ParamC := SpinParamC.Value;
  N.Inputs[0] := ComboPinId(CmbPin0);
  N.Inputs[1] := ComboPinId(CmbPin1);
  N.Inputs[2] := ComboPinId(CmbPin2);
  G.AddOrUpdateNode(N);
  NotifyChanged('Update Material Graph Node Parameters');
  RefreshAll;
end;

procedure TMaterialGraphForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TMaterialGraphHelper.BuildMarkdownReport(
    FDesignRoot, FDesignOwner, CurrentGraph);
end;

procedure TMaterialGraphForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TMaterialGraphForm.PaintGraphPaint(Sender: TObject);
var
  C: TCanvas;
  G: TCastleMaterialGraph;
  I, P, SrcIdx, PinCnt, X1, Y1, X2, Y2, Seg, Steps: Integer;
  T, U0, BX, BY, PrevX, PrevY: Single;
  N: TMaterialGraphNode;
  HeaderCol: TColor;
begin
  C := PaintGraph.Canvas;
  C.Brush.Color := RGBToColor(24, 26, 32);
  C.FillRect(0, 0, PaintGraph.Width, PaintGraph.Height);

  { Subtle 24px grid }
  C.Pen.Color := RGBToColor(34, 38, 48);
  C.Pen.Width := 1;
  I := 0;
  while I < PaintGraph.Width do
  begin
    C.Line(I, 0, I, PaintGraph.Height);
    Inc(I, 24);
  end;
  I := 0;
  while I < PaintGraph.Height do
  begin
    C.Line(0, I, PaintGraph.Width, I);
    Inc(I, 24);
  end;

  G := CurrentGraph;
  if G = nil then
  begin
    C.Font.Color := RGBToColor(180, 190, 210);
    C.Brush.Style := bsClear;
    C.TextOut(24, 24, 'No TCastleMaterialGraph in design yet — click a preset button on the left.');
    Exit;
  end;

  { Draw cubic Bezier connection wires }
  C.Pen.Color := RGBToColor(92, 208, 255);
  C.Pen.Width := 2;
  for I := 0 to G.NodeCount - 1 do
  begin
    N := G.Nodes[I];
    PinCnt := TCastleMaterialGraph.NodeInputCount(N.Kind);
    for P := 0 to PinCnt - 1 do
      if Trim(N.Inputs[P]) <> '' then
      begin
        SrcIdx := G.FindNodeIndex(Trim(N.Inputs[P]));
        if SrcIdx >= 0 then
        begin
          X1 := Round(G.Nodes[SrcIdx].PosX) + NodeCardW;
          Y1 := Round(G.Nodes[SrcIdx].PosY) + 38;
          X2 := Round(N.PosX);
          Y2 := Round(N.PosY) + 26 + P * 10;
          Steps := 16;
          PrevX := X1;
          PrevY := Y1;
          for Seg := 1 to Steps do
          begin
            T := Seg / Steps;
            U0 := 1.0 - T;
            BX := U0 * U0 * U0 * X1 + 3 * U0 * U0 * T * (X1 + 56) +
                  3 * U0 * T * T * (X2 - 56) + T * T * T * X2;
            BY := U0 * U0 * U0 * Y1 + 3 * U0 * U0 * T * Y1 +
                  3 * U0 * T * T * Y2 + T * T * T * Y2;
            C.Line(Round(PrevX), Round(PrevY), Round(BX), Round(BY));
            PrevX := BX;
            PrevY := BY;
          end;
        end;
      end;
  end;

  { Draw node cards }
  for I := 0 to G.NodeCount - 1 do
  begin
    N := G.Nodes[I];
    X1 := Round(N.PosX);
    Y1 := Round(N.PosY);

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(40, 44, 54);
    if I = FSelectedNodeIdx then
    begin
      C.Pen.Color := RGBToColor(255, 208, 72);
      C.Pen.Width := 2;
    end else
    begin
      C.Pen.Color := RGBToColor(78, 86, 104);
      C.Pen.Width := 1;
    end;
    C.RoundRect(X1, Y1, X1 + NodeCardW, Y1 + NodeCardH, 8, 8);

    case N.Kind of
      mnkPbrOutput: HeaderCol := RGBToColor(168, 62, 92);
      mnkNoise3D, mnkVoronoi3D, mnkChecker3D, mnkSineWave: HeaderCol := RGBToColor(52, 118, 86);
      mnkMixColor, mnkAdd, mnkMultiply, mnkRemapSmoothstep: HeaderCol := RGBToColor(64, 96, 158);
    else
      HeaderCol := RGBToColor(98, 78, 146);
    end;
    C.Brush.Color := HeaderCol;
    C.Pen.Style := psClear;
    C.RoundRect(X1 + 1, Y1 + 1, X1 + NodeCardW - 1, Y1 + 22, 6, 6);
    C.Pen.Style := psSolid;

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.Font.Style := [fsBold];
    C.TextOut(X1 + 7, Y1 + 3, N.NodeId);
    C.Font.Style := [];
    C.Font.Color := RGBToColor(196, 204, 220);
    C.TextOut(X1 + 7, Y1 + 25, Copy(TCastleMaterialGraph.NodeKindDisplayName(N.Kind), 1, 20));
    C.Font.Color := RGBToColor(148, 168, 196);
    C.TextOut(X1 + 7, Y1 + 44, Format('A:%.2f B:%.2f', [N.ParamA, N.ParamB]));
  end;
end;

procedure TMaterialGraphForm.PaintGraphMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  G: TCastleMaterialGraph;
  I, NX, NY: Integer;
begin
  if Button <> mbLeft then
    Exit;
  G := CurrentGraph;
  if G = nil then
    Exit;
  for I := G.NodeCount - 1 downto 0 do
  begin
    NX := Round(G.Nodes[I].PosX);
    NY := Round(G.Nodes[I].PosY);
    if (X >= NX) and (X <= NX + NodeCardW) and
       (Y >= NY) and (Y <= NY + NodeCardH) then
    begin
      FSelectedNodeIdx := I;
      FDraggingNodeIdx := I;
      FDragOffsetX := X - G.Nodes[I].PosX;
      FDragOffsetY := Y - G.Nodes[I].PosY;
      PopulateNodeInspector;
      PaintGraph.Invalidate;
      Exit;
    end;
  end;
end;

procedure TMaterialGraphForm.PaintGraphMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
var
  G: TCastleMaterialGraph;
  N: TMaterialGraphNode;
begin
  if FDraggingNodeIdx < 0 then
    Exit;
  G := CurrentGraph;
  if (G = nil) or (FDraggingNodeIdx >= G.NodeCount) then
    Exit;
  N := G.Nodes[FDraggingNodeIdx];
  N.PosX := Max(4.0, X - FDragOffsetX);
  N.PosY := Max(4.0, Y - FDragOffsetY);
  G.AddOrUpdateNode(N);
  PaintGraph.Invalidate;
end;

procedure TMaterialGraphForm.PaintGraphMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNodeIdx >= 0 then
  begin
    FDraggingNodeIdx := -1;
    NotifyChanged('Move Material Graph Node');
  end;
end;

procedure TMaterialGraphForm.PaintSpherePaint(Sender: TObject);
const
  BlockPx = 3;
var
  G: TCastleMaterialGraph;
  C: TCanvas;
  W, H, PY, PX: Integer;
  Col: TCastleColor;
begin
  C := PaintSphere.Canvas;
  W := Max(1, PaintSphere.Width);
  H := Max(1, PaintSphere.Height);
  G := CurrentGraph;
  if G = nil then
  begin
    C.Brush.Color := RGBToColor(28, 30, 36);
    C.FillRect(0, 0, W, H);
    Exit;
  end;

  PY := 0;
  while PY < H do
  begin
    PX := 0;
    while PX < W do
    begin
      Col := G.EvaluatePreviewPixel((PX + 0.5) / W, (PY + 0.5) / H, FPreviewTimeSec, true);
      C.Brush.Color := RGBToColor(
        Round(Clamped(Col.X, 0.0, 1.0) * 255),
        Round(Clamped(Col.Y, 0.0, 1.0) * 255),
        Round(Clamped(Col.Z, 0.0, 1.0) * 255));
      C.FillRect(PX, PY, Min(W, PX + BlockPx), Min(H, PY + BlockPx));
      Inc(PX, BlockPx);
    end;
    Inc(PY, BlockPx);
  end;
end;

end.
