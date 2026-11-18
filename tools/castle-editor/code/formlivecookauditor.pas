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

{ Visual Studio dialog for Live Coding RTTI Broker & Release Package Cook Auditor (Phase 356). }
unit FormLiveCookAuditor;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  ToolLiveCookAuditor, ToolStudioHub;

type
  TLiveCookModifiedCallback = procedure(const UndoComment: String) of object;
  TLiveCookRefreshCallback = procedure of object;

  TLiveCookAuditorForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLiveCookModifiedCallback;
    FOnRefresh: TLiveCookRefreshCallback;
    FSavedSnapshot: TLiveRttiSnapshot;
    FLastCookScore: Integer;
    FLastReadyToShip: Boolean;
    FPaintGauge: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshAudit;
    procedure BtnCaptureSnapshotClick(Sender: TObject);
    procedure BtnRehydrateSnapshotClick(Sender: TObject);
    procedure BtnRunCookAuditClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCookGauge(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TLiveCookModifiedCallback;
      const AOnRefresh: TLiveCookRefreshCallback);
    destructor Destroy; override;
  end;

implementation

constructor TLiveCookAuditorForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TLiveCookModifiedCallback;
  const AOnRefresh: TLiveCookRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FSavedSnapshot := nil;
  FLastCookScore := 100;
  FLastReadyToShip := True;
  Caption := 'Live Coding RTTI Broker & Release Package Cook Auditor Studio — 86-Studio Hub (Phase 356)';
  Width := 980;
  Height := 620;
  Position := poScreenCenter;
  BuildUi;
  RefreshAudit;
end;

destructor TLiveCookAuditorForm.Destroy;
begin
  FreeAndNil(FSavedSnapshot);
  inherited Destroy;
end;

procedure TLiveCookAuditorForm.BuildUi;
var
  Lbl: TLabel;
  TopRow: TPanel;

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
  Lbl.Caption := 'UE 6.0+ Live Coding & Cook Parity — RTTI Hot-Reload Snapshot/Rehydrate, CoreRedirect Field Aliases & 86-Studio Release Cook Gate';

  TopRow := TPanel.Create(Self);
  TopRow.Parent := Self;
  TopRow.Align := alTop;
  TopRow.Height := 42;
  TopRow.BevelOuter := bvNone;
  MakeBtn(TopRow, 'Capture Live RTTI Snapshot', @BtnCaptureSnapshotClick);
  MakeBtn(TopRow, 'Rehydrate Live Snapshot (Hot-Reload)', @BtnRehydrateSnapshotClick);
  MakeBtn(TopRow, 'Run Release Package Cook Audit', @BtnRunCookAuditClick);
  MakeBtn(TopRow, 'Copy Markdown Report', @BtnCopyReportClick);

  FPaintGauge := TPaintBox.Create(Self);
  FPaintGauge.Parent := Self;
  FPaintGauge.Align := alTop;
  FPaintGauge.Height := 74;
  FPaintGauge.OnPaint := @PaintCookGauge;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TLiveCookAuditorForm.RefreshAudit;
var
  Rep: TCookAuditReport;
begin
  Rep := TLiveCodingCookBroker.AuditPackageCookReadiness(FDesignRoot, FDesignOwner, False);
  try
    FLastCookScore := Rep.CookReadinessScore;
    FLastReadyToShip := Rep.CookReadyToShip;
  finally
    FreeAndNil(Rep);
  end;
  FMemoReport.Lines.Text := TLiveCodingCookBroker.GenerateCookAndLiveCodingMarkdown(FDesignRoot, FDesignOwner);
  if FSavedSnapshot <> nil then
    FMemoReport.Lines.Add(Format(LineEnding + '> Active Buffered Live Coding Snapshot: `%d` components / `%d` RTTI properties ready for hot-rehydration.',
      [FSavedSnapshot.CapturedComponentCount, FSavedSnapshot.CapturedPropertyCount]));
  FPaintGauge.Invalidate;
end;

procedure TLiveCookAuditorForm.BtnCaptureSnapshotClick(Sender: TObject);
begin
  FreeAndNil(FSavedSnapshot);
  FSavedSnapshot := TLiveCodingCookBroker.CaptureLiveRttiSnapshot(FDesignRoot, FDesignOwner);
  RefreshAudit;
end;

procedure TLiveCookAuditorForm.BtnRehydrateSnapshotClick(Sender: TObject);
var
  NoAliases: array of TRttiFieldAliasRule;
  Stats: TLiveRehydrateStats;
begin
  if FSavedSnapshot = nil then Exit;
  SetLength(NoAliases, 0);
  Stats := TLiveCodingCookBroker.RehydrateLiveRttiSnapshot(FSavedSnapshot, FDesignRoot, FDesignOwner, NoAliases);
  if Assigned(FOnModified) then
    FOnModified(Format('Rehydrate Live Coding Snapshot (%d props)', [Stats.PropertiesRestored]));
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshAudit;
end;

procedure TLiveCookAuditorForm.BtnRunCookAuditClick(Sender: TObject);
begin
  RefreshAudit;
end;

procedure TLiveCookAuditorForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TLiveCookAuditorForm.PaintCookGauge(Sender: TObject);
var
  Cv: TCanvas;
  W, H, BarW: Integer;
begin
  Cv := FPaintGauge.Canvas;
  W := FPaintGauge.Width;
  H := FPaintGauge.Height;
  Cv.Brush.Color := RGBToColor(22, 26, 34);
  Cv.FillRect(0, 0, W, H);

  BarW := Round((W - 36) * (FLastCookScore / 100.0));
  if FLastReadyToShip then
    Cv.Brush.Color := RGBToColor(48, 210, 115)
  else
    Cv.Brush.Color := RGBToColor(240, 88, 68);
  Cv.FillRect(18, 34, 18 + BarW, 58);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.Font.Style := [fsBold];
  Cv.TextOut(18, 10, Format('Release Package Cook Readiness: %d / 100 (%s) | Cataloged Studios: %d | MCP Tools: 17', [
    FLastCookScore,
    BoolToStr(FLastReadyToShip, 'SHIP-READY', 'BLOCKED BY COOK HAZARDS'),
    TStudioHubManager.StudioCount]));
end;

end.
