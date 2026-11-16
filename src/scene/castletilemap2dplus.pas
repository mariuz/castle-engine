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

{ 2D / 2.5D Bitmask Auto-Tilemap (4-Bit Cardinal & 8-Bit Corner-Gated Wang /
  Blob Bitmasking, Exact 2D Greedy Collider Rectangle Merging & Extruded PBR
  Meshes) and Paper2D-Style Multi-Clip Sprite Flipbooks with Frame-Exact
  Notify Callbacks (@link(TCastleAutoTilemap), @link(TCastleFlipbook2D))
  (Phase 323 — UE 6.0+ Paper2D / PaperZD & Auto-Tilemap Parity). }
unit CastleTilemap2DPlus;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleScene, X3DNodes;

type
  { Spatial plane orientation of the 2D / 2.5D auto-tilemap. }
  TTilemapOrientation = (
    tmoTopDownXZ,
    tmoSideScrollerXY
  );

  { Built-in auto-tilemap layout presets. }
  TTilemapPreset = (
    tmpCustom,
    tmpDungeonRoomsAndCorridors,
    tmpSideScrollerPlatformer
  );

  { Greedy-merged contiguous rectangle of identical solid tiles. }
  TMergedTileRect = record
    StartX: Integer;
    StartY: Integer;
    SpanW: Integer;
    SpanH: Integer;
    TileId: Byte;
  end;
  TMergedTileRectArray = array of TMergedTileRect;

  { Named sprite flipbook animation clip with frame-exact notify index. }
  TFlipbookClipDef = record
    ClipName: String;
    StartFrame: Integer;
    FrameCount: Integer;
    FramesPerSec: Single;
    Looping: Boolean;
    NotifyFrameOffset: Integer; // -1 = disabled; 0..FrameCount-1 = fire OnFlipbookNotify
  end;
  TFlipbookClipDefArray = array of TFlipbookClipDef;

  TFlipbookNotifyEvent = procedure(Sender: TObject; const ClipName: String;
    const AtlasFrameIndex: Integer) of object;

  { 2D / 2.5D Auto-Tilemap supporting 4-bit cardinal (0..15) and 8-bit
    corner-gated Blob/Wang (0..255) neighbor bitmasking, exact 2D greedy
    collider rectangle merging, and @code(csTransient) extruded 3D geometry. }
  TCastleAutoTilemap = class(TCastleTransform)
  public
    const
      DefaultGridWidth = 16;
      DefaultGridHeight = 12;
      DefaultTileSize = 1.0;
      DefaultWallExtrudeHeight = 1.6;
      TileEmpty = 0;
      TileSolidWall = 1;
      TileWaterHazard = 2;
      TileGrassPlatform = 3;
  strict private
    FPreset: TTilemapPreset;
    FOrientation: TTilemapOrientation;
    FGridWidth: Integer;
    FGridHeight: Integer;
    FTileSize: Single;
    FWallExtrudeHeight: Single;
    FCells: array of Byte;
    FMergedRects: TMergedTileRectArray;
    FMeshRoot: TCastleTransform;

    procedure SetPreset(const Value: TTilemapPreset);
    procedure SetOrientation(const Value: TTilemapOrientation);
    procedure SetTileSize(const Value: Single);
    procedure SetWallExtrudeHeight(const Value: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function InBounds(const AX, AY: Integer): Boolean;
    function MatchesTerrain(const AX, AY: Integer; const ATerrainId: Byte): Boolean;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TTilemapPreset): String; static;

    procedure ResizeGrid(const AWidth, AHeight: Integer; const ClearAll: Boolean = True);
    procedure ClearCells(const FillTileId: Byte = TileEmpty);
    procedure ApplyPreset(const APreset: TTilemapPreset);

    function GetTile(const AX, AY: Integer): Byte;
    procedure SetTile(const AX, AY: Integer; const ATileId: Byte;
      const RebuildNow: Boolean = True);
    procedure PaintRect(const X0, Y0, X1, Y1: Integer; const ATileId: Byte;
      const Filled: Boolean = True; const RebuildNow: Boolean = True);

    { 4-bit cardinal auto-tile bitmask (North=1, East=2, South=4, West=8 -> 0..15).
      Note: Y+1 is North (up), Y-1 is South (down), X+1 is East, X-1 is West. }
    function ComputeCardinalMask4Bit(const AX, AY: Integer): Byte;

    { 8-bit corner-gated Wang / Blob bitmask:
      Bits 0..3: N(1), E(2), S(4), W(8).
      Bits 4..7: NE(16, gated by N&E), SE(32, gated by S&E),
                 SW(64, gated by S&W), NW(128, gated by N&W). }
    function ComputeBlobMask8Bit(const AX, AY: Integer): Byte;

    { Partition all non-zero solid cells (TileId = TileSolidWall) into minimal
      greedy-merged axis-aligned rectangles and rebuild @code(csTransient) 3D boxes. }
    procedure RebuildTilemapMesh;

    function SolidCellCount: Integer;
    function MergedColliderCount: Integer;
    function GetMergedRect(const Index: Integer): TMergedTileRect;
    function TilemapSummaryBadge: String;

    property GridWidth: Integer read FGridWidth;
    property GridHeight: Integer read FGridHeight;
  published
    property Preset: TTilemapPreset read FPreset write SetPreset default tmpDungeonRoomsAndCorridors;
    property Orientation: TTilemapOrientation read FOrientation write SetOrientation default tmoTopDownXZ;
    property TileSize: Single read FTileSize write SetTileSize {$ifdef FPC}default DefaultTileSize{$endif};
    property WallExtrudeHeight: Single read FWallExtrudeHeight write SetWallExtrudeHeight {$ifdef FPC}default DefaultWallExtrudeHeight{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Paper2D-style 2D/2.5D multi-clip sprite sheet flipbook transform with
    UV sub-rect calculation, loop/hold playback, and frame-exact notifies. }
  TCastleFlipbook2D = class(TCastleTransform)
  public
    const
      DefaultAtlasCols = 4;
      DefaultAtlasRows = 4;
      DefaultQuadWidth = 1.2;
      DefaultQuadHeight = 1.4;
  strict private
    FAtlasCols: Integer;
    FAtlasRows: Integer;
    FQuadWidth: Single;
    FQuadHeight: Single;
    FClips: TFlipbookClipDefArray;

    FActiveClipIndex: Integer;
    FIsPlaying: Boolean;
    FFrameTimerSec: Single;
    FCurrentClipFrameOffset: Integer;
    FNotifyFiredThisCycle: Boolean;

    FQuadScene: TCastleScene;
    FTexCoordNode: TTextureCoordinateNode;
    FOnFlipbookNotify: TFlipbookNotifyEvent;

    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure RebuildQuadScene;
    procedure SyncQuadUvRect;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyDefaultHeroClips;
    procedure ClearClips;
    procedure AddClip(const AName: String; const AStartFrame, AFrameCount: Integer;
      const AFps: Single; const ALooping: Boolean = True;
      const ANotifyFrameOffset: Integer = -1);
    function ClipCount: Integer;
    function FindClipIndex(const AName: String): Integer;

    function PlayClip(const AName: String): Boolean;
    procedure StepFlipbook(const Dt: Single);

    function CurrentAtlasFrameIndex: Integer;
    procedure CurrentUvBounds(out U0, V0, U1, V1: Single);
    function ActiveClipName: String;
    function FlipbookSummaryBadge: String;

    property IsPlaying: Boolean read FIsPlaying;
    property CurrentClipFrameOffset: Integer read FCurrentClipFrameOffset;
    property OnFlipbookNotify: TFlipbookNotifyEvent read FOnFlipbookNotify write FOnFlipbookNotify;
  published
    property AtlasCols: Integer read FAtlasCols write FAtlasCols default DefaultAtlasCols;
    property AtlasRows: Integer read FAtlasRows write FAtlasRows default DefaultAtlasRows;
    property QuadWidth: Single read FQuadWidth write FQuadWidth {$ifdef FPC}default DefaultQuadWidth{$endif};
    property QuadHeight: Single read FQuadHeight write FQuadHeight {$ifdef FPC}default DefaultQuadHeight{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize, CastleApplicationProperties;

{ TCastleAutoTilemap --------------------------------------------------------- }

constructor TCastleAutoTilemap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOrientation := tmoTopDownXZ;
  FTileSize := DefaultTileSize;
  FWallExtrudeHeight := DefaultWallExtrudeHeight;
  ResizeGrid(DefaultGridWidth, DefaultGridHeight, True);
  ApplyPreset(tmpDungeonRoomsAndCorridors);
end;

procedure TCastleAutoTilemap.Loaded;
begin
  inherited;
  RebuildTilemapMesh;
end;

class function TCastleAutoTilemap.PresetDisplayName(const APreset: TTilemapPreset): String;
begin
  case APreset of
    tmpCustom:                   Result := 'Custom Tilemap';
    tmpDungeonRoomsAndCorridors: Result := 'Top-Down Dungeon Rooms';
    tmpSideScrollerPlatformer:   Result := '2.5D Side-Scroller Platforms';
  end;
end;

function TCastleAutoTilemap.InBounds(const AX, AY: Integer): Boolean;
begin
  Result := (AX >= 0) and (AX < FGridWidth) and (AY >= 0) and (AY < FGridHeight);
end;

procedure TCastleAutoTilemap.ResizeGrid(const AWidth, AHeight: Integer;
  const ClearAll: Boolean);
var
  I: Integer;
begin
  FGridWidth := Clamped(AWidth, 2, 128);
  FGridHeight := Clamped(AHeight, 2, 128);
  SetLength(FCells, FGridWidth * FGridHeight);
  if ClearAll then
    for I := 0 to High(FCells) do
      FCells[I] := TileEmpty;
end;

procedure TCastleAutoTilemap.ClearCells(const FillTileId: Byte);
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FCells[I] := FillTileId;
  RebuildTilemapMesh;
end;

function TCastleAutoTilemap.GetTile(const AX, AY: Integer): Byte;
begin
  if InBounds(AX, AY) then
    Result := FCells[AY * FGridWidth + AX]
  else
    Result := TileEmpty;
end;

procedure TCastleAutoTilemap.SetTile(const AX, AY: Integer;
  const ATileId: Byte; const RebuildNow: Boolean);
begin
  if not InBounds(AX, AY) then
    Exit;
  FCells[AY * FGridWidth + AX] := ATileId;
  if RebuildNow then
    RebuildTilemapMesh;
end;

procedure TCastleAutoTilemap.PaintRect(const X0, Y0, X1, Y1: Integer;
  const ATileId: Byte; const Filled, RebuildNow: Boolean);
var
  MinX, MaxX, MinY, MaxY, X, Y: Integer;
begin
  MinX := Clamped(Min(X0, X1), 0, FGridWidth - 1);
  MaxX := Clamped(Max(X0, X1), 0, FGridWidth - 1);
  MinY := Clamped(Min(Y0, Y1), 0, FGridHeight - 1);
  MaxY := Clamped(Max(Y0, Y1), 0, FGridHeight - 1);

  for Y := MinY to MaxY do
    for X := MinX to MaxX do
      if Filled or (X = MinX) or (X = MaxX) or (Y = MinY) or (Y = MaxY) then
        FCells[Y * FGridWidth + X] := ATileId;

  if RebuildNow then
    RebuildTilemapMesh;
end;

procedure TCastleAutoTilemap.ApplyPreset(const APreset: TTilemapPreset);
begin
  FPreset := APreset;
  case APreset of
    tmpDungeonRoomsAndCorridors:
      begin
        FOrientation := tmoTopDownXZ;
        ResizeGrid(16, 12, True);
        { Outer dungeon perimeter wall }
        PaintRect(0, 0, 15, 11, TileSolidWall, False, False);
        { Central dividing wall with 2-tile doorway }
        PaintRect(7, 1, 8, 4, TileSolidWall, True, False);
        PaintRect(7, 7, 8, 10, TileSolidWall, True, False);
        { Twin pillars }
        SetTile(3, 5, TileSolidWall, False);
        SetTile(12, 5, TileSolidWall, False);
        RebuildTilemapMesh;
      end;
    tmpSideScrollerPlatformer:
      begin
        FOrientation := tmoSideScrollerXY;
        ResizeGrid(16, 12, True);
        PaintRect(0, 0, 15, 1, TileSolidWall, True, False);
        PaintRect(3, 4, 7, 4, TileSolidWall, True, False);
        PaintRect(9, 7, 13, 7, TileSolidWall, True, False);
        RebuildTilemapMesh;
      end;
    tmpCustom: ;
  end;
end;

function TCastleAutoTilemap.MatchesTerrain(const AX, AY: Integer;
  const ATerrainId: Byte): Boolean;
begin
  Result := InBounds(AX, AY) and (GetTile(AX, AY) = ATerrainId);
end;

function TCastleAutoTilemap.ComputeCardinalMask4Bit(const AX, AY: Integer): Byte;
var
  T: Byte;
begin
  T := GetTile(AX, AY);
  if T = TileEmpty then
    Exit(0);
  Result := 0;
  if MatchesTerrain(AX, AY + 1, T) then Result := Result or 1; // North
  if MatchesTerrain(AX + 1, AY, T) then Result := Result or 2; // East
  if MatchesTerrain(AX, AY - 1, T) then Result := Result or 4; // South
  if MatchesTerrain(AX - 1, AY, T) then Result := Result or 8; // West
end;

function TCastleAutoTilemap.ComputeBlobMask8Bit(const AX, AY: Integer): Byte;
var
  T: Byte;
  HasN, HasE, HasS, HasW: Boolean;
begin
  T := GetTile(AX, AY);
  if T = TileEmpty then
    Exit(0);
  HasN := MatchesTerrain(AX, AY + 1, T);
  HasE := MatchesTerrain(AX + 1, AY, T);
  HasS := MatchesTerrain(AX, AY - 1, T);
  HasW := MatchesTerrain(AX - 1, AY, T);

  Result := 0;
  if HasN then Result := Result or 1;
  if HasE then Result := Result or 2;
  if HasS then Result := Result or 4;
  if HasW then Result := Result or 8;

  { Corner bits are gated by BOTH adjacent cardinal neighbors (47-tile Blob rule) }
  if HasN and HasE and MatchesTerrain(AX + 1, AY + 1, T) then Result := Result or 16;  // NE
  if HasS and HasE and MatchesTerrain(AX + 1, AY - 1, T) then Result := Result or 32;  // SE
  if HasS and HasW and MatchesTerrain(AX - 1, AY - 1, T) then Result := Result or 64;  // SW
  if HasN and HasW and MatchesTerrain(AX - 1, AY + 1, T) then Result := Result or 128; // NW
end;

procedure TCastleAutoTilemap.RebuildTilemapMesh;
var
  Visited: array of Boolean;
  X, Y, WSpan, HSpan, CheckX, CheckY, I, N: Integer;
  CanGrowRow: Boolean;
  TId: Byte;
  WallBox: TCastleBox;
  CenterU, CenterV, SpanU, SpanV: Single;
begin
  if csLoading in ComponentState then
    Exit;

  FMergedRects := nil;
  FreeAndNil(FMeshRoot);

  SetLength(Visited, FGridWidth * FGridHeight);
  for I := 0 to High(Visited) do
    Visited[I] := False;

  { Exact 2D Greedy Meshing over all non-empty tiles }
  for Y := 0 to FGridHeight - 1 do
    for X := 0 to FGridWidth - 1 do
    begin
      if Visited[Y * FGridWidth + X] then
        Continue;
      TId := GetTile(X, Y);
      if TId = TileEmpty then
        Continue;

      { Expand maximally along +X }
      WSpan := 1;
      while (X + WSpan < FGridWidth) and
            (not Visited[Y * FGridWidth + (X + WSpan)]) and
            (GetTile(X + WSpan, Y) = TId) do
        Inc(WSpan);

      { Expand maximally along +Y while entire row strip matches }
      HSpan := 1;
      while Y + HSpan < FGridHeight do
      begin
        CanGrowRow := True;
        for CheckX := X to X + WSpan - 1 do
          if Visited[(Y + HSpan) * FGridWidth + CheckX] or
             (GetTile(CheckX, Y + HSpan) <> TId) then
          begin
            CanGrowRow := False;
            Break;
          end;
        if not CanGrowRow then
          Break;
        Inc(HSpan);
      end;

      for CheckY := Y to Y + HSpan - 1 do
        for CheckX := X to X + WSpan - 1 do
          Visited[CheckY * FGridWidth + CheckX] := True;

      N := Length(FMergedRects);
      SetLength(FMergedRects, N + 1);
      FMergedRects[N].StartX := X;
      FMergedRects[N].StartY := Y;
      FMergedRects[N].SpanW := WSpan;
      FMergedRects[N].SpanH := HSpan;
      FMergedRects[N].TileId := TId;
    end;

  FMeshRoot := TCastleTransform.Create(Self);
  FMeshRoot.SetTransient;
  Add(FMeshRoot);

  for I := 0 to High(FMergedRects) do
  begin
    SpanU := FMergedRects[I].SpanW * FTileSize;
    SpanV := FMergedRects[I].SpanH * FTileSize;
    CenterU := (FMergedRects[I].StartX + FMergedRects[I].SpanW * 0.5 - FGridWidth * 0.5) * FTileSize;
    CenterV := (FMergedRects[I].StartY + FMergedRects[I].SpanH * 0.5 - FGridHeight * 0.5) * FTileSize;

    WallBox := TCastleBox.Create(FMeshRoot);
    WallBox.SetTransient;
    if FOrientation = tmoTopDownXZ then
    begin
      WallBox.Size := Vector3(SpanU, FWallExtrudeHeight, SpanV);
      WallBox.Translation := Vector3(CenterU, FWallExtrudeHeight * 0.5, -CenterV);
    end else
    begin
      WallBox.Size := Vector3(SpanU, SpanV, FWallExtrudeHeight);
      WallBox.Translation := Vector3(CenterU, CenterV, 0.0);
    end;
    WallBox.Color := Vector4(0.46, 0.52, 0.62, 1.0);
    FMeshRoot.Add(WallBox);
  end;
end;

function TCastleAutoTilemap.SolidCellCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FCells) do
    if FCells[I] <> TileEmpty then
      Inc(Result);
end;

function TCastleAutoTilemap.MergedColliderCount: Integer;
begin
  Result := Length(FMergedRects);
end;

function TCastleAutoTilemap.GetMergedRect(const Index: Integer): TMergedTileRect;
begin
  Result := FMergedRects[Clamped(Index, 0, Max(0, High(FMergedRects)))];
end;

function TCastleAutoTilemap.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'Orientation') or
     (PropertyName = 'TileSize') or
     (PropertyName = 'WallExtrudeHeight') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleAutoTilemap.TilemapSummaryBadge: String;
begin
  Result := Format('[Tilemap:%dx%d %d tiles -> %d greedy boxes]', [
    FGridWidth, FGridHeight, SolidCellCount, MergedColliderCount]);
end;

procedure TCastleAutoTilemap.SetPreset(const Value: TTilemapPreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleAutoTilemap.SetOrientation(const Value: TTilemapOrientation);
begin
  if FOrientation <> Value then
  begin
    FOrientation := Value;
    RebuildTilemapMesh;
  end;
end;

procedure TCastleAutoTilemap.SetTileSize(const Value: Single);
begin
  FTileSize := Max(0.1, Value);
  RebuildTilemapMesh;
end;

procedure TCastleAutoTilemap.SetWallExtrudeHeight(const Value: Single);
begin
  FWallExtrudeHeight := Max(0.1, Value);
  RebuildTilemapMesh;
end;

function TCastleAutoTilemap.GetConfigJson: String;
var
  Root: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('orient', Ord(FOrientation));
    Root.Add('w', FGridWidth);
    Root.Add('h', FGridHeight);
    Root.Add('tileSize', FTileSize);
    Root.Add('extrude', FWallExtrudeHeight);
    Arr := TJSONArray.Create;
    for I := 0 to High(FCells) do
      Arr.Add(Integer(FCells[I]));
    Root.Add('cells', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleAutoTilemap.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root: TJSONObject;
  Arr: TJSONArray;
  I, W, H: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TTilemapPreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TTilemapPreset))));
      FOrientation := TTilemapOrientation(Clamped(Root.Get('orient', Ord(FOrientation)),
        0, Ord(High(TTilemapOrientation))));
      W := Clamped(Root.Get('w', FGridWidth), 2, 128);
      H := Clamped(Root.Get('h', FGridHeight), 2, 128);
      FTileSize := Max(0.1, Root.Get('tileSize', FTileSize));
      FWallExtrudeHeight := Max(0.1, Root.Get('extrude', FWallExtrudeHeight));
      ResizeGrid(W, H, True);
      Arr := Root.Find('cells', jtArray) as TJSONArray;
      if Arr <> nil then
        for I := 0 to Min(High(FCells), Arr.Count - 1) do
          FCells[I] := Byte(Clamped(Arr.Integers[I], 0, 255));
      RebuildTilemapMesh;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleFlipbook2D ---------------------------------------------------------- }

constructor TCastleFlipbook2D.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAtlasCols := DefaultAtlasCols;
  FAtlasRows := DefaultAtlasRows;
  FQuadWidth := DefaultQuadWidth;
  FQuadHeight := DefaultQuadHeight;
  FActiveClipIndex := -1;
  ApplyDefaultHeroClips;
  RebuildQuadScene;
end;

procedure TCastleFlipbook2D.Loaded;
begin
  inherited;
  RebuildQuadScene;
end;

procedure TCastleFlipbook2D.ClearClips;
begin
  FClips := nil;
  FActiveClipIndex := -1;
  FIsPlaying := False;
end;

procedure TCastleFlipbook2D.AddClip(const AName: String;
  const AStartFrame, AFrameCount: Integer; const AFps: Single;
  const ALooping: Boolean; const ANotifyFrameOffset: Integer);
var
  N: Integer;
begin
  N := Length(FClips);
  SetLength(FClips, N + 1);
  FClips[N].ClipName := AName;
  FClips[N].StartFrame := Max(0, AStartFrame);
  FClips[N].FrameCount := Max(1, AFrameCount);
  FClips[N].FramesPerSec := Clamped(AFps, 0.5, 120.0);
  FClips[N].Looping := ALooping;
  FClips[N].NotifyFrameOffset := ANotifyFrameOffset;
end;

procedure TCastleFlipbook2D.ApplyDefaultHeroClips;
begin
  ClearClips;
  AddClip('Idle', 0, 4, 6.0, True, -1);
  AddClip('Run', 4, 6, 12.0, True, 2);
  AddClip('AttackSlash', 10, 4, 10.0, False, 2);
  PlayClip('Idle');
end;

function TCastleFlipbook2D.ClipCount: Integer;
begin
  Result := Length(FClips);
end;

function TCastleFlipbook2D.FindClipIndex(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FClips) do
    if SameText(FClips[I].ClipName, AName) then
      Exit(I);
  Result := -1;
end;

function TCastleFlipbook2D.PlayClip(const AName: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindClipIndex(AName);
  if Idx < 0 then
    Exit(False);
  FActiveClipIndex := Idx;
  FCurrentClipFrameOffset := 0;
  FFrameTimerSec := 0.0;
  FNotifyFiredThisCycle := False;
  FIsPlaying := True;
  SyncQuadUvRect;
  Result := True;
end;

function TCastleFlipbook2D.CurrentAtlasFrameIndex: Integer;
begin
  if (FActiveClipIndex >= 0) and (FActiveClipIndex <= High(FClips)) then
    Result := FClips[FActiveClipIndex].StartFrame + FCurrentClipFrameOffset
  else
    Result := 0;
end;

procedure TCastleFlipbook2D.CurrentUvBounds(out U0, V0, U1, V1: Single);
var
  Cols, Rows, FrameIdx, Col, RowFromTop: Integer;
  CellW, CellH: Single;
begin
  Cols := Max(1, FAtlasCols);
  Rows := Max(1, FAtlasRows);
  FrameIdx := Clamped(CurrentAtlasFrameIndex, 0, Cols * Rows - 1);
  Col := FrameIdx mod Cols;
  RowFromTop := FrameIdx div Cols;

  CellW := 1.0 / Cols;
  CellH := 1.0 / Rows;
  U0 := Col * CellW;
  U1 := U0 + CellW;
  V1 := 1.0 - RowFromTop * CellH;
  V0 := V1 - CellH;
end;

procedure TCastleFlipbook2D.RebuildQuadScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  HW, H: Single;
begin
  if csLoading in ComponentState then
    Exit;
  FreeAndNil(FQuadScene);

  HW := Max(0.05, FQuadWidth * 0.5);
  H := Max(0.1, FQuadHeight);

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(0.32, 0.84, 0.96);
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  Coord := TCoordinateNode.Create;
  Coord.SetPoint([
    Vector3(-HW, 0.0, 0.0), Vector3(HW, 0.0, 0.0), Vector3(HW, H, 0.0),
    Vector3(-HW, 0.0, 0.0), Vector3(HW, H, 0.0), Vector3(-HW, H, 0.0)
  ]);
  FTexCoordNode := TTextureCoordinateNode.Create;
  TriSet.Coord := Coord;
  TriSet.TexCoord := FTexCoordNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);

  FQuadScene := TCastleScene.Create(Self);
  FQuadScene.SetTransient;
  FQuadScene.Load(Root, True);
  Add(FQuadScene);
  SyncQuadUvRect;
end;

procedure TCastleFlipbook2D.SyncQuadUvRect;
var
  U0, V0, U1, V1: Single;
begin
  if FTexCoordNode = nil then
    Exit;
  CurrentUvBounds(U0, V0, U1, V1);
  FTexCoordNode.SetPoint([
    Vector2(U0, V0), Vector2(U1, V0), Vector2(U1, V1),
    Vector2(U0, V0), Vector2(U1, V1), Vector2(U0, V1)
  ]);
end;

procedure TCastleFlipbook2D.StepFlipbook(const Dt: Single);
var
  Clip: TFlipbookClipDef;
  FrameDur: Single;
begin
  if (not FIsPlaying) or (Dt <= 0.0) or
     (FActiveClipIndex < 0) or (FActiveClipIndex > High(FClips)) then
    Exit;

  Clip := FClips[FActiveClipIndex];
  FrameDur := 1.0 / Max(0.5, Clip.FramesPerSec);
  FFrameTimerSec := FFrameTimerSec + Dt;

  while FFrameTimerSec >= FrameDur - 1e-6 do
  begin
    FFrameTimerSec := Max(0.0, FFrameTimerSec - FrameDur);
    Inc(FCurrentClipFrameOffset);

    if FCurrentClipFrameOffset >= Clip.FrameCount then
    begin
      if Clip.Looping then
      begin
        FCurrentClipFrameOffset := 0;
        FNotifyFiredThisCycle := False;
      end else
      begin
        FCurrentClipFrameOffset := Clip.FrameCount - 1;
        FIsPlaying := False;
        SyncQuadUvRect;
        Exit;
      end;
    end;

    if (not FNotifyFiredThisCycle) and
       (Clip.NotifyFrameOffset = FCurrentClipFrameOffset) then
    begin
      FNotifyFiredThisCycle := True;
      if Assigned(FOnFlipbookNotify) then
        FOnFlipbookNotify(Self, Clip.ClipName, CurrentAtlasFrameIndex);
    end;
  end;

  SyncQuadUvRect;
end;

procedure TCastleFlipbook2D.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleApplicationMode = appRunning then
    StepFlipbook(SecondsPassed);
end;

function TCastleFlipbook2D.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'AtlasCols') or
     (PropertyName = 'AtlasRows') or
     (PropertyName = 'QuadWidth') or
     (PropertyName = 'QuadHeight') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleFlipbook2D.ActiveClipName: String;
begin
  if (FActiveClipIndex >= 0) and (FActiveClipIndex <= High(FClips)) then
    Result := FClips[FActiveClipIndex].ClipName
  else
    Result := 'None';
end;

function TCastleFlipbook2D.FlipbookSummaryBadge: String;
begin
  Result := Format('[Flipbook2D:%s f%d %dx%d]', [
    ActiveClipName, CurrentAtlasFrameIndex, FAtlasCols, FAtlasRows]);
end;

function TCastleFlipbook2D.GetConfigJson: String;
var
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('cols', FAtlasCols);
    Root.Add('rows', FAtlasRows);
    Arr := TJSONArray.Create;
    for I := 0 to High(FClips) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('name', FClips[I].ClipName);
      Obj.Add('start', FClips[I].StartFrame);
      Obj.Add('count', FClips[I].FrameCount);
      Obj.Add('fps', FClips[I].FramesPerSec);
      Obj.Add('loop', FClips[I].Looping);
      Obj.Add('notify', FClips[I].NotifyFrameOffset);
      Arr.Add(Obj);
    end;
    Root.Add('clips', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleFlipbook2D.SetConfigJson(const Value: String);
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
      FAtlasCols := Max(1, Root.Get('cols', FAtlasCols));
      FAtlasRows := Max(1, Root.Get('rows', FAtlasRows));
      Arr := Root.Find('clips', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        ClearClips;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            Obj := TJSONObject(Arr.Items[I]);
            AddClip(Obj.Get('name', 'Clip'), Obj.Get('start', 0),
              Obj.Get('count', 1), Obj.Get('fps', 8.0),
              Obj.Get('loop', True), Obj.Get('notify', -1));
          end;
        if Length(FClips) > 0 then
          PlayClip(FClips[0].ClipName);
      end;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleAutoTilemap,
    ['2D & Paper2D', 'Auto-Tilemap (4-Bit / 8-Bit Wang & Greedy Colliders)']);
  RegisterSerializableComponent(TCastleFlipbook2D,
    ['2D & Paper2D', 'Paper2D Sprite Sheet Flipbook']);
end.
