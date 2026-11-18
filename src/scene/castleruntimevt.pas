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

{ Runtime Virtual Texture (RVT) LRU physical tile page cache & persistent
  deformable snow/mud/sand trail heightfield with raised displacement berms
  and gradual snowfall/settling recovery
  (Phase 350 — Unreal Engine 6.0+ URuntimeVirtualTexture & Snow Trail Parity). }
unit CastleRuntimeVt;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleImages, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Deformable surface material presets. }
  TRvtSurfaceMaterial = (
    rsmAlpineFreshSnow,
    rsmPeatBogMud,
    rsmDesertDuneSand
  );

  { Physical page slot inside the RVT LRU page cache. }
  TRvtPhysicalPageSlot = record
    Occupied: Boolean;
    VirtualTileX: Integer;
    VirtualTileZ: Integer;
    MipLevel: Integer;
    LastUsedStamp: Int64;
    HitCount: Integer;
  end;

  { Runtime Virtual Texture LRU page cache + deformable snow/mud/sand surface. }
  TCastleRuntimeVirtualTexture = class(TCastleTransform)
  private
    FSurfaceMaterial: TRvtSurfaceMaterial;
    FWorldExtentXZ: Single;
    FVirtualGridTiles: Integer;
    FPhysicalCacheSlots: Integer;
    FGridResolution: Integer;
    FRimPushRatio: Single;
    FSnowfillRecoveryRate: Single;
    FBuildVisualSurfaceMesh: Boolean;

    FPages: array of TRvtPhysicalPageSlot;
    FClockStamp: Int64;
    FCacheHitCount: Integer;
    FCacheMissCount: Integer;
    FEvictionCount: Integer;

    FDisplacement: array of Single;
    FTotalStampsCount: Integer;

    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    FIndexSetNode: TIndexedTriangleSetNode;
    FBuiltMeshRes: Integer;

    procedure SetSurfaceMaterial(const AValue: TRvtSurfaceMaterial);
    procedure SetWorldExtentXZ(const AValue: Single);
    procedure SetVirtualGridTiles(const AValue: Integer);
    procedure SetPhysicalCacheSlots(const AValue: Integer);
    procedure SetGridResolution(const AValue: Integer);
    procedure SetBuildVisualSurfaceMesh(const AValue: Boolean);

    procedure EnsureVisualScene;
    procedure RebuildVisualMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearPageCache;
    procedure ClearDisplacementField;

    { Request virtual tile (AVTileX, AVTileZ, AMip) in the physical page table;
      returns physical slot index [0..PhysicalCacheSlots-1], evicting LRU if full. }
    function RequestVirtualTile(const AVTileX, AVTileZ: Integer;
      const AMipLevel: Integer = 0): Integer;

    { Map world (X, Z) to virtual tile coordinates and request residency. }
    function RequestWorldTile(const AWorldX, AWorldZ: Single;
      const AMipLevel: Integer = 0): Integer;

    function IsVirtualTileResident(const AVTileX, AVTileZ: Integer;
      const AMipLevel: Integer = 0): Boolean;

    { Stamp a boot footprint or wheel depression at local/world (AX, AZ) with
      central sinkage (-ASinkDepthMeters) and raised rim berm (+RimPushRatio). }
    procedure StampFootprintOrTire(const ALocalX, ALocalZ: Single;
      const ARadiusMeters: Single = 0.45;
      const ASinkDepthMeters: Single = 0.24);

    { Gradually heal snow/mud ruts back toward 0.0 at SnowfillRecoveryRate. }
    procedure StepThermalSnowfillRecovery(const ADt: Single);

    function SampleDisplacementGrid(const IX, IZ: Integer): Single;
    function SampleDisplacementLocalXZ(const ALocalX, ALocalZ: Single): Single;
    function MinDepressionMeters: Single;
    function MaxBermRimMeters: Single;
    function OccupiedPageCount: Integer;
    function GetPageSlot(const AIndex: Integer): TRvtPhysicalPageSlot;

    { Export 8-bit heightmap image (128 = 0.0m neutral, <128 rut, >128 berm). }
    function ExportDisplacementGrayscaleImage: TRGBImage;
    function RvtSummaryBadge: String;

    property CacheHitCount: Integer read FCacheHitCount;
    property CacheMissCount: Integer read FCacheMissCount;
    property EvictionCount: Integer read FEvictionCount;
    property TotalStampsCount: Integer read FTotalStampsCount;
  published
    property SurfaceMaterial: TRvtSurfaceMaterial
      read FSurfaceMaterial write SetSurfaceMaterial default rsmAlpineFreshSnow;
    property WorldExtentXZ: Single
      read FWorldExtentXZ write SetWorldExtentXZ {$ifdef FPC}default 24.0{$endif};
    property VirtualGridTiles: Integer
      read FVirtualGridTiles write SetVirtualGridTiles default 16;
    property PhysicalCacheSlots: Integer
      read FPhysicalCacheSlots write SetPhysicalCacheSlots default 16;
    property GridResolution: Integer
      read FGridResolution write SetGridResolution default 48;
    property RimPushRatio: Single
      read FRimPushRatio write FRimPushRatio {$ifdef FPC}default 0.28{$endif};
    property SnowfillRecoveryRate: Single
      read FSnowfillRecoveryRate write FSnowfillRecoveryRate {$ifdef FPC}default 0.18{$endif};
    property BuildVisualSurfaceMesh: Boolean
      read FBuildVisualSurfaceMesh write SetBuildVisualSurfaceMesh default True;
  end;

function RvtMaterialToDisplayName(const AMat: TRvtSurfaceMaterial): String;

implementation

uses
  CastleComponentSerialize;

function RvtMaterialToDisplayName(const AMat: TRvtSurfaceMaterial): String;
begin
  case AMat of
    rsmAlpineFreshSnow: Result := 'Alpine Fresh Powder Snow';
    rsmPeatBogMud:      Result := 'Wet Peat-Bog Mud';
    rsmDesertDuneSand:  Result := 'Loose Desert Dune Sand';
  end;
end;

{ TCastleRuntimeVirtualTexture ----------------------------------------------- }

constructor TCastleRuntimeVirtualTexture.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSurfaceMaterial := rsmAlpineFreshSnow;
  FWorldExtentXZ := 24.0;
  FVirtualGridTiles := 16;
  FPhysicalCacheSlots := 16;
  FGridResolution := 48;
  FRimPushRatio := 0.28;
  FSnowfillRecoveryRate := 0.18;
  FBuildVisualSurfaceMesh := True;
  FBuiltMeshRes := 0;

  SetLength(FPages, FPhysicalCacheSlots);
  SetLength(FDisplacement, FGridResolution * FGridResolution);
  ClearPageCache;
  ClearDisplacementField;
end;

destructor TCastleRuntimeVirtualTexture.Destroy;
begin
  FCoordNode := nil;
  FColorNode := nil;
  FIndexSetNode := nil;
  FreeAndNil(FTransientScene);
  SetLength(FPages, 0);
  SetLength(FDisplacement, 0);
  inherited Destroy;
end;

function TCastleRuntimeVirtualTexture.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'SurfaceMaterial', 'WorldExtentXZ', 'VirtualGridTiles',
       'PhysicalCacheSlots', 'GridResolution', 'RimPushRatio',
       'SnowfillRecoveryRate', 'BuildVisualSurfaceMesh'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleRuntimeVirtualTexture.SetSurfaceMaterial(
  const AValue: TRvtSurfaceMaterial);
begin
  if FSurfaceMaterial = AValue then Exit;
  FSurfaceMaterial := AValue;
  RebuildVisualMesh;
end;

procedure TCastleRuntimeVirtualTexture.SetWorldExtentXZ(const AValue: Single);
begin
  FWorldExtentXZ := EnsureRange(AValue, 4.0, 1024.0);
  RebuildVisualMesh;
end;

procedure TCastleRuntimeVirtualTexture.SetVirtualGridTiles(const AValue: Integer);
begin
  FVirtualGridTiles := EnsureRange(AValue, 2, 256);
end;

procedure TCastleRuntimeVirtualTexture.SetPhysicalCacheSlots(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 2, 128);
  if V = FPhysicalCacheSlots then Exit;
  FPhysicalCacheSlots := V;
  SetLength(FPages, FPhysicalCacheSlots);
  ClearPageCache;
end;

procedure TCastleRuntimeVirtualTexture.SetGridResolution(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 12, 128);
  if V = FGridResolution then Exit;
  FGridResolution := V;
  SetLength(FDisplacement, FGridResolution * FGridResolution);
  ClearDisplacementField;
end;

procedure TCastleRuntimeVirtualTexture.SetBuildVisualSurfaceMesh(
  const AValue: Boolean);
begin
  if FBuildVisualSurfaceMesh = AValue then Exit;
  FBuildVisualSurfaceMesh := AValue;
  if not FBuildVisualSurfaceMesh then
  begin
    FCoordNode := nil;
    FColorNode := nil;
    FIndexSetNode := nil;
    FreeAndNil(FTransientScene);
    FBuiltMeshRes := 0;
  end else
    RebuildVisualMesh;
end;

procedure TCastleRuntimeVirtualTexture.ClearPageCache;
var
  I: Integer;
begin
  if Length(FPages) <> FPhysicalCacheSlots then
    SetLength(FPages, FPhysicalCacheSlots);
  for I := 0 to High(FPages) do
    FPages[I] := Default(TRvtPhysicalPageSlot);
  FClockStamp := 0;
  FCacheHitCount := 0;
  FCacheMissCount := 0;
  FEvictionCount := 0;
end;

procedure TCastleRuntimeVirtualTexture.ClearDisplacementField;
var
  I: Integer;
begin
  if Length(FDisplacement) <> FGridResolution * FGridResolution then
    SetLength(FDisplacement, FGridResolution * FGridResolution);
  for I := 0 to High(FDisplacement) do
    FDisplacement[I] := 0.0;
  FTotalStampsCount := 0;
  RebuildVisualMesh;
end;

function TCastleRuntimeVirtualTexture.RequestVirtualTile(
  const AVTileX, AVTileZ, AMipLevel: Integer): Integer;
var
  TX, TZ, Mip, I, EmptyIdx, LruIdx: Integer;
  OldestStamp: Int64;
begin
  TX := EnsureRange(AVTileX, 0, FVirtualGridTiles - 1);
  TZ := EnsureRange(AVTileZ, 0, FVirtualGridTiles - 1);
  Mip := Max(0, AMipLevel);
  Inc(FClockStamp);

  { 1. Check resident hit }
  for I := 0 to High(FPages) do
    if FPages[I].Occupied and
       (FPages[I].VirtualTileX = TX) and
       (FPages[I].VirtualTileZ = TZ) and
       (FPages[I].MipLevel = Mip) then
    begin
      Inc(FCacheHitCount);
      Inc(FPages[I].HitCount);
      FPages[I].LastUsedStamp := FClockStamp;
      Exit(I);
    end;

  { 2. Cache miss: find free slot or evict strict LRU slot }
  Inc(FCacheMissCount);
  EmptyIdx := -1;
  LruIdx := 0;
  OldestStamp := High(Int64);
  for I := 0 to High(FPages) do
  begin
    if not FPages[I].Occupied then
    begin
      EmptyIdx := I;
      Break;
    end;
    if FPages[I].LastUsedStamp < OldestStamp then
    begin
      OldestStamp := FPages[I].LastUsedStamp;
      LruIdx := I;
    end;
  end;

  if EmptyIdx >= 0 then
    Result := EmptyIdx
  else
  begin
    Result := LruIdx;
    Inc(FEvictionCount);
  end;

  FPages[Result].Occupied := True;
  FPages[Result].VirtualTileX := TX;
  FPages[Result].VirtualTileZ := TZ;
  FPages[Result].MipLevel := Mip;
  FPages[Result].LastUsedStamp := FClockStamp;
  FPages[Result].HitCount := 1;
end;

function TCastleRuntimeVirtualTexture.RequestWorldTile(
  const AWorldX, AWorldZ: Single; const AMipLevel: Integer): Integer;
var
  HalfExt, U, V: Single;
  TX, TZ: Integer;
begin
  HalfExt := Max(1.0, FWorldExtentXZ * 0.5);
  U := EnsureRange((AWorldX + HalfExt) / (2.0 * HalfExt), 0.0, 0.99999);
  V := EnsureRange((AWorldZ + HalfExt) / (2.0 * HalfExt), 0.0, 0.99999);
  TX := Trunc(U * FVirtualGridTiles);
  TZ := Trunc(V * FVirtualGridTiles);
  Result := RequestVirtualTile(TX, TZ, AMipLevel);
end;

function TCastleRuntimeVirtualTexture.IsVirtualTileResident(
  const AVTileX, AVTileZ, AMipLevel: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FPages) do
    if FPages[I].Occupied and
       (FPages[I].VirtualTileX = AVTileX) and
       (FPages[I].VirtualTileZ = AVTileZ) and
       (FPages[I].MipLevel = AMipLevel) then
      Exit(True);
  Result := False;
end;

procedure TCastleRuntimeVirtualTexture.StampFootprintOrTire(
  const ALocalX, ALocalZ, ARadiusMeters, ASinkDepthMeters: Single);
var
  HalfExt, OuterR, CellStep, CellX, CellZ, Dist, Q, CarveDepth, BermHeight, T: Single;
  MinIX, MaxIX, MinIZ, MaxIZ, IX, IZ, Idx: Integer;
begin
  RequestWorldTile(ALocalX, ALocalZ, 0);

  HalfExt := FWorldExtentXZ * 0.5;
  CellStep := FWorldExtentXZ / Single(Max(1, FGridResolution - 1));
  OuterR := Max(0.10, ARadiusMeters) * 1.32;

  MinIX := EnsureRange(Floor((ALocalX - OuterR + HalfExt) / CellStep), 0, FGridResolution - 1);
  MaxIX := EnsureRange(Ceil((ALocalX + OuterR + HalfExt) / CellStep), 0, FGridResolution - 1);
  MinIZ := EnsureRange(Floor((ALocalZ - OuterR + HalfExt) / CellStep), 0, FGridResolution - 1);
  MaxIZ := EnsureRange(Ceil((ALocalZ + OuterR + HalfExt) / CellStep), 0, FGridResolution - 1);

  for IZ := MinIZ to MaxIZ do
  begin
    CellZ := -HalfExt + IZ * CellStep;
    for IX := MinIX to MaxIX do
    begin
      CellX := -HalfExt + IX * CellStep;
      Dist := Hypot(CellX - ALocalX, CellZ - ALocalZ);
      Q := Dist / Max(0.08, ARadiusMeters);
      Idx := IZ * FGridResolution + IX;

      if Q < 0.78 then
      begin
        { Smooth bowl rut depression }
        T := Q / 0.78;
        CarveDepth := -Abs(ASinkDepthMeters) * (1.0 - T * T);
        FDisplacement[Idx] := Min(FDisplacement[Idx], CarveDepth);
      end else if Q <= 1.30 then
      begin
        { Displaced snow/mud rim berm around footprint }
        T := (Q - 0.78) / 0.52;
        BermHeight := Abs(ASinkDepthMeters) * FRimPushRatio * Sin(T * Pi);
        if FDisplacement[Idx] >= -0.005 then
          FDisplacement[Idx] := Max(FDisplacement[Idx], BermHeight);
      end;
    end;
  end;

  Inc(FTotalStampsCount);
  RebuildVisualMesh;
end;

procedure TCastleRuntimeVirtualTexture.StepThermalSnowfillRecovery(
  const ADt: Single);
var
  Decay: Single;
  I: Integer;
begin
  if ADt <= 0.0 then Exit;
  Decay := Exp(-Max(0.0, FSnowfillRecoveryRate) * ADt);
  for I := 0 to High(FDisplacement) do
    FDisplacement[I] := FDisplacement[I] * Decay;
  RebuildVisualMesh;
end;

function TCastleRuntimeVirtualTexture.SampleDisplacementGrid(
  const IX, IZ: Integer): Single;
begin
  if (IX < 0) or (IX >= FGridResolution) or (IZ < 0) or (IZ >= FGridResolution) then
    Exit(0.0);
  Result := FDisplacement[IZ * FGridResolution + IX];
end;

function TCastleRuntimeVirtualTexture.SampleDisplacementLocalXZ(
  const ALocalX, ALocalZ: Single): Single;
var
  HalfExt, CellStep: Single;
  IX, IZ: Integer;
begin
  HalfExt := FWorldExtentXZ * 0.5;
  CellStep := FWorldExtentXZ / Single(Max(1, FGridResolution - 1));
  IX := EnsureRange(Round((ALocalX + HalfExt) / CellStep), 0, FGridResolution - 1);
  IZ := EnsureRange(Round((ALocalZ + HalfExt) / CellStep), 0, FGridResolution - 1);
  Result := SampleDisplacementGrid(IX, IZ);
end;

function TCastleRuntimeVirtualTexture.MinDepressionMeters: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FDisplacement) do
    if FDisplacement[I] < Result then
      Result := FDisplacement[I];
end;

function TCastleRuntimeVirtualTexture.MaxBermRimMeters: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FDisplacement) do
    if FDisplacement[I] > Result then
      Result := FDisplacement[I];
end;

function TCastleRuntimeVirtualTexture.OccupiedPageCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FPages) do
    if FPages[I].Occupied then
      Inc(Result);
end;

function TCastleRuntimeVirtualTexture.GetPageSlot(
  const AIndex: Integer): TRvtPhysicalPageSlot;
begin
  if (AIndex >= 0) and (AIndex <= High(FPages)) then
    Result := FPages[AIndex]
  else
    Result := Default(TRvtPhysicalPageSlot);
end;

function TCastleRuntimeVirtualTexture.ExportDisplacementGrayscaleImage: TRGBImage;
var
  IX, IZ: Integer;
  HVal: Single;
  Lum: Byte;
  Px: PVector3Byte;
begin
  Result := TRGBImage.Create(FGridResolution, FGridResolution);
  for IZ := 0 to FGridResolution - 1 do
    for IX := 0 to FGridResolution - 1 do
    begin
      HVal := SampleDisplacementGrid(IX, IZ);
      Lum := Byte(EnsureRange(Round(128.0 + HVal * 260.0), 0, 255));
      Px := Result.PixelPtr(IX, IZ);
      Px^.X := Lum;
      Px^.Y := Lum;
      Px^.Z := Lum;
    end;
end;

procedure TCastleRuntimeVirtualTexture.EnsureVisualScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
begin
  if not FBuildVisualSurfaceMesh then Exit;
  if FTransientScene <> nil then Exit;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientRvtSnowMesh';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := Vector3(1, 1, 1);
  Mat.Roughness := 0.85;
  App.Material := Mat;
  Shape.Appearance := App;

  FIndexSetNode := TIndexedTriangleSetNode.Create;
  FIndexSetNode.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  FIndexSetNode.Coord := FCoordNode;
  FIndexSetNode.Color := FColorNode;
  Shape.Geometry := FIndexSetNode;
  Root.AddChildren(Shape);

  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleRuntimeVirtualTexture.RebuildVisualMesh;
var
  Verts, Colors: TVector3List;
  Indices: TInt32List;
  HalfExt, StepXZ, HVal, ShadeT: Single;
  IX, IZ, Row0, Row1: Integer;
  BaseCol, RutCol, RimCol, Col: TVector3;
begin
  if not FBuildVisualSurfaceMesh then Exit;
  EnsureVisualScene;
  if FTransientScene = nil then Exit;

  case FSurfaceMaterial of
    rsmAlpineFreshSnow:
      begin
        BaseCol := Vector3(0.92, 0.95, 0.99);
        RutCol  := Vector3(0.46, 0.62, 0.82);
        RimCol  := Vector3(1.00, 1.00, 1.00);
      end;
    rsmPeatBogMud:
      begin
        BaseCol := Vector3(0.38, 0.28, 0.20);
        RutCol  := Vector3(0.16, 0.11, 0.08);
        RimCol  := Vector3(0.52, 0.40, 0.28);
      end;
    rsmDesertDuneSand:
      begin
        BaseCol := Vector3(0.86, 0.74, 0.50);
        RutCol  := Vector3(0.62, 0.48, 0.30);
        RimCol  := Vector3(0.96, 0.86, 0.64);
      end;
  end;

  HalfExt := FWorldExtentXZ * 0.5;
  StepXZ := FWorldExtentXZ / Single(Max(1, FGridResolution - 1));

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    Verts.Capacity := FGridResolution * FGridResolution;
    Colors.Capacity := FGridResolution * FGridResolution;
    for IZ := 0 to FGridResolution - 1 do
      for IX := 0 to FGridResolution - 1 do
      begin
        HVal := SampleDisplacementGrid(IX, IZ);
        Verts.Add(Vector3(-HalfExt + IX * StepXZ, HVal, -HalfExt + IZ * StepXZ));
        if HVal < -0.005 then
        begin
          ShadeT := EnsureRange(-HVal / 0.26, 0.0, 1.0);
          Col := Lerp(ShadeT, BaseCol, RutCol);
        end else if HVal > 0.005 then
        begin
          ShadeT := EnsureRange(HVal / 0.10, 0.0, 1.0);
          Col := Lerp(ShadeT, BaseCol, RimCol);
        end else
          Col := BaseCol;
        Colors.Add(Col);
      end;

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;

    if FBuiltMeshRes <> FGridResolution then
    begin
      Indices := TInt32List.Create;
      try
        Indices.Capacity := (FGridResolution - 1) * (FGridResolution - 1) * 6;
        for IZ := 0 to FGridResolution - 2 do
        begin
          Row0 := IZ * FGridResolution;
          Row1 := (IZ + 1) * FGridResolution;
          for IX := 0 to FGridResolution - 2 do
          begin
            Indices.Add(Row0 + IX);
            Indices.Add(Row1 + IX);
            Indices.Add(Row1 + IX + 1);
            Indices.Add(Row0 + IX);
            Indices.Add(Row1 + IX + 1);
            Indices.Add(Row0 + IX + 1);
          end;
        end;
        FIndexSetNode.SetIndex(Indices);
      finally
        FreeAndNil(Indices);
      end;
      FBuiltMeshRes := FGridResolution;
    end;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

function TCastleRuntimeVirtualTexture.RvtSummaryBadge: String;
begin
  Result := Format('[RVT:%d/%d pages Hit=%d Evict=%d Rut=%.2fm]', [
    OccupiedPageCount, FPhysicalCacheSlots,
    FCacheHitCount, FEvictionCount, MinDepressionMeters
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleRuntimeVirtualTexture,
    ['World & Streaming', 'Runtime Virtual Texture & Snow/Mud Trails (TCastleRuntimeVirtualTexture)']);

end.
