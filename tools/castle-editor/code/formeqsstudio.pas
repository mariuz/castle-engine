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

{ Interactive Environment Query System (EQS) Tactical Cover, Sniper Vantage &
  Rear Flank Studio (@link(TEqsStudioForm)) featuring a 1-click Tactical Cover
  Arena spawner, preset switchers, a live Top-Down XZ Tactical Heatmap canvas
  rendering LoS rays, candidate scores, Querier, Threat & #1 Best Spot, and
  Markdown export (Phase 319). }
unit FormEqsStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform, CastleEqsTactical, ToolEqsStudio;

type
  TEqsStudioModifiedCallback = procedure(const AComment: String) of object;
  TEqsStudioRefreshViewportCallback = procedure of object;

  TEqsStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TEqsStudioModifiedCallback;
    FOnRefreshViewport: TEqsStudioRefreshViewportCallback;

    FQueries: TEqsBehaviorArray;
    FReport: TEqsAuditReport;

    LblHeader: TLabel;
    ListQueries: TListBox;
    PaintHeatmap: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function SelectedQuery: TCastleEqsQueryBehavior;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnArenaClick(Sender: TObject);
    procedure BtnModeTakeCoverClick(Sender: TObject);
    procedure BtnModeSniperClick(Sender: TObject);
    procedure BtnModeRearFlankClick(Sender: TObject);
    procedure BtnMoveAgentClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure ListQueriesClick(Sender: TObject);
    procedure PaintHeatmapPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TEqsStudioModifiedCallback;
      const AOnRefreshViewport: TEqsStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TEqsStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TEqsStudioModifiedCallback;
  const AOnRefreshViewport: TEqsStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Environment Query System (EQS) Tactical Cover, Vantage & Flank Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TEqsStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TEqsStudioForm.BuildUi;
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
  LblHeader.Caption := 'EQS Tactical Queries: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn Tactical Cover Arena', 4, 2, 205, @BtnSpawnArenaClick);
  MakeBtn(RowTop, 'Mode: Take Cover', 215, 2, 145, @BtnModeTakeCoverClick);
  MakeBtn(RowTop, 'Mode: Sniper High-Ground', 366, 2, 185, @BtnModeSniperClick);
  MakeBtn(RowTop, 'Mode: Rear Flank (180°)', 557, 2, 175, @BtnModeRearFlankClick);
  MakeBtn(RowTop, 'Move Agent -> Best Spot', 738, 2, 180, @BtnMoveAgentClick);
  MakeBtn(RowTop, 'Copy Markdown', 924, 2, 140, @BtnCopyMarkdownClick);

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
  Lbl.Caption := 'EQS Query Behaviors:';

  ListQueries := TListBox.Create(Self);
  ListQueries.Parent := PanelLeft;
  ListQueries.SetBounds(10, 26, 320, 225);
  ListQueries.OnClick := @ListQueriesClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 260, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Candidate Scoring & QA Diagnostics:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 282, 320, 290);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintHeatmap := TPaintBox.Create(Self);
  PaintHeatmap.Parent := PanelCenter;
  PaintHeatmap.Align := alClient;
  PaintHeatmap.OnPaint := @PaintHeatmapPaint;
end;

function TEqsStudioForm.SelectedQuery: TCastleEqsQueryBehavior;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := ListQueries.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FQueries)) then
    Result := FQueries[Idx];
end;

procedure TEqsStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TEqsStudioForm.RefreshAll;
var
  SavedIdx, I: Integer;
  Q: TCastleEqsQueryBehavior;
begin
  SavedIdx := ListQueries.ItemIndex;
  TEqsStudioHelper.ScanEqsBehaviors(FDesignRoot, FDesignOwner, FQueries);
  FreeAndNil(FReport);
  FReport := TEqsStudioHelper.AuditEqsQueries(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'EQS Queries: %d  |  Solved: %d  |  Valid Candidates: %d / %d  |  QA Warnings: %d',
    [FReport.QueryCount, FReport.SolvedCount, FReport.TotalValidCandidates,
     FReport.TotalCandidates, FReport.Warnings.Count]);

  ListQueries.Items.BeginUpdate;
  try
    ListQueries.Items.Clear;
    for I := 0 to High(FQueries) do
      ListQueries.Items.Add(Format('%s  %s', [FQueries[I].Name, FQueries[I].EqsSummaryBadge]));
  finally
    ListQueries.Items.EndUpdate;
  end;
  if ListQueries.Items.Count > 0 then
    ListQueries.ItemIndex := Clamped(Max(0, SavedIdx), 0, ListQueries.Items.Count - 1);

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    Q := SelectedQuery;
    if Q <> nil then
    begin
      MemoDiag.Lines.Add(Format('Query: %s (%s)',
        [Q.Name, TCastleEqsQueryBehavior.PresetDisplayName(Q.Preset)]));
      MemoDiag.Lines.Add(Format('Candidates: %d valid / %d generated',
        [Q.ValidCandidateCount, Q.CandidateCount]));
      if Q.HasValidBestSpot then
        MemoDiag.Lines.Add(Format('Best Spot: (%.2f, %.2f, %.2f)  RawScore=%.2f',
          [Q.BestWorldPos.X, Q.BestWorldPos.Y, Q.BestWorldPos.Z, Q.BestScore]))
      else
        MemoDiag.Lines.Add('Best Spot: <none>');
      MemoDiag.Lines.Add('');
    end;
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] All EQS spatial queries resolved cleanly.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintHeatmap.Invalidate;
end;

procedure TEqsStudioForm.BtnSpawnArenaClick(Sender: TObject);
var
  Ag, Th, Wl, Bal: TCastleTransform;
  Eq: TCastleEqsQueryBehavior;
begin
  TEqsStudioHelper.SpawnTacticalCoverArenaDemo(FDesignRoot, FDesignOwner, Ag, Th, Wl, Bal, Eq);
  if Eq <> nil then
    Eq.ShowDebugSpheres := True;
  NotifyChanged('Spawn Tactical EQS Cover Arena');
end;

procedure TEqsStudioForm.BtnModeTakeCoverClick(Sender: TObject);
var
  Q: TCastleEqsQueryBehavior;
begin
  Q := SelectedQuery;
  if Q = nil then Exit;
  Q.ApplyPreset(epTakeCoverFromThreat);
  Q.RunQuery;
  NotifyChanged('EQS Preset: Take Cover From Threat');
end;

procedure TEqsStudioForm.BtnModeSniperClick(Sender: TObject);
var
  Q: TCastleEqsQueryBehavior;
begin
  Q := SelectedQuery;
  if Q = nil then Exit;
  Q.ApplyPreset(epSniperLineOfSightVantage);
  Q.RunQuery;
  NotifyChanged('EQS Preset: Sniper High-Ground Vantage');
end;

procedure TEqsStudioForm.BtnModeRearFlankClick(Sender: TObject);
var
  Q: TCastleEqsQueryBehavior;
begin
  Q := SelectedQuery;
  if Q = nil then Exit;
  Q.ApplyPreset(epFlankRearSurround);
  Q.RunQuery;
  NotifyChanged('EQS Preset: Rear Flank Surround');
end;

procedure TEqsStudioForm.BtnMoveAgentClick(Sender: TObject);
var
  Q: TCastleEqsQueryBehavior;
begin
  Q := SelectedQuery;
  if (Q = nil) or (Q.Parent = nil) then Exit;
  if not Q.HasValidBestSpot then
    Q.RunQuery;
  if Q.HasValidBestSpot then
    Q.Parent.Translation := Vector3(Q.BestWorldPos.X, Q.BestWorldPos.Y + 0.90, Q.BestWorldPos.Z);
  NotifyChanged('Move Squad Agent to EQS Best Spot');
end;

procedure TEqsStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TEqsStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TEqsStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TEqsStudioForm.ListQueriesClick(Sender: TObject);
begin
  RefreshAll;
end;

procedure TEqsStudioForm.PaintHeatmapPaint(Sender: TObject);
var
  C: TCanvas;
  Q: TCastleEqsQueryBehavior;
  W, H, Cx, Cy, Px, Py, Tx, Ty, I, Rad: Integer;
  ScalePx, S: Single;
  Cand: TEqsCandidateItem;
begin
  C := PaintHeatmap.Canvas;
  W := Max(200, PaintHeatmap.Width);
  H := Max(200, PaintHeatmap.Height);
  C.Brush.Color := RGBToColor(20, 24, 31);
  C.FillRect(0, 0, W, H);

  Q := SelectedQuery;
  if Q = nil then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn Tactical Cover Arena" to visualize EQS cover, LoS & flank heatmaps.');
    Exit;
  end;

  Cx := W div 2;
  Cy := H div 2 + 12;
  ScalePx := Min(W, H) / 34.0;

  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(18, 12, Format('Top-Down XZ Tactical EQS Heatmap — %s',
    [TCastleEqsQueryBehavior.PresetDisplayName(Q.Preset)]));
  C.Font.Style := [];

  { Draw candidate points }
  for I := 0 to Q.CandidateCount - 1 do
  begin
    Cand := Q.GetCandidate(I);
    Px := Cx + Round(Cand.WorldPos.X * ScalePx);
    Py := Cy + Round(Cand.WorldPos.Z * ScalePx);
    if Cand.FilteredOut then
    begin
      C.Brush.Color := RGBToColor(58, 62, 70);
      C.Pen.Color := RGBToColor(78, 82, 92);
      C.Ellipse(Px - 3, Py - 3, Px + 3, Py + 3);
    end else
    begin
      S := Cand.NormalizedScore;
      Rad := 5 + Round(S * 6.0);
      C.Brush.Color := RGBToColor(
        Round(Lerp(S, 230.0, 48.0)),
        Round(Lerp(S, 92.0, 226.0)),
        78);
      C.Pen.Color := RGBToColor(220, 245, 230);
      C.Ellipse(Px - Rad, Py - Rad, Px + Rad, Py + Rad);
    end;
  end;

  { Draw Threat }
  if Q.ThreatTransform <> nil then
  begin
    Tx := Cx + Round(Q.ThreatTransform.Translation.X * ScalePx);
    Ty := Cy + Round(Q.ThreatTransform.Translation.Z * ScalePx);
    C.Brush.Color := RGBToColor(242, 64, 64);
    C.Pen.Color := RGBToColor(255, 210, 210);
    C.Rectangle(Tx - 9, Ty - 9, Tx + 9, Ty + 9);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(255, 140, 140);
    C.TextOut(Tx + 12, Ty - 8, 'THREAT');
  end;

  { Draw Querier }
  if Q.Parent <> nil then
  begin
    Px := Cx + Round(Q.Parent.Translation.X * ScalePx);
    Py := Cy + Round(Q.Parent.Translation.Z * ScalePx);
    C.Brush.Color := RGBToColor(64, 178, 250);
    C.Pen.Color := RGBToColor(220, 240, 255);
    C.Ellipse(Px - 9, Py - 9, Px + 9, Py + 9);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(140, 215, 255);
    C.TextOut(Px + 12, Py - 8, 'AGENT');
  end;

  { Highlight #1 Best Spot }
  if Q.HasValidBestSpot then
  begin
    Px := Cx + Round(Q.BestWorldPos.X * ScalePx);
    Py := Cy + Round(Q.BestWorldPos.Z * ScalePx);
    C.Pen.Color := RGBToColor(255, 218, 64);
    C.Pen.Width := 3;
    C.Brush.Style := bsClear;
    C.Ellipse(Px - 14, Py - 14, Px + 14, Py + 14);
    C.Pen.Width := 1;
    C.Font.Color := RGBToColor(255, 226, 92);
    C.TextOut(Px + 16, Py - 8, Format('BEST (%.2f)', [Q.BestScore]));
  end;
end;

end.
