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

{ Interactive Volumetric Exponential Height Fog, Henyey-Greenstein God-Ray
  Light Shafts & Box-Parallax Reflection Probe Studio (@link(TVolumetricStudioForm))
  featuring an Altitude Fog Density Curve + Polar Henyey-Greenstein Phase Lobe
  visualizer (Phase 324). }
unit FormVolumetricStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleColors, CastleVolumetrics, ToolVolumetricStudio;

type
  TVolumetricStudioModifiedCallback = procedure(const AComment: String) of object;
  TVolumetricStudioRefreshViewportCallback = procedure of object;

  TVolumetricStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TVolumetricStudioModifiedCallback;
    FOnRefreshViewport: TVolumetricStudioRefreshViewportCallback;

    FAtms: TVolumetricAtmosphereArray;
    FProbes: TReflectionProbeArray;
    FReport: TVolumetricAuditReport;

    LblHeader: TLabel;
    ListItems: TListBox;
    PaintVol: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveAtm: TCastleVolumetricAtmosphere;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnPresetValleyMistClick(Sender: TObject);
    procedure BtnPresetGodRaysClick(Sender: TObject);
    procedure BtnPresetNeonHazeClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintVolPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TVolumetricStudioModifiedCallback;
      const AOnRefreshViewport: TVolumetricStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TVolumetricStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TVolumetricStudioModifiedCallback;
  const AOnRefreshViewport: TVolumetricStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Volumetric Height Fog, Anisotropic God-Rays & Box-Parallax Reflection Probe Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TVolumetricStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TVolumetricStudioForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Volumetric Fog & Reflection Probes: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn Volumetric Fog + 2 Probes', 4, 2, 238, @BtnSpawnDemoClick);
  MakeBtn(RowTop, 'Preset: Valley Mist', 248, 2, 150, @BtnPresetValleyMistClick);
  MakeBtn(RowTop, 'Preset: Golden God-Rays', 404, 2, 178, @BtnPresetGodRaysClick);
  MakeBtn(RowTop, 'Preset: Cyberpunk Haze', 588, 2, 175, @BtnPresetNeonHazeClick);
  MakeBtn(RowTop, 'Copy Markdown Report', 770, 2, 170, @BtnCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Caption := 'Close';
  BtnClose.Width := 110;
  BtnClose.Height := 28;
  BtnClose.Top := 7;
  BtnClose.Left := Width - 130;
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.OnClick := @BtnCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Volumetric & Probe Nodes:';

  ListItems := TListBox.Create(Self);
  ListItems.Parent := PanelLeft;
  ListItems.SetBounds(10, 26, 320, 230);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 264, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Transmittance, Probe Blend & QA:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 286, 320, 285);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintVol := TPaintBox.Create(Self);
  PaintVol.Parent := PanelCenter;
  PaintVol.Align := alClient;
  PaintVol.OnPaint := @PaintVolPaint;
end;

function TVolumetricStudioForm.ActiveAtm: TCastleVolumetricAtmosphere;
begin
  if Length(FAtms) > 0 then Result := FAtms[0] else Result := nil;
end;

procedure TVolumetricStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TVolumetricStudioForm.RefreshAll;
var
  I: Integer;
  A: TCastleVolumetricAtmosphere;
  DomP: TCastleReflectionProbe;
  BlendCol: TCastleColorRGB;
  Tau0, Tau30, T0, T30: Single;
begin
  TVolumetricStudioHelper.ScanVolumetrics(FDesignRoot, FDesignOwner, FAtms, FProbes);
  FreeAndNil(FReport);
  FReport := TVolumetricStudioHelper.AuditVolumetrics(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Volumetric Atmospheres: %d  |  Local Reflection Probes: %d  |  QA Warnings: %d',
    [FReport.AtmosphereCount, FReport.ProbeCount, FReport.Warnings.Count]);

  ListItems.Items.BeginUpdate;
  try
    ListItems.Items.Clear;
    for I := 0 to High(FAtms) do
      ListItems.Items.Add(FAtms[I].Name + '  ' + FAtms[I].VolumetricSummaryBadge);
    for I := 0 to High(FProbes) do
      ListItems.Items.Add(FProbes[I].Name + '  ' + FProbes[I].ProbeSummaryBadge);
  finally
    ListItems.Items.EndUpdate;
  end;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    A := ActiveAtm;
    if A <> nil then
    begin
      T0 := A.EvaluateSegmentTransmittance(Vector3(0, 0, 0), Vector3(0, 0, -50), Tau0);
      T30 := A.EvaluateSegmentTransmittance(Vector3(0, 30, 0), Vector3(0, 30, -50), Tau30);
      MemoDiag.Lines.Add(Format('50m Valley Transmittance (Y=0):  %.1f%% (tau=%.2f)', [T0 * 100.0, Tau0]));
      MemoDiag.Lines.Add(Format('50m Peak Transmittance   (Y=30): %.1f%% (tau=%.2f)', [T30 * 100.0, Tau30]));
    end;
    if Length(FProbes) > 0 then
    begin
      TVolumetricStudioHelper.BlendReflectionProbesAtPoint(
        FDesignRoot, FDesignOwner, TVector3.Zero, DomP, BlendCol);
      if DomP <> nil then
        MemoDiag.Lines.Add(Format('Origin Dominant Probe: %s (Prio %d)', [DomP.Name, DomP.Priority]));
    end;
    MemoDiag.Lines.Add('');
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] Volumetric height fog & box-parallax probes healthy.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintVol.Invalidate;
end;

procedure TVolumetricStudioForm.BtnSpawnDemoClick(Sender: TObject);
var
  A: TCastleVolumetricAtmosphere;
  P1, P2: TCastleReflectionProbe;
begin
  TVolumetricStudioHelper.SpawnVolumetricValleyAndProbesDemo(
    FDesignRoot, FDesignOwner, A, P1, P2);
  NotifyChanged('Spawn Volumetric Height Fog + Box-Parallax Probes');
end;

procedure TVolumetricStudioForm.BtnPresetValleyMistClick(Sender: TObject);
var A: TCastleVolumetricAtmosphere;
begin
  A := ActiveAtm; if A = nil then Exit;
  A.ApplyPreset(vpMorningValleyMist);
  NotifyChanged('Volumetric Preset: Morning Valley Mist');
end;

procedure TVolumetricStudioForm.BtnPresetGodRaysClick(Sender: TObject);
var A: TCastleVolumetricAtmosphere;
begin
  A := ActiveAtm; if A = nil then Exit;
  A.ApplyPreset(vpGoldenHourGodRays);
  NotifyChanged('Volumetric Preset: Golden Hour God-Rays');
end;

procedure TVolumetricStudioForm.BtnPresetNeonHazeClick(Sender: TObject);
var A: TCastleVolumetricAtmosphere;
begin
  A := ActiveAtm; if A = nil then Exit;
  A.ApplyPreset(vpCyberpunkNeonHaze);
  NotifyChanged('Volumetric Preset: Cyberpunk Neon Haze');
end;

procedure TVolumetricStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TVolumetricStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TVolumetricStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TVolumetricStudioForm.PaintVolPaint(Sender: TObject);
var
  C: TCanvas;
  A: TCastleVolumetricAtmosphere;
  W, H, MidX, PlotL, PlotR, PlotT, PlotB, I, Px, Py, PrevX, PrevY, Cx, Cy: Integer;
  AltY, DensNorm, Ang, PhaseVal, MaxPhase, RadPx: Single;
begin
  C := PaintVol.Canvas;
  W := Max(200, PaintVol.Width);
  H := Max(200, PaintVol.Height);
  C.Brush.Color := RGBToColor(20, 24, 31);
  C.FillRect(0, 0, W, H);

  A := ActiveAtm;
  if A = nil then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn Volumetric Fog + 2 Probes" to inspect altitude density & Henyey-Greenstein phase lobe.');
    Exit;
  end;

  MidX := W div 2;

  { Left panel: Altitude Y vs Exponential Fog Density }
  PlotL := 28; PlotR := MidX - 20; PlotT := 48; PlotB := H - 40;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(PlotL, 14, 'Altitude Y (0..40m) vs. Exponential Fog Density');
  C.Font.Style := [];
  C.Pen.Color := RGBToColor(64, 76, 94);
  C.Brush.Color := RGBToColor(28, 33, 42);
  C.Rectangle(PlotL, PlotT, PlotR, PlotB);

  PrevX := PlotL; PrevY := PlotB;
  C.Pen.Color := RGBToColor(92, 198, 252);
  C.Pen.Width := 2;
  for I := 0 to 50 do
  begin
    AltY := (I / 50.0) * 40.0;
    DensNorm := Clamped(A.DensityAtAltitude(AltY) / Max(0.001, A.BaseDensity), 0.0, 1.0);
    Px := PlotL + Round(DensNorm * (PlotR - PlotL - 12));
    Py := PlotB - Round((I / 50.0) * (PlotB - PlotT));
    if I > 0 then C.Line(PrevX, PrevY, Px, Py);
    PrevX := Px; PrevY := Py;
  end;
  C.Pen.Width := 1;

  { Right panel: Polar Henyey-Greenstein Scattering Phase Lobe }
  Cx := MidX + (W - MidX) div 2;
  Cy := H div 2 + 12;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.Brush.Style := bsClear;
  C.TextOut(MidX + 20, 14, Format('Henyey-Greenstein Anisotropic Lobe (g = %.2f)',
    [A.ScatteringAnisotropyG]));
  C.Font.Style := [];

  MaxPhase := Max(0.05, EvaluateHenyeyGreensteinPhase(1.0, Abs(A.ScatteringAnisotropyG)));
  C.Pen.Color := RGBToColor(252, 192, 72);
  C.Pen.Width := 2;
  PrevX := Cx; PrevY := Cy;
  for I := 0 to 72 do
  begin
    Ang := (2.0 * Pi * I) / 72.0;
    PhaseVal := EvaluateHenyeyGreensteinPhase(Cos(Ang), A.ScatteringAnisotropyG);
    RadPx := 18.0 + Sqrt(Clamped(PhaseVal / MaxPhase, 0.0, 1.0)) * 135.0;
    Px := Cx + Round(Cos(Ang) * RadPx);
    Py := Cy - Round(Sin(Ang) * RadPx);
    if I > 0 then C.Line(PrevX, PrevY, Px, Py);
    PrevX := Px; PrevY := Py;
  end;
  C.Pen.Width := 1;
end;

end.
