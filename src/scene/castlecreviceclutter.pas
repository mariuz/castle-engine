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

{ Procedural Wall-Crevice & Seam Micro-Clutter Skirt Volume scattering pebbles,
  mortar rubble, and windblown leaves exclusively along concave wall-floor seams
  and L-corners via WorldRay (Phase 370 — UE 6.0+ PCG Crevice Clutter Parity). }
unit CastleCreviceClutter;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Micro-clutter biome skirt presets. }
  TCreviceClutterPreset = (
    ccpCustom,
    ccpStoneMortarRubble,
    ccpAutumnWindblownLeaves,
    ccpMossyDungeonPebbles
  );

  { Single baked concave-seam clutter instance. }
  TCreviceClutterItem = record
    WorldPos: TVector3;
    WallDistanceMeters: Single;
    ConcavityScore: Single;
    RadiusMeters: Single;
    IsInsideCorner: Boolean;
  end;

  { PCG concave wall-floor crevice scanner & single-draw-call micro-clutter skirt baker. }
  TCastleCreviceClutterVolume = class(TCastleTransform)
  private
    FPreset: TCreviceClutterPreset;
    FVolumeExtentXZ: Single;
    FGridResolution: Integer;
    FSeamSkirtWidthMeters: Single;
    FDensityProbability: Single;
    FRandomSeed: Integer;
    FShowClutterMesh: Boolean;
    FItems: array of TCreviceClutterItem;
    FInsideCornerItemCount: Integer;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TCreviceClutterPreset);
    procedure SetVolumeExtentXZ(const AValue: Single);
    procedure SetGridResolution(const AValue: Integer);
    procedure SetSeamSkirtWidthMeters(const AValue: Single);
    procedure SetDensityProbability(const AValue: Single);
    procedure SetRandomSeed(const AValue: Integer);
    procedure SetShowClutterMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParams(const APreset: TCreviceClutterPreset);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ClearBakedClutter;
    function BakeCreviceClutterFromWorld(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;
    function ClutterCount: Integer;
    function GetClutterItem(const AIndex: Integer): TCreviceClutterItem;
    procedure RebuildClutterMesh;
    function CreviceSummaryBadge: String;
    property InsideCornerItemCount: Integer read FInsideCornerItemCount;
  published
    property Preset: TCreviceClutterPreset read FPreset write SetPreset default ccpStoneMortarRubble;
    property VolumeExtentXZ: Single read FVolumeExtentXZ write SetVolumeExtentXZ {$ifdef FPC}default 14.0{$endif};
    property GridResolution: Integer read FGridResolution write SetGridResolution default 20;
    property SeamSkirtWidthMeters: Single read FSeamSkirtWidthMeters write SetSeamSkirtWidthMeters {$ifdef FPC}default 1.60{$endif};
    property DensityProbability: Single read FDensityProbability write SetDensityProbability {$ifdef FPC}default 0.85{$endif};
    property RandomSeed: Integer read FRandomSeed write SetRandomSeed default 20260370;
    property ShowClutterMesh: Boolean read FShowClutterMesh write SetShowClutterMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function CrevicePresetToString(const APreset: TCreviceClutterPreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function CrevicePresetToString(const APreset: TCreviceClutterPreset): String;
begin
  case APreset of
    ccpCustom: Result := 'Custom Crevice Clutter Skirt';
    ccpStoneMortarRubble: Result := 'Ruined Stone & Mortar Rubble Skirt';
    ccpAutumnWindblownLeaves: Result := 'Windblown Autumn Leaf Drift Skirt';
    ccpMossyDungeonPebbles: Result := 'Damp Mossy Dungeon Corner Pebbles';
  end;
end;

function NextSeededFloat01(var AState: Cardinal): Single;
begin
  {$PUSH}{$Q-}{$R-}
  AState := AState * Cardinal(1664525) + Cardinal(1013904223);
  {$POP}
  Result := (AState and $00FFFFFF) / 16777216.0;
end;

{ TCastleCreviceClutterVolume ------------------------------------------------- }

constructor TCastleCreviceClutterVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVolumeExtentXZ := 14.0;
  FGridResolution := 20;
  FRandomSeed := 20260370;
  FShowClutterMesh := True;
  ApplyPresetParams(ccpStoneMortarRubble);
end;

destructor TCastleCreviceClutterVolume.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleCreviceClutterVolume.ApplyPresetParams(const APreset: TCreviceClutterPreset);
begin
  FPreset := APreset;
  case APreset of
    ccpStoneMortarRubble, ccpCustom:
      begin
        FSeamSkirtWidthMeters := 1.60;
        FDensityProbability := 0.85;
      end;
    ccpAutumnWindblownLeaves:
      begin
        FSeamSkirtWidthMeters := 2.10;
        FDensityProbability := 0.92;
      end;
    ccpMossyDungeonPebbles:
      begin
        FSeamSkirtWidthMeters := 1.20;
        FDensityProbability := 0.80;
      end;
  end;
end;

procedure TCastleCreviceClutterVolume.SetPreset(const AValue: TCreviceClutterPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> ccpCustom then
  begin
    ApplyPresetParams(AValue);
    RebuildClutterMesh;
  end;
end;

procedure TCastleCreviceClutterVolume.SetVolumeExtentXZ(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 2.0, 200.0);
  if SameValue(FVolumeExtentXZ, V, 1e-4) then Exit;
  FVolumeExtentXZ := V;
end;

procedure TCastleCreviceClutterVolume.SetGridResolution(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 4, 96);
  if FGridResolution = V then Exit;
  FGridResolution := V;
end;

procedure TCastleCreviceClutterVolume.SetSeamSkirtWidthMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.20, 10.0);
  if SameValue(FSeamSkirtWidthMeters, V, 1e-4) then Exit;
  FSeamSkirtWidthMeters := V;
  FPreset := ccpCustom;
end;

procedure TCastleCreviceClutterVolume.SetDensityProbability(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.05, 1.0);
  if SameValue(FDensityProbability, V, 1e-4) then Exit;
  FDensityProbability := V;
  FPreset := ccpCustom;
end;

procedure TCastleCreviceClutterVolume.SetRandomSeed(const AValue: Integer);
begin
  if FRandomSeed = AValue then Exit;
  FRandomSeed := AValue;
end;

procedure TCastleCreviceClutterVolume.SetShowClutterMesh(const AValue: Boolean);
begin
  if FShowClutterMesh = AValue then Exit;
  FShowClutterMesh := AValue;
  if not FShowClutterMesh then
    ClearTransientScene
  else
    RebuildClutterMesh;
end;

procedure TCastleCreviceClutterVolume.ClearBakedClutter;
begin
  SetLength(FItems, 0);
  FInsideCornerItemCount := 0;
  ClearTransientScene;
end;

function TCastleCreviceClutterVolume.BakeCreviceClutterFromWorld(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;

  function HasValidSolidHit(const RayHit: TRayCollision; const MaxDist: Single;
    out OutDist: Single): Boolean;
  var
    K: Integer;
    HitT: TCastleTransform;
  begin
    Result := False;
    OutDist := MaxDist + 1.0;
    if (RayHit = nil) or (RayHit.Distance > MaxDist) then Exit;
    for K := 0 to RayHit.Count - 1 do
    begin
      HitT := RayHit[K].Item;
      if (HitT = nil) or (HitT = AWorldRoot) or (HitT = Self) then Continue;
      if csTransient in HitT.ComponentStyle then Continue;
      OutDist := RayHit.Distance;
      Exit(True);
    end;
  end;

var
  SeedState: Cardinal;
  GX, GZ, DirIdx, WallHitDirs, N: Integer;
  HalfExt, CellStep, SampleX, SampleZ, FloorDist, FloorY, WallDist,
    MinWallDist, AzRad, WallProx, CornerBoost, Score: Single;
  OriginW, ProbePt, HorizDir: TVector3;
  RayHit: TRayCollision;
begin
  SetLength(FItems, 0);
  FInsideCornerItemCount := 0;
  if AWorldRoot = nil then Exit(0);

  {$PUSH}{$Q-}{$R-}
  SeedState := Cardinal(FRandomSeed) xor $9E3779B9;
  {$POP}
  if SeedState = 0 then SeedState := 1;

  if Parent <> nil then
    OriginW := WorldTranslation
  else
    OriginW := Translation;

  HalfExt := FVolumeExtentXZ * 0.5;
  CellStep := FVolumeExtentXZ / Max(2, FGridResolution);

  for GZ := 0 to FGridResolution - 1 do
    for GX := 0 to FGridResolution - 1 do
    begin
      SampleX := OriginW.X - HalfExt + (GX + 0.20 + 0.60 * NextSeededFloat01(SeedState)) * CellStep;
      SampleZ := OriginW.Z - HalfExt + (GZ + 0.20 + 0.60 * NextSeededFloat01(SeedState)) * CellStep;

      { 1. Downward floor ray }
      RayHit := AWorldRoot.WorldRay(Vector3(SampleX, OriginW.Y + 8.0, SampleZ), Vector3(0, -1, 0));
      try
        if not HasValidSolidHit(RayHit, 16.0, FloorDist) then
          Continue;
        FloorY := (OriginW.Y + 8.0) - FloorDist;
      finally
        FreeAndNil(RayHit);
      end;

      { 2. Cast 8 horizontal compass rays at ankle height (+0.35m) to detect adjacent walls & concave L-corners }
      ProbePt := Vector3(SampleX, FloorY + 0.35, SampleZ);
      MinWallDist := FSeamSkirtWidthMeters + 10.0;
      WallHitDirs := 0;

      for DirIdx := 0 to 7 do
      begin
        AzRad := (DirIdx / 8.0) * 2.0 * Pi;
        HorizDir := Vector3(Cos(AzRad), 0.0, Sin(AzRad));
        RayHit := AWorldRoot.WorldRay(ProbePt, HorizDir);
        try
          if HasValidSolidHit(RayHit, FSeamSkirtWidthMeters, WallDist) then
          begin
            Inc(WallHitDirs);
            if WallDist < MinWallDist then
              MinWallDist := WallDist;
          end;
        finally
          FreeAndNil(RayHit);
        end;
      end;

      { Strictly reject open floor beyond SeamSkirtWidthMeters or points embedded inside walls (< 0.06m) }
      if (WallHitDirs = 0) or (MinWallDist > FSeamSkirtWidthMeters) or (MinWallDist < 0.06) then
        Continue;

      WallProx := 1.0 - (MinWallDist / Max(0.15, FSeamSkirtWidthMeters));
      if WallHitDirs >= 4 then
        CornerBoost := 1.45
      else
        CornerBoost := 1.0;
      Score := EnsureRange(WallProx * FDensityProbability * CornerBoost, 0.0, 1.0);

      if NextSeededFloat01(SeedState) <= Score then
      begin
        N := Length(FItems);
        SetLength(FItems, N + 1);
        FItems[N].WorldPos := Vector3(SampleX, FloorY, SampleZ);
        FItems[N].WallDistanceMeters := MinWallDist;
        FItems[N].ConcavityScore := Score;
        FItems[N].RadiusMeters := 0.08 + 0.16 * WallProx;
        FItems[N].IsInsideCorner := WallHitDirs >= 4;
        if FItems[N].IsInsideCorner then
          Inc(FInsideCornerItemCount);
      end;
    end;

  RebuildClutterMesh;
  Result := Length(FItems);
end;

function TCastleCreviceClutterVolume.ClutterCount: Integer;
begin
  Result := Length(FItems);
end;

function TCastleCreviceClutterVolume.GetClutterItem(const AIndex: Integer): TCreviceClutterItem;
begin
  if (AIndex >= 0) and (AIndex < Length(FItems)) then
    Result := FItems[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleCreviceClutterVolume.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientCreviceClutterMesh';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.RenderOptions.Lighting := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleCreviceClutterVolume.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleCreviceClutterVolume.RebuildClutterMesh;
var
  Verts, Cols: TVector3List;
  I: Integer;
  CenterLoc, Apex, E1, E2, E3, BaseCol, CornerCol, C: TVector3;
  R: Single;
begin
  if (not FShowClutterMesh) or (Length(FItems) = 0) then
  begin
    ClearTransientScene;
    Exit;
  end;

  case FPreset of
    ccpAutumnWindblownLeaves:
      begin
        BaseCol := Vector3(0.84, 0.42, 0.14);
        CornerCol := Vector3(0.95, 0.68, 0.18);
      end;
    ccpMossyDungeonPebbles:
      begin
        BaseCol := Vector3(0.24, 0.56, 0.28);
        CornerCol := Vector3(0.38, 0.78, 0.34);
      end;
    else
      begin
        BaseCol := Vector3(0.56, 0.54, 0.50);
        CornerCol := Vector3(0.76, 0.72, 0.64);
      end;
  end;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for I := 0 to High(FItems) do
    begin
      if Parent <> nil then
        CenterLoc := WorldToLocal(FItems[I].WorldPos)
      else
        CenterLoc := FItems[I].WorldPos - Translation;
      R := FItems[I].RadiusMeters;
      Apex := CenterLoc + Vector3(0.0, R * 0.85, 0.0);
      E1 := CenterLoc + Vector3(R, 0.02, 0.0);
      E2 := CenterLoc + Vector3(-R * 0.5, 0.02, R * 0.86);
      E3 := CenterLoc + Vector3(-R * 0.5, 0.02, -R * 0.86);
      if FItems[I].IsInsideCorner then C := CornerCol else C := BaseCol;

      Verts.Add(Apex); Verts.Add(E1); Verts.Add(E2);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(Apex); Verts.Add(E2); Verts.Add(E3);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(Apex); Verts.Add(E3); Verts.Add(E1);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
    end;

    EnsureTransientScene;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleCreviceClutterVolume.GetConfigJson: String;
var
  RootObj, IObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('extentXZ', FVolumeExtentXZ);
    RootObj.Add('gridRes', FGridResolution);
    RootObj.Add('skirtW', FSeamSkirtWidthMeters);
    RootObj.Add('density', FDensityProbability);
    RootObj.Add('seed', FRandomSeed);
    Arr := TJSONArray.Create;
    for I := 0 to High(FItems) do
    begin
      IObj := TJSONObject.Create;
      IObj.Add('x', FItems[I].WorldPos.X);
      IObj.Add('y', FItems[I].WorldPos.Y);
      IObj.Add('z', FItems[I].WorldPos.Z);
      IObj.Add('wd', FItems[I].WallDistanceMeters);
      IObj.Add('r', FItems[I].RadiusMeters);
      IObj.Add('corner', FItems[I].IsInsideCorner);
      Arr.Add(IObj);
    end;
    RootObj.Add('items', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleCreviceClutterVolume.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, IObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FVolumeExtentXZ := EnsureRange(RootObj.Get('extentXZ', FVolumeExtentXZ), 2.0, 200.0);
      FGridResolution := EnsureRange(RootObj.Get('gridRes', FGridResolution), 4, 96);
      FSeamSkirtWidthMeters := EnsureRange(RootObj.Get('skirtW', FSeamSkirtWidthMeters), 0.20, 10.0);
      FDensityProbability := EnsureRange(RootObj.Get('density', FDensityProbability), 0.05, 1.0);
      FRandomSeed := RootObj.Get('seed', FRandomSeed);
      FInsideCornerItemCount := 0;
      Arr := RootObj.Find('items', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        SetLength(FItems, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            IObj := TJSONObject(Arr.Items[I]);
            FItems[I].WorldPos := Vector3(IObj.Get('x', 0.0), IObj.Get('y', 0.0), IObj.Get('z', 0.0));
            FItems[I].WallDistanceMeters := IObj.Get('wd', 0.5);
            FItems[I].ConcavityScore := 0.8;
            FItems[I].RadiusMeters := Max(0.04, IObj.Get('r', 0.14));
            FItems[I].IsInsideCorner := IObj.Get('corner', False);
            if FItems[I].IsInsideCorner then
              Inc(FInsideCornerItemCount);
          end;
      end;
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TCreviceClutterPreset))) and
         (PresetOrd <= Ord(High(TCreviceClutterPreset))) then
        FPreset := TCreviceClutterPreset(PresetOrd);
      RebuildClutterMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleCreviceClutterVolume.CreviceSummaryBadge: String;
begin
  Result := Format('[Crevice:%d items Skirt=%.2fm Corners=%d]', [
    ClutterCount,
    FSeamSkirtWidthMeters,
    FInsideCornerItemCount]);
end;

initialization
  RegisterSerializableComponent(TCastleCreviceClutterVolume, ['PCG & Scatter', 'Wall-Crevice & Seam Micro-Clutter']);
end.
