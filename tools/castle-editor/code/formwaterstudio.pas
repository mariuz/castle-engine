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

{ Interactive Gerstner Ocean / River Water System, Shoreline Foam & Multi-Pontoon
  Buoyancy Studio (@link(TWaterStudioForm)) featuring 1-click ocean/river/lake
  spawners, a live X-Y Gerstner wave + 4-pontoon floating hull cross-section
  visualizer, step simulation controls, and Markdown report export (Phase 308). }
unit FormWaterStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Spin, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleUtils,
  CastleWaterSystem, ToolWaterStudio;

type
  TWaterStudioModifiedCallback = procedure(const AComment: String) of object;
  TWaterStudioRefreshViewportCallback = procedure of object;

  TWaterStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSelectedTransform: TCastleTransform;
    FSpawnPos: TVector3;
    FOnModified: TWaterStudioModifiedCallback;
    FOnRefreshViewport: TWaterStudioRefreshViewportCallback;

    FReport: TWaterStudioAuditReport;
    FSyncingUi: Boolean;

    LblHeader: TLabel;
    ListWater: TListBox;
    PaintWave: TPaintBox;
    SpinSizeX: TFloatSpinEdit;
    SpinSizeZ: TFloatSpinEdit;
    SpinAmplitude: TFloatSpinEdit;
    SpinWaveLength: TFloatSpinEdit;
    SpinSteepness: TFloatSpinEdit;
    SpinFlowX: TFloatSpinEdit;
    SpinFlowZ: TFloatSpinEdit;
    MemoDiag: TMemo;

    procedure BuildUi;
    function CurrentWater: TCastleWaterVolume;
    procedure RefreshAll;
    procedure PopulateInspector;
    procedure NotifyChanged(const AComment: String);

    procedure ListWaterClick(Sender: TObject);
    procedure BtnSpawnLakeClick(Sender: TObject);
    procedure BtnSpawnOceanClick(Sender: TObject);
    procedure BtnSpawnRiverClick(Sender: TObject);
    procedure BtnSpawnStormClick(Sender: TObject);
    procedure BtnSpawnSwampClick(Sender: TObject);
    procedure BtnSpawnCrateClick(Sender: TObject);
    procedure BtnAttachSelectedClick(Sender: TObject);
    procedure BtnStepSimClick(Sender: TObject);
    procedure BtnApplyParamsClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintWavePaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const ASelectedTransform: TCastleTransform;
      const ASpawnPos: TVector3;
      const AOnModified: TWaterStudioModifiedCallback;
      const AOnRefreshViewport: TWaterStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TWaterStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const ASelectedTransform: TCastleTransform;
  const ASpawnPos: TVector3;
  const AOnModified: TWaterStudioModifiedCallback;
  const AOnRefreshViewport: TWaterStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSelectedTransform := ASelectedTransform;
  FSpawnPos := ASpawnPos;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Gerstner Ocean / River Water System & 4-Pontoon Buoyancy Studio';
  Position := poScreenCenter;
  Width := 1080;
  Height := 700;

  BuildUi;
  RefreshAll;
end;

destructor TWaterStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TWaterStudioForm.BuildUi;
var
  TopBar, BottomBar, MainArea, LeftCol, CenterCol, RightCol, Row: TPanel;
  Btn: TButton;
  Lbl: TLabel;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 40;
  TopBar.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := TopBar;
  LblHeader.Left := 12;
  LblHeader.Top := 11;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Water Volumes: 0';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 44;
  BottomBar.BevelOuter := bvNone;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 12;
  Btn.Top := 8;
  Btn.Width := 190;
  Btn.Height := 28;
  Btn.Caption := 'Copy Markdown Report';
  Btn.OnClick := @BtnCopyMarkdownClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 212;
  Btn.Top := 8;
  Btn.Width := 210;
  Btn.Height := 28;
  Btn.Caption := 'Step Waves & Buoyancy (+0.1s)';
  Btn.OnClick := @BtnStepSimClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 432;
  Btn.Top := 8;
  Btn.Width := 210;
  Btn.Height := 28;
  Btn.Caption := '+ Spawn Floating Hull Crate';
  Btn.OnClick := @BtnSpawnCrateClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 652;
  Btn.Top := 8;
  Btn.Width := 220;
  Btn.Height := 28;
  Btn.Caption := 'Attach Buoyancy to Selected';
  Btn.Enabled := FSelectedTransform <> nil;
  Btn.OnClick := @BtnAttachSelectedClick;

  Btn := TButton.Create(Self);
  Btn.Parent := BottomBar;
  Btn.Left := 970;
  Btn.Top := 8;
  Btn.Width := 94;
  Btn.Height := 28;
  Btn.Anchors := [akTop, akRight];
  Btn.Caption := 'Close';
  Btn.OnClick := @BtnCloseClick;

  MainArea := TPanel.Create(Self);
  MainArea.Parent := Self;
  MainArea.Align := alClient;
  MainArea.BevelOuter := bvNone;

  { Left Column }
  LeftCol := TPanel.Create(Self);
  LeftCol.Parent := MainArea;
  LeftCol.Align := alLeft;
  LeftCol.Width := 220;
  LeftCol.BevelOuter := bvNone;
  LeftCol.BorderWidth := 6;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := LeftCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Water Bodies in Design';

  ListWater := TListBox.Create(Self);
  ListWater.Parent := LeftCol;
  ListWater.Align := alTop;
  ListWater.Height := 180;
  ListWater.OnClick := @ListWaterClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Calm Alpine Lake';
  Btn.OnClick := @BtnSpawnLakeClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Open Ocean Swell';
  Btn.OnClick := @BtnSpawnOceanClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Flowing River Current';
  Btn.OnClick := @BtnSpawnRiverClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Stormy High Seas';
  Btn.OnClick := @BtnSpawnStormClick;

  Btn := TButton.Create(Self);
  Btn.Parent := LeftCol;
  Btn.Align := alTop;
  Btn.Height := 28;
  Btn.Caption := '+ Viscous Toxic Swamp';
  Btn.OnClick := @BtnSpawnSwampClick;

  { Right Column }
  RightCol := TPanel.Create(Self);
  RightCol.Parent := MainArea;
  RightCol.Align := alRight;
  RightCol.Width := 300;
  RightCol.BevelOuter := bvNone;
  RightCol.BorderWidth := 6;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RightCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Gerstner & Flow Parameters';

  Row := TPanel.Create(Self);
  Row.Parent := RightCol;
  Row.Align := alTop;
  Row.Height := 204;
  Row.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self); Lbl.Parent := Row; Lbl.Left := 4; Lbl.Top := 8; Lbl.Caption := 'Size X / Z (m):';
  SpinSizeX := TFloatSpinEdit.Create(Self); SpinSizeX.Parent := Row; SpinSizeX.Left := 112; SpinSizeX.Top := 4; SpinSizeX.Width := 82; SpinSizeX.MinValue := 2; SpinSizeX.MaxValue := 2000; SpinSizeX.Increment := 2;
  SpinSizeZ := TFloatSpinEdit.Create(Self); SpinSizeZ.Parent := Row; SpinSizeZ.Left := 198; SpinSizeZ.Top := 4; SpinSizeZ.Width := 82; SpinSizeZ.MinValue := 2; SpinSizeZ.MaxValue := 2000; SpinSizeZ.Increment := 2;

  Lbl := TLabel.Create(Self); Lbl.Parent := Row; Lbl.Left := 4; Lbl.Top := 38; Lbl.Caption := 'Amp / Len (m):';
  SpinAmplitude := TFloatSpinEdit.Create(Self); SpinAmplitude.Parent := Row; SpinAmplitude.Left := 112; SpinAmplitude.Top := 34; SpinAmplitude.Width := 82; SpinAmplitude.MinValue := 0; SpinAmplitude.MaxValue := 20; SpinAmplitude.Increment := 0.05;
  SpinWaveLength := TFloatSpinEdit.Create(Self); SpinWaveLength.Parent := Row; SpinWaveLength.Left := 198; SpinWaveLength.Top := 34; SpinWaveLength.Width := 82; SpinWaveLength.MinValue := 0.5; SpinWaveLength.MaxValue := 200; SpinWaveLength.Increment := 1.0;

  Lbl := TLabel.Create(Self); Lbl.Parent := Row; Lbl.Left := 4; Lbl.Top := 68; Lbl.Caption := 'Steepness [0..1]:';
  SpinSteepness := TFloatSpinEdit.Create(Self); SpinSteepness.Parent := Row; SpinSteepness.Left := 112; SpinSteepness.Top := 64; SpinSteepness.Width := 82; SpinSteepness.MinValue := 0; SpinSteepness.MaxValue := 1; SpinSteepness.Increment := 0.05;

  Lbl := TLabel.Create(Self); Lbl.Parent := Row; Lbl.Left := 4; Lbl.Top := 98; Lbl.Caption := 'Flow X/Z (m/s):';
  SpinFlowX := TFloatSpinEdit.Create(Self); SpinFlowX.Parent := Row; SpinFlowX.Left := 112; SpinFlowX.Top := 94; SpinFlowX.Width := 82; SpinFlowX.MinValue := -30; SpinFlowX.MaxValue := 30; SpinFlowX.Increment := 0.25;
  SpinFlowZ := TFloatSpinEdit.Create(Self); SpinFlowZ.Parent := Row; SpinFlowZ.Left := 198; SpinFlowZ.Top := 94; SpinFlowZ.Width := 82; SpinFlowZ.MinValue := -30; SpinFlowZ.MaxValue := 30; SpinFlowZ.Increment := 0.25;

  Btn := TButton.Create(Self);
  Btn.Parent := Row;
  Btn.Left := 4;
  Btn.Top := 134;
  Btn.Width := 276;
  Btn.Height := 28;
  Btn.Caption := 'Apply Water Parameters';
  Btn.OnClick := @BtnApplyParamsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := RightCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Buoyancy & Audit Diagnostics';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := RightCol;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := true;
  MemoDiag.ScrollBars := ssVertical;

  { Center Column }
  CenterCol := TPanel.Create(Self);
  CenterCol.Parent := MainArea;
  CenterCol.Align := alClient;
  CenterCol.BevelOuter := bvNone;
  CenterCol.BorderWidth := 6;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := CenterCol;
  Lbl.Align := alTop;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Live X-Y Gerstner Wave Profile, Crest Foam & Floating 4-Pontoon Hulls';

  PaintWave := TPaintBox.Create(Self);
  PaintWave.Parent := CenterCol;
  PaintWave.Align := alClient;
  PaintWave.OnPaint := @PaintWavePaint;
end;

function TWaterStudioForm.CurrentWater: TCastleWaterVolume;
var
  Idx: Integer;
begin
  Result := nil;
  if FReport = nil then
    Exit;
  Idx := ListWater.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.WaterVolumes)) then
    Result := FReport.WaterVolumes[Idx];
end;

procedure TWaterStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TWaterStudioForm.RefreshAll;
var
  PrevIdx, I: Integer;
  W: TCastleWaterVolume;
begin
  PrevIdx := ListWater.ItemIndex;
  FreeAndNil(FReport);
  FReport := TWaterStudioHelper.ScanDesign(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Water Volumes: %d | Buoyant Hulls: %d (%d floating/submerged, %d dry) | Warnings: %d',
    [Length(FReport.WaterVolumes), Length(FReport.BuoyantHulls),
     FReport.SubmergedHullCount, FReport.DryHullCount, FReport.Warnings.Count]);

  ListWater.Items.BeginUpdate;
  try
    ListWater.Items.Clear;
    for I := 0 to High(FReport.WaterVolumes) do
    begin
      W := FReport.WaterVolumes[I];
      ListWater.Items.Add(Format('%s [%s, %.0fx%.0fm]',
        [W.Name, TCastleWaterVolume.PresetDisplayName(W.Preset), W.SizeX, W.SizeZ]));
    end;
    if ListWater.Items.Count > 0 then
      ListWater.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListWater.Items.Count - 1);
  finally
    ListWater.Items.EndUpdate;
  end;

  PopulateInspector;
  PaintWave.Invalidate;
end;

procedure TWaterStudioForm.PopulateInspector;
var
  W: TCastleWaterVolume;
  I: Integer;
begin
  FSyncingUi := true;
  try
    W := CurrentWater;
    if W <> nil then
    begin
      SpinSizeX.Value := W.SizeX;
      SpinSizeZ.Value := W.SizeZ;
      SpinAmplitude.Value := W.WaveAmplitude;
      SpinWaveLength.Value := W.WaveLength;
      SpinSteepness.Value := W.WaveSteepness;
      SpinFlowX.Value := W.FlowSpeedX;
      SpinFlowZ.Value := W.FlowSpeedZ;
    end;

    MemoDiag.Lines.BeginUpdate;
    try
      MemoDiag.Lines.Clear;
      for I := 0 to High(FReport.BuoyantHulls) do
        if FReport.BuoyantHulls[I].Parent <> nil then
          MemoDiag.Lines.Add(Format('%s: %d/4 pontoons submerged (sub=%.2f, Y=%.2fm)',
            [FReport.BuoyantHulls[I].Parent.Name,
             FReport.BuoyantHulls[I].SubmergedPontoonCount,
             FReport.BuoyantHulls[I].AverageSubmergence,
             FReport.BuoyantHulls[I].Parent.Translation.Y]));
      if FReport.Warnings.Count > 0 then
      begin
        MemoDiag.Lines.Add('');
        for I := 0 to FReport.Warnings.Count - 1 do
          MemoDiag.Lines.Add('! ' + FReport.Warnings[I]);
      end;
    finally
      MemoDiag.Lines.EndUpdate;
    end;
  finally
    FSyncingUi := false;
  end;
end;

procedure TWaterStudioForm.ListWaterClick(Sender: TObject);
begin
  PopulateInspector;
  PaintWave.Invalidate;
end;

procedure TWaterStudioForm.BtnSpawnLakeClick(Sender: TObject);
begin
  TWaterStudioHelper.SpawnWaterVolume(FDesignRoot, FDesignOwner, wbpCalmLake, FSpawnPos);
  NotifyChanged('Spawn Calm Lake Water Volume');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnSpawnOceanClick(Sender: TObject);
begin
  TWaterStudioHelper.SpawnWaterVolume(FDesignRoot, FDesignOwner, wbpOpenOceanSwell, FSpawnPos);
  NotifyChanged('Spawn Open Ocean Water Volume');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnSpawnRiverClick(Sender: TObject);
begin
  TWaterStudioHelper.SpawnWaterVolume(FDesignRoot, FDesignOwner, wbpFlowingRiver, FSpawnPos);
  NotifyChanged('Spawn Flowing River Water Volume');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnSpawnStormClick(Sender: TObject);
begin
  TWaterStudioHelper.SpawnWaterVolume(FDesignRoot, FDesignOwner, wbpStormyHighSeas, FSpawnPos);
  NotifyChanged('Spawn Stormy High Seas Water Volume');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnSpawnSwampClick(Sender: TObject);
begin
  TWaterStudioHelper.SpawnWaterVolume(FDesignRoot, FDesignOwner, wbpToxicSwamp, FSpawnPos);
  NotifyChanged('Spawn Toxic Swamp Water Volume');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnSpawnCrateClick(Sender: TObject);
var
  W: TCastleWaterVolume;
  CratePos: TVector3;
begin
  W := CurrentWater;
  if W = nil then
    W := TWaterStudioHelper.SpawnWaterVolume(FDesignRoot, FDesignOwner, wbpOpenOceanSwell, FSpawnPos);
  if W <> nil then
    CratePos := W.Translation + Vector3(0.0, 0.9, 0.0)
  else
    CratePos := FSpawnPos + Vector3(0.0, 0.9, 0.0);
  TWaterStudioHelper.SpawnFloatingCrate(FDesignRoot, FDesignOwner, W, CratePos);
  NotifyChanged('Spawn Floating Buoyancy Hull');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnAttachSelectedClick(Sender: TObject);
begin
  if FSelectedTransform = nil then
    Exit;
  TWaterStudioHelper.AttachBuoyancyToTransform(FSelectedTransform, FDesignOwner, CurrentWater);
  NotifyChanged('Attach 4-Pontoon Buoyancy Behavior');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnStepSimClick(Sender: TObject);
begin
  TWaterStudioHelper.StepAllWaterAndBuoyancy(FDesignRoot, FDesignOwner, 0.1);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TWaterStudioForm.BtnApplyParamsClick(Sender: TObject);
var
  W: TCastleWaterVolume;
begin
  if FSyncingUi then
    Exit;
  W := CurrentWater;
  if W = nil then
    Exit;
  W.Preset := wbpCustom;
  W.SizeX := SpinSizeX.Value;
  W.SizeZ := SpinSizeZ.Value;
  W.WaveAmplitude := SpinAmplitude.Value;
  W.WaveLength := SpinWaveLength.Value;
  W.WaveSteepness := SpinSteepness.Value;
  W.FlowSpeedX := SpinFlowX.Value;
  W.FlowSpeedZ := SpinFlowZ.Value;
  NotifyChanged('Update Gerstner Water Volume Parameters');
  RefreshAll;
end;

procedure TWaterStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TWaterStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TWaterStudioForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TWaterStudioForm.PaintWavePaint(Sender: TObject);
var
  C: TCanvas;
  W: TCastleWaterVolume;
  CW, CH, MidY, I, Steps, PX, PY, PrevX, PrevY: Integer;
  SpanX, MetersPerPx, LX, Foam: Single;
  SurfPos, SurfNorm: TVector3;
  B: TCastleBuoyancyBehavior;
begin
  C := PaintWave.Canvas;
  CW := Max(1, PaintWave.Width);
  CH := Max(1, PaintWave.Height);
  C.Brush.Color := RGBToColor(18, 24, 36);
  C.FillRect(0, 0, CW, CH);

  W := CurrentWater;
  if W = nil then
  begin
    C.Font.Color := RGBToColor(190, 205, 225);
    C.Brush.Style := bsClear;
    C.TextOut(20, 20, 'Click "+ Open Ocean Swell" or "+ Flowing River Current" to create a Gerstner water volume.');
    Exit;
  end;

  MidY := CH div 2;
  SpanX := Max(4.0, W.SizeX);
  MetersPerPx := SpanX / CW;

  { Draw Gerstner water column fill & crest foam }
  Steps := Max(32, CW div 4);
  PrevX := 0;
  PrevY := MidY;
  for I := 0 to Steps do
  begin
    PX := Round((I / Steps) * CW);
    LX := -SpanX * 0.5 + (I / Steps) * SpanX;
    W.SampleSurfaceLocal(LX, 0.0, W.ElapsedTime, SurfPos, SurfNorm, Foam);
    PY := MidY - Round(SurfPos.Y * 42.0);

    C.Pen.Color := RGBToColor(24, 82, 128);
    C.Pen.Width := 3;
    C.Line(PX, PY, PX, CH);

    if I > 0 then
    begin
      if Foam > 0.25 then
        C.Pen.Color := RGBToColor(235, 248, 255)
      else
        C.Pen.Color := RGBToColor(68, 198, 232);
      C.Pen.Width := 3;
      C.Line(PrevX, PrevY, PX, PY);
    end;
    PrevX := PX;
    PrevY := PY;
  end;

  { Draw floating buoyant hulls }
  for I := 0 to High(FReport.BuoyantHulls) do
  begin
    B := FReport.BuoyantHulls[I];
    if B.Parent <> nil then
    begin
      PX := Round(((B.Parent.Translation.X - W.Translation.X) + SpanX * 0.5) / Max(0.001, MetersPerPx));
      PY := MidY - Round((B.Parent.Translation.Y - W.Translation.Y) * 42.0);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(214, 148, 68);
      C.Pen.Color := RGBToColor(255, 226, 128);
      C.Pen.Width := 2;
      C.Rectangle(PX - 18, PY - 12, PX + 18, PY + 12);
    end;
  end;
end;

end.
