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

{ Visual Studio dialog for Mutable Modular Character Customizer (Phase 360). }
unit FormMutableStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleMutableCharacter, ToolMutableStudio;

type
  TMutableStudioModifiedCallback = procedure(const UndoComment: String) of object;
  TMutableStudioRefreshCallback = procedure of object;

  TMutableStudioForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TMutableStudioModifiedCallback;
    FOnRefresh: TMutableStudioRefreshCallback;
    FRollSeed: Integer;
    FPaintSilhouette: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveHero: TCastleMutableCharacter;
    procedure NotifyChange(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnPaladinClick(Sender: TObject);
    procedure BtnRangerClick(Sender: TObject);
    procedure BtnMageClick(Sender: TObject);
    procedure BtnCycleHelmClick(Sender: TObject);
    procedure BtnTitanMorphClick(Sender: TObject);
    procedure BtnRandomizeClick(Sender: TObject);
    procedure BtnCopyRecipeClick(Sender: TObject);
    procedure PaintSilhouette(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TMutableStudioModifiedCallback;
      const AOnRefresh: TMutableStudioRefreshCallback);
  end;

implementation

constructor TMutableStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TMutableStudioModifiedCallback;
  const AOnRefresh: TMutableStudioRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FRollSeed := 20260360;
  Caption := 'Mutable Modular Character Customizer, Morphs & Recipe Studio (Phase 360)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TMutableStudioForm.BuildUi;
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
  Lbl.Caption := 'UE 6.0+ Mutable (UCustomizableObject) — Modular Equipment Slots, Helm-Clips-Hair Exclusion, Body Morphs & Recipe Codes';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 40;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn Modular Hero Pedestal', @BtnSpawnClick);
  MakeBtn(Row1, 'Archetype: Paladin Knight', @BtnPaladinClick);
  MakeBtn(Row1, 'Archetype: Ranger Scout', @BtnRangerClick);
  MakeBtn(Row1, 'Archetype: Arcane Battle-Mage', @BtnMageClick);
  MakeBtn(Row1, 'Copy Recipe Code', @BtnCopyRecipeClick);

  Row2 := TPanel.Create(Self);
  Row2.Parent := Self;
  Row2.Align := alTop;
  Row2.Height := 40;
  Row2.BevelOuter := bvNone;
  MakeBtn(Row2, 'Cycle Headgear (Test Closed-Helm Hair Clip)', @BtnCycleHelmClick);
  MakeBtn(Row2, 'Morph: Towering Titan (1.20x + Max Bulk)', @BtnTitanMorphClick);
  MakeBtn(Row2, 'Seeded Randomize Loadout', @BtnRandomizeClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintSilhouette := TPaintBox.Create(Self);
  FPaintSilhouette.Parent := BodyPanel;
  FPaintSilhouette.Align := alLeft;
  FPaintSilhouette.Width := 440;
  FPaintSilhouette.OnPaint := @PaintSilhouette;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TMutableStudioForm.ActiveHero: TCastleMutableCharacter;
begin
  Result := TMutableStudioHelper.FindMutableInHierarchy(FDesignRoot);
end;

procedure TMutableStudioForm.NotifyChange(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TMutableStudioForm.RefreshView;
begin
  FMemoReport.Lines.Text := TMutableStudioHelper.GenerateMutableReport(ActiveHero);
  FPaintSilhouette.Invalidate;
end;

procedure TMutableStudioForm.BtnSpawnClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  if TMutableStudioHelper.SpawnMutableTurntablePedestal(FDesignRoot, FDesignOwner, H) then
    NotifyChange('Spawn Mutable Modular Hero Pedestal');
end;

procedure TMutableStudioForm.BtnPaladinClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H = nil then Exit;
  H.Preset := mapPaladinPlateKnight;
  NotifyChange('Switch Mutable Hero to Paladin Plate Knight');
end;

procedure TMutableStudioForm.BtnRangerClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H = nil then Exit;
  H.Preset := mapRangerHoodedScout;
  NotifyChange('Switch Mutable Hero to Ranger Hooded Scout');
end;

procedure TMutableStudioForm.BtnMageClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H = nil then Exit;
  H.Preset := mapArcaneBattleMage;
  NotifyChange('Switch Mutable Hero to Arcane Battle-Mage');
end;

procedure TMutableStudioForm.BtnCycleHelmClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H = nil then Exit;
  H.HeadgearSlot := (H.HeadgearSlot + 1) mod 4;
  NotifyChange('Cycle Mutable Headgear Slot');
end;

procedure TMutableStudioForm.BtnTitanMorphClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H = nil then Exit;
  H.HeightScale := 1.20;
  H.ShoulderBulkMorph := 1.00;
  H.BuildMuscularityMorph := 1.00;
  NotifyChange('Apply Towering Titan Body Morphs');
end;

procedure TMutableStudioForm.BtnRandomizeClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H = nil then Exit;
  Inc(FRollSeed, 137);
  H.RandomizeCharacter(FRollSeed);
  NotifyChange('Randomize Mutable Character Loadout');
end;

procedure TMutableStudioForm.BtnCopyRecipeClick(Sender: TObject);
var
  H: TCastleMutableCharacter;
begin
  H := ActiveHero;
  if H <> nil then
    Clipboard.AsText := H.ExportRecipeCode;
end;

procedure TMutableStudioForm.PaintSilhouette(Sender: TObject);
var
  Cv: TCanvas;
  W, H, CX, BaseY, TopY, HalfShoulderPx: Integer;
  Hero: TCastleMutableCharacter;
begin
  Cv := FPaintSilhouette.Canvas;
  W := FPaintSilhouette.Width;
  H := FPaintSilhouette.Height;
  Cv.Brush.Color := RGBToColor(22, 26, 34);
  Cv.FillRect(0, 0, W, H);

  Hero := ActiveHero;
  if Hero = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn Modular Hero Pedestal" to inspect Proportion Silhouette.');
    Exit;
  end;

  CX := W div 2;
  BaseY := H - 48;
  TopY := BaseY - Round(Hero.TotalBoundsHeightMeters * 175.0);
  HalfShoulderPx := Round(Hero.ShoulderSpanMeters * 95.0);

  Cv.Brush.Color := RGBToColor(
    EnsureRange(Round(Hero.PrimaryArmorRGB.X * 255), 0, 255),
    EnsureRange(Round(Hero.PrimaryArmorRGB.Y * 255), 0, 255),
    EnsureRange(Round(Hero.PrimaryArmorRGB.Z * 255), 0, 255));
  Cv.Rectangle(CX - HalfShoulderPx, TopY + 55, CX + HalfShoulderPx, BaseY - 95);
  Cv.Ellipse(CX - 28, TopY, CX + 28, TopY + 56);
  Cv.Rectangle(CX - 36, BaseY - 95, CX - 8, BaseY);
  Cv.Rectangle(CX + 8, BaseY - 95, CX + 36, BaseY);

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(12, 10, Format('%s | %d parts (%d tris)', [
    Hero.ExportRecipeCode, Hero.MergedPartCount, Hero.GeneratedTriangleCount]));
end;

end.
