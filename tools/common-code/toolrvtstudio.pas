{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for the Runtime Virtual Texture (RVT) Tile Page Cache &
  Persistent Snow/Mud Footstep Trail Studio (Phase 350). }
unit ToolRvtStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform,
  CastleRuntimeVt;

type
  TRvtStudioSummary = record
    RvtCount: Integer;
    OccupiedPages: Integer;
    TotalPageSlots: Integer;
    CacheHits: Integer;
    CacheMisses: Integer;
    Evictions: Integer;
    DeepestRutMeters: Single;
    HighestBermMeters: Single;
    WarningsCount: Integer;
  end;

  TRvtStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstRvt(const ARoot: TComponent): TCastleRuntimeVirtualTexture; static;

    class function SpawnAlpineSnowfieldRvtDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ARvt: TCastleRuntimeVirtualTexture): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TRvtStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TRvtStudioHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TRvtStudioHelper.FindFirstRvt(
  const ARoot: TComponent): TCastleRuntimeVirtualTexture;

  function ScanRec(const T: TCastleTransform): TCastleRuntimeVirtualTexture;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleRuntimeVirtualTexture then
      Exit(TCastleRuntimeVirtualTexture(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TRvtStudioHelper.SpawnAlpineSnowfieldRvtDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ARvt: TCastleRuntimeVirtualTexture): Boolean;
var
  RootT: TCastleTransform;
  I: Integer;
  ZPos, StepX: Single;
begin
  ARvt := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  ARvt := TCastleRuntimeVirtualTexture.Create(ADesignOwner);
  ARvt.Name := MakeUniqueName(ADesignOwner, 'AlpineSnowfieldRVT');
  ARvt.SurfaceMaterial := rsmAlpineFreshSnow;
  ARvt.WorldExtentXZ := 24.0;
  ARvt.GridResolution := 48;
  RootT.Add(ARvt);

  { Stamp alternating left/right hiker boot prints + parallel sled runner ruts }
  for I := -5 to 5 do
  begin
    ZPos := I * 1.45;
    if (I mod 2) = 0 then StepX := -2.6 else StepX := -1.9;
    ARvt.StampFootprintOrTire(StepX, ZPos, 0.55, 0.24);
    ARvt.StampFootprintOrTire(+3.2, ZPos, 0.65, 0.28);
  end;
  Result := True;
end;

class function TRvtStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TRvtStudioSummary;
var
  R: TCastleRuntimeVirtualTexture;
begin
  Result := Default(TRvtStudioSummary);
  R := FindFirstRvt(ARoot);
  if R = nil then Exit;

  Result.RvtCount := 1;
  Result.OccupiedPages := R.OccupiedPageCount;
  Result.TotalPageSlots := R.PhysicalCacheSlots;
  Result.CacheHits := R.CacheHitCount;
  Result.CacheMisses := R.CacheMissCount;
  Result.Evictions := R.EvictionCount;
  Result.DeepestRutMeters := R.MinDepressionMeters;
  Result.HighestBermMeters := R.MaxBermRimMeters;

  if (R.CacheMissCount > 8) and (R.EvictionCount > R.CacheHitCount) then
  begin
    Inc(Result.WarningsCount);
    if AWarnings <> nil then
      AWarnings.Add(Format('%s is thrashing LRU pages (%d evictions vs %d hits); consider increasing PhysicalCacheSlots.', [
        R.Name, R.EvictionCount, R.CacheHitCount]));
  end;
end;

class function TRvtStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TRvtStudioSummary;
  R: TCastleRuntimeVirtualTexture;
  SB: TStringBuilder;
  I: Integer;
  Slot: TRvtPhysicalPageSlot;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    R := FindFirstRvt(ARoot);
    SB.AppendLine('# Castle Game Engine — Runtime Virtual Texture & Snow/Mud Trail Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Physical Page Residency**: `%d / %d` slots (`%d` hits, `%d` misses, `%d` LRU evictions)', [
      Sum.OccupiedPages, Sum.TotalPageSlots, Sum.CacheHits, Sum.CacheMisses, Sum.Evictions]));
    SB.AppendLine(Format('- **Deformable Depth Range**: `%.3fm` deepest rut .. `+%.3fm` raised rim berm', [
      Sum.DeepestRutMeters, Sum.HighestBermMeters]));
    if R <> nil then
    begin
      SB.AppendLine(Format('- **Surface Material**: `%s` (`%d x %d` grid)', [
        RvtMaterialToDisplayName(R.SurfaceMaterial), R.GridResolution, R.GridResolution]));
      SB.AppendLine;
      SB.AppendLine('| Slot | Virtual Tile `(X, Z)` | Mip | Hits | Stamp |');
      SB.AppendLine('| ---: | :---: | ---: | ---: | ---: |');
      for I := 0 to R.PhysicalCacheSlots - 1 do
      begin
        Slot := R.GetPageSlot(I);
        if Slot.Occupied then
          SB.AppendLine(Format('| `%d` | `(%d, %d)` | `%d` | `%d` | `%d` |', [
            I, Slot.VirtualTileX, Slot.VirtualTileZ, Slot.MipLevel, Slot.HitCount, Slot.LastUsedStamp]));
      end;
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
