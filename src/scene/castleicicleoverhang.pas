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

{ Procedural roof-eave icicle & cavern stalactite/stalagmite generator scanning
  ceiling undersides via upward WorldRay probes, verifying downward open-air
  clearance, spawning paired meltwater floor stalagmites, and evaluating
  Stefan-law ribbed taper profiles (Phase 397). }
unit CastleIcicleOverhang;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors;

type
  { Preset winter eave vs. limestone cave vs. glacial cavern profiles. }
  TIcicleOverhangPreset = (
    iopRoofEaveWinterIcicles,
    iopLimestoneCaveStalactites,
    iopGlacialIceCavern
  );

  { Generated hanging spike + optional paired floor stalagmite record. }
  TIcicleSpikeSample = record
    CeilingAttachWorld: TVector3;
    TipWorld: TVector3;
    LengthMeters: Single;
    BaseRadiusMeters: Single;
    HasPairedStalagmite: Boolean;
    FloorHitWorld: TVector3;
    StalagmiteHeightMeters: Single;
  end;

  { Scene transform volume that scans overhead overhangs via WorldRay and
    grows tapered icicles / stalactites + paired floor stalagmites. }
  TCastleIcicleOverhang = class(TCastleTransform)
  private
    FPreset: TIcicleOverhangPreset;
    FScanWidthMeters: Single;
    FScanDepthMeters: Single;
    FCeilingSearchHeightMeters: Single;
    FCandidateProbeCount: Integer;
    FMinSpikeLengthMeters: Single;
    FMaxSpikeLengthMeters: Single;
    FBaseRadiusMeters: Single;
    FMinClearDropMeters: Single;
    FMaxStalagmiteDropMeters: Single;
    FSpawnFloorStalagmites: Boolean;
    FRandomSeed: Integer;
    FShowPreview: Boolean;
    FSpikes: array of TIcicleSpikeSample;
    FPairedStalagmiteCount: Integer;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TIcicleOverhangPreset);
    procedure SetCandidateProbeCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TIcicleOverhangPreset);

    { Evaluate Stefan-law ribbed cone radius at normalized tip progress AU01 in [0..1]
      (0 = ceiling root BaseRadiusMeters, 1 = sharp tip 0.0). }
    function EvaluateProfileRadiusAtNormalizedU(const AU01: Single): Single;

    { Scan AWorldRoot above Self for overhang undersides, clamp spike lengths
      above floor geometry, and optionally spawn paired floor stalagmites. }
    function GrowOverhangSpikes(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;

    function SpikeCount: Integer;
    function GetSpike(const AIndex: Integer): TIcicleSpikeSample;
    procedure RebuildPreview;
    procedure ClearPreview;
    function IcicleSummaryBadge: String;

    property PairedStalagmiteCount: Integer read FPairedStalagmiteCount;
  published
    property Preset: TIcicleOverhangPreset
      read FPreset write SetPreset default iopRoofEaveWinterIcicles;
    property ScanWidthMeters: Single
      read FScanWidthMeters write FScanWidthMeters;
    property ScanDepthMeters: Single
      read FScanDepthMeters write FScanDepthMeters;
    property CeilingSearchHeightMeters: Single
      read FCeilingSearchHeightMeters write FCeilingSearchHeightMeters;
    property CandidateProbeCount: Integer
      read FCandidateProbeCount write SetCandidateProbeCount default 32;
    property MinSpikeLengthMeters: Single
      read FMinSpikeLengthMeters write FMinSpikeLengthMeters;
    property MaxSpikeLengthMeters: Single
      read FMaxSpikeLengthMeters write FMaxSpikeLengthMeters;
    property BaseRadiusMeters: Single
      read FBaseRadiusMeters write FBaseRadiusMeters;
    property MinClearDropMeters: Single
      read FMinClearDropMeters write FMinClearDropMeters;
    property MaxStalagmiteDropMeters: Single
      read FMaxStalagmiteDropMeters write FMaxStalagmiteDropMeters;
    property SpawnFloorStalagmites: Boolean
      read FSpawnFloorStalagmites write FSpawnFloorStalagmites default True;
    property RandomSeed: Integer
      read FRandomSeed write FRandomSeed default 7711;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function IciclePresetToString(const APreset: TIcicleOverhangPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function IciclePresetToString(const APreset: TIcicleOverhangPreset): String;
begin
  case APreset of
    iopRoofEaveWinterIcicles:    Result := 'RoofEaveWinterIcicles';
    iopLimestoneCaveStalactites: Result := 'LimestoneCaveStalactites';
    iopGlacialIceCavern:         Result := 'GlacialIceCavern';
  end;
end;

{$PUSH}{$Q-}{$R-}
function IcicleHash01(const ASeed, ASalt: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(ASeed) * Cardinal(747796405) +
       Cardinal(ASalt + 23) * Cardinal(2891336453) + Cardinal(1013904223);
  H := ((H shr ((H shr 28) + 4)) xor H) * Cardinal(277803737);
  H := (H shr 22) xor H;
  Result := (H and $00FFFFFF) / 16777216.0;
end;
{$POP}

{ TCastleIcicleOverhang ------------------------------------------------------ }

constructor TCastleIcicleOverhang.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCandidateProbeCount := 32;
  FSpawnFloorStalagmites := True;
  FRandomSeed := 7711;
  FShowPreview := True;
  FPairedStalagmiteCount := 0;
  ApplyPreset(iopRoofEaveWinterIcicles);
end;

destructor TCastleIcicleOverhang.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleIcicleOverhang.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'ScanWidthMeters', 'ScanDepthMeters',
       'CeilingSearchHeightMeters', 'CandidateProbeCount',
       'MinSpikeLengthMeters', 'MaxSpikeLengthMeters',
       'BaseRadiusMeters', 'MinClearDropMeters',
       'MaxStalagmiteDropMeters', 'SpawnFloorStalagmites',
       'RandomSeed', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleIcicleOverhang.SetPreset(const AValue: TIcicleOverhangPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleIcicleOverhang.SetCandidateProbeCount(const AValue: Integer);
begin
  FCandidateProbeCount := Clamped(AValue, 4, 256);
end;

procedure TCastleIcicleOverhang.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleIcicleOverhang.ApplyPreset(const APreset: TIcicleOverhangPreset);
begin
  FPreset := APreset;
  case APreset of
    iopRoofEaveWinterIcicles:
      begin
        FScanWidthMeters := 8.0;
        FScanDepthMeters := 4.0;
        FCeilingSearchHeightMeters := 6.0;
        FCandidateProbeCount := 28;
        FMinSpikeLengthMeters := 0.35;
        FMaxSpikeLengthMeters := 1.25;
        FBaseRadiusMeters := 0.065;
        FMinClearDropMeters := 0.55;
        FMaxStalagmiteDropMeters := 6.0;
        FSpawnFloorStalagmites := False;
      end;
    iopLimestoneCaveStalactites:
      begin
        FScanWidthMeters := 10.0;
        FScanDepthMeters := 8.0;
        FCeilingSearchHeightMeters := 8.0;
        FCandidateProbeCount := 36;
        FMinSpikeLengthMeters := 0.65;
        FMaxSpikeLengthMeters := 2.40;
        FBaseRadiusMeters := 0.16;
        FMinClearDropMeters := 0.85;
        FMaxStalagmiteDropMeters := 9.0;
        FSpawnFloorStalagmites := True;
      end;
    iopGlacialIceCavern:
      begin
        FScanWidthMeters := 10.0;
        FScanDepthMeters := 8.0;
        FCeilingSearchHeightMeters := 8.0;
        FCandidateProbeCount := 32;
        FMinSpikeLengthMeters := 0.50;
        FMaxSpikeLengthMeters := 2.10;
        FBaseRadiusMeters := 0.12;
        FMinClearDropMeters := 0.70;
        FMaxStalagmiteDropMeters := 8.5;
        FSpawnFloorStalagmites := True;
      end;
  end;
end;

function TCastleIcicleOverhang.EvaluateProfileRadiusAtNormalizedU(
  const AU01: Single): Single;
var
  U, RibWave: Single;
begin
  U := Clamped(AU01, 0.0, 1.0);
  if U >= 0.9999 then
    Exit(0.0);
  RibWave := 1.0 + 0.08 * Sin(18.0 * Pi * U) * (1.0 - U);
  Result := Max(0.0, FBaseRadiusMeters * Power(1.0 - U, 0.72) * RibWave);
end;

function TCastleIcicleOverhang.GrowOverhangSpikes(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;

  function RayNearestHit(const AOrig, ADir: TVector3; const AMaxDist: Single;
    out AHitPoint: TVector3; out AHitDist: Single): Boolean;
  var
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
    D: Single;
  begin
    Result := False;
    AHitPoint := AOrig;
    AHitDist := AMaxDist + 1.0;
    if AWorldRoot = nil then Exit;
    RH := AWorldRoot.WorldRay(AOrig, ADir);
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = AWorldRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        D := PointsDistance(AOrig, RH[K].Point);
        if (D >= 0.03) and (D <= AMaxDist) and (D < AHitDist) then
        begin
          AHitDist := D;
          AHitPoint := RH[K].Point;
          Result := True;
        end;
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  WT: TMatrix4;
  NProbes, I, OutCount: Integer;
  HalfW, HalfD, SearchH, MinLen, MaxLen, DesiredLen, ClampedLen: Single;
  CeilDist, FloorDist, LX, LZ: Single;
  ProbeWorld, CeilPt, DownStart, FloorPt: TVector3;
  HasFloor: Boolean;
begin
  SetLength(FSpikes, 0);
  FPairedStalagmiteCount := 0;
  Result := 0;
  if AWorldRoot = nil then Exit;

  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;

  NProbes := Clamped(FCandidateProbeCount, 4, 256);
  HalfW := Max(0.25, FScanWidthMeters) * 0.5;
  HalfD := Max(0.25, FScanDepthMeters) * 0.5;
  SearchH := Max(0.5, FCeilingSearchHeightMeters);
  MinLen := Max(0.10, FMinSpikeLengthMeters);
  MaxLen := Max(MinLen + 0.05, FMaxSpikeLengthMeters);

  SetLength(FSpikes, NProbes);
  OutCount := 0;

  for I := 0 to NProbes - 1 do
  begin
    LX := (IcicleHash01(FRandomSeed, I * 3) * 2.0 - 1.0) * HalfW;
    LZ := (IcicleHash01(FRandomSeed, I * 3 + 1) * 2.0 - 1.0) * HalfD;
    ProbeWorld := WT.MultPoint(Vector3(LX, 0.0, LZ));

    { 1. Cast upward (+Y) to locate overhang/ceiling underside }
    if not RayNearestHit(ProbeWorld, Vector3(0.0, 1.0, 0.0), SearchH,
         CeilPt, CeilDist) then
      Continue;

    { 2. Cast downward (-Y) from 4 cm below ceiling to check air drop & floor }
    DownStart := CeilPt - Vector3(0.0, 0.04, 0.0);
    HasFloor := RayNearestHit(DownStart, Vector3(0.0, -1.0, 0.0),
      Max(SearchH * 2.5, FMaxStalagmiteDropMeters + 2.0), FloorPt, FloorDist);

    if HasFloor and (FloorDist < FMinClearDropMeters) then
      Continue;

    DesiredLen := Lerp(IcicleHash01(FRandomSeed, I * 3 + 2), MinLen, MaxLen);
    if HasFloor then
      ClampedLen := Min(DesiredLen, FloorDist * 0.62)
    else
      ClampedLen := DesiredLen;

    if ClampedLen < 0.12 then
      Continue;

    FSpikes[OutCount] := Default(TIcicleSpikeSample);
    FSpikes[OutCount].CeilingAttachWorld := CeilPt;
    FSpikes[OutCount].LengthMeters := ClampedLen;
    FSpikes[OutCount].TipWorld := CeilPt - Vector3(0.0, ClampedLen, 0.0);
    FSpikes[OutCount].BaseRadiusMeters := FBaseRadiusMeters *
      (0.75 + 0.55 * IcicleHash01(FRandomSeed + 91, I));

    if FSpawnFloorStalagmites and HasFloor and
       (FloorDist <= FMaxStalagmiteDropMeters) and
       (FloorDist > ClampedLen + 0.25) then
    begin
      FSpikes[OutCount].HasPairedStalagmite := True;
      FSpikes[OutCount].FloorHitWorld := FloorPt;
      FSpikes[OutCount].StalagmiteHeightMeters := Min(
        ClampedLen * 0.48, (FloorDist - ClampedLen) * 0.55);
      Inc(FPairedStalagmiteCount);
    end;

    Inc(OutCount);
  end;

  SetLength(FSpikes, OutCount);
  Result := OutCount;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleIcicleOverhang.SpikeCount: Integer;
begin
  Result := Length(FSpikes);
end;

function TCastleIcicleOverhang.GetSpike(
  const AIndex: Integer): TIcicleSpikeSample;
begin
  if (AIndex >= 0) and (AIndex < Length(FSpikes)) then
    Result := FSpikes[AIndex]
  else
    Result := Default(TIcicleSpikeSample);
end;

procedure TCastleIcicleOverhang.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
  end;
end;

procedure TCastleIcicleOverhang.RebuildPreview;
var
  InvWT, WT: TMatrix4;
  ConeUpper, ConeLower, MoundBox: TCastleBox;
  I: Integer;
  S: TIcicleSpikeSample;
  Col: TVector4;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if (not FShowPreview) or (Length(FSpikes) = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'IcicleOverhangPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  case FPreset of
    iopRoofEaveWinterIcicles:    Col := Vector4(0.76, 0.93, 1.0, 0.90);
    iopLimestoneCaveStalactites: Col := Vector4(0.64, 0.56, 0.44, 1.0);
    iopGlacialIceCavern:         Col := Vector4(0.48, 0.86, 0.98, 0.92);
  end;

  for I := 0 to High(FSpikes) do
  begin
    S := FSpikes[I];
    ConeUpper := TCastleBox.Create(FPreviewRoot);
    ConeUpper.SetTransient;
    ConeUpper.Pickable := False;
    ConeUpper.Collides := False;
    ConeUpper.Size := Vector3(S.BaseRadiusMeters * 2.0, S.LengthMeters * 0.55, S.BaseRadiusMeters * 2.0);
    ConeUpper.Translation := InvWT.MultPoint(
      S.CeilingAttachWorld - Vector3(0.0, S.LengthMeters * 0.275, 0.0));
    ConeUpper.Color := Col;
    FPreviewRoot.Add(ConeUpper);

    ConeLower := TCastleBox.Create(FPreviewRoot);
    ConeLower.SetTransient;
    ConeLower.Pickable := False;
    ConeLower.Collides := False;
    ConeLower.Size := Vector3(S.BaseRadiusMeters * 0.85, S.LengthMeters * 0.45, S.BaseRadiusMeters * 0.85);
    ConeLower.Translation := InvWT.MultPoint(
      S.CeilingAttachWorld - Vector3(0.0, S.LengthMeters * 0.775, 0.0));
    ConeLower.Color := Col;
    FPreviewRoot.Add(ConeLower);

    if S.HasPairedStalagmite then
    begin
      MoundBox := TCastleBox.Create(FPreviewRoot);
      MoundBox.SetTransient;
      MoundBox.Pickable := False;
      MoundBox.Collides := False;
      MoundBox.Size := Vector3(S.BaseRadiusMeters * 2.3, S.StalagmiteHeightMeters, S.BaseRadiusMeters * 2.3);
      MoundBox.Translation := InvWT.MultPoint(
        S.FloorHitWorld + Vector3(0.0, S.StalagmiteHeightMeters * 0.5, 0.0));
      MoundBox.Color := Col;
      FPreviewRoot.Add(MoundBox);
    end;
  end;

  Add(FPreviewRoot);
end;

function TCastleIcicleOverhang.IcicleSummaryBadge: String;
begin
  Result := Format('[Icicles:%d spikes %d stalagmites]', [
    Length(FSpikes), FPairedStalagmiteCount]);
end;

initialization
  RegisterSerializableComponent(TCastleIcicleOverhang, 'Procedural Icicle & Stalactite Overhang');

end.
