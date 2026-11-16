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

{ Automated unit tests for Phase 323 2D / 2.5D Bitmask Auto-Tilemap (4-Bit
  Cardinal & 8-Bit Corner-Gated Wang/Blob), Greedy Collider Rectangle Merging &
  Paper2D Sprite Flipbook Studio (@link(TCastleAutoTilemap),
  @link(TCastleFlipbook2D), @link(TTilemapStudioHelper)). }
unit TestToolTilemapStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolTilemapStudio = class(TCastleTestCase)
  strict private
    FFiredFlipbookEvents: TStringList;
    procedure HandleFlipbookNotify(Sender: TObject; const ClipName: String;
      const AtlasFrameIndex: Integer);
  published
    procedure TestCardinal4BitAndCornerGated8BitBlobAutotileMasksAndGreedyColliderMerge;
    procedure TestFlipbook2DUvFrameSteppingNonLoopHoldAndFrameExactNotifyCallback;
  end;

implementation

uses
  CastleVectors, CastleViewport, CastleTransform, CastleComponentSerialize,
  CastleTilemap2DPlus, ToolTilemapStudio;

procedure TTestToolTilemapStudio.HandleFlipbookNotify(Sender: TObject;
  const ClipName: String; const AtlasFrameIndex: Integer);
begin
  if FFiredFlipbookEvents <> nil then
    FFiredFlipbookEvents.Add(Format('%s:%d', [ClipName, AtlasFrameIndex]));
end;

procedure TTestToolTilemapStudio.TestCardinal4BitAndCornerGated8BitBlobAutotileMasksAndGreedyColliderMerge;
var
  OwnerComp, LoadedComp: TComponent;
  Vp: TCastleViewport;
  Map, LoadedMap: TCastleAutoTilemap;
  Fb: TCastleFlipbook2D;
  RayHit: TRayCollision;
  JsonStr: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TTilemapStudioHelper.SpawnAutoTileDungeonAndFlipbookDemo(Vp, OwnerComp, Map, Fb);

    { 1. Isolated tile -> 4-bit = 0, 8-bit = 0 }
    Map.ResizeGrid(12, 10, True);
    Map.SetTile(2, 2, TCastleAutoTilemap.TileSolidWall, False);
    AssertEquals(0, Map.ComputeCardinalMask4Bit(2, 2));
    AssertEquals(0, Map.ComputeBlobMask8Bit(2, 2));

    { 2. Plus '+' cross without diagonal corners -> 4-bit = 15 (N+E+S+W), 8-bit = 15 (corners empty!) }
    Map.ClearCells;
    Map.SetTile(5, 5, TCastleAutoTilemap.TileSolidWall, False);
    Map.SetTile(5, 6, TCastleAutoTilemap.TileSolidWall, False); // N (1)
    Map.SetTile(6, 5, TCastleAutoTilemap.TileSolidWall, False); // E (2)
    Map.SetTile(5, 4, TCastleAutoTilemap.TileSolidWall, False); // S (4)
    Map.SetTile(4, 5, TCastleAutoTilemap.TileSolidWall, False); // W (8)
    AssertEquals(15, Map.ComputeCardinalMask4Bit(5, 5));
    AssertEquals(15, Map.ComputeBlobMask8Bit(5, 5));

    { Corner-gating test: setting NE corner (6,6) when N and E exist sets bit 16 (15 + 16 = 31),
      whereas setting NW corner (4,6) if W (4,5) is cleared MUST NOT set bit 128! }
    Map.SetTile(6, 6, TCastleAutoTilemap.TileSolidWall, False);
    AssertEquals(31, Map.ComputeBlobMask8Bit(5, 5));
    Map.SetTile(4, 5, TCastleAutoTilemap.TileEmpty, False); // clear West
    Map.SetTile(4, 6, TCastleAutoTilemap.TileSolidWall, False); // NW present without W!
    AssertEquals(7 + 16, Map.ComputeBlobMask8Bit(5, 5)); // N(1)+E(2)+S(4)+NE(16) = 23 (NW gated out!)

    { Full 3x3 solid block -> center has all 8 bits = 255, and Greedy Mesher merges 9 cells into 1 box! }
    Map.ClearCells;
    Map.PaintRect(2, 2, 7, 5, TCastleAutoTilemap.TileSolidWall, True, True); // 6x4 = 24 solid cells!
    AssertEquals(255, Map.ComputeBlobMask8Bit(4, 3));
    AssertEquals(24, Map.SolidCellCount);
    AssertEquals(1, Map.MergedColliderCount); // 24 cells -> 1 single greedy collider box!
    AssertEquals(6, Map.GetMergedRect(0).SpanW);
    AssertEquals(4, Map.GetMergedRect(0).SpanH);

    { 3. Verify 3D WorldRay hits the extruded greedy box }
    RayHit := Vp.Items.WorldRay(
      Vector3(-1.0, 5.0, 1.0), Vector3(0.0, -1.0, 0.0));
    try
      AssertTrue(RayHit <> nil);
    finally
      FreeAndNil(RayHit);
    end;

    { 4. csTransient-clean JSON roundtrip }
    JsonStr := ComponentToString(Map);
    LoadedComp := StringToComponent(JsonStr, OwnerComp);
    AssertTrue(LoadedComp is TCastleAutoTilemap);
    LoadedMap := TCastleAutoTilemap(LoadedComp);
    AssertEquals(24, LoadedMap.SolidCellCount);
    AssertEquals(1, LoadedMap.MergedColliderCount);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolTilemapStudio.TestFlipbook2DUvFrameSteppingNonLoopHoldAndFrameExactNotifyCallback;
var
  OwnerComp: TComponent;
  Vp: TCastleViewport;
  Map: TCastleAutoTilemap;
  Fb: TCastleFlipbook2D;
  Rep: TTilemapAuditReport;
  U0, V0, U1, V1: Single;
  K: Integer;
begin
  FFiredFlipbookEvents := TStringList.Create;
  OwnerComp := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(OwnerComp);
    Vp.Name := 'MainViewport';
    TTilemapStudioHelper.SpawnAutoTileDungeonAndFlipbookDemo(Vp, OwnerComp, Map, Fb);
    Fb.OnFlipbookNotify := {$ifdef FPC}@{$endif}HandleFlipbookNotify;

    { 1. AttackSlash: StartFrame=10, FrameCount=4 @ 10 FPS (0.10s/frame), Looping=False, NotifyOffset=2 }
    AssertTrue(Fb.PlayClip('AttackSlash'));
    AssertEquals(10, Fb.CurrentAtlasFrameIndex);
    Fb.CurrentUvBounds(U0, V0, U1, V1);
    { Frame 10 in 4x4 atlas: Col = 2 -> U in [0.50 .. 0.75], RowFromTop = 2 -> V in [0.25 .. 0.50] }
    AssertSameValue(0.50, U0, 1e-4);
    AssertSameValue(0.75, U1, 1e-4);
    AssertSameValue(0.25, V0, 1e-4);
    AssertSameValue(0.50, V1, 1e-4);

    for K := 1 to 6 do
      Fb.StepFlipbook(0.10);

    { Non-looping clip stops cleanly at final frame 13 (10 + 3) and fired notify at frame 12 exactly once! }
    AssertFalse(Fb.IsPlaying);
    AssertEquals(13, Fb.CurrentAtlasFrameIndex);
    AssertEquals(1, FFiredFlipbookEvents.Count);
    AssertEquals('AttackSlash:12', FFiredFlipbookEvents[0]);

    Rep := TTilemapStudioHelper.AuditTilemaps(Vp, OwnerComp);
    try
      AssertEquals(1, Rep.TilemapCount);
      AssertEquals(1, Rep.FlipbookCount);
      AssertEquals(0, Rep.Warnings.Count);
    finally
      FreeAndNil(Rep);
    end;
  finally
    FreeAndNil(OwnerComp);
    FreeAndNil(FFiredFlipbookEvents);
  end;
end;

initialization
  RegisterTest(TTestToolTilemapStudio);
end.
