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

{ Automated unit tests for Phase 301 Modular Socket Snapping, Room/Dungeon
  Grammar & Kitbash Assembler Studio (@link(TCastleSnapSocket),
  @link(TCastleModularPieceBehavior), and @link(TModularSnapHelper)). }
unit TestToolModularSnap;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolModularSnap = class(TCastleTestCase)
  published
    procedure TestOpposing180SocketSnapRotatedRoomCategoryFilterAndJsonRoundtrip;
    procedure TestSeededZeroOverlapDungeonGrammarOverlapAuditAndCleanup;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize, CastleTransform,
  EditorRegisterAllComponents,
  CastleModularSnap, ToolModularSnap;

procedure TTestToolModularSnap.TestOpposing180SocketSnapRotatedRoomCategoryFilterAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  World, LoadedWorld, Hall, Corridor, PipePiece: TCastleTransform;
  HallSocks, CorrSocks, PipeSocks: TSnapSocketArray;
  HallPos, HallOut, HallUp, CorrPos, CorrOut, CorrUp: TVector3;
  JsonStr: String;
  LoadedSum: TModularSnapSummary;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    { 1. EntryHall (8x4x8m) placed at (10, 0, 5) rotated to face +X -> North socket at (14, 0, 5) outward (+1, 0, 0) }
    Hall := TModularSnapHelper.CreateModularPieceInDesign(
      World, DesignOwner, mpkEntryHall, Vector3(10.0, 0.0, 5.0));
    Hall.SetView(Vector3(10.0, 0.0, 5.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0));
    HallSocks := TModularSnapHelper.CollectPieceSockets(Hall);
    AssertEquals(1, Length(HallSocks));
    HallSocks[0].GetHierarchyWorldFrame(HallPos, HallOut, HallUp);
    AssertVectorEquals(Vector3(14.0, 0.0, 5.0), HallPos, 1e-3);
    AssertVectorEquals(Vector3(1.0, 0.0, 0.0), HallOut, 1e-3);

    { 2. Straight Corridor (4x4x8m) snapped onto Hall's doorway }
    Corridor := TModularSnapHelper.CreateModularPieceInDesign(
      World, DesignOwner, mpkCorridorStraight, Vector3(12.0, 0.0, 8.0));
    AssertTrue(TModularSnapHelper.SnapPieceToNearestOpenSocket(Corridor, World, 50.0));

    CorrSocks := TModularSnapHelper.CollectPieceSockets(Corridor);
    AssertEquals(2, Length(CorrSocks));
    AssertTrue(HallSocks[0].Occupied);

    { Find whichever Corridor socket mated with HallSocks[0] }
    if CorrSocks[0].Occupied then
      CorrSocks[0].GetHierarchyWorldFrame(CorrPos, CorrOut, CorrUp)
    else
      CorrSocks[1].GetHierarchyWorldFrame(CorrPos, CorrOut, CorrUp);

    AssertVectorEquals(HallPos, CorrPos, 1e-3);
    AssertVectorEquals(-HallOut, CorrOut, 1e-3); // exact 180-degree opposing normal!
    AssertVectorEquals(Vector3(18.0, 0.0, 5.0), Corridor.Translation, 1e-3);

    { 3. Incompatible socket category ('Pipe_Flange' vs 'Doorway_3m') must reject snap }
    PipePiece := TModularSnapHelper.CreateModularPieceInDesign(
      World, DesignOwner, mpkTreasureChamber, Vector3(22.0, 0.0, 5.0));
    PipeSocks := TModularSnapHelper.CollectPieceSockets(PipePiece);
    PipeSocks[0].SocketCategory := 'Pipe_Flange';
    AssertFalse(TModularSnapHelper.SnapPieceToNearestOpenSocket(PipePiece, World, 50.0));

    { 4. JSON roundtrip without csTransient greybox mesh bloat }
    JsonStr := ComponentToString(World);
    AssertEquals(0, Pos('TTriangleSetNode', JsonStr));

    LoadedOwner := TComponent.Create(nil);
    try
      LoadedWorld := StringToComponent(JsonStr, LoadedOwner) as TCastleTransform;
      try
        LoadedSum := TModularSnapHelper.ScanModularPiecesAndSockets(LoadedWorld);
        AssertEquals(3, Length(LoadedSum.Pieces));
        AssertEquals(2, LoadedSum.OccupiedSocketsCount);
      finally
        FreeAndNil(LoadedWorld);
      end;
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolModularSnap.TestSeededZeroOverlapDungeonGrammarOverlapAuditAndCleanup;
var
  DesignOwner: TComponent;
  World, CollidingPiece: TCastleTransform;
  PlacedA, PlacedB, Removed: Integer;
  SumA, SumB: TModularSnapSummary;
  LastPosRun1, LastPosRun2: TVector3;
  Report: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    { 1. Seeded PCG dungeon layout places 9 connected rooms with 0 overlaps }
    PlacedA := TModularSnapHelper.GenerateSeededDungeonLayout(World, DesignOwner, 9, 4242);
    AssertEquals(9, PlacedA);
    SumA := TModularSnapHelper.ScanModularPiecesAndSockets(World);
    AssertEquals(9, Length(SumA.Pieces));
    AssertEquals(0, SumA.OverlappingPairsCount);
    LastPosRun1 := SumA.Pieces[High(SumA.Pieces)].Translation;

    { 2. Identical seed 4242 reproduces identical dungeon coordinates }
    PlacedB := TModularSnapHelper.GenerateSeededDungeonLayout(World, DesignOwner, 9, 4242);
    AssertEquals(9, PlacedB);
    SumB := TModularSnapHelper.ScanModularPiecesAndSockets(World);
    LastPosRun2 := SumB.Pieces[High(SumB.Pieces)].Translation;
    AssertVectorEquals(LastPosRun1, LastPosRun2, 1e-4);

    { 3. Deliberately overlapping piece at origin triggers overlap audit warning }
    CollidingPiece := TModularSnapHelper.CreateModularPieceInDesign(
      World, DesignOwner, mpkEntryHall, Vector3(0.5, 0.0, 0.5));
    AssertTrue(CollidingPiece <> nil);
    SumB := TModularSnapHelper.ScanModularPiecesAndSockets(World);
    AssertTrue(SumB.OverlappingPairsCount >= 1);

    Report := TModularSnapHelper.BuildMarkdownReport(World);
    AssertTrue(Pos('Overlap & Socket Diagnostics', Report) > 0);

    { 4. ClearGeneratedDungeonPieces removes only generated pieces (leaving manual CollidingPiece) }
    Removed := TModularSnapHelper.ClearGeneratedDungeonPieces(World);
    AssertEquals(9, Removed);
    SumB := TModularSnapHelper.ScanModularPiecesAndSockets(World);
    AssertEquals(1, Length(SumB.Pieces));
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolModularSnap);
end.
