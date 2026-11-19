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

{ Visual Studio dialog for Procedural Ivy, Vine & Root Surface Climber (Phase 379). }
unit FormIvyClimber;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleViewport, CastleIvyClimber, ToolIvyClimber;

type
  TIvyClimberModifiedCallback = procedure(const UndoComment: String) of object;
  TIvyClimberRefreshCallback = procedure of object;

  TIvyClimberForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TIvyClimberModifiedCallback;
    FOnRefresh: TIvyClimberRefreshCallback;
    FLblSummary: TLabel;
    FPaintElevation: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnRegrowReseedClick(Sender: TObject);
    procedure BtnAutumnCrimsonClick(Sender: TObject);
    procedure BtnCaveRootClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintIvyElevation(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TIvyClimberModifiedCallback;
      const AOnRefresh: TIvyClimberRefreshCallback);
  end;

implementation

constructor TIvyClimberForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TIvyClimberModifiedCallback;
  const AOnRefresh: TIvyClimberRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Ivy, Vine & Root Surface Climber Studio (Phase 379)';
  Width := 1020;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TIvyClimberForm.BuildUi;
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

  MakeBtn(Row1, '+ Spawn Masonry Wall & Grow Ivy', @BtnSpawnDemoClick);
  MakeBtn(Row1, 'Re-Seed & Regrow Tendrils', @BtnRegrowReseedClick);
  MakeBtn(Row1, 'Autumn Crimson Creeper', @BtnAutumnCrimsonClick);
  MakeBtn(Row1, 'Bioluminescent Cave Root', @BtnCaveRootClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintElevation := TPaintBox.Create(Self);
  FPaintElevation.Parent := BodyPanel;
  FPaintElevation.Align := alLeft;
  FPaintElevation.Width := 460;
  FPaintElevation.OnPaint := @PaintIvyElevation;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

procedure TIvyClimberForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then FOnModified(AReason);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshView;
end;

procedure TIvyClimberForm.RefreshView;
var
  Ivy: TCastleIvyClimber;
begin
  Ivy := TIvyClimberHelper.FindIvyInHierarchy(FDesignRoot);
  if Ivy = nil then
    FLblSummary.Caption := 'No TCastleIvyClimber in scene — click "+ Spawn Masonry Wall & Grow Ivy".'
  else
    FLblSummary.Caption := Format('%s %s | Peak Height Y=%.2fm | Seed=%d', [
      Ivy.Name, Ivy.IvySummaryBadge, Ivy.MaxReachedHeightY, Ivy.RandomSeed]);
  FMemoReport.Lines.Text := TIvyClimberHelper.GenerateIvyReport(Ivy);
  FPaintElevation.Invalidate;
end;

procedure TIvyClimberForm.BtnSpawnDemoClick(Sender: TObject);
var
  Ivy: TCastleIvyClimber;
begin
  if TIvyClimberHelper.SpawnMasonryWallIvyDemo(FDesignRoot, FDesignOwner, Ivy) then
    NotifyChanged('Spawn Masonry Wall & Grow Ivy');
end;

procedure TIvyClimberForm.BtnRegrowReseedClick(Sender: TObject);
var
  Ivy: TCastleIvyClimber;
  Vp: TCastleViewport;
begin
  Ivy := TIvyClimberHelper.FindIvyInHierarchy(FDesignRoot);
  Vp := TIvyClimberHelper.FindViewport(FDesignRoot);
  if (Ivy = nil) or (Vp = nil) then Exit;
  Ivy.RandomSeed := Ivy.RandomSeed + 137;
  Ivy.GrowIvyOnWorld(Vp.Items);
  NotifyChanged('Re-Seed & Regrow Ivy');
end;

procedure TIvyClimberForm.BtnAutumnCrimsonClick(Sender: TObject);
var
  Ivy: TCastleIvyClimber;
  Vp: TCastleViewport;
begin
  Ivy := TIvyClimberHelper.FindIvyInHierarchy(FDesignRoot);
  Vp := TIvyClimberHelper.FindViewport(FDesignRoot);
  if (Ivy = nil) or (Vp = nil) then Exit;
  Ivy.Preset := ivpAutumnCrimsonCreeper;
  Ivy.GrowIvyOnWorld(Vp.Items);
  NotifyChanged('Autumn Crimson Creeper');
end;

procedure TIvyClimberForm.BtnCaveRootClick(Sender: TObject);
var
  Ivy: TCastleIvyClimber;
  Vp: TCastleViewport;
begin
  Ivy := TIvyClimberHelper.FindIvyInHierarchy(FDesignRoot);
  Vp := TIvyClimberHelper.FindViewport(FDesignRoot);
  if (Ivy = nil) or (Vp = nil) then Exit;
  Ivy.Preset := ivpBioluminescentCaveRoot;
  Ivy.GrowIvyOnWorld(Vp.Items);
  NotifyChanged('Bioluminescent Cave Root');
end;

procedure TIvyClimberForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TIvyClimberForm.PaintIvyElevation(Sender: TObject);
var
  Cv: TCanvas;
  Ivy: TCastleIvyClimber;
  I, Px, Py: Integer;
  N: TIvyGrowthNode;
begin
  Cv := FPaintElevation.Canvas;
  Cv.Brush.Color := RGBToColor(16, 22, 24);
  Cv.FillRect(0, 0, FPaintElevation.Width, FPaintElevation.Height);

  Ivy := TIvyClimberHelper.FindIvyInHierarchy(FDesignRoot);
  if Ivy = nil then Exit;

  for I := 0 to Ivy.NodeCount - 1 do
  begin
    N := Ivy.GetNode(I);
    Px := (FPaintElevation.Width div 2) + Round(N.WorldPos.X * 72.0);
    Py := FPaintElevation.Height - 40 - Round(N.WorldPos.Y * 95.0);
    if N.AttachedToWall then
      Cv.Brush.Color := RGBToColor(62, 210, 96)
    else
      Cv.Brush.Color := RGBToColor(165, 130, 75);
    Cv.Pen.Color := Cv.Brush.Color;
    Cv.Ellipse(Px - 4, Py - 4, Px + 4, Py + 4);
  end;
end;

end.
