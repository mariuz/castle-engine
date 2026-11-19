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

{ Visual Studio dialog for Three-Way Scene & Prefab Diff/Merge Inspector +
  106-Studio Hub / 20-Tool MCP Upgrade (Phase 386). }
unit FormPrefabDiffMerge;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  ToolStudioHub, ToolPrefabDiffMerge;

type
  TPrefabDiffMergeModifiedCallback = procedure(const UndoComment: String) of object;
  TPrefabDiffMergeRefreshCallback = procedure of object;

  TPrefabDiffMergeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPrefabDiffMergeModifiedCallback;
    FOnRefresh: TPrefabDiffMergeRefreshCallback;
    FBaseJson, FOursJson, FTheirsJson: String;
    FLblSummary: TLabel;
    FPaintBars: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure BtnBuildScenarioClick(Sender: TObject);
    procedure BtnMergePreferOursClick(Sender: TObject);
    procedure BtnMergePreferTheirsClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintDiffBreakdown(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPrefabDiffMergeModifiedCallback;
      const AOnRefresh: TPrefabDiffMergeRefreshCallback);
  end;

implementation

constructor TPrefabDiffMergeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPrefabDiffMergeModifiedCallback;
  const AOnRefresh: TPrefabDiffMergeRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Three-Way Scene & Prefab Diff/Merge Inspector & 106-Studio Hub';
  Width := 860;
  Height := 590;
  Position := poMainFormCenter;
  TPrefabDiffMergeEngine.BuildSyntheticBranchConflictScenario(FBaseJson, FOursJson, FTheirsJson);
  TPrefabDiffMergeEngine.SharedEngine.RunMergeAndStore(FBaseJson, FOursJson, FTheirsJson, mcpPreferOurs);
  BuildUi;
  RefreshView;
end;

procedure TPrefabDiffMergeForm.BuildUi;
var
  TopBar, BtnRow: TPanel;
  BtnScenario, BtnOurs, BtnTheirs, BtnCopy, BtnClose: TButton;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 40;
  TopBar.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := TopBar;
  FLblSummary.Left := 12;
  FLblSummary.Top := 11;
  FLblSummary.Font.Style := [fsBold];

  BtnRow := TPanel.Create(Self);
  BtnRow.Parent := Self;
  BtnRow.Align := alTop;
  BtnRow.Height := 44;
  BtnRow.BevelOuter := bvNone;

  BtnScenario := TButton.Create(Self);
  BtnScenario.Parent := BtnRow;
  BtnScenario.SetBounds(10, 6, 225, 30);
  BtnScenario.Caption := 'Generate 3-Way Branch Scenario';
  BtnScenario.OnClick := @BtnBuildScenarioClick;

  BtnOurs := TButton.Create(Self);
  BtnOurs.Parent := BtnRow;
  BtnOurs.SetBounds(243, 6, 185, 30);
  BtnOurs.Caption := '3-Way Merge (Prefer Ours)';
  BtnOurs.OnClick := @BtnMergePreferOursClick;

  BtnTheirs := TButton.Create(Self);
  BtnTheirs.Parent := BtnRow;
  BtnTheirs.SetBounds(436, 6, 195, 30);
  BtnTheirs.Caption := '3-Way Merge (Prefer Theirs)';
  BtnTheirs.OnClick := @BtnMergePreferTheirsClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := BtnRow;
  BtnCopy.SetBounds(639, 6, 115, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BtnRow;
  BtnClose.SetBounds(762, 6, 76, 30);
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrClose;

  FPaintBars := TPaintBox.Create(Self);
  FPaintBars.Parent := Self;
  FPaintBars.Align := alTop;
  FPaintBars.Height := 180;
  FPaintBars.OnPaint := @PaintDiffBreakdown;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
end;

procedure TPrefabDiffMergeForm.RefreshView;
var
  Rep: TThreeWayMergeReport;
begin
  Rep := TPrefabDiffMergeEngine.SharedEngine.LastReport;
  FLblSummary.Caption := Format(
    'Auto-Merged: %d  |  True Conflicts: %d  |  Added Nodes: +%d  |  Unified Hub: %d Studios & 20 MCP Tools',
    [Rep.AutoMergedCount, Rep.ConflictCount, Rep.AddedNodesCount, TStudioHubManager.StudioCount]);
  FMemoReport.Lines.Text := TPrefabDiffMergeEngine.BuildMarkdownReport(Rep);
  FPaintBars.Invalidate;
end;

procedure TPrefabDiffMergeForm.BtnBuildScenarioClick(Sender: TObject);
begin
  TPrefabDiffMergeEngine.BuildSyntheticBranchConflictScenario(FBaseJson, FOursJson, FTheirsJson);
  TPrefabDiffMergeEngine.SharedEngine.RunMergeAndStore(FBaseJson, FOursJson, FTheirsJson, mcpPreferOurs);
  RefreshView;
end;

procedure TPrefabDiffMergeForm.BtnMergePreferOursClick(Sender: TObject);
begin
  TPrefabDiffMergeEngine.SharedEngine.RunMergeAndStore(FBaseJson, FOursJson, FTheirsJson, mcpPreferOurs);
  RefreshView;
end;

procedure TPrefabDiffMergeForm.BtnMergePreferTheirsClick(Sender: TObject);
begin
  TPrefabDiffMergeEngine.SharedEngine.RunMergeAndStore(FBaseJson, FOursJson, FTheirsJson, mcpPreferTheirs);
  RefreshView;
end;

procedure TPrefabDiffMergeForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TPrefabDiffMergeForm.PaintDiffBreakdown(Sender: TObject);
var
  C: TCanvas;
  Rep: TThreeWayMergeReport;
  Total, WAuto, WConf: Integer;
begin
  C := FPaintBars.Canvas;
  C.Brush.Color := $00201C18;
  C.FillRect(0, 0, FPaintBars.Width, FPaintBars.Height);

  Rep := TPrefabDiffMergeEngine.SharedEngine.LastReport;
  Total := Max(1, Rep.AutoMergedCount + Rep.ConflictCount);
  WAuto := Round((FPaintBars.Width - 60) * (Rep.AutoMergedCount / Single(Total)));
  WConf := (FPaintBars.Width - 60) - WAuto;

  C.Brush.Color := $0058D048;
  C.FillRect(30, 48, 30 + WAuto, 96);
  C.Brush.Color := $004050E8;
  C.FillRect(30 + WAuto, 48, 30 + WAuto + WConf, 96);

  C.Font.Color := clWhite;
  C.Brush.Style := bsClear;
  C.TextOut(32, 20, Format('Green = Non-Conflicting Auto-Merges (%d)   |   Red = True 3-Way Conflicts (%d)   |   Catalog = %d Studios',
    [Rep.AutoMergedCount, Rep.ConflictCount, TStudioHubManager.StudioCount]));
end;

end.
