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

{ Lumen-style 3D Spherical Harmonics (SH2 L0+L1) Irradiance Probe Grid,
  WorldRay Sky-Occlusion & Colored Albedo Bounce Baker (Phase 357). }
unit CastleSurfaceGi;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Irradiance volume density and lighting presets. }
  TSurfaceGiPreset = (
    sgpCustom,
    sgpCornellColorBleedRoom,
    sgpIndoorOutdoorCourtyard,
    sgpDenseDungeonTorchGrid
  );

  { Single baked 4-coefficient (L0 + L1 XYZ) RGB Spherical Harmonics GI probe. }
  TSurfaceGiProbe = record
    ProbeIndex: Integer;
    GridIX, GridIY, GridIZ: Integer;
    LocalPos: TVector3;
    WorldPos: TVector3;
    SkyVisibility: Single;
    SH0_AmbientRGB: TVector3;
    SH1_X_RGB: TVector3;
    SH1_Y_RGB: TVector3;
    SH1_Z_RGB: TVector3;
    DominantBounceRGB: TVector3;
  end;

  { Summary statistics from the most recent WorldRay SH2 GI bake. }
  TSurfaceGiBakeStats = record
    TotalProbes: Integer;
    RaysCastCount: Integer;
    SkyHitCount: Integer;
    BounceSurfaceHitCount: Integer;
    MeanSkyVisibility: Single;
    MeanAmbientLuminance: Single;
  end;

  { 3D irradiance probe volume matching Unreal Engine 6.0+ Lumen Surface Cache /
    Irradiance Volume workflows with Fibonacci sphere WorldRay sky-occlusion,
    colored surface bounce bleeding, and trilinear L0+L1 SH2 normal evaluation. }
  TCastleSurfaceGiGrid = class(TCastleTransform)
  private
    FPreset: TSurfaceGiPreset;
    FGridX: Integer;
    FGridY: Integer;
    FGridZ: Integer;
    FVolumeSize: TVector3;
    FRaysPerProbe: Integer;
    FMaxRayDistance: Single;
    FSkyColorRGB: TVector3;
    FSkyIntensity: Single;
    FBounceIntensity: Single;
    FShowDebugProbes: Boolean;
    FProbes: array of TSurfaceGiProbe;
    FBakeStats: TSurfaceGiBakeStats;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TSurfaceGiPreset);
    procedure SetGridX(const AValue: Integer);
    procedure SetGridY(const AValue: Integer);
    procedure SetGridZ(const AValue: Integer);
    procedure SetRaysPerProbe(const AValue: Integer);
    procedure SetMaxRayDistance(const AValue: Single);
    procedure SetSkyIntensity(const AValue: Single);
    procedure SetBounceIntensity(const AValue: Single);
    procedure SetShowDebugProbes(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParamsOnly(const APreset: TSurfaceGiPreset);
    function ProbeIndex3D(const IX, IY, IZ: Integer): Integer;
    function LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
    function WorldPointToLocalSafe(const WorldPt: TVector3): TVector3;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    procedure RebuildProbePreviewMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure InitializeUnbakedGrid;
    procedure BakeIrradianceProbes(const AWorldRoot: TCastleAbstractRootTransform);
    function ProbeCount: Integer;
    function GetProbe(const AIndex: Integer): TSurfaceGiProbe;
    function GetProbe3D(const IX, IY, IZ: Integer): TSurfaceGiProbe;
    function SampleIrradianceAtWorld(const AWorldPos, AWorldNormal: TVector3): TVector3;
    function GiSummaryBadge: String;
    property BakeStats: TSurfaceGiBakeStats read FBakeStats;
  published
    property Preset: TSurfaceGiPreset read FPreset write SetPreset default sgpCornellColorBleedRoom;
    property GridX: Integer read FGridX write SetGridX default 4;
    property GridY: Integer read FGridY write SetGridY default 2;
    property GridZ: Integer read FGridZ write SetGridZ default 4;
    property RaysPerProbe: Integer read FRaysPerProbe write SetRaysPerProbe default 32;
    property MaxRayDistance: Single read FMaxRayDistance write SetMaxRayDistance {$ifdef FPC}default 18.0{$endif};
    property SkyIntensity: Single read FSkyIntensity write SetSkyIntensity {$ifdef FPC}default 1.0{$endif};
    property BounceIntensity: Single read FBounceIntensity write SetBounceIntensity {$ifdef FPC}default 1.35{$endif};
    property ShowDebugProbes: Boolean read FShowDebugProbes write SetShowDebugProbes default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function SurfaceGiPresetToString(const APreset: TSurfaceGiPreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function SurfaceGiPresetToString(const APreset: TSurfaceGiPreset): String;
begin
  case APreset of
    sgpCustom: Result := 'Custom SH2 Probe Grid';
    sgpCornellColorBleedRoom: Result := 'Cornell Color-Bleed Courtyard (4x2x4)';
    sgpIndoorOutdoorCourtyard: Result := 'Indoor/Outdoor Sky-Occlusion Grid (5x2x5)';
    sgpDenseDungeonTorchGrid: Result := 'Dense Dungeon Bounce Grid (6x2x6)';
  end;
end;

function LuminanceRGB(const C: TVector3): Single;
begin
  Result := C.X * 0.2126 + C.Y * 0.7152 + C.Z * 0.0722;
end;

function FibonacciSphereDirection(const Index, Count: Integer): TVector3;
const
  GoldenAngle = 2.399963229728653;
var
  Y, R, Theta: Single;
begin
  if Count <= 1 then
    Exit(Vector3(0, 1, 0));
  Y := 1.0 - (2.0 * (Index + 0.5) / Count);
  R := Sqrt(Max(0.0, 1.0 - Y * Y));
  Theta := GoldenAngle * Index;
  Result := Vector3(Cos(Theta) * R, Y, Sin(Theta) * R);
end;

{ TCastleSurfaceGiGrid ------------------------------------------------------- }

constructor TCastleSurfaceGiGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := sgpCornellColorBleedRoom;
  FGridX := 4;
  FGridY := 2;
  FGridZ := 4;
  FVolumeSize := Vector3(7.0, 2.2, 9.0);
  FRaysPerProbe := 32;
  FMaxRayDistance := 18.0;
  FSkyColorRGB := Vector3(0.72, 0.84, 1.0);
  FSkyIntensity := 1.0;
  FBounceIntensity := 1.35;
  FShowDebugProbes := True;
  ApplyPresetParamsOnly(sgpCornellColorBleedRoom);
  InitializeUnbakedGrid;
end;

destructor TCastleSurfaceGiGrid.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleSurfaceGiGrid.ApplyPresetParamsOnly(const APreset: TSurfaceGiPreset);
begin
  case APreset of
    sgpCornellColorBleedRoom, sgpCustom:
      begin
        FGridX := 4;
        FGridY := 2;
        FGridZ := 4;
        FVolumeSize := Vector3(7.0, 2.2, 9.0);
        FSkyColorRGB := Vector3(0.72, 0.84, 1.0);
        FSkyIntensity := 1.0;
        FBounceIntensity := 1.35;
      end;
    sgpIndoorOutdoorCourtyard:
      begin
        FGridX := 5;
        FGridY := 2;
        FGridZ := 5;
        FVolumeSize := Vector3(12.0, 2.6, 12.0);
        FSkyColorRGB := Vector3(0.78, 0.88, 1.0);
        FSkyIntensity := 1.15;
        FBounceIntensity := 1.20;
      end;
    sgpDenseDungeonTorchGrid:
      begin
        FGridX := 6;
        FGridY := 2;
        FGridZ := 6;
        FVolumeSize := Vector3(10.0, 2.4, 10.0);
        FSkyColorRGB := Vector3(0.28, 0.32, 0.45);
        FSkyIntensity := 0.55;
        FBounceIntensity := 1.75;
      end;
  end;
end;

procedure TCastleSurfaceGiGrid.SetPreset(const AValue: TSurfaceGiPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> sgpCustom then
  begin
    ApplyPresetParamsOnly(AValue);
    InitializeUnbakedGrid;
  end;
end;

procedure TCastleSurfaceGiGrid.SetGridX(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 2, 12);
  if FGridX = V then Exit;
  FGridX := V;
  FPreset := sgpCustom;
  InitializeUnbakedGrid;
end;

procedure TCastleSurfaceGiGrid.SetGridY(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 1, 8);
  if FGridY = V then Exit;
  FGridY := V;
  FPreset := sgpCustom;
  InitializeUnbakedGrid;
end;

procedure TCastleSurfaceGiGrid.SetGridZ(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 2, 12);
  if FGridZ = V then Exit;
  FGridZ := V;
  FPreset := sgpCustom;
  InitializeUnbakedGrid;
end;

procedure TCastleSurfaceGiGrid.SetRaysPerProbe(const AValue: Integer);
begin
  FRaysPerProbe := EnsureRange(AValue, 8, 128);
end;

procedure TCastleSurfaceGiGrid.SetMaxRayDistance(const AValue: Single);
begin
  FMaxRayDistance := EnsureRange(AValue, 1.0, 200.0);
end;

procedure TCastleSurfaceGiGrid.SetSkyIntensity(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 10.0);
  if SameValue(FSkyIntensity, V, 1e-4) then Exit;
  FSkyIntensity := V;
end;

procedure TCastleSurfaceGiGrid.SetBounceIntensity(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 10.0);
  if SameValue(FBounceIntensity, V, 1e-4) then Exit;
  FBounceIntensity := V;
end;

procedure TCastleSurfaceGiGrid.SetShowDebugProbes(const AValue: Boolean);
begin
  if FShowDebugProbes = AValue then Exit;
  FShowDebugProbes := AValue;
  if not FShowDebugProbes then
    ClearTransientScene
  else
    RebuildProbePreviewMesh;
end;

function TCastleSurfaceGiGrid.ProbeIndex3D(const IX, IY, IZ: Integer): Integer;
begin
  Result := (IY * FGridZ + IZ) * FGridX + IX;
end;

function TCastleSurfaceGiGrid.LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorld(LocalPt)
  else
    Result := Translation + LocalPt;
end;

function TCastleSurfaceGiGrid.WorldPointToLocalSafe(const WorldPt: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := WorldToLocal(WorldPt)
  else
    Result := WorldPt - Translation;
end;

procedure TCastleSurfaceGiGrid.InitializeUnbakedGrid;
var
  IX, IY, IZ, Idx, Total: Integer;
  UX, UY, UZ: Single;
  LP: TVector3;
begin
  Total := FGridX * FGridY * FGridZ;
  SetLength(FProbes, Total);
  FillChar(FBakeStats, SizeOf(FBakeStats), 0);
  FBakeStats.TotalProbes := Total;

  for IY := 0 to FGridY - 1 do
    for IZ := 0 to FGridZ - 1 do
      for IX := 0 to FGridX - 1 do
      begin
        Idx := ProbeIndex3D(IX, IY, IZ);
        if FGridX > 1 then UX := IX / (FGridX - 1) else UX := 0.5;
        if FGridY > 1 then UY := IY / (FGridY - 1) else UY := 0.5;
        if FGridZ > 1 then UZ := IZ / (FGridZ - 1) else UZ := 0.5;

        LP := Vector3(
          (UX - 0.5) * FVolumeSize.X,
          0.75 + UY * FVolumeSize.Y,
          (UZ - 0.5) * FVolumeSize.Z);

        FProbes[Idx].ProbeIndex := Idx;
        FProbes[Idx].GridIX := IX;
        FProbes[Idx].GridIY := IY;
        FProbes[Idx].GridIZ := IZ;
        FProbes[Idx].LocalPos := LP;
        FProbes[Idx].WorldPos := LocalPointToWorldSafe(LP);
        FProbes[Idx].SkyVisibility := 1.0;
        FProbes[Idx].SH0_AmbientRGB := FSkyColorRGB * (0.55 * FSkyIntensity);
        FProbes[Idx].SH1_X_RGB := TVector3.Zero;
        FProbes[Idx].SH1_Y_RGB := FSkyColorRGB * (0.25 * FSkyIntensity);
        FProbes[Idx].SH1_Z_RGB := TVector3.Zero;
        FProbes[Idx].DominantBounceRGB := TVector3.Zero;
      end;

  FBakeStats.MeanSkyVisibility := 1.0;
  FBakeStats.MeanAmbientLuminance := LuminanceRGB(FSkyColorRGB * (0.55 * FSkyIntensity));
  if FShowDebugProbes then
    RebuildProbePreviewMesh;
end;

procedure TCastleSurfaceGiGrid.BakeIrradianceProbes(const AWorldRoot: TCastleAbstractRootTransform);
var
  RootWorld: TCastleAbstractRootTransform;
  PIdx, RIdx, UpperSkyRays, UpperEscapedRays, BounceHits: Integer;
  ProbeW, RayDir, SampleRadiance, SumSH0, SumSHX, SumSHY, SumSHZ, SumBounce, HitAlbedo: TVector3;
  RayHit: TRayCollision;
  HitValid: Boolean;
  Atten, InvRays, SumVis, SumLuma: Single;

  function ExtractHitAlbedo(const Collision: TRayCollision; out Albedo: TVector3): Boolean;
  var
    K: Integer;
    ItemT: TCastleTransform;
  begin
    Result := False;
    Albedo := Vector3(0.55, 0.55, 0.55);
    if (Collision = nil) or (Collision.Distance > FMaxRayDistance) then Exit;

    for K := 0 to Collision.Count - 1 do
    begin
      ItemT := Collision[K].Item;
      if (ItemT = nil) or (ItemT = Self) or (ItemT = RootWorld) then Continue;
      if csTransient in ItemT.ComponentStyle then Continue;

      if ItemT is TCastleBox then
      begin
        Albedo := TCastleBox(ItemT).Color.XYZ;
        Exit(True);
      end else
      if ItemT is TCastleSphere then
      begin
        Albedo := TCastleSphere(ItemT).Color.XYZ;
        Exit(True);
      end else
      begin
        Result := True;
      end;
    end;
  end;

begin
  if AWorldRoot <> nil then
    RootWorld := AWorldRoot
  else
    RootWorld := World;

  InitializeUnbakedGrid;
  if (RootWorld = nil) or (Length(FProbes) = 0) then Exit;

  FillChar(FBakeStats, SizeOf(FBakeStats), 0);
  FBakeStats.TotalProbes := Length(FProbes);
  InvRays := 1.0 / Max(1, FRaysPerProbe);
  SumVis := 0.0;
  SumLuma := 0.0;

  for PIdx := 0 to High(FProbes) do
  begin
    ProbeW := LocalPointToWorldSafe(FProbes[PIdx].LocalPos);
    FProbes[PIdx].WorldPos := ProbeW;

    UpperSkyRays := 0;
    UpperEscapedRays := 0;
    BounceHits := 0;
    SumSH0 := TVector3.Zero;
    SumSHX := TVector3.Zero;
    SumSHY := TVector3.Zero;
    SumSHZ := TVector3.Zero;
    SumBounce := TVector3.Zero;

    for RIdx := 0 to FRaysPerProbe - 1 do
    begin
      RayDir := FibonacciSphereDirection(RIdx, FRaysPerProbe);
      Inc(FBakeStats.RaysCastCount);
      if RayDir.Y > 0.05 then
        Inc(UpperSkyRays);

      HitValid := False;
      HitAlbedo := TVector3.Zero;
      RayHit := RootWorld.WorldRay(ProbeW, RayDir);
      try
        if (RayHit <> nil) and (RayHit.Distance <= FMaxRayDistance) then
          HitValid := ExtractHitAlbedo(RayHit, HitAlbedo);

        if HitValid then
        begin
          Inc(FBakeStats.BounceSurfaceHitCount);
          Inc(BounceHits);
          Atten := 1.0 / (1.0 + 0.14 * RayHit.Distance);
          SampleRadiance := HitAlbedo * (FBounceIntensity * Atten);
          SumBounce := SumBounce + HitAlbedo;
        end else
        begin
          if RayDir.Y > 0.05 then
          begin
            Inc(UpperEscapedRays);
            Inc(FBakeStats.SkyHitCount);
            SampleRadiance := FSkyColorRGB * (FSkyIntensity * (0.45 + 0.55 * RayDir.Y));
          end else
            SampleRadiance := FSkyColorRGB * (0.12 * FSkyIntensity);
        end;
      finally
        FreeAndNil(RayHit);
      end;

      { Project sample radiance onto L0 and L1 Spherical Harmonics basis }
      SumSH0 := SumSH0 + SampleRadiance;
      SumSHX := SumSHX + SampleRadiance * (RayDir.X * 1.65);
      SumSHY := SumSHY + SampleRadiance * (RayDir.Y * 1.65);
      SumSHZ := SumSHZ + SampleRadiance * (RayDir.Z * 1.65);
    end;

    if UpperSkyRays > 0 then
      FProbes[PIdx].SkyVisibility := UpperEscapedRays / UpperSkyRays
    else
      FProbes[PIdx].SkyVisibility := 0.0;

    FProbes[PIdx].SH0_AmbientRGB := SumSH0 * InvRays;
    FProbes[PIdx].SH1_X_RGB := SumSHX * InvRays;
    FProbes[PIdx].SH1_Y_RGB := SumSHY * InvRays;
    FProbes[PIdx].SH1_Z_RGB := SumSHZ * InvRays;
    if BounceHits > 0 then
      FProbes[PIdx].DominantBounceRGB := SumBounce * (1.0 / BounceHits)
    else
      FProbes[PIdx].DominantBounceRGB := TVector3.Zero;

    SumVis := SumVis + FProbes[PIdx].SkyVisibility;
    SumLuma := SumLuma + LuminanceRGB(FProbes[PIdx].SH0_AmbientRGB);
  end;

  FBakeStats.MeanSkyVisibility := SumVis / Length(FProbes);
  FBakeStats.MeanAmbientLuminance := SumLuma / Length(FProbes);

  if FShowDebugProbes then
    RebuildProbePreviewMesh;
end;

function TCastleSurfaceGiGrid.ProbeCount: Integer;
begin
  Result := Length(FProbes);
end;

function TCastleSurfaceGiGrid.GetProbe(const AIndex: Integer): TSurfaceGiProbe;
begin
  if (AIndex >= 0) and (AIndex < Length(FProbes)) then
    Result := FProbes[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleSurfaceGiGrid.GetProbe3D(const IX, IY, IZ: Integer): TSurfaceGiProbe;
begin
  Result := GetProbe(ProbeIndex3D(
    EnsureRange(IX, 0, FGridX - 1),
    EnsureRange(IY, 0, FGridY - 1),
    EnsureRange(IZ, 0, FGridZ - 1)));
end;

function TCastleSurfaceGiGrid.SampleIrradianceAtWorld(const AWorldPos, AWorldNormal: TVector3): TVector3;
var
  LP, N: TVector3;
  FX, FY, FZ, TX, TY, TZ, WX, WY, WZ, Weight: Single;
  IX0, IY0, IZ0, IX1, IY1, IZ1, DX, DY, DZ: Integer;
  P: TSurfaceGiProbe;
  C0, CX, CY, CZ: TVector3;
begin
  if Length(FProbes) = 0 then
    Exit(TVector3.Zero);

  if AWorldNormal.LengthSqr > 1e-8 then
    N := AWorldNormal.Normalize
  else
    N := Vector3(0, 1, 0);

  LP := WorldPointToLocalSafe(AWorldPos);
  FX := EnsureRange((LP.X / Max(0.01, FVolumeSize.X)) + 0.5, 0.0, 1.0) * (FGridX - 1);
  if FGridY > 1 then
    FY := EnsureRange((LP.Y - 0.75) / Max(0.01, FVolumeSize.Y), 0.0, 1.0) * (FGridY - 1)
  else
    FY := 0.0;
  FZ := EnsureRange((LP.Z / Max(0.01, FVolumeSize.Z)) + 0.5, 0.0, 1.0) * (FGridZ - 1);

  IX0 := EnsureRange(Floor(FX), 0, FGridX - 1);
  IY0 := EnsureRange(Floor(FY), 0, FGridY - 1);
  IZ0 := EnsureRange(Floor(FZ), 0, FGridZ - 1);
  IX1 := Min(FGridX - 1, IX0 + 1);
  IY1 := Min(FGridY - 1, IY0 + 1);
  IZ1 := Min(FGridZ - 1, IZ0 + 1);

  TX := FX - IX0;
  TY := FY - IY0;
  TZ := FZ - IZ0;

  C0 := TVector3.Zero;
  CX := TVector3.Zero;
  CY := TVector3.Zero;
  CZ := TVector3.Zero;

  for DY := 0 to 1 do
    for DZ := 0 to 1 do
      for DX := 0 to 1 do
      begin
        if DX = 0 then WX := 1.0 - TX else WX := TX;
        if DY = 0 then WY := 1.0 - TY else WY := TY;
        if DZ = 0 then WZ := 1.0 - TZ else WZ := TZ;
        Weight := WX * WY * WZ;
        if Weight <= 1e-6 then Continue;

        P := GetProbe3D(
          IfThen(DX = 0, IX0, IX1),
          IfThen(DY = 0, IY0, IY1),
          IfThen(DZ = 0, IZ0, IZ1));
        C0 := C0 + P.SH0_AmbientRGB * Weight;
        CX := CX + P.SH1_X_RGB * Weight;
        CY := CY + P.SH1_Y_RGB * Weight;
        CZ := CZ + P.SH1_Z_RGB * Weight;
      end;

  Result := C0 + CX * N.X + CY * N.Y + CZ * N.Z;
  Result.X := Max(0.0, Result.X);
  Result.Y := Max(0.0, Result.Y);
  Result.Z := Max(0.0, Result.Z);
end;

procedure TCastleSurfaceGiGrid.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientSurfaceGiProbes';
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

procedure TCastleSurfaceGiGrid.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleSurfaceGiGrid.RebuildProbePreviewMesh;
const
  Rad = 0.22;
var
  Verts, Cols: TVector3List;
  I: Integer;
  C, TopP, BotP, PX, NX, PZ, NZ, Col: TVector3;

  procedure AddTri(const A, B, D, TCol: TVector3);
  begin
    Verts.Add(A); Verts.Add(B); Verts.Add(D);
    Cols.Add(TCol); Cols.Add(TCol); Cols.Add(TCol);
  end;

begin
  if not FShowDebugProbes then Exit;
  EnsureTransientScene;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for I := 0 to High(FProbes) do
    begin
      C := FProbes[I].LocalPos;
      TopP := C + Vector3(0, Rad, 0);
      BotP := C + Vector3(0, -Rad, 0);
      PX := C + Vector3(Rad, 0, 0);
      NX := C + Vector3(-Rad, 0, 0);
      PZ := C + Vector3(0, 0, Rad);
      NZ := C + Vector3(0, 0, -Rad);
      Col := Vector3(
        EnsureRange(FProbes[I].SH0_AmbientRGB.X * 1.4, 0.08, 1.0),
        EnsureRange(FProbes[I].SH0_AmbientRGB.Y * 1.4, 0.08, 1.0),
        EnsureRange(FProbes[I].SH0_AmbientRGB.Z * 1.4, 0.08, 1.0));

      AddTri(TopP, PZ, PX, Col);
      AddTri(TopP, PX, NZ, Col);
      AddTri(TopP, NZ, NX, Col);
      AddTri(TopP, NX, PZ, Col);
      AddTri(BotP, PX, PZ, Col * 0.75);
      AddTri(BotP, NZ, PX, Col * 0.75);
      AddTri(BotP, NX, NZ, Col * 0.75);
      AddTri(BotP, PZ, NX, Col * 0.75);
    end;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleSurfaceGiGrid.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('gx', FGridX);
    Obj.Add('gy', FGridY);
    Obj.Add('gz', FGridZ);
    Obj.Add('vx', FVolumeSize.X);
    Obj.Add('vy', FVolumeSize.Y);
    Obj.Add('vz', FVolumeSize.Z);
    Obj.Add('skyInt', FSkyIntensity);
    Obj.Add('bounceInt', FBounceIntensity);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleSurfaceGiGrid.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      PresetOrd := Obj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TSurfaceGiPreset))) and
         (PresetOrd <= Ord(High(TSurfaceGiPreset))) then
        FPreset := TSurfaceGiPreset(PresetOrd);
      FGridX := EnsureRange(Obj.Get('gx', FGridX), 2, 12);
      FGridY := EnsureRange(Obj.Get('gy', FGridY), 1, 8);
      FGridZ := EnsureRange(Obj.Get('gz', FGridZ), 2, 12);
      FVolumeSize.X := EnsureRange(Obj.Get('vx', FVolumeSize.X), 1.0, 200.0);
      FVolumeSize.Y := EnsureRange(Obj.Get('vy', FVolumeSize.Y), 0.5, 100.0);
      FVolumeSize.Z := EnsureRange(Obj.Get('vz', FVolumeSize.Z), 1.0, 200.0);
      FSkyIntensity := EnsureRange(Obj.Get('skyInt', FSkyIntensity), 0.0, 10.0);
      FBounceIntensity := EnsureRange(Obj.Get('bounceInt', FBounceIntensity), 0.0, 10.0);
      InitializeUnbakedGrid;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleSurfaceGiGrid.GiSummaryBadge: String;
begin
  Result := Format('[GI-SH2:%d probes Sky=%.0f%% Luma=%.2f]', [
    FBakeStats.TotalProbes,
    FBakeStats.MeanSkyVisibility * 100.0,
    FBakeStats.MeanAmbientLuminance]);
end;

initialization
  RegisterSerializableComponent(TCastleSurfaceGiGrid, ['Lighting & GI', 'Surface Cache SH2 GI Probe Grid']);
end.
