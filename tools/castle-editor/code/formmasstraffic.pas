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

{ Visual Studio dialog for MassTraffic Multi-Lane Signal & IDM Headway (Phase 355). }
unit FormMassTraffic;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleMassTraffic, ToolMassTraffic;

type
  TMassTrafficModifiedCallback = procedure(const UndoComment: String) of object;
  TMassTrafficRefreshCallback = procedure of object;

  TMassTrafficForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMassTrafficModifiedCallback;
    FOnRefresh: TMassTrafficRefreshCallback;
    FPaintCrossroads: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveTraffic: TCastleMassTrafficManager;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnDowntownClick(Sender: TObject);
    procedure BtnRushHourClick(Sender: TObject);
    procedure BtnLateNightClick(Sender: TObject);
    procedure BtnStep3SecClick(Sender: TObject);
    procedure BtnStep12SecCycleClick(Sender: TObject);
    procedure BtnForceEWGreenClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCrossroadsMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMassTrafficModifiedCallback;
      const AOnRefresh: TMassTrafficRefreshCallback);
  end;

implementation

constructor TMassTrafficForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMassTrafficModifiedCallback;
  const AOnRefresh: TMassTrafficRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'MassTraffic Multi-Lane Road Network, Signal Phases & IDM Headway Studio (Phase 355)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TMassTrafficForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ MassTraffic — 8-Lane Directed Crossroads, NEMA Conflict-Free 4-Way Signals & Intelligent Driver Model (IDM) Headway';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn 8-Lane Crossroads (24 cars)', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Downtown (24)', @BtnDowntownClick);
  MakeBtn(Row1, 'Preset: Rush Hour (40)', @BtnRushHourClick);
  MakeBtn(Row1, 'Preset: Late Night (16)', @BtnLateNightClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Step Traffic (+3.0s)', @BtnStep3SecClick);
  MakeBtn(Row2, 'Full Signal Cycle (+12.0s)', @BtnStep12SecCycleClick);
  MakeBtn(Row2, 'Force EW=GREEN / NS=RED', @BtnForceEWGreenClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintCrossroads := TPaintBox.Create(Self);
  FPaintCrossroads.Parent := BodyPanel;
  FPaintCrossroads.Align := alLeft;
  FPaintCrossroads.Width := 520;
  FPaintCrossroads.OnPaint := @PaintCrossroadsMap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TMassTrafficForm.ActiveTraffic: TCastleMassTrafficManager;
begin
  Result := TMassTrafficHelper.FindTrafficInHierarchy(FDesignRoot);
end;

procedure TMassTrafficForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TMassTrafficForm.RefreshView;
begin
  FMemoReport.Lines.Text := TMassTrafficHelper.GenerateMassTrafficReport(ActiveTraffic);
  FPaintCrossroads.Invalidate;
end;

procedure TMassTrafficForm.BtnSpawnClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
begin
  if TMassTrafficHelper.SpawnMassTrafficCrossroads(FDesignRoot, FDesignOwner, T) then
    NotifyChange('Spawn MassTraffic 8-Lane Crossroads');
end;

procedure TMassTrafficForm.BtnDowntownClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
begin
  T := ActiveTraffic;
  if T = nil then Exit;
  T.Preset := mtpDowntownCrossroads24;
  NotifyChange('Switch MassTraffic to Downtown Crossroads');
end;

procedure TMassTrafficForm.BtnRushHourClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
begin
  T := ActiveTraffic;
  if T = nil then Exit;
  T.Preset := mtpRushHourGridlock40;
  NotifyChange('Switch MassTraffic to Rush-Hour 40 Cars');
end;

procedure TMassTrafficForm.BtnLateNightClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
begin
  T := ActiveTraffic;
  if T = nil then Exit;
  T.Preset := mtpLateNightCruisers16;
  NotifyChange('Switch MassTraffic to Late-Night Cruisers');
end;

procedure TMassTrafficForm.BtnStep3SecClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
  I: Integer;
begin
  T := ActiveTraffic;
  if T = nil then Exit;
  for I := 1 to 15 do
    T.StepTraffic(0.20);
  NotifyChange('Step MassTraffic Simulation (+3.0s)');
end;

procedure TMassTrafficForm.BtnStep12SecCycleClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
  I: Integer;
begin
  T := ActiveTraffic;
  if T = nil then Exit;
  for I := 1 to 60 do
    T.StepTraffic(0.20);
  NotifyChange('Step MassTraffic Full Signal Cycle (+12.0s)');
end;

procedure TMassTrafficForm.BtnForceEWGreenClick(Sender: TObject);
var
  T: TCastleMassTrafficManager;
begin
  T := ActiveTraffic;
  if T = nil then Exit;
  T.ForceSignalPhase(tspEastWestGreen);
  NotifyChange('Force East-West Green Signal Phase');
end;

procedure TMassTrafficForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TMassTrafficHelper.GenerateMassTrafficReport(ActiveTraffic);
end;

procedure TMassTrafficForm.PaintCrossroadsMap(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, CX, CY, RoadHalfPx, PX, PY: Integer;
  T: TCastleMassTrafficManager;
  V: TTrafficVehicleState;

  function AspectToColor(const C: TTrafficLightColor): TColor;
  begin
    case C of
      tlcGreen: Result := RGBToColor(50, 235, 95);
      tlcYellow: Result := RGBToColor(250, 210, 50);
    else
      Result := RGBToColor(245, 65, 60);
    end;
  end;

begin
  Cv := FPaintCrossroads.Canvas;
  W := FPaintCrossroads.Width;
  H := FPaintCrossroads.Height;
  Cv.Brush.Color := RGBToColor(20, 25, 30);
  Cv.FillRect(0, 0, W, H);

  T := ActiveTraffic;
  if T = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn 8-Lane Crossroads" to inspect live IDM Traffic & Signals.');
    Exit;
  end;

  CX := W div 2;
  CY := H div 2;
  RoadHalfPx := 28;
  Cv.Brush.Color := RGBToColor(46, 50, 58);
  Cv.FillRect(CX - RoadHalfPx, 16, CX + RoadHalfPx, H - 16);
  Cv.FillRect(16, CY - RoadHalfPx, W - 16, CY + RoadHalfPx);

  { Signal stop bars }
  Cv.Pen.Width := 4;
  Cv.Pen.Color := AspectToColor(T.NorthSouthLightColor);
  Cv.Line(CX - RoadHalfPx, CY - RoadHalfPx - 4, CX + RoadHalfPx, CY - RoadHalfPx - 4);
  Cv.Line(CX - RoadHalfPx, CY + RoadHalfPx + 4, CX + RoadHalfPx, CY + RoadHalfPx + 4);

  Cv.Pen.Color := AspectToColor(T.EastWestLightColor);
  Cv.Line(CX - RoadHalfPx - 4, CY - RoadHalfPx, CX - RoadHalfPx - 4, CY + RoadHalfPx);
  Cv.Line(CX + RoadHalfPx + 4, CY - RoadHalfPx, CX + RoadHalfPx + 4, CY + RoadHalfPx);

  Cv.Pen.Width := 1;
  Cv.Pen.Color := clBlack;
  for I := 0 to T.VehicleStateCount - 1 do
  begin
    V := T.GetVehicleState(I);
    PX := Round(CX + (V.WorldOrLocalPos.X / 64.0) * (W * 0.44));
    PY := Round(CY + (V.WorldOrLocalPos.Z / 64.0) * (H * 0.44));
    Cv.Brush.Color := RGBToColor(Round(V.ColorRGB.X * 255), Round(V.ColorRGB.Y * 255), Round(V.ColorRGB.Z * 255));
    Cv.Rectangle(PX - 4, PY - 4, PX + 4, PY + 4);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 8, Format('XZ Crossroads | %s | Queued=%d | Overlaps=%d', [
    TrafficSignalPhaseToString(T.SignalPhase), T.Stats.StoppedQueueCount, T.Stats.RearEndOverlapCount]));
end;

end.
