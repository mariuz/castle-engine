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

{ RPG Slot & Weight-Capped Inventory, Equipment Paperdoll with Automatic
  Gameplay Ability System (@link(TCastleAbilitySystemBehavior)) Attribute Sync,
  Atomic Crafting Recipes & Seeded Weighted / Pity-Protected Loot Tables
  (@link(TCastleInventoryBehavior), @link(TCastleLootTable))
  (Phase 320 — UE 6.0+ Lyra Inventory, Crafting & Loot Table Parity). }
unit CastleInventoryCraft;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleClassUtils, CastleTransform, CastleBehaviors, CastleGameplayAbility;

type
  { Standard 5-tier RPG item rarity classification. }
  TItemRarity = (
    irCommon,
    irUncommon,
    irRare,
    irEpic,
    irLegendary
  );

  { Character equipment paperdoll slot. }
  TEquipmentSlot = (
    esNone,
    esHead,
    esChest,
    esMainHand,
    esOffHand,
    esAccessory
  );

  { Built-in itemization & crafting presets. }
  TInventoryPreset = (
    ivpCustom,
    ivpFantasyRpgLoadout,
    ivpSciFiSurvivalLoadout
  );

  { Master catalog definition of an item type. }
  TInventoryItemDef = record
    ItemId: String;
    DisplayName: String;
    Rarity: TItemRarity;
    EquipSlot: TEquipmentSlot;
    MaxStack: Integer;
    UnitWeightKg: Single;
    GoldValue: Integer;
    StatAttrName: String;
    StatModOp: TGasModifierOp;
    StatMagnitude: Single;
    GrantedTag: String;
  end;
  TInventoryItemDefArray = array of TInventoryItemDef;

  { Single occupied slot in the inventory bag. }
  TInventorySlotStack = record
    ItemId: String;
    Quantity: Integer;
  end;
  TInventorySlotStackArray = array of TInventorySlotStack;

  { Single ingredient requirement inside a crafting recipe. }
  TCraftingIngredient = record
    ItemId: String;
    RequiredQty: Integer;
  end;
  TCraftingIngredientArray = array of TCraftingIngredient;

  { Atomic crafting recipe converting ingredients into minted output items. }
  TCraftingRecipeDef = record
    RecipeId: String;
    DisplayName: String;
    OutputItemId: String;
    OutputQuantity: Integer;
    Ingredients: TCraftingIngredientArray;
  end;
  TCraftingRecipeDefArray = array of TCraftingRecipeDef;

  { Weighted drop entry inside a @link(TCastleLootTable). }
  TLootDropEntry = record
    ItemId: String;
    Rarity: TItemRarity;
    Weight: Single;
    MinQty: Integer;
    MaxQty: Integer;
  end;
  TLootDropEntryArray = array of TLootDropEntry;

  { Composable RPG Inventory, Paperdoll Equipment & Crafting behavior.
    Automatically applies and removes passive @link(TCastleAbilitySystemBehavior)
    attribute modifiers and Gameplay Tags whenever equipment changes on the same
    @link(TCastleTransform). }
  TCastleInventoryBehavior = class(TCastleBehavior)
  public
    const
      DefaultMaxSlots = 20;
      DefaultMaxCarryWeightKg = 60.0;
  strict private
    FPreset: TInventoryPreset;
    FMaxSlots: Integer;
    FMaxCarryWeightKg: Single;
    FGoldCoins: Integer;

    FItemCatalog: TInventoryItemDefArray;
    FBagSlots: TInventorySlotStackArray;
    FEquippedIds: array [TEquipmentSlot] of String;
    FRecipes: TCraftingRecipeDefArray;

    procedure SetPreset(const Value: TInventoryPreset);
    procedure SetMaxSlots(const Value: Integer);
    procedure SetMaxCarryWeightKg(const Value: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function SiblingGasBehavior: TCastleAbilitySystemBehavior;
    function CanFitAdditionalItems(const ADef: TInventoryItemDef;
      const AQty: Integer; const IgnoreBagWeightDeltaKg: Single;
      out OutReason: String): Boolean;
    procedure ApplySlotEffectToGas(const ASlot: TEquipmentSlot; const AItemId: String);
    procedure RemoveSlotEffectFromGas(const ASlot: TEquipmentSlot);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function RarityDisplayName(const ARarity: TItemRarity): String; static;
    class function SlotDisplayName(const ASlot: TEquipmentSlot): String; static;

    procedure ApplyPreset(const APreset: TInventoryPreset);
    procedure ClearAll;

    { Catalog & Recipe registration }
    procedure RegisterItemDef(const ADef: TInventoryItemDef);
    function FindItemDef(const AItemId: String; out OutDef: TInventoryItemDef): Boolean;
    function CatalogCount: Integer;
    function GetCatalogDef(const Index: Integer): TInventoryItemDef;

    procedure RegisterRecipe(const ARecipeId, ADisplayName, AOutputItemId: String;
      const AOutputQty: Integer; const AIngredients: array of TCraftingIngredient);
    function RecipeCount: Integer;
    function GetRecipe(const Index: Integer): TCraftingRecipeDef;
    function FindRecipe(const ARecipeId: String; out OutRecipe: TCraftingRecipeDef): Boolean;

    { Bag operations }
    function UsedSlotCount: Integer;
    function GetBagSlot(const Index: Integer): TInventorySlotStack;
    function CurrentCarryWeightKg: Single;
    function GetTotalItemCount(const AItemId: String): Integer;
    function TryAddItem(const AItemId: String; const AQty: Integer;
      out OutReason: String): Boolean; overload;
    function TryAddItem(const AItemId: String; const AQty: Integer = 1): Boolean; overload;
    function TryRemoveItem(const AItemId: String; const AQty: Integer): Boolean;

    { Paperdoll Equipment <-> GAS sync }
    function EquippedItemInSlot(const ASlot: TEquipmentSlot): String;
    procedure SyncAllEquipmentToGas;
    function EquipItemFromBag(const AItemId: String; out OutReason: String): Boolean;
    function UnequipSlot(const ASlot: TEquipmentSlot; out OutReason: String): Boolean;

    { Atomic Crafting }
    function CanCraftRecipe(const ARecipeId: String; out OutReason: String): Boolean;
    function TryCraftRecipe(const ARecipeId: String; out OutReason: String): Boolean;

    function InventorySummaryBadge: String;
  published
    property Preset: TInventoryPreset read FPreset write SetPreset default ivpFantasyRpgLoadout;
    property MaxSlots: Integer read FMaxSlots write SetMaxSlots default DefaultMaxSlots;
    property MaxCarryWeightKg: Single read FMaxCarryWeightKg write SetMaxCarryWeightKg {$ifdef FPC}default DefaultMaxCarryWeightKg{$endif};
    property GoldCoins: Integer read FGoldCoins write FGoldCoins default 100;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Deterministic seeded weighted rarity loot table with bad-luck protection
    (@link(LegendaryPityThreshold)) guaranteeing a Legendary drop if @code(N)
    consecutive rolls miss Legendary tier. }
  TCastleLootTable = class(TCastleComponent)
  public
    const
      DefaultSeed = 2026;
      DefaultLegendaryPityThreshold = 10;
  strict private
    FSeed: Cardinal;
    FRngState: Cardinal;
    FLegendaryPityThreshold: Integer;
    FRollsSinceLegendary: Integer;
    FTotalRolls: Integer;
    FEntries: TLootDropEntryArray;

    procedure SetSeed(const Value: Cardinal);
    function NextRandom01: Single;
    function NextRandomRange(const AMin, AMax: Integer): Integer;
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyDefaultFantasyChestTable;
    procedure ClearEntries;
    procedure AddEntry(const AItemId: String; const ARarity: TItemRarity;
      const AWeight: Single; const AMinQty: Integer = 1; const AMaxQty: Integer = 1);
    function EntryCount: Integer;
    function GetEntry(const Index: Integer): TLootDropEntry;
    procedure ResetRngAndPity;

    function RollSingleDrop(out OutItemId: String; out OutQty: Integer;
      out OutRarity: TItemRarity): Boolean;
    function RollIntoInventory(const TargetInv: TCastleInventoryBehavior;
      out OutItemId: String; out OutQty: Integer; out OutRarity: TItemRarity): Boolean;

    function LootSummaryBadge: String;

    property RollsSinceLegendary: Integer read FRollsSinceLegendary;
    property TotalRolls: Integer read FTotalRolls;
  published
    property Seed: Cardinal read FSeed write SetSeed default DefaultSeed;
    property LegendaryPityThreshold: Integer read FLegendaryPityThreshold
      write FLegendaryPityThreshold default DefaultLegendaryPityThreshold;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function MakeCraftIngredient(const AItemId: String; const AQty: Integer): TCraftingIngredient;

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize;

function MakeCraftIngredient(const AItemId: String; const AQty: Integer): TCraftingIngredient;
begin
  Result.ItemId := AItemId;
  Result.RequiredQty := Max(1, AQty);
end;

{ TCastleInventoryBehavior --------------------------------------------------- }

constructor TCastleInventoryBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxSlots := DefaultMaxSlots;
  FMaxCarryWeightKg := DefaultMaxCarryWeightKg;
  FGoldCoins := 100;
  ApplyPreset(ivpFantasyRpgLoadout);
end;

class function TCastleInventoryBehavior.RarityDisplayName(const ARarity: TItemRarity): String;
begin
  case ARarity of
    irCommon:    Result := 'Common';
    irUncommon:  Result := 'Uncommon';
    irRare:      Result := 'Rare';
    irEpic:      Result := 'Epic';
    irLegendary: Result := 'Legendary';
  end;
end;

class function TCastleInventoryBehavior.SlotDisplayName(const ASlot: TEquipmentSlot): String;
begin
  case ASlot of
    esNone:      Result := 'BagOnly';
    esHead:      Result := 'Head';
    esChest:     Result := 'Chest';
    esMainHand:  Result := 'MainHand';
    esOffHand:   Result := 'OffHand';
    esAccessory: Result := 'Accessory';
  end;
end;

procedure TCastleInventoryBehavior.ClearAll;
var
  S: TEquipmentSlot;
begin
  for S in TEquipmentSlot do
  begin
    if S <> esNone then
      RemoveSlotEffectFromGas(S);
    FEquippedIds[S] := '';
  end;
  FItemCatalog := nil;
  FBagSlots := nil;
  FRecipes := nil;
end;

procedure TCastleInventoryBehavior.RegisterItemDef(const ADef: TInventoryItemDef);
var
  I, N: Integer;
  CleanDef: TInventoryItemDef;
begin
  CleanDef := ADef;
  CleanDef.MaxStack := Max(1, CleanDef.MaxStack);
  CleanDef.UnitWeightKg := Max(0.0, CleanDef.UnitWeightKg);
  for I := 0 to High(FItemCatalog) do
    if SameText(FItemCatalog[I].ItemId, CleanDef.ItemId) then
    begin
      FItemCatalog[I] := CleanDef;
      Exit;
    end;
  N := Length(FItemCatalog);
  SetLength(FItemCatalog, N + 1);
  FItemCatalog[N] := CleanDef;
end;

function TCastleInventoryBehavior.FindItemDef(const AItemId: String;
  out OutDef: TInventoryItemDef): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FItemCatalog) do
    if SameText(FItemCatalog[I].ItemId, AItemId) then
    begin
      OutDef := FItemCatalog[I];
      Exit(True);
    end;
  Result := False;
end;

function TCastleInventoryBehavior.CatalogCount: Integer;
begin
  Result := Length(FItemCatalog);
end;

function TCastleInventoryBehavior.GetCatalogDef(const Index: Integer): TInventoryItemDef;
begin
  Result := FItemCatalog[Clamped(Index, 0, Max(0, High(FItemCatalog)))];
end;

procedure TCastleInventoryBehavior.RegisterRecipe(
  const ARecipeId, ADisplayName, AOutputItemId: String;
  const AOutputQty: Integer; const AIngredients: array of TCraftingIngredient);
var
  N, I: Integer;
begin
  N := Length(FRecipes);
  SetLength(FRecipes, N + 1);
  FRecipes[N].RecipeId := ARecipeId;
  FRecipes[N].DisplayName := ADisplayName;
  FRecipes[N].OutputItemId := AOutputItemId;
  FRecipes[N].OutputQuantity := Max(1, AOutputQty);
  SetLength(FRecipes[N].Ingredients, Length(AIngredients));
  for I := 0 to High(AIngredients) do
    FRecipes[N].Ingredients[I] := AIngredients[I];
end;

function TCastleInventoryBehavior.RecipeCount: Integer;
begin
  Result := Length(FRecipes);
end;

function TCastleInventoryBehavior.GetRecipe(const Index: Integer): TCraftingRecipeDef;
begin
  Result := FRecipes[Clamped(Index, 0, Max(0, High(FRecipes)))];
end;

function TCastleInventoryBehavior.FindRecipe(const ARecipeId: String;
  out OutRecipe: TCraftingRecipeDef): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FRecipes) do
    if SameText(FRecipes[I].RecipeId, ARecipeId) then
    begin
      OutRecipe := FRecipes[I];
      Exit(True);
    end;
  Result := False;
end;

procedure TCastleInventoryBehavior.ApplyPreset(const APreset: TInventoryPreset);

  procedure DefItem(const AId, AName: String; const ARarity: TItemRarity;
    const ASlot: TEquipmentSlot; const AMaxStack: Integer; const AWeight: Single;
    const AGold: Integer; const AAttr: String = '';
    const AOp: TGasModifierOp = gmoFlatAdd; const AMag: Single = 0.0;
    const ATag: String = '');
  var
    D: TInventoryItemDef;
  begin
    D.ItemId := AId;
    D.DisplayName := AName;
    D.Rarity := ARarity;
    D.EquipSlot := ASlot;
    D.MaxStack := AMaxStack;
    D.UnitWeightKg := AWeight;
    D.GoldValue := AGold;
    D.StatAttrName := AAttr;
    D.StatModOp := AOp;
    D.StatMagnitude := AMag;
    D.GrantedTag := ATag;
    RegisterItemDef(D);
  end;

begin
  FPreset := APreset;
  case APreset of
    ivpFantasyRpgLoadout:
      begin
        ClearAll;
        DefItem('IronOre', 'Iron Ore', irCommon, esNone, 20, 1.5, 8);
        DefItem('SunbloomHerb', 'Sunbloom Herb', irCommon, esNone, 20, 0.2, 10);
        DefItem('CrystalShard', 'Arcane Crystal Shard', irRare, esNone, 10, 0.5, 45);
        DefItem('HealthElixir', 'Greater Health Elixir', irUncommon, esNone, 10, 0.4, 30);
        DefItem('VanguardHelm', 'Vanguard Steel Helm', irUncommon, esHead, 1, 2.2, 85,
          'MaxHealth', gmoFlatAdd, 25.0, 'Equipped.Armor.Helm');
        DefItem('AegisPlate', 'Aegis Mithril Plate', irEpic, esChest, 1, 7.5, 320,
          'Armor', gmoFlatAdd, 30.0, 'Equipped.Armor.Chest');
        DefItem('ArchmageRing', 'Signet of the Archmage', irRare, esAccessory, 1, 0.2, 210,
          'SpellPower', gmoPercentAdd, 0.25, 'Equipped.Ring.Archmage');
        DefItem('SunfireBlade', 'Sunfire Greatsword', irLegendary, esMainHand, 1, 3.8, 900,
          'AttackPower', gmoFlatAdd, 35.0, 'Equipped.Weapon.Sunfire');

        RegisterRecipe('CraftSunfireBlade', 'Forge Sunfire Greatsword', 'SunfireBlade', 1,
          [MakeCraftIngredient('IronOre', 3), MakeCraftIngredient('CrystalShard', 2)]);
        RegisterRecipe('CraftHealthElixir', 'Brew Greater Health Elixir', 'HealthElixir', 1,
          [MakeCraftIngredient('SunbloomHerb', 2)]);
      end;
    ivpSciFiSurvivalLoadout:
      begin
        ClearAll;
        DefItem('TitaniumScrap', 'Titanium Scrap', irCommon, esNone, 30, 1.0, 12);
        DefItem('PlasmaCell', 'Plasma Energy Cell', irRare, esNone, 15, 0.6, 50);
        DefItem('MedInjector', 'Nano-Med Injector', irUncommon, esNone, 10, 0.3, 35);
        DefItem('PulseRifle', 'Phase Pulse Rifle', irLegendary, esMainHand, 1, 4.2, 950,
          'AttackPower', gmoFlatAdd, 42.0, 'Equipped.Weapon.PulseRifle');

        RegisterRecipe('CraftPulseRifle', 'Assemble Phase Pulse Rifle', 'PulseRifle', 1,
          [MakeCraftIngredient('TitaniumScrap', 4), MakeCraftIngredient('PlasmaCell', 2)]);
      end;
    ivpCustom: ;
  end;
end;

function TCastleInventoryBehavior.UsedSlotCount: Integer;
begin
  Result := Length(FBagSlots);
end;

function TCastleInventoryBehavior.GetBagSlot(const Index: Integer): TInventorySlotStack;
begin
  Result := FBagSlots[Clamped(Index, 0, Max(0, High(FBagSlots)))];
end;

function TCastleInventoryBehavior.CurrentCarryWeightKg: Single;
var
  I: Integer;
  S: TEquipmentSlot;
  Def: TInventoryItemDef;
begin
  Result := 0.0;
  for I := 0 to High(FBagSlots) do
    if FindItemDef(FBagSlots[I].ItemId, Def) then
      Result := Result + Def.UnitWeightKg * FBagSlots[I].Quantity;
  for S in TEquipmentSlot do
    if (S <> esNone) and (FEquippedIds[S] <> '') and FindItemDef(FEquippedIds[S], Def) then
      Result := Result + Def.UnitWeightKg;
end;

function TCastleInventoryBehavior.GetTotalItemCount(const AItemId: String): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FBagSlots) do
    if SameText(FBagSlots[I].ItemId, AItemId) then
      Result := Result + FBagSlots[I].Quantity;
end;

function TCastleInventoryBehavior.CanFitAdditionalItems(
  const ADef: TInventoryItemDef; const AQty: Integer;
  const IgnoreBagWeightDeltaKg: Single; out OutReason: String): Boolean;
var
  ProjectedWeight: Single;
  Remaining, FreeInExisting, NeededNewSlots, I: Integer;
begin
  OutReason := '';
  if AQty <= 0 then
    Exit(True);

  ProjectedWeight := CurrentCarryWeightKg - IgnoreBagWeightDeltaKg +
    ADef.UnitWeightKg * AQty;
  if ProjectedWeight > FMaxCarryWeightKg + 1e-4 then
  begin
    OutReason := Format('Exceeds MaxCarryWeightKg (%.1f / %.1f kg).',
      [ProjectedWeight, FMaxCarryWeightKg]);
    Exit(False);
  end;

  Remaining := AQty;
  for I := 0 to High(FBagSlots) do
    if SameText(FBagSlots[I].ItemId, ADef.ItemId) and
       (FBagSlots[I].Quantity < ADef.MaxStack) then
    begin
      FreeInExisting := ADef.MaxStack - FBagSlots[I].Quantity;
      Remaining := Remaining - Min(Remaining, FreeInExisting);
      if Remaining <= 0 then
        Break;
    end;

  if Remaining > 0 then
  begin
    NeededNewSlots := (Remaining + ADef.MaxStack - 1) div ADef.MaxStack;
    if Length(FBagSlots) + NeededNewSlots > FMaxSlots then
    begin
      OutReason := Format('Not enough free bag slots (%d needed, %d/%d used).',
        [NeededNewSlots, Length(FBagSlots), FMaxSlots]);
      Exit(False);
    end;
  end;

  Result := True;
end;

function TCastleInventoryBehavior.TryAddItem(const AItemId: String;
  const AQty: Integer; out OutReason: String): Boolean;
var
  Def: TInventoryItemDef;
  Remaining, AddHere, I, N: Integer;
begin
  if AQty <= 0 then
  begin
    OutReason := 'Quantity must be positive.';
    Exit(False);
  end;
  if not FindItemDef(AItemId, Def) then
  begin
    OutReason := Format('Unknown ItemId "%s".', [AItemId]);
    Exit(False);
  end;
  if not CanFitAdditionalItems(Def, AQty, 0.0, OutReason) then
    Exit(False);

  Remaining := AQty;
  for I := 0 to High(FBagSlots) do
    if SameText(FBagSlots[I].ItemId, Def.ItemId) and
       (FBagSlots[I].Quantity < Def.MaxStack) then
    begin
      AddHere := Min(Remaining, Def.MaxStack - FBagSlots[I].Quantity);
      FBagSlots[I].Quantity := FBagSlots[I].Quantity + AddHere;
      Remaining := Remaining - AddHere;
      if Remaining <= 0 then
        Break;
    end;

  while Remaining > 0 do
  begin
    AddHere := Min(Remaining, Def.MaxStack);
    N := Length(FBagSlots);
    SetLength(FBagSlots, N + 1);
    FBagSlots[N].ItemId := Def.ItemId;
    FBagSlots[N].Quantity := AddHere;
    Remaining := Remaining - AddHere;
  end;

  OutReason := '';
  Result := True;
end;

function TCastleInventoryBehavior.TryAddItem(const AItemId: String;
  const AQty: Integer): Boolean;
var
  DummyReason: String;
begin
  Result := TryAddItem(AItemId, AQty, DummyReason);
end;

function TCastleInventoryBehavior.TryRemoveItem(const AItemId: String;
  const AQty: Integer): Boolean;
var
  Remaining, TakeHere, I, K: Integer;
begin
  if (AQty <= 0) or (GetTotalItemCount(AItemId) < AQty) then
    Exit(False);

  Remaining := AQty;
  for I := High(FBagSlots) downto 0 do
    if SameText(FBagSlots[I].ItemId, AItemId) then
    begin
      TakeHere := Min(Remaining, FBagSlots[I].Quantity);
      FBagSlots[I].Quantity := FBagSlots[I].Quantity - TakeHere;
      Remaining := Remaining - TakeHere;
      if FBagSlots[I].Quantity <= 0 then
      begin
        for K := I to High(FBagSlots) - 1 do
          FBagSlots[K] := FBagSlots[K + 1];
        SetLength(FBagSlots, Length(FBagSlots) - 1);
      end;
      if Remaining <= 0 then
        Break;
    end;

  Result := True;
end;

function TCastleInventoryBehavior.SiblingGasBehavior: TCastleAbilitySystemBehavior;
begin
  if Parent <> nil then
    Result := Parent.FindBehavior(TCastleAbilitySystemBehavior) as TCastleAbilitySystemBehavior
  else
    Result := nil;
end;

procedure TCastleInventoryBehavior.RemoveSlotEffectFromGas(const ASlot: TEquipmentSlot);
var
  Gas: TCastleAbilitySystemBehavior;
  SlotEffectId: String;
  I: Integer;
begin
  Gas := SiblingGasBehavior;
  if (Gas = nil) or (ASlot = esNone) then
    Exit;
  SlotEffectId := 'EquipPaperdoll.' + SlotDisplayName(ASlot);
  for I := Gas.ActiveEffects.Count - 1 downto 0 do
    if SameText(Gas.ActiveEffects[I].Def.EffectId, SlotEffectId) then
      Gas.ActiveEffects.Delete(I);
end;

procedure TCastleInventoryBehavior.ApplySlotEffectToGas(
  const ASlot: TEquipmentSlot; const AItemId: String);
var
  Gas: TCastleAbilitySystemBehavior;
  Def: TInventoryItemDef;
  Eff: TGasEffectDef;
  DummyReason: String;
begin
  RemoveSlotEffectFromGas(ASlot);
  Gas := SiblingGasBehavior;
  if (Gas = nil) or (ASlot = esNone) or (AItemId = '') then
    Exit;
  if not FindItemDef(AItemId, Def) then
    Exit;

  if (Def.StatAttrName <> '') and (not Gas.HasAttribute(Def.StatAttrName)) then
    Gas.DefineOrSetAttribute(TGasAttributeDef.CreateSimple(Def.StatAttrName, 10.0, 0.0, 9999.0));

  Eff := TGasEffectDef.CreateDefault('EquipPaperdoll.' + SlotDisplayName(ASlot));
  Eff.EffectTag := 'Buff.Equipment.' + SlotDisplayName(ASlot);
  Eff.GrantedTag := Def.GrantedTag;
  Eff.DurationSec := 3600.0 * 24.0; // Passive equipment buff while worn
  Eff.MaxStacks := 1;
  Eff.TargetAttrName := Def.StatAttrName;
  Eff.ModOp := Def.StatModOp;
  Eff.ModMagnitude := Def.StatMagnitude;
  Gas.ApplyEffectDef(Eff, DummyReason);
end;

procedure TCastleInventoryBehavior.SyncAllEquipmentToGas;
var
  S: TEquipmentSlot;
begin
  for S in TEquipmentSlot do
    if S <> esNone then
      ApplySlotEffectToGas(S, FEquippedIds[S]);
end;

function TCastleInventoryBehavior.EquippedItemInSlot(const ASlot: TEquipmentSlot): String;
begin
  Result := FEquippedIds[ASlot];
end;

function TCastleInventoryBehavior.EquipItemFromBag(const AItemId: String;
  out OutReason: String): Boolean;
var
  Def: TInventoryItemDef;
  OldEquipped: String;
begin
  if not FindItemDef(AItemId, Def) then
  begin
    OutReason := Format('Unknown item "%s".', [AItemId]);
    Exit(False);
  end;
  if Def.EquipSlot = esNone then
  begin
    OutReason := Format('Item "%s" is not equippable.', [Def.DisplayName]);
    Exit(False);
  end;
  if GetTotalItemCount(AItemId) < 1 then
  begin
    OutReason := Format('Item "%s" is not in bag.', [Def.DisplayName]);
    Exit(False);
  end;

  OldEquipped := FEquippedIds[Def.EquipSlot];
  TryRemoveItem(AItemId, 1);
  if OldEquipped <> '' then
  begin
    RemoveSlotEffectFromGas(Def.EquipSlot);
    FEquippedIds[Def.EquipSlot] := '';
    if not TryAddItem(OldEquipped, 1, OutReason) then
    begin
      { Roll back cleanly if swapping somehow overflows slots }
      FEquippedIds[Def.EquipSlot] := OldEquipped;
      ApplySlotEffectToGas(Def.EquipSlot, OldEquipped);
      TryAddItem(AItemId, 1);
      Exit(False);
    end;
  end;

  FEquippedIds[Def.EquipSlot] := Def.ItemId;
  ApplySlotEffectToGas(Def.EquipSlot, Def.ItemId);
  OutReason := '';
  Result := True;
end;

function TCastleInventoryBehavior.UnequipSlot(const ASlot: TEquipmentSlot;
  out OutReason: String): Boolean;
var
  CurId: String;
  Def: TInventoryItemDef;
begin
  if (ASlot = esNone) or (FEquippedIds[ASlot] = '') then
  begin
    OutReason := 'Slot is already empty.';
    Exit(False);
  end;
  CurId := FEquippedIds[ASlot];
  if not FindItemDef(CurId, Def) then
  begin
    RemoveSlotEffectFromGas(ASlot);
    FEquippedIds[ASlot] := '';
    OutReason := '';
    Exit(True);
  end;

  { Weight is unchanged when moving equipped -> bag; check slot capacity }
  if not CanFitAdditionalItems(Def, 1, Def.UnitWeightKg, OutReason) then
    Exit(False);

  RemoveSlotEffectFromGas(ASlot);
  FEquippedIds[ASlot] := '';
  Result := TryAddItem(CurId, 1, OutReason);
end;

function TCastleInventoryBehavior.CanCraftRecipe(const ARecipeId: String;
  out OutReason: String): Boolean;
var
  Rec: TCraftingRecipeDef;
  OutDef, IngDef: TInventoryItemDef;
  FreedWeight: Single;
  I: Integer;
begin
  if not FindRecipe(ARecipeId, Rec) then
  begin
    OutReason := Format('Unknown recipe "%s".', [ARecipeId]);
    Exit(False);
  end;
  if not FindItemDef(Rec.OutputItemId, OutDef) then
  begin
    OutReason := Format('Output item "%s" missing from catalog.', [Rec.OutputItemId]);
    Exit(False);
  end;

  FreedWeight := 0.0;
  for I := 0 to High(Rec.Ingredients) do
  begin
    if GetTotalItemCount(Rec.Ingredients[I].ItemId) < Rec.Ingredients[I].RequiredQty then
    begin
      OutReason := Format('Missing ingredient %s (%d / %d).',
        [Rec.Ingredients[I].ItemId, GetTotalItemCount(Rec.Ingredients[I].ItemId),
         Rec.Ingredients[I].RequiredQty]);
      Exit(False);
    end;
    if FindItemDef(Rec.Ingredients[I].ItemId, IngDef) then
      FreedWeight := FreedWeight + IngDef.UnitWeightKg * Rec.Ingredients[I].RequiredQty;
  end;

  Result := CanFitAdditionalItems(OutDef, Rec.OutputQuantity, FreedWeight, OutReason);
end;

function TCastleInventoryBehavior.TryCraftRecipe(const ARecipeId: String;
  out OutReason: String): Boolean;
var
  Rec: TCraftingRecipeDef;
  I: Integer;
begin
  if not CanCraftRecipe(ARecipeId, OutReason) then
    Exit(False);
  FindRecipe(ARecipeId, Rec);
  for I := 0 to High(Rec.Ingredients) do
    TryRemoveItem(Rec.Ingredients[I].ItemId, Rec.Ingredients[I].RequiredQty);
  Result := TryAddItem(Rec.OutputItemId, Rec.OutputQuantity, OutReason);
end;

function TCastleInventoryBehavior.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'MaxSlots') or
     (PropertyName = 'MaxCarryWeightKg') or
     (PropertyName = 'GoldCoins') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleInventoryBehavior.InventorySummaryBadge: String;
var
  EquipCount: Integer;
  S: TEquipmentSlot;
begin
  EquipCount := 0;
  for S in TEquipmentSlot do
    if (S <> esNone) and (FEquippedIds[S] <> '') then
      Inc(EquipCount);
  Result := Format('[Inventory:%d/%d slots %.1f/%.0fkg %d eq]', [
    UsedSlotCount, FMaxSlots, CurrentCarryWeightKg, FMaxCarryWeightKg, EquipCount]);
end;

procedure TCastleInventoryBehavior.SetPreset(const Value: TInventoryPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleInventoryBehavior.SetMaxSlots(const Value: Integer);
begin
  FMaxSlots := Max(1, Value);
end;

procedure TCastleInventoryBehavior.SetMaxCarryWeightKg(const Value: Single);
begin
  FMaxCarryWeightKg := Max(1.0, Value);
end;

function TCastleInventoryBehavior.GetConfigJson: String;
var
  Root, Obj, EqObj: TJSONObject;
  BagArr: TJSONArray;
  I: Integer;
  S: TEquipmentSlot;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('maxSlots', FMaxSlots);
    Root.Add('maxWeight', FMaxCarryWeightKg);
    Root.Add('gold', FGoldCoins);

    BagArr := TJSONArray.Create;
    for I := 0 to High(FBagSlots) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FBagSlots[I].ItemId);
      Obj.Add('qty', FBagSlots[I].Quantity);
      BagArr.Add(Obj);
    end;
    Root.Add('bag', BagArr);

    EqObj := TJSONObject.Create;
    for S in TEquipmentSlot do
      if (S <> esNone) and (FEquippedIds[S] <> '') then
        EqObj.Add(SlotDisplayName(S), FEquippedIds[S]);
    Root.Add('equipped', EqObj);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleInventoryBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, Obj, EqObj: TJSONObject;
  BagArr: TJSONArray;
  I: Integer;
  S: TEquipmentSlot;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      ApplyPreset(TInventoryPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TInventoryPreset)))));
      FMaxSlots := Max(1, Root.Get('maxSlots', FMaxSlots));
      FMaxCarryWeightKg := Max(1.0, Root.Get('maxWeight', FMaxCarryWeightKg));
      FGoldCoins := Root.Get('gold', FGoldCoins);

      FBagSlots := nil;
      BagArr := Root.Find('bag', jtArray) as TJSONArray;
      if BagArr <> nil then
        for I := 0 to BagArr.Count - 1 do
          if BagArr.Items[I] is TJSONObject then
          begin
            Obj := TJSONObject(BagArr.Items[I]);
            TryAddItem(Obj.Get('id', ''), Obj.Get('qty', 1));
          end;

      EqObj := Root.Find('equipped', jtObject) as TJSONObject;
      if EqObj <> nil then
        for S in TEquipmentSlot do
          if S <> esNone then
          begin
            FEquippedIds[S] := EqObj.Get(SlotDisplayName(S), '');
            ApplySlotEffectToGas(S, FEquippedIds[S]);
          end;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleLootTable ----------------------------------------------------------- }

constructor TCastleLootTable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSeed := DefaultSeed;
  FLegendaryPityThreshold := DefaultLegendaryPityThreshold;
  ApplyDefaultFantasyChestTable;
  ResetRngAndPity;
end;

procedure TCastleLootTable.SetSeed(const Value: Cardinal);
begin
  FSeed := Max(Cardinal(1), Value);
  ResetRngAndPity;
end;

procedure TCastleLootTable.ResetRngAndPity;
begin
  if FSeed = 0 then
    FRngState := 2026
  else
    FRngState := FSeed;
  FRollsSinceLegendary := 0;
  FTotalRolls := 0;
end;

function TCastleLootTable.NextRandom01: Single;
var
  X: Cardinal;
begin
  X := FRngState;
  if X = 0 then
    X := 2463534242;
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  FRngState := X;
  Result := (X and $00FFFFFF) / 16777216.0;
end;

function TCastleLootTable.NextRandomRange(const AMin, AMax: Integer): Integer;
begin
  if AMax <= AMin then
    Exit(AMin);
  Result := AMin + Trunc(NextRandom01 * (AMax - AMin + 1));
  Result := Clamped(Result, AMin, AMax);
end;

procedure TCastleLootTable.ClearEntries;
begin
  FEntries := nil;
end;

procedure TCastleLootTable.AddEntry(const AItemId: String;
  const ARarity: TItemRarity; const AWeight: Single;
  const AMinQty, AMaxQty: Integer);
var
  N: Integer;
begin
  N := Length(FEntries);
  SetLength(FEntries, N + 1);
  FEntries[N].ItemId := AItemId;
  FEntries[N].Rarity := ARarity;
  FEntries[N].Weight := Max(0.0, AWeight);
  FEntries[N].MinQty := Max(1, AMinQty);
  FEntries[N].MaxQty := Max(FEntries[N].MinQty, AMaxQty);
end;

procedure TCastleLootTable.ApplyDefaultFantasyChestTable;
begin
  ClearEntries;
  AddEntry('IronOre', irCommon, 42.0, 1, 3);
  AddEntry('SunbloomHerb', irCommon, 30.0, 1, 3);
  AddEntry('HealthElixir', irUncommon, 16.0, 1, 2);
  AddEntry('CrystalShard', irRare, 8.0, 1, 2);
  AddEntry('AegisPlate', irEpic, 3.0, 1, 1);
  AddEntry('SunfireBlade', irLegendary, 1.0, 1, 1);
end;

function TCastleLootTable.EntryCount: Integer;
begin
  Result := Length(FEntries);
end;

function TCastleLootTable.GetEntry(const Index: Integer): TLootDropEntry;
begin
  Result := FEntries[Clamped(Index, 0, Max(0, High(FEntries)))];
end;

function TCastleLootTable.RollSingleDrop(out OutItemId: String;
  out OutQty: Integer; out OutRarity: TItemRarity): Boolean;
var
  I, ChosenIdx, BestLegendIdx: Integer;
  TotalW, Pick, Accum: Single;
begin
  OutItemId := '';
  OutQty := 0;
  OutRarity := irCommon;
  if Length(FEntries) = 0 then
    Exit(False);

  Inc(FTotalRolls);
  Inc(FRollsSinceLegendary);

  BestLegendIdx := -1;
  TotalW := 0.0;
  for I := 0 to High(FEntries) do
  begin
    TotalW := TotalW + FEntries[I].Weight;
    if (FEntries[I].Rarity = irLegendary) and (BestLegendIdx < 0) then
      BestLegendIdx := I;
  end;

  { Bad-luck protection pity trigger }
  if (FLegendaryPityThreshold > 0) and (BestLegendIdx >= 0) and
     (FRollsSinceLegendary >= FLegendaryPityThreshold) then
    ChosenIdx := BestLegendIdx
  else
  begin
    if TotalW <= 1e-6 then
      ChosenIdx := 0
    else
    begin
      Pick := NextRandom01 * TotalW;
      Accum := 0.0;
      ChosenIdx := High(FEntries);
      for I := 0 to High(FEntries) do
      begin
        Accum := Accum + FEntries[I].Weight;
        if Pick <= Accum then
        begin
          ChosenIdx := I;
          Break;
        end;
      end;
    end;
  end;

  OutItemId := FEntries[ChosenIdx].ItemId;
  OutRarity := FEntries[ChosenIdx].Rarity;
  OutQty := NextRandomRange(FEntries[ChosenIdx].MinQty, FEntries[ChosenIdx].MaxQty);
  if OutRarity = irLegendary then
    FRollsSinceLegendary := 0;
  Result := True;
end;

function TCastleLootTable.RollIntoInventory(
  const TargetInv: TCastleInventoryBehavior; out OutItemId: String;
  out OutQty: Integer; out OutRarity: TItemRarity): Boolean;
begin
  if (TargetInv = nil) or (not RollSingleDrop(OutItemId, OutQty, OutRarity)) then
    Exit(False);
  Result := TargetInv.TryAddItem(OutItemId, OutQty);
end;

function TCastleLootTable.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Seed') or
     (PropertyName = 'LegendaryPityThreshold') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleLootTable.LootSummaryBadge: String;
begin
  Result := Format('[LootTable:%d entries Pity %d/%d]', [
    Length(FEntries), FRollsSinceLegendary, FLegendaryPityThreshold]);
end;

function TCastleLootTable.GetConfigJson: String;
var
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('seed', Int64(FSeed));
    Root.Add('pity', FLegendaryPityThreshold);
    Arr := TJSONArray.Create;
    for I := 0 to High(FEntries) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FEntries[I].ItemId);
      Obj.Add('rarity', Ord(FEntries[I].Rarity));
      Obj.Add('weight', FEntries[I].Weight);
      Obj.Add('minQ', FEntries[I].MinQty);
      Obj.Add('maxQ', FEntries[I].MaxQty);
      Arr.Add(Obj);
    end;
    Root.Add('entries', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleLootTable.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FSeed := Cardinal(Max(Int64(1), Root.Get('seed', Int64(FSeed))));
      FLegendaryPityThreshold := Max(0, Root.Get('pity', FLegendaryPityThreshold));
      Arr := Root.Find('entries', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        ClearEntries;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            Obj := TJSONObject(Arr.Items[I]);
            AddEntry(
              Obj.Get('id', 'IronOre'),
              TItemRarity(Clamped(Obj.Get('rarity', 0), 0, Ord(High(TItemRarity)))),
              Obj.Get('weight', 10.0),
              Obj.Get('minQ', 1),
              Obj.Get('maxQ', 1));
          end;
      end;
      ResetRngAndPity;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleInventoryBehavior,
    ['RPG & Narrative', 'Inventory, Paperdoll Equipment & Crafting']);
  RegisterSerializableComponent(TCastleLootTable,
    ['RPG & Narrative', 'Weighted Rarity & Pity Loot Table']);
end.
