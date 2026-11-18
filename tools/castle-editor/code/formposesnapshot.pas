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

{ Visual studio dialog for Skeletal Pose Snapshot & Dash Ghost Trail (Phase 375). }
unit FormPoseSnapshot;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastlePoseSnapshot, ToolPoseSnapshot;

type
  TPoseSnapshotModifiedCallback = procedure(const UndoComment: String) of object;
  TPoseSnapshotRefreshCallback = procedure of object;

  TPoseSnapshotForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPoseSnapshotModifiedCallback;
    FOnRefresh: TPoseSnapshotRefreshCallback;
    FLblSummary: TLabel;
    FPaintTimeline: TPaintBox;
    FMemoReport: TMemo;
    FDashCursorX: Single;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnCaptureDashStepClick(Sender: TObject);
    procedure BtnStepDecayClick(Sender: TObject);
    procedure BtnToggleStatueClick(Sender: TObject);
    procedure BtnShadowVioletClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintGhostRing(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPoseSnapshotModifiedCallback;
      const AOnRefresh: TPoseSnapshotRefreshCallback);
  end;

implementation

constructor TPoseSnapshotForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPoseSnapshotModifiedCallback;
  const AOnRefresh: TPoseSnapshotRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FDashCursorX := 7.4;
  Caption := 'Skeletal Pose Snapshot, Dash Ghost Trail & Petrified Statue Studio (Phase 375)';
  Width := 1020;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TPoseSnapshotForm.BuildUi;
var
  Row1, BodyPanel: TPanel;

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
  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := Self;
  FLblSummary.Align := alTop;
  FLblSummary.BorderSpacing.Around := 8;
  FLblSummary.Font.Style := [fsBold];

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;

  MakeBtn(Row1, '+ Spawn Cyan Dash Trail', @BtnSpawnDemoClick);
  MakeBtn(Row1, 'Capture Dash Afterimage (+1.8m)', @BtnCaptureDashStepClick);
  MakeBtn(Row1, 'Step Decay (+0.15s)', @BtnStepDecayClick);
  MakeBtn(Row1, 'Shadow-Step Violet Preset', @BtnShadowVioletClick);
  MakeBtn(Row1, 'Toggle Medusa Statue Freeze', @BtnToggleStatueClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintTimeline := TPaintBox.Create(Self);
  FPaintTimeline.Parent := BodyPanel;
  FPaintTimeline.Align := alLeft;
  FPaintTimeline.Width := 460;
  FPaintTimeline.OnPaint := @PaintGhostRing;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TPoseSnapshotForm.NotifyChanged;
begin
  if Assigned(FOnModified) then FOnModified('Pose Snapshot Studio');
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TPoseSnapshotForm.RefreshView;
var
  Trail: TCastlePoseSnapshotTrail;
begin
  Trail := TPoseSnapshotHelper.FindPoseTrailInHierarchy(FDesignRoot);
  if Trail = nil then
    FLblSummary.Caption := 'No TCastlePoseSnapshotTrail in scene — click "+ Spawn Cyan Dash Trail".'
  else
    FLblSummary.Caption := Format('%s %s | Total Captured: %d | Frozen Statue: %s', [
      Trail.Name, Trail.PoseSummaryBadge, Trail.TotalCapturedCount,
      BoolToStr(Trail.IsStatueFrozen, 'YES (PETRIFIED)', 'NO')]);
  FMemoReport.Lines.Text := TPoseSnapshotHelper.GeneratePoseSnapshotReport(Trail);
  FPaintTimeline.Invalidate;
end;

procedure TPoseSnapshotForm.BtnSpawnDemoClick(Sender: TObject);
var
  Trail: TCastlePoseSnapshotTrail;
begin
  FDashCursorX := 7.4;
  if TPoseSnapshotHelper.SpawnDashGhostTrailDemo(FDesignRoot, FDesignOwner, Trail) then
    NotifyChanged;
end;

procedure TPoseSnapshotForm.BtnCaptureDashStepClick(Sender: TObject);
var
  Trail: TCastlePoseSnapshotTrail;
begin
  Trail := TPoseSnapshotHelper.FindPoseTrailInHierarchy(FDesignRoot);
  if Trail = nil then Exit;
  Trail.CaptureDashAfterimage(Vector3(FDashCursorX, 0.0, Sin(FDashCursorX * 0.4) * 1.2), 0.15, FDashCursorX * 0.2);
  FDashCursorX := FDashCursorX + 1.8;
  NotifyChanged;
end;

procedure TPoseSnapshotForm.BtnStepDecayClick(Sender: TObject);
var
  Trail: TCastlePoseSnapshotTrail;
begin
  Trail := TPoseSnapshotHelper.FindPoseTrailInHierarchy(FDesignRoot);
  if Trail = nil then Exit;
  Trail.StepGhostDecay(0.15);
  NotifyChanged;
end;

procedure TPoseSnapshotForm.BtnShadowVioletClick(Sender: TObject);
var
  Trail: TCastlePoseSnapshotTrail;
begin
  Trail := TPoseSnapshotHelper.FindPoseTrailInHierarchy(FDesignRoot);
  if Trail = nil then Exit;
  Trail.Preset := ptpShadowStepViolet;
  NotifyChanged;
end;

procedure TPoseSnapshotForm.BtnToggleStatueClick(Sender: TObject);
var
  Trail: TCastlePoseSnapshotTrail;
begin
  Trail := TPoseSnapshotHelper.FindPoseTrailInHierarchy(FDesignRoot);
  if Trail = nil then Exit;
  if Trail.IsStatueFrozen then
    Trail.UnfreezeStatuePose
  else
    Trail.FreezeStatuePose(Vector3(FDashCursorX, 0.0, 0.0), 0.25, 0.50);
  NotifyChanged;
end;

procedure TPoseSnapshotForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TPoseSnapshotForm.PaintGhostRing(Sender: TObject);
var
  C: TCanvas;
  Trail: TCastlePoseSnapshotTrail;
  I, BarY, BarW: Integer;
  G: TPoseGhostEntry;
begin
  C := FPaintTimeline.Canvas;
  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, FPaintTimeline.Width, FPaintTimeline.Height);

  Trail := TPoseSnapshotHelper.FindPoseTrailInHierarchy(FDesignRoot);
  if Trail = nil then Exit;

  for I := 0 to Trail.MaxGhostCount - 1 do
  begin
    G := Trail.GetGhostSlot(I);
    BarY := 24 + I * 34;
    C.Brush.Color := RGBToColor(30, 36, 48);
    C.Pen.Color := RGBToColor(64, 78, 98);
    C.Rectangle(20, BarY, FPaintTimeline.Width - 20, BarY + 26);
    if G.Active then
    begin
      BarW := Round((FPaintTimeline.Width - 44) * EnsureRange(G.CurrentAlpha, 0.0, 1.0));
      C.Brush.Color := RGBToColor(
        Round(EnsureRange(G.TintColor.X, 0.0, 1.0) * 240),
        Round(EnsureRange(G.TintColor.Y, 0.0, 1.0) * 240),
        Round(EnsureRange(G.TintColor.Z, 0.0, 1.0) * 240));
      C.Rectangle(22, BarY + 2, 22 + BarW, BarY + 24);
    end;
  end;
end;

end.
