{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Visual Studio dialog for Diegetic 3D World-Space Hologram, Offscreen Edge
  Clamping & WorldRay X-Ray Occluded Waypoint Studio (Phase 390). }
unit FormWorldWaypoint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleWorldWaypoint, ToolWorldWaypoint;

type
  TWorldWaypointModifiedCallback = procedure(const UndoComment: String) of object;
  TWorldWaypointRefreshCallback = procedure of object;

  TWorldWaypointForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TWorldWaypointModifiedCallback;
    FOnRefresh: TWorldWaypointRefreshCallback;
    FLblSummary: TLabel;
    FPaintHud: TPaintBox;
    FMemoReport: TMemo;
    function FindViewport: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnTestOccludedClick(Sender: TObject);
    procedure BtnTestBehindCamClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintHudScreen(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TWorldWaypointModifiedCallback;
      const AOnRefresh: TWorldWaypointRefreshCallback);
  end;

implementation

constructor TWorldWaypointForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TWorldWaypointModifiedCallback;
  const AOnRefresh: TWorldWaypointRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Diegetic 3D World Waypoint, Offscreen Edge & X-Ray Occlusion Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TWorldWaypointForm.FindViewport: TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if FDesignRoot = nil then Exit;
  if FDesignRoot is TCastleViewport then Exit(TCastleViewport(FDesignRoot));
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]));
end;

procedure TWorldWaypointForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnOcc, BtnBehind, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 42;
  PnlTop.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := PnlTop;
  FLblSummary.Left := 12;
  FLblSummary.Top := 12;
  FLblSummary.Caption := 'Ready.';

  PnlButtons := TPanel.Create(Self);
  PnlButtons.Parent := Self;
  PnlButtons.Align := alTop;
  PnlButtons.Height := 46;
  PnlButtons.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := PnlButtons;
  BtnSpawn.SetBounds(10, 8, 195, 30);
  BtnSpawn.Caption := '+ Spawn Objective + Wall';
  BtnSpawn.OnClick := @BtnSpawnDemoClick;

  BtnOcc := TButton.Create(Self);
  BtnOcc.Parent := PnlButtons;
  BtnOcc.SetBounds(211, 8, 190, 30);
  BtnOcc.Caption := 'Test X-Ray Wall Occlusion';
  BtnOcc.OnClick := @BtnTestOccludedClick;

  BtnBehind := TButton.Create(Self);
  BtnBehind.Parent := PnlButtons;
  BtnBehind.SetBounds(407, 8, 195, 30);
  BtnBehind.Caption := 'Turn Camera Away (Behind)';
  BtnBehind.OnClick := @BtnTestBehindCamClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(608, 8, 130, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintHud := TPaintBox.Create(Self);
  FPaintHud.Parent := Self;
  FPaintHud.Align := alTop;
  FPaintHud.Height := 200;
  FPaintHud.OnPaint := @PaintHudScreen;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Align := alBottom;
  BtnClose.Height := 34;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;
end;

procedure TWorldWaypointForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TWorldWaypointForm.RefreshView;
var
  W: TCastleWorldWaypoint;
begin
  W := TWorldWaypointHelper.FindFirstWaypoint(FDesignRoot);
  if W = nil then
    FLblSummary.Caption := 'No TCastleWorldWaypoint in scene. Click "+ Spawn Objective + Wall".'
  else
    FLblSummary.Caption := W.WaypointSummaryBadge;
  FMemoReport.Lines.Text := TWorldWaypointHelper.GenerateMarkdownReport(W);
  FPaintHud.Invalidate;
end;

procedure TWorldWaypointForm.BtnSpawnDemoClick(Sender: TObject);
var
  W: TCastleWorldWaypoint;
begin
  if TWorldWaypointHelper.SpawnCourtyardWaypointDemo(FDesignRoot, FDesignOwner, W) then
    NotifyChanged('Spawn Courtyard Waypoint & Occluder Wall');
end;

procedure TWorldWaypointForm.BtnTestOccludedClick(Sender: TObject);
var
  W: TCastleWorldWaypoint;
  VP: TCastleViewport;
begin
  W := TWorldWaypointHelper.FindFirstWaypoint(FDesignRoot);
  VP := FindViewport;
  if (W = nil) or (VP = nil) then Exit;
  W.EvaluateForCamera(VP.Items, Vector3(0.0, 1.85, 0.0),
    Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, False);
  RefreshView;
end;

procedure TWorldWaypointForm.BtnTestBehindCamClick(Sender: TObject);
var
  W: TCastleWorldWaypoint;
  VP: TCastleViewport;
begin
  W := TWorldWaypointHelper.FindFirstWaypoint(FDesignRoot);
  VP := FindViewport;
  if (W = nil) or (VP = nil) then Exit;
  W.EvaluateForCamera(VP.Items, Vector3(-3.0, 1.85, 0.0),
    Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0), 60.0, 16.0 / 9.0, False);
  RefreshView;
end;

procedure TWorldWaypointForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TWorldWaypointForm.PaintHudScreen(Sender: TObject);
var
  C: TCanvas;
  WP: TCastleWorldWaypoint;
  P: TWaypointHudProjection;
  W, H, MX, MY, PX, PY: Integer;
begin
  C := FPaintHud.Canvas;
  W := Max(20, FPaintHud.Width);
  H := Max(20, FPaintHud.Height);
  C.Brush.Color := RGBToColor(14, 20, 28);
  C.FillRect(0, 0, W, H);

  MX := Round(W * 0.06);
  MY := Round(H * 0.06);
  C.Pen.Color := RGBToColor(58, 76, 98);
  C.Brush.Style := bsClear;
  C.Rectangle(MX, MY, W - MX, H - MY);

  WP := TWorldWaypointHelper.FindFirstWaypoint(FDesignRoot);
  if WP = nil then Exit;
  P := WP.LastProjection;
  PX := Round(P.ScreenUv.X * W);
  PY := Round((1.0 - P.ScreenUv.Y) * H);

  C.Brush.Style := bsSolid;
  case P.State of
    wssOnScreenClear:        C.Brush.Color := RGBToColor(255, 210, 64);
    wssOnScreenOccludedWall: C.Brush.Color := RGBToColor(110, 195, 255);
    wssOffScreenClampedEdge: C.Brush.Color := RGBToColor(255, 110, 80);
  else
    C.Brush.Color := RGBToColor(110, 110, 120);
  end;
  C.Ellipse(PX - 7, PY - 7, PX + 7, PY + 7);
end;

end.
