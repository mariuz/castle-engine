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

{ Stateless Editor & Headless Helper for 2D / 2.5D Bitmask Auto-Tilemaps,
  Greedy Collider Merging & Paper2D Sprite Flipbooks
  (@link(TTilemapStudioHelper), @link(TTilemapAuditReport))
  (Phase 323 — UE 6.0+ Paper2D / PaperZD Parity). }
unit ToolTilemapStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTransform, CastleViewport, CastleTilemap2DPlus;

type
  TAutoTilemapArray = array of TCastleAutoTilemap;
  TFlipbook2DArray = array of TCastleFlipbook2D;

  { QA summary across all auto-tilemaps and Paper2D flipbooks in a design. }
  TTilemapAuditReport = class
  public
    TilemapCount: Integer;
    FlipbookCount: Integer;
    TotalSolidCells: Integer;
    TotalMergedColliders: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastleAutoTilemap) and @link(TCastleFlipbook2D). }
  TTilemapStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanTilemapsAndFlipbooks(const RootComp, DesignOwner: TComponent;
      out OutTilemaps: TAutoTilemapArray;
      out OutFlipbooks: TFlipbook2DArray); static;

    class procedure SpawnAutoTileDungeonAndFlipbookDemo(
      const RootComp, DesignOwner: TComponent;
      out OutTilemap: TCastleAutoTilemap;
      out OutFlipbook: TCastleFlipbook2D); static;

    class function AuditTilemaps(
      const RootComp, DesignOwner: TComponent): TTilemapAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleVectors;

constructor TTilemapAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TTilemapAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TTilemapStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
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

class procedure TTilemapStudioHelper.ScanTilemapsAndFlipbooks(
  const RootComp, DesignOwner: TComponent;
  out OutTilemaps: TAutoTilemapArray;
  out OutFlipbooks: TFlipbook2DArray);

  procedure AddMap(const M: TCastleAutoTilemap);
  var K: Integer;
  begin
    for K := 0 to High(OutTilemaps) do if OutTilemaps[K] = M then Exit;
    SetLength(OutTilemaps, Length(OutTilemaps) + 1);
    OutTilemaps[High(OutTilemaps)] := M;
  end;

  procedure AddFb(const F: TCastleFlipbook2D);
  var K: Integer;
  begin
    for K := 0 to High(OutFlipbooks) do if OutFlipbooks[K] = F then Exit;
    SetLength(OutFlipbooks, Length(OutFlipbooks) + 1);
    OutFlipbooks[High(OutFlipbooks)] := F;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleAutoTilemap then
      AddMap(TCastleAutoTilemap(C))
    else if C is TCastleFlipbook2D then
      AddFb(TCastleFlipbook2D(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutTilemaps := nil;
  OutFlipbooks := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TTilemapStudioHelper.SpawnAutoTileDungeonAndFlipbookDemo(
  const RootComp, DesignOwner: TComponent;
  out OutTilemap: TCastleAutoTilemap;
  out OutFlipbook: TCastleFlipbook2D);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  Idx: Integer;
begin
  OutTilemap := nil;
  OutFlipbook := nil;

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
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('AutoTileDungeon_' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  OutTilemap := TCastleAutoTilemap.Create(OwnerToUse);
  OutTilemap.Name := 'AutoTileDungeon_' + IntToStr(Idx);
  OutTilemap.ApplyPreset(tmpDungeonRoomsAndCorridors);
  ParentTrans.Add(OutTilemap);

  OutFlipbook := TCastleFlipbook2D.Create(OwnerToUse);
  OutFlipbook.Name := 'Paper2DHeroFlipbook_' + IntToStr(Idx);
  OutFlipbook.Translation := Vector3(-3.0, 0.0, 0.0);
  ParentTrans.Add(OutFlipbook);
end;

class function TTilemapStudioHelper.AuditTilemaps(
  const RootComp, DesignOwner: TComponent): TTilemapAuditReport;
var
  Maps: TAutoTilemapArray;
  Fbs: TFlipbook2DArray;
  I: Integer;
begin
  Result := TTilemapAuditReport.Create;
  ScanTilemapsAndFlipbooks(RootComp, DesignOwner, Maps, Fbs);
  Result.TilemapCount := Length(Maps);
  Result.FlipbookCount := Length(Fbs);

  for I := 0 to High(Maps) do
  begin
    Result.TotalSolidCells := Result.TotalSolidCells + Maps[I].SolidCellCount;
    Result.TotalMergedColliders := Result.TotalMergedColliders + Maps[I].MergedColliderCount;
    if Maps[I].SolidCellCount = 0 then
      Result.Warnings.Add(Format(
        'AutoTilemap "%s" has 0 painted solid cells.', [Maps[I].Name]));
  end;

  for I := 0 to High(Fbs) do
    if Fbs[I].ClipCount = 0 then
      Result.Warnings.Add(Format(
        'Flipbook2D "%s" has 0 animation clips registered.', [Fbs[I].Name]));
end;

class function TTilemapStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Maps: TAutoTilemapArray;
  Fbs: TFlipbook2DArray;
  Rep: TTilemapAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanTilemapsAndFlipbooks(RootComp, DesignOwner, Maps, Fbs);
  Rep := AuditTilemaps(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Auto-Tilemap, Greedy Collider & Paper2D Flipbook Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Auto-Tilemaps:** %d (`%d` solid tiles merged into `%d` greedy collider boxes)',
      [Rep.TilemapCount, Rep.TotalSolidCells, Rep.TotalMergedColliders]));
    SB.AppendLine(Format('- **Paper2D Flipbooks:** %d', [Rep.FlipbookCount]));
    SB.AppendLine('');
    for I := 0 to High(Maps) do
      SB.AppendLine(Format('- `%s`: %s', [Maps[I].Name, Maps[I].TilemapSummaryBadge]));
    for I := 0 to High(Fbs) do
      SB.AppendLine(Format('- `%s`: %s', [Fbs[I].Name, Fbs[I].FlipbookSummaryBadge]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
