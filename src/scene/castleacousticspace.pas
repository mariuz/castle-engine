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

{ Fibonacci-sphere WorldRay room acoustics solver computing Sabine and
  Eyring-Norris RT60 reverberation decay, outdoor sky-escape leak, early
  reflection predelay, and Uniform Theory of Diffraction (UTD) doorway
  detour low-pass obstruction filtering (Phase 388). }
unit CastleAcousticSpace;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset room material & probe profiles for acoustic simulation. }
  TAcousticSpacePreset = (
    acpCathedralStoneNave,
    acpPaddedRecordingBooth,
    acpOpenCanyonEcho
  );

  { Per-ray hit record captured during BakeRoomAcoustics. }
  TAcousticRaySample = record
    Direction: TVector3;
    HitPoint: TVector3;
    DistanceMeters: Single;
    EscapedToSky: Boolean;
    SurfaceAbsorption01: Single;
  end;

  { Aggregated physical reverberation metrics returned by BakeRoomAcoustics. }
  TAcousticRoomReport = record
    RayCount: Integer;
    HitRayCount: Integer;
    EscapedSkyRayCount: Integer;
    OutdoorLeak01: Single;
    MeanFreePathMeters: Single;
    MinWallDistMeters: Single;
    EstimatedVolumeM3: Single;
    EstimatedSurfaceAreaM2: Single;
    MeanAbsorption01: Single;
    SabineRt60Sec: Single;
    EyringRt60Sec: Single;
    PredelayMs: Single;
    WetReverbMix01: Single;
  end;

  { Direct vs. doorway-diffracted vs. wall-occluded acoustic transmission sample. }
  TAcousticObstructionSample = record
    DirectLineOfSight: Boolean;
    DiffractedViaPortal: Boolean;
    DirectDistanceMeters: Single;
    PortalPathMeters: Single;
    DetourExcessMeters: Single;
    FresnelNumber1kHz: Single;
    DirectGain01: Single;
    LowPassCutoffHz: Single;
  end;

  { Scene transform probe that raytraces enclosing 3D room geometry to estimate
    Sabine/Eyring RT60 reverb and portal diffraction LPF obstruction. }
  TCastleAcousticProbe = class(TCastleTransform)
  private
    FPreset: TAcousticSpacePreset;
    FRayCount: Integer;
    FMaxProbeDistanceMeters: Single;
    FDefaultWallAbsorption: Single;
    FAirAttenuationPerMeter: Single;
    FSpeedOfSoundMps: Single;
    FShowPreview: Boolean;
    FLastRoom: TAcousticRoomReport;
    FRaySamples: array of TAcousticRaySample;
    FPreviewRoot: TCastleTransform;
    FPreviewScene: TCastleScene;
    procedure SetPreset(const AValue: TAcousticSpacePreset);
    procedure SetRayCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
    procedure EnsurePreviewNodes;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TAcousticSpacePreset);

    { Cast Fibonacci-sphere WorldRay feelers from Self world origin to estimate
      enclosing volume, material absorption, Sabine/Eyring RT60, and predelay. }
    function BakeRoomAcoustics(
      const AWorldRoot: TCastleAbstractRootTransform): TAcousticRoomReport;

    { Evaluate direct line-of-sight, 1-portal doorway diffraction detour, or
      sealed wall transmission muffling from ASourceWorldPos to Self. }
    function EvaluateSourceObstruction(
      const AWorldRoot: TCastleAbstractRootTransform;
      const ASourceWorldPos, APortalWorldPos: TVector3): TAcousticObstructionSample;

    procedure RebuildPreview;
    procedure ClearPreview;
    function AcousticSummaryBadge: String;

    property LastRoom: TAcousticRoomReport read FLastRoom;
  published
    property Preset: TAcousticSpacePreset
      read FPreset write SetPreset default acpCathedralStoneNave;
    property RayCount: Integer
      read FRayCount write SetRayCount default 48;
    property MaxProbeDistanceMeters: Single
      read FMaxProbeDistanceMeters write FMaxProbeDistanceMeters;
    property DefaultWallAbsorption: Single
      read FDefaultWallAbsorption write FDefaultWallAbsorption;
    property AirAttenuationPerMeter: Single
      read FAirAttenuationPerMeter write FAirAttenuationPerMeter;
    property SpeedOfSoundMps: Single
      read FSpeedOfSoundMps write FSpeedOfSoundMps;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function AcousticPresetToString(const APreset: TAcousticSpacePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function AcousticPresetToString(const APreset: TAcousticSpacePreset): String;
begin
  case APreset of
    acpCathedralStoneNave:   Result := 'CathedralStoneNave';
    acpPaddedRecordingBooth: Result := 'PaddedRecordingBooth';
    acpOpenCanyonEcho:       Result := 'OpenCanyonEcho';
  end;
end;

function ClassifySurfaceAbsorption(const AItemName: String;
  const ADefaultAlpha: Single): Single;
var
  Lower: String;
begin
  Lower := LowerCase(AItemName);
  if (Pos('carpet', Lower) > 0) or (Pos('padded', Lower) > 0) or
     (Pos('foam', Lower) > 0) or (Pos('curtain', Lower) > 0) or
     (Pos('snow', Lower) > 0) then
    Result := 0.65
  else if (Pos('wood', Lower) > 0) or (Pos('plank', Lower) > 0) or
          (Pos('timber', Lower) > 0) then
    Result := 0.16
  else if (Pos('stone', Lower) > 0) or (Pos('marble', Lower) > 0) or
          (Pos('cathedral', Lower) > 0) or (Pos('concrete', Lower) > 0) or
          (Pos('granite', Lower) > 0) then
    Result := 0.032
  else
    Result := Clamped(ADefaultAlpha, 0.01, 0.98);
end;

{ TCastleAcousticProbe ------------------------------------------------------- }

constructor TCastleAcousticProbe.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRayCount := 48;
  FSpeedOfSoundMps := 343.0;
  FShowPreview := True;
  FLastRoom := Default(TAcousticRoomReport);
  ApplyPreset(acpCathedralStoneNave);
end;

destructor TCastleAcousticProbe.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleAcousticProbe.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'RayCount', 'MaxProbeDistanceMeters',
       'DefaultWallAbsorption', 'AirAttenuationPerMeter',
       'SpeedOfSoundMps', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleAcousticProbe.SetPreset(const AValue: TAcousticSpacePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleAcousticProbe.SetRayCount(const AValue: Integer);
begin
  FRayCount := Clamped(AValue, 8, 256);
end;

procedure TCastleAcousticProbe.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleAcousticProbe.ApplyPreset(const APreset: TAcousticSpacePreset);
begin
  FPreset := APreset;
  FSpeedOfSoundMps := 343.0;
  case APreset of
    acpCathedralStoneNave:
      begin
        FRayCount := 48;
        FMaxProbeDistanceMeters := 65.0;
        FDefaultWallAbsorption := 0.035;
        FAirAttenuationPerMeter := 0.0012;
      end;
    acpPaddedRecordingBooth:
      begin
        FRayCount := 48;
        FMaxProbeDistanceMeters := 25.0;
        FDefaultWallAbsorption := 0.62;
        FAirAttenuationPerMeter := 0.0018;
      end;
    acpOpenCanyonEcho:
      begin
        FRayCount := 64;
        FMaxProbeDistanceMeters := 90.0;
        FDefaultWallAbsorption := 0.08;
        FAirAttenuationPerMeter := 0.0015;
      end;
  end;
end;

function TCastleAcousticProbe.BakeRoomAcoustics(
  const AWorldRoot: TCastleAbstractRootTransform): TAcousticRoomReport;
const
  GoldenAngle = 2.39996323;
var
  WT: TMatrix4;
  ProbeOrigin, Dir: TVector3;
  N, I, K: Integer;
  Y, RadAtY, Theta, MaxDist, BestDist, D, SumDist, SumAlpha, AlphaEff: Single;
  DenomSabine, DenomEyring, SoundSpd: Single;
  RH: TRayCollision;
  HitItem, BestItem: TCastleTransform;
begin
  Result := Default(TAcousticRoomReport);
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  ProbeOrigin := WT.MultPoint(TVector3.Zero);

  N := Clamped(FRayCount, 8, 256);
  MaxDist := Max(1.0, FMaxProbeDistanceMeters);
  SoundSpd := Max(50.0, FSpeedOfSoundMps);
  Result.RayCount := N;
  Result.MinWallDistMeters := MaxDist;
  SetLength(FRaySamples, N);

  SumDist := 0.0;
  SumAlpha := 0.0;

  for I := 0 to N - 1 do
  begin
    Y := 1.0 - (2.0 * (I + 0.5) / N);
    RadAtY := Sqrt(Max(0.0, 1.0 - Y * Y));
    Theta := GoldenAngle * I;
    Dir := Vector3(Cos(Theta) * RadAtY, Y, Sin(Theta) * RadAtY).Normalize;

    FRaySamples[I].Direction := Dir;
    BestDist := MaxDist + 1.0;
    BestItem := nil;

    if AWorldRoot <> nil then
    begin
      RH := AWorldRoot.WorldRay(ProbeOrigin, Dir);
      try
        if RH <> nil then
          for K := 0 to RH.Count - 1 do
          begin
            HitItem := RH[K].Item;
            if (HitItem = nil) or (HitItem = AWorldRoot) or (HitItem = Self) then
              Continue;
            if csTransient in HitItem.ComponentStyle then
              Continue;
            D := PointsDistance(ProbeOrigin, RH[K].Point);
            if (D >= 0.02) and (D <= MaxDist) and (D < BestDist) then
            begin
              BestDist := D;
              BestItem := HitItem;
            end;
          end;
      finally
        FreeAndNil(RH);
      end;
    end;

    if BestItem <> nil then
    begin
      Inc(Result.HitRayCount);
      FRaySamples[I].EscapedToSky := False;
      FRaySamples[I].DistanceMeters := BestDist;
      FRaySamples[I].HitPoint := ProbeOrigin + Dir * BestDist;
      FRaySamples[I].SurfaceAbsorption01 := ClassifySurfaceAbsorption(
        BestItem.Name, FDefaultWallAbsorption);
      SumDist := SumDist + BestDist;
      SumAlpha := SumAlpha + FRaySamples[I].SurfaceAbsorption01;
      if BestDist < Result.MinWallDistMeters then
        Result.MinWallDistMeters := BestDist;
    end else
    begin
      Inc(Result.EscapedSkyRayCount);
      FRaySamples[I].EscapedToSky := True;
      FRaySamples[I].DistanceMeters := MaxDist;
      FRaySamples[I].HitPoint := ProbeOrigin + Dir * (MaxDist * 0.35);
      FRaySamples[I].SurfaceAbsorption01 := 1.0;
    end;
  end;

  Result.OutdoorLeak01 := Result.EscapedSkyRayCount / N;
  if Result.HitRayCount > 0 then
  begin
    Result.MeanFreePathMeters := SumDist / Result.HitRayCount;
    Result.MeanAbsorption01 := SumAlpha / Result.HitRayCount;
  end else
  begin
    Result.MeanFreePathMeters := 0.0;
    Result.MeanAbsorption01 := 1.0;
    Result.MinWallDistMeters := 0.0;
  end;

  if Result.HitRayCount = 0 then
  begin
    Result.EstimatedVolumeM3 := 0.0;
    Result.EstimatedSurfaceAreaM2 := 0.0;
    Result.SabineRt60Sec := 0.0;
    Result.EyringRt60Sec := 0.0;
    Result.PredelayMs := 0.0;
    Result.WetReverbMix01 := 0.0;
  end else
  begin
    Result.EstimatedVolumeM3 := (4.0 / 3.0) * Pi *
      Power(Result.MeanFreePathMeters, 3.0) *
      Clamped(1.0 - 0.88 * Result.OutdoorLeak01, 0.04, 1.0);
    Result.EstimatedSurfaceAreaM2 := 4.0 * Pi * Sqr(Result.MeanFreePathMeters);

    { Open sky rays act as an aperture of 100% absorption }
    AlphaEff := Clamped(
      Lerp(Result.OutdoorLeak01, Result.MeanAbsorption01, 0.985), 0.015, 0.99);
    DenomSabine := Result.EstimatedSurfaceAreaM2 * AlphaEff +
      4.0 * Max(0.0, FAirAttenuationPerMeter) * Result.EstimatedVolumeM3;
    DenomEyring := -Result.EstimatedSurfaceAreaM2 * Ln(1.0 - Min(0.985, AlphaEff)) +
      4.0 * Max(0.0, FAirAttenuationPerMeter) * Result.EstimatedVolumeM3;

    if DenomSabine > 1e-4 then
      Result.SabineRt60Sec := (0.161 * Result.EstimatedVolumeM3) / DenomSabine;
    if DenomEyring > 1e-4 then
      Result.EyringRt60Sec := (0.161 * Result.EstimatedVolumeM3) / DenomEyring;

    Result.PredelayMs := (2.0 * Result.MinWallDistMeters / SoundSpd) * 1000.0;
    Result.WetReverbMix01 := Clamped(
      (1.0 - Result.OutdoorLeak01) * Clamped(Result.SabineRt60Sec / 2.5, 0.08, 0.92),
      0.0, 0.95);
  end;

  FLastRoom := Result;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleAcousticProbe.EvaluateSourceObstruction(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ASourceWorldPos, APortalWorldPos: TVector3): TAcousticObstructionSample;

  function SegmentUnobstructed(const AFrom, ATo: TVector3): Boolean;
  var
    Seg: TVector3;
    Len, D: Single;
    RH: TRayCollision;
    J: Integer;
    Item: TCastleTransform;
  begin
    Result := True;
    if AWorldRoot = nil then Exit;
    Seg := ATo - AFrom;
    Len := Seg.Length;
    if Len < 0.02 then Exit;
    Seg := Seg / Len;
    RH := AWorldRoot.WorldRay(AFrom, Seg);
    try
      if RH = nil then Exit;
      for J := 0 to RH.Count - 1 do
      begin
        Item := RH[J].Item;
        if (Item = nil) or (Item = AWorldRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        D := PointsDistance(AFrom, RH[J].Point);
        if (D > 0.03) and (D < Len - 0.03) then
          Exit(False);
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  WT: TMatrix4;
  ListenerPos: TVector3;
  Lambda1kHz, D1, D2: Single;
begin
  Result := Default(TAcousticObstructionSample);
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  ListenerPos := WT.MultPoint(TVector3.Zero);

  Result.DirectDistanceMeters := Max(0.01, PointsDistance(ListenerPos, ASourceWorldPos));
  Lambda1kHz := Max(0.05, FSpeedOfSoundMps) / 1000.0;

  if SegmentUnobstructed(ListenerPos, ASourceWorldPos) then
  begin
    Result.DirectLineOfSight := True;
    Result.DiffractedViaPortal := False;
    Result.PortalPathMeters := Result.DirectDistanceMeters;
    Result.DetourExcessMeters := 0.0;
    Result.FresnelNumber1kHz := 0.0;
    Result.DirectGain01 := 1.0;
    Result.LowPassCutoffHz := 20000.0;
    Exit;
  end;

  { Direct ray is blocked; test 1-bounce doorway/portal diffraction path }
  D1 := PointsDistance(ListenerPos, APortalWorldPos);
  D2 := PointsDistance(APortalWorldPos, ASourceWorldPos);
  Result.PortalPathMeters := D1 + D2;
  Result.DetourExcessMeters := Max(0.0, Result.PortalPathMeters - Result.DirectDistanceMeters);
  Result.FresnelNumber1kHz := (2.0 * Result.DetourExcessMeters) / Lambda1kHz;

  if SegmentUnobstructed(ListenerPos, APortalWorldPos) and
     SegmentUnobstructed(APortalWorldPos, ASourceWorldPos) then
  begin
    Result.DirectLineOfSight := False;
    Result.DiffractedViaPortal := True;
    { Kurze-Anderson UTD edge diffraction attenuation & HF shadow rolloff }
    Result.DirectGain01 := Clamped(1.0 / Sqrt(1.0 + 3.0 * Result.FresnelNumber1kHz), 0.16, 0.88);
    Result.LowPassCutoffHz := Clamped(8500.0 / (1.0 + 0.65 * Result.FresnelNumber1kHz), 750.0, 8500.0);
  end else
  begin
    { Completely sealed behind solid masonry without open doorway path }
    Result.DirectLineOfSight := False;
    Result.DiffractedViaPortal := False;
    Result.DirectGain01 := 0.10;
    Result.LowPassCutoffHz := 380.0;
  end;
end;

procedure TCastleAcousticProbe.EnsurePreviewNodes;
begin
  if FPreviewRoot <> nil then Exit;
  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'AcousticProbePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewScene := TCastleScene.Create(FPreviewRoot);
  FPreviewScene.SetTransient;
  FPreviewScene.Name := 'AcousticProbePreviewScene';
  FPreviewScene.Pickable := False;
  FPreviewScene.Collides := False;
  FPreviewRoot.Add(FPreviewScene);
end;

procedure TCastleAcousticProbe.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewScene := nil;
  end;
end;

procedure TCastleAcousticProbe.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  Counts: array of Int32;
  InvWT, WT: TMatrix4;
  LocalOrig: TVector3;
  I: Integer;
begin
  if (csDestroying in ComponentState) or (not FShowPreview) then Exit;
  if Length(FRaySamples) = 0 then
  begin
    ClearPreview;
    Exit;
  end;

  EnsurePreviewNodes;
  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then
      InvWT := TMatrix4.Identity;
  end;
  LocalOrig := TVector3.Zero;

  SetLength(Pts, Length(FRaySamples) * 2);
  SetLength(Counts, Length(FRaySamples));
  for I := 0 to High(FRaySamples) do
  begin
    Pts[I * 2] := LocalOrig;
    Pts[I * 2 + 1] := InvWT.MultPoint(FRaySamples[I].HitPoint);
    Counts[I] := 2;
  end;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FLastRoom.SabineRt60Sec > 1.2 then
    MatNode.EmissiveColor := Vector3(0.32, 0.78, 1.0)
  else
    MatNode.EmissiveColor := Vector3(0.35, 0.92, 0.56);
  ShapeNode.Material := MatNode;

  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewScene.Load(RootNode, True);
end;

function TCastleAcousticProbe.AcousticSummaryBadge: String;
begin
  Result := FormatDot('[Acoustic:RT60=%.2fs Leak=%.0f%% Mix=%.0f%%]', [
    FLastRoom.SabineRt60Sec,
    FLastRoom.OutdoorLeak01 * 100.0,
    FLastRoom.WetReverbMix01 * 100.0]);
end;

initialization
  RegisterSerializableComponent(TCastleAcousticProbe, 'Acoustic Reverb & Diffraction Probe');

end.
