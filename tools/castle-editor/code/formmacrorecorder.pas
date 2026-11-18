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

{ Visual Studio dialog for Editor Action Macro Recorder & 96-Studio Hub (Phase 376). }
unit FormMacroRecorder;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, ToolMacroRecorder, ToolStudioHub;

type
  TMacroRecorderModifiedCallback = procedure(const UndoComment: String) of object;
  TMacroRecorderRefreshCallback = procedure of object;

  TMacroRecorderForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMacroRecorderModifiedCallback;
    FOnRefresh: TMacroRecorderRefreshCallback;
    FLblSummary: TLabel;
    FPaintPipeline: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnRecordPresetClick(Sender: TObject);
    procedure BtnReplay1xClick(Sender: TObject);
    procedure BtnReplay2xClick(Sender: TObject);
    procedure BtnClearMacroClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintPipelineCanvas(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMacroRecorderModifiedCallback;
      const AOnRefresh: TMacroRecorderRefreshCallback);
  end;

implementation

constructor TMacroRecorderForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMacroRecorderModifiedCallback;
  const AOnRefresh: TMacroRecorderRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Editor Action Macro Recorder & 96-Studio Hub Studio (Phase 376)';
  Width := 1040;
  Height := 650;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TMacroRecorderForm.BuildUi;
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

  MakeBtn(Row1, '+ Spawn 4 Crate Pillars Demo', @BtnSpawnDemoClick);
  MakeBtn(Row1, 'Record 3-Step Crate Batch Macro', @BtnRecordPresetClick);
  MakeBtn(Row1, 'Replay Macro (1.0x)', @BtnReplay1xClick);
  MakeBtn(Row1, 'Replay Macro (2.0x Boost)', @BtnReplay2xClick);
  MakeBtn(Row1, 'Clear Macro Steps', @BtnClearMacroClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintPipeline := TPaintBox.Create(Self);
  FPaintPipeline.Parent := BodyPanel;
  FPaintPipeline.Align := alLeft;
  FPaintPipeline.Width := 460;
  FPaintPipeline.OnPaint := @PaintPipelineCanvas;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TMacroRecorderForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TMacroRecorderForm.RefreshView;
var
  Rec: TEditorMacroRecorder;
begin
  Rec := TEditorMacroRecorder.SharedRecorder;
  FLblSummary.Caption := Format(
    'UE 6.0+ Editor Macro Parity — %s (%d steps, %d replays, %d touched) | %d Studios & 19 MCP Tools',
    [Rec.MacroName, Rec.StepCount, Rec.ReplayCount, Rec.LastAffectedCount,
     TStudioHubManager.StudioCount]);
  FMemoReport.Lines.Text := Rec.GenerateMacroReport(FDesignRoot);
  FPaintPipeline.Invalidate;
end;

procedure TMacroRecorderForm.BtnSpawnDemoClick(Sender: TObject);
begin
  if TEditorMacroRecorder.SpawnCratePillarsDemo(FDesignRoot, FDesignOwner) > 0 then
    NotifyChanged('Spawn Macro Crate Pillars Demo')
  else
    RefreshView;
end;

procedure TMacroRecorderForm.BtnRecordPresetClick(Sender: TObject);
var
  Rec: TEditorMacroRecorder;
begin
  Rec := TEditorMacroRecorder.SharedRecorder;
  Rec.ClearSteps;
  Rec.StartRecording('ElevateAndTintCrates');
  Rec.RecordStep(mskAddTranslate, 'MacroCrate', Vector3(0.0, 1.25, 0.0));
  Rec.RecordStep(mskMultiplyScale, 'MacroCrate', Vector3(1.0, 1.35, 1.0));
  Rec.RecordStep(mskSetBoxColorRgb, 'MacroCrate', Vector3(0.22, 0.82, 0.56));
  Rec.StopRecording;
  RefreshView;
end;

procedure TMacroRecorderForm.BtnReplay1xClick(Sender: TObject);
begin
  if TEditorMacroRecorder.SharedRecorder.ReplayMacro(FDesignRoot, 1.0) > 0 then
    NotifyChanged('Replay Editor Macro (1.0x)')
  else
    RefreshView;
end;

procedure TMacroRecorderForm.BtnReplay2xClick(Sender: TObject);
begin
  if TEditorMacroRecorder.SharedRecorder.ReplayMacro(FDesignRoot, 2.0) > 0 then
    NotifyChanged('Replay Editor Macro (2.0x)')
  else
    RefreshView;
end;

procedure TMacroRecorderForm.BtnClearMacroClick(Sender: TObject);
begin
  TEditorMacroRecorder.SharedRecorder.ClearSteps;
  RefreshView;
end;

procedure TMacroRecorderForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TMacroRecorderForm.PaintPipelineCanvas(Sender: TObject);
var
  Cv: TCanvas;
  Rec: TEditorMacroRecorder;
  I, BoxY: Integer;
  S: TEditorMacroStep;
begin
  Cv := FPaintPipeline.Canvas;
  Cv.Brush.Color := RGBToColor(16, 21, 30);
  Cv.FillRect(0, 0, FPaintPipeline.Width, FPaintPipeline.Height);

  Cv.Font.Color := RGBToColor(110, 225, 175);
  Cv.Font.Style := [fsBold];
  Cv.TextOut(16, 12, Format('Horizon 11 Unified Hub: %d Studios | 19 MCP Tools', [
    TStudioHubManager.StudioCount]));

  Rec := TEditorMacroRecorder.SharedRecorder;
  Cv.Font.Style := [];
  for I := 0 to Min(Rec.StepCount - 1, 9) do
  begin
    S := Rec.GetStep(I);
    BoxY := 44 + I * 48;
    Cv.Brush.Color := RGBToColor(30, 40, 56);
    Cv.Pen.Color := RGBToColor(80, 145, 220);
    Cv.Rectangle(16, BoxY, FPaintPipeline.Width - 16, BoxY + 40);
    Cv.Font.Color := RGBToColor(235, 242, 250);
    Cv.TextOut(26, BoxY + 11, Format('#%d  %s  [filter="%s"]', [
      I + 1, TEditorMacroRecorder.StepKindToString(S.Kind), S.TargetFilter]));
  end;
end;

end.
