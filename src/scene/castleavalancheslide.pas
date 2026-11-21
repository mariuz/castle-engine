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

{ Mass-conserving Mohr-Coulomb granular rockslide, talus scree cone, and
  alpine slab avalanche chute solver with WorldRay bedrock/deflection-berm
  baking (Phase 408). }
unit CastleAvalancheSlide;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

const
  AvalancheChuteBinCount = 24;

type
  { Preset granular friction / angle-of-repose material classes. }
  TAvalancheSlidePreset = (
    aspGraniteTalusRockslide,
    aspDryDuneSandAvalanche,
    aspWetAlpineSlabAvalanche
  );

  { Per-bin chute bedrock, granular debris thickness & surface elevation. }
  TAvalancheBinSample = record
    BinIndex: Integer;
    LocalX: Single;
    BedrockElevationY: Single;
    DebrisDepthMeters: Single;
    SurfaceElevationY: Single;
  end;

  { Mass-conserving Mohr-Coulomb granular avalanche & talus chute component. }
  TCastleAvalancheSlide = class(TCastleTransform)
  private
    FPreset: TAvalancheSlidePreset;
    FChuteLengthMeters: Single;
    FChuteWidthMeters: Single;
    FAngleOfReposeDeg: Single;
    FFlowMobility01: Single;
    FHeadscarpSlopeDropMeters: Single;
    FShowPreview: Boolean;
    FBedrockY: array[0..AvalancheChuteBinCount - 1] of Single;
    FDebrisDepth: array[0..AvalancheChuteBinCount - 1] of Single;
    FPreviewRoot: TCastleTransform;
    FPreviewProfileScene: TCastleScene;
    procedure SetPreset(const AValue: TAvalancheSlidePreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TAvalancheSlidePreset);
    procedure ResetDefaultMountainChute;

    { Sample underlying cliff, valley floor, and concrete deflection berms
      along the chute via downward WorldRay probes. }
    procedure BakeBedrockAndBermsFromWorld(
      const AWorldRoot: TCastleAbstractRootTransform);

    { Deposit a granular release slab (height AAddedDepthMeters) across bins
      [AStartBin .. AEndBin]. }
    procedure ReleaseHeadscarpSlab(const AStartBin, AEndBin: Integer;
      const AAddedDepthMeters: Single);

    { Advance exact mass-conserving Mohr-Coulomb angle-of-repose relaxation. }
    procedure StepAvalancheRelaxation(const APasses: Integer = 25);

    function TotalDebrisVolumeCubicMeters: Single;
    function DebrisVolumeFromBinRange(const AStartBin, AEndBin: Integer): Single;
    function MaxRunoutDistanceMeters: Single;
    function MaxActiveSlopeDeg: Single;
    function GetBinSample(const ABinIndex: Integer): TAvalancheBinSample;

    procedure RebuildPreview;
    procedure ClearPreview;
    function AvalancheSummaryBadge: String;
  published
    property Preset: TAvalancheSlidePreset
      read FPreset write SetPreset default aspGraniteTalusRockslide;
    property ChuteLengthMeters: Single read FChuteLengthMeters write FChuteLengthMeters;
    property ChuteWidthMeters: Single read FChuteWidthMeters write FChuteWidthMeters;
    property AngleOfReposeDeg: Single read FAngleOfReposeDeg write FAngleOfReposeDeg;
    property FlowMobility01: Single read FFlowMobility01 write FFlowMobility01;
    property HeadscarpSlopeDropMeters: Single
      read FHeadscarpSlopeDropMeters write FHeadscarpSlopeDropMeters;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function AvalancheSlidePresetToString(const APreset: TAvalancheSlidePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function AvalancheSlidePresetToString(const APreset: TAvalancheSlidePreset): String;
begin
  case APreset of
    aspGraniteTalusRockslide:  Result := 'GraniteTalusRockslide';
    aspDryDuneSandAvalanche:   Result := 'DryDuneSandAvalanche';
    aspWetAlpineSlabAvalanche: Result := 'WetAlpineSlabAvalanche';
  end;
end;

constructor TCastleAvalancheSlide.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FChuteLengthMeters := 24.0;
  FChuteWidthMeters := 6.0;
  FHeadscarpSlopeDropMeters := 9.0;
  ApplyPreset(aspGraniteTalusRockslide);
  ResetDefaultMountainChute;
end;

destructor TCastleAvalancheSlide.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleAvalancheSlide.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'ChuteLengthMeters', 'ChuteWidthMeters',
       'AngleOfReposeDeg', 'FlowMobility01',
       'HeadscarpSlopeDropMeters', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleAvalancheSlide.SetPreset(const AValue: TAvalancheSlidePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleAvalancheSlide.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleAvalancheSlide.ApplyPreset(const APreset: TAvalancheSlidePreset);
begin
  FPreset := APreset;
  case APreset of
    aspGraniteTalusRockslide:
      begin
        FAngleOfReposeDeg := 38.0;
        FFlowMobility01 := 0.45;
      end;
    aspDryDuneSandAvalanche:
      begin
        FAngleOfReposeDeg := 31.0;
        FFlowMobility01 := 0.60;
      end;
    aspWetAlpineSlabAvalanche:
      begin
        FAngleOfReposeDeg := 16.0;
        FFlowMobility01 := 0.78;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleAvalancheSlide.ResetDefaultMountainChute;
var
  I: Integer;
  T: Single;
begin
  for I := 0 to AvalancheChuteBinCount - 1 do
  begin
    { Steep 55-deg upper headscarp (bins 0..7) transitioning to flat valley runout (bins 8..23) }
    if I <= 7 then
    begin
      T := 1.0 - (I / 8.0);
      FBedrockY[I] := Max(0.0, FHeadscarpSlopeDropMeters) * T;
    end else
      FBedrockY[I] := 0.0;
    FDebrisDepth[I] := 0.0;
  end;
  ReleaseHeadscarpSlab(0, 4, 2.40);
end;

procedure TCastleAvalancheSlide.BakeBedrockAndBermsFromWorld(
  const AWorldRoot: TCastleAbstractRootTransform);
var
  ActiveRoot: TCastleAbstractRootTransform;
  WT, InvWT: TMatrix4;
  I, K: Integer;
  Dx, LX, BestWorldY, LocalY: Single;
  ProbeWorld: TVector3;
  RH: TRayCollision;
  Item: TCastleTransform;
  HitAny: Boolean;
begin
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;
  if ActiveRoot = nil then Exit;

  if HasWorldTransform then
  begin
    WT := WorldTransform;
    InvWT := WorldInverseTransform;
  end else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  Dx := Max(1.0, FChuteLengthMeters) / AvalancheChuteBinCount;
  for I := 0 to AvalancheChuteBinCount - 1 do
  begin
    LX := (I + 0.5) * Dx;
    ProbeWorld := WT.MultPoint(Vector3(LX, 25.0, 0.0));
    RH := ActiveRoot.WorldRay(ProbeWorld, Vector3(0.0, -1.0, 0.0));
    try
      HitAny := False;
      BestWorldY := -1e9;
      if RH <> nil then
        for K := 0 to RH.Count - 1 do
        begin
          Item := RH[K].Item;
          if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
          if csTransient in Item.ComponentStyle then Continue;
          if RH[K].Point.Y > BestWorldY then
          begin
            BestWorldY := RH[K].Point.Y;
            HitAny := True;
          end;
        end;
      if HitAny then
      begin
        LocalY := InvWT.MultPoint(Vector3(ProbeWorld.X, BestWorldY, ProbeWorld.Z)).Y;
        FBedrockY[I] := LocalY;
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleAvalancheSlide.ReleaseHeadscarpSlab(
  const AStartBin, AEndBin: Integer; const AAddedDepthMeters: Single);
var
  I, LoB, HiB: Integer;
begin
  if AAddedDepthMeters <= 0.0 then Exit;
  LoB := Clamped(Min(AStartBin, AEndBin), 0, AvalancheChuteBinCount - 1);
  HiB := Clamped(Max(AStartBin, AEndBin), 0, AvalancheChuteBinCount - 1);
  for I := LoB to HiB do
    FDebrisDepth[I] := FDebrisDepth[I] + AAddedDepthMeters;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleAvalancheSlide.StepAvalancheRelaxation(const APasses: Integer);
var
  Pass, I: Integer;
  Dx, CritDrop, Mob, HI, HJ, Excess, Flux: Single;
  Delta: array[0..AvalancheChuteBinCount - 1] of Single;
begin
  if APasses <= 0 then Exit;
  Dx := Max(1.0, FChuteLengthMeters) / AvalancheChuteBinCount;
  CritDrop := Dx * Tan(DegToRad(Clamped(FAngleOfReposeDeg, 2.0, 80.0)));
  Mob := Clamped(FFlowMobility01, 0.05, 0.95);

  for Pass := 1 to APasses do
  begin
    for I := 0 to AvalancheChuteBinCount - 1 do
      Delta[I] := 0.0;

    for I := 0 to AvalancheChuteBinCount - 2 do
    begin
      HI := FBedrockY[I] + FDebrisDepth[I];
      HJ := FBedrockY[I + 1] + FDebrisDepth[I + 1];
      if (HI - HJ > CritDrop) and (FDebrisDepth[I] > 1e-6) then
      begin
        Excess := (HI - HJ) - CritDrop;
        Flux := Min(FDebrisDepth[I] * 0.48, 0.45 * Mob * Excess);
        Delta[I] := Delta[I] - Flux;
        Delta[I + 1] := Delta[I + 1] + Flux;
      end else
      if (HJ - HI > CritDrop) and (FDebrisDepth[I + 1] > 1e-6) then
      begin
        Excess := (HJ - HI) - CritDrop;
        Flux := Min(FDebrisDepth[I + 1] * 0.48, 0.45 * Mob * Excess);
        Delta[I + 1] := Delta[I + 1] - Flux;
        Delta[I] := Delta[I] + Flux;
      end;
    end;

    for I := 0 to AvalancheChuteBinCount - 1 do
      FDebrisDepth[I] := Max(0.0, FDebrisDepth[I] + Delta[I]);
  end;

  if FShowPreview then
    RebuildPreview;
end;

function TCastleAvalancheSlide.TotalDebrisVolumeCubicMeters: Single;
begin
  Result := DebrisVolumeFromBinRange(0, AvalancheChuteBinCount - 1);
end;

function TCastleAvalancheSlide.DebrisVolumeFromBinRange(
  const AStartBin, AEndBin: Integer): Single;
var
  I, LoB, HiB: Integer;
  Dx, SumD: Single;
begin
  LoB := Clamped(Min(AStartBin, AEndBin), 0, AvalancheChuteBinCount - 1);
  HiB := Clamped(Max(AStartBin, AEndBin), 0, AvalancheChuteBinCount - 1);
  Dx := Max(1.0, FChuteLengthMeters) / AvalancheChuteBinCount;
  SumD := 0.0;
  for I := LoB to HiB do
    SumD := SumD + FDebrisDepth[I];
  Result := SumD * Dx * Max(0.5, FChuteWidthMeters);
end;

function TCastleAvalancheSlide.MaxRunoutDistanceMeters: Single;
var
  I: Integer;
  Dx: Single;
begin
  Result := 0.0;
  Dx := Max(1.0, FChuteLengthMeters) / AvalancheChuteBinCount;
  for I := AvalancheChuteBinCount - 1 downto 0 do
    if FDebrisDepth[I] > 0.02 then
      Exit((I + 1) * Dx);
end;

function TCastleAvalancheSlide.MaxActiveSlopeDeg: Single;
var
  I: Integer;
  Dx, HI, HJ, DegVal: Single;
begin
  Result := 0.0;
  Dx := Max(1.0, FChuteLengthMeters) / AvalancheChuteBinCount;
  for I := 0 to AvalancheChuteBinCount - 2 do
    if (FDebrisDepth[I] > 0.02) and (FDebrisDepth[I + 1] > 0.02) then
    begin
      HI := FBedrockY[I] + FDebrisDepth[I];
      HJ := FBedrockY[I + 1] + FDebrisDepth[I + 1];
      DegVal := RadToDeg(ArcTan(Abs(HI - HJ) / Dx));
      if DegVal > Result then
        Result := DegVal;
    end;
end;

function TCastleAvalancheSlide.GetBinSample(
  const ABinIndex: Integer): TAvalancheBinSample;
var
  Idx: Integer;
  Dx: Single;
begin
  Idx := Clamped(ABinIndex, 0, AvalancheChuteBinCount - 1);
  Dx := Max(1.0, FChuteLengthMeters) / AvalancheChuteBinCount;
  Result.BinIndex := Idx;
  Result.LocalX := (Idx + 0.5) * Dx;
  Result.BedrockElevationY := FBedrockY[Idx];
  Result.DebrisDepthMeters := FDebrisDepth[Idx];
  Result.SurfaceElevationY := FBedrockY[Idx] + FDebrisDepth[Idx];
end;

procedure TCastleAvalancheSlide.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewProfileScene := nil;
  end;
end;

procedure TCastleAvalancheSlide.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  Pts: array[0..(AvalancheChuteBinCount * 2) - 1] of TVector3;
  I: Integer;
  S: TAvalancheBinSample;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'AvalancheSlidePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewProfileScene := TCastleScene.Create(FPreviewRoot);
  FPreviewProfileScene.SetTransient;
  FPreviewProfileScene.Name := 'AvalancheSlidePreviewProfile';
  FPreviewProfileScene.Pickable := False;
  FPreviewProfileScene.Collides := False;
  FPreviewRoot.Add(FPreviewProfileScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.92, 0.68, 0.35);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  for I := 0 to AvalancheChuteBinCount - 1 do
  begin
    S := GetBinSample(I);
    Pts[I] := Vector3(S.LocalX, S.BedrockElevationY, 0.0);
    Pts[AvalancheChuteBinCount + I] := Vector3(S.LocalX, S.SurfaceElevationY + 0.03, 0.0);
  end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([AvalancheChuteBinCount, AvalancheChuteBinCount]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewProfileScene.Load(RootNode, True);
end;

function TCastleAvalancheSlide.AvalancheSummaryBadge: String;
begin
  Result := FormatDot('[Avalanche:Repose=%.0fdeg Vol=%.0fm3 Runout=%.1fm]', [
    FAngleOfReposeDeg,
    TotalDebrisVolumeCubicMeters,
    MaxRunoutDistanceMeters]);
end;

initialization
  RegisterSerializableComponent(TCastleAvalancheSlide, 'Granular Avalanche & Rockslide');

end.
