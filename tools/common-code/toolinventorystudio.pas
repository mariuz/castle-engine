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

{ Stateless Editor & Headless Helper for RPG Inventory Grids, Paperdoll-to-GAS
  Equipment Sync, Atomic Crafting & Seeded Weighted Loot Tables
  (@link(TInventoryStudioHelper), @link(TInventoryAuditReport))
  (Phase 320 — UE 6.0+ Lyra Inventory, Crafting & Loot Table Parity). }
unit ToolInventoryStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTransform, CastleViewport, CastleGameplayAbility, CastleInventoryCraft;

type
  TInventoryBehaviorArray = array of TCastleInventoryBehavior;
  TLootTableArray = array of TCastleLootTable;
  TRarityHistogram = array [TItemRarity] of Integer;

  { QA summary across all RPG inventory behaviors and loot tables in a design. }
  TInventoryAuditReport = class
  public
    InventoryCount: Integer;
    LootTableCount: Integer;
    TotalOccupiedSlots: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, simulating Monte Carlo loot
    distributions, and auditing @link(TCastleInventoryBehavior) & @link(TCastleLootTable). }
  TInventoryStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanInventoriesAndLoot(const RootComp, DesignOwner: TComponent;
      out OutInventories: TInventoryBehaviorArray;
      out OutLootTables: TLootTableArray); static;

    class procedure SpawnRpgHeroInventoryAndLootChestDemo(
      const RootComp, DesignOwner: TComponent;
      out OutHero: TCastleTransform;
      out OutGas: TCastleAbilitySystemBehavior;
      out OutInv: TCastleInventoryBehavior;
      out OutLoot: TCastleLootTable); static;

    class procedure RunMonteCarloLootSimulation(const ALoot: TCastleLootTable;
      const NumRolls: Integer; out OutHist: TRarityHistogram); static;

    class function AuditInventories(
      const RootComp, DesignOwner: TComponent): TInventoryAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleScene;

constructor TInventoryAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TInventoryAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TInventoryStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
end;

class procedure TInventoryStudioHelper.ScanInventoriesAndLoot(
  const RootComp, DesignOwner: TComponent;
  out OutInventories: TInventoryBehaviorArray;
  out OutLootTables: TLootTableArray);

  procedure AddInvUnique(const V: TCastleInventoryBehavior);
  var
    K: Integer;
  begin
    if (V = nil) or (csTransient in V.ComponentStyle) then
      Exit;
    for K := 0 to High(OutInventories) do
      if OutInventories[K] = V then
        Exit;
    SetLength(OutInventories, Length(OutInventories) + 1);
    OutInventories[High(OutInventories)] := V;
  end;

  procedure AddLootUnique(const L: TCastleLootTable);
  var
    K: Integer;
  begin
    if (L = nil) or (csTransient in L.ComponentStyle) then
      Exit;
    for K := 0 to High(OutLootTables) do
      if OutLootTables[K] = L then
        Exit;
    SetLength(OutLootTables, Length(OutLootTables) + 1);
    OutLootTables[High(OutLootTables)] := L;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleInventoryBehavior then
      AddInvUnique(TCastleInventoryBehavior(C))
    else if C is TCastleLootTable then
      AddLootUnique(TCastleLootTable(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutInventories := nil;
  OutLootTables := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TInventoryStudioHelper.SpawnRpgHeroInventoryAndLootChestDemo(
  const RootComp, DesignOwner: TComponent;
  out OutHero: TCastleTransform;
  out OutGas: TCastleAbilitySystemBehavior;
  out OutInv: TCastleInventoryBehavior;
  out OutLoot: TCastleLootTable);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  HeroBox: TCastleBox;
  Idx: Integer;
begin
  OutHero := nil;
  OutGas := nil;
  OutInv := nil;
  OutLoot := nil;

  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('RpgAdventurer' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  HeroBox := TCastleBox.Create(OwnerToUse);
  HeroBox.Name := 'RpgAdventurer' + IntToStr(Idx);
  HeroBox.Size := Vector3(0.80, 1.80, 0.60);
  HeroBox.Translation := Vector3(0.0, 0.90, 0.0);
  HeroBox.Color := Vector4(0.88, 0.68, 0.24, 1.0);
  ParentTrans.Add(HeroBox);

  OutGas := TCastleAbilitySystemBehavior.Create(OwnerToUse);
  OutGas.Name := 'AdventurerGas_' + IntToStr(Idx);
  OutGas.ApplyPreset(gapVanguardPaladin);
  OutGas.DefineOrSetAttribute(TGasAttributeDef.CreateSimple('AttackPower', 25.0, 0.0, 999.0));
  OutGas.DefineOrSetAttribute(TGasAttributeDef.CreateSimple('SpellPower', 20.0, 0.0, 999.0));
  HeroBox.AddBehavior(OutGas);

  OutInv := TCastleInventoryBehavior.Create(OwnerToUse);
  OutInv.Name := 'AdventurerInventory_' + IntToStr(Idx);
  OutInv.ApplyPreset(ivpFantasyRpgLoadout);
  OutInv.TryAddItem('IronOre', 3);
  OutInv.TryAddItem('CrystalShard', 2);
  OutInv.TryAddItem('SunbloomHerb', 2);
  OutInv.TryAddItem('VanguardHelm', 1);
  HeroBox.AddBehavior(OutInv);

  OutLoot := TCastleLootTable.Create(OwnerToUse);
  OutLoot.Name := 'DungeonBossLootTable_' + IntToStr(Idx);

  OutHero := HeroBox;
end;

class procedure TInventoryStudioHelper.RunMonteCarloLootSimulation(
  const ALoot: TCastleLootTable; const NumRolls: Integer;
  out OutHist: TRarityHistogram);
var
  R: TItemRarity;
  I, Qty: Integer;
  ItemId: String;
begin
  for R in TItemRarity do
    OutHist[R] := 0;
  if ALoot = nil then
    Exit;
  for I := 1 to NumRolls do
    if ALoot.RollSingleDrop(ItemId, Qty, R) then
      Inc(OutHist[R]);
end;

class function TInventoryStudioHelper.AuditInventories(
  const RootComp, DesignOwner: TComponent): TInventoryAuditReport;
var
  Invs: TInventoryBehaviorArray;
  Loots: TLootTableArray;
  I, K: Integer;
  Rec: TCraftingRecipeDef;
  DummyDef: TInventoryItemDef;
begin
  Result := TInventoryAuditReport.Create;
  ScanInventoriesAndLoot(RootComp, DesignOwner, Invs, Loots);
  Result.InventoryCount := Length(Invs);
  Result.LootTableCount := Length(Loots);

  for I := 0 to High(Invs) do
  begin
    Result.TotalOccupiedSlots := Result.TotalOccupiedSlots + Invs[I].UsedSlotCount;
    for K := 0 to Invs[I].RecipeCount - 1 do
    begin
      Rec := Invs[I].GetRecipe(K);
      if not Invs[I].FindItemDef(Rec.OutputItemId, DummyDef) then
        Result.Warnings.Add(Format(
          'Inventory "%s" recipe "%s" references undeclared OutputItemId "%s".',
          [Invs[I].Name, Rec.RecipeId, Rec.OutputItemId]));
    end;
  end;

  for I := 0 to High(Loots) do
    if Loots[I].EntryCount = 0 then
      Result.Warnings.Add(Format(
        'LootTable "%s" has 0 drop entries.', [Loots[I].Name]));
end;

class function TInventoryStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Invs: TInventoryBehaviorArray;
  Loots: TLootTableArray;
  Rep: TInventoryAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanInventoriesAndLoot(RootComp, DesignOwner, Invs, Loots);
  Rep := AuditInventories(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# RPG Inventory, Equipment Paperdoll, Crafting & Loot Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Inventories:** %d (`%d` occupied slots)',
      [Rep.InventoryCount, Rep.TotalOccupiedSlots]));
    SB.AppendLine(Format('- **Loot Tables:** %d', [Rep.LootTableCount]));
    SB.AppendLine('');
    for I := 0 to High(Invs) do
      SB.AppendLine(Format('- `%s`: %s', [Invs[I].Name, Invs[I].InventorySummaryBadge]));
    for I := 0 to High(Loots) do
      SB.AppendLine(Format('- `%s`: %s', [Loots[I].Name, Loots[I].LootSummaryBadge]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
