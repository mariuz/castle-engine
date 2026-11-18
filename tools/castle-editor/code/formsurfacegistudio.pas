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

{ Visual Studio dialog for Lumen-Style Surface Cache SH2 GI Probes (Phase 357). }
unit FormSurfaceGiStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleViewport, CastleSurfaceGi, ToolSurfaceGi;

type
  TSurfaceGiModifiedCallback = procedure(const UndoComment: String) of object;
  TSurfaceGiRefreshCallback = procedure of object;

  TSurfaceGiStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSurfaceGiModifiedCallback;
    FOnRefresh: TSurfaceGiRefreshCallback;
    FPaintProbes: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveGrid: TCastleSurfaceGiGrid;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnAndBakeClick(Sender: TObject);
    procedure BtnRebakeClick(Sender: TObject);
    procedure BtnPresetCornellClick(Sender: TObject);
    procedure BtnPresetCourtyardClick(Sender: TObject);
    procedure BtnBoostBounceClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintProbeMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSurfaceGiModifiedCallback;
      const AOnRefresh: TSurfaceGiRefreshCallback);
  end;

implementation

constructor TSurfaceGiStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSurfaceGiModifiedCallback;
  const AOnRefresh: TSurfaceGiRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Lumen Surface Cache SH2 GI Probes & Sky-Occlusion Baker Studio (Phase 357)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TSurfaceGiStudioForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ Lumen Irradiance Parity — Fibonacci WorldRay Sky-Occlusion, Colored Wall Bounce Bleeding & Trilinear SH2 Sampling';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Cornell Courtyard & Bake SH2 GI', @BtnSpawnAndBakeClick);
  MakeBtn(Row1, 'Bake WorldRay SH2 Probes Now', @BtnRebakeClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Preset: Cornell Room (4x2x4)', @BtnPresetCornellClick);
  MakeBtn(Row2, 'Preset: Courtyard (5x2x5)', @BtnPresetCourtyardClick);
  MakeBtn(Row2, 'Boost Bounce Intensity (2.4x)', @BtnBoostBounceClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintProbes := TPaintBox.Create(Self);
  FPaintProbes.Parent := BodyPanel;
  FPaintProbes.Align := alLeft;
  FPaintProbes.Width := 520;
  FPaintProbes.OnPaint := @PaintProbeMap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TSurfaceGiStudioForm.ActiveGrid: TCastleSurfaceGiGrid;
begin
  Result := TSurfaceGiHelper.FindGiGridInHierarchy(FDesignRoot);
end;

procedure TSurfaceGiStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TSurfaceGiStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TSurfaceGiHelper.GenerateSurfaceGiReport(ActiveGrid);
  FPaintProbes.Invalidate;
end;

procedure TSurfaceGiStudioForm.BtnSpawnAndBakeClick(Sender: TObject);
var
  G: TCastleSurfaceGiGrid;
begin
  if TSurfaceGiHelper.SpawnCornellBounceAndRoofDemo(FDesignRoot, FDesignOwner, G) then
    NotifyChange('Spawn Cornell Courtyard & Bake SH2 GI');
end;

procedure TSurfaceGiStudioForm.BtnRebakeClick(Sender: TObject);
var
  G: TCastleSurfaceGiGrid;
  Vp: TCastleViewport;
begin
  G := ActiveGrid;
  Vp := TSurfaceGiHelper.FindViewport(FDesignRoot);
  if (G = nil) or (Vp = nil) then Exit;
  G.BakeIrradianceProbes(Vp.Items);
  NotifyChange('Re-bake Surface Cache SH2 GI Probes');
end;

procedure TSurfaceGiStudioForm.BtnPresetCornellClick(Sender: TObject);
var
  G: TCastleSurfaceGiGrid;
  Vp: TCastleViewport;
begin
  G := ActiveGrid;
  Vp := TSurfaceGiHelper.FindViewport(FDesignRoot);
  if G = nil then Exit;
  G.Preset := sgpCornellColorBleedRoom;
  if Vp <> nil then G.BakeIrradianceProbes(Vp.Items);
  NotifyChange('Switch GI Grid to Cornell Room');
end;

procedure TSurfaceGiStudioForm.BtnPresetCourtyardClick(Sender: TObject);
var
  G: TCastleSurfaceGiGrid;
  Vp: TCastleViewport;
begin
  G := ActiveGrid;
  Vp := TSurfaceGiHelper.FindViewport(FDesignRoot);
  if G = nil then Exit;
  G.Preset := sgpIndoorOutdoorCourtyard;
  if Vp <> nil then G.BakeIrradianceProbes(Vp.Items);
  NotifyChange('Switch GI Grid to Indoor/Outdoor Courtyard');
end;

procedure TSurfaceGiStudioForm.BtnBoostBounceClick(Sender: TObject);
var
  G: TCastleSurfaceGiGrid;
  Vp: TCastleViewport;
begin
  G := ActiveGrid;
  Vp := TSurfaceGiHelper.FindViewport(FDesignRoot);
  if G = nil then Exit;
  G.BounceIntensity := 2.4;
  if Vp <> nil then G.BakeIrradianceProbes(Vp.Items);
  NotifyChange('Boost Indirect Bounce Intensity to 2.4x');
end;

procedure TSurfaceGiStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TSurfaceGiHelper.GenerateSurfaceGiReport(ActiveGrid);
end;

procedure TSurfaceGiStudioForm.PaintProbeMap(Sender: TObject);
var
  Cv: TCanvas;
  W, H, IX, IZ, PX, PY: Integer;
  G: TCastleSurfaceGiGrid;
  P: TSurfaceGiProbe;
begin
  Cv := FPaintProbes.Canvas;
  W := FPaintProbes.Width;
  H := FPaintProbes.Height;
  Cv.Brush.Color := RGBToColor(20, 24, 32);
  Cv.FillRect(0, 0, W, H);

  G := ActiveGrid;
  if G = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Cornell Courtyard & Bake SH2 GI" to inspect XZ Probe Map.');
    Exit;
  end;

  for IZ := 0 to G.GridZ - 1 do
    for IX := 0 to G.GridX - 1 do
    begin
      P := G.GetProbe3D(IX, 0, IZ);
      PX := Round(58 + (IX / Max(1, G.GridX - 1)) * (W - 116));
      PY := Round(58 + (IZ / Max(1, G.GridZ - 1)) * (H - 116));
      Cv.Brush.Color := RGBToColor(
        EnsureRange(Round(P.SH0_AmbientRGB.X * 230), 18, 255),
        EnsureRange(Round(P.SH0_AmbientRGB.Y * 230), 18, 255),
        EnsureRange(Round(P.SH0_AmbientRGB.Z * 230), 18, 255));
      Cv.Pen.Color := RGBToColor(220, 230, 245);
      Cv.Ellipse(PX - 18, PY - 18, PX + 18, PY + 18);
      Cv.Brush.Style := bsClear;
      Cv.Font.Color := clWhite;
      Cv.TextOut(PX - 14, PY + 20, Format('%.0f%%', [P.SkyVisibility * 100.0]));
    end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(14, 10, Format('XZ Lower-Layer SH2 Probe Heatmap (Sky Vis %%) | Mean Sky=%.1f%%', [
    G.BakeStats.MeanSkyVisibility * 100.0]));
end;

end.
