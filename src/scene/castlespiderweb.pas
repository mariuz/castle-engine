{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Procedural 3D orb-weaver spiderweb & dungeon corner cobweb generator with
  radial WorldRay wall/ceiling anchor mooring, power-law capture spiral with
  micro-catenary silk sag, seeded torn-sector decay, and morning dewdrop beads
  (Phase 392). }
unit CastleSpiderweb;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset architectural & botanical cobweb styles. }
  TSpiderwebPreset = (
    swpSymmetricGardenOrbWeb,
    swpTornDungeonCornerCobweb,
    swpDewdropForestCanopySilk
  );

  { Single silk thread segment in world space. }
  TSilkSegment = record
    StartWorld: TVector3;
    EndWorld: TVector3;
    IsRadialSpoke: Boolean;
  end;

  { Morning dewdrop water bead suspended on capture silk. }
  TDewdropBead = record
    WorldPos: TVector3;
    RadiusMeters: Single;
  end;

  { Scene transform that weaves radial spokes, wall-anchored mooring threads,
    sagging capture spirals, and dewdrop beads across 3D corners and arches. }
  TCastleSpiderwebGenerator = class(TCastleTransform)
  private
    FPreset: TSpiderwebPreset;
    FSpokeCount: Integer;
    FSpiralTurnCount: Integer;
    FMaxAnchorSearchRadiusMeters: Single;
    FFallbackWebRadiusMeters: Single;
    FSilkGravitySagMeters: Single;
    FTornSectorRatio01: Single;
    FDewdropDensity01: Single;
    FRandomSeed: Integer;
    FShowPreview: Boolean;
    FHubWorldPos: TVector3;
    FAnchoredSpokeCount: Integer;
    FSegments: array of TSilkSegment;
    FDewdrops: array of TDewdropBead;
    FPreviewRoot: TCastleTransform;
    FPreviewSilkScene: TCastleScene;
    procedure SetPreset(const AValue: TSpiderwebPreset);
    procedure SetSpokeCount(const AValue: Integer);
    procedure SetSpiralTurnCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TSpiderwebPreset);

    { Fire radial WorldRay mooring rays inside the local XY web plane to lock
      anchors onto surrounding walls/ceilings/floors and weave capture silk. }
    function WeaveSpiderwebOnWorld(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;

    function SilkSegmentCount: Integer;
    function GetSilkSegment(const AIndex: Integer): TSilkSegment;
    function DewdropCount: Integer;
    procedure RebuildPreview;
    procedure ClearPreview;
    function SpiderwebSummaryBadge: String;

    property AnchoredSpokeCount: Integer read FAnchoredSpokeCount;
    property HubWorldPos: TVector3 read FHubWorldPos;
  published
    property Preset: TSpiderwebPreset
      read FPreset write SetPreset default swpSymmetricGardenOrbWeb;
    property SpokeCount: Integer
      read FSpokeCount write SetSpokeCount default 12;
    property SpiralTurnCount: Integer
      read FSpiralTurnCount write SetSpiralTurnCount default 8;
    property MaxAnchorSearchRadiusMeters: Single
      read FMaxAnchorSearchRadiusMeters write FMaxAnchorSearchRadiusMeters;
    property FallbackWebRadiusMeters: Single
      read FFallbackWebRadiusMeters write FFallbackWebRadiusMeters;
    property SilkGravitySagMeters: Single
      read FSilkGravitySagMeters write FSilkGravitySagMeters;
    property TornSectorRatio01: Single
      read FTornSectorRatio01 write FTornSectorRatio01;
    property DewdropDensity01: Single
      read FDewdropDensity01 write FDewdropDensity01;
    property RandomSeed: Integer
      read FRandomSeed write FRandomSeed default 4096;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function SpiderwebPresetToString(const APreset: TSpiderwebPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function SpiderwebPresetToString(const APreset: TSpiderwebPreset): String;
begin
  case APreset of
    swpSymmetricGardenOrbWeb:   Result := 'SymmetricGardenOrbWeb';
    swpTornDungeonCornerCobweb: Result := 'TornDungeonCornerCobweb';
    swpDewdropForestCanopySilk: Result := 'DewdropForestCanopySilk';
  end;
end;

{$PUSH}{$Q-}{$R-}
function WebHash01(const ASeed, ASalt: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(ASeed) * Cardinal(747796405) +
       Cardinal(ASalt + 17) * Cardinal(2891336453) + Cardinal(1013904223);
  H := ((H shr ((H shr 28) + 4)) xor H) * Cardinal(277803737);
  H := (H shr 22) xor H;
  Result := (H and $00FFFFFF) / 16777216.0;
end;
{$POP}

{ TCastleSpiderwebGenerator -------------------------------------------------- }

constructor TCastleSpiderwebGenerator.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSpokeCount := 12;
  FSpiralTurnCount := 8;
  FRandomSeed := 4096;
  FShowPreview := True;
  FAnchoredSpokeCount := 0;
  FHubWorldPos := TVector3.Zero;
  ApplyPreset(swpSymmetricGardenOrbWeb);
end;

destructor TCastleSpiderwebGenerator.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleSpiderwebGenerator.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'SpokeCount', 'SpiralTurnCount',
       'MaxAnchorSearchRadiusMeters', 'FallbackWebRadiusMeters',
       'SilkGravitySagMeters', 'TornSectorRatio01',
       'DewdropDensity01', 'RandomSeed', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSpiderwebGenerator.SetPreset(const AValue: TSpiderwebPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleSpiderwebGenerator.SetSpokeCount(const AValue: Integer);
begin
  FSpokeCount := Clamped(AValue, 5, 32);
end;

procedure TCastleSpiderwebGenerator.SetSpiralTurnCount(const AValue: Integer);
begin
  FSpiralTurnCount := Clamped(AValue, 2, 24);
end;

procedure TCastleSpiderwebGenerator.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleSpiderwebGenerator.ApplyPreset(const APreset: TSpiderwebPreset);
begin
  FPreset := APreset;
  case APreset of
    swpSymmetricGardenOrbWeb:
      begin
        FSpokeCount := 12;
        FSpiralTurnCount := 8;
        FMaxAnchorSearchRadiusMeters := 3.5;
        FFallbackWebRadiusMeters := 1.5;
        FSilkGravitySagMeters := 0.035;
        FTornSectorRatio01 := 0.0;
        FDewdropDensity01 := 0.15;
      end;
    swpTornDungeonCornerCobweb:
      begin
        FSpokeCount := 14;
        FSpiralTurnCount := 9;
        FMaxAnchorSearchRadiusMeters := 4.5;
        FFallbackWebRadiusMeters := 1.8;
        FSilkGravitySagMeters := 0.075;
        FTornSectorRatio01 := 0.34;
        FDewdropDensity01 := 0.0;
      end;
    swpDewdropForestCanopySilk:
      begin
        FSpokeCount := 16;
        FSpiralTurnCount := 10;
        FMaxAnchorSearchRadiusMeters := 4.0;
        FFallbackWebRadiusMeters := 1.7;
        FSilkGravitySagMeters := 0.055;
        FTornSectorRatio01 := 0.05;
        FDewdropDensity01 := 0.65;
      end;
  end;
end;

function TCastleSpiderwebGenerator.WeaveSpiderwebOnWorld(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;
var
  WT: TMatrix4;
  Anchors: array of TVector3;
  NSpokes, NTurns, I, NextI, TurnIdx, K, SegCap, DewCap: Integer;
  Angle, MaxR, FallbackR, BestDist, D, U0, U1, SagAmt: Single;
  LocalDir, WorldDir, P0, P1, PMid, AvgAnchor: TVector3;
  RH: TRayCollision;
  HitItem: TCastleTransform;

  procedure PushSeg(const A, B: TVector3; const AIsSpoke: Boolean);
  var
    Idx: Integer;
  begin
    Idx := SegCap;
    Inc(SegCap);
    if Idx >= Length(FSegments) then
      SetLength(FSegments, Max(64, Length(FSegments) * 2));
    FSegments[Idx].StartWorld := A;
    FSegments[Idx].EndWorld := B;
    FSegments[Idx].IsRadialSpoke := AIsSpoke;
  end;

  procedure PushDew(const APos: TVector3; const ARad: Single);
  var
    Idx: Integer;
  begin
    Idx := DewCap;
    Inc(DewCap);
    if Idx >= Length(FDewdrops) then
      SetLength(FDewdrops, Max(32, Length(FDewdrops) * 2));
    FDewdrops[Idx].WorldPos := APos;
    FDewdrops[Idx].RadiusMeters := ARad;
  end;

begin
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  FHubWorldPos := WT.MultPoint(TVector3.Zero);

  NSpokes := Clamped(FSpokeCount, 5, 32);
  NTurns := Clamped(FSpiralTurnCount, 2, 24);
  MaxR := Max(0.3, FMaxAnchorSearchRadiusMeters);
  FallbackR := Max(0.2, FFallbackWebRadiusMeters);

  SetLength(Anchors, NSpokes);
  FAnchoredSpokeCount := 0;
  AvgAnchor := TVector3.Zero;

  for I := 0 to NSpokes - 1 do
  begin
    Angle := (2.0 * Pi * I) / NSpokes;
    LocalDir := Vector3(Cos(Angle), Sin(Angle), 0.0);
    WorldDir := WT.MultDirection(LocalDir);
    if WorldDir.LengthSqr < 1e-8 then
      WorldDir := LocalDir
    else
      WorldDir := WorldDir.Normalize;

    BestDist := MaxR + 1.0;
    if AWorldRoot <> nil then
    begin
      RH := AWorldRoot.WorldRay(FHubWorldPos, WorldDir);
      try
        if RH <> nil then
          for K := 0 to RH.Count - 1 do
          begin
            HitItem := RH[K].Item;
            if (HitItem = nil) or (HitItem = AWorldRoot) or (HitItem = Self) then
              Continue;
            if csTransient in HitItem.ComponentStyle then
              Continue;
            D := PointsDistance(FHubWorldPos, RH[K].Point);
            if (D >= 0.12) and (D <= MaxR) and (D < BestDist) then
              BestDist := D;
          end;
      finally
        FreeAndNil(RH);
      end;
    end;

    if BestDist <= MaxR then
    begin
      Inc(FAnchoredSpokeCount);
      Anchors[I] := FHubWorldPos + WorldDir * BestDist;
    end else
      Anchors[I] := FHubWorldPos + WorldDir * FallbackR;

    AvgAnchor := AvgAnchor + Anchors[I];
  end;

  { Tension relaxation pulls hub 25% toward centroid of wall anchors }
  AvgAnchor := AvgAnchor / NSpokes;
  FHubWorldPos := Lerp(0.25, FHubWorldPos, AvgAnchor);

  SegCap := 0;
  DewCap := 0;
  SetLength(FSegments, NSpokes * (NTurns * 2 + 2));
  SetLength(FDewdrops, 32);

  { 1. Radial anchor spokes }
  for I := 0 to NSpokes - 1 do
    PushSeg(FHubWorldPos, Anchors[I], True);

  { 2. Continuous capture spiral with micro-catenary silk sag & torn sectors }
  for TurnIdx := 1 to NTurns do
    for I := 0 to NSpokes - 1 do
    begin
      if (FTornSectorRatio01 > 0.0001) and
         (WebHash01(FRandomSeed, TurnIdx * 131 + I) <
          Clamped(FTornSectorRatio01, 0.0, 0.92)) then
        Continue;

      NextI := (I + 1) mod NSpokes;
      U0 := Power((TurnIdx - 1 + (I / NSpokes)) / (NTurns + 0.35), 1.12);
      U1 := Power((TurnIdx - 1 + ((I + 1) / NSpokes)) / (NTurns + 0.35), 1.12);
      U0 := Clamped(U0, 0.06, 0.96);
      U1 := Clamped(U1, 0.06, 0.96);

      P0 := Lerp(U0, FHubWorldPos, Anchors[I]);
      P1 := Lerp(U1, FHubWorldPos, Anchors[NextI]);
      SagAmt := Max(0.0, FSilkGravitySagMeters) * (0.35 + 0.65 * U0);
      PMid := (P0 + P1) * 0.5 - Vector3(0.0, SagAmt, 0.0);

      PushSeg(P0, PMid, False);
      PushSeg(PMid, P1, False);

      if (FDewdropDensity01 > 0.001) and (DewCap < 96) and
         (WebHash01(FRandomSeed + 77, TurnIdx * 97 + I) <
          Clamped(FDewdropDensity01, 0.0, 1.0)) then
        PushDew(PMid, 0.018 + 0.014 * WebHash01(FRandomSeed + 19, I * 31 + TurnIdx));
    end;

  SetLength(FSegments, SegCap);
  SetLength(FDewdrops, DewCap);
  Result := SegCap;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleSpiderwebGenerator.SilkSegmentCount: Integer;
begin
  Result := Length(FSegments);
end;

function TCastleSpiderwebGenerator.GetSilkSegment(
  const AIndex: Integer): TSilkSegment;
begin
  if (AIndex >= 0) and (AIndex < Length(FSegments)) then
    Result := FSegments[AIndex]
  else
    Result := Default(TSilkSegment);
end;

function TCastleSpiderwebGenerator.DewdropCount: Integer;
begin
  Result := Length(FDewdrops);
end;

procedure TCastleSpiderwebGenerator.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewSilkScene := nil;
  end;
end;

procedure TCastleSpiderwebGenerator.RebuildPreview;
var
  InvWT, WT: TMatrix4;
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  Counts: array of Int32;
  BeadBox: TCastleBox;
  I: Integer;
  D: Single;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if (not FShowPreview) or (Length(FSegments) = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then
      InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'SpiderwebPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  FPreviewSilkScene := TCastleScene.Create(FPreviewRoot);
  FPreviewSilkScene.SetTransient;
  FPreviewSilkScene.Pickable := False;
  FPreviewSilkScene.Collides := False;
  FPreviewRoot.Add(FPreviewSilkScene);

  SetLength(Pts, Length(FSegments) * 2);
  SetLength(Counts, Length(FSegments));
  for I := 0 to High(FSegments) do
  begin
    Pts[I * 2] := InvWT.MultPoint(FSegments[I].StartWorld);
    Pts[I * 2 + 1] := InvWT.MultPoint(FSegments[I].EndWorld);
    Counts[I] := 2;
  end;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.84, 0.88, 0.94);
  ShapeNode.Material := MatNode;
  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewSilkScene.Load(RootNode, True);

  for I := 0 to High(FDewdrops) do
  begin
    BeadBox := TCastleBox.Create(FPreviewRoot);
    BeadBox.SetTransient;
    BeadBox.Pickable := False;
    BeadBox.Collides := False;
    D := FDewdrops[I].RadiusMeters * 2.0;
    BeadBox.Size := Vector3(D, D, D);
    BeadBox.Translation := InvWT.MultPoint(FDewdrops[I].WorldPos);
    BeadBox.Color := Vector4(0.68, 0.94, 1.0, 0.90);
    FPreviewRoot.Add(BeadBox);
  end;

  Add(FPreviewRoot);
end;

function TCastleSpiderwebGenerator.SpiderwebSummaryBadge: String;
begin
  Result := FormatDot('[Web:%d/%d moored %d threads %d dew]', [
    FAnchoredSpokeCount, FSpokeCount, Length(FSegments), Length(FDewdrops)]);
end;

initialization
  RegisterSerializableComponent(TCastleSpiderwebGenerator, 'Procedural Orb-Weaver Spiderweb');

end.
