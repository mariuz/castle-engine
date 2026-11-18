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

{ Visual Studio dialog for Contextual Paired Animation & Docking (Phase 358). }
unit FormContextualAnim;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleViewport,
  CastleContextualAnim, ToolContextualAnim;

type
  TContextualAnimModifiedCallback = procedure(const UndoComment: String) of object;
  TContextualAnimRefreshCallback = procedure of object;

  TContextualAnimForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TContextualAnimModifiedCallback;
    FOnRefresh: TContextualAnimRefreshCallback;
    FPaintDojo: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveScene: TCastleContextualAnimScene;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnStealthTakedownClick(Sender: TObject);
    procedure BtnFrontParryClick(Sender: TObject);
    procedure BtnCoOpBoostClick(Sender: TObject);
    procedure BtnExecuteSyncClick(Sender: TObject);
    procedure BtnTestWallBlockClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintDojoMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TContextualAnimModifiedCallback;
      const AOnRefresh: TContextualAnimRefreshCallback);
  end;

implementation

constructor TContextualAnimForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TContextualAnimModifiedCallback;
  const AOnRefresh: TContextualAnimRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Contextual Paired Animation, Docking & Wall-Safe Clearance Studio (Phase 358)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TContextualAnimForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ UContextualAnimSceneAsset — Stealth Takedown, Parry Finisher, Co-Op Lift, Approach Cones & WorldRay Wall Clearance';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Paired Combat Dojo', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Stealth Rear Takedown', @BtnStealthTakedownClick);
  MakeBtn(Row1, 'Preset: Front Parry Finisher', @BtnFrontParryClick);
  MakeBtn(Row1, 'Preset: Co-Op Wall Boost Lift', @BtnCoOpBoostClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Execute Paired Warp & Contact Sync!', @BtnExecuteSyncClick);
  MakeBtn(Row2, 'Test Wall-Blocked Rear Takedown (Safety Gate)', @BtnTestWallBlockClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintDojo := TPaintBox.Create(Self);
  FPaintDojo.Parent := BodyPanel;
  FPaintDojo.Align := alLeft;
  FPaintDojo.Width := 520;
  FPaintDojo.OnPaint := @PaintDojoMap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TContextualAnimForm.ActiveScene: TCastleContextualAnimScene;
begin
  Result := TContextualAnimHelper.FindContextualSceneInHierarchy(FDesignRoot);
end;

procedure TContextualAnimForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TContextualAnimForm.RefreshView;
begin
  FMemoReport.Lines.Text := TContextualAnimHelper.GenerateContextualAnimReport(ActiveScene);
  FPaintDojo.Invalidate;
end;

procedure TContextualAnimForm.BtnSpawnClick(Sender: TObject);
var
  S: TCastleContextualAnimScene;
  Inst, Guard, Wall: TCastleTransform;
begin
  if TContextualAnimHelper.SpawnContextualPairedDojo(FDesignRoot, FDesignOwner, S, Inst, Guard, Wall) then
    NotifyChange('Spawn Contextual Paired Animation Dojo');
end;

procedure TContextualAnimForm.BtnStealthTakedownClick(Sender: TObject);
var
  S: TCastleContextualAnimScene;
  Vp: TCastleViewport;
begin
  S := ActiveScene;
  Vp := TContextualAnimHelper.FindViewport(FDesignRoot);
  if (S = nil) or (S.InstigatorActor = nil) or (S.TargetActor = nil) then Exit;
  S.Preset := capStealthRearTakedown;
  S.TargetActor.Translation := Vector3(0, 0, 0);
  S.InstigatorActor.Translation := Vector3(0.45, 0, 2.05);
  if Vp <> nil then S.EvaluateDockingEligibility(S.InstigatorActor, S.TargetActor, Vp.Items);
  NotifyChange('Configure Stealth Rear Takedown');
end;

procedure TContextualAnimForm.BtnFrontParryClick(Sender: TObject);
var
  S: TCastleContextualAnimScene;
  Vp: TCastleViewport;
begin
  S := ActiveScene;
  Vp := TContextualAnimHelper.FindViewport(FDesignRoot);
  if (S = nil) or (S.InstigatorActor = nil) or (S.TargetActor = nil) then Exit;
  S.Preset := capFrontParryRiposteFinisher;
  S.TargetActor.Translation := Vector3(0, 0, 0);
  S.InstigatorActor.Translation := Vector3(-0.35, 0, -2.20);
  if Vp <> nil then S.EvaluateDockingEligibility(S.InstigatorActor, S.TargetActor, Vp.Items);
  NotifyChange('Configure Front Parry Riposte Finisher');
end;

procedure TContextualAnimForm.BtnCoOpBoostClick(Sender: TObject);
var
  S: TCastleContextualAnimScene;
  Vp: TCastleViewport;
begin
  S := ActiveScene;
  Vp := TContextualAnimHelper.FindViewport(FDesignRoot);
  if (S = nil) or (S.InstigatorActor = nil) or (S.TargetActor = nil) then Exit;
  S.Preset := capCoOpWallBoostLift;
  S.TargetActor.Translation := Vector3(0, 0, 0);
  S.InstigatorActor.Translation := Vector3(0.30, 0, 1.85);
  if Vp <> nil then S.EvaluateDockingEligibility(S.InstigatorActor, S.TargetActor, Vp.Items);
  NotifyChange('Configure Co-Op Wall Boost Lift');
end;

procedure TContextualAnimForm.BtnExecuteSyncClick(Sender: TObject);
var
  S: TCastleContextualAnimScene;
  Vp: TCastleViewport;
  I: Integer;
begin
  S := ActiveScene;
  Vp := TContextualAnimHelper.FindViewport(FDesignRoot);
  if (S = nil) or (S.InstigatorActor = nil) or (S.TargetActor = nil) or (Vp = nil) then Exit;
  if S.BeginSynchronizedScene(S.InstigatorActor, S.TargetActor, Vp.Items) then
  begin
    for I := 1 to 12 do
      S.StepSynchronizedScene(S.DurationSec * 0.05);
    NotifyChange('Execute Contextual Paired Warp & Contact Sync');
  end else
    RefreshView;
end;

procedure TContextualAnimForm.BtnTestWallBlockClick(Sender: TObject);
var
  S: TCastleContextualAnimScene;
  Vp: TCastleViewport;
begin
  S := ActiveScene;
  Vp := TContextualAnimHelper.FindViewport(FDesignRoot);
  if (S = nil) or (S.InstigatorActor = nil) or (S.TargetActor = nil) or (Vp = nil) then Exit;
  S.Preset := capStealthRearTakedown;
  { Place Guard with back right against ContextualTestWall (Z = 6.0, half-thick 0.25 -> Z = 5.35) }
  S.TargetActor.Translation := Vector3(0.0, 0.0, 5.35);
  S.InstigatorActor.Translation := Vector3(0.60, 0.0, 5.70);
  S.EvaluateDockingEligibility(S.InstigatorActor, S.TargetActor, Vp.Items);
  NotifyChange('Test Wall-Blocked Rear Takedown');
end;

procedure TContextualAnimForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TContextualAnimHelper.GenerateContextualAnimReport(ActiveScene);
end;

procedure TContextualAnimForm.PaintDojoMap(Sender: TObject);
var
  Cv: TCanvas;
  W, H: Integer;
  S: TCastleContextualAnimScene;
  D: TContextualDockCheckResult;

  function MapXZ(const Pt: TVector3): TPoint;
  begin
    Result.X := Round(W * 0.5 + (Pt.X / 8.0) * (W * 0.42));
    Result.Y := Round(H * 0.5 + (Pt.Z / 8.0) * (H * 0.42));
  end;

var
  TPt, DPt, IPt: TPoint;
begin
  Cv := FPaintDojo.Canvas;
  W := FPaintDojo.Width;
  H := FPaintDojo.Height;
  Cv.Brush.Color := RGBToColor(22, 25, 33);
  Cv.FillRect(0, 0, W, H);

  S := ActiveScene;
  if S = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Paired Combat Dojo" to inspect XZ Docking & Clearance.');
    Exit;
  end;

  D := S.LastDockCheck;
  TPt := MapXZ(D.TargetAnchorWorldPos);
  DPt := MapXZ(D.DesiredInstigatorDockWorldPos);

  if D.CanTrigger then
    Cv.Pen.Color := RGBToColor(65, 230, 130)
  else
    Cv.Pen.Color := RGBToColor(245, 75, 70);
  Cv.Pen.Width := 2;
  Cv.Line(TPt.X, TPt.Y, DPt.X, DPt.Y);

  Cv.Brush.Color := RGBToColor(235, 75, 70);
  Cv.Ellipse(TPt.X - 9, TPt.Y - 9, TPt.X + 9, TPt.Y + 9);

  Cv.Brush.Color := RGBToColor(70, 220, 130);
  Cv.Rectangle(DPt.X - 7, DPt.Y - 7, DPt.X + 7, DPt.Y + 7);

  if S.InstigatorActor <> nil then
  begin
    IPt := MapXZ(S.InstigatorActor.WorldTranslation);
    Cv.Brush.Color := RGBToColor(65, 180, 250);
    Cv.Ellipse(IPt.X - 8, IPt.Y - 8, IPt.X + 8, IPt.Y + 8);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('XZ Paired Docking | %s | %s %s', [
    ContextualPresetToString(S.Preset),
    BoolToStr(D.CanTrigger, 'ELIGIBLE', 'BLOCKED:'),
    D.BlockReason]));
end;

end.
