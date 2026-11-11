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

{ Interactive 3-Column Bidirectional Asset Reference Graph, Broken-URL
  Auto-Repair & Orphan Asset Sweeper Studio (@link(TAssetGraphForm))
  (Phase 292 — UE 5.9 / 6.0 Reference Viewer Parity). }
unit FormAssetGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Clipbrd, Types,
  ToolAssetGraph;

type
  TGraphHitCard = record
    Bounds: TRect;
    TargetRelPath: String;
  end;

  TAssetGraphForm = class(TForm)
  private
    FDataDirPath: String;
    FReport: TAssetGraphReport;
    FFilteredNodeIndices: array of Integer;
    FActiveNodeIdx: Integer;
    FHitCards: array of TGraphHitCard;

    { Top bar }
    EditSearch: TEdit;
    ButtonRescan: TButton;
    ButtonRepairUrls: TButton;
    ButtonSweepOrphans: TButton;
    ButtonCopyMarkdown: TButton;

    { Left asset list }
    ListAssets: TListBox;

    { Center 3-column Reference Graph Canvas }
    PaintBoxGraph: TPaintBox;

    { Bottom audit tabs }
    PageBottom: TPageControl;
    TabRepairs: TTabSheet;
    ListRepairs: TListBox;
    TabOrphans: TTabSheet;
    ListOrphans: TListBox;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    procedure RescanProjectData;
    procedure RebuildFilteredAssetList;
    procedure SelectAssetByRelPath(const ARelPath: String);

    procedure EditSearchChange(Sender: TObject);
    procedure ListAssetsSelectionChange(Sender: TObject; User: Boolean);
    procedure PaintBoxGraphPaint(Sender: TObject);
    procedure PaintBoxGraphMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ButtonRescanClick(Sender: TObject);
    procedure ButtonRepairUrlsClick(Sender: TObject);
    procedure ButtonSweepOrphansClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADataDirPath: String; const AInitialRelPath: String = '');
  end;

implementation

uses
  StrUtils;

constructor TAssetGraphForm.CreateStudio(AOwner: TComponent;
  const ADataDirPath: String; const AInitialRelPath: String);
begin
  inherited CreateNew(AOwner, 0);
  FDataDirPath := ADataDirPath;
  FActiveNodeIdx := -1;
  BuildUi;
  RescanProjectData;
  if AInitialRelPath <> '' then
    SelectAssetByRelPath(AInitialRelPath);
end;

procedure TAssetGraphForm.BuildUi;
var
  PanelTop, PanelBottom, PanelLeft, PanelMain: TPanel;
  SplitterLR, SplitterTB: TSplitter;
  Lbl: TLabel;
begin
  Caption := 'Bidirectional Asset Reference Graph, Orphan Sweeper & Broken-URL Auto-Repair (UE 5.9 / 6.0 Parity)';
  Width := 1120;
  Height := 700;
  Position := poMainFormCenter;
  Constraints.MinWidth := 920;
  Constraints.MinHeight := 560;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 46;
  PanelTop.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelTop;
  Lbl.SetBounds(10, 14, 42, 18);
  Lbl.Caption := 'Filter:';

  EditSearch := TEdit.Create(Self);
  EditSearch.Parent := PanelTop;
  EditSearch.SetBounds(54, 10, 210, 26);
  EditSearch.TextHint := 'Search asset filename or folder...';
  EditSearch.OnChange := @EditSearchChange;

  ButtonRescan := TButton.Create(Self);
  ButtonRescan.Parent := PanelTop;
  ButtonRescan.SetBounds(274, 8, 126, 30);
  ButtonRescan.Caption := 'Rescan data/';
  ButtonRescan.OnClick := @ButtonRescanClick;

  ButtonRepairUrls := TButton.Create(Self);
  ButtonRepairUrls.Parent := PanelTop;
  ButtonRepairUrls.SetBounds(408, 8, 210, 30);
  ButtonRepairUrls.Caption := 'Auto-Repair Broken URLs (0)';
  ButtonRepairUrls.OnClick := @ButtonRepairUrlsClick;

  ButtonSweepOrphans := TButton.Create(Self);
  ButtonSweepOrphans.Parent := PanelTop;
  ButtonSweepOrphans.SetBounds(626, 8, 224, 30);
  ButtonSweepOrphans.Caption := 'Quarantine Orphans to Trash (0)';
  ButtonSweepOrphans.OnClick := @ButtonSweepOrphansClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(858, 8, 186, 30);
  ButtonCopyMarkdown.Caption := 'Copy Markdown + Mermaid';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 38;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.SetBounds(12, 10, 860, 18);
  LabelStatus.Caption := 'Ready.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.BorderSpacing.Around := 5;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 310;
  PanelLeft.BorderSpacing.Around := 4;
  PanelLeft.BevelOuter := bvNone;

  ListAssets := TListBox.Create(Self);
  ListAssets.Parent := PanelLeft;
  ListAssets.Align := alClient;
  ListAssets.OnSelectionChange := @ListAssetsSelectionChange;

  SplitterLR := TSplitter.Create(Self);
  SplitterLR.Parent := Self;
  SplitterLR.Align := alLeft;

  PanelMain := TPanel.Create(Self);
  PanelMain.Parent := Self;
  PanelMain.Align := alClient;
  PanelMain.BevelOuter := bvNone;

  PageBottom := TPageControl.Create(Self);
  PageBottom.Parent := PanelMain;
  PageBottom.Align := alBottom;
  PageBottom.Height := 180;

  TabRepairs := TTabSheet.Create(Self);
  TabRepairs.PageControl := PageBottom;
  TabRepairs.Caption := 'Broken-URL Auto-Repairs';

  ListRepairs := TListBox.Create(Self);
  ListRepairs.Parent := TabRepairs;
  ListRepairs.Align := alClient;

  TabOrphans := TTabSheet.Create(Self);
  TabOrphans.PageControl := PageBottom;
  TabOrphans.Caption := 'Unreferenced Orphan Assets';

  ListOrphans := TListBox.Create(Self);
  ListOrphans.Parent := TabOrphans;
  ListOrphans.Align := alClient;

  SplitterTB := TSplitter.Create(Self);
  SplitterTB.Parent := PanelMain;
  SplitterTB.Align := alBottom;
  SplitterTB.Top := PageBottom.Top - 4;

  PaintBoxGraph := TPaintBox.Create(Self);
  PaintBoxGraph.Parent := PanelMain;
  PaintBoxGraph.Align := alClient;
  PaintBoxGraph.OnPaint := @PaintBoxGraphPaint;
  PaintBoxGraph.OnMouseDown := @PaintBoxGraphMouseDown;
end;

procedure TAssetGraphForm.RescanProjectData;
var
  I: Integer;
begin
  FReport := TAssetDependencyAnalyzer.AnalyzeDataDirectory(FDataDirPath);

  ListRepairs.Items.BeginUpdate;
  try
    ListRepairs.Items.Clear;
    for I := 0 to High(FReport.Repairs) do
      ListRepairs.Items.Add(Format('[%s]  %s  -->  %s  (%s)',
        [FReport.Repairs[I].OwnerAssetRelPath,
         FReport.Repairs[I].BrokenUrl,
         FReport.Repairs[I].SuggestedUrl,
         FReport.Repairs[I].MatchReason]));
    if ListRepairs.Items.Count = 0 then
      ListRepairs.Items.Add('No broken URLs detected in data/.');
  finally
    ListRepairs.Items.EndUpdate;
  end;

  ListOrphans.Items.BeginUpdate;
  try
    ListOrphans.Items.Clear;
    for I := 0 to High(FReport.Nodes) do
      if FReport.Nodes[I].IsOrphan then
        ListOrphans.Items.Add(Format('%s  [%s | %s]',
          [FReport.Nodes[I].DataRelPath,
           AssetCategoryToDisplayName(FReport.Nodes[I].Category),
           FormatByteSizeShort(FReport.Nodes[I].SizeBytes)]));
    if ListOrphans.Items.Count = 0 then
      ListOrphans.Items.Add('Zero unreferenced orphan assets found.');
  finally
    ListOrphans.Items.EndUpdate;
  end;

  ButtonRepairUrls.Caption := Format('Auto-Repair Broken URLs (%d)',
    [Length(FReport.Repairs)]);
  ButtonRepairUrls.Enabled := Length(FReport.Repairs) > 0;

  ButtonSweepOrphans.Caption := Format('Quarantine Orphans (%d | %s)',
    [FReport.OrphanCount, FormatByteSizeShort(FReport.OrphanBytes)]);
  ButtonSweepOrphans.Enabled := FReport.OrphanCount > 0;

  RebuildFilteredAssetList;

  LabelStatus.Caption := Format(
    'Scanned %s: %d assets (%s) | Orphans: %d (%s) | Broken URLs: %d',
    [FDataDirPath, FReport.TotalAssets, FormatByteSizeShort(FReport.TotalBytes),
     FReport.OrphanCount, FormatByteSizeShort(FReport.OrphanBytes),
     FReport.BrokenUrlCount]);
end;

procedure TAssetGraphForm.RebuildFilteredAssetList;
var
  Q, Flags: String;
  I, N: Integer;
begin
  Q := LowerCase(Trim(EditSearch.Text));
  SetLength(FFilteredNodeIndices, 0);

  ListAssets.Items.BeginUpdate;
  try
    ListAssets.Items.Clear;
    for I := 0 to High(FReport.Nodes) do
    begin
      if (Q <> '') and (Pos(Q, LowerCase(FReport.Nodes[I].DataRelPath)) = 0) then
        Continue;
      N := Length(FFilteredNodeIndices);
      SetLength(FFilteredNodeIndices, N + 1);
      FFilteredNodeIndices[N] := I;

      Flags := '';
      if FReport.Nodes[I].IsOrphan then
        Flags := Flags + ' [ORPHAN]';
      if Length(FReport.Nodes[I].BrokenUrls) > 0 then
        Flags := Flags + Format(' [BROKEN:%d]', [Length(FReport.Nodes[I].BrokenUrls)]);

      ListAssets.Items.Add(Format('%s (In:%d Out:%d)%s',
        [FReport.Nodes[I].DataRelPath,
         Length(FReport.Nodes[I].Referencers),
         Length(FReport.Nodes[I].Dependencies),
         Flags]));
    end;

    if Length(FFilteredNodeIndices) > 0 then
    begin
      ListAssets.ItemIndex := 0;
      FActiveNodeIdx := FFilteredNodeIndices[0];
    end else
      FActiveNodeIdx := -1;
  finally
    ListAssets.Items.EndUpdate;
  end;

  PaintBoxGraph.Invalidate;
end;

procedure TAssetGraphForm.SelectAssetByRelPath(const ARelPath: String);
var
  I, NodeIdx: Integer;
begin
  NodeIdx := TAssetDependencyAnalyzer.FindNodeIndex(FReport, ARelPath);
  if NodeIdx < 0 then
    Exit;
  FActiveNodeIdx := NodeIdx;
  for I := 0 to High(FFilteredNodeIndices) do
    if FFilteredNodeIndices[I] = NodeIdx then
    begin
      ListAssets.ItemIndex := I;
      Break;
    end;
  PaintBoxGraph.Invalidate;
end;

procedure TAssetGraphForm.EditSearchChange(Sender: TObject);
begin
  RebuildFilteredAssetList;
end;

procedure TAssetGraphForm.ListAssetsSelectionChange(Sender: TObject;
  User: Boolean);
var
  Idx: Integer;
begin
  Idx := ListAssets.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FFilteredNodeIndices)) then
  begin
    FActiveNodeIdx := FFilteredNodeIndices[Idx];
    PaintBoxGraph.Invalidate;
  end;
end;

procedure TAssetGraphForm.PaintBoxGraphPaint(Sender: TObject);
var
  C: TCanvas;
  R, CenterRect, CardRect: TRect;
  Node: TAssetNodeInfo;
  ColW, LeftX, MidX, RightX, MidY, CardH, GapY, MaxShow, I, YTop: Integer;

  procedure RegisterHitCard(const ABounds: TRect; const ARelPath: String);
  var
    K: Integer;
  begin
    K := Length(FHitCards);
    SetLength(FHitCards, K + 1);
    FHitCards[K].Bounds := ABounds;
    FHitCards[K].TargetRelPath := ARelPath;
  end;

  procedure DrawCubicWire(const X1, Y1, X2, Y2: Integer; const Col: TColor);
  var
    Pts: array [0..3] of TPoint;
    DX: Integer;
  begin
    DX := Max(30, Abs(X2 - X1) div 2);
    Pts[0] := Point(X1, Y1);
    Pts[1] := Point(X1 + DX, Y1);
    Pts[2] := Point(X2 - DX, Y2);
    Pts[3] := Point(X2, Y2);
    C.Pen.Color := Col;
    C.Pen.Width := 2;
    C.PolyBezier(Pts);
  end;

begin
  SetLength(FHitCards, 0);
  C := PaintBoxGraph.Canvas;
  R := PaintBoxGraph.ClientRect;
  C.Brush.Color := RGBToColor(20, 24, 32);
  C.FillRect(R);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(168, 182, 204);
  C.TextOut(14, 8, 'REFERENCERS (Used By ->)');
  C.TextOut((R.Right div 2) - 65, 8, 'SELECTED ASSET');
  C.TextOut(Max(300, R.Right - 240), 8, 'DEPENDENCIES (-> Uses)');

  if (FActiveNodeIdx < 0) or (FActiveNodeIdx > High(FReport.Nodes)) then
  begin
    C.Font.Color := RGBToColor(150, 162, 180);
    C.TextOut(20, 44, 'Select an asset on the left to inspect its bidirectional reference graph.');
    Exit;
  end;

  Node := FReport.Nodes[FActiveNodeIdx];
  ColW := Min(230, Max(145, (R.Right - 90) div 3));
  LeftX := 16;
  MidX := (R.Right - ColW) div 2;
  RightX := R.Right - ColW - 16;
  MidY := Max(90, R.Bottom div 2);

  CenterRect := Rect(MidX, MidY - 38, MidX + ColW, MidY + 38);

  { 1. Left column: Referencers }
  CardH := 34;
  GapY := 8;
  MaxShow := Min(8, Length(Node.Referencers));
  for I := 0 to MaxShow - 1 do
  begin
    YTop := MidY - ((MaxShow * (CardH + GapY)) div 2) + I * (CardH + GapY);
    CardRect := Rect(LeftX, YTop, LeftX + ColW, YTop + CardH);
    DrawCubicWire(CardRect.Right, (CardRect.Top + CardRect.Bottom) div 2,
      CenterRect.Left, MidY, RGBToColor(78, 178, 252));

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(34, 46, 66);
    C.Pen.Color := RGBToColor(86, 168, 242);
    C.Pen.Width := 1;
    C.RoundRect(CardRect, 8, 8);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(225, 236, 250);
    C.TextOut(CardRect.Left + 8, CardRect.Top + 9,
      ExtractFileName(Node.Referencers[I]));
    RegisterHitCard(CardRect, Node.Referencers[I]);
  end;

  { 2. Right column: Dependencies + Broken URLs }
  MaxShow := Min(7, Length(Node.Dependencies));
  for I := 0 to MaxShow - 1 do
  begin
    YTop := MidY - (((MaxShow + Length(Node.BrokenUrls)) * (CardH + GapY)) div 2) +
            I * (CardH + GapY);
    CardRect := Rect(RightX, YTop, RightX + ColW, YTop + CardH);
    DrawCubicWire(CenterRect.Right, MidY,
      CardRect.Left, (CardRect.Top + CardRect.Bottom) div 2,
      RGBToColor(68, 214, 138));

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(30, 54, 44);
    C.Pen.Color := RGBToColor(68, 214, 138);
    C.Pen.Width := 1;
    C.RoundRect(CardRect, 8, 8);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(225, 246, 234);
    C.TextOut(CardRect.Left + 8, CardRect.Top + 9,
      ExtractFileName(Node.Dependencies[I]));
    RegisterHitCard(CardRect, Node.Dependencies[I]);
  end;

  for I := 0 to Min(3, Length(Node.BrokenUrls)) - 1 do
  begin
    YTop := MidY - (((MaxShow + Length(Node.BrokenUrls)) * (CardH + GapY)) div 2) +
            (MaxShow + I) * (CardH + GapY);
    CardRect := Rect(RightX, YTop, RightX + ColW, YTop + CardH);
    DrawCubicWire(CenterRect.Right, MidY,
      CardRect.Left, (CardRect.Top + CardRect.Bottom) div 2,
      RGBToColor(244, 88, 88));

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(68, 28, 32);
    C.Pen.Color := RGBToColor(246, 92, 92);
    C.Pen.Width := 2;
    C.RoundRect(CardRect, 8, 8);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(255, 196, 196);
    C.TextOut(CardRect.Left + 8, CardRect.Top + 9,
      'BROKEN: ' + ExtractFileName(Node.BrokenUrls[I]));
  end;

  { 3. Center selected card }
  C.Brush.Style := bsSolid;
  if Node.IsOrphan then
  begin
    C.Brush.Color := RGBToColor(66, 52, 24);
    C.Pen.Color := RGBToColor(246, 190, 66);
  end else
  begin
    C.Brush.Color := RGBToColor(42, 58, 88);
    C.Pen.Color := RGBToColor(118, 196, 255);
  end;
  C.Pen.Width := 2;
  C.RoundRect(CenterRect, 10, 10);

  C.Brush.Style := bsClear;
  C.Font.Style := [Graphics.fsBold];
  C.Font.Color := RGBToColor(245, 248, 255);
  C.TextOut(CenterRect.Left + 10, CenterRect.Top + 10,
    ExtractFileName(Node.DataRelPath));
  C.Font.Style := [];
  C.Font.Color := RGBToColor(186, 202, 226);
  C.TextOut(CenterRect.Left + 10, CenterRect.Top + 30,
    Format('%s | %s', [AssetCategoryToDisplayName(Node.Category),
      FormatByteSizeShort(Node.SizeBytes)]));
  C.TextOut(CenterRect.Left + 10, CenterRect.Top + 50,
    Format('In: %d | Out: %d%s',
      [Length(Node.Referencers), Length(Node.Dependencies),
       IfThen(Node.IsOrphan, ' | ORPHAN', '')]));
end;

procedure TAssetGraphForm.PaintBoxGraphMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  if Button <> mbLeft then
    Exit;
  for I := 0 to High(FHitCards) do
    if PtInRect(FHitCards[I].Bounds, Point(X, Y)) then
    begin
      SelectAssetByRelPath(FHitCards[I].TargetRelPath);
      Exit;
    end;
end;

procedure TAssetGraphForm.ButtonRescanClick(Sender: TObject);
begin
  RescanProjectData;
end;

procedure TAssetGraphForm.ButtonRepairUrlsClick(Sender: TObject);
var
  FixedCount: Integer;
begin
  if Length(FReport.Repairs) = 0 then
    Exit;
  FixedCount := TAssetDependencyAnalyzer.RepairBrokenUrls(
    FDataDirPath, FReport.Repairs);
  RescanProjectData;
  LabelStatus.Caption := Format('Auto-repaired %d broken URL reference(s) on disk.',
    [FixedCount]);
end;

procedure TAssetGraphForm.ButtonSweepOrphansClick(Sender: TObject);
var
  Orphans: array of String;
  I, N, SweptCount: Integer;
  TrashDir: String;
begin
  if FReport.OrphanCount = 0 then
    Exit;
  if MessageDlg(Format(
       'Quarantine %d unreferenced orphan file(s) (%s) out of data/ into .castle-orphan-trash/?',
       [FReport.OrphanCount, FormatByteSizeShort(FReport.OrphanBytes)]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  SetLength(Orphans, 0);
  for I := 0 to High(FReport.Nodes) do
    if FReport.Nodes[I].IsOrphan then
    begin
      N := Length(Orphans);
      SetLength(Orphans, N + 1);
      Orphans[N] := FReport.Nodes[I].DataRelPath;
    end;

  SweptCount := TAssetDependencyAnalyzer.SweepOrphanAssetsToTrash(
    FDataDirPath, Orphans, TrashDir);
  RescanProjectData;
  LabelStatus.Caption := Format('Quarantined %d orphan asset(s) into %s',
    [SweptCount, TrashDir]);
end;

procedure TAssetGraphForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TAssetDependencyAnalyzer.FormatAssetGraphMarkdown(FReport);
  LabelStatus.Caption := 'Copied Asset Reference Graph Markdown + Mermaid report to clipboard.';
end;

procedure TAssetGraphForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
