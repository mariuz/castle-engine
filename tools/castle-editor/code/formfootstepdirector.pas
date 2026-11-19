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

{ Visual Studio dialog for Skeletal Footstep Decal & Acoustic Surface (Phase 380). }
unit FormFootstepDirector;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleViewport, CastleFootstepDirector, ToolFootstepDirector;

type
  TFootstepDirectorModifiedCallback = procedure(const UndoComment: String) of object;
  TFootstepDirectorRefreshCallback = procedure of object;

  TFootstepDirectorForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TFootstepDirectorModifiedCallback;
    FOnRefresh: TFootstepDirectorRefreshCallback;
    FLblSummary: TLabel;
    FPaintWalkway: TPaintBox;
    FMemoReport: TMemo;
    FActorZ: Single;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnWalkwayClick(Sender: TObject);
    procedure BtnMarchStepClick(Sender: TObject);
    procedure BtnSneakPresetClick(Sender: TObject);
    procedure BtnClearPrintsClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintWalkwayPrints(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TFootstepDirectorModifiedCallback;
      const AOnRefresh: TFootstepDirectorRefreshCallback);
  end;

implementation

constructor TFootstepDirectorForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TFootstepDirectorModifiedCallback;
  const AOnRefresh: TFootstepDirectorRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FActorZ := 0.8;
  Caption := 'Skeletal Footstep Decal, Splash/Dust & Acoustic Surface Studio (Phase 380)';
  Width := 1020;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TFootstepDirectorForm.BuildUi;
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

  MakeBtn(Row1, '+ Spawn Snow/Puddle/Metal Walkway', @BtnSpawnWalkwayClick);
  MakeBtn(Row1, 'March Forward (+1.1m)', @BtnMarchStepClick);
  MakeBtn(Row1, 'Stealth Rogue Sneak Preset', @BtnSneakPresetClick);
  MakeBtn(Row1, 'Clear Footprints', @BtnClearPrintsClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintWalkway := TPaintBox.Create(Self);
  FPaintWalkway.Parent := BodyPanel;
  FPaintWalkway.Align := alLeft;
  FPaintWalkway.Width := 460;
  FPaintWalkway.OnPaint := @PaintWalkwayPrints;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TFootstepDirectorForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TFootstepDirectorForm.RefreshView;
var
  D: TCastleFootstepDirector;
begin
  D := TFootstepDirectorHelper.FindDirectorInHierarchy(FDesignRoot);
  if D = nil then
    FLblSummary.Caption := 'No TCastleFootstepDirector in scene — click "+ Spawn Snow/Puddle/Metal Walkway".'
  else
    FLblSummary.Caption := Format('%s %s | Actor Z=%.1fm | Gain=%.0f%%', [
      D.Name, D.FootstepSummaryBadge, FActorZ, D.LastFootstep.AcousticGain01 * 100.0]);
  FMemoReport.Lines.Text := TFootstepDirectorHelper.GenerateFootstepReport(D);
  FPaintWalkway.Invalidate;
end;

procedure TFootstepDirectorForm.BtnSpawnWalkwayClick(Sender: TObject);
var
  D: TCastleFootstepDirector;
begin
  FActorZ := 0.8;
  if TFootstepDirectorHelper.SpawnMultiSurfaceWalkwayDemo(FDesignRoot, FDesignOwner, D) then
    NotifyChanged('Spawn Multi-Surface Footstep Walkway');
end;

procedure TFootstepDirectorForm.BtnMarchStepClick(Sender: TObject);
var
  D: TCastleFootstepDirector;
  Vp: TCastleViewport;
begin
  D := TFootstepDirectorHelper.FindDirectorInHierarchy(FDesignRoot);
  Vp := TFootstepDirectorHelper.FindViewport(FDesignRoot);
  if (D = nil) or (Vp = nil) then Exit;
  FActorZ := FActorZ + 1.1;
  if FActorZ > 11.5 then FActorZ := 0.8;
  D.AdvanceLocomotionCycle(Vp.Items, Vector3(0.0, 0.0, FActorZ), 0.0, 4.4, 0.25);
  NotifyChanged('Advance Footstep Cycle');
end;

procedure TFootstepDirectorForm.BtnSneakPresetClick(Sender: TObject);
var
  D: TCastleFootstepDirector;
begin
  D := TFootstepDirectorHelper.FindDirectorInHierarchy(FDesignRoot);
  if D = nil then Exit;
  D.Preset := fdpStealthRogueSneak;
  NotifyChanged('Stealth Rogue Sneak Preset');
end;

procedure TFootstepDirectorForm.BtnClearPrintsClick(Sender: TObject);
var
  D: TCastleFootstepDirector;
begin
  D := TFootstepDirectorHelper.FindDirectorInHierarchy(FDesignRoot);
  if D = nil then Exit;
  D.ClearFootprints;
  FActorZ := 0.8;
  NotifyChanged('Clear Footprints');
end;

procedure TFootstepDirectorForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TFootstepDirectorForm.PaintWalkwayPrints(Sender: TObject);
var
  Cv: TCanvas;
  D: TCastleFootstepDirector;
  I, Px, Py: Integer;
  E: TFootprintDecalEntry;
begin
  Cv := FPaintWalkway.Canvas;
  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, FPaintWalkway.Width, FPaintWalkway.Height);

  D := TFootstepDirectorHelper.FindDirectorInHierarchy(FDesignRoot);
  if D = nil then Exit;

  for I := 0 to MaxFootprintDecals - 1 do
  begin
    E := D.GetDecalSlot(I);
    if not E.Active then Continue;
    Px := (FPaintWalkway.Width div 2) + Round(E.WorldPos.X * 140.0);
    Py := FPaintWalkway.Height - 40 - Round(E.WorldPos.Z * 38.0);
    if E.FootSide = fsLeftFoot then
      Cv.Brush.Color := RGBToColor(80, 210, 255)
    else
      Cv.Brush.Color := RGBToColor(255, 175, 70);
    Cv.Pen.Color := Cv.Brush.Color;
    Cv.Rectangle(Px - 7, Py - 12, Px + 7, Py + 12);
  end;
end;

end.
