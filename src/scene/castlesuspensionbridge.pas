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

{ Procedural rope & chain suspension bridge with Green's-function live point-load
  plank deflection, off-center torsional roll tilt, deterministic broken-plank
  chasm gaps, and transient 3D deck + handrail preview (Phase 389). }
unit CastleSuspensionBridge;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset structural & material profiles for suspension bridges. }
  TSuspensionBridgePreset = (
    sbpJungleVineFootbridge,
    sbpDwarvenIronChainSpan,
    sbpRottedChasmTrapBridge
  );

  { Evaluated state of a single bridge deck plank along [0..1] span. }
  TBridgePlankState = record
    PlankIndex: Integer;
    NormalizedT: Single;
    WorldCenter: TVector3;
    RestSagY: Single;
    LiveLoadDropY: Single;
    RollAngleRad: Single;
    IsBrokenGap: Boolean;
  end;

  { Procedural suspension bridge solving coupled cable sag, Green's-function
    point-load depression, lateral roll torque, and broken-slat hazards. }
  TCastleSuspensionBridge = class(TCastleTransform)
  private
    FPreset: TSuspensionBridgePreset;
    FSpanLengthMeters: Single;
    FEndElevationDeltaY: Single;
    FDeckWidthMeters: Single;
    FHandrailHeightMeters: Single;
    FPlankCount: Integer;
    FBaseSagRatio: Single;
    FCableTensionStiffnessNPerM: Single;
    FTorsionalRollStiffnessNmPerRad: Single;
    FBrokenPlankRatio01: Single;
    FRandomSeed: Integer;
    FShowPreview: Boolean;
    FHasLiveLoad: Boolean;
    FLoadNormalizedT: Single;
    FLoadLateralOffsetMeters: Single;
    FLoadMassKg: Single;
    FPlanks: array of TBridgePlankState;
    FIntactPlankCount: Integer;
    FBrokenGapCount: Integer;
    FMaxTotalDropMeters: Single;
    FPreviewRoot: TCastleTransform;
    FPreviewCablesScene: TCastleScene;
    procedure SetPreset(const AValue: TSuspensionBridgePreset);
    procedure SetPlankCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TSuspensionBridgePreset);

    { Apply a live character/vehicle point load at ANormalizedSpanT in [0..1]
      and lateral offset ALateralOffsetMeters (-DeckWidth/2 .. +DeckWidth/2). }
    procedure ApplyWalkerLoad(const ANormalizedSpanT: Single;
      const ALateralOffsetMeters: Single; const ALoadMassKg: Single);
    procedure ClearWalkerLoad;

    { Deterministically test whether plank APlankIndex is a broken hazard gap. }
    function IsPlankBroken(const APlankIndex: Integer): Boolean;

    { Evaluate total vertical Y offset (relative to start anchor) and roll angle
      at arbitrary normalized span coordinate AT01 in [0..1]. }
    procedure EvaluateDeckAtNormalizedT(const AT01: Single;
      out AVerticalY: Single; out ALiveLoadDropY: Single;
      out ARollAngleRad: Single);

    procedure RebuildBridge;
    procedure ClearPreview;
    function PlankStateCount: Integer;
    function GetPlankState(const AIndex: Integer): TBridgePlankState;
    function BridgeSummaryBadge: String;

    property IntactPlankCount: Integer read FIntactPlankCount;
    property BrokenGapCount: Integer read FBrokenGapCount;
    property MaxTotalDropMeters: Single read FMaxTotalDropMeters;
    property HasLiveLoad: Boolean read FHasLiveLoad;
    property LoadNormalizedT: Single read FLoadNormalizedT;
    property LoadMassKg: Single read FLoadMassKg;
  published
    property Preset: TSuspensionBridgePreset
      read FPreset write SetPreset default sbpJungleVineFootbridge;
    property SpanLengthMeters: Single
      read FSpanLengthMeters write FSpanLengthMeters;
    property EndElevationDeltaY: Single
      read FEndElevationDeltaY write FEndElevationDeltaY;
    property DeckWidthMeters: Single
      read FDeckWidthMeters write FDeckWidthMeters;
    property HandrailHeightMeters: Single
      read FHandrailHeightMeters write FHandrailHeightMeters;
    property PlankCount: Integer
      read FPlankCount write SetPlankCount default 28;
    property BaseSagRatio: Single
      read FBaseSagRatio write FBaseSagRatio;
    property CableTensionStiffnessNPerM: Single
      read FCableTensionStiffnessNPerM write FCableTensionStiffnessNPerM;
    property TorsionalRollStiffnessNmPerRad: Single
      read FTorsionalRollStiffnessNmPerRad write FTorsionalRollStiffnessNmPerRad;
    property BrokenPlankRatio01: Single
      read FBrokenPlankRatio01 write FBrokenPlankRatio01;
    property RandomSeed: Integer
      read FRandomSeed write FRandomSeed default 1337;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function SuspensionBridgePresetToString(const APreset: TSuspensionBridgePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function SuspensionBridgePresetToString(const APreset: TSuspensionBridgePreset): String;
begin
  case APreset of
    sbpJungleVineFootbridge:  Result := 'JungleVineFootbridge';
    sbpDwarvenIronChainSpan:  Result := 'DwarvenIronChainSpan';
    sbpRottedChasmTrapBridge: Result := 'RottedChasmTrapBridge';
  end;
end;

{$PUSH}{$Q-}{$R-}
function PlankHash01(const ASeed, AIndex: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(ASeed) * Cardinal(747796405) +
       Cardinal(AIndex + 1) * Cardinal(2891336453) + Cardinal(1013904223);
  H := ((H shr ((H shr 28) + 4)) xor H) * Cardinal(277803737);
  H := (H shr 22) xor H;
  Result := (H and $00FFFFFF) / 16777216.0;
end;
{$POP}

{ TCastleSuspensionBridge ---------------------------------------------------- }

constructor TCastleSuspensionBridge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPlankCount := 28;
  FRandomSeed := 1337;
  FEndElevationDeltaY := 0.0;
  FShowPreview := True;
  FHasLiveLoad := False;
  FLoadNormalizedT := 0.5;
  FLoadLateralOffsetMeters := 0.0;
  FLoadMassKg := 0.0;
  ApplyPreset(sbpJungleVineFootbridge);
end;

destructor TCastleSuspensionBridge.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleSuspensionBridge.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'SpanLengthMeters', 'EndElevationDeltaY', 'DeckWidthMeters',
       'HandrailHeightMeters', 'PlankCount', 'BaseSagRatio',
       'CableTensionStiffnessNPerM', 'TorsionalRollStiffnessNmPerRad',
       'BrokenPlankRatio01', 'RandomSeed', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSuspensionBridge.SetPreset(const AValue: TSuspensionBridgePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleSuspensionBridge.SetPlankCount(const AValue: Integer);
begin
  FPlankCount := Clamped(AValue, 4, 128);
end;

procedure TCastleSuspensionBridge.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildBridge
  else
    ClearPreview;
end;

procedure TCastleSuspensionBridge.ApplyPreset(const APreset: TSuspensionBridgePreset);
begin
  FPreset := APreset;
  case APreset of
    sbpJungleVineFootbridge:
      begin
        FSpanLengthMeters := 24.0;
        FDeckWidthMeters := 2.0;
        FHandrailHeightMeters := 1.15;
        FPlankCount := 28;
        FBaseSagRatio := 0.085;
        FCableTensionStiffnessNPerM := 4200.0;
        FTorsionalRollStiffnessNmPerRad := 1500.0;
        FBrokenPlankRatio01 := 0.0;
      end;
    sbpDwarvenIronChainSpan:
      begin
        FSpanLengthMeters := 24.0;
        FDeckWidthMeters := 3.2;
        FHandrailHeightMeters := 1.30;
        FPlankCount := 32;
        FBaseSagRatio := 0.032;
        FCableTensionStiffnessNPerM := 32000.0;
        FTorsionalRollStiffnessNmPerRad := 14000.0;
        FBrokenPlankRatio01 := 0.0;
      end;
    sbpRottedChasmTrapBridge:
      begin
        FSpanLengthMeters := 26.0;
        FDeckWidthMeters := 1.8;
        FHandrailHeightMeters := 1.05;
        FPlankCount := 30;
        FBaseSagRatio := 0.125;
        FCableTensionStiffnessNPerM := 2400.0;
        FTorsionalRollStiffnessNmPerRad := 900.0;
        FBrokenPlankRatio01 := 0.28;
      end;
  end;
  RebuildBridge;
end;

procedure TCastleSuspensionBridge.ApplyWalkerLoad(const ANormalizedSpanT: Single;
  const ALateralOffsetMeters: Single; const ALoadMassKg: Single);
begin
  FHasLiveLoad := ALoadMassKg > 0.01;
  FLoadNormalizedT := Clamped(ANormalizedSpanT, 0.0, 1.0);
  FLoadLateralOffsetMeters := Clamped(
    ALateralOffsetMeters, -0.5 * FDeckWidthMeters, 0.5 * FDeckWidthMeters);
  FLoadMassKg := Max(0.0, ALoadMassKg);
  RebuildBridge;
end;

procedure TCastleSuspensionBridge.ClearWalkerLoad;
begin
  FHasLiveLoad := False;
  FLoadMassKg := 0.0;
  FLoadLateralOffsetMeters := 0.0;
  RebuildBridge;
end;

function TCastleSuspensionBridge.IsPlankBroken(const APlankIndex: Integer): Boolean;
begin
  { Never break first or last anchor planks so bridge endpoints stay walkable }
  if (APlankIndex <= 0) or (APlankIndex >= FPlankCount - 1) or
     (FBrokenPlankRatio01 <= 0.0001) then
    Exit(False);
  Result := PlankHash01(FRandomSeed, APlankIndex) < Clamped(FBrokenPlankRatio01, 0.0, 0.90);
end;

procedure TCastleSuspensionBridge.EvaluateDeckAtNormalizedT(const AT01: Single;
  out AVerticalY: Single; out ALiveLoadDropY: Single;
  out ARollAngleRad: Single);
var
  T, TLoad, GreenKernel, ForceN, StiffSafe, RollStiffSafe, TorqueNm: Single;
  RestSag: Single;
begin
  T := Clamped(AT01, 0.0, 1.0);
  RestSag := -Max(0.0, FSpanLengthMeters) * Max(0.0, FBaseSagRatio) * 4.0 * T * (1.0 - T);

  ALiveLoadDropY := 0.0;
  ARollAngleRad := 0.0;
  if FHasLiveLoad and (FLoadMassKg > 0.01) and (T > 1e-5) and (T < 1.0 - 1e-5) then
  begin
    TLoad := Clamped(FLoadNormalizedT, 0.02, 0.98);
    { Continuous taut-cable Green's function G(t, t0), zero at endpoints t=0,1 }
    if T <= TLoad then
      GreenKernel := T * (1.0 - TLoad)
    else
      GreenKernel := TLoad * (1.0 - T);

    ForceN := FLoadMassKg * 9.81;
    StiffSafe := Max(250.0, FCableTensionStiffnessNPerM);
    ALiveLoadDropY := -(ForceN / StiffSafe) * (4.0 * GreenKernel);

    TorqueNm := ForceN * FLoadLateralOffsetMeters;
    RollStiffSafe := Max(100.0, FTorsionalRollStiffnessNmPerRad);
    ARollAngleRad := Clamped(
      (TorqueNm / RollStiffSafe) * (4.0 * GreenKernel), -0.65, 0.65);
  end;

  AVerticalY := (FEndElevationDeltaY * T) + RestSag + ALiveLoadDropY;
end;

procedure TCastleSuspensionBridge.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewCablesScene := nil;
  end;
end;

procedure TCastleSuspensionBridge.RebuildBridge;
var
  WT: TMatrix4;
  N, I: Integer;
  T, VertY, LiveDrop, RollRad, SpanSafe, WidthSafe, RailH, PlankLen: Single;
  LocalCenter: TVector3;
  PlankBox: TCastleBox;
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  CablePts: array of TVector3;
  CableCounts: array of Int32;
begin
  if csDestroying in ComponentState then Exit;
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;

  N := Clamped(FPlankCount, 4, 128);
  SpanSafe := Max(2.0, FSpanLengthMeters);
  WidthSafe := Max(0.6, FDeckWidthMeters);
  RailH := Max(0.3, FHandrailHeightMeters);

  SetLength(FPlanks, N);
  FIntactPlankCount := 0;
  FBrokenGapCount := 0;
  FMaxTotalDropMeters := 0.0;

  for I := 0 to N - 1 do
  begin
    T := I / Max(1, N - 1);
    EvaluateDeckAtNormalizedT(T, VertY, LiveDrop, RollRad);
    LocalCenter := Vector3(0.0, VertY, -T * SpanSafe);
    FPlanks[I].PlankIndex := I;
    FPlanks[I].NormalizedT := T;
    FPlanks[I].WorldCenter := WT.MultPoint(LocalCenter);
    FPlanks[I].RestSagY := VertY - LiveDrop - (FEndElevationDeltaY * T);
    FPlanks[I].LiveLoadDropY := LiveDrop;
    FPlanks[I].RollAngleRad := RollRad;
    FPlanks[I].IsBrokenGap := IsPlankBroken(I);
    if FPlanks[I].IsBrokenGap then
      Inc(FBrokenGapCount)
    else
      Inc(FIntactPlankCount);
    if -(FPlanks[I].RestSagY + LiveDrop) > FMaxTotalDropMeters then
      FMaxTotalDropMeters := -(FPlanks[I].RestSagY + LiveDrop);
  end;

  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'SuspensionBridgePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  PlankLen := (SpanSafe / N) * 0.78;
  for I := 0 to N - 1 do
  begin
    if FPlanks[I].IsBrokenGap then Continue;
    PlankBox := TCastleBox.Create(FPreviewRoot);
    PlankBox.SetTransient;
    PlankBox.Pickable := False;
    PlankBox.Collides := False;
    PlankBox.Size := Vector3(WidthSafe, 0.08, PlankLen);
    T := FPlanks[I].NormalizedT;
    EvaluateDeckAtNormalizedT(T, VertY, LiveDrop, RollRad);
    PlankBox.Translation := Vector3(0.0, VertY, -T * SpanSafe);
    PlankBox.Rotation := Vector4(0.0, 0.0, 1.0, RollRad);
    case FPreset of
      sbpJungleVineFootbridge:  PlankBox.Color := Vector4(0.54, 0.38, 0.20, 1.0);
      sbpDwarvenIronChainSpan:  PlankBox.Color := Vector4(0.36, 0.39, 0.44, 1.0);
      sbpRottedChasmTrapBridge: PlankBox.Color := Vector4(0.42, 0.30, 0.18, 1.0);
    end;
    FPreviewRoot.Add(PlankBox);
  end;

  { Left and Right handrail catenary cables }
  FPreviewCablesScene := TCastleScene.Create(FPreviewRoot);
  FPreviewCablesScene.SetTransient;
  FPreviewCablesScene.Pickable := False;
  FPreviewCablesScene.Collides := False;
  FPreviewRoot.Add(FPreviewCablesScene);

  SetLength(CablePts, N * 2);
  SetLength(CableCounts, 2);
  CableCounts[0] := N;
  CableCounts[1] := N;
  for I := 0 to N - 1 do
  begin
    T := FPlanks[I].NormalizedT;
    EvaluateDeckAtNormalizedT(T, VertY, LiveDrop, RollRad);
    CablePts[I] := Vector3(-0.5 * WidthSafe, VertY + RailH, -T * SpanSafe);
    CablePts[N + I] := Vector3(0.5 * WidthSafe, VertY + RailH, -T * SpanSafe);
  end;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.76, 0.64, 0.36);
  ShapeNode.Material := MatNode;
  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(CablePts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(CableCounts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewCablesScene.Load(RootNode, True);
end;

function TCastleSuspensionBridge.PlankStateCount: Integer;
begin
  Result := Length(FPlanks);
end;

function TCastleSuspensionBridge.GetPlankState(
  const AIndex: Integer): TBridgePlankState;
begin
  if (AIndex >= 0) and (AIndex < Length(FPlanks)) then
    Result := FPlanks[AIndex]
  else
    Result := Default(TBridgePlankState);
end;

function TCastleSuspensionBridge.BridgeSummaryBadge: String;
begin
  Result := FormatDot('[Bridge:%.0fm Planks=%d/%d Sag=%.2fm]', [
    FSpanLengthMeters, FIntactPlankCount, FPlankCount, FMaxTotalDropMeters]);
end;

initialization
  RegisterSerializableComponent(TCastleSuspensionBridge, 'Procedural Rope Suspension Bridge');

end.
