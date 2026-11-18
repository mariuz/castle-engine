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

{ Smart Camera Collision Occluder Cutaway / Dither Fade & Radial Character
  Foliage Parting component (Phase 362 — UE 6.0+ Camera Occluder & Foliage
  Interaction Parity). }
unit CastleOccluderFader;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

const
  { Assign Tag := OccluderIgnoreTag on floors or player avatars that should never cutaway. }
  OccluderIgnoreTag = 8801;

type
  { Camera cutaway & foliage interaction presets. }
  TOccluderFadePreset = (
    ofpCustom,
    ofpIsometricArpgRoofCutaway,
    ofpThirdPersonWallCorridorFade,
    ofpStealthTallGrassParting
  );

  { Live per-transform cutaway fade state. }
  TOccluderTrackedEntry = record
    TransformName: String;
    CurrentOpacity: Single;
    TargetOpacity: Single;
    CurrentlyBlockingRay: Boolean;
  end;

  { Camera-to-target WorldRay occluder cutaway fader and length-preserving
    character-proximity foliage parting controller. }
  TCastleCameraOccluderFader = class(TCastleTransform)
  private
    FPreset: TOccluderFadePreset;
    FCutawayMinOpacity: Single;
    FFadeInSpeed: Single;
    FRestoreOpacitySpeed: Single;
    FCorridorProbeRadius: Single;
    FFoliagePartingRadius: Single;
    FFoliageMaxBendDegrees: Single;
    FShowPartedGrassPreview: Boolean;
    FTracked: array of TOccluderTrackedEntry;
    FActiveFadedCount: Integer;
    FPartedBladeCount: Integer;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TOccluderFadePreset);
    procedure SetCutawayMinOpacity(const AValue: Single);
    procedure SetFadeInSpeed(const AValue: Single);
    procedure SetRestoreOpacitySpeed(const AValue: Single);
    procedure SetCorridorProbeRadius(const AValue: Single);
    procedure SetFoliagePartingRadius(const AValue: Single);
    procedure SetFoliageMaxBendDegrees(const AValue: Single);
    procedure SetShowPartedGrassPreview(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParams(const APreset: TOccluderFadePreset);
    function FindOrAddTrackedIndex(const AName: String): Integer;
    class procedure ApplyOpacityToTransform(const T: TCastleTransform; const AOpacity: Single);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ResetAllFadedOccluders(const RootWorld: TCastleTransform);
    function TrackedCount: Integer;
    function GetTrackedEntry(const AIndex: Integer): TOccluderTrackedEntry;
    function GetTrackedOpacity(const ATransformName: String): Single;
    function EvaluateBladePartingTip(const BladeRootWorld: TVector3;
      const BladeHeight: Single; const InteractorPositions: array of TVector3;
      out OutBendAngleDeg: Single): TVector3;
    procedure RebuildFoliagePreviewMesh(const InteractorPositions: array of TVector3);
    function StepOccluderAndFoliage(const RootWorld: TCastleTransform;
      const CameraWorldPos, TargetFocusWorldPos: TVector3;
      const InteractorPositions: array of TVector3;
      const Dt: Single): Integer;
    function OccluderSummaryBadge: String;
    property ActiveFadedCount: Integer read FActiveFadedCount;
    property PartedBladeCount: Integer read FPartedBladeCount;
  published
    property Preset: TOccluderFadePreset read FPreset write SetPreset default ofpIsometricArpgRoofCutaway;
    property CutawayMinOpacity: Single read FCutawayMinOpacity write SetCutawayMinOpacity {$ifdef FPC}default 0.18{$endif};
    property FadeInSpeed: Single read FFadeInSpeed write SetFadeInSpeed {$ifdef FPC}default 9.0{$endif};
    property RestoreOpacitySpeed: Single read FRestoreOpacitySpeed write SetRestoreOpacitySpeed {$ifdef FPC}default 6.0{$endif};
    property CorridorProbeRadius: Single read FCorridorProbeRadius write SetCorridorProbeRadius {$ifdef FPC}default 0.40{$endif};
    property FoliagePartingRadius: Single read FFoliagePartingRadius write SetFoliagePartingRadius {$ifdef FPC}default 1.85{$endif};
    property FoliageMaxBendDegrees: Single read FFoliageMaxBendDegrees write SetFoliageMaxBendDegrees {$ifdef FPC}default 52.0{$endif};
    property ShowPartedGrassPreview: Boolean read FShowPartedGrassPreview write SetShowPartedGrassPreview default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function OccluderPresetToString(const APreset: TOccluderFadePreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function OccluderPresetToString(const APreset: TOccluderFadePreset): String;
begin
  case APreset of
    ofpCustom: Result := 'Custom Cutaway & Foliage Parting';
    ofpIsometricArpgRoofCutaway: Result := 'Isometric ARPG Roof & Wall Cutaway (18% Alpha)';
    ofpThirdPersonWallCorridorFade: Result := 'Third-Person Tight Corridor Pillar Dither (28% Alpha)';
    ofpStealthTallGrassParting: Result := 'Stealth Tall-Grass Meadow Parting (2.6m Halo)';
  end;
end;

{ TCastleCameraOccluderFader -------------------------------------------------- }

constructor TCastleCameraOccluderFader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPartedGrassPreview := True;
  ApplyPresetParams(ofpIsometricArpgRoofCutaway);
  RebuildFoliagePreviewMesh([]);
end;

destructor TCastleCameraOccluderFader.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleCameraOccluderFader.ApplyPresetParams(const APreset: TOccluderFadePreset);
begin
  FPreset := APreset;
  case APreset of
    ofpIsometricArpgRoofCutaway, ofpCustom:
      begin
        FCutawayMinOpacity := 0.18;
        FFadeInSpeed := 9.0;
        FRestoreOpacitySpeed := 6.0;
        FCorridorProbeRadius := 0.40;
        FFoliagePartingRadius := 1.85;
        FFoliageMaxBendDegrees := 52.0;
      end;
    ofpThirdPersonWallCorridorFade:
      begin
        FCutawayMinOpacity := 0.28;
        FFadeInSpeed := 12.0;
        FRestoreOpacitySpeed := 7.5;
        FCorridorProbeRadius := 0.65;
        FFoliagePartingRadius := 1.40;
        FFoliageMaxBendDegrees := 40.0;
      end;
    ofpStealthTallGrassParting:
      begin
        FCutawayMinOpacity := 0.15;
        FFadeInSpeed := 8.0;
        FRestoreOpacitySpeed := 5.0;
        FCorridorProbeRadius := 0.35;
        FFoliagePartingRadius := 2.60;
        FFoliageMaxBendDegrees := 64.0;
      end;
  end;
end;

procedure TCastleCameraOccluderFader.SetPreset(const AValue: TOccluderFadePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> ofpCustom then
  begin
    ApplyPresetParams(AValue);
    RebuildFoliagePreviewMesh([]);
  end;
end;

procedure TCastleCameraOccluderFader.SetCutawayMinOpacity(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.02, 0.95);
  if SameValue(FCutawayMinOpacity, V, 1e-4) then Exit;
  FCutawayMinOpacity := V;
  FPreset := ofpCustom;
end;

procedure TCastleCameraOccluderFader.SetFadeInSpeed(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.5, 60.0);
  if SameValue(FFadeInSpeed, V, 1e-4) then Exit;
  FFadeInSpeed := V;
  FPreset := ofpCustom;
end;

procedure TCastleCameraOccluderFader.SetRestoreOpacitySpeed(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.5, 60.0);
  if SameValue(FRestoreOpacitySpeed, V, 1e-4) then Exit;
  FRestoreOpacitySpeed := V;
  FPreset := ofpCustom;
end;

procedure TCastleCameraOccluderFader.SetCorridorProbeRadius(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 3.0);
  if SameValue(FCorridorProbeRadius, V, 1e-4) then Exit;
  FCorridorProbeRadius := V;
  FPreset := ofpCustom;
end;

procedure TCastleCameraOccluderFader.SetFoliagePartingRadius(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.25, 10.0);
  if SameValue(FFoliagePartingRadius, V, 1e-4) then Exit;
  FFoliagePartingRadius := V;
  FPreset := ofpCustom;
  RebuildFoliagePreviewMesh([]);
end;

procedure TCastleCameraOccluderFader.SetFoliageMaxBendDegrees(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 5.0, 82.0);
  if SameValue(FFoliageMaxBendDegrees, V, 1e-4) then Exit;
  FFoliageMaxBendDegrees := V;
  FPreset := ofpCustom;
  RebuildFoliagePreviewMesh([]);
end;

procedure TCastleCameraOccluderFader.SetShowPartedGrassPreview(const AValue: Boolean);
begin
  if FShowPartedGrassPreview = AValue then Exit;
  FShowPartedGrassPreview := AValue;
  if not FShowPartedGrassPreview then
    ClearTransientScene
  else
    RebuildFoliagePreviewMesh([]);
end;

function TCastleCameraOccluderFader.FindOrAddTrackedIndex(const AName: String): Integer;
var
  I, N: Integer;
begin
  for I := 0 to High(FTracked) do
    if SameText(FTracked[I].TransformName, AName) then
      Exit(I);
  N := Length(FTracked);
  SetLength(FTracked, N + 1);
  FTracked[N].TransformName := AName;
  FTracked[N].CurrentOpacity := 1.0;
  FTracked[N].TargetOpacity := 1.0;
  FTracked[N].CurrentlyBlockingRay := False;
  Result := N;
end;

class procedure TCastleCameraOccluderFader.ApplyOpacityToTransform(
  const T: TCastleTransform; const AOpacity: Single);
var
  ClampedA: Single;
begin
  if T = nil then Exit;
  ClampedA := EnsureRange(AOpacity, 0.02, 1.0);
  if T is TCastleBox then
    TCastleBox(T).Color := Vector4(TCastleBox(T).Color.XYZ, ClampedA)
  else if T is TCastleSphere then
    TCastleSphere(T).Color := Vector4(TCastleSphere(T).Color.XYZ, ClampedA);
end;

procedure TCastleCameraOccluderFader.ResetAllFadedOccluders(const RootWorld: TCastleTransform);

  function FindNamedTransform(const ParentT: TCastleTransform; const AName: String): TCastleTransform;
  var
    J: Integer;
  begin
    Result := nil;
    if ParentT = nil then Exit;
    if SameText(ParentT.Name, AName) then Exit(ParentT);
    for J := 0 to ParentT.Count - 1 do
    begin
      Result := FindNamedTransform(ParentT[J], AName);
      if Result <> nil then Exit;
    end;
  end;

var
  I: Integer;
  T: TCastleTransform;
begin
  if RootWorld <> nil then
    for I := 0 to High(FTracked) do
    begin
      T := FindNamedTransform(RootWorld, FTracked[I].TransformName);
      ApplyOpacityToTransform(T, 1.0);
    end;
  SetLength(FTracked, 0);
  FActiveFadedCount := 0;
end;

function TCastleCameraOccluderFader.TrackedCount: Integer;
begin
  Result := Length(FTracked);
end;

function TCastleCameraOccluderFader.GetTrackedEntry(const AIndex: Integer): TOccluderTrackedEntry;
begin
  if (AIndex >= 0) and (AIndex < Length(FTracked)) then
    Result := FTracked[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleCameraOccluderFader.GetTrackedOpacity(const ATransformName: String): Single;
var
  I: Integer;
begin
  for I := 0 to High(FTracked) do
    if SameText(FTracked[I].TransformName, ATransformName) then
      Exit(FTracked[I].CurrentOpacity);
  Result := 1.0;
end;

function TCastleCameraOccluderFader.EvaluateBladePartingTip(
  const BladeRootWorld: TVector3; const BladeHeight: Single;
  const InteractorPositions: array of TVector3;
  out OutBendAngleDeg: Single): TVector3;
var
  I: Integer;
  DeltaXZ, PushDir, AccumPush: TVector3;
  DistXZ, Weight, BendStrength, RadAngle, EffHeight: Single;
begin
  EffHeight := Max(0.05, BladeHeight);
  AccumPush := TVector3.Zero;
  for I := 0 to High(InteractorPositions) do
  begin
    DeltaXZ := Vector3(
      BladeRootWorld.X - InteractorPositions[I].X,
      0.0,
      BladeRootWorld.Z - InteractorPositions[I].Z);
    DistXZ := DeltaXZ.Length;
    if DistXZ < FFoliagePartingRadius then
    begin
      Weight := Sqr(1.0 - (DistXZ / Max(0.1, FFoliagePartingRadius)));
      if DistXZ > 1e-4 then
        PushDir := DeltaXZ / DistXZ
      else
        PushDir := Vector3(1.0, 0.0, 0.0);
      AccumPush := AccumPush + PushDir * Weight;
    end;
  end;

  BendStrength := EnsureRange(AccumPush.Length, 0.0, 1.0);
  OutBendAngleDeg := BendStrength * FFoliageMaxBendDegrees;
  if AccumPush.LengthSqr > 1e-8 then
    PushDir := AccumPush.Normalize
  else
    PushDir := Vector3(1.0, 0.0, 0.0);

  RadAngle := DegToRad(OutBendAngleDeg);
  { Exact length-preserving rigid rod rotation: Sin^2 + Cos^2 = 1 -> |Tip - Root| = EffHeight }
  Result := BladeRootWorld +
    PushDir * (EffHeight * Sin(RadAngle)) +
    Vector3(0.0, EffHeight * Cos(RadAngle), 0.0);
end;

procedure TCastleCameraOccluderFader.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientFoliagePartingMesh';
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

procedure TCastleCameraOccluderFader.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleCameraOccluderFader.RebuildFoliagePreviewMesh(
  const InteractorPositions: array of TVector3);
const
  GridHalf = 4;
  BladeSpacing = 0.70;
  BladeHeight = 1.25;
var
  Verts, Cols: TVector3List;
  GX, GZ, PartedCnt: Integer;
  RootLoc, RootW, TipW, TipLoc, HalfBase: TVector3;
  BendDeg, BendRatio: Single;
  BaseCol, TipCol: TVector3;
begin
  PartedCnt := 0;
  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for GZ := -GridHalf to GridHalf do
      for GX := -GridHalf to GridHalf do
      begin
        RootLoc := Vector3(GX * BladeSpacing, 0.0, GZ * BladeSpacing);
        if Parent <> nil then
          RootW := LocalToWorld(RootLoc)
        else
          RootW := Translation + RootLoc;

        TipW := EvaluateBladePartingTip(RootW, BladeHeight, InteractorPositions, BendDeg);
        if BendDeg > 2.0 then
          Inc(PartedCnt);

        if Parent <> nil then
          TipLoc := WorldToLocal(TipW)
        else
          TipLoc := TipW - Translation;

        BendRatio := EnsureRange(BendDeg / Max(1.0, FFoliageMaxBendDegrees), 0.0, 1.0);
        BaseCol := Vector3(0.10, 0.36, 0.14);
        TipCol := Lerp(BendRatio, Vector3(0.28, 0.74, 0.26), Vector3(0.86, 0.92, 0.34));
        HalfBase := Vector3(0.06, 0.0, 0.0);

        Verts.Add(RootLoc - HalfBase);
        Verts.Add(RootLoc + HalfBase);
        Verts.Add(TipLoc);
        Cols.Add(BaseCol);
        Cols.Add(BaseCol);
        Cols.Add(TipCol);
      end;

    FPartedBladeCount := PartedCnt;
    if FShowPartedGrassPreview then
    begin
      EnsureTransientScene;
      FCoordNode.SetPoint(Verts);
      FCoordNode.FdPoint.Changed;
      FColorNode.SetColor(Cols);
      FColorNode.FdColor.Changed;
    end;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleCameraOccluderFader.StepOccluderAndFoliage(
  const RootWorld: TCastleTransform;
  const CameraWorldPos, TargetFocusWorldPos: TVector3;
  const InteractorPositions: array of TVector3;
  const Dt: Single): Integer;

  function FindNamedTransform(const ParentT: TCastleTransform; const AName: String): TCastleTransform;
  var
    J: Integer;
  begin
    Result := nil;
    if ParentT = nil then Exit;
    if SameText(ParentT.Name, AName) then Exit(ParentT);
    for J := 0 to ParentT.Count - 1 do
    begin
      Result := FindNamedTransform(ParentT[J], AName);
      if Result <> nil then Exit;
    end;
  end;

  function ResolveTopOccluder(const RayHit: TRayCollision; const MaxAllowedDist: Single): TCastleTransform;
  var
    K: Integer;
    Cand: TCastleTransform;
  begin
    Result := nil;
    if (RayHit = nil) or (RayHit.Distance > MaxAllowedDist) then Exit;
    for K := 0 to RayHit.Count - 1 do
    begin
      Cand := RayHit[K].Item;
      if (Cand = nil) or (Cand = RootWorld) or (Cand = Self) then Continue;
      if csTransient in Cand.ComponentStyle then Continue;
      if Cand.Tag = OccluderIgnoreTag then Continue;
      if Trim(Cand.Name) = '' then Continue;
      Result := Cand;
      Exit;
    end;
  end;

var
  ActualRoot: TCastleAbstractRootTransform;
  SegVec, RayDir, RightAxis, UpAxis, RayStart, RayEnd, OffsetVec: TVector3;
  SegLen, RemainingDist, StepDist, Alpha: Single;
  RayIdx, Hop, I, TIdx, WriteIdx: Integer;
  RayHit: TRayCollision;
  HitT: TCastleTransform;
begin
  Result := 0;
  for I := 0 to High(FTracked) do
    FTracked[I].CurrentlyBlockingRay := False;

  ActualRoot := nil;
  if RootWorld is TCastleAbstractRootTransform then
    ActualRoot := TCastleAbstractRootTransform(RootWorld)
  else if RootWorld <> nil then
    ActualRoot := RootWorld.World;

  if (ActualRoot <> nil) and (Dt > 0.0) then
  begin
    SegVec := TargetFocusWorldPos - CameraWorldPos;
    SegLen := SegVec.Length;
    if SegLen > 0.60 then
    begin
      RayDir := SegVec / SegLen;
      if Abs(RayDir.Y) < 0.92 then
        RightAxis := TVector3.CrossProduct(RayDir, Vector3(0, 1, 0)).Normalize
      else
        RightAxis := TVector3.CrossProduct(RayDir, Vector3(1, 0, 0)).Normalize;
      UpAxis := TVector3.CrossProduct(RightAxis, RayDir).Normalize;

      for RayIdx := 0 to 4 do
      begin
        case RayIdx of
          0: OffsetVec := TVector3.Zero;
          1: OffsetVec := RightAxis * FCorridorProbeRadius;
          2: OffsetVec := -RightAxis * FCorridorProbeRadius;
          3: OffsetVec := UpAxis * FCorridorProbeRadius;
          else OffsetVec := -UpAxis * FCorridorProbeRadius;
        end;
        RayStart := CameraWorldPos + OffsetVec;
        RayEnd := TargetFocusWorldPos + OffsetVec;
        RemainingDist := (RayEnd - RayStart).Length - 0.45;

        for Hop := 1 to 6 do
        begin
          if RemainingDist <= 0.15 then Break;
          RayHit := ActualRoot.WorldRay(RayStart, RayDir);
          try
            HitT := ResolveTopOccluder(RayHit, RemainingDist);
            if HitT <> nil then
            begin
              TIdx := FindOrAddTrackedIndex(HitT.Name);
              FTracked[TIdx].CurrentlyBlockingRay := True;
              FTracked[TIdx].TargetOpacity := FCutawayMinOpacity;
              StepDist := Max(0.35, RayHit.Distance + 0.35);
              RayStart := RayStart + RayDir * StepDist;
              RemainingDist := RemainingDist - StepDist;
            end else
              Break;
          finally
            FreeAndNil(RayHit);
          end;
        end;
      end;
    end;

    WriteIdx := 0;
    for I := 0 to High(FTracked) do
    begin
      if FTracked[I].CurrentlyBlockingRay then
      begin
        FTracked[I].TargetOpacity := FCutawayMinOpacity;
        Alpha := 1.0 - Exp(-FFadeInSpeed * Dt);
      end else
      begin
        FTracked[I].TargetOpacity := 1.0;
        Alpha := 1.0 - Exp(-FRestoreOpacitySpeed * Dt);
      end;
      FTracked[I].CurrentOpacity := Lerp(Alpha, FTracked[I].CurrentOpacity, FTracked[I].TargetOpacity);
      HitT := FindNamedTransform(RootWorld, FTracked[I].TransformName);
      if (not FTracked[I].CurrentlyBlockingRay) and (FTracked[I].CurrentOpacity >= 0.995) then
      begin
        ApplyOpacityToTransform(HitT, 1.0);
      end else
      begin
        ApplyOpacityToTransform(HitT, FTracked[I].CurrentOpacity);
        if FTracked[I].CurrentOpacity < 0.95 then
          Inc(Result);
        FTracked[WriteIdx] := FTracked[I];
        Inc(WriteIdx);
      end;
    end;
    SetLength(FTracked, WriteIdx);
  end;

  FActiveFadedCount := Result;
  RebuildFoliagePreviewMesh(InteractorPositions);
end;

function TCastleCameraOccluderFader.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('minOpacity', FCutawayMinOpacity);
    RootObj.Add('fadeSpeed', FFadeInSpeed);
    RootObj.Add('restoreSpeed', FRestoreOpacitySpeed);
    RootObj.Add('corridorRadius', FCorridorProbeRadius);
    RootObj.Add('partRadius', FFoliagePartingRadius);
    RootObj.Add('maxBendDeg', FFoliageMaxBendDegrees);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleCameraOccluderFader.SetConfigJson(const AValue: String);
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
      FCutawayMinOpacity := EnsureRange(RootObj.Get('minOpacity', FCutawayMinOpacity), 0.02, 0.95);
      FFadeInSpeed := EnsureRange(RootObj.Get('fadeSpeed', FFadeInSpeed), 0.5, 60.0);
      FRestoreOpacitySpeed := EnsureRange(RootObj.Get('restoreSpeed', FRestoreOpacitySpeed), 0.5, 60.0);
      FCorridorProbeRadius := EnsureRange(RootObj.Get('corridorRadius', FCorridorProbeRadius), 0.0, 3.0);
      FFoliagePartingRadius := EnsureRange(RootObj.Get('partRadius', FFoliagePartingRadius), 0.25, 10.0);
      FFoliageMaxBendDegrees := EnsureRange(RootObj.Get('maxBendDeg', FFoliageMaxBendDegrees), 5.0, 82.0);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TOccluderFadePreset))) and
         (PresetOrd <= Ord(High(TOccluderFadePreset))) then
        FPreset := TOccluderFadePreset(PresetOrd);
      RebuildFoliagePreviewMesh([]);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleCameraOccluderFader.OccluderSummaryBadge: String;
begin
  Result := Format('[Cutaway:%d faded Min=%.0f%% GrassR=%.1fm]', [
    FActiveFadedCount,
    FCutawayMinOpacity * 100.0,
    FFoliagePartingRadius]);
end;

initialization
  RegisterSerializableComponent(TCastleCameraOccluderFader, ['Camera & Cinematics', 'Camera Occluder Cutaway & Foliage Parting']);
end.
