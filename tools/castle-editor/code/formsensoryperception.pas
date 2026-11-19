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

{ Visual Studio dialog for AI Sensory Perception Sight, Hearing & Scent (Phase 378). }
unit FormSensoryPerception;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleViewport, CastleSensoryPerception, ToolSensoryPerception;

type
  TSensoryPerceptionModifiedCallback = procedure(const UndoComment: String) of object;
  TSensoryPerceptionRefreshCallback = procedure of object;

  TSensoryPerceptionForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSensoryPerceptionModifiedCallback;
    FOnRefresh: TSensoryPerceptionRefreshCallback;
    FLblSummary: TLabel;
    FPaintRadar: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnTestFovealClearClick(Sender: TObject);
    procedure BtnTestWallBlockedClick(Sender: TObject);
    procedure BtnTestMuffledSoundClick(Sender: TObject);
    procedure BtnBloodhoundScentClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintRadarCones(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSensoryPerceptionModifiedCallback;
      const AOnRefresh: TSensoryPerceptionRefreshCallback);
  end;

implementation

constructor TSensoryPerceptionForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSensoryPerceptionModifiedCallback;
  const AOnRefresh: TSensoryPerceptionRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'AI Sensory Perception Sight, Hearing & Decaying Scent Studio (Phase 378)';
  Width := 1040;
  Height := 650;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TSensoryPerceptionForm.BuildUi;
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

  MakeBtn(Row1, '+ Spawn Stealth Courtyard Sensor', @BtnSpawnDemoClick);
  MakeBtn(Row1, 'Test Clear Foveal Sight', @BtnTestFovealClearClick);
  MakeBtn(Row1, 'Test Wall-Blocked Sight', @BtnTestWallBlockedClick);
  MakeBtn(Row1, 'Emit Gunshot Behind Wall (88 dB)', @BtnTestMuffledSoundClick);
  MakeBtn(Row1, 'Bloodhound Scent Track', @BtnBloodhoundScentClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintRadar := TPaintBox.Create(Self);
  FPaintRadar.Parent := BodyPanel;
  FPaintRadar.Align := alLeft;
  FPaintRadar.Width := 460;
  FPaintRadar.OnPaint := @PaintRadarCones;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TSensoryPerceptionForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TSensoryPerceptionForm.RefreshView;
var
  S: TCastleSensoryPerception;
begin
  S := TSensoryPerceptionHelper.FindSensorInHierarchy(FDesignRoot);
  if S = nil then
    FLblSummary.Caption := 'No TCastleSensoryPerception in scene — click "+ Spawn Stealth Courtyard Sensor".'
  else
    FLblSummary.Caption := Format('%s %s | Last: %s', [
      S.Name, S.SensorySummaryBadge, S.LastStimulusSummary]);
  FMemoReport.Lines.Text := TSensoryPerceptionHelper.GenerateSensoryReport(S);
  FPaintRadar.Invalidate;
end;

procedure TSensoryPerceptionForm.BtnSpawnDemoClick(Sender: TObject);
var
  S: TCastleSensoryPerception;
begin
  if TSensoryPerceptionHelper.SpawnStealthCourtyardSensorDemo(FDesignRoot, FDesignOwner, S) then
    NotifyChanged('Spawn Stealth Courtyard Sensor');
end;

procedure TSensoryPerceptionForm.BtnTestFovealClearClick(Sender: TObject);
var
  S: TCastleSensoryPerception;
  Vp: TCastleViewport;
begin
  S := TSensoryPerceptionHelper.FindSensorInHierarchy(FDesignRoot);
  Vp := TSensoryPerceptionHelper.FindViewport(FDesignRoot);
  if (S = nil) or (Vp = nil) then Exit;
  S.EvaluateSightTarget(Vp.Items, Vector3(4.2, 1.5, 9.5));
  RefreshView;
end;

procedure TSensoryPerceptionForm.BtnTestWallBlockedClick(Sender: TObject);
var
  S: TCastleSensoryPerception;
  Vp: TCastleViewport;
begin
  S := TSensoryPerceptionHelper.FindSensorInHierarchy(FDesignRoot);
  Vp := TSensoryPerceptionHelper.FindViewport(FDesignRoot);
  if (S = nil) or (Vp = nil) then Exit;
  S.ClearAllStimuli;
  S.EvaluateSightTarget(Vp.Items, Vector3(0.0, 1.5, 13.0));
  RefreshView;
end;

procedure TSensoryPerceptionForm.BtnTestMuffledSoundClick(Sender: TObject);
var
  S: TCastleSensoryPerception;
  Vp: TCastleViewport;
begin
  S := TSensoryPerceptionHelper.FindSensorInHierarchy(FDesignRoot);
  Vp := TSensoryPerceptionHelper.FindViewport(FDesignRoot);
  if (S = nil) or (Vp = nil) then Exit;
  S.EvaluateAcousticEvent(Vp.Items, Vector3(0.0, 1.2, 14.0), 88.0);
  RefreshView;
end;

procedure TSensoryPerceptionForm.BtnBloodhoundScentClick(Sender: TObject);
var
  S: TCastleSensoryPerception;
  BestPos: TVector3;
  BestTag: String;
begin
  S := TSensoryPerceptionHelper.FindSensorInHierarchy(FDesignRoot);
  if S = nil then Exit;
  S.Preset := sppBloodhoundTracker;
  S.DropScentBreadcrumb('IntruderBootprints', Vector3(3.5, 0.0, 5.0), 0.92);
  S.SampleStrongestScent(BestPos, BestTag);
  NotifyChanged('Bloodhound Scent Track');
end;

procedure TSensoryPerceptionForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TSensoryPerceptionForm.PaintRadarCones(Sender: TObject);
var
  Cv: TCanvas;
  S: TCastleSensoryPerception;
  Ox, Oy, R: Integer;
  PerRad, FovRad: Single;
begin
  Cv := FPaintRadar.Canvas;
  Cv.Brush.Color := RGBToColor(14, 20, 26);
  Cv.FillRect(0, 0, FPaintRadar.Width, FPaintRadar.Height);

  S := TSensoryPerceptionHelper.FindSensorInHierarchy(FDesignRoot);
  if S = nil then Exit;

  Ox := FPaintRadar.Width div 2;
  Oy := FPaintRadar.Height - 50;
  R := 260;

  PerRad := DegToRad(S.PeripheralHalfAngleDeg);
  FovRad := DegToRad(S.FovealHalfAngleDeg);

  Cv.Pen.Color := RGBToColor(235, 175, 55);
  Cv.Line(Ox, Oy, Ox - Round(Sin(PerRad) * R * 0.8), Oy - Round(Cos(PerRad) * R * 0.8));
  Cv.Line(Ox, Oy, Ox + Round(Sin(PerRad) * R * 0.8), Oy - Round(Cos(PerRad) * R * 0.8));

  Cv.Pen.Width := 2;
  Cv.Pen.Color := RGBToColor(70, 235, 145);
  Cv.Line(Ox, Oy, Ox - Round(Sin(FovRad) * R), Oy - Round(Cos(FovRad) * R));
  Cv.Line(Ox, Oy, Ox + Round(Sin(FovRad) * R), Oy - Round(Cos(FovRad) * R));
  Cv.Pen.Width := 1;
end;

end.
