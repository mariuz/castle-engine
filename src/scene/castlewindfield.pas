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

{ Procedural Foliage Wind Gust Field, 3-Tier Pivot-Painter Trunk/Branch/Leaf
  Bend & Expanding Radial Shockwave Ring Director (Phase 364 — UE 6.0+
  WindDirectionalSource & Radial Impulse Parity). }
unit CastleWindField;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Beaufort-scale wind & storm presets. }
  TWindBeaufortPreset = (
    wbpCustom,
    wbpGentleSpringBreeze,
    wbpAutumnGaleSquall,
    wbpHurricaneTempest
  );

  { Propagating radial explosion / helicopter-rotor shockwave ring. }
  TWindShockwaveRing = record
    OriginWorld: TVector3;
    PeakForceMps: Single;
    WaveSpeedMps: Single;
    MaxRadiusMeters: Single;
    CurrentRadiusMeters: Single;
    BandHalfWidthMeters: Single;
    Active: Boolean;
  end;

  { Evaluated 3-tier UE Pivot-Painter 2.0 foliage wind & bend state at a world point. }
  TPivotPainterWindSample = record
    NetWindVelocityMps: TVector3;
    TrunkBendOffsetMeters: TVector3;
    BranchSwayOffsetMeters: TVector3;
    LeafFlutterPhase: Single;
    ShockwaveContributionMps: Single;
  end;

  { Global directional wind gust field + propagating radial shockwave impulse director. }
  TCastleWindFieldDirector = class(TCastleTransform)
  private
    FPreset: TWindBeaufortPreset;
    FWindAzimuthDeg: Single;
    FBaseWindSpeedMps: Single;
    FGustAmplitudeMps: Single;
    FGustFrequencyHz: Single;
    FTrunkStiffness: Single;
    FBranchFlexibility: Single;
    FShowWindGrovePreview: Boolean;
    FElapsedTimeSec: Single;
    FShockwaves: array of TWindShockwaveRing;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TWindBeaufortPreset);
    procedure SetWindAzimuthDeg(const AValue: Single);
    procedure SetBaseWindSpeedMps(const AValue: Single);
    procedure SetGustAmplitudeMps(const AValue: Single);
    procedure SetGustFrequencyHz(const AValue: Single);
    procedure SetTrunkStiffness(const AValue: Single);
    procedure SetBranchFlexibility(const AValue: Single);
    procedure SetShowWindGrovePreview(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParams(const APreset: TWindBeaufortPreset);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure TriggerRadialShockwave(const AOriginWorld: TVector3;
      const APeakForceMps, AWaveSpeedMps, AMaxRadiusMeters: Single);
    procedure ClearShockwaves;
    function ActiveShockwaveCount: Integer;
    function GetShockwave(const AIndex: Integer): TWindShockwaveRing;
    procedure StepWindField(const Dt: Single);
    function SamplePivotWindAtWorld(const AWorldPos: TVector3;
      const ATreeHeightMeters: Single): TPivotPainterWindSample;
    procedure RebuildWindGrovePreviewMesh;
    function WindSummaryBadge: String;
    property ElapsedTimeSec: Single read FElapsedTimeSec;
  published
    property Preset: TWindBeaufortPreset read FPreset write SetPreset default wbpGentleSpringBreeze;
    property WindAzimuthDeg: Single read FWindAzimuthDeg write SetWindAzimuthDeg {$ifdef FPC}default 35.0{$endif};
    property BaseWindSpeedMps: Single read FBaseWindSpeedMps write SetBaseWindSpeedMps {$ifdef FPC}default 4.2{$endif};
    property GustAmplitudeMps: Single read FGustAmplitudeMps write SetGustAmplitudeMps {$ifdef FPC}default 2.6{$endif};
    property GustFrequencyHz: Single read FGustFrequencyHz write SetGustFrequencyHz {$ifdef FPC}default 0.40{$endif};
    property TrunkStiffness: Single read FTrunkStiffness write SetTrunkStiffness {$ifdef FPC}default 14.0{$endif};
    property BranchFlexibility: Single read FBranchFlexibility write SetBranchFlexibility {$ifdef FPC}default 1.35{$endif};
    property ShowWindGrovePreview: Boolean read FShowWindGrovePreview write SetShowWindGrovePreview default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function WindPresetToString(const APreset: TWindBeaufortPreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function WindPresetToString(const APreset: TWindBeaufortPreset): String;
begin
  case APreset of
    wbpCustom: Result := 'Custom Wind & Gust Field';
    wbpGentleSpringBreeze: Result := 'Beaufort 3 Gentle Spring Breeze (4.2 m/s)';
    wbpAutumnGaleSquall: Result := 'Beaufort 8 Autumn Gale Squall (14.5 m/s)';
    wbpHurricaneTempest: Result := 'Beaufort 12 Hurricane Tempest (28.0 m/s)';
  end;
end;

{ TCastleWindFieldDirector ---------------------------------------------------- }

constructor TCastleWindFieldDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowWindGrovePreview := True;
  FElapsedTimeSec := 0.0;
  ApplyPresetParams(wbpGentleSpringBreeze);
  RebuildWindGrovePreviewMesh;
end;

destructor TCastleWindFieldDirector.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleWindFieldDirector.ApplyPresetParams(const APreset: TWindBeaufortPreset);
begin
  FPreset := APreset;
  case APreset of
    wbpGentleSpringBreeze, wbpCustom:
      begin
        FWindAzimuthDeg := 35.0;
        FBaseWindSpeedMps := 4.2;
        FGustAmplitudeMps := 2.6;
        FGustFrequencyHz := 0.40;
        FTrunkStiffness := 14.0;
        FBranchFlexibility := 1.35;
      end;
    wbpAutumnGaleSquall:
      begin
        FWindAzimuthDeg := 60.0;
        FBaseWindSpeedMps := 14.5;
        FGustAmplitudeMps := 7.5;
        FGustFrequencyHz := 0.75;
        FTrunkStiffness := 12.0;
        FBranchFlexibility := 1.80;
      end;
    wbpHurricaneTempest:
      begin
        FWindAzimuthDeg := 15.0;
        FBaseWindSpeedMps := 28.0;
        FGustAmplitudeMps := 12.0;
        FGustFrequencyHz := 1.15;
        FTrunkStiffness := 10.5;
        FBranchFlexibility := 2.25;
      end;
  end;
end;

procedure TCastleWindFieldDirector.SetPreset(const AValue: TWindBeaufortPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> wbpCustom then
  begin
    ApplyPresetParams(AValue);
    RebuildWindGrovePreviewMesh;
  end;
end;

procedure TCastleWindFieldDirector.SetWindAzimuthDeg(const AValue: Single);
begin
  if SameValue(FWindAzimuthDeg, AValue, 1e-4) then Exit;
  FWindAzimuthDeg := AValue;
  FPreset := wbpCustom;
  RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.SetBaseWindSpeedMps(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 80.0);
  if SameValue(FBaseWindSpeedMps, V, 1e-4) then Exit;
  FBaseWindSpeedMps := V;
  FPreset := wbpCustom;
  RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.SetGustAmplitudeMps(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 50.0);
  if SameValue(FGustAmplitudeMps, V, 1e-4) then Exit;
  FGustAmplitudeMps := V;
  FPreset := wbpCustom;
  RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.SetGustFrequencyHz(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.05, 10.0);
  if SameValue(FGustFrequencyHz, V, 1e-4) then Exit;
  FGustFrequencyHz := V;
  FPreset := wbpCustom;
end;

procedure TCastleWindFieldDirector.SetTrunkStiffness(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 1.0, 200.0);
  if SameValue(FTrunkStiffness, V, 1e-4) then Exit;
  FTrunkStiffness := V;
  FPreset := wbpCustom;
  RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.SetBranchFlexibility(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.1, 8.0);
  if SameValue(FBranchFlexibility, V, 1e-4) then Exit;
  FBranchFlexibility := V;
  FPreset := wbpCustom;
  RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.SetShowWindGrovePreview(const AValue: Boolean);
begin
  if FShowWindGrovePreview = AValue then Exit;
  FShowWindGrovePreview := AValue;
  if not FShowWindGrovePreview then
    ClearTransientScene
  else
    RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.TriggerRadialShockwave(
  const AOriginWorld: TVector3;
  const APeakForceMps, AWaveSpeedMps, AMaxRadiusMeters: Single);
var
  N: Integer;
begin
  N := Length(FShockwaves);
  SetLength(FShockwaves, N + 1);
  FShockwaves[N].OriginWorld := AOriginWorld;
  FShockwaves[N].PeakForceMps := Max(1.0, APeakForceMps);
  FShockwaves[N].WaveSpeedMps := Max(1.0, AWaveSpeedMps);
  FShockwaves[N].MaxRadiusMeters := Max(2.0, AMaxRadiusMeters);
  FShockwaves[N].CurrentRadiusMeters := 0.0;
  FShockwaves[N].BandHalfWidthMeters := Max(1.5, AMaxRadiusMeters * 0.18);
  FShockwaves[N].Active := True;
  RebuildWindGrovePreviewMesh;
end;

procedure TCastleWindFieldDirector.ClearShockwaves;
begin
  SetLength(FShockwaves, 0);
  RebuildWindGrovePreviewMesh;
end;

function TCastleWindFieldDirector.ActiveShockwaveCount: Integer;
begin
  Result := Length(FShockwaves);
end;

function TCastleWindFieldDirector.GetShockwave(const AIndex: Integer): TWindShockwaveRing;
begin
  if (AIndex >= 0) and (AIndex < Length(FShockwaves)) then
    Result := FShockwaves[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleWindFieldDirector.StepWindField(const Dt: Single);
var
  I, WriteIdx: Integer;
begin
  if Dt <= 0.0 then Exit;
  FElapsedTimeSec := FElapsedTimeSec + Dt;
  WriteIdx := 0;
  for I := 0 to High(FShockwaves) do
  begin
    FShockwaves[I].CurrentRadiusMeters :=
      FShockwaves[I].CurrentRadiusMeters + FShockwaves[I].WaveSpeedMps * Dt;
    if FShockwaves[I].CurrentRadiusMeters <=
       (FShockwaves[I].MaxRadiusMeters + FShockwaves[I].BandHalfWidthMeters) then
    begin
      FShockwaves[WriteIdx] := FShockwaves[I];
      Inc(WriteIdx);
    end;
  end;
  SetLength(FShockwaves, WriteIdx);
  if FShowWindGrovePreview then
    RebuildWindGrovePreviewMesh;
end;

function TCastleWindFieldDirector.SamplePivotWindAtWorld(
  const AWorldPos: TVector3; const ATreeHeightMeters: Single): TPivotPainterWindSample;
var
  AzRad, Phase, GustPulse, InstantSpeed, DistXZ, WaveDelta, CrestW, AttenW,
    ShockMag, EffH, TrunkScale, MaxBend, TrunkLen: Single;
  WindDir, ShockVec, DeltaXZ, RadialDir, LateralDir: TVector3;
  I: Integer;
begin
  AzRad := DegToRad(FWindAzimuthDeg);
  WindDir := Vector3(Cos(AzRad), 0.0, Sin(AzRad));
  Phase := FElapsedTimeSec * FGustFrequencyHz * 2.0 * Pi -
           TVector3.DotProduct(AWorldPos, WindDir) * 0.16;
  GustPulse := 0.5 + 0.5 * Sin(Phase);
  InstantSpeed := FBaseWindSpeedMps + FGustAmplitudeMps * GustPulse;

  ShockVec := TVector3.Zero;
  Result.ShockwaveContributionMps := 0.0;
  for I := 0 to High(FShockwaves) do
  begin
    DeltaXZ := Vector3(
      AWorldPos.X - FShockwaves[I].OriginWorld.X,
      0.0,
      AWorldPos.Z - FShockwaves[I].OriginWorld.Z);
    DistXZ := DeltaXZ.Length;
    WaveDelta := Abs(DistXZ - FShockwaves[I].CurrentRadiusMeters);
    if WaveDelta < FShockwaves[I].BandHalfWidthMeters then
    begin
      CrestW := 1.0 - (WaveDelta / FShockwaves[I].BandHalfWidthMeters);
      AttenW := 1.0 - EnsureRange(
        Sqr(FShockwaves[I].CurrentRadiusMeters / Max(1.0, FShockwaves[I].MaxRadiusMeters)) * 0.80,
        0.0, 0.80);
      if DistXZ > 1e-4 then
        RadialDir := DeltaXZ / DistXZ
      else
        RadialDir := WindDir;
      ShockMag := FShockwaves[I].PeakForceMps * CrestW * AttenW;
      ShockVec := ShockVec + RadialDir * ShockMag;
      Result.ShockwaveContributionMps := Result.ShockwaveContributionMps + ShockMag;
    end;
  end;

  Result.NetWindVelocityMps := WindDir * InstantSpeed + ShockVec;

  { 3-Tier Pivot-Painter 2.0 Hierarchy:
    1) Cantilever trunk bend ~ H^2 / Stiffness
    2) Secondary branch sway + cross-wind harmonic flutter
    3) High-frequency leaf phase }
  EffH := Max(0.5, ATreeHeightMeters);
  TrunkScale := 0.032 * Sqr(EffH) / Max(1.0, FTrunkStiffness);
  Result.TrunkBendOffsetMeters := Result.NetWindVelocityMps * TrunkScale;
  MaxBend := EffH * 0.55;
  TrunkLen := Result.TrunkBendOffsetMeters.Length;
  if TrunkLen > MaxBend then
    Result.TrunkBendOffsetMeters := Result.TrunkBendOffsetMeters * (MaxBend / TrunkLen);

  LateralDir := Vector3(-WindDir.Z, 0.0, WindDir.X);
  Result.BranchSwayOffsetMeters :=
    Result.TrunkBendOffsetMeters * (0.45 * FBranchFlexibility) +
    LateralDir * (Sin(Phase * 2.3 + AWorldPos.X * 0.7) * 0.08 * FBranchFlexibility);

  Result.LeafFlutterPhase := Frac(
    FElapsedTimeSec * (1.8 + Result.NetWindVelocityMps.Length * 0.32) +
    (AWorldPos.X + AWorldPos.Z) * 0.13);
end;

procedure TCastleWindFieldDirector.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientWindGrovePreview';
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

procedure TCastleWindFieldDirector.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleWindFieldDirector.RebuildWindGrovePreviewMesh;
const
  TreeOffsets: array[0..4] of TVector3 = (
    (X:  0.0; Y: 0.0; Z:  0.0),
    (X: -5.5; Y: 0.0; Z: -4.0),
    (X:  5.5; Y: 0.0; Z: -4.0),
    (X: -5.5; Y: 0.0; Z:  4.5),
    (X:  5.5; Y: 0.0; Z:  4.5)
  );
var
  Verts, Cols: TVector3List;
  I, Seg: Integer;
  BaseLoc, BaseW, CrownApexLoc, TrunkCol, CanopyCol, RingCol, P0, P1: TVector3;
  Sample: TPivotPainterWindSample;
  TreeH, R, A0, A1, ShockRatio: Single;
begin
  if not FShowWindGrovePreview then Exit;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    TrunkCol := Vector3(0.42, 0.28, 0.16);
    for I := 0 to High(TreeOffsets) do
    begin
      TreeH := 4.2;
      BaseLoc := TreeOffsets[I];
      if Parent <> nil then
        BaseW := LocalToWorld(BaseLoc)
      else
        BaseW := Translation + BaseLoc;

      Sample := SamplePivotWindAtWorld(BaseW, TreeH);
      CrownApexLoc := BaseLoc + Vector3(0.0, TreeH, 0.0) +
        Sample.TrunkBendOffsetMeters + Sample.BranchSwayOffsetMeters;

      ShockRatio := EnsureRange(Sample.ShockwaveContributionMps / 18.0, 0.0, 1.0);
      CanopyCol := Lerp(ShockRatio, Vector3(0.18, 0.68, 0.28), Vector3(0.96, 0.72, 0.20));

      { Trunk triangle }
      Verts.Add(BaseLoc + Vector3(-0.18, 0.0, 0.0));
      Verts.Add(BaseLoc + Vector3( 0.18, 0.0, 0.0));
      Verts.Add(CrownApexLoc);
      Cols.Add(TrunkCol); Cols.Add(TrunkCol); Cols.Add(TrunkCol);

      { Swaying foliage crown cone (2 crossed triangles) }
      Verts.Add(BaseLoc + Vector3(-1.1, TreeH * 0.45, 0.0) + Sample.TrunkBendOffsetMeters * 0.45);
      Verts.Add(BaseLoc + Vector3( 1.1, TreeH * 0.45, 0.0) + Sample.TrunkBendOffsetMeters * 0.45);
      Verts.Add(CrownApexLoc);
      Cols.Add(CanopyCol); Cols.Add(CanopyCol); Cols.Add(CanopyCol);

      Verts.Add(BaseLoc + Vector3(0.0, TreeH * 0.45, -1.1) + Sample.TrunkBendOffsetMeters * 0.45);
      Verts.Add(BaseLoc + Vector3(0.0, TreeH * 0.45,  1.1) + Sample.TrunkBendOffsetMeters * 0.45);
      Verts.Add(CrownApexLoc);
      Cols.Add(CanopyCol); Cols.Add(CanopyCol); Cols.Add(CanopyCol);
    end;

    { Expanding radial shockwave ring ribbons }
    RingCol := Vector3(1.0, 0.55, 0.18);
    for I := 0 to High(FShockwaves) do
    begin
      R := Max(0.25, FShockwaves[I].CurrentRadiusMeters);
      if Parent <> nil then
        BaseLoc := WorldToLocal(FShockwaves[I].OriginWorld)
      else
        BaseLoc := FShockwaves[I].OriginWorld - Translation;
      for Seg := 0 to 15 do
      begin
        A0 := (Seg / 16.0) * 2.0 * Pi;
        A1 := ((Seg + 1) / 16.0) * 2.0 * Pi;
        P0 := BaseLoc + Vector3(Cos(A0) * R, 0.12, Sin(A0) * R);
        P1 := BaseLoc + Vector3(Cos(A1) * R, 0.12, Sin(A1) * R);
        Verts.Add(P0);
        Verts.Add(P1);
        Verts.Add(BaseLoc + Vector3(Cos(A0) * (R + 0.35), 0.25, Sin(A0) * (R + 0.35)));
        Cols.Add(RingCol); Cols.Add(RingCol); Cols.Add(RingCol);
      end;
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

function TCastleWindFieldDirector.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('azimuth', FWindAzimuthDeg);
    RootObj.Add('baseSpeed', FBaseWindSpeedMps);
    RootObj.Add('gustAmp', FGustAmplitudeMps);
    RootObj.Add('gustFreq', FGustFrequencyHz);
    RootObj.Add('stiffness', FTrunkStiffness);
    RootObj.Add('branchFlex', FBranchFlexibility);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleWindFieldDirector.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FWindAzimuthDeg := RootObj.Get('azimuth', FWindAzimuthDeg);
      FBaseWindSpeedMps := EnsureRange(RootObj.Get('baseSpeed', FBaseWindSpeedMps), 0.0, 80.0);
      FGustAmplitudeMps := EnsureRange(RootObj.Get('gustAmp', FGustAmplitudeMps), 0.0, 50.0);
      FGustFrequencyHz := EnsureRange(RootObj.Get('gustFreq', FGustFrequencyHz), 0.05, 10.0);
      FTrunkStiffness := EnsureRange(RootObj.Get('stiffness', FTrunkStiffness), 1.0, 200.0);
      FBranchFlexibility := EnsureRange(RootObj.Get('branchFlex', FBranchFlexibility), 0.1, 8.0);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TWindBeaufortPreset))) and
         (PresetOrd <= Ord(High(TWindBeaufortPreset))) then
        FPreset := TWindBeaufortPreset(PresetOrd);
      RebuildWindGrovePreviewMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleWindFieldDirector.WindSummaryBadge: String;
begin
  Result := Format('[Wind:%.1fm/s Az=%.0fdeg Waves=%d]', [
    FBaseWindSpeedMps + FGustAmplitudeMps * 0.5,
    FWindAzimuthDeg,
    ActiveShockwaveCount]);
end;

initialization
  RegisterSerializableComponent(TCastleWindFieldDirector, ['Environment & Weather', 'Wind Gust Field & Shockwave Director']);
end.
