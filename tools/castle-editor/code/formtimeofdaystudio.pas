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

{ Interactive 24-Hour Solar Ephemeris, Sky/Atmosphere & Weather Studio
  (@link(TTimeOfDayStudioForm)) with live 24h sky-gradient + solar-arc scrubber,
  1-click weather presets, and live day-cycle transport (Phase 299). }
unit FormTimeOfDayStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleColors, CastleUtils,
  CastleTimeOfDayWeather, ToolTimeOfDayStudio;

type
  TTimeOfDayStudioModifiedCallback = procedure(const AComment: String) of object;
  TTimeOfDayStudioRefreshViewportCallback = procedure of object;

  TTimeOfDayStudioForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FSelectedComponent: TComponent;
    FOnModified: TTimeOfDayStudioModifiedCallback;
    FOnRefreshViewport: TTimeOfDayStudioRefreshViewportCallback;

    FControllers: TTimeOfDayControllerArray;
    FScrubbingTimeline: Boolean;
    FCyclePlaying: Boolean;
    FDirtyFromLiveScrub: Boolean;

    TimerCycle: TTimer;

    ButtonEnsureRig: TButton;
    ButtonPresetSunny: TButton;
    ButtonPresetDusk: TButton;
    ButtonPresetFog: TButton;
    ButtonPresetStorm: TButton;
    ButtonPresetBlizzard: TButton;
    ButtonPresetBloodMoon: TButton;
    ButtonToggleCycle: TButton;
    ButtonCopyMarkdown: TButton;

    ListBoxControllers: TListBox;
    EditHour: TEdit;
    EditLatitude: TEdit;
    EditDayOfYear: TEdit;
    EditDayLengthSec: TEdit;
    EditClouds: TEdit;
    EditPrecip: TEdit;
    EditFogMult: TEdit;
    EditWindDir: TEdit;
    EditWindSpeed: TEdit;
    CheckAutoAdvance: TCheckBox;
    ButtonApplyProps: TButton;

    PaintBoxSkyTimeline: TPaintBox;
    MemoDiagnostics: TMemo;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveController: TCastleTimeOfDayWeather;
    procedure RefreshControllerList(const ASelect: TCastleTimeOfDayWeather = nil);
    procedure LoadActiveIntoControls;
    procedure NotifyModified(const AComment: String);
    procedure ApplyQuickPreset(const APreset: TWeatherPreset; const ALabel: String);
    procedure ScrubTimelineAtX(const AX: Integer);

    procedure ButtonEnsureRigClick(Sender: TObject);
    procedure ButtonPresetSunnyClick(Sender: TObject);
    procedure ButtonPresetDuskClick(Sender: TObject);
    procedure ButtonPresetFogClick(Sender: TObject);
    procedure ButtonPresetStormClick(Sender: TObject);
    procedure ButtonPresetBlizzardClick(Sender: TObject);
    procedure ButtonPresetBloodMoonClick(Sender: TObject);
    procedure ButtonToggleCycleClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);

    procedure ListBoxControllersClick(Sender: TObject);
    procedure ButtonApplyPropsClick(Sender: TObject);

    procedure PaintBoxSkyTimelinePaint(Sender: TObject);
    procedure PaintBoxSkyTimelineMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBoxSkyTimelineMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBoxSkyTimelineMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure TimerCycleTimer(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
      const AOnModified: TTimeOfDayStudioModifiedCallback;
      const AOnRefreshViewport: TTimeOfDayStudioRefreshViewportCallback);
  end;

implementation

function RgbToTColor(const C: TCastleColorRGB): TColor;
begin
  Result := RGBToColor(
    Round(Clamped(C.X, 0.0, 1.0) * 255.0),
    Round(Clamped(C.Y, 0.0, 1.0) * 255.0),
    Round(Clamped(C.Z, 0.0, 1.0) * 255.0)
  );
end;

{ TTimeOfDayStudioForm ------------------------------------------------------- }

constructor TTimeOfDayStudioForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
  const AOnModified: TTimeOfDayStudioModifiedCallback;
  const AOnRefreshViewport: TTimeOfDayStudioRefreshViewportCallback);
var
  InitCtrl: TCastleTimeOfDayWeather;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FSelectedComponent := ASelectedComponent;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Dynamic Time-of-Day, Solar Ephemeris & Weather Studio';
  Width := 1040;
  Height := 700;
  Position := poMainFormCenter;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 600;

  TimerCycle := TTimer.Create(Self);
  TimerCycle.Interval := 40;
  TimerCycle.Enabled := false;
  TimerCycle.OnTimer := @TimerCycleTimer;

  BuildUi;

  InitCtrl := nil;
  if ASelectedComponent is TCastleTimeOfDayWeather then
    InitCtrl := TCastleTimeOfDayWeather(ASelectedComponent);
  RefreshControllerList(InitCtrl);
end;

procedure TTimeOfDayStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelRight: TPanel;
  YPos: Integer;

  function MakeTopButton(const ACaption: String; const ALeft, AWidth: Integer;
    const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PanelTop;
    Result.Left := ALeft;
    Result.Top := 8;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

  function AddLabeledEdit(const AParent: TWinControl; const ATitle: String;
    var ATop: Integer; const ADefault: String): TEdit;
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := AParent;
    Lbl.Left := 10;
    Lbl.Top := ATop + 4;
    Lbl.Caption := ATitle;

    Result := TEdit.Create(Self);
    Result.Parent := AParent;
    Result.Left := 180;
    Result.Top := ATop;
    Result.Width := 135;
    Result.Text := ADefault;
    Inc(ATop, 28);
  end;

var
  LblList, LblSky, LblDiag: TLabel;
begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 46;
  PanelTop.BevelOuter := bvNone;

  ButtonEnsureRig := MakeTopButton('+ Ensure Sky/Sun/Fog Rig', 8, 172, @ButtonEnsureRigClick);
  ButtonPresetSunny := MakeTopButton('Sunny 11:30', 186, 94, @ButtonPresetSunnyClick);
  ButtonPresetDusk := MakeTopButton('Dusk 18:30', 284, 90, @ButtonPresetDuskClick);
  ButtonPresetFog := MakeTopButton('Fog 09:00', 378, 84, @ButtonPresetFogClick);
  ButtonPresetStorm := MakeTopButton('Storm 15:00', 466, 94, @ButtonPresetStormClick);
  ButtonPresetBlizzard := MakeTopButton('Blizzard', 564, 82, @ButtonPresetBlizzardClick);
  ButtonPresetBloodMoon := MakeTopButton('Blood Moon', 650, 96, @ButtonPresetBloodMoonClick);
  ButtonToggleCycle := MakeTopButton('Play 24h Cycle', 754, 118, @ButtonToggleCycleClick);
  ButtonCopyMarkdown := MakeTopButton('Copy Report', 878, 108, @ButtonCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.Left := 12;
  LabelStatus.Top := 12;
  LabelStatus.Caption := 'Drag across the 24h Solar Ephemeris timeline to scrub sun/moon angles, sky colors, and fog live.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.Left := Width - 104;
  ButtonClose.Top := 6;
  ButtonClose.Width := 90;
  ButtonClose.Height := 30;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 332;
  PanelLeft.BevelOuter := bvLowered;

  LblList := TLabel.Create(Self);
  LblList.Parent := PanelLeft;
  LblList.Left := 10;
  LblList.Top := 8;
  LblList.Caption := 'Time-of-Day Controllers in Design:';

  ListBoxControllers := TListBox.Create(Self);
  ListBoxControllers.Parent := PanelLeft;
  ListBoxControllers.Left := 10;
  ListBoxControllers.Top := 28;
  ListBoxControllers.Width := 308;
  ListBoxControllers.Height := 90;
  ListBoxControllers.OnClick := @ListBoxControllersClick;

  YPos := 128;
  EditHour := AddLabeledEdit(PanelLeft, 'Clock Hour (0..24):', YPos, '10.50');
  EditLatitude := AddLabeledEdit(PanelLeft, 'Latitude (deg):', YPos, '35.0');
  EditDayOfYear := AddLabeledEdit(PanelLeft, 'Day of Year (1..365):', YPos, '172');
  EditDayLengthSec := AddLabeledEdit(PanelLeft, 'Day Cycle Length (s):', YPos, '600.0');
  EditClouds := AddLabeledEdit(PanelLeft, 'Cloud Coverage (0..1):', YPos, '0.12');
  EditPrecip := AddLabeledEdit(PanelLeft, 'Precipitation (0..1):', YPos, '0.00');
  EditFogMult := AddLabeledEdit(PanelLeft, 'Fog Density Mult:', YPos, '1.00');
  EditWindDir := AddLabeledEdit(PanelLeft, 'Wind Direction (deg):', YPos, '45.0');
  EditWindSpeed := AddLabeledEdit(PanelLeft, 'Wind Speed (m/s):', YPos, '2.50');

  CheckAutoAdvance := TCheckBox.Create(Self);
  CheckAutoAdvance.Parent := PanelLeft;
  CheckAutoAdvance.Left := 10;
  CheckAutoAdvance.Top := YPos + 4;
  CheckAutoAdvance.Caption := 'Auto-Advance Cycle in Runtime';
  Inc(YPos, 30);

  ButtonApplyProps := TButton.Create(Self);
  ButtonApplyProps.Parent := PanelLeft;
  ButtonApplyProps.Left := 10;
  ButtonApplyProps.Top := YPos + 4;
  ButtonApplyProps.Width := 308;
  ButtonApplyProps.Height := 32;
  ButtonApplyProps.Caption := 'Apply Ephemeris & Weather Parameters';
  ButtonApplyProps.OnClick := @ButtonApplyPropsClick;

  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := PanelBody;
  PanelRight.Align := alClient;
  PanelRight.BevelOuter := bvNone;

  LblSky := TLabel.Create(Self);
  LblSky.Parent := PanelRight;
  LblSky.Left := 12;
  LblSky.Top := 8;
  LblSky.Caption := '24-Hour Solar Ephemeris & Sky-Dome Scrubber (LMB Click / Drag 00:00 -> 24:00):';

  PaintBoxSkyTimeline := TPaintBox.Create(Self);
  PaintBoxSkyTimeline.Parent := PanelRight;
  PaintBoxSkyTimeline.Left := 12;
  PaintBoxSkyTimeline.Top := 28;
  PaintBoxSkyTimeline.Width := PanelRight.Width - 24;
  PaintBoxSkyTimeline.Height := 250;
  PaintBoxSkyTimeline.Anchors := [akTop, akLeft, akRight];
  PaintBoxSkyTimeline.OnPaint := @PaintBoxSkyTimelinePaint;
  PaintBoxSkyTimeline.OnMouseDown := @PaintBoxSkyTimelineMouseDown;
  PaintBoxSkyTimeline.OnMouseMove := @PaintBoxSkyTimelineMouseMove;
  PaintBoxSkyTimeline.OnMouseUp := @PaintBoxSkyTimelineMouseUp;

  LblDiag := TLabel.Create(Self);
  LblDiag.Parent := PanelRight;
  LblDiag.Left := 12;
  LblDiag.Top := 288;
  LblDiag.Caption := 'Live Solar/Lunar Ephemeris Schedule & Rig Diagnostics:';

  MemoDiagnostics := TMemo.Create(Self);
  MemoDiagnostics.Parent := PanelRight;
  MemoDiagnostics.Left := 12;
  MemoDiagnostics.Top := 308;
  MemoDiagnostics.Width := PanelRight.Width - 24;
  MemoDiagnostics.Height := PanelRight.Height - 318;
  MemoDiagnostics.Anchors := [akTop, akLeft, akRight, akBottom];
  MemoDiagnostics.ReadOnly := true;
  MemoDiagnostics.ScrollBars := ssBoth;
  MemoDiagnostics.Font.Name := 'Courier New';
end;

function TTimeOfDayStudioForm.ActiveController: TCastleTimeOfDayWeather;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := ListBoxControllers.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FControllers)) then
    Result := FControllers[Idx];
end;

procedure TTimeOfDayStudioForm.RefreshControllerList(
  const ASelect: TCastleTimeOfDayWeather);
var
  Sum: TTimeOfDayStudioSummary;
  I, SelIdx: Integer;
begin
  Sum := TTimeOfDayStudioHelper.ScanTimeOfDayControllers(FRootComponent);
  FControllers := Sum.Controllers;

  ListBoxControllers.Items.BeginUpdate;
  try
    ListBoxControllers.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FControllers) do
    begin
      ListBoxControllers.Items.Add(Format('%s  %s',
        [FControllers[I].Name, FControllers[I].TimeOfDaySummaryBadge]));
      if FControllers[I] = ASelect then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FControllers) > 0) then
      SelIdx := 0;
    ListBoxControllers.ItemIndex := SelIdx;
  finally
    ListBoxControllers.Items.EndUpdate;
  end;

  LoadActiveIntoControls;
  MemoDiagnostics.Text := TTimeOfDayStudioHelper.BuildMarkdownReport(FRootComponent);
  PaintBoxSkyTimeline.Invalidate;
end;

procedure TTimeOfDayStudioForm.LoadActiveIntoControls;
var
  C: TCastleTimeOfDayWeather;
begin
  C := ActiveController;
  if C = nil then
    Exit;
  EditHour.Text := FormatFloat('0.00', C.TimeOfDayHours);
  EditLatitude.Text := FormatFloat('0.0', C.LatitudeDeg);
  EditDayOfYear.Text := IntToStr(C.DayOfYear);
  EditDayLengthSec.Text := FormatFloat('0.0', C.DayLengthRealSeconds);
  EditClouds.Text := FormatFloat('0.00', C.CloudCoverage);
  EditPrecip.Text := FormatFloat('0.00', C.PrecipitationIntensity);
  EditFogMult.Text := FormatFloat('0.00', C.FogDensityMultiplier);
  EditWindDir.Text := FormatFloat('0.0', C.WindDirectionDeg);
  EditWindSpeed.Text := FormatFloat('0.00', C.WindSpeed);
  CheckAutoAdvance.Checked := C.AutoAdvanceInRuntime;
end;

procedure TTimeOfDayStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TTimeOfDayStudioForm.ApplyQuickPreset(const APreset: TWeatherPreset;
  const ALabel: String);
var
  C: TCastleTimeOfDayWeather;
begin
  C := ActiveController;
  if C = nil then
    C := TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(
      FRootComponent, FDesignOwner, APreset)
  else
    C.ApplyPresetWithRecommendedHour(APreset);

  if C = nil then
    Exit;

  NotifyModified('Apply Time-of-Day Preset: ' + ALabel);
  RefreshControllerList(C);
  LabelStatus.Caption := Format('Applied "%s" (%s) onto "%s".',
    [ALabel, C.FormatClockHHMM, C.Name]);
end;

procedure TTimeOfDayStudioForm.ButtonEnsureRigClick(Sender: TObject);
var
  C: TCastleTimeOfDayWeather;
begin
  C := TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(
    FRootComponent, FDesignOwner, wpClearSunny);
  if C <> nil then
  begin
    NotifyModified('Ensure Time-of-Day Sky/Sun/Fog Rig');
    RefreshControllerList(C);
    LabelStatus.Caption := Format('Ensured complete Time-of-Day rig ("%s").', [C.Name]);
  end;
end;

procedure TTimeOfDayStudioForm.ButtonPresetSunnyClick(Sender: TObject);
begin
  ApplyQuickPreset(wpClearSunny, 'Clear Sunny');
end;

procedure TTimeOfDayStudioForm.ButtonPresetDuskClick(Sender: TObject);
begin
  ApplyQuickPreset(wpGoldenDusk, 'Golden Dusk');
end;

procedure TTimeOfDayStudioForm.ButtonPresetFogClick(Sender: TObject);
begin
  ApplyQuickPreset(wpOvercastFog, 'Overcast Fog');
end;

procedure TTimeOfDayStudioForm.ButtonPresetStormClick(Sender: TObject);
begin
  ApplyQuickPreset(wpRainStorm, 'Rain Storm');
end;

procedure TTimeOfDayStudioForm.ButtonPresetBlizzardClick(Sender: TObject);
begin
  ApplyQuickPreset(wpBlizzardSnow, 'Blizzard Snow');
end;

procedure TTimeOfDayStudioForm.ButtonPresetBloodMoonClick(Sender: TObject);
begin
  ApplyQuickPreset(wpBloodMoon, 'Blood Moon');
end;

procedure TTimeOfDayStudioForm.ButtonToggleCycleClick(Sender: TObject);
var
  C: TCastleTimeOfDayWeather;
begin
  C := ActiveController;
  if C = nil then
    C := TTimeOfDayStudioHelper.EnsureTimeOfDayRigInDesign(FRootComponent, FDesignOwner, wpClearSunny);
  if C = nil then
    Exit;

  FCyclePlaying := not FCyclePlaying;
  TimerCycle.Enabled := FCyclePlaying;
  if FCyclePlaying then
  begin
    ButtonToggleCycle.Caption := 'Pause Cycle';
    LabelStatus.Caption := 'Playing live 24-hour solar cycle in viewport...';
  end else
  begin
    ButtonToggleCycle.Caption := 'Play 24h Cycle';
    NotifyModified('Advance 24h Time-of-Day Cycle');
    RefreshControllerList(C);
  end;
end;

procedure TTimeOfDayStudioForm.TimerCycleTimer(Sender: TObject);
var
  C: TCastleTimeOfDayWeather;
begin
  C := ActiveController;
  if C = nil then
  begin
    FCyclePlaying := false;
    TimerCycle.Enabled := false;
    Exit;
  end;
  C.TimeOfDayHours := C.TimeOfDayHours + 0.12;
  EditHour.Text := FormatFloat('0.00', C.TimeOfDayHours);
  LabelStatus.Caption := Format('Live Cycle: %s | Elev=%.1f deg | Light=%.2f lux',
    [C.FormatClockHHMM, C.CurrentAtmosphere.SolarElevationDeg, C.CurrentAtmosphere.DirectLightIntensity]);
  PaintBoxSkyTimeline.Invalidate;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TTimeOfDayStudioForm.ButtonCopyMarkdownClick(Sender: TObject);
var
  Report: String;
begin
  Report := TTimeOfDayStudioHelper.BuildMarkdownReport(FRootComponent);
  Clipboard.AsText := Report;
  MemoDiagnostics.Text := Report;
  LabelStatus.Caption := 'Copied 24-hour Time-of-Day & Weather Markdown report to clipboard.';
end;

procedure TTimeOfDayStudioForm.ListBoxControllersClick(Sender: TObject);
begin
  LoadActiveIntoControls;
  PaintBoxSkyTimeline.Invalidate;
end;

procedure TTimeOfDayStudioForm.ButtonApplyPropsClick(Sender: TObject);
var
  C: TCastleTimeOfDayWeather;
begin
  C := ActiveController;
  if C = nil then
    Exit;
  C.TimeOfDayHours := StrToFloatDef(EditHour.Text, C.TimeOfDayHours);
  C.LatitudeDeg := StrToFloatDef(EditLatitude.Text, C.LatitudeDeg);
  C.DayOfYear := StrToIntDef(EditDayOfYear.Text, C.DayOfYear);
  C.DayLengthRealSeconds := StrToFloatDef(EditDayLengthSec.Text, C.DayLengthRealSeconds);
  C.CloudCoverage := StrToFloatDef(EditClouds.Text, C.CloudCoverage);
  C.PrecipitationIntensity := StrToFloatDef(EditPrecip.Text, C.PrecipitationIntensity);
  C.FogDensityMultiplier := StrToFloatDef(EditFogMult.Text, C.FogDensityMultiplier);
  C.WindDirectionDeg := StrToFloatDef(EditWindDir.Text, C.WindDirectionDeg);
  C.WindSpeed := StrToFloatDef(EditWindSpeed.Text, C.WindSpeed);
  C.AutoAdvanceInRuntime := CheckAutoAdvance.Checked;
  C.SynchronizeLinkedRig;

  NotifyModified('Update Time-of-Day & Weather Parameters');
  RefreshControllerList(C);
  LabelStatus.Caption := Format('Updated "%s" (%s).', [C.Name, C.FormatClockHHMM]);
end;

procedure TTimeOfDayStudioForm.ScrubTimelineAtX(const AX: Integer);
var
  C: TCastleTimeOfDayWeather;
  W: Integer;
  H: Single;
begin
  C := ActiveController;
  if C = nil then
    Exit;
  W := Max(1, PaintBoxSkyTimeline.Width - 40);
  H := Clamped((AX - 20) / W, 0.0, 0.9995) * 24.0;
  C.TimeOfDayHours := H;
  EditHour.Text := FormatFloat('0.00', C.TimeOfDayHours);
  FDirtyFromLiveScrub := true;
  PaintBoxSkyTimeline.Invalidate;
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TTimeOfDayStudioForm.PaintBoxSkyTimelineMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
  begin
    FScrubbingTimeline := true;
    ScrubTimelineAtX(X);
  end;
end;

procedure TTimeOfDayStudioForm.PaintBoxSkyTimelineMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if FScrubbingTimeline then
    ScrubTimelineAtX(X);
end;

procedure TTimeOfDayStudioForm.PaintBoxSkyTimelineMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FScrubbingTimeline then
  begin
    FScrubbingTimeline := false;
    if FDirtyFromLiveScrub then
    begin
      FDirtyFromLiveScrub := false;
      NotifyModified('Scrub Time-of-Day Clock');
      RefreshControllerList(ActiveController);
    end;
  end;
end;

procedure TTimeOfDayStudioForm.PaintBoxSkyTimelinePaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, PlotW, PlotH, Col, X0, X1, MidY, CurX, CurY, PrevX, PrevY, TickH: Integer;
  C: TCastleTimeOfDayWeather;
  S: TTimeOfDayAtmosphereState;
  HourSample: Single;
begin
  Cv := PaintBoxSkyTimeline.Canvas;
  W := PaintBoxSkyTimeline.Width;
  H := PaintBoxSkyTimeline.Height;

  Cv.Brush.Color := RGBToColor(18, 22, 30);
  Cv.FillRect(0, 0, W, H);

  C := ActiveController;
  if C = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(20, H div 2 - 8,
      'No TCastleTimeOfDayWeather in design — click "+ Ensure Sky/Sun/Fog Rig" above.');
    Exit;
  end;

  PlotW := Max(40, W - 40);
  PlotH := Max(60, H - 44);
  MidY := 16 + PlotH div 2;

  { 1. Render 96 vertical sky-zenith/equator gradient slices across 00:00 .. 24:00. }
  for Col := 0 to 95 do
  begin
    HourSample := (Col + 0.5) / 96.0 * 24.0;
    S := C.EvaluateAtmosphereAtHour(HourSample);
    X0 := 20 + Round((Col / 96.0) * PlotW);
    X1 := 20 + Round(((Col + 1) / 96.0) * PlotW);

    Cv.Brush.Color := RgbToTColor(S.SkyTopColor);
    Cv.FillRect(X0, 16, X1 + 1, MidY);

    Cv.Brush.Color := RgbToTColor(S.SkyEquatorColor);
    Cv.FillRect(X0, MidY, X1 + 1, 16 + PlotH);
  end;

  { 2. Horizon line (Solar Elevation = 0 deg) & 3-hour clock ticks. }
  Cv.Pen.Color := RGBToColor(210, 220, 235);
  Cv.Pen.Width := 1;
  Cv.Pen.Style := psDot;
  Cv.Line(20, MidY, 20 + PlotW, MidY);
  Cv.Pen.Style := psSolid;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  for TickH := 0 to 8 do
  begin
    X0 := 20 + Round((TickH * 3.0 / 24.0) * PlotW);
    Cv.Pen.Color := RGBToColor(120, 130, 150);
    Cv.Line(X0, 16 + PlotH, X0, 22 + PlotH);
    Cv.TextOut(X0 - 12, 23 + PlotH, Format('%.2d:00', [TickH * 3]));
  end;

  { 3. Solar elevation curve (-90..+90 deg). }
  Cv.Pen.Color := RGBToColor(255, 215, 70);
  Cv.Pen.Width := 2;
  PrevX := 20;
  PrevY := MidY;
  for Col := 0 to 96 do
  begin
    HourSample := (Col / 96.0) * 24.0;
    S := C.EvaluateAtmosphereAtHour(HourSample);
    CurX := 20 + Round((Col / 96.0) * PlotW);
    CurY := MidY - Round((S.SolarElevationDeg / 90.0) * (PlotH * 0.45));
    if Col > 0 then
      Cv.Line(PrevX, PrevY, CurX, CurY);
    PrevX := CurX;
    PrevY := CurY;
  end;

  { 4. Active TimeOfDayHours scrubber bar & sun/moon disc. }
  S := C.CurrentAtmosphere;
  CurX := 20 + Round((S.TimeOfDayHours / 24.0) * PlotW);
  CurY := MidY - Round((S.SolarElevationDeg / 90.0) * (PlotH * 0.45));

  Cv.Pen.Color := clWhite;
  Cv.Pen.Width := 2;
  Cv.Line(CurX, 16, CurX, 16 + PlotH);

  Cv.Brush.Style := bsSolid;
  if S.IsNightLunarMode then
    Cv.Brush.Color := RgbToTColor(S.DirectLightColor)
  else
    Cv.Brush.Color := RGBToColor(255, 230, 95);
  Cv.Ellipse(CurX - 7, CurY - 7, CurX + 7, CurY + 7);

  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.Font.Color := clWhite;
  Cv.TextOut(26, 22, Format('%s  |  Elev: %.1f deg  |  Az: %.0f deg  |  Lux: %.2f  |  Fog: %.0f m',
    [C.FormatClockHHMM, S.SolarElevationDeg, S.SolarAzimuthDeg,
     S.DirectLightIntensity, S.FogVisibilityRange]));
end;

procedure TTimeOfDayStudioForm.ButtonCloseClick(Sender: TObject);
begin
  TimerCycle.Enabled := false;
  Close;
end;

end.
