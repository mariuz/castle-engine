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

{ Octahedral Billboard Impostor Atlas Mapping & 3-View Barycentric Blend (Phase 374).
  Provides reversible upper-hemisphere hemi-octahedral projection between 3D view
  directions (Y >= 0) and [0..1]^2 atlas UV coordinates, 3-nearest-tile barycentric
  interpolation weights across an NxN impostor atlas, distance-gated mesh-to-impostor
  LOD switchover, and transient camera-facing proxy card visualization. }
unit CastleOctahedralImpostor;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions, CastleColors,
  CastleClassUtils, CastleComponentSerialize;

type
  TOctahedralImpostorPreset = (
    oipPineCanopy8x8,
    oipCliffspire12x12,
    oipCrowdSilhouette6x6,
    oipCustom
  );

  TOctahedralBlendSample = record
    Uv: TVector2;
    TileIndex0: Integer;
    TileIndex1: Integer;
    TileIndex2: Integer;
    Cell0X, Cell0Y: Integer;
    Cell1X, Cell1Y: Integer;
    Cell2X, Cell2Y: Integer;
    Weight0: Single;
    Weight1: Single;
    Weight2: Single;
    DistanceMeters: Single;
    UseImpostorCard: Boolean;
  end;

  { Octahedral impostor proxy transform with hemi-octahedral UV encoding and 3-view barycentric blend. }
  TCastleOctahedralImpostor = class(TCastleTransform)
  private
    FPreset: TOctahedralImpostorPreset;
    FAtlasGridSize: Integer;
    FAtlasResolutionPx: Integer;
    FSwitchDistanceMeters: Single;
    FCardWidthMeters: Single;
    FCardHeightMeters: Single;
    FDitherTransitionBandMeters: Single;
    FShowPreviewCard: Boolean;
    FLastSample: TOctahedralBlendSample;
    FPreviewRoot: TCastleTransform;
    FCardTransform: TCastleBox;
    FHighPolyStandIn: TCastleBox;
    procedure SetPreset(const Value: TOctahedralImpostorPreset);
    procedure SetAtlasGridSize(const Value: Integer);
    procedure SetAtlasResolutionPx(const Value: Integer);
    procedure SetSwitchDistanceMeters(const Value: Single);
    procedure SetCardWidthMeters(const Value: Single);
    procedure SetCardHeightMeters(const Value: Single);
    procedure SetDitherTransitionBandMeters(const Value: Single);
    procedure SetShowPreviewCard(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure RebuildPreviewVisuals;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Reversible upper-hemisphere (Y >= 0) hemi-octahedral projection onto [0..1]^2. }
    class function EncodeHemiOctahedralUv(const Dir: TVector3): TVector2;
    class function DecodeHemiOctahedralDir(const Uv: TVector2): TVector3;

    { Compute 3-nearest-tile barycentric blend weights for a given [0..1]^2 UV coordinate. }
    function SampleAtlasBarycentric(const Uv: TVector2): TOctahedralBlendSample;

    { Evaluate observer world position, LOD switchover, and 3-view blend weights. }
    function EvaluateCameraObserver(const ObserverWorldPos: TVector3): TOctahedralBlendSample;

    function TotalAtlasViews: Integer;
    function TileResolutionPx: Integer;
    function ImpostorSummaryBadge: String;

    property LastSample: TOctahedralBlendSample read FLastSample;
  published
    property Preset: TOctahedralImpostorPreset read FPreset write SetPreset default oipPineCanopy8x8;
    property AtlasGridSize: Integer read FAtlasGridSize write SetAtlasGridSize default 8;
    property AtlasResolutionPx: Integer read FAtlasResolutionPx write SetAtlasResolutionPx default 2048;
    property SwitchDistanceMeters: Single read FSwitchDistanceMeters write SetSwitchDistanceMeters {$ifdef FPC}default 45.0{$endif};
    property CardWidthMeters: Single read FCardWidthMeters write SetCardWidthMeters {$ifdef FPC}default 8.0{$endif};
    property CardHeightMeters: Single read FCardHeightMeters write SetCardHeightMeters {$ifdef FPC}default 14.0{$endif};
    property DitherTransitionBandMeters: Single read FDitherTransitionBandMeters write SetDitherTransitionBandMeters {$ifdef FPC}default 5.0{$endif};
    property ShowPreviewCard: Boolean read FShowPreviewCard write SetShowPreviewCard default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

implementation

uses fpjson, jsonparser;

constructor TCastleOctahedralImpostor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := oipPineCanopy8x8;
  FAtlasGridSize := 8;
  FAtlasResolutionPx := 2048;
  FSwitchDistanceMeters := 45.0;
  FCardWidthMeters := 8.0;
  FCardHeightMeters := 14.0;
  FDitherTransitionBandMeters := 5.0;
  FShowPreviewCard := True;
  FLastSample := SampleAtlasBarycentric(Vector2(0.5, 0.5));
  RebuildPreviewVisuals;
end;

destructor TCastleOctahedralImpostor.Destroy;
begin
  inherited Destroy;
end;

function TCastleOctahedralImpostor.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'AtlasGridSize') or
     (PropertyName = 'AtlasResolutionPx') or
     (PropertyName = 'SwitchDistanceMeters') or
     (PropertyName = 'CardWidthMeters') or
     (PropertyName = 'CardHeightMeters') or
     (PropertyName = 'DitherTransitionBandMeters') or
     (PropertyName = 'ShowPreviewCard') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleOctahedralImpostor.EncodeHemiOctahedralUv(const Dir: TVector3): TVector2;
var
  ClampedY, L1Norm, Ox, Oz: Single;
begin
  ClampedY := Max(0.0, Dir.Y);
  L1Norm := Abs(Dir.X) + ClampedY + Abs(Dir.Z);
  if L1Norm < 1e-6 then
    Exit(Vector2(0.5, 0.5));
  Ox := Dir.X / L1Norm;
  Oz := Dir.Z / L1Norm;
  Result.X := EnsureRange(((Ox - Oz) + 1.0) * 0.5, 0.0, 1.0);
  Result.Y := EnsureRange(((Ox + Oz) + 1.0) * 0.5, 0.0, 1.0);
end;

class function TCastleOctahedralImpostor.DecodeHemiOctahedralDir(const Uv: TVector2): TVector3;
var
  ClampedU, ClampedV, A, B, Ox, Oy, Oz, Len: Single;
begin
  ClampedU := EnsureRange(Uv.X, 0.0, 1.0);
  ClampedV := EnsureRange(Uv.Y, 0.0, 1.0);
  A := ClampedU * 2.0 - 1.0;
  B := ClampedV * 2.0 - 1.0;
  Ox := (A + B) * 0.5;
  Oz := (B - A) * 0.5;
  Oy := Max(0.0, 1.0 - Abs(Ox) - Abs(Oz));
  Len := Sqrt(Ox * Ox + Oy * Oy + Oz * Oz);
  if Len < 1e-6 then
    Result := Vector3(0.0, 1.0, 0.0)
  else
    Result := Vector3(Ox / Len, Oy / Len, Oz / Len);
end;

function TCastleOctahedralImpostor.SampleAtlasBarycentric(const Uv: TVector2): TOctahedralBlendSample;
var
  N, Ix, Iy: Integer;
  Gx, Gy, Fx, Fy: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Uv := Vector2(EnsureRange(Uv.X, 0.0, 1.0), EnsureRange(Uv.Y, 0.0, 1.0));
  N := Max(2, FAtlasGridSize);
  Gx := Result.Uv.X * (N - 1);
  Gy := Result.Uv.Y * (N - 1);
  Ix := EnsureRange(Trunc(Gx), 0, N - 2);
  Iy := EnsureRange(Trunc(Gy), 0, N - 2);
  Fx := EnsureRange(Gx - Ix, 0.0, 1.0);
  Fy := EnsureRange(Gy - Iy, 0.0, 1.0);

  Result.Cell0X := Ix;
  Result.Cell0Y := Iy;
  Result.Cell2X := Ix + 1;
  Result.Cell2Y := Iy + 1;

  if Fx >= Fy then
  begin
    Result.Cell1X := Ix + 1;
    Result.Cell1Y := Iy;
    Result.Weight0 := 1.0 - Fx;
    Result.Weight1 := Fx - Fy;
    Result.Weight2 := Fy;
  end else
  begin
    Result.Cell1X := Ix;
    Result.Cell1Y := Iy + 1;
    Result.Weight0 := 1.0 - Fy;
    Result.Weight1 := Fy - Fx;
    Result.Weight2 := Fx;
  end;

  Result.TileIndex0 := Result.Cell0Y * N + Result.Cell0X;
  Result.TileIndex1 := Result.Cell1Y * N + Result.Cell1X;
  Result.TileIndex2 := Result.Cell2Y * N + Result.Cell2X;
end;

function TCastleOctahedralImpostor.EvaluateCameraObserver(
  const ObserverWorldPos: TVector3): TOctahedralBlendSample;
var
  Delta, DirUpper: TVector3;
  Dist, YawRad: Single;
begin
  Delta := ObserverWorldPos - Translation;
  Dist := Delta.Length;
  if Dist < 1e-4 then
    DirUpper := Vector3(0.0, 0.25, 1.0).Normalize
  else
  begin
    DirUpper := Delta / Dist;
    if DirUpper.Y < 0.0 then
      DirUpper.Y := 0.0;
    if DirUpper.LengthSqr < 1e-6 then
      DirUpper := Vector3(0.0, 1.0, 0.0)
    else
      DirUpper := DirUpper.Normalize;
  end;

  Result := SampleAtlasBarycentric(EncodeHemiOctahedralUv(DirUpper));
  Result.DistanceMeters := Dist;
  Result.UseImpostorCard := Dist >= FSwitchDistanceMeters;
  FLastSample := Result;

  if FCardTransform <> nil then
  begin
    FCardTransform.Exists := FShowPreviewCard and Result.UseImpostorCard;
    if (Abs(Delta.X) > 1e-4) or (Abs(Delta.Z) > 1e-4) then
    begin
      YawRad := ArcTan2(Delta.X, Delta.Z);
      FCardTransform.Rotation := Vector4(0.0, 1.0, 0.0, YawRad);
    end;
  end;
  if FHighPolyStandIn <> nil then
    FHighPolyStandIn.Exists := FShowPreviewCard and (not Result.UseImpostorCard);
end;

function TCastleOctahedralImpostor.TotalAtlasViews: Integer;
begin
  Result := Max(2, FAtlasGridSize) * Max(2, FAtlasGridSize);
end;

function TCastleOctahedralImpostor.TileResolutionPx: Integer;
begin
  Result := Max(16, FAtlasResolutionPx div Max(2, FAtlasGridSize));
end;

function TCastleOctahedralImpostor.ImpostorSummaryBadge: String;
begin
  Result := Format('[Impostor:%dx%d=%dviews LOD>=%.0fm]', [
    FAtlasGridSize, FAtlasGridSize, TotalAtlasViews, FSwitchDistanceMeters]);
end;

procedure TCastleOctahedralImpostor.RebuildPreviewVisuals;
begin
  if FPreviewRoot = nil then
  begin
    FPreviewRoot := TCastleTransform.Create(Self);
    FPreviewRoot.SetTransient;
    FPreviewRoot.Name := 'ImpostorPreviewTransient';
    Add(FPreviewRoot);

    FCardTransform := TCastleBox.Create(FPreviewRoot);
    FCardTransform.SetTransient;
    FCardTransform.Material := pmUnlit;
    FCardTransform.Color := Vector4(0.24, 0.78, 0.44, 0.90);
    FPreviewRoot.Add(FCardTransform);

    FHighPolyStandIn := TCastleBox.Create(FPreviewRoot);
    FHighPolyStandIn.SetTransient;
    FHighPolyStandIn.Material := pmPhysical;
    FHighPolyStandIn.Color := Vector4(0.20, 0.56, 0.28, 1.0);
    FPreviewRoot.Add(FHighPolyStandIn);
  end;

  FPreviewRoot.Exists := FShowPreviewCard;
  FCardTransform.Size := Vector3(Max(0.5, FCardWidthMeters), Max(0.5, FCardHeightMeters), 0.08);
  FCardTransform.Translation := Vector3(0.0, FCardHeightMeters * 0.5, 0.0);
  FCardTransform.Exists := FShowPreviewCard and FLastSample.UseImpostorCard;

  FHighPolyStandIn.Size := Vector3(Max(0.5, FCardWidthMeters * 0.65),
    Max(0.5, FCardHeightMeters), Max(0.5, FCardWidthMeters * 0.65));
  FHighPolyStandIn.Translation := Vector3(0.0, FCardHeightMeters * 0.5, 0.0);
  FHighPolyStandIn.Exists := FShowPreviewCard and (not FLastSample.UseImpostorCard);
end;

procedure TCastleOctahedralImpostor.SetPreset(const Value: TOctahedralImpostorPreset);
begin
  if FPreset = Value then Exit;
  FPreset := Value;
  case Value of
    oipPineCanopy8x8:
      begin
        FAtlasGridSize := 8;
        FAtlasResolutionPx := 2048;
        FSwitchDistanceMeters := 45.0;
        FCardWidthMeters := 8.0;
        FCardHeightMeters := 14.0;
        FDitherTransitionBandMeters := 5.0;
      end;
    oipCliffspire12x12:
      begin
        FAtlasGridSize := 12;
        FAtlasResolutionPx := 4096;
        FSwitchDistanceMeters := 80.0;
        FCardWidthMeters := 22.0;
        FCardHeightMeters := 36.0;
        FDitherTransitionBandMeters := 10.0;
      end;
    oipCrowdSilhouette6x6:
      begin
        FAtlasGridSize := 6;
        FAtlasResolutionPx := 1024;
        FSwitchDistanceMeters := 28.0;
        FCardWidthMeters := 1.2;
        FCardHeightMeters := 1.9;
        FDitherTransitionBandMeters := 3.0;
      end;
    oipCustom: ;
  end;
  FLastSample := SampleAtlasBarycentric(FLastSample.Uv);
  RebuildPreviewVisuals;
end;

procedure TCastleOctahedralImpostor.SetAtlasGridSize(const Value: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(Value, 2, 32);
  if FAtlasGridSize = Clamped then Exit;
  FAtlasGridSize := Clamped;
  FPreset := oipCustom;
  FLastSample := SampleAtlasBarycentric(FLastSample.Uv);
end;

procedure TCastleOctahedralImpostor.SetAtlasResolutionPx(const Value: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(Value, 256, 8192);
  if FAtlasResolutionPx = Clamped then Exit;
  FAtlasResolutionPx := Clamped;
  FPreset := oipCustom;
end;

procedure TCastleOctahedralImpostor.SetSwitchDistanceMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := Max(1.0, Value);
  if SameValue(FSwitchDistanceMeters, Clamped, 1e-4) then Exit;
  FSwitchDistanceMeters := Clamped;
  FPreset := oipCustom;
end;

procedure TCastleOctahedralImpostor.SetCardWidthMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := Max(0.25, Value);
  if SameValue(FCardWidthMeters, Clamped, 1e-4) then Exit;
  FCardWidthMeters := Clamped;
  FPreset := oipCustom;
  RebuildPreviewVisuals;
end;

procedure TCastleOctahedralImpostor.SetCardHeightMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := Max(0.25, Value);
  if SameValue(FCardHeightMeters, Clamped, 1e-4) then Exit;
  FCardHeightMeters := Clamped;
  FPreset := oipCustom;
  RebuildPreviewVisuals;
end;

procedure TCastleOctahedralImpostor.SetDitherTransitionBandMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := Max(0.0, Value);
  if SameValue(FDitherTransitionBandMeters, Clamped, 1e-4) then Exit;
  FDitherTransitionBandMeters := Clamped;
  FPreset := oipCustom;
end;

procedure TCastleOctahedralImpostor.SetShowPreviewCard(const Value: Boolean);
begin
  if FShowPreviewCard = Value then Exit;
  FShowPreviewCard := Value;
  RebuildPreviewVisuals;
end;

function TCastleOctahedralImpostor.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('atlasGridSize', FAtlasGridSize);
    Obj.Add('atlasResolutionPx', FAtlasResolutionPx);
    Obj.Add('switchDistanceMeters', FSwitchDistanceMeters);
    Obj.Add('cardWidthMeters', FCardWidthMeters);
    Obj.Add('cardHeightMeters', FCardHeightMeters);
    Obj.Add('ditherTransitionBandMeters', FDitherTransitionBandMeters);
    Obj.Add('lastUvX', FLastSample.Uv.X);
    Obj.Add('lastUvY', FLastSample.Uv.Y);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleOctahedralImpostor.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  SavedPreset: Integer;
begin
  if Trim(Value) = '' then Exit;
  try
    Data := GetJSON(Value);
  except
    Exit;
  end;
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    FAtlasGridSize := EnsureRange(Obj.Get('atlasGridSize', FAtlasGridSize), 2, 32);
    FAtlasResolutionPx := EnsureRange(Obj.Get('atlasResolutionPx', FAtlasResolutionPx), 256, 8192);
    FSwitchDistanceMeters := Max(1.0, Obj.Get('switchDistanceMeters', FSwitchDistanceMeters));
    FCardWidthMeters := Max(0.25, Obj.Get('cardWidthMeters', FCardWidthMeters));
    FCardHeightMeters := Max(0.25, Obj.Get('cardHeightMeters', FCardHeightMeters));
    FDitherTransitionBandMeters := Max(0.0, Obj.Get('ditherTransitionBandMeters', FDitherTransitionBandMeters));
    SavedPreset := Obj.Get('preset', Ord(FPreset));
    if (SavedPreset >= Ord(Low(TOctahedralImpostorPreset))) and
       (SavedPreset <= Ord(High(TOctahedralImpostorPreset))) then
      FPreset := TOctahedralImpostorPreset(SavedPreset);
    FLastSample := SampleAtlasBarycentric(Vector2(
      Obj.Get('lastUvX', 0.5), Obj.Get('lastUvY', 0.5)));
    RebuildPreviewVisuals;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleOctahedralImpostor, 'Octahedral Billboard Impostor');
end.
