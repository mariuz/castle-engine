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

{ Visual Studio dialog for Planar Portal & Seamless Mirror Teleport (Phase 377). }
unit FormPortalStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastlePortalPair, ToolPortalStudio;

type
  TPortalStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TPortalStudioRefreshCallback = procedure of object;

  TPortalStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TPortalStudioModifiedCallback;
    FOnRefresh: TPortalStudioRefreshCallback;
    FLblSummary: TLabel;
    FPaintDiagram: TPaintBox;
    FMemoReport: TMemo;
    FLastWarpedPos: TVector3;
    FLastWarpedVel: TVector3;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnPairClick(Sender: TObject);
    procedure BtnTestWalkCrossClick(Sender: TObject);
    procedure BtnStepCooldownClick(Sender: TObject);
    procedure BtnToggleMirrorClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintTopDownPortals(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TPortalStudioModifiedCallback;
      const AOnRefresh: TPortalStudioRefreshCallback);
  end;

implementation

constructor TPortalStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TPortalStudioModifiedCallback;
  const AOnRefresh: TPortalStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FLastWarpedPos := TVector3.Zero;
  FLastWarpedVel := TVector3.Zero;
  Caption := 'Planar Portal & Seamless Mirror Oblique Frustum Studio (Phase 377)';
  Width := 1020;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TPortalStudioForm.BuildUi;
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

  MakeBtn(Row1, '+ Spawn Linked Blue/Orange Portals', @BtnSpawnPairClick);
  MakeBtn(Row1, 'Walk Actor Through Blue Portal!', @BtnTestWalkCrossClick);
  MakeBtn(Row1, 'Step Cooldown (+0.30s)', @BtnStepCooldownClick);
  MakeBtn(Row1, 'Toggle Planar Mirror Mode', @BtnToggleMirrorClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintDiagram := TPaintBox.Create(Self);
  FPaintDiagram.Parent := BodyPanel;
  FPaintDiagram.Align := alLeft;
  FPaintDiagram.Width := 460;
  FPaintDiagram.OnPaint := @PaintTopDownPortals;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TPortalStudioForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TPortalStudioForm.RefreshView;
var
  P: TCastlePortalGateway;
begin
  P := TPortalStudioHelper.FindPrimaryPortal(FDesignRoot);
  if P = nil then
    FLblSummary.Caption := 'No TCastlePortalGateway in scene — click "+ Spawn Linked Blue/Orange Portals".'
  else
    FLblSummary.Caption := Format('%s %s | Last Emerged Pos=(%.2f, %.2f, %.2f) Vel=(%.1f, %.1f, %.1f)', [
      P.Name, P.PortalSummaryBadge,
      FLastWarpedPos.X, FLastWarpedPos.Y, FLastWarpedPos.Z,
      FLastWarpedVel.X, FLastWarpedVel.Y, FLastWarpedVel.Z]);
  FMemoReport.Lines.Text := TPortalStudioHelper.GeneratePortalReport(FDesignRoot, P);
  FPaintDiagram.Invalidate;
end;

procedure TPortalStudioForm.BtnSpawnPairClick(Sender: TObject);
var
  BlueP, OrangeP: TCastlePortalGateway;
begin
  if TPortalStudioHelper.SpawnLinkedBlueOrangePortalsDemo(FDesignRoot, FDesignOwner, BlueP, OrangeP) then
    NotifyChanged('Spawn Linked Blue/Orange Portals');
end;

procedure TPortalStudioForm.BtnTestWalkCrossClick(Sender: TObject);
var
  P: TCastlePortalGateway;
begin
  P := TPortalStudioHelper.FindPrimaryPortal(FDesignRoot);
  if P = nil then Exit;
  P.StepPortalCooldown(1.0);
  if P.ResolveLinkedPortal(FDesignRoot) <> nil then
    P.ResolveLinkedPortal(FDesignRoot).StepPortalCooldown(1.0);
  P.TryCrossPortal(FDesignRoot,
    P.Translation + Vector3(0.0, 1.0, 0.8),
    P.Translation + Vector3(0.0, 1.0, -0.4),
    Vector3(0.0, 0.0, -6.0),
    FLastWarpedPos, FLastWarpedVel);
  NotifyChanged('Test Portal Walk Crossing');
end;

procedure TPortalStudioForm.BtnStepCooldownClick(Sender: TObject);
var
  P, Dest: TCastlePortalGateway;
begin
  P := TPortalStudioHelper.FindPrimaryPortal(FDesignRoot);
  if P = nil then Exit;
  P.StepPortalCooldown(0.30);
  Dest := P.ResolveLinkedPortal(FDesignRoot);
  if Dest <> nil then Dest.StepPortalCooldown(0.30);
  RefreshView;
end;

procedure TPortalStudioForm.BtnToggleMirrorClick(Sender: TObject);
var
  P: TCastlePortalGateway;
begin
  P := TPortalStudioHelper.FindPrimaryPortal(FDesignRoot);
  if P = nil then Exit;
  P.MirrorMode := not P.MirrorMode;
  NotifyChanged('Toggle Portal Mirror Mode');
end;

procedure TPortalStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TPortalStudioForm.PaintTopDownPortals(Sender: TObject);
var
  Cv: TCanvas;
  P, Dest: TCastlePortalGateway;
  Cx, Cy: Integer;
begin
  Cv := FPaintDiagram.Canvas;
  Cv.Brush.Color := RGBToColor(15, 20, 28);
  Cv.FillRect(0, 0, FPaintDiagram.Width, FPaintDiagram.Height);

  P := TPortalStudioHelper.FindPrimaryPortal(FDesignRoot);
  if P = nil then Exit;

  Cx := FPaintDiagram.Width div 2;
  Cy := FPaintDiagram.Height div 2;

  Cv.Pen.Width := 4;
  Cv.Pen.Color := RGBToColor(40, 195, 255);
  Cv.Line(Cx - 140, Cy + 40, Cx - 60, Cy + 40);

  Dest := P.ResolveLinkedPortal(FDesignRoot);
  if (Dest <> nil) and (not P.MirrorMode) then
  begin
    Cv.Pen.Color := RGBToColor(255, 138, 36);
    Cv.Line(Cx + 90, Cy - 80, Cx + 90, Cy);
    Cv.Pen.Width := 1;
    Cv.Pen.Style := psDash;
    Cv.Pen.Color := RGBToColor(160, 210, 240);
    Cv.Line(Cx - 100, Cy + 40, Cx + 90, Cy - 40);
    Cv.Pen.Style := psSolid;
  end;
  Cv.Pen.Width := 1;
end;

end.
