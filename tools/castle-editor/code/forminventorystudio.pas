{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Interactive RPG Inventory Grid, Paperdoll-to-GAS Equipment Bonus Sync,
  Atomic Crafting & Weighted/Pity Loot Table Studio (@link(TInventoryStudioForm))
  featuring a 1-click RPG Adventurer + Loot Chest spawner, Craft / Equip /
  Loot Roll / 50x Monte Carlo buttons, a live Bag Slot Grid + Paperdoll +
  Rarity Distribution canvas, and Markdown export (Phase 320). }
unit FormInventoryStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleTransform, CastleGameplayAbility,
  CastleInventoryCraft, ToolInventoryStudio;

type
  TInventoryStudioModifiedCallback = procedure(const AComment: String) of object;
  TInventoryStudioRefreshViewportCallback = procedure of object;

  TInventoryStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TInventoryStudioModifiedCallback;
    FOnRefreshViewport: TInventoryStudioRefreshViewportCallback;

    FInvs: TInventoryBehaviorArray;
    FLoots: TLootTableArray;
    FLastHist: TRarityHistogram;
    FReport: TInventoryAuditReport;

    LblHeader: TLabel;
    ListBag: TListBox;
    PaintBoard: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function ActiveInv: TCastleInventoryBehavior;
    function ActiveLoot: TCastleLootTable;
    procedure RefreshAll;
    procedure NotifyChanged(const AComment: String);

    procedure BtnSpawnHeroDemoClick(Sender: TObject);
    procedure BtnGrantCraftingMatsClick(Sender: TObject);
    procedure BtnCraftSunfireClick(Sender: TObject);
    procedure BtnEquipSelectedOrSunfireClick(Sender: TObject);
    procedure BtnRollLootOnceClick(Sender: TObject);
    procedure BtnMonteCarlo50Click(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintBoardPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TInventoryStudioModifiedCallback;
      const AOnRefreshViewport: TInventoryStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TInventoryStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TInventoryStudioModifiedCallback;
  const AOnRefreshViewport: TInventoryStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'RPG Inventory Grid, Equipment Paperdoll GAS Bonuses, Crafting & Loot Studio';
  Width := 1140;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TInventoryStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TInventoryStudioForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.SetBounds(12, 8, 1080, 20);
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'RPG Inventory & Loot Tables: scanning...';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 34, 1120, 32);
  RowTop.BevelOuter := bvNone;
  MakeBtn(RowTop, '+ Spawn RPG Hero + Loot Table', 4, 2, 205, @BtnSpawnHeroDemoClick);
  MakeBtn(RowTop, '+ Crafting Mats', 214, 2, 125, @BtnGrantCraftingMatsClick);
  MakeBtn(RowTop, 'Craft Sunfire Blade!', 344, 2, 160, @BtnCraftSunfireClick);
  MakeBtn(RowTop, 'Equip Selected / Blade', 509, 2, 170, @BtnEquipSelectedOrSunfireClick);
  MakeBtn(RowTop, 'Roll Chest -> Bag', 684, 2, 140, @BtnRollLootOnceClick);
  MakeBtn(RowTop, '50x Loot Sim', 829, 2, 115, @BtnMonteCarlo50Click);
  MakeBtn(RowTop, 'Copy Markdown', 949, 2, 130, @BtnCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PanelBottom;
  BtnClose.Caption := 'Close';
  BtnClose.Width := 110;
  BtnClose.Height := 28;
  BtnClose.Top := 7;
  BtnClose.Left := Width - 130;
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.OnClick := @BtnCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Bag Slots (Select item to Equip):';

  ListBag := TListBox.Create(Self);
  ListBag.Parent := PanelLeft;
  ListBag.SetBounds(10, 26, 320, 235);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 268, 310, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Equipped Paperdoll, GAS Stats & QA:';

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelLeft;
  MemoDiag.SetBounds(10, 290, 320, 280);
  MemoDiag.Anchors := [akTop, akLeft, akBottom];
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintBoard := TPaintBox.Create(Self);
  PaintBoard.Parent := PanelCenter;
  PaintBoard.Align := alClient;
  PaintBoard.OnPaint := @PaintBoardPaint;
end;

function TInventoryStudioForm.ActiveInv: TCastleInventoryBehavior;
begin
  if Length(FInvs) > 0 then
    Result := FInvs[0]
  else
    Result := nil;
end;

function TInventoryStudioForm.ActiveLoot: TCastleLootTable;
begin
  if Length(FLoots) > 0 then
    Result := FLoots[0]
  else
    Result := nil;
end;

procedure TInventoryStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TInventoryStudioForm.RefreshAll;
var
  Inv: TCastleInventoryBehavior;
  Gas: TCastleAbilitySystemBehavior;
  SlotStack: TInventorySlotStack;
  S: TEquipmentSlot;
  I: Integer;
begin
  TInventoryStudioHelper.ScanInventoriesAndLoot(FDesignRoot, FDesignOwner, FInvs, FLoots);
  FreeAndNil(FReport);
  FReport := TInventoryStudioHelper.AuditInventories(FDesignRoot, FDesignOwner);

  LblHeader.Caption := Format(
    'Inventories: %d (%d occupied slots)  |  Loot Tables: %d  |  QA Warnings: %d',
    [FReport.InventoryCount, FReport.TotalOccupiedSlots, FReport.LootTableCount,
     FReport.Warnings.Count]);

  Inv := ActiveInv;
  ListBag.Items.BeginUpdate;
  try
    ListBag.Items.Clear;
    if Inv <> nil then
      for I := 0 to Inv.UsedSlotCount - 1 do
      begin
        SlotStack := Inv.GetBagSlot(I);
        ListBag.Items.Add(Format('[Slot %d] %s  x%d', [I + 1, SlotStack.ItemId, SlotStack.Quantity]));
      end;
  finally
    ListBag.Items.EndUpdate;
  end;

  MemoDiag.Lines.BeginUpdate;
  try
    MemoDiag.Lines.Clear;
    if Inv <> nil then
    begin
      MemoDiag.Lines.Add(Inv.InventorySummaryBadge);
      for S in TEquipmentSlot do
        if S <> esNone then
          MemoDiag.Lines.Add(Format('  %s: %s', [
            TCastleInventoryBehavior.SlotDisplayName(S),
            IfThen(Inv.EquippedItemInSlot(S) <> '', Inv.EquippedItemInSlot(S), '<empty>')]));
      if (Inv.Parent <> nil) and (Inv.Parent.FindBehavior(TCastleAbilitySystemBehavior) <> nil) then
      begin
        Gas := TCastleAbilitySystemBehavior(Inv.Parent.FindBehavior(TCastleAbilitySystemBehavior));
        MemoDiag.Lines.Add('');
        MemoDiag.Lines.Add(Format('GAS AttackPower: %.1f (Base %.1f)',
          [Gas.GetCurrentValue('AttackPower'), Gas.GetBaseValue('AttackPower')]));
        MemoDiag.Lines.Add(Format('GAS MaxHealth:   %.1f (Base %.1f)',
          [Gas.GetCurrentValue('MaxHealth'), Gas.GetBaseValue('MaxHealth')]));
      end;
      MemoDiag.Lines.Add('');
    end;
    if FReport.Warnings.Count = 0 then
      MemoDiag.Lines.Add('[OK] All inventory recipes & loot tables valid.')
    else
      for I := 0 to FReport.Warnings.Count - 1 do
        MemoDiag.Lines.Add('[WARN] ' + FReport.Warnings[I]);
  finally
    MemoDiag.Lines.EndUpdate;
  end;

  PaintBoard.Invalidate;
end;

procedure TInventoryStudioForm.BtnSpawnHeroDemoClick(Sender: TObject);
var
  H: TCastleTransform;
  G: TCastleAbilitySystemBehavior;
  Inv: TCastleInventoryBehavior;
  Lt: TCastleLootTable;
begin
  TInventoryStudioHelper.SpawnRpgHeroInventoryAndLootChestDemo(
    FDesignRoot, FDesignOwner, H, G, Inv, Lt);
  NotifyChanged('Spawn RPG Hero Inventory + GAS + Loot Table');
end;

procedure TInventoryStudioForm.BtnGrantCraftingMatsClick(Sender: TObject);
var
  Inv: TCastleInventoryBehavior;
begin
  Inv := ActiveInv;
  if Inv = nil then Exit;
  Inv.TryAddItem('IronOre', 3);
  Inv.TryAddItem('CrystalShard', 2);
  NotifyChanged('Grant Crafting Materials');
end;

procedure TInventoryStudioForm.BtnCraftSunfireClick(Sender: TObject);
var
  Inv: TCastleInventoryBehavior;
  Reason: String;
begin
  Inv := ActiveInv;
  if Inv = nil then Exit;
  Inv.TryCraftRecipe('CraftSunfireBlade', Reason);
  NotifyChanged('Craft Sunfire Greatsword');
end;

procedure TInventoryStudioForm.BtnEquipSelectedOrSunfireClick(Sender: TObject);
var
  Inv: TCastleInventoryBehavior;
  Idx: Integer;
  Reason: String;
begin
  Inv := ActiveInv;
  if Inv = nil then Exit;
  Idx := ListBag.ItemIndex;
  if (Idx >= 0) and (Idx < Inv.UsedSlotCount) then
    Inv.EquipItemFromBag(Inv.GetBagSlot(Idx).ItemId, Reason)
  else
    Inv.EquipItemFromBag('SunfireBlade', Reason);
  NotifyChanged('Equip RPG Item into Paperdoll');
end;

procedure TInventoryStudioForm.BtnRollLootOnceClick(Sender: TObject);
var
  Inv: TCastleInventoryBehavior;
  Lt: TCastleLootTable;
  ItemId: String;
  Qty: Integer;
  Rar: TItemRarity;
begin
  Inv := ActiveInv;
  Lt := ActiveLoot;
  if (Inv = nil) or (Lt = nil) then Exit;
  if Lt.RollIntoInventory(Inv, ItemId, Qty, Rar) then
    Inc(FLastHist[Rar]);
  NotifyChanged('Roll Loot Table Into Bag');
end;

procedure TInventoryStudioForm.BtnMonteCarlo50Click(Sender: TObject);
var
  Lt: TCastleLootTable;
begin
  Lt := ActiveLoot;
  if Lt = nil then Exit;
  TInventoryStudioHelper.RunMonteCarloLootSimulation(Lt, 50, FLastHist);
  RefreshAll;
end;

procedure TInventoryStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TInventoryStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TInventoryStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

procedure TInventoryStudioForm.PaintBoardPaint(Sender: TObject);
var
  C: TCanvas;
  Inv: TCastleInventoryBehavior;
  W, H, Col, Row, CellX, CellY, SlotIdx, MaxCount, BarW: Integer;
  SlotStack: TInventorySlotStack;
  R: TItemRarity;
begin
  C := PaintBoard.Canvas;
  W := Max(200, PaintBoard.Width);
  H := Max(200, PaintBoard.Height);
  C.Brush.Color := RGBToColor(22, 26, 33);
  C.FillRect(0, 0, W, H);

  Inv := ActiveInv;
  if Inv = nil then
  begin
    C.Font.Color := RGBToColor(190, 202, 218);
    C.TextOut(24, 24, 'Click "+ Spawn RPG Hero + Loot Table" to inspect bag grid, paperdoll & rarity drops.');
    Exit;
  end;

  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(20, 14, Format('Inventory Slot Grid (%d / %d slots, %.1f / %.0f kg)',
    [Inv.UsedSlotCount, Inv.MaxSlots, Inv.CurrentCarryWeightKg, Inv.MaxCarryWeightKg]));
  C.Font.Style := [];

  { 5x4 Bag Slot Grid }
  for SlotIdx := 0 to Min(19, Inv.MaxSlots - 1) do
  begin
    Col := SlotIdx mod 5;
    Row := SlotIdx div 5;
    CellX := 20 + Col * 136;
    CellY := 42 + Row * 66;
    if SlotIdx < Inv.UsedSlotCount then
    begin
      SlotStack := Inv.GetBagSlot(SlotIdx);
      C.Brush.Color := RGBToColor(44, 62, 86);
      C.Pen.Color := RGBToColor(110, 175, 240);
      C.RoundRect(CellX, CellY, CellX + 128, CellY + 58, 8, 8);
      C.Brush.Style := bsClear;
      C.Font.Color := RGBToColor(235, 242, 252);
      C.TextOut(CellX + 8, CellY + 10, Copy(SlotStack.ItemId, 1, 14));
      C.Font.Color := RGBToColor(250, 210, 82);
      C.TextOut(CellX + 8, CellY + 32, Format('x%d', [SlotStack.Quantity]));
    end else
    begin
      C.Brush.Color := RGBToColor(30, 35, 44);
      C.Pen.Color := RGBToColor(62, 70, 84);
      C.RoundRect(CellX, CellY, CellX + 128, CellY + 58, 8, 8);
    end;
  end;

  { Rarity Histogram }
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(232, 240, 250);
  C.TextOut(20, 326, 'Loot Roll Rarity Distribution (Pity-Protected)');
  C.Font.Style := [];

  MaxCount := 1;
  for R in TItemRarity do
    MaxCount := Max(MaxCount, FLastHist[R]);

  for R in TItemRarity do
  begin
    CellY := 356 + Ord(R) * 34;
    C.Brush.Style := bsClear;
    C.Font.Color := RGBToColor(210, 220, 236);
    C.TextOut(20, CellY + 4, TCastleInventoryBehavior.RarityDisplayName(R));
    BarW := Round((FLastHist[R] / MaxCount) * (W - 220));
    case R of
      irCommon:    C.Brush.Color := RGBToColor(150, 160, 172);
      irUncommon:  C.Brush.Color := RGBToColor(68, 210, 122);
      irRare:      C.Brush.Color := RGBToColor(64, 160, 250);
      irEpic:      C.Brush.Color := RGBToColor(186, 98, 248);
      irLegendary: C.Brush.Color := RGBToColor(250, 184, 48);
    end;
    C.FillRect(120, CellY, 120 + Max(4, BarW), CellY + 24);
    C.Brush.Style := bsClear;
    C.TextOut(130 + Max(4, BarW), CellY + 4, IntToStr(FLastHist[R]));
  end;
end;

end.
