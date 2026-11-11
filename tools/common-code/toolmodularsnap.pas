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

{ Hierarchy discovery, 1-click modular room/corridor kitbash creation, nearest
  compatible open-socket snapping, seeded zero-overlap PCG dungeon grammar
  assembly, and Markdown reporting for @link(TCastleSnapSocket) and
  @link(TCastleModularPieceBehavior) (Phase 301). }
unit ToolModularSnap;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleUiControls, CastleViewport,
  CastleModularSnap;

const
  ModularGeneratedPieceTag = 7801;

type
  TSnapSocketArray = array of TCastleSnapSocket;
  TModularPieceTransformArray = array of TCastleTransform;

  { Hierarchy scan & overlap audit summary for Modular Snap Studio. }
  TModularSnapSummary = record
    Pieces: TModularPieceTransformArray;
    Sockets: TSnapSocketArray;
    OpenSocketsCount: Integer;
    OccupiedSocketsCount: Integer;
    OverlappingPairsCount: Integer;
    Warnings: array of String;
  end;

  { Stateless editor helper for Modular Socket Snapping & Dungeon Grammar. }
  TModularSnapHelper = class
  public
    class function ScanModularPiecesAndSockets(
      const ARoot: TComponent): TModularSnapSummary;

    class function CreateModularPieceInDesign(
      const ARoot, ADesignOwner: TComponent;
      const AKind: TModularPieceKind;
      const AWorldPos: TVector3): TCastleTransform;

    { Collect all direct/nested @link(TCastleSnapSocket) connectors on @code(APiece). }
    class function CollectPieceSockets(const APiece: TCastleTransform): TSnapSocketArray;

    { Snap @code(AMovingPiece) onto the nearest compatible unoccupied
      @link(TCastleSnapSocket) on another piece within @code(AMaxDistance). }
    class function SnapPieceToNearestOpenSocket(
      const AMovingPiece: TCastleTransform; const ARoot: TComponent;
      const AMaxDistance: Single = 50.0): Boolean;

    { Deterministically assemble a connected, zero-overlap modular dungeon of
      up to @code(ATargetPieceCount) rooms/corridors from @code(ASeed). }
    class function GenerateSeededDungeonLayout(
      const ARoot, ADesignOwner: TComponent;
      const ATargetPieceCount: Integer = 8;
      const ASeed: Integer = 1337): Integer;

    class function ClearGeneratedDungeonPieces(const ARoot: TComponent): Integer;

    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

function ProposeUniqueModularName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindWorldItemsContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindWorldItemsContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function NextXorShift32(var AState: Cardinal): Cardinal;
begin
  if AState = 0 then
    AState := 2463534242;
  AState := AState xor (AState shl 13);
  AState := AState xor (AState shr 17);
  AState := AState xor (AState shl 5);
  Result := AState;
end;

function OwnerPieceOfSocket(const ASocket: TCastleSnapSocket): TCastleTransform;
var
  Cur: TCastleTransform;
begin
  Result := nil;
  if ASocket = nil then
    Exit;
  Cur := ASocket.Parent;
  while Cur <> nil do
  begin
    if Cur.FindBehavior(TCastleModularPieceBehavior) <> nil then
      Exit(Cur);
    Cur := Cur.Parent;
  end;
  Result := ASocket.Parent;
end;

{ TModularSnapHelper --------------------------------------------------------- }

class function TModularSnapHelper.CollectPieceSockets(
  const APiece: TCastleTransform): TSnapSocketArray;
var
  OutArr: TSnapSocketArray;

  procedure Walk(const T: TCastleTransform);
  var
    I, N: Integer;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;
    if (T <> APiece) and (T is TCastleSnapSocket) then
    begin
      N := Length(OutArr);
      SetLength(OutArr, N + 1);
      OutArr[N] := TCastleSnapSocket(T);
    end;
    for I := 0 to T.Count - 1 do
      Walk(T[I]);
  end;

begin
  OutArr := nil;
  Walk(APiece);
  Result := OutArr;
end;

class function TModularSnapHelper.ScanModularPiecesAndSockets(
  const ARoot: TComponent): TModularSnapSummary;
var
  OutSum: TModularSnapSummary;
  Visited: TList;

  procedure AppendWarning(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(OutSum.Warnings);
    SetLength(OutSum.Warnings, N + 1);
    OutSum.Warnings[N] := Msg;
  end;

  procedure AddPiece(const P: TCastleTransform);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Pieces) do
      if OutSum.Pieces[I] = P then
        Exit;
    SetLength(OutSum.Pieces, Length(OutSum.Pieces) + 1);
    OutSum.Pieces[High(OutSum.Pieces)] := P;
  end;

  procedure AddSocket(const S: TCastleSnapSocket);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Sockets) do
      if OutSum.Sockets[I] = S then
        Exit;
    SetLength(OutSum.Sockets, Length(OutSum.Sockets) + 1);
    OutSum.Sockets[High(OutSum.Sockets)] := S;
    if S.Occupied then
      Inc(OutSum.OccupiedSocketsCount)
    else
      Inc(OutSum.OpenSocketsCount);
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleSnapSocket then
      AddSocket(TCastleSnapSocket(C));

    if (C is TCastleTransform) and
       (TCastleTransform(C).FindBehavior(TCastleModularPieceBehavior) <> nil) then
      AddPiece(TCastleTransform(C));

    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        Visit(VP.Items);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;
  end;

var
  I, J: Integer;
  SingleArr: array [0..0] of TCastleTransform;
begin
  OutSum := Default(TModularSnapSummary);
  if ARoot = nil then
  begin
    Result := OutSum;
    Exit;
  end;

  Visited := TList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  for I := 0 to High(OutSum.Pieces) do
    for J := I + 1 to High(OutSum.Pieces) do
    begin
      SingleArr[0] := OutSum.Pieces[J];
      if CheckModularPieceWorldOverlap(OutSum.Pieces[I], nil, SingleArr, 0.12) then
      begin
        Inc(OutSum.OverlappingPairsCount);
        AppendWarning(Format('Modular pieces "%s" and "%s" have overlapping footprints.',
          [OutSum.Pieces[I].Name, OutSum.Pieces[J].Name]));
      end;
    end;

  Result := OutSum;
end;

class function TModularSnapHelper.CreateModularPieceInDesign(
  const ARoot, ADesignOwner: TComponent;
  const AKind: TModularPieceKind;
  const AWorldPos: TVector3): TCastleTransform;
var
  Container: TCastleTransform;
  OwnerToUse: TComponent;
  Beh: TCastleModularPieceBehavior;
  Extents: TVector3;
  BaseName: String;

  procedure AddDoorSocket(const ASuffix: String; const APos, AOutDir: TVector3);
  var
    S: TCastleSnapSocket;
  begin
    S := TCastleSnapSocket.Create(OwnerToUse);
    S.Name := ProposeUniqueModularName(OwnerToUse, Result.Name + '_' + ASuffix);
    S.SocketCategory := 'Doorway_3m';
    S.SetView(APos, AOutDir, Vector3(0.0, 1.0, 0.0));
    Result.Add(S);
  end;

begin
  Result := nil;
  Container := FindWorldItemsContainer(ARoot);
  if Container = nil then
    Exit;

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  case AKind of
    mpkEntryHall:
      begin
        BaseName := 'EntryHall';
        Extents := Vector3(8.0, 4.0, 8.0);
      end;
    mpkCorridorStraight:
      begin
        BaseName := 'Corridor';
        Extents := Vector3(4.0, 4.0, 8.0);
      end;
    mpkCornerTurnL:
      begin
        BaseName := 'CornerTurnL';
        Extents := Vector3(6.0, 4.0, 6.0);
      end;
    mpkCrossJunction:
      begin
        BaseName := 'CrossJunction';
        Extents := Vector3(6.0, 4.0, 6.0);
      end;
    mpkTreasureChamber:
      begin
        BaseName := 'TreasureChamber';
        Extents := Vector3(10.0, 5.0, 10.0);
      end;
  else
    begin
      BaseName := 'ModularPiece';
      Extents := Vector3(6.0, 4.0, 6.0);
    end;
  end;

  Result := TCastleTransform.Create(OwnerToUse);
  Result.Name := ProposeUniqueModularName(OwnerToUse, BaseName);
  Result.Translation := AWorldPos;

  Beh := TCastleModularPieceBehavior.Create(OwnerToUse);
  Beh.Name := ProposeUniqueModularName(OwnerToUse, Result.Name + '_Behavior');
  Beh.PieceKind := AKind;
  Beh.PieceBoundsExtents := Extents;
  Result.AddBehavior(Beh);

  case AKind of
    mpkEntryHall:
      AddDoorSocket('Front', Vector3(0.0, 0.0, Extents.Z * 0.5), Vector3(0.0, 0.0, 1.0));
    mpkCorridorStraight:
      begin
        AddDoorSocket('South', Vector3(0.0, 0.0, Extents.Z * 0.5), Vector3(0.0, 0.0, 1.0));
        AddDoorSocket('North', Vector3(0.0, 0.0, -Extents.Z * 0.5), Vector3(0.0, 0.0, -1.0));
      end;
    mpkCornerTurnL:
      begin
        AddDoorSocket('South', Vector3(0.0, 0.0, Extents.Z * 0.5), Vector3(0.0, 0.0, 1.0));
        AddDoorSocket('East', Vector3(Extents.X * 0.5, 0.0, 0.0), Vector3(1.0, 0.0, 0.0));
      end;
    mpkCrossJunction:
      begin
        AddDoorSocket('South', Vector3(0.0, 0.0, Extents.Z * 0.5), Vector3(0.0, 0.0, 1.0));
        AddDoorSocket('North', Vector3(0.0, 0.0, -Extents.Z * 0.5), Vector3(0.0, 0.0, -1.0));
        AddDoorSocket('East', Vector3(Extents.X * 0.5, 0.0, 0.0), Vector3(1.0, 0.0, 0.0));
        AddDoorSocket('West', Vector3(-Extents.X * 0.5, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0));
      end;
    mpkTreasureChamber:
      AddDoorSocket('South', Vector3(0.0, 0.0, Extents.Z * 0.5), Vector3(0.0, 0.0, 1.0));
  else
    begin
      AddDoorSocket('South', Vector3(0.0, 0.0, Extents.Z * 0.5), Vector3(0.0, 0.0, 1.0));
      AddDoorSocket('North', Vector3(0.0, 0.0, -Extents.Z * 0.5), Vector3(0.0, 0.0, -1.0));
    end;
  end;

  Container.Add(Result);
end;

class function TModularSnapHelper.SnapPieceToNearestOpenSocket(
  const AMovingPiece: TCastleTransform; const ARoot: TComponent;
  const AMaxDistance: Single): Boolean;
var
  Sum: TModularSnapSummary;
  MovingSockets: TSnapSocketArray;
  BestMoving, BestTarget: TCastleSnapSocket;
  BestDistSqr, MaxDistSqr, DistSqr: Single;
  PosA, DirA, UpA, PosB, DirB, UpB: TVector3;
  I, J: Integer;
  OtherOwner: TCastleTransform;
begin
  Result := false;
  if (AMovingPiece = nil) or (ARoot = nil) then
    Exit;

  MovingSockets := CollectPieceSockets(AMovingPiece);
  if Length(MovingSockets) = 0 then
    Exit;

  Sum := ScanModularPiecesAndSockets(ARoot);
  BestMoving := nil;
  BestTarget := nil;
  MaxDistSqr := Sqr(Max(0.1, AMaxDistance));
  BestDistSqr := MaxDistSqr;

  for I := 0 to High(MovingSockets) do
  begin
    if MovingSockets[I].Occupied then
      Continue;
    MovingSockets[I].GetHierarchyWorldFrame(PosA, DirA, UpA);

    for J := 0 to High(Sum.Sockets) do
    begin
      if Sum.Sockets[J].Occupied then
        Continue;
      OtherOwner := OwnerPieceOfSocket(Sum.Sockets[J]);
      if (OtherOwner = nil) or (OtherOwner = AMovingPiece) then
        Continue;
      if not MovingSockets[I].IsCompatibleWith(Sum.Sockets[J]) then
        Continue;

      Sum.Sockets[J].GetHierarchyWorldFrame(PosB, DirB, UpB);
      DistSqr := PointsDistanceSqr(PosA, PosB);
      if DistSqr < BestDistSqr then
      begin
        BestDistSqr := DistSqr;
        BestMoving := MovingSockets[I];
        BestTarget := Sum.Sockets[J];
      end;
    end;
  end;

  if (BestMoving <> nil) and (BestTarget <> nil) then
    Result := SnapModularPieceToTargetSocket(AMovingPiece, BestMoving, BestTarget, true);
end;

class function TModularSnapHelper.ClearGeneratedDungeonPieces(
  const ARoot: TComponent): Integer;
var
  Sum: TModularSnapSummary;
  I: Integer;
  P: TCastleTransform;
begin
  Result := 0;
  Sum := ScanModularPiecesAndSockets(ARoot);
  for I := High(Sum.Pieces) downto 0 do
  begin
    P := Sum.Pieces[I];
    if (P <> nil) and (P.Tag = ModularGeneratedPieceTag) then
    begin
      if P.Parent <> nil then
        P.Parent.Remove(P);
      FreeAndNil(P);
      Inc(Result);
    end;
  end;
end;

class function TModularSnapHelper.GenerateSeededDungeonLayout(
  const ARoot, ADesignOwner: TComponent;
  const ATargetPieceCount: Integer; const ASeed: Integer): Integer;
const
  ExpansionPalette: array [0..3] of TModularPieceKind = (
    mpkCorridorStraight,
    mpkCrossJunction,
    mpkCornerTurnL,
    mpkTreasureChamber
  );
var
  Rng: Cardinal;
  PlacedPieces: TModularPieceTransformArray;
  OpenSockets: TSnapSocketArray;
  BlockedSockets: TList;
  EntryPiece, CandPiece, TargetOwner: TCastleTransform;
  TargetSock: TCastleSnapSocket;
  CandSockets: TSnapSocketArray;
  TargetCount, GuardSteps, SockPickIdx, KindTry, KindIdx, I, N: Integer;
  PlacedThisStep: Boolean;

  procedure RefreshOpenSocketPool;
  var
    PIdx, SIdx: Integer;
    PSocks: TSnapSocketArray;
  begin
    OpenSockets := nil;
    for PIdx := 0 to High(PlacedPieces) do
    begin
      PSocks := CollectPieceSockets(PlacedPieces[PIdx]);
      for SIdx := 0 to High(PSocks) do
        if (not PSocks[SIdx].Occupied) and
           (BlockedSockets.IndexOf(PSocks[SIdx]) < 0) then
        begin
          SetLength(OpenSockets, Length(OpenSockets) + 1);
          OpenSockets[High(OpenSockets)] := PSocks[SIdx];
        end;
    end;
  end;

begin
  Result := 0;
  if ARoot = nil then
    Exit;

  ClearGeneratedDungeonPieces(ARoot);
  TargetCount := Clamped(ATargetPieceCount, 1, 64);
  Rng := Cardinal(Max(1, Abs(ASeed)));
  PlacedPieces := nil;

  BlockedSockets := TList.Create;
  try
    EntryPiece := CreateModularPieceInDesign(ARoot, ADesignOwner, mpkEntryHall, TVector3.Zero);
    if EntryPiece = nil then
      Exit;
    EntryPiece.Tag := ModularGeneratedPieceTag;
    SetLength(PlacedPieces, 1);
    PlacedPieces[0] := EntryPiece;

    GuardSteps := 0;
    while (Length(PlacedPieces) < TargetCount) and (GuardSteps < TargetCount * 16) do
    begin
      Inc(GuardSteps);
      RefreshOpenSocketPool;
      if Length(OpenSockets) = 0 then
        Break;

      SockPickIdx := Integer(NextXorShift32(Rng) mod Cardinal(Length(OpenSockets)));
      TargetSock := OpenSockets[SockPickIdx];
      TargetOwner := OwnerPieceOfSocket(TargetSock);
      PlacedThisStep := false;

      for KindTry := 0 to High(ExpansionPalette) do
      begin
        { Bias final room toward TreasureChamber; avoid capping the last open
          socket with a 1-socket TreasureChamber before the final step. }
        if (Length(PlacedPieces) = TargetCount - 1) and (KindTry = 0) then
          KindIdx := 3
        else
        if (Length(OpenSockets) <= 1) and (Length(PlacedPieces) < TargetCount - 1) then
          KindIdx := (Integer(NextXorShift32(Rng) mod 3) + KindTry) mod 3
        else
          KindIdx := (Integer(NextXorShift32(Rng) mod 4) + KindTry) mod 4;

        CandPiece := CreateModularPieceInDesign(
          ARoot, ADesignOwner, ExpansionPalette[KindIdx], TVector3.Zero);
        if CandPiece = nil then
          Break;
        CandPiece.Tag := ModularGeneratedPieceTag;
        CandSockets := CollectPieceSockets(CandPiece);

        if (Length(CandSockets) > 0) and
           SnapModularPieceToTargetSocket(CandPiece, CandSockets[0], TargetSock, false) and
           (not CheckModularPieceWorldOverlap(CandPiece, TargetOwner, PlacedPieces, 0.12)) then
        begin
          CandSockets[0].Occupied := true;
          TargetSock.Occupied := true;
          CandSockets[0].ConnectedSocketName := TargetSock.Name;
          TargetSock.ConnectedSocketName := CandSockets[0].Name;

          N := Length(PlacedPieces);
          SetLength(PlacedPieces, N + 1);
          PlacedPieces[N] := CandPiece;
          PlacedThisStep := true;
          Break;
        end else
        begin
          if CandPiece.Parent <> nil then
            CandPiece.Parent.Remove(CandPiece);
          FreeAndNil(CandPiece);
        end;
      end;

      if not PlacedThisStep then
        BlockedSockets.Add(TargetSock);
    end;

    Result := Length(PlacedPieces);
  finally
    FreeAndNil(BlockedSockets);
  end;
  for I := 0 to High(PlacedPieces) do
    ; // suppress unused hint
end;

class function TModularSnapHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Sum: TModularSnapSummary;
  SB: TStringBuilder;
  I: Integer;
  P: TCastleTransform;
  Beh: TCastleModularPieceBehavior;
  B: TBox3D;
begin
  Sum := ScanModularPiecesAndSockets(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Modular Socket Snapping & Dungeon Grammar Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Modular Pieces**: `%d` | **Total Sockets**: `%d` (`%d` Open, `%d` Occupied) | **Overlaps**: `%d`',
      [Length(Sum.Pieces), Length(Sum.Sockets),
       Sum.OpenSocketsCount, Sum.OccupiedSocketsCount, Sum.OverlappingPairsCount]));
    SB.AppendLine;

    if Length(Sum.Pieces) > 0 then
    begin
      SB.AppendLine('| Piece | Archetype | World Center `(X, Y, Z)` | Footprint `(W x D)` |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to High(Sum.Pieces) do
      begin
        P := Sum.Pieces[I];
        Beh := P.FindBehavior(TCastleModularPieceBehavior) as TCastleModularPieceBehavior;
        B := Beh.ComputeHierarchyWorldBox;
        SB.AppendLine(Format('| `%s` | %s | `(%.1f, %.1f, %.1f)` | `%.1f x %.1f m` |',
          [P.Name, TCastleModularPieceBehavior.PieceKindDisplayName(Beh.PieceKind),
           B.Center.X, B.Center.Y, B.Center.Z,
           Beh.PieceBoundsExtents.X, Beh.PieceBoundsExtents.Z]));
      end;
      SB.AppendLine;
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Overlap & Socket Diagnostics');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- [!] ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
