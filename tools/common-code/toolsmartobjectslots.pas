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

{ Stateless helper for Multi-Slot SmartObject Queue & Cooldown Studio (Phase 368). }
unit ToolSmartObjectSlots;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSmartObjectSlots;

type
  TSmartObjectSlotsHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindSmartObjectInHierarchy(const Root: TComponent): TCastleMultiSlotSmartObject;
    class function SpawnTavernSmartTableDemo(const Root, DesignOwner: TComponent;
      out Station: TCastleMultiSlotSmartObject): Boolean;
    class function GenerateSmartSlotsReport(const Station: TCastleMultiSlotSmartObject): String;
  end;

implementation

class function TSmartObjectSlotsHelper.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TSmartObjectSlotsHelper.FindSmartObjectInHierarchy(
  const Root: TComponent): TCastleMultiSlotSmartObject;

  function WalkTransform(const T: TCastleTransform): TCastleMultiSlotSmartObject;
  var
    I: Integer;
  begin
    if T is TCastleMultiSlotSmartObject then
      Exit(TCastleMultiSlotSmartObject(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleMultiSlotSmartObject then Exit(TCastleMultiSlotSmartObject(Root));
  if Root is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(Root));
    if Result <> nil then Exit;
  end;
  Vp := FindViewport(Root);
  if (Vp <> nil) and (Vp.Items <> nil) then
  begin
    Result := WalkTransform(Vp.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to Root.ComponentCount - 1 do
    if Root.Components[I] is TCastleMultiSlotSmartObject then
      Exit(TCastleMultiSlotSmartObject(Root.Components[I]));
end;

class function TSmartObjectSlotsHelper.SpawnTavernSmartTableDemo(
  const Root, DesignOwner: TComponent;
  out Station: TCastleMultiSlotSmartObject): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  TableBox: TCastleBox;
begin
  Result := False;
  Station := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('TavernOakTableMesh') = nil then
  begin
    TableBox := TCastleBox.Create(OwnerComp);
    TableBox.Name := 'TavernOakTableMesh';
    TableBox.Size := Vector3(1.8, 0.85, 1.8);
    TableBox.Translation := Vector3(0.0, 0.425, 0.0);
    TableBox.Color := Vector4(0.54, 0.36, 0.20, 1.0);
    Vp.Items.Add(TableBox);
  end;

  Station := FindSmartObjectInHierarchy(Root);
  if Station = nil then
  begin
    Station := TCastleMultiSlotSmartObject.Create(OwnerComp);
    Station.Name := 'MultiSlotSmartObject1';
    Station.Preset := smspTavernFourSeatTable;
    Vp.Items.Add(Station);
  end;
  Result := True;
end;

class function TSmartObjectSlotsHelper.GenerateSmartSlotsReport(
  const Station: TCastleMultiSlotSmartObject): String;
var
  I: Integer;
  S: TSmartObjectSlotEntry;
  W: TSmartObjectWaiter;
  ReqLabel, UserLabel: String;
begin
  if Station = nil then
    Exit('# Multi-Slot SmartObject Queue & Cooldown Report' + LineEnding + LineEnding +
         '_No `TCastleMultiSlotSmartObject` found in design._');

  Result :=
    '# Multi-Slot SmartObject Queue & Cooldown Report (Phase 368)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Archetype** | `%s` (%s) |', [Station.Name, SmartMultiSlotPresetToString(Station.Preset)]) + LineEnding +
    Format('| **Available Slots** | **`%d / %d` free** |', [Station.FreeSlotCount, Station.SlotCount]) + LineEnding +
    Format('| **FIFO Wait-Queue** | **`%d` waiting** (`%d` total promotions) |', [
      Station.WaitQueueCount, Station.TotalPromotions]) + LineEnding + LineEnding +
    '## Docking Slots' + LineEnding +
    '| Slot ID | Required Tag | State | Occupant | Cooldown |' + LineEnding +
    '| :--- | :--- | :--- | :--- | :--- |' + LineEnding;

  for I := 0 to Station.SlotCount - 1 do
  begin
    S := Station.GetSlot(I);
    if S.RequiredUserTag <> '' then ReqLabel := S.RequiredUserTag else ReqLabel := '(Any)';
    if S.ActiveUserId <> '' then UserLabel := S.ActiveUserId else UserLabel := '-';
    Result := Result + Format('| `%s` | `%s` | **`%s`** | `%s` | `%.1f / %.1fs` |', [
      S.SlotId, ReqLabel, SmartSlotStateToString(S.State), UserLabel,
      S.RemainingCooldownSec, S.CooldownDurationSec]) + LineEnding;
  end;

  if Station.WaitQueueCount > 0 then
  begin
    Result := Result + LineEnding + '## FIFO Wait-Queue' + LineEnding;
    for I := 0 to Station.WaitQueueCount - 1 do
    begin
      W := Station.GetWaiter(I);
      Result := Result + Format('%d. **`%s`** (`Tags: %s`)' + LineEnding, [
        I + 1, W.UserId, W.UserTagsCsv]);
    end;
  end;
end;

end.
