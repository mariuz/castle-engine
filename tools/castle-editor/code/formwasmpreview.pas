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

{ Built-in WebAssembly (@code(targetWeb)) Live Preview HTTP Server control
  center and visual bundle size profiler dialog (Phase 284 — UE 5.9 Web Parity). }
unit FormWasmPreview;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, Graphics, Clipbrd,
  ToolWasmPreviewServer;

type
  TWasmCompileCallback = procedure of object;

  TWasmPreviewForm = class(TForm)
  private
    FServer: TWasmPreviewHttpServer;
    FProjectDataDir: String;
    FOnCompileWeb: TWasmCompileCallback;
    FReport: TWasmBundleReport;

    EditDistDir: TEdit;
    ButtonBrowseDist: TButton;
    SpinPort: TSpinEdit;
    CheckCoopCoep: TCheckBox;
    CheckAutoReload: TCheckBox;
    ButtonToggleServer: TButton;
    ButtonOpenBrowser: TButton;
    ButtonCompileWeb: TButton;
    LabelLiveTelemetry: TLabel;
    TimerStatus: TTimer;

    PaintChart: TPaintBox;
    LabelSummaryStats: TLabel;
    PagesDetails: TPageControl;
    ListBreakdown: TListView;
    MemoRecommendations: TMemo;

    ButtonRefreshProfile: TButton;
    ButtonCopyReport: TButton;
    ButtonClose: TButton;

    procedure BuildUi;
    procedure SyncControlsFromServer;
    procedure RefreshBundleProfile;
    procedure UpdateTelemetryBanner;

    procedure ButtonBrowseDistClick(Sender: TObject);
    procedure ButtonToggleServerClick(Sender: TObject);
    procedure ButtonOpenBrowserClick(Sender: TObject);
    procedure ButtonCompileWebClick(Sender: TObject);
    procedure CheckOptionsChange(Sender: TObject);
    procedure TimerStatusTimer(Sender: TObject);
    procedure PaintChartPaint(Sender: TObject);
    procedure ButtonRefreshProfileClick(Sender: TObject);
    procedure ButtonCopyReportClick(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent;
      const AServer: TWasmPreviewHttpServer;
      const AProjectDataDir: String;
      const AOnCompileWeb: TWasmCompileCallback = nil);
    destructor Destroy; override;
  end;

implementation

uses
  Math, CastleOpenDocument, CastleUtils;

const
  CategoryBarColors: array [TWasmPayloadCategory] of TColor = (
    $00E87828, // wpcWasmBinary (vibrant blue-indigo in BGR)
    $0050B8F0, // wpcJsHtmlShell (amber-gold)
    $0078C840, // wpcPackedDataArchive (emerald green)
    $00D860B8, // wpcTextures (magenta)
    $00F0B838, // wpcModels3D (cyan)
    $004868F0, // wpcAudio (coral)
    $0098D898, // wpcDesignsFontsShaders (mint)
    $00989898  // wpcOther (gray)
  );

constructor TWasmPreviewForm.CreateDialog(AOwner: TComponent;
  const AServer: TWasmPreviewHttpServer;
  const AProjectDataDir: String;
  const AOnCompileWeb: TWasmCompileCallback);
begin
  inherited CreateNew(AOwner, 0);
  FServer := AServer;
  FProjectDataDir := AProjectDataDir;
  FOnCompileWeb := AOnCompileWeb;

  Caption := 'WebAssembly (targetWeb) Live Preview Server & Bundle Size Profiler';
  Position := poMainFormCenter;
  Width := 920;
  Height := 640;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 520;

  BuildUi;
  SyncControlsFromServer;
  RefreshBundleProfile;
  UpdateTelemetryBanner;
end;

destructor TWasmPreviewForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TWasmPreviewForm.BuildUi;
var
  ServerGroup: TGroupBox;
  RowDir, RowServer, ChartPanel, BottomPanel: TPanel;
  LblDir, LblPort: TLabel;
  TabFiles, TabHints: TTabSheet;
  Col: TListColumn;
begin
  ServerGroup := TGroupBox.Create(Self);
  ServerGroup.Parent := Self;
  ServerGroup.Align := alTop;
  ServerGroup.AutoSize := true;
  ServerGroup.Caption := 'Localhost WebAssembly Preview HTTP Server (COOP/COEP & Auto-Reload)';
  ServerGroup.BorderSpacing.Around := 8;

  RowDir := TPanel.Create(Self);
  RowDir.Parent := ServerGroup;
  RowDir.Align := alTop;
  RowDir.Height := 34;
  RowDir.BevelOuter := bvNone;
  RowDir.BorderSpacing.Around := 4;

  LblDir := TLabel.Create(Self);
  LblDir.Parent := RowDir;
  LblDir.Align := alLeft;
  LblDir.Layout := tlCenter;
  LblDir.Caption := 'Web Dist Root:';
  LblDir.BorderSpacing.Right := 6;

  ButtonBrowseDist := TButton.Create(Self);
  ButtonBrowseDist.Parent := RowDir;
  ButtonBrowseDist.Align := alRight;
  ButtonBrowseDist.AutoSize := true;
  ButtonBrowseDist.Caption := 'Browse...';
  ButtonBrowseDist.OnClick := @ButtonBrowseDistClick;

  EditDistDir := TEdit.Create(Self);
  EditDistDir.Parent := RowDir;
  EditDistDir.Align := alClient;
  EditDistDir.BorderSpacing.Right := 6;

  RowServer := TPanel.Create(Self);
  RowServer.Parent := ServerGroup;
  RowServer.Align := alTop;
  RowServer.Height := 36;
  RowServer.BevelOuter := bvNone;
  RowServer.BorderSpacing.Around := 4;

  LblPort := TLabel.Create(Self);
  LblPort.Parent := RowServer;
  LblPort.Align := alLeft;
  LblPort.Layout := tlCenter;
  LblPort.Caption := 'Port:';
  LblPort.BorderSpacing.Right := 4;

  SpinPort := TSpinEdit.Create(Self);
  SpinPort.Parent := RowServer;
  SpinPort.Align := alLeft;
  SpinPort.Width := 78;
  SpinPort.MinValue := 1024;
  SpinPort.MaxValue := 65535;
  SpinPort.Value := TWasmPreviewHttpServer.DefaultWasmPreviewPort;
  SpinPort.BorderSpacing.Right := 12;

  CheckCoopCoep := TCheckBox.Create(Self);
  CheckCoopCoep.Parent := RowServer;
  CheckCoopCoep.Align := alLeft;
  CheckCoopCoep.Caption := 'COOP/COEP (SharedArrayBuffer)';
  CheckCoopCoep.Checked := true;
  CheckCoopCoep.BorderSpacing.Right := 12;
  CheckCoopCoep.OnChange := @CheckOptionsChange;

  CheckAutoReload := TCheckBox.Create(Self);
  CheckAutoReload.Parent := RowServer;
  CheckAutoReload.Align := alLeft;
  CheckAutoReload.Caption := 'Live Auto-Reload';
  CheckAutoReload.Checked := true;
  CheckAutoReload.BorderSpacing.Right := 12;
  CheckAutoReload.OnChange := @CheckOptionsChange;

  ButtonToggleServer := TButton.Create(Self);
  ButtonToggleServer.Parent := RowServer;
  ButtonToggleServer.Align := alLeft;
  ButtonToggleServer.AutoSize := true;
  ButtonToggleServer.Caption := 'Start Server';
  ButtonToggleServer.BorderSpacing.Right := 6;
  ButtonToggleServer.OnClick := @ButtonToggleServerClick;

  ButtonOpenBrowser := TButton.Create(Self);
  ButtonOpenBrowser.Parent := RowServer;
  ButtonOpenBrowser.Align := alLeft;
  ButtonOpenBrowser.AutoSize := true;
  ButtonOpenBrowser.Caption := 'Launch in Browser';
  ButtonOpenBrowser.BorderSpacing.Right := 6;
  ButtonOpenBrowser.OnClick := @ButtonOpenBrowserClick;

  ButtonCompileWeb := TButton.Create(Self);
  ButtonCompileWeb.Parent := RowServer;
  ButtonCompileWeb.Align := alLeft;
  ButtonCompileWeb.AutoSize := true;
  ButtonCompileWeb.Caption := 'Compile Web Target';
  ButtonCompileWeb.Visible := Assigned(FOnCompileWeb);
  ButtonCompileWeb.OnClick := @ButtonCompileWebClick;

  LabelLiveTelemetry := TLabel.Create(Self);
  LabelLiveTelemetry.Parent := ServerGroup;
  LabelLiveTelemetry.Align := alTop;
  LabelLiveTelemetry.Font.Style := [fsBold];
  LabelLiveTelemetry.BorderSpacing.Around := 6;
  LabelLiveTelemetry.Caption := 'Server Status: Stopped';

  ChartPanel := TPanel.Create(Self);
  ChartPanel.Parent := Self;
  ChartPanel.Align := alTop;
  ChartPanel.Height := 84;
  ChartPanel.BevelOuter := bvNone;
  ChartPanel.BorderSpacing.Left := 8;
  ChartPanel.BorderSpacing.Right := 8;

  LabelSummaryStats := TLabel.Create(Self);
  LabelSummaryStats.Parent := ChartPanel;
  LabelSummaryStats.Align := alTop;
  LabelSummaryStats.Font.Style := [fsBold];
  LabelSummaryStats.Caption := 'Bundle Size Summary: scanning...';
  LabelSummaryStats.BorderSpacing.Bottom := 4;

  PaintChart := TPaintBox.Create(Self);
  PaintChart.Parent := ChartPanel;
  PaintChart.Align := alClient;
  PaintChart.OnPaint := @PaintChartPaint;

  BottomPanel := TPanel.Create(Self);
  BottomPanel.Parent := Self;
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 42;
  BottomPanel.BevelOuter := bvNone;
  BottomPanel.BorderSpacing.Around := 6;

  ButtonRefreshProfile := TButton.Create(Self);
  ButtonRefreshProfile.Parent := BottomPanel;
  ButtonRefreshProfile.Align := alLeft;
  ButtonRefreshProfile.AutoSize := true;
  ButtonRefreshProfile.Caption := 'Rescan Bundle & Data Sizes';
  ButtonRefreshProfile.BorderSpacing.Right := 8;
  ButtonRefreshProfile.OnClick := @ButtonRefreshProfileClick;

  ButtonCopyReport := TButton.Create(Self);
  ButtonCopyReport.Parent := BottomPanel;
  ButtonCopyReport.Align := alLeft;
  ButtonCopyReport.AutoSize := true;
  ButtonCopyReport.Caption := 'Copy Markdown Diagnostics Report';
  ButtonCopyReport.OnClick := @ButtonCopyReportClick;

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := BottomPanel;
  ButtonClose.Align := alRight;
  ButtonClose.Width := 96;
  ButtonClose.Caption := 'Close';
  ButtonClose.Cancel := true;
  ButtonClose.OnClick := @ButtonCloseClick;

  PagesDetails := TPageControl.Create(Self);
  PagesDetails.Parent := Self;
  PagesDetails.Align := alClient;
  PagesDetails.BorderSpacing.Around := 8;

  TabFiles := PagesDetails.AddTabSheet;
  TabFiles.Caption := 'Payload Breakdown & Heavy Artifacts';

  ListBreakdown := TListView.Create(Self);
  ListBreakdown.Parent := TabFiles;
  ListBreakdown.Align := alClient;
  ListBreakdown.ViewStyle := vsReport;
  ListBreakdown.RowSelect := true;
  ListBreakdown.ReadOnly := true;

  Col := ListBreakdown.Columns.Add; Col.Caption := 'Source'; Col.Width := 95;
  Col := ListBreakdown.Columns.Add; Col.Caption := 'Category'; Col.Width := 215;
  Col := ListBreakdown.Columns.Add; Col.Caption := 'Artifact / Path'; Col.Width := 330;
  Col := ListBreakdown.Columns.Add; Col.Caption := 'Size'; Col.Width := 105;
  Col := ListBreakdown.Columns.Add; Col.Caption := 'Share'; Col.Width := 85;

  TabHints := PagesDetails.AddTabSheet;
  TabHints.Caption := 'Optimization Hints & Markdown Report';

  MemoRecommendations := TMemo.Create(Self);
  MemoRecommendations.Parent := TabHints;
  MemoRecommendations.Align := alClient;
  MemoRecommendations.ReadOnly := true;
  MemoRecommendations.ScrollBars := ssAutoBoth;
  MemoRecommendations.Font.Name := 'Monospace';

  TimerStatus := TTimer.Create(Self);
  TimerStatus.Interval := 1000;
  TimerStatus.OnTimer := @TimerStatusTimer;
  TimerStatus.Enabled := true;
end;

procedure TWasmPreviewForm.SyncControlsFromServer;
begin
  if FServer = nil then
    Exit;
  EditDistDir.Text := FServer.DocumentRoot;
  SpinPort.Value := FServer.Port;
  CheckCoopCoep.Checked := FServer.EnableCrossOriginIsolation;
  CheckAutoReload.Checked := FServer.EnableAutoReload;
end;

procedure TWasmPreviewForm.RefreshBundleProfile;
var
  Cat: TWasmPayloadCategory;
  Item: TListItem;
  I: Integer;
  Pct: Double;
begin
  FreeAndNil(FReport);
  FReport := TWasmBundleProfiler.ProfileWebBundle(Trim(EditDistDir.Text), FProjectDataDir);

  LabelSummaryStats.Caption := Format(
    'Web Dist Payload: %s  |  Raw data/ Assets: %s  |  Cold Download — Slow 3G: %.1fs, Fast 4G: %.2fs, Broadband: %.2fs',
    [TWasmBundleProfiler.FormatBytesHuman(FReport.TotalDistBytes),
     TWasmBundleProfiler.FormatBytesHuman(FReport.TotalRawDataBytes),
     FReport.EstSecondsSlow3G, FReport.EstSecondsFast4G, FReport.EstSecondsBroadband]);

  ListBreakdown.Items.BeginUpdate;
  try
    ListBreakdown.Items.Clear;

    { 1. Category summary rows }
    for Cat := Low(TWasmPayloadCategory) to High(TWasmPayloadCategory) do
      if (FReport.DistCategoryBytes[Cat] > 0) or (FReport.DataCategoryBytes[Cat] > 0) then
      begin
        Item := ListBreakdown.Items.Add;
        Item.Caption := '[Category]';
        Item.SubItems.Add(TWasmBundleProfiler.CategoryDisplayName(Cat));
        Item.SubItems.Add(Format('dist: %s  |  data/: %s',
          [TWasmBundleProfiler.FormatBytesHuman(FReport.DistCategoryBytes[Cat]),
           TWasmBundleProfiler.FormatBytesHuman(FReport.DataCategoryBytes[Cat])]));
        Item.SubItems.Add(TWasmBundleProfiler.FormatBytesHuman(FReport.DistCategoryBytes[Cat]));
        if FReport.TotalDistBytes > 0 then
          Pct := (FReport.DistCategoryBytes[Cat] * 100.0) / FReport.TotalDistBytes
        else
          Pct := 0.0;
        Item.SubItems.Add(Format('%.1f%%', [Pct]));
      end;

    { 2. Individual dist/ files }
    for I := 0 to High(FReport.DistFiles) do
    begin
      Item := ListBreakdown.Items.Add;
      Item.Caption := 'web/dist';
      Item.SubItems.Add(TWasmBundleProfiler.CategoryDisplayName(FReport.DistFiles[I].Category));
      Item.SubItems.Add(FReport.DistFiles[I].RelativePath);
      Item.SubItems.Add(TWasmBundleProfiler.FormatBytesHuman(FReport.DistFiles[I].SizeBytes));
      if FReport.TotalDistBytes > 0 then
        Pct := (FReport.DistFiles[I].SizeBytes * 100.0) / FReport.TotalDistBytes
      else
        Pct := 0.0;
      Item.SubItems.Add(Format('%.1f%%', [Pct]));
    end;

    { 3. Top source data/ files }
    for I := 0 to High(FReport.LargestDataFiles) do
    begin
      Item := ListBreakdown.Items.Add;
      Item.Caption := 'data/';
      Item.SubItems.Add(TWasmBundleProfiler.CategoryDisplayName(FReport.LargestDataFiles[I].Category));
      Item.SubItems.Add(FReport.LargestDataFiles[I].RelativePath);
      Item.SubItems.Add(TWasmBundleProfiler.FormatBytesHuman(FReport.LargestDataFiles[I].SizeBytes));
      if FReport.TotalRawDataBytes > 0 then
        Pct := (FReport.LargestDataFiles[I].SizeBytes * 100.0) / FReport.TotalRawDataBytes
      else
        Pct := 0.0;
      Item.SubItems.Add(Format('%.1f%% of data', [Pct]));
    end;
  finally
    ListBreakdown.Items.EndUpdate;
  end;

  MemoRecommendations.Lines.Text := FReport.FormatMarkdownReport;
  PaintChart.Invalidate;
end;

procedure TWasmPreviewForm.UpdateTelemetryBanner;
begin
  if FServer = nil then
    Exit;
  if FServer.Listening then
  begin
    ButtonToggleServer.Caption := 'Stop Server';
    LabelLiveTelemetry.Caption := Format(
      'RUNNING at %s  |  Requests: %d  |  Transferred: %s  |  Last URI: %s',
      [FServer.PreviewUrl(false),
       FServer.RequestsServed,
       TWasmBundleProfiler.FormatBytesHuman(FServer.BytesServed),
       FServer.LastRequestedUri]);
  end else
  begin
    ButtonToggleServer.Caption := 'Start Server';
    LabelLiveTelemetry.Caption := Format(
      'STOPPED (Configured endpoint: http://127.0.0.1:%d/index.html) — Click "Start Server" or "Launch in Browser"',
      [SpinPort.Value]);
  end;
end;

procedure TWasmPreviewForm.PaintChartPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, BarX, SegW, LegendX: Integer;
  TotalBytes: Int64;
  UseDist: Boolean;
  Cat: TWasmPayloadCategory;
  CatBytes: Int64;
begin
  C := PaintChart.Canvas;
  W := PaintChart.ClientWidth;
  H := PaintChart.ClientHeight;
  C.Brush.Color := $00221C18;
  C.FillRect(0, 0, W, H);

  if FReport = nil then
    Exit;

  UseDist := FReport.TotalDistBytes > 0;
  if UseDist then
    TotalBytes := FReport.TotalDistBytes
  else
    TotalBytes := FReport.TotalRawDataBytes;

  if TotalBytes <= 0 then
  begin
    C.Font.Color := clSilver;
    C.TextOut(12, 18, 'No web/dist or data/ files found yet — compile with targetWeb or select a dist folder.');
    Exit;
  end;

  BarX := 8;
  for Cat := Low(TWasmPayloadCategory) to High(TWasmPayloadCategory) do
  begin
    if UseDist then
      CatBytes := FReport.DistCategoryBytes[Cat]
    else
      CatBytes := FReport.DataCategoryBytes[Cat];
    if CatBytes <= 0 then
      Continue;

    SegW := Max(4, Round(((W - 16) * Double(CatBytes)) / Double(TotalBytes)));
    if BarX + SegW > W - 8 then
      SegW := Max(1, (W - 8) - BarX);
    C.Brush.Color := CategoryBarColors[Cat];
    C.FillRect(BarX, 6, BarX + SegW, 30);
    Inc(BarX, SegW);
  end;

  { Legend strip underneath stacked bar }
  LegendX := 8;
  C.Brush.Style := bsSolid;
  C.Font.Color := clWhite;
  for Cat := Low(TWasmPayloadCategory) to High(TWasmPayloadCategory) do
  begin
    if UseDist then
      CatBytes := FReport.DistCategoryBytes[Cat]
    else
      CatBytes := FReport.DataCategoryBytes[Cat];
    if CatBytes <= 0 then
      Continue;
    C.Brush.Color := CategoryBarColors[Cat];
    C.FillRect(LegendX, 38, LegendX + 10, 48);
    C.Brush.Style := bsClear;
    C.TextOut(LegendX + 14, 35,
      TWasmBundleProfiler.CategoryDisplayName(Cat) + ' (' +
      TWasmBundleProfiler.FormatBytesHuman(CatBytes) + ')');
    LegendX := LegendX + C.TextWidth(TWasmBundleProfiler.CategoryDisplayName(Cat) +
      ' (' + TWasmBundleProfiler.FormatBytesHuman(CatBytes) + ')') + 28;
    C.Brush.Style := bsSolid;
    if LegendX > W - 80 then
      Break;
  end;
end;

procedure TWasmPreviewForm.ButtonBrowseDistClick(Sender: TObject);
var
  ChosenDir: String;
begin
  ChosenDir := Trim(EditDistDir.Text);
  if SelectDirectory('Select WebAssembly dist Directory', '', ChosenDir) then
  begin
    EditDistDir.Text := ChosenDir;
    if FServer <> nil then
      FServer.DocumentRoot := ChosenDir;
    RefreshBundleProfile;
  end;
end;

procedure TWasmPreviewForm.ButtonToggleServerClick(Sender: TObject);
begin
  if FServer = nil then
    Exit;
  if FServer.Listening then
    FServer.StopServer
  else
  begin
    FServer.DocumentRoot := Trim(EditDistDir.Text);
    FServer.Port := Word(SpinPort.Value);
    FServer.EnableCrossOriginIsolation := CheckCoopCoep.Checked;
    FServer.EnableAutoReload := CheckAutoReload.Checked;
    if not FServer.StartServer then
      MessageDlg('Server Error',
        Format('Could not bind localhost TCP port %d. Try choosing a different port.',
          [SpinPort.Value]), mtError, [mbOK], 0);
  end;
  UpdateTelemetryBanner;
end;

procedure TWasmPreviewForm.ButtonOpenBrowserClick(Sender: TObject);
begin
  if FServer = nil then
    Exit;
  if not FServer.Listening then
  begin
    FServer.DocumentRoot := Trim(EditDistDir.Text);
    FServer.Port := Word(SpinPort.Value);
    FServer.EnableCrossOriginIsolation := CheckCoopCoep.Checked;
    FServer.EnableAutoReload := CheckAutoReload.Checked;
    if not FServer.StartServer then
    begin
      MessageDlg('Server Error',
        Format('Could not start localhost HTTP server on port %d.', [SpinPort.Value]),
        mtError, [mbOK], 0);
      Exit;
    end;
    UpdateTelemetryBanner;
  end;
  OpenUrl(FServer.PreviewUrl(true));
end;

procedure TWasmPreviewForm.ButtonCompileWebClick(Sender: TObject);
begin
  if Assigned(FOnCompileWeb) then
    FOnCompileWeb;
end;

procedure TWasmPreviewForm.CheckOptionsChange(Sender: TObject);
begin
  if FServer = nil then
    Exit;
  FServer.EnableCrossOriginIsolation := CheckCoopCoep.Checked;
  FServer.EnableAutoReload := CheckAutoReload.Checked;
end;

procedure TWasmPreviewForm.TimerStatusTimer(Sender: TObject);
begin
  UpdateTelemetryBanner;
end;

procedure TWasmPreviewForm.ButtonRefreshProfileClick(Sender: TObject);
begin
  if FServer <> nil then
    FServer.DocumentRoot := Trim(EditDistDir.Text);
  RefreshBundleProfile;
end;

procedure TWasmPreviewForm.ButtonCopyReportClick(Sender: TObject);
begin
  if FReport <> nil then
  begin
    Clipboard.AsText := FReport.FormatMarkdownReport;
    MessageDlg('Copied Report',
      'WebAssembly Bundle Diagnostics Markdown report copied to clipboard.',
      mtInformation, [mbOK], 0);
  end;
end;

procedure TWasmPreviewForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
