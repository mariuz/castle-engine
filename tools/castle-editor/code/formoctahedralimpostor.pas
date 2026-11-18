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

{ Visual studio dialog for Octahedral Billboard Impostor Atlas Mapping (Phase 374). }
unit FormOctahedralImpostor;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleOctahedralImpostor, ToolOctahedralImpostor;

type
  TOctahedralImpostorModifiedCallback = procedure(const UndoComment: String) of object;
  TOctahedralImpostorRefreshCallback = procedure of object;

  TOctahedralImpostorForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TOctahedralImpostorModifiedCallback;
    FOnRefresh: TOctahedralImpostorRefreshCallback;
    FLblSummary: TLabel;
    FPaintAtlas: TPaintBox;
    FMemoReport: TMemo;
    FOrbitAngleDeg: Single;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged;
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnPinePresetClick(Sender: TObject);
    procedure BtnCliffPresetClick(Sender: TObject);
    procedure BtnOrbitObserverClick(Sender: TObject);
    procedure BtnNearObserverClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintAtlasGrid(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TOctahedralImpostorModifiedCallback;
      const AOnRefresh: TOctahedralImpostorRefreshCallback);
  end;

implementation

constructor TOctahedralImpostorForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TOctahedralImpostorModifiedCallback;
  const AOnRefresh: TOctahedralImpostorRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FOrbitAngleDeg := 32.0;
  Caption := 'Octahedral Billboard Impostor Atlas & 3-View Blend Studio (Phase 374)';
  Width := 1020;
  Height := 650;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TOctahedralImpostorForm.BuildUi;
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

  MakeBtn(Row1, '+ Spawn 8x8 Pine Canopy Impostor', @BtnSpawnDemoClick);
  MakeBtn(Row1, '8x8 Pine Preset (45m)', @BtnPinePresetClick);
  MakeBtn(Row1, '12x12 Cliffspire Preset (80m)', @BtnCliffPresetClick);
  MakeBtn(Row1, 'Orbit Far Camera (+35 deg)', @BtnOrbitObserverClick);
  MakeBtn(Row1, 'Move Camera Close (15m Mesh)', @BtnNearObserverClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintAtlas := TPaintBox.Create(Self);
  FPaintAtlas.Parent := BodyPanel;
  FPaintAtlas.Align := alLeft;
  FPaintAtlas.Width := 460;
  FPaintAtlas.OnPaint := @PaintAtlasGrid;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TOctahedralImpostorForm.NotifyChanged;
begin
  if Assigned(FOnModified) then FOnModified('Octahedral Impostor Studio');
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TOctahedralImpostorForm.RefreshView;
var
  Imp: TCastleOctahedralImpostor;
begin
  Imp := TOctahedralImpostorHelper.FindImpostorInHierarchy(FDesignRoot);
  if Imp = nil then
    FLblSummary.Caption := 'No TCastleOctahedralImpostor in scene — click "+ Spawn 8x8 Pine Canopy Impostor".'
  else
    FLblSummary.Caption := Format('%s %s | UV=(%.3f, %.3f) | Blend: #%d(%.2f) + #%d(%.2f) + #%d(%.2f)', [
      Imp.Name, Imp.ImpostorSummaryBadge, Imp.LastSample.Uv.X, Imp.LastSample.Uv.Y,
      Imp.LastSample.TileIndex0, Imp.LastSample.Weight0,
      Imp.LastSample.TileIndex1, Imp.LastSample.Weight1,
      Imp.LastSample.TileIndex2, Imp.LastSample.Weight2]);
  FMemoReport.Lines.Text := TOctahedralImpostorHelper.GenerateImpostorReport(Imp);
  FPaintAtlas.Invalidate;
end;

procedure TOctahedralImpostorForm.BtnSpawnDemoClick(Sender: TObject);
var
  Imp: TCastleOctahedralImpostor;
begin
  if TOctahedralImpostorHelper.SpawnPineCanopyImpostorDemo(FDesignRoot, FDesignOwner, Imp) then
    NotifyChanged;
end;

procedure TOctahedralImpostorForm.BtnPinePresetClick(Sender: TObject);
var
  Imp: TCastleOctahedralImpostor;
begin
  Imp := TOctahedralImpostorHelper.FindImpostorInHierarchy(FDesignRoot);
  if Imp = nil then Exit;
  Imp.Preset := oipPineCanopy8x8;
  Imp.EvaluateCameraObserver(Vector3(40.0, 20.0, 50.0));
  NotifyChanged;
end;

procedure TOctahedralImpostorForm.BtnCliffPresetClick(Sender: TObject);
var
  Imp: TCastleOctahedralImpostor;
begin
  Imp := TOctahedralImpostorHelper.FindImpostorInHierarchy(FDesignRoot);
  if Imp = nil then Exit;
  Imp.Preset := oipCliffspire12x12;
  Imp.EvaluateCameraObserver(Vector3(75.0, 35.0, 85.0));
  NotifyChanged;
end;

procedure TOctahedralImpostorForm.BtnOrbitObserverClick(Sender: TObject);
var
  Imp: TCastleOctahedralImpostor;
  Rad, Dist: Single;
begin
  Imp := TOctahedralImpostorHelper.FindImpostorInHierarchy(FDesignRoot);
  if Imp = nil then Exit;
  FOrbitAngleDeg := FOrbitAngleDeg + 35.0;
  Rad := DegToRad(FOrbitAngleDeg);
  Dist := Max(Imp.SwitchDistanceMeters + 25.0, 70.0);
  Imp.EvaluateCameraObserver(Imp.Translation + Vector3(Cos(Rad) * Dist, Dist * 0.42, Sin(Rad) * Dist));
  NotifyChanged;
end;

procedure TOctahedralImpostorForm.BtnNearObserverClick(Sender: TObject);
var
  Imp: TCastleOctahedralImpostor;
begin
  Imp := TOctahedralImpostorHelper.FindImpostorInHierarchy(FDesignRoot);
  if Imp = nil then Exit;
  Imp.EvaluateCameraObserver(Imp.Translation + Vector3(0.0, 6.0, 15.0));
  NotifyChanged;
end;

procedure TOctahedralImpostorForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TOctahedralImpostorForm.PaintAtlasGrid(Sender: TObject);
var
  C: TCanvas;
  Imp: TCastleOctahedralImpostor;
  N, X, Y, Pad, Side, X0, Y0, X1, Y1, Px, Py: Integer;
  S: TOctahedralBlendSample;
  W: Single;
begin
  C := FPaintAtlas.Canvas;
  C.Brush.Color := RGBToColor(18, 22, 28);
  C.FillRect(0, 0, FPaintAtlas.Width, FPaintAtlas.Height);

  Imp := TOctahedralImpostorHelper.FindImpostorInHierarchy(FDesignRoot);
  if Imp = nil then Exit;

  N := Max(2, Imp.AtlasGridSize);
  S := Imp.LastSample;
  Pad := 24;
  Side := Min(FPaintAtlas.Width, FPaintAtlas.Height) - Pad * 2;
  if Side < 60 then Exit;

  for Y := 0 to N - 1 do
    for X := 0 to N - 1 do
    begin
      X0 := Pad + Round((X / N) * Side);
      Y0 := Pad + Round((Y / N) * Side);
      X1 := Pad + Round(((X + 1) / N) * Side);
      Y1 := Pad + Round(((Y + 1) / N) * Side);
      W := 0.0;
      if (X = S.Cell0X) and (Y = S.Cell0Y) then W := S.Weight0
      else if (X = S.Cell1X) and (Y = S.Cell1Y) then W := S.Weight1
      else if (X = S.Cell2X) and (Y = S.Cell2Y) then W := S.Weight2;

      if W > 0.001 then
        C.Brush.Color := RGBToColor(Round(40 + 180 * W), Round(90 + 150 * W), 80)
      else
        C.Brush.Color := RGBToColor(30, 38, 48);
      C.Pen.Color := RGBToColor(68, 84, 102);
      C.Rectangle(X0, Y0, X1, Y1);
    end;

  Px := Pad + Round(S.Uv.X * Side);
  Py := Pad + Round(S.Uv.Y * Side);
  C.Pen.Color := RGBToColor(255, 220, 70);
  C.Brush.Color := RGBToColor(255, 180, 40);
  C.Ellipse(Px - 5, Py - 5, Px + 5, Py + 5);
end;

end.
