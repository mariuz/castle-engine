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

{ Automated unit tests for Phase 320 RPG Inventory Grid, Paperdoll-to-GAS
  Attribute Modifier Sync, Atomic Crafting & Pity-Protected Loot Table Studio
  (@link(TCastleInventoryBehavior), @link(TCastleLootTable),
  @link(TInventoryStudioHelper)). }
unit TestToolInventoryStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolInventoryStudio = class(TCastleTestCase)
  published
    procedure TestStackingWeightCapAtomicCraftingAndPaperdollGasAttributeSync;
    procedure TestWeightedLootTableSeededDeterminismAndLegendaryPityGuarantee;
  end;

implementation

uses
  CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleGameplayAbility, CastleInventoryCraft, ToolInventoryStudio;

procedure TTestToolInventoryStudio.TestStackingWeightCapAtomicCraftingAndPaperdollGasAttributeSync;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Hero: TCastleTransform;
  Gas: TCastleAbilitySystemBehavior;
  Inv, LoadedInv: TCastleInventoryBehavior;
  Loot: TCastleLootTable;
  Reason, JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TInventoryStudioHelper.SpawnRpgHeroInventoryAndLootChestDemo(
      Vp, OwnerComp, Hero, Gas, Inv, Loot);

    { 1. Stack merging: already has 3x IronOre (MaxStack 20); adding 10x merges into same slot! }
    AssertEquals(4, Inv.UsedSlotCount);
    AssertTrue(Inv.TryAddItem('IronOre', 10, Reason));
    AssertEquals(13, Inv.GetTotalItemCount('IronOre'));
    AssertEquals(4, Inv.UsedSlotCount);

    { 2. Atomic weight cap rejection: adding 50x IronOre (75 kg) exceeds 60 kg MaxCarryWeightKg }
    AssertFalse(Inv.TryAddItem('IronOre', 50, Reason));
    AssertEquals(13, Inv.GetTotalItemCount('IronOre')); // Unchanged!

    { 3. Atomic Crafting: CraftSunfireBlade consumes 3x IronOre + 2x CrystalShard -> 1x SunfireBlade }
    AssertEquals(0, Inv.GetTotalItemCount('SunfireBlade'));
    AssertTrue(Inv.TryCraftRecipe('CraftSunfireBlade', Reason));
    AssertEquals(10, Inv.GetTotalItemCount('IronOre'));
    AssertEquals(0, Inv.GetTotalItemCount('CrystalShard'));
    AssertEquals(1, Inv.GetTotalItemCount('SunfireBlade'));
    { Second craft fails cleanly because CrystalShard is now 0 }
    AssertFalse(Inv.CanCraftRecipe('CraftSunfireBlade', Reason));

    { 4. Paperdoll Equipment <-> GAS Attribute & GameplayTag live sync }
    AssertSameValue(25.0, Gas.GetCurrentValue('AttackPower'), 1e-3);
    AssertFalse(Gas.HasMatchingTag('Equipped.Weapon.*'));

    AssertTrue(Inv.EquipItemFromBag('SunfireBlade', Reason));
    AssertEquals(0, Inv.GetTotalItemCount('SunfireBlade'));
    AssertEquals('SunfireBlade', Inv.EquippedItemInSlot(esMainHand));
    AssertSameValue(60.0, Gas.GetCurrentValue('AttackPower'), 1e-3); // 25 + 35 = 60!
    AssertTrue(Gas.HasMatchingTag('Equipped.Weapon.Sunfire'));

    { Unequipping restores bag item and strips GAS passive modifier & tag cleanly }
    AssertTrue(Inv.UnequipSlot(esMainHand, Reason));
    AssertEquals(1, Inv.GetTotalItemCount('SunfireBlade'));
    AssertSameValue(25.0, Gas.GetCurrentValue('AttackPower'), 1e-3);
    AssertFalse(Gas.HasMatchingTag('Equipped.Weapon.Sunfire'));

    { 5. ConfigJson serialization roundtrip }
    AssertTrue(Inv.EquipItemFromBag('SunfireBlade', Reason));
    JsonStr := ComponentToString(Inv);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleInventoryBehavior);
    LoadedInv := TCastleInventoryBehavior(LoadedComp);
    AssertEquals('SunfireBlade', LoadedInv.EquippedItemInSlot(esMainHand));
    AssertEquals(10, LoadedInv.GetTotalItemCount('IronOre'));
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolInventoryStudio.TestWeightedLootTableSeededDeterminismAndLegendaryPityGuarantee;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Hero: TCastleTransform;
  Gas: TCastleAbilitySystemBehavior;
  Inv: TCastleInventoryBehavior;
  LootA, LootB: TCastleLootTable;
  Rep: TInventoryAuditReport;
  ItemA, ItemB: String;
  QtyA, QtyB, I, LegendCount: Integer;
  RarA, RarB: TItemRarity;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TInventoryStudioHelper.SpawnRpgHeroInventoryAndLootChestDemo(
      Vp, OwnerComp, Hero, Gas, Inv, LootA);

    { 1. Identical seeds produce identical drop sequences }
    LootA.Seed := 7777;
    LootB := TCastleLootTable.Create(OwnerComp);
    LootB.Seed := 7777;
    for I := 1 to 15 do
    begin
      AssertTrue(LootA.RollSingleDrop(ItemA, QtyA, RarA));
      AssertTrue(LootB.RollSingleDrop(ItemB, QtyB, RarB));
      AssertEquals(ItemA, ItemB);
      AssertEquals(QtyA, QtyB);
      AssertEquals(Ord(RarA), Ord(RarB));
    end;

    { 2. Bad-luck protection pity guarantee: even with ultra-tiny Legendary weight (0.0001),
      LegendaryPityThreshold = 6 guarantees >= 2 Legendaries across 12 rolls! }
    LootA.ClearEntries;
    LootA.AddEntry('IronOre', irCommon, 1000.0, 1, 1);
    LootA.AddEntry('SunfireBlade', irLegendary, 0.0001, 1, 1);
    LootA.LegendaryPityThreshold := 6;
    LootA.ResetRngAndPity;

    LegendCount := 0;
    for I := 1 to 12 do
    begin
      AssertTrue(LootA.RollSingleDrop(ItemA, QtyA, RarA));
      if RarA = irLegendary then
        Inc(LegendCount);
    end;
    AssertTrue(LegendCount >= 2);

    Rep := TInventoryStudioHelper.AuditInventories(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.InventoryCount);
      AssertEquals(2, Rep.LootTableCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolInventoryStudio);
end.
