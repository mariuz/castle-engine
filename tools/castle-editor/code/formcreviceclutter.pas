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

{ Visual Studio dialog for Wall-Crevice & Seam Micro-Clutter Skirt (Phase 370). }
unit FormCreviceClutter;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleViewport, CastleCreviceClutter, ToolCreviceClutter;

type
  TCreviceClutterModifiedCallback = procedure(const UndoComment: String) of object;
  TCreviceClutterRefreshCallback = procedure of object;

  TCreviceClutterForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TCreviceClutterModifiedCallback;
    FOnRefresh: TCreviceClutterRefreshCallback;
    FPaintMap: TPaintBox;
    FMemoReport: TMemo;
    procedure BuildUi;
    function ActiveVolume: TCastleCreviceClutterVolume;
    procedure RebakeAndNotify(const AComment: String);
    procedure RefreshView;
    procedure BtnSpawnClick(Sender: TObject);
    procedure BtnRubbleClick(Sender: TObject);
    procedure BtnLeavesClick(Sender: TObject);
    procedure BtnMossClick(Sender: TObject);
    procedure BtnReseedClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintCreviceMap(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent; const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TCreviceClutterModifiedCallback;
      const AOnRefresh: TCreviceClutterRefreshCallback);
  end;

implementation

constructor TCreviceClutterForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TCreviceClutterModifiedCallback;
  const AOnRefresh: TCreviceClutterRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Wall-Crevice & Seam Micro-Clutter Skirt Studio (Phase 370)';
  Width := 980;
  Height := 640;
  Position := poScreenCenter;
  BuildUi;
  RefreshView;
end;

procedure TCreviceClutterForm.BuildUi;
var
  Lbl: TLabel;
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
  Lbl := TLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.Align := alTop;
  Lbl.BorderSpacing.Around := 8;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'UE 6.0+ PCG Crevice Clutter — 8-Compass WorldRay Wall-Floor Seam Detection, L-Corner Pileup & Open-Floor Cleanliness';

  Row1 := TPanel.Create(Self);
  Row1.Parent := Self;
  Row1.Align := alTop;
  Row1.Height := 42;
  Row1.BevelOuter := bvNone;
  MakeBtn(Row1, '+ Spawn L-Wall Courtyard & Bake Skirt', @BtnSpawnClick);
  MakeBtn(Row1, 'Stone Rubble', @BtnRubbleClick);
  MakeBtn(Row1, 'Autumn Leaves', @BtnLeavesClick);
  MakeBtn(Row1, 'Mossy Pebbles', @BtnMossClick);
  MakeBtn(Row1, 'Randomize Seed & Rebake', @BtnReseedClick);
  MakeBtn(Row1, 'Copy Markdown Report', @BtnCopyReportClick);

  BodyPanel := TPanel.Create(Self);
  BodyPanel.Parent := Self;
  BodyPanel.Align := alClient;
  BodyPanel.BevelOuter := bvNone;

  FPaintMap := TPaintBox.Create(Self);
  FPaintMap.Parent := BodyPanel;
  FPaintMap.Align := alLeft;
  FPaintMap.Width := 480;
  FPaintMap.OnPaint := @PaintCreviceMap;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := BodyPanel;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssAutoBoth;
  FMemoReport.Font.Name := 'Monospace';
end;

function TCreviceClutterForm.ActiveVolume: TCastleCreviceClutterVolume;
begin
  Result := TCreviceClutterHelper.FindClutterVolumeInHierarchy(FDesignRoot);
end;

procedure TCreviceClutterForm.RebakeAndNotify(const AComment: String);
var
  V: TCastleCreviceClutterVolume;
  Vp: TCastleViewport;
begin
  V := ActiveVolume;
  Vp := TCreviceClutterHelper.FindViewport(FDesignRoot);
  if (V <> nil) and (Vp <> nil) then
    V.BakeCreviceClutterFromWorld(Vp.Items);
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TCreviceClutterForm.RefreshView;
begin
  FMemoReport.Lines.Text := TCreviceClutterHelper.GenerateCreviceReport(ActiveVolume);
  FPaintMap.Invalidate;
end;

procedure TCreviceClutterForm.BtnSpawnClick(Sender: TObject);
var
  V: TCastleCreviceClutterVolume;
begin
  if TCreviceClutterHelper.SpawnCourtyardLWallDemo(FDesignRoot, FDesignOwner, V) then
    RebakeAndNotify('Spawn Courtyard L-Wall & Bake Crevice Clutter');
end;

procedure TCreviceClutterForm.BtnRubbleClick(Sender: TObject);
var
  V: TCastleCreviceClutterVolume;
begin
  V := ActiveVolume;
  if V = nil then Exit;
  V.Preset := ccpStoneMortarRubble;
  RebakeAndNotify('Switch Crevice Clutter to Stone Rubble');
end;

procedure TCreviceClutterForm.BtnLeavesClick(Sender: TObject);
var
  V: TCastleCreviceClutterVolume;
begin
  V := ActiveVolume;
  if V = nil then Exit;
  V.Preset := ccpAutumnWindblownLeaves;
  RebakeAndNotify('Switch Crevice Clutter to Autumn Leaves');
end;

procedure TCreviceClutterForm.BtnMossClick(Sender: TObject);
var
  V: TCastleCreviceClutterVolume;
begin
  V := ActiveVolume;
  if V = nil then Exit;
  V.Preset := ccpMossyDungeonPebbles;
  RebakeAndNotify('Switch Crevice Clutter to Mossy Pebbles');
end;

procedure TCreviceClutterForm.BtnReseedClick(Sender: TObject);
var
  V: TCastleCreviceClutterVolume;
begin
  V := ActiveVolume;
  if V = nil then Exit;
  V.RandomSeed := V.RandomSeed + 137;
  RebakeAndNotify('Randomize Crevice Clutter Seed');
end;

procedure TCreviceClutterForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TCreviceClutterHelper.GenerateCreviceReport(ActiveVolume);
end;

procedure TCreviceClutterForm.PaintCreviceMap(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I, PX, PY, R: Integer;
  V: TCastleCreviceClutterVolume;
  Item: TCreviceClutterItem;
  HalfExt: Single;
begin
  Cv := FPaintMap.Canvas;
  W := FPaintMap.Width;
  H := FPaintMap.Height;
  Cv.Brush.Color := RGBToColor(22, 24, 28);
  Cv.FillRect(0, 0, W, H);

  V := ActiveVolume;
  if V = nil then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(16, 22, 'Click "+ Spawn L-Wall Courtyard & Bake Skirt" to inspect XZ Seam Scatter.');
    Exit;
  end;

  HalfExt := Max(1.0, V.VolumeExtentXZ * 0.5);
  for I := 0 to V.ClutterCount - 1 do
  begin
    Item := V.GetClutterItem(I);
    PX := Round(W * 0.50 + (Item.WorldPos.X / HalfExt) * (W * 0.40));
    PY := Round(H * 0.52 + (Item.WorldPos.Z / HalfExt) * (H * 0.40));
    R := Max(3, Round(Item.RadiusMeters * 26));
    if Item.IsInsideCorner then
      Cv.Brush.Color := RGBToColor(250, 200, 75)
    else
      Cv.Brush.Color := RGBToColor(155, 195, 130);
    Cv.Ellipse(PX - R, PY - R, PX + R, PY + R);
  end;

  Cv.Brush.Style := bsClear;
  Cv.Font.Color := clWhite;
  Cv.TextOut(14, 12, Format('XZ Crevice Skirt Map | %d Items (%d L-Corner) | Open Center = 0', [
    V.ClutterCount, V.InsideCornerItemCount]));
end;

end.
