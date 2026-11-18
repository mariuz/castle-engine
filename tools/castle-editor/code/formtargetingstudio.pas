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

{ Visual Studio dialog for Targeting System Preset Lock-On & Aim-Assist (Phase 359). }
unit FormTargetingStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleViewport,
  CastleTargetingSystem, ToolTargetingStudio;

type
  TTargetingStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TTargetingStudioRefreshCallback = procedure of object;

  TTargetingStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TTargetingStudioModifiedCallback;
    FOnRefresh: TTargetingStudioRefreshCallback;
    FPaintCone: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveTargeting: TCastleTargetingBehavior;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnMeleeLockClick(Sender: TObject);
    procedure BtnRangedMagClick(Sender: TObject);
    procedure BtnHealerTriageClick(Sender: TObject);
    procedure BtnFlickLeftClick(Sender: TObject);
    procedure BtnFlickRightClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintConeRadar(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TTargetingStudioModifiedCallback;
      const AOnRefresh: TTargetingStudioRefreshCallback);
  end;

implementation

constructor TTargetingStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TTargetingStudioModifiedCallback;
  const AOnRefresh: TTargetingStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Targeting System Preset Stack (Lock-On, Aim Magnetism & Stick-Flick) Studio (Phase 359)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TTargetingStudioForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ UTargetingPreset — Multi-Stage Cone/Range/LoS/Faction Filter, Threat & Low-HP Scoring, Aim Magnetism & Stick-Flick';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Combat Targeting Range', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: Melee Hard Lock-On', @BtnMeleeLockClick);
  MakeBtn(Row1, 'Preset: Ranged Aim Magnetism', @BtnRangedMagClick);
  MakeBtn(Row1, 'Preset: Healer Friendly Lowest-HP', @BtnHealerTriageClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, '<- Flick Right-Stick LEFT', @BtnFlickLeftClick);
  MakeBtn(Row2, 'Flick Right-Stick RIGHT ->', @BtnFlickRightClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintCone := TPaintBox.Create(Self);
  FPaintCone.Parent := BodyPanel;
  FPaintCone.Align := alLeft;
  FPaintCone.Width := 500;
  FPaintCone.OnPaint := @PaintConeRadar;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TTargetingStudioForm.ActiveTargeting: TCastleTargetingBehavior;
begin
  Result := TTargetingStudioHelper.FindTargetingInHierarchy(FDesignRoot);
end;

procedure TTargetingStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TTargetingStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TTargetingStudioHelper.GenerateTargetingReport(ActiveTargeting);
  FPaintCone.Invalidate;
end;

procedure TTargetingStudioForm.BtnSpawnClick(Sender: TObject);
var
  P: TCastleTransform;
  T: TCastleTargetingBehavior;
begin
  if TTargetingStudioHelper.SpawnTargetingCombatRange(FDesignRoot, FDesignOwner, P, T) then
    NotifyChange('Spawn Combat Targeting Range');
end;

procedure TTargetingStudioForm.BtnMeleeLockClick(Sender: TObject);
var
  T: TCastleTargetingBehavior;
  Vp: TCastleViewport;
begin
  T := ActiveTargeting;
  Vp := TTargetingStudioHelper.FindViewport(FDesignRoot);
  if (T = nil) or (Vp = nil) then Exit;
  T.Preset := tpkMeleeSoulsHardLockOn;
  T.EvaluateTargetingStack(Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
  NotifyChange('Switch Targeting to Melee Hard Lock-On');
end;

procedure TTargetingStudioForm.BtnRangedMagClick(Sender: TObject);
var
  T: TCastleTargetingBehavior;
  Vp: TCastleViewport;
begin
  T := ActiveTargeting;
  Vp := TTargetingStudioHelper.FindViewport(FDesignRoot);
  if (T = nil) or (Vp = nil) then Exit;
  T.Preset := tpkRangedAimMagnetism;
  T.EvaluateTargetingStack(Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
  NotifyChange('Switch Targeting to Ranged Aim Magnetism');
end;

procedure TTargetingStudioForm.BtnHealerTriageClick(Sender: TObject);
var
  T: TCastleTargetingBehavior;
  Vp: TCastleViewport;
begin
  T := ActiveTargeting;
  Vp := TTargetingStudioHelper.FindViewport(FDesignRoot);
  if (T = nil) or (Vp = nil) then Exit;
  T.Preset := tpkHealerFriendlyLowestHp;
  T.EvaluateTargetingStack(Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
  NotifyChange('Switch Targeting to Healer Friendly Lowest-HP');
end;

procedure TTargetingStudioForm.BtnFlickLeftClick(Sender: TObject);
var
  T: TCastleTargetingBehavior;
  Vp: TCastleViewport;
begin
  T := ActiveTargeting;
  Vp := TTargetingStudioHelper.FindViewport(FDesignRoot);
  if (T = nil) or (Vp = nil) then Exit;
  T.SwitchLockedTargetHorizontal(-1.0, Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
  NotifyChange('Flick Lock-On Target Left');
end;

procedure TTargetingStudioForm.BtnFlickRightClick(Sender: TObject);
var
  T: TCastleTargetingBehavior;
  Vp: TCastleViewport;
begin
  T := ActiveTargeting;
  Vp := TTargetingStudioHelper.FindViewport(FDesignRoot);
  if (T = nil) or (Vp = nil) then Exit;
  T.SwitchLockedTargetHorizontal(1.0, Vector3(0, 1.25, 0), Vector3(0, 0, -1), Vp.Items);
  NotifyChange('Flick Lock-On Target Right');
end;

procedure TTargetingStudioForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TTargetingStudioHelper.GenerateTargetingReport(ActiveTargeting);
end;

procedure TTargetingStudioForm.PaintConeRadar(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, OX, OY, PX, PY: Integer;
  T: TCastleTargetingBehavior;
  E: TTargetCandidateEval;
  AngRad: Single;
begin
  Cv := FPaintCone.Canvas;
  W := FPaintCone.Width;
  H := FPaintCone.Height;
  Cv.Brush.Color := RGBToColor(18, 22, 30);
  Cv.FillRect(0, 0, W, H);

  T := ActiveTargeting;
  if T = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Combat Targeting Range" to inspect XZ Lock-On Cone.');
    Exit;
  end;

  OX := W div 2;
  OY := H - 46;
  AngRad := DegToRad(T.MaxHalfConeAngleDeg);
  Cv.Pen.Color := RGBToColor(70, 160, 230);
  Cv.Pen.Style := psDash;
  Cv.Line(OX, OY, OX - Round(Sin(AngRad) * 360), OY - Round(Cos(AngRad) * 360));
  Cv.Line(OX, OY, OX + Round(Sin(AngRad) * 360), OY - Round(Cos(AngRad) * 360));
  Cv.Pen.Style := psSolid;

  for I := 0 to T.CandidateCount - 1 do
  begin
    E := T.GetCandidateEval(I);
    PX := OX + Round((E.WorldAimPoint.X / 8.0) * (W * 0.42));
    PY := OY + Round((E.WorldAimPoint.Z / 16.0) * (H * 0.75));
    if E.TargetTransform = T.LockedTarget then
      Cv.Brush.Color := RGBToColor(255, 220, 55)
    else if E.PassedFilters then
      Cv.Brush.Color := RGBToColor(65, 225, 130)
    else
      Cv.Brush.Color := RGBToColor(150, 65, 65);
    Cv.Ellipse(PX - 8, PY - 8, PX + 8, PY + 8);
  end;

  Cv.Brush.Color := RGBToColor(70, 185, 255);
  Cv.Ellipse(OX - 8, OY - 8, OX + 8, OY + 8);
end;

end.
