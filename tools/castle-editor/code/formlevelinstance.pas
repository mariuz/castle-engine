{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Level Instances, Packed Level Actors & One-File-Per-Actor
  (OFPA) Studio dialog featuring a Level Instance & Packed ISM Top-Down Outliner
  Canvas, In-Place Edit / Commit / Discard / Break controls, and an OFPA
  __ExternalActors__ FNV-1a Bucket & Git Merge Inspector
  (Phase 390 — 110 UE Studios / 33 MCP). }
unit FormLevelInstance;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleLevelInstance, ToolLevelInstance;

type
  TLevelInstModifiedCallback = procedure(const UndoComment: String) of object;
  TLevelInstRefreshCallback = procedure of object;

  TLevelInstanceForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TLevelInstModifiedCallback;
    FOnRefresh: TLevelInstRefreshCallback;

    FActiveLi: TCastleLevelInstance;
    FOfpaFiles: TOfpaActorFileEntryArray;

    FLblStatus: TLabel;
    FPaintAssembly: TPaintBox;
    FPaintOfpa: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintAssemblyCanvas(Sender: TObject);
    procedure PaintOfpaManifestCanvas(Sender: TObject);

    procedure BtnSpawnTowerClick(Sender: TObject);
    procedure BtnSpawnStreetClick(Sender: TObject);
    procedure BtnEditInPlaceClick(Sender: TObject);
    procedure BtnCommitSyncClick(Sender: TObject);
    procedure BtnDiscardClick(Sender: TObject);
    procedure BtnBreakActorsClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TLevelInstModifiedCallback;
      const AOnRefresh: TLevelInstRefreshCallback);
  end;

implementation

constructor TLevelInstanceForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TLevelInstModifiedCallback;
  const AOnRefresh: TLevelInstRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Level Instances, Packed Level Actors & One-File-Per-Actor (OFPA) Studio (110 UE Studios / 33 MCP)';
  Position := poScreenCenter;
  Width := 1280;
  Height := 720;

  BuildUi;
  FActiveLi := TLevelInstanceHelper.FindFirstLevelInstance(FDesignRoot);
  RefreshFromScene;
end;

procedure TLevelInstanceForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom: TPanel;
  BtnTower, BtnStreet, BtnEdit, BtnCommit, BtnDisc, BtnBreak, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 8;
  FLblStatus.Caption := 'Level Instances, Packed Level Actors & OFPA Studio Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnTower := TButton.Create(Self);
  BtnTower.Parent := PnlToolbar;
  BtnTower.SetBounds(8, 6, 178, 30);
  BtnTower.Caption := '+ Watchtower LevelInst';
  BtnTower.OnClick := @BtnSpawnTowerClick;

  BtnStreet := TButton.Create(Self);
  BtnStreet.Parent := PnlToolbar;
  BtnStreet.SetBounds(190, 6, 178, 30);
  BtnStreet.Caption := '+ Cyber Street LevelInst';
  BtnStreet.OnClick := @BtnSpawnStreetClick;

  BtnEdit := TButton.Create(Self);
  BtnEdit.Parent := PnlToolbar;
  BtnEdit.SetBounds(372, 6, 138, 30);
  BtnEdit.Caption := 'Edit In-Place';
  BtnEdit.OnClick := @BtnEditInPlaceClick;

  BtnCommit := TButton.Create(Self);
  BtnCommit.Parent := PnlToolbar;
  BtnCommit.SetBounds(514, 6, 172, 30);
  BtnCommit.Caption := 'Commit + Sync Siblings';
  BtnCommit.OnClick := @BtnCommitSyncClick;

  BtnDisc := TButton.Create(Self);
  BtnDisc.Parent := PnlToolbar;
  BtnDisc.SetBounds(690, 6, 128, 30);
  BtnDisc.Caption := 'Discard Edits';
  BtnDisc.OnClick := @BtnDiscardClick;

  BtnBreak := TButton.Create(Self);
  BtnBreak.Parent := PnlToolbar;
  BtnBreak.SetBounds(822, 6, 148, 30);
  BtnBreak.Caption := 'Break Into Scene';
  BtnBreak.OnClick := @BtnBreakActorsClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(974, 6, 128, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 136;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.ReadOnly := True;
  FMemoReport.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 520;
  PnlRight.BevelOuter := bvLowered;

  FPaintOfpa := TPaintBox.Create(Self);
  FPaintOfpa.Parent := PnlRight;
  FPaintOfpa.Align := alClient;
  FPaintOfpa.OnPaint := @PaintOfpaManifestCanvas;

  FPaintAssembly := TPaintBox.Create(Self);
  FPaintAssembly.Parent := Self;
  FPaintAssembly.Align := alClient;
  FPaintAssembly.OnPaint := @PaintAssemblyCanvas;
end;

procedure TLevelInstanceForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TLevelInstanceForm.RefreshFromScene;
begin
  if (FActiveLi = nil) and (FDesignRoot <> nil) then
    FActiveLi := TLevelInstanceHelper.FindFirstLevelInstance(FDesignRoot);

  FOfpaFiles := TLevelInstanceHelper.ExportDesignToOfpaRepo(FDesignRoot);

  if FActiveLi <> nil then
    FLblStatus.Caption := FActiveLi.Name + '  ' + FActiveLi.LevelInstanceSummaryBadge +
      Format('  OFPA Files=%d', [Length(FOfpaFiles)])
  else
    FLblStatus.Caption := Format('OFPA External Actor Files=%d — click "+ Watchtower LevelInst".',
      [Length(FOfpaFiles)]);

  FMemoReport.Text := TLevelInstanceHelper.GenerateMarkdownReport(FDesignRoot, FActiveLi);
  FPaintAssembly.Invalidate;
  FPaintOfpa.Invalidate;
end;

procedure TLevelInstanceForm.PaintAssemblyCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, I, RX, RY, RW, RH, YBatch: Integer;
  ScalePx: Single;
  S: TLevelInstanceSubActor;
begin
  C := FPaintAssembly.Canvas;
  W := FPaintAssembly.Width;
  H := FPaintAssembly.Height;

  C.Brush.Color := RGBToColor(18, 20, 26);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(148, 206, 255);
  C.TextOut(14, 10, 'Level Instance Footprint & Packed ISM Batch Consolidator');

  if FActiveLi = nil then Exit;

  CX := W div 2;
  CY := (H div 2) - 24;
  ScalePx := 42.0;

  for I := 0 to High(FActiveLi.SubActors) do
  begin
    S := FActiveLi.SubActors[I];
    RX := CX + Round(S.LocalPos.X * ScalePx);
    RY := CY - Round(S.LocalPos.Z * ScalePx);
    if Abs(Sin(DegToRad(S.YawDeg))) > 0.7 then
    begin
      RW := Max(8, Round(S.LocalSize.Z * ScalePx * 0.5));
      RH := Max(8, Round(S.LocalSize.X * ScalePx * 0.5));
    end else
    begin
      RW := Max(8, Round(S.LocalSize.X * ScalePx * 0.5));
      RH := Max(8, Round(S.LocalSize.Z * ScalePx * 0.5));
    end;

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(
      EnsureRange(Round(S.ColorRGBA.X * 210), 0, 255),
      EnsureRange(Round(S.ColorRGBA.Y * 210), 0, 255),
      EnsureRange(Round(S.ColorRGBA.Z * 210), 0, 255));
    if FActiveLi.EditMode = limEditingInPlace then
      C.Pen.Color := RGBToColor(255, 212, 72)
    else
      C.Pen.Color := RGBToColor(196, 224, 255);
    C.Rectangle(RX - RW, RY - RH, RX + RW, RY + RH);
  end;

  { Packed ISM Batch Cards along bottom of viewport }
  YBatch := H - 118;
  for I := 0 to High(FActiveLi.PackedBatches) do
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(32, 42, 56);
    C.Pen.Color := RGBToColor(86, 178, 248);
    C.RoundRect(16, YBatch, W - 16, YBatch + 28, 6, 6);
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(225, 238, 255);
    C.TextOut(26, YBatch + 6, Format('Packed ISM Batch: %s   (%d GPU instances -> 1 draw call)',
      [FActiveLi.PackedBatches[I].MeshTag, FActiveLi.PackedBatches[I].InstanceCount]));
    Inc(YBatch, 32);
  end;
end;

procedure TLevelInstanceForm.PaintOfpaManifestCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, YRow, I: Integer;
begin
  C := FPaintOfpa.Canvas;
  W := FPaintOfpa.Width;
  H := FPaintOfpa.Height;

  C.Brush.Color := RGBToColor(24, 26, 32);
  C.FillRect(0, 0, W, H);

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(36, 42, 54);
  C.FillRect(0, 0, W, 30);
  C.Brush.Style := bsClear;
  C.Font.Color := clWhite;
  C.TextOut(12, 7, 'One-File-Per-Actor (OFPA) __ExternalActors__ Manifest');

  YRow := 38;
  for I := 0 to High(FOfpaFiles) do
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(34, 38, 46);
    C.Pen.Color := RGBToColor(20, 22, 26);
    C.Rectangle(8, YRow, W - 8, YRow + 48);

    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(112, 236, 152);
    C.TextOut(16, YRow + 6, FOfpaFiles[I].ActorName + '   [FNV1a #' + FOfpaFiles[I].ContentHashHex + ']');
    C.Font.Color := RGBToColor(162, 198, 242);
    C.TextOut(16, YRow + 26, FOfpaFiles[I].RelativeOfpaPath);

    Inc(YRow, 54);
    if YRow > H - 48 then Break;
  end;
end;

procedure TLevelInstanceForm.BtnSpawnTowerClick(Sender: TObject);
begin
  FActiveLi := TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
    FDesignRoot, FDesignOwner, lipMedievalWatchtower10Actors, Vector3(0, 0, 0));
  NotifyChanged('Spawn Watchtower Level Instance');
end;

procedure TLevelInstanceForm.BtnSpawnStreetClick(Sender: TObject);
begin
  FActiveLi := TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
    FDesignRoot, FDesignOwner, lipCyberpunkStreetBlock12Actors, Vector3(14, 0, 0));
  NotifyChanged('Spawn Cyber Street Level Instance');
end;

procedure TLevelInstanceForm.BtnEditInPlaceClick(Sender: TObject);
begin
  if FActiveLi = nil then Exit;
  FActiveLi.BeginEditInPlace;
  RefreshFromScene;
end;

procedure TLevelInstanceForm.BtnCommitSyncClick(Sender: TObject);
begin
  if FActiveLi = nil then Exit;
  if FActiveLi.CommitInPlaceEdits then
  begin
    TLevelInstanceHelper.SyncSiblingInstancesInDesign(FDesignRoot, FActiveLi);
    NotifyChanged('Commit Level Instance & Sync Sibling Archetypes');
  end;
end;

procedure TLevelInstanceForm.BtnDiscardClick(Sender: TObject);
begin
  if FActiveLi = nil then Exit;
  FActiveLi.DiscardInPlaceEdits;
  RefreshFromScene;
end;

procedure TLevelInstanceForm.BtnBreakActorsClick(Sender: TObject);
var
  ParentT: TCastleTransform;
begin
  if FActiveLi = nil then Exit;
  ParentT := TLevelInstanceHelper.FindParentViewportItems(FDesignRoot);
  if ParentT <> nil then
  begin
    FActiveLi.BreakIntoWorldActors(ParentT, FDesignOwner);
    NotifyChanged('Break Level Instance Into Standalone Actors');
  end;
end;

procedure TLevelInstanceForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Text;
end;

end.
