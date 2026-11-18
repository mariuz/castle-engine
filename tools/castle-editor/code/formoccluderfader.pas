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

{ Visual Studio dialog for Smart Camera Collision Occluder Cutaway & Foliage Parting (Phase 362). }
unit FormOccluderFader;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleViewport, CastleOccluderFader, ToolOccluderFader;

type
  TOccluderFaderModifiedCallback = procedure(const UndoComment: String) of object;
  TOccluderFaderRefreshCallback = procedure of object;

  TOccluderFaderForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TOccluderFaderModifiedCallback;
    FOnRefresh: TOccluderFaderRefreshCallback;
    FCamWorldPos: TVector3;
    FPaintRadar: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveFader: TCastleCameraOccluderFader;
    function ActiveHero: TCastleTransform;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnArpgPresetClick(Sender: TObject);
    procedure BtnCorridorPresetClick(Sender: TObject);
    procedure BtnMeadowPresetClick(Sender: TObject);
    procedure BtnBehindWallCamClick(Sender: TObject);
    procedure BtnOverheadClearCamClick(Sender: TObject);
    procedure BtnWalkHeroMeadowClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCutawayDiagram(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TOccluderFaderModifiedCallback;
      const AOnRefresh: TOccluderFaderRefreshCallback);
  end;

implementation

constructor TOccluderFaderForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TOccluderFaderModifiedCallback;
  const AOnRefresh: TOccluderFaderRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FCamWorldPos := Vector3(0.0, 3.2, 10.0);
  Caption := 'Smart Camera Occluder Cutaway / Dither Fade & Foliage Parting Studio (Phase 362)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TOccluderFaderForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ Camera Occluder Cutaway & Foliage Interaction — 5-Ray WorldRay Wall Fade + Length-Preserving Grass Parting';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn ARPG Courtyard & Tall Grass', @BtnSpawnClick);
  MakeBtn(Row1, 'Preset: ARPG Roof Cutaway', @BtnArpgPresetClick);
  MakeBtn(Row1, 'Preset: Tight Corridor Fade', @BtnCorridorPresetClick);
  MakeBtn(Row1, 'Preset: Stealth Tall-Grass Halo', @BtnMeadowPresetClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Camera Behind Wall (Trigger Cutaway!)', @BtnBehindWallCamClick);
  MakeBtn(Row2, 'Camera Overhead Clear (Restore 100% Opacity)', @BtnOverheadClearCamClick);
  MakeBtn(Row2, 'Stride Hero Across Tall-Grass Meadow', @BtnWalkHeroMeadowClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintRadar := TPaintBox.Create(Self);
  FPaintRadar.Parent := BodyPanel;
  FPaintRadar.Align := alLeft;
  FPaintRadar.Width := 480;
  FPaintRadar.OnPaint := @PaintCutawayDiagram;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TOccluderFaderForm.ActiveFader: TCastleCameraOccluderFader;
begin
  Result := TOccluderFaderHelper.FindFaderInHierarchy(FDesignRoot);
end;

function TOccluderFaderForm.ActiveHero: TCastleTransform;
begin
  Result := nil;
  if FDesignOwner <> nil then
    Result := FDesignOwner.FindComponent('CutawayHeroActor') as TCastleTransform;
end;

procedure TOccluderFaderForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TOccluderFaderForm.RefreshView;
begin
  FMemoReport.Lines.Text := TOccluderFaderHelper.GenerateOccluderReport(ActiveFader);
  FPaintRadar.Invalidate;
end;

procedure TOccluderFaderForm.BtnSpawnClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
  Hero, Wall, Pillar: TCastleTransform;
begin
  if TOccluderFaderHelper.SpawnArpgCourtyardCutawayDemo(FDesignRoot, FDesignOwner, F, Hero, Wall, Pillar) then
  begin
    FCamWorldPos := Vector3(0.0, 3.2, 10.0);
    NotifyChange('Spawn ARPG Courtyard Cutaway & Foliage Parting Demo');
  end;
end;

procedure TOccluderFaderForm.BtnArpgPresetClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
begin
  F := ActiveFader;
  if F = nil then Exit;
  F.Preset := ofpIsometricArpgRoofCutaway;
  NotifyChange('Apply Isometric ARPG Roof Cutaway Preset');
end;

procedure TOccluderFaderForm.BtnCorridorPresetClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
begin
  F := ActiveFader;
  if F = nil then Exit;
  F.Preset := ofpThirdPersonWallCorridorFade;
  NotifyChange('Apply Third-Person Corridor Fade Preset');
end;

procedure TOccluderFaderForm.BtnMeadowPresetClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
begin
  F := ActiveFader;
  if F = nil then Exit;
  F.Preset := ofpStealthTallGrassParting;
  NotifyChange('Apply Stealth Tall-Grass Parting Preset');
end;

procedure TOccluderFaderForm.BtnBehindWallCamClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
  Vp: TCastleViewport;
  H: TCastleTransform;
  HeroPos: TVector3;
begin
  F := ActiveFader;
  Vp := TOccluderFaderHelper.FindViewport(FDesignRoot);
  if (F = nil) or (Vp = nil) then Exit;
  H := ActiveHero;
  if H <> nil then HeroPos := H.Translation else HeroPos := Vector3(0, 0.9, 0);
  FCamWorldPos := Vector3(0.0, 2.5, 10.0);
  F.StepOccluderAndFoliage(Vp.Items, FCamWorldPos, HeroPos, [HeroPos], 0.80);
  NotifyChange('Step Camera Behind Wall Occluder');
end;

procedure TOccluderFaderForm.BtnOverheadClearCamClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
  Vp: TCastleViewport;
  H: TCastleTransform;
  HeroPos: TVector3;
begin
  F := ActiveFader;
  Vp := TOccluderFaderHelper.FindViewport(FDesignRoot);
  if (F = nil) or (Vp = nil) then Exit;
  H := ActiveHero;
  if H <> nil then HeroPos := H.Translation else HeroPos := Vector3(0, 0.9, 0);
  FCamWorldPos := Vector3(0.0, 14.0, 1.5);
  F.StepOccluderAndFoliage(Vp.Items, FCamWorldPos, HeroPos, [HeroPos], 1.20);
  NotifyChange('Step Camera Overhead Clear Sightline');
end;

procedure TOccluderFaderForm.BtnWalkHeroMeadowClick(Sender: TObject);
var
  F: TCastleCameraOccluderFader;
  Vp: TCastleViewport;
  H: TCastleTransform;
begin
  F := ActiveFader;
  Vp := TOccluderFaderHelper.FindViewport(FDesignRoot);
  H := ActiveHero;
  if (F = nil) or (Vp = nil) or (H = nil) then Exit;
  H.Translation := Vector3(
    Sin(H.Translation.X + 1.1) * 1.8,
    0.9,
    Cos(H.Translation.Z + 0.9) * 1.8);
  F.StepOccluderAndFoliage(Vp.Items, FCamWorldPos, H.Translation, [H.Translation], 0.35);
  NotifyChange('Stride Hero Through Tall-Grass Meadow');
end;

procedure TOccluderFaderForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TOccluderFaderHelper.GenerateOccluderReport(ActiveFader);
end;

procedure TOccluderFaderForm.PaintCutawayDiagram(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, CY, HaloR: Integer;
  F: TCastleCameraOccluderFader;
  WallAlpha: Single;
begin
  Cv := FPaintRadar.Canvas;
  W := FPaintRadar.Width;
  H := FPaintRadar.Height;
  Cv.Brush.Color := RGBToColor(20, 26, 22);
  Cv.FillRect(0, 0, W, H);

  F := ActiveFader;
  if F = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn ARPG Courtyard & Tall Grass" to preview Cutaway & Parting.');
    Exit;
  end;

  CX := W div 2;
  CY := H div 2 - 20;
  HaloR := Round(F.FoliagePartingRadius * 28);

  { Foliage parting halo }
  Cv.Pen.Color := RGBToColor(110, 225, 95);
  Cv.Pen.Width := 2;
  Cv.Brush.Color := RGBToColor(32, 58, 34);
  Cv.Ellipse(CX - HaloR, CY - HaloR, CX + HaloR, CY + HaloR);

  { Front wall cutaway bar }
  WallAlpha := F.GetTrackedOpacity('CastleFrontWallOccluder');
  Cv.Brush.Color := RGBToColor(
    Round(60 + WallAlpha * 130),
    Round(55 + WallAlpha * 115),
    Round(50 + WallAlpha * 100));
  Cv.Rectangle(CX - 110, CY + 65, CX + 110, CY + 86);

  { Sightline ray Camera -> Hero }
  Cv.Pen.Color := RGBToColor(90, 200, 255);
  Cv.Line(CX, H - 36, CX, CY);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('Wall Opacity = %.0f%% | Parted Blades = %d (R=%.2fm)', [
    WallAlpha * 100.0, F.PartedBladeCount, F.FoliagePartingRadius]));
end;

end.
