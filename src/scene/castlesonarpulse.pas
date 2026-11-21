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

{ 3D active sonar & echolocation pulse solver with finite-speed spherical
  wavefront expansion, WorldRay occlusion, two-way roundtrip echo arrival
  gating (t >= 2*d/c), steel vs. anechoic stealth reflectivity, phosphor
  persistence, and exact monostatic Doppler shift (Phase 414). }
unit CastleSonarPulse;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset acoustic & tactical motion-tracker propagation modes. }
  TSonarPulsePreset = (
    sppSubmarineHydrophone1500,
    sppBatCaveBiosonar343,
    sppSciFiMotionTrackerPulse
  );

  { Tracked sonar echo contact with roundtrip arrival & Doppler telemetry. }
  TSonarEchoContact = record
    TargetName: String;
    WorldHitPos: TVector3;
    RangeMeters: Single;
    Reflectivity01: Single;
    TwoWayArrivalTimeSec: Single;
    DopplerShiftHz: Single;
    EchoArrived: Boolean;
    PhosphorBrightness01: Single;
  end;

  { 3D active sonar & echolocation pulse emitter component. }
  TCastleSonarPulse = class(TCastleTransform)
  private
    FPreset: TSonarPulsePreset;
    FPropagationSpeedMps: Single;
    FCarrierFrequencyHz: Single;
    FMaxRangeMeters: Single;
    FPhosphorFadeSec: Single;
    FAzimuthRayCount: Integer;
    FShowPreview: Boolean;
    FPingActive: Boolean;
    FElapsedPingSec: Single;
    FWavefrontRadiusMeters: Single;
    FContacts: array of TSonarEchoContact;
    FRevealedContactCount: Integer;
    FPreviewRoot: TCastleTransform;
    FPreviewRingScene: TCastleScene;
    procedure SetPreset(const AValue: TSonarPulsePreset);
    procedure SetAzimuthRayCount(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
    procedure UpdateContactArrivals;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TSonarPulsePreset);

    { Exact monostatic two-way active sonar Doppler shift [Hz]:
      f_rx - f0 = f0 * ((c + v_closing) / (c - v_closing) - 1). }
    class function ComputeTwoWayDopplerShiftHz(
      const ACarrierHz, ASoundSpeedMps: Single;
      const AEmitterWorld, ATargetWorld, ATargetVelocityMps: TVector3): Single;

    { Emit a 360-deg WorldRay sonar ping from world origin and schedule two-way
      roundtrip echo arrival times t = 2 * d / c. }
    function EmitSonarPing(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;

    { Register a dynamic moving contact (e.g. torpedo / creature) subject to
      WorldRay line-of-sight check, material reflectivity, and Doppler shift. }
    function ProbeDynamicContact(
      const AWorldRoot: TCastleAbstractRootTransform;
      const AName: String; const ATargetWorld, ATargetVelocityMps: TVector3;
      const AMaterialReflectivity01: Single = 0.90): Boolean;

    { Advance ping wavefront R(t) = c * t, reveal echoes once t >= 2*d/c, and
      decay phosphor brightness over PhosphorFadeSec. }
    procedure StepPulsePropagation(const ADtSec: Single);

    function ContactCount: Integer;
    function GetContact(const AIndex: Integer): TSonarEchoContact;

    procedure RebuildPreview;
    procedure ClearPreview;
    function SonarSummaryBadge: String;

    property PingActive: Boolean read FPingActive;
    property ElapsedPingSec: Single read FElapsedPingSec;
    property WavefrontRadiusMeters: Single read FWavefrontRadiusMeters;
    property RevealedContactCount: Integer read FRevealedContactCount;
  published
    property Preset: TSonarPulsePreset
      read FPreset write SetPreset default sppSciFiMotionTrackerPulse;
    property PropagationSpeedMps: Single
      read FPropagationSpeedMps write FPropagationSpeedMps;
    property CarrierFrequencyHz: Single
      read FCarrierFrequencyHz write FCarrierFrequencyHz;
    property MaxRangeMeters: Single
      read FMaxRangeMeters write FMaxRangeMeters;
    property PhosphorFadeSec: Single
      read FPhosphorFadeSec write FPhosphorFadeSec;
    property AzimuthRayCount: Integer
      read FAzimuthRayCount write SetAzimuthRayCount default 24;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function SonarPulsePresetToString(const APreset: TSonarPulsePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function SonarPulsePresetToString(const APreset: TSonarPulsePreset): String;
begin
  case APreset of
    sppSubmarineHydrophone1500: Result := 'SubmarineHydrophone1500';
    sppBatCaveBiosonar343:      Result := 'BatCaveBiosonar343';
    sppSciFiMotionTrackerPulse: Result := 'SciFiMotionTrackerPulse';
  end;
end;

function ClassifyAcousticReflectivity(const ACompName: String): Single;
begin
  if (Pos('Anechoic', ACompName) > 0) or (Pos('Stealth', ACompName) > 0) then
    Result := 0.08
  else if (Pos('Steel', ACompName) > 0) or (Pos('Submarine', ACompName) > 0) or
          (Pos('Hull', ACompName) > 0) then
    Result := 0.95
  else
    Result := 0.58;
end;

class function TCastleSonarPulse.ComputeTwoWayDopplerShiftHz(
  const ACarrierHz, ASoundSpeedMps: Single;
  const AEmitterWorld, ATargetWorld, ATargetVelocityMps: TVector3): Single;
var
  OutVec, OutUnit: TVector3;
  Dist, C, VClosing: Single;
begin
  OutVec := ATargetWorld - AEmitterWorld;
  Dist := OutVec.Length;
  C := Max(10.0, ASoundSpeedMps);
  if (Dist <= 1e-4) or (ACarrierHz <= 0.0) then
    Exit(0.0);

  OutUnit := OutVec / Dist;
  { Positive VClosing when target moves TOWARD emitter (-OutUnit) }
  VClosing := Clamped(-TVector3.DotProduct(ATargetVelocityMps, OutUnit),
    -0.85 * C, 0.85 * C);
  Result := ACarrierHz * (((C + VClosing) / (C - VClosing)) - 1.0);
end;

constructor TCastleSonarPulse.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FAzimuthRayCount := 24;
  FPingActive := False;
  FElapsedPingSec := 0.0;
  FWavefrontRadiusMeters := 0.0;
  FRevealedContactCount := 0;
  ApplyPreset(sppSciFiMotionTrackerPulse);
end;

destructor TCastleSonarPulse.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleSonarPulse.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'PropagationSpeedMps', 'CarrierFrequencyHz',
       'MaxRangeMeters', 'PhosphorFadeSec', 'AzimuthRayCount', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSonarPulse.SetPreset(const AValue: TSonarPulsePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleSonarPulse.SetAzimuthRayCount(const AValue: Integer);
begin
  FAzimuthRayCount := Clamped(AValue, 4, 128);
end;

procedure TCastleSonarPulse.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleSonarPulse.ApplyPreset(const APreset: TSonarPulsePreset);
begin
  FPreset := APreset;
  case APreset of
    sppSubmarineHydrophone1500:
      begin
        FPropagationSpeedMps := 1500.0;
        FCarrierFrequencyHz := 3500.0;
        FMaxRangeMeters := 600.0;
        FPhosphorFadeSec := 4.0;
      end;
    sppBatCaveBiosonar343:
      begin
        FPropagationSpeedMps := 343.0;
        FCarrierFrequencyHz := 45000.0;
        FMaxRangeMeters := 60.0;
        FPhosphorFadeSec := 1.2;
      end;
    sppSciFiMotionTrackerPulse:
      begin
        FPropagationSpeedMps := 40.0;
        FCarrierFrequencyHz := 2400.0;
        FMaxRangeMeters := 80.0;
        FPhosphorFadeSec := 2.5;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleSonarPulse.UpdateContactArrivals;
var
  I, Rev: Integer;
  DtAfterArrival, FadeDur, DistAtten: Single;
begin
  Rev := 0;
  FadeDur := Max(0.1, FPhosphorFadeSec);
  for I := 0 to High(FContacts) do
  begin
    if FElapsedPingSec >= FContacts[I].TwoWayArrivalTimeSec then
    begin
      FContacts[I].EchoArrived := True;
      DtAfterArrival := FElapsedPingSec - FContacts[I].TwoWayArrivalTimeSec;
      DistAtten := 1.0 / (1.0 + 0.002 * Sqr(FContacts[I].RangeMeters));
      FContacts[I].PhosphorBrightness01 :=
        Clamped(FContacts[I].Reflectivity01 * DistAtten *
          (1.0 - (DtAfterArrival / FadeDur)), 0.0, 1.0);
      if FContacts[I].PhosphorBrightness01 > 0.01 then
        Inc(Rev);
    end else
    begin
      FContacts[I].EchoArrived := False;
      FContacts[I].PhosphorBrightness01 := 0.0;
    end;
  end;
  FRevealedContactCount := Rev;
end;

function TCastleSonarPulse.EmitSonarPing(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;
var
  ActiveRoot: TCastleAbstractRootTransform;
  WT: TMatrix4;
  Orig, Dir: TVector3;
  I, K, N: Integer;
  Ang, MaxR, CSpeed, BestDist, D: Single;
  RH: TRayCollision;
  BestNode: TRayCollisionNode;
  HitItem: TCastleTransform;
  Found: Boolean;
begin
  SetLength(FContacts, 0);
  FPingActive := True;
  FElapsedPingSec := 0.0;
  FWavefrontRadiusMeters := 0.5;
  FRevealedContactCount := 0;

  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;
  if ActiveRoot = nil then
  begin
    if FShowPreview then RebuildPreview;
    Exit(0);
  end;

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  Orig := WT.MultPoint(TVector3.Zero);
  MaxR := Max(1.0, FMaxRangeMeters);
  CSpeed := Max(1.0, FPropagationSpeedMps);

  for I := 0 to Clamped(FAzimuthRayCount, 4, 128) - 1 do
  begin
    Ang := 2.0 * Pi * I / Clamped(FAzimuthRayCount, 4, 128);
    Dir := Vector3(Sin(Ang), 0.0, -Cos(Ang));
    Found := False;
    BestDist := MaxR + 1.0;
    BestNode := Default(TRayCollisionNode);

    RH := ActiveRoot.WorldRay(Orig, Dir);
    try
      if RH <> nil then
        for K := 0 to RH.Count - 1 do
        begin
          HitItem := RH[K].Item;
          if (HitItem = nil) or (HitItem = ActiveRoot) or (HitItem = Self) then
            Continue;
          if csTransient in HitItem.ComponentStyle then Continue;
          D := PointsDistance(Orig, RH[K].Point);
          if (D >= 0.25) and (D <= MaxR) and (D < BestDist) then
          begin
            BestDist := D;
            BestNode := RH[K];
            Found := True;
          end;
        end;
    finally
      FreeAndNil(RH);
    end;

    if Found then
    begin
      N := Length(FContacts);
      SetLength(FContacts, N + 1);
      FContacts[N] := Default(TSonarEchoContact);
      FContacts[N].TargetName := BestNode.Item.Name;
      FContacts[N].WorldHitPos := BestNode.Point;
      FContacts[N].RangeMeters := BestDist;
      FContacts[N].Reflectivity01 := ClassifyAcousticReflectivity(BestNode.Item.Name);
      FContacts[N].TwoWayArrivalTimeSec := (2.0 * BestDist) / CSpeed;
    end;
  end;

  UpdateContactArrivals;
  if FShowPreview then
    RebuildPreview;
  Result := Length(FContacts);
end;

function TCastleSonarPulse.ProbeDynamicContact(
  const AWorldRoot: TCastleAbstractRootTransform;
  const AName: String; const ATargetWorld, ATargetVelocityMps: TVector3;
  const AMaterialReflectivity01: Single): Boolean;
var
  ActiveRoot: TCastleAbstractRootTransform;
  WT: TMatrix4;
  Orig, SegVec, Dir: TVector3;
  Dist, HitDist, CSpeed: Single;
  RH: TRayCollision;
  K, N: Integer;
  HitItem: TCastleTransform;
begin
  Result := False;
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  Orig := WT.MultPoint(TVector3.Zero);
  SegVec := ATargetWorld - Orig;
  Dist := SegVec.Length;
  if (Dist <= 0.1) or (Dist > Max(1.0, FMaxRangeMeters)) then Exit;

  if ActiveRoot <> nil then
  begin
    Dir := SegVec / Dist;
    RH := ActiveRoot.WorldRay(Orig, Dir);
    try
      if RH <> nil then
        for K := 0 to RH.Count - 1 do
        begin
          HitItem := RH[K].Item;
          if (HitItem = nil) or (HitItem = ActiveRoot) or (HitItem = Self) then
            Continue;
          if csTransient in HitItem.ComponentStyle then Continue;
          if SameText(HitItem.Name, AName) then Continue;
          HitDist := PointsDistance(Orig, RH[K].Point);
          if (HitDist > 0.1) and (HitDist < Dist - 0.15) then
            Exit(False);
        end;
    finally
      FreeAndNil(RH);
    end;
  end;

  CSpeed := Max(1.0, FPropagationSpeedMps);
  N := Length(FContacts);
  SetLength(FContacts, N + 1);
  FContacts[N] := Default(TSonarEchoContact);
  FContacts[N].TargetName := AName;
  FContacts[N].WorldHitPos := ATargetWorld;
  FContacts[N].RangeMeters := Dist;
  FContacts[N].Reflectivity01 := Clamped(AMaterialReflectivity01, 0.02, 1.0);
  FContacts[N].TwoWayArrivalTimeSec := (2.0 * Dist) / CSpeed;
  FContacts[N].DopplerShiftHz := ComputeTwoWayDopplerShiftHz(
    FCarrierFrequencyHz, CSpeed, Orig, ATargetWorld, ATargetVelocityMps);
  UpdateContactArrivals;
  Result := True;
end;

procedure TCastleSonarPulse.StepPulsePropagation(const ADtSec: Single);
begin
  if (not FPingActive) or (ADtSec <= 0.0) then Exit;
  FElapsedPingSec := FElapsedPingSec + ADtSec;
  FWavefrontRadiusMeters := Min(Max(1.0, FMaxRangeMeters),
    FElapsedPingSec * Max(1.0, FPropagationSpeedMps));
  UpdateContactArrivals;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleSonarPulse.ContactCount: Integer;
begin
  Result := Length(FContacts);
end;

function TCastleSonarPulse.GetContact(const AIndex: Integer): TSonarEchoContact;
begin
  if (AIndex >= 0) and (AIndex < Length(FContacts)) then
    Result := FContacts[AIndex]
  else
    Result := Default(TSonarEchoContact);
end;

procedure TCastleSonarPulse.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewRingScene := nil;
  end;
end;

procedure TCastleSonarPulse.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  Pts: array[0..24] of TVector3;
  I: Integer;
  R, Ang: Single;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  R := Max(0.6, Min(25.0, FWavefrontRadiusMeters));
  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'SonarPulsePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewRingScene := TCastleScene.Create(FPreviewRoot);
  FPreviewRingScene.SetTransient;
  FPreviewRingScene.Name := 'SonarPulsePreviewWavefront';
  FPreviewRingScene.Pickable := False;
  FPreviewRingScene.Collides := False;
  FPreviewRoot.Add(FPreviewRingScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.20, 0.98, 0.72);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  for I := 0 to 24 do
  begin
    Ang := 2.0 * Pi * I / 24.0;
    Pts[I] := Vector3(Cos(Ang) * R, 0.1, Sin(Ang) * R);
  end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([25]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewRingScene.Load(RootNode, True);
end;

function TCastleSonarPulse.SonarSummaryBadge: String;
begin
  Result := FormatDot('[Sonar:R=%.1fm Echoes=%d/%d]', [
    FWavefrontRadiusMeters, FRevealedContactCount, Length(FContacts)]);
end;

initialization
  RegisterSerializableComponent(TCastleSonarPulse, 'Active Sonar & Echolocation');

end.
