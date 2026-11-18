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

{ Visual Studio dialog for Async Asset Preloader & VRAM Residency Pool (Phase 365). }
unit FormPreloadStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleAssetPreloader, ToolPreloadStudio;

type
  TPreloadStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TPreloadStudioRefreshCallback = procedure of object;

  TPreloadStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPreloadStudioModifiedCallback;
    FOnRefresh: TPreloadStudioRefreshCallback;
    FPaintPool: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveQueue: TCastleAssetPreloadQueue;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnBossPresetClick(Sender: TObject);
    procedure BtnOpenWorldPresetClick(Sender: TObject);
    procedure BtnCutscenePresetClick(Sender: TObject);
    procedure BtnStepFrameClick(Sender: TObject);
    procedure BtnStressLruClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintVramTimeline(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPreloadStudioModifiedCallback;
      const AOnRefresh: TPreloadStudioRefreshCallback);
  end;

implementation

constructor TPreloadStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPreloadStudioModifiedCallback;
  const AOnRefresh: TPreloadStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Async Asset Preloader, Hitch-Free Warmup Queue & VRAM Residency Studio (Phase 365)';
  Width := 1000;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TPreloadStudioForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ FStreamableManager — Priority Warmup Queue, Strict Frame-Budget ms Throttling & Pinned/LRU VRAM Eviction';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Boss Airlock Preloader', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Boss Arena Door', @BtnBossPresetClick);
  MakeBtn(Row1, 'Preset: Open-World Horizon', @BtnOpenWorldPresetClick);
  MakeBtn(Row1, 'Preset: Cutscene Zero-Hitch', @BtnCutscenePresetClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Step 1 Frame Warmup Slice (Respect ms Budget!)', @BtnStepFrameClick);
  MakeBtn(Row2, 'Enqueue Heavy 140 MB Vista (Test LRU Eviction)', @BtnStressLruClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintPool := TPaintBox.Create(Self);
  FPaintPool.Parent := BodyPanel;
  FPaintPool.Align := alLeft;
  FPaintPool.Width := 480;
  FPaintPool.OnPaint := @PaintVramTimeline;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TPreloadStudioForm.ActiveQueue: TCastleAssetPreloadQueue;
begin
  Result := TPreloadStudioHelper.FindPreloaderInHierarchy(FDesignRoot);
end;

procedure TPreloadStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TPreloadStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TPreloadStudioHelper.GeneratePreloadReport(ActiveQueue);
  FPaintPool.Invalidate;
end;

procedure TPreloadStudioForm.BtnSpawnClick(Sender: TObject);
var
  Q: TCastleAssetPreloadQueue;
begin
  if TPreloadStudioHelper.SpawnBossAirlockPreloadDemo(FDesignRoot, FDesignOwner, Q) then
    NotifyChange('Spawn Boss Airlock Asset Preloader');
end;

procedure TPreloadStudioForm.BtnBossPresetClick(Sender: TObject);
var
  Q: TCastleAssetPreloadQueue;
begin
  Q := ActiveQueue;
  if Q = nil then Exit;
  Q.Preset := papBossArenaSeamlessDoor;
  NotifyChange('Apply Boss Arena Airlock Preset');
end;

procedure TPreloadStudioForm.BtnOpenWorldPresetClick(Sender: TObject);
var
  Q: TCastleAssetPreloadQueue;
begin
  Q := ActiveQueue;
  if Q = nil then Exit;
  Q.Preset := papOpenWorldHorizonPrefetch;
  NotifyChange('Apply Open-World Horizon Prefetch Preset');
end;

procedure TPreloadStudioForm.BtnCutscenePresetClick(Sender: TObject);
var
  Q: TCastleAssetPreloadQueue;
begin
  Q := ActiveQueue;
  if Q = nil then Exit;
  Q.Preset := papCutsceneZeroHitchLock;
  NotifyChange('Apply Cutscene Zero-Hitch Preset');
end;

procedure TPreloadStudioForm.BtnStepFrameClick(Sender: TObject);
var
  Q: TCastleAssetPreloadQueue;
begin
  Q := ActiveQueue;
  if Q = nil then Exit;
  Q.StepFrameWarmupBudget;
  NotifyChange('Step 1 Frame Budgeted Asset Warmup Slice');
end;

procedure TPreloadStudioForm.BtnStressLruClick(Sender: TObject);
var
  Q: TCastleAssetPreloadQueue;
begin
  Q := ActiveQueue;
  if Q = nil then Exit;
  Q.EnqueueAssetRequest(
    Format('castle-data:/megatexture/cliff_tile_%d.ktx2', [Q.EntryCount + 1]),
    prpHighCombatVfx, 140.0, 1.5, False);
  Q.StepFrameWarmupBudget;
  NotifyChange('Enqueue 140 MB Texture & Trigger LRU VRAM Eviction');
end;

procedure TPreloadStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TPreloadStudioHelper.GeneratePreloadReport(ActiveQueue);
end;

procedure TPreloadStudioForm.PaintVramTimeline(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, Y, BarW, MaxBarW: Integer;
  Q: TCastleAssetPreloadQueue;
  E: TPreloadAssetEntry;
  FillRatio: Single;
begin
  Cv := FPaintPool.Canvas;
  W := FPaintPool.Width;
  H := FPaintPool.Height;
  Cv.Brush.Color := RGBToColor(18, 20, 28);
  Cv.FillRect(0, 0, W, H);

  Q := ActiveQueue;
  if Q = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Boss Airlock Preloader" to inspect VRAM Residency Bars.');
    Exit;
  end;

  MaxBarW := W - 36;
  FillRatio := EnsureRange(Q.CurrentResidentVramMB / Max(1.0, Q.MaxVramBudgetMB), 0.0, 1.0);
  Cv.Brush.Color := RGBToColor(40, 46, 62);
  Cv.Rectangle(18, 36, 18 + MaxBarW, 62);
  Cv.Brush.Color := RGBToColor(65, 195, 255);
  Cv.Rectangle(18, 36, 18 + Round(MaxBarW * FillRatio), 62);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(18, 12, Format('VRAM Pool: %.1f / %.1f MB | Frame Slice: %.2f / %.2f ms', [
    Q.CurrentResidentVramMB, Q.MaxVramBudgetMB, Q.LastFrameSpentMs, Q.MaxBudgetMsPerFrame]));

  Y := 82;
  for I := 0 to Min(12, Q.EntryCount - 1) do
  begin
    E := Q.GetEntry(I);
    BarW := Max(28, Round((E.EstimatedVramMB / Max(1.0, Q.MaxVramBudgetMB)) * MaxBarW));
    case E.State of
      prsResidentLoaded:
        if E.PinnedHandle then
          Cv.Brush.Color := RGBToColor(245, 190, 55)
        else
          Cv.Brush.Color := RGBToColor(65, 210, 120);
      prsQueuedPending:
        Cv.Brush.Color := RGBToColor(80, 120, 190);
      prsEvictedCold:
        Cv.Brush.Color := RGBToColor(115, 65, 70);
    end;
    Cv.Brush.Style := bsSolid;
    Cv.Rectangle(18, Y, 18 + Min(MaxBarW, BarW), Y + 24);
    Cv.Brush.Style := bsClear;
    Cv.Font.Color := clWhite;
    Cv.TextOut(24, Y + 4, Format('[%s] %s (%.0fMB)', [
      PreloadStateToString(E.State), ExtractFileName(E.AssetUrl), E.EstimatedVramMB]));
    Inc(Y, 32);
  end;
end;

end.
