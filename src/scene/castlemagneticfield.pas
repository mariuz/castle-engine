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

{ 3D magnetic dipole B-field solver, opposite-pole attraction vs. like-pole
  repulsion, ferromagnetic crane pull, Lenz-law eddy-current velocity braking,
  and WorldRay zero-G hull mag-boot locking (Phase 409). }
unit CastleMagneticField;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTriangles, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset electromagnetic gameplay profiles. }
  TMagneticFieldPreset = (
    mfpScrapyardElectromagnetCrane,
    mfpZeroGHullMagBoots,
    mfpRailcoasterEddyBrake
  );

  { Evaluated B-field, dipole/ferromagnetic force & Lenz eddy-brake sample. }
  TMagneticForceSample = record
    BFieldTesla: TVector3;
    BFieldMagnitudeTesla: Single;
    DipoleForceNewtons: TVector3;
    FerromagneticPullNewtons: TVector3;
    EddyBrakeForceNewtons: TVector3;
    TotalForceNewtons: TVector3;
  end;

  { Zero-G spacecraft hull mag-boot lock probe result. }
  TMagBootGripResult = record
    HullLocked: Boolean;
    SnapWorldPoint: TVector3;
    HullSurfaceNormal: TVector3;
    HoldForceNewtons: Single;
  end;

  { 3D magnetic dipole, eddy brake & mag-boot field component. }
  TCastleMagneticField = class(TCastleTransform)
  private
    FPreset: TMagneticFieldPreset;
    FCoilEnergized: Boolean;
    FDipoleMomentAmpSqM: Single;
    FCoreSofteningRadiusM: Single;
    FFerromagneticGain: Single;
    FEddyConductivityGain: Single;
    FMagBootSnapRangeMeters: Single;
    FMagBootHoldNewtons: Single;
    FShowPreview: Boolean;
    FPreviewRoot: TCastleTransform;
    FPreviewLoopsScene: TCastleScene;
    procedure SetPreset(const AValue: TMagneticFieldPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TMagneticFieldPreset);

    { Exact 3D magnetic dipole vector B(r) = (mu0 / 4*pi*r^3) * (3(m.rHat)rHat - m)
      with dipole axis aligned along transformed local +Y. }
    function SampleBFieldTeslaAtWorld(const AWorldPoint: TVector3): TVector3;

    { Evaluate dipole-dipole force (on ATargetDipoleMoment), soft-iron
      ferromagnetic attraction, and Lenz-law eddy-current damping (-sigma*B^2*v). }
    function EvaluateMagneticForces(const ABodyWorldPos, ABodyVelocityMps,
      ATargetDipoleMoment: TVector3;
      const AFerromagneticSusceptibility: Single = 0.0): TMagneticForceSample;

    { Cast a WorldRay from ABootWorldPos along ABootDownDir to clamp zero-G
      mag-boots onto nearby steel hull plating. }
    function ProbeZeroGMagBootGrip(
      const AWorldRoot: TCastleAbstractRootTransform;
      const ABootWorldPos, ABootDownDir: TVector3): TMagBootGripResult;

    procedure RebuildPreview;
    procedure ClearPreview;
    function MagnetSummaryBadge: String;
  published
    property Preset: TMagneticFieldPreset
      read FPreset write SetPreset default mfpScrapyardElectromagnetCrane;
    property CoilEnergized: Boolean
      read FCoilEnergized write FCoilEnergized default True;
    property DipoleMomentAmpSqM: Single
      read FDipoleMomentAmpSqM write FDipoleMomentAmpSqM;
    property CoreSofteningRadiusM: Single
      read FCoreSofteningRadiusM write FCoreSofteningRadiusM;
    property FerromagneticGain: Single
      read FFerromagneticGain write FFerromagneticGain;
    property EddyConductivityGain: Single
      read FEddyConductivityGain write FEddyConductivityGain;
    property MagBootSnapRangeMeters: Single
      read FMagBootSnapRangeMeters write FMagBootSnapRangeMeters;
    property MagBootHoldNewtons: Single
      read FMagBootHoldNewtons write FMagBootHoldNewtons;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function MagneticFieldPresetToString(const APreset: TMagneticFieldPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

const
  { mu0 / (4 * pi) in SI Tesla * m / Ampere }
  Mu0Over4Pi = 1.0e-7;

function MagneticFieldPresetToString(const APreset: TMagneticFieldPreset): String;
begin
  case APreset of
    mfpScrapyardElectromagnetCrane: Result := 'ScrapyardElectromagnetCrane';
    mfpZeroGHullMagBoots:           Result := 'ZeroGHullMagBoots';
    mfpRailcoasterEddyBrake:        Result := 'RailcoasterEddyBrake';
  end;
end;

constructor TCastleMagneticField.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FCoilEnergized := True;
  ApplyPreset(mfpScrapyardElectromagnetCrane);
end;

destructor TCastleMagneticField.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleMagneticField.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'CoilEnergized', 'DipoleMomentAmpSqM',
       'CoreSofteningRadiusM', 'FerromagneticGain',
       'EddyConductivityGain', 'MagBootSnapRangeMeters',
       'MagBootHoldNewtons', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMagneticField.SetPreset(const AValue: TMagneticFieldPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleMagneticField.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleMagneticField.ApplyPreset(const APreset: TMagneticFieldPreset);
begin
  FPreset := APreset;
  FCoilEnergized := True;
  case APreset of
    mfpScrapyardElectromagnetCrane:
      begin
        FDipoleMomentAmpSqM := 2.5e6;
        FCoreSofteningRadiusM := 0.35;
        FFerromagneticGain := 4500.0;
        FEddyConductivityGain := 120.0;
        FMagBootSnapRangeMeters := 0.65;
        FMagBootHoldNewtons := 1800.0;
      end;
    mfpZeroGHullMagBoots:
      begin
        FDipoleMomentAmpSqM := 4.0e5;
        FCoreSofteningRadiusM := 0.20;
        FFerromagneticGain := 1200.0;
        FEddyConductivityGain := 40.0;
        FMagBootSnapRangeMeters := 0.95;
        FMagBootHoldNewtons := 4200.0;
      end;
    mfpRailcoasterEddyBrake:
      begin
        FDipoleMomentAmpSqM := 6.0e6;
        FCoreSofteningRadiusM := 0.25;
        FFerromagneticGain := 0.0;
        FEddyConductivityGain := 8500.0;
        FMagBootSnapRangeMeters := 0.40;
        FMagBootHoldNewtons := 800.0;
      end;
  end;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleMagneticField.SampleBFieldTeslaAtWorld(
  const AWorldPoint: TVector3): TVector3;
var
  WT: TMatrix4;
  OriginW, AxisW, MVec, RVec, RHat: TVector3;
  Dist, RSoft, R3, MDotR: Single;
begin
  if not FCoilEnergized then
    Exit(TVector3.Zero);

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  OriginW := WT.MultPoint(TVector3.Zero);
  AxisW := WT.MultDirection(Vector3(0.0, 1.0, 0.0));
  if AxisW.LengthSqr > 1e-6 then
    AxisW := AxisW.Normalize
  else
    AxisW := Vector3(0.0, 1.0, 0.0);

  MVec := AxisW * FDipoleMomentAmpSqM;
  RVec := AWorldPoint - OriginW;
  Dist := RVec.Length;
  RSoft := Max(Max(0.05, FCoreSofteningRadiusM), Dist);
  R3 := RSoft * RSoft * RSoft;

  if Dist > 1e-5 then
  begin
    RHat := RVec / Dist;
    MDotR := TVector3.DotProduct(MVec, RHat);
    Result := ((RHat * (3.0 * MDotR)) - MVec) * (Mu0Over4Pi / R3);
  end else
    Result := AxisW * (2.0 * Mu0Over4Pi * FDipoleMomentAmpSqM / R3);
end;

function TCastleMagneticField.EvaluateMagneticForces(
  const ABodyWorldPos, ABodyVelocityMps, ATargetDipoleMoment: TVector3;
  const AFerromagneticSusceptibility: Single): TMagneticForceSample;
const
  Eps = 0.02;
var
  B0, BX1, BX0, BY1, BY0, BZ1, BZ0: TVector3;
  BMagSq, E0, EX1, EX0, EY1, EY0, EZ1, EZ0: Single;
  U0, UX1, UX0, UY1, UY0, UZ1, UZ0: Single;
begin
  Result := Default(TMagneticForceSample);
  if not FCoilEnergized then Exit;

  B0 := SampleBFieldTeslaAtWorld(ABodyWorldPos);
  BMagSq := B0.LengthSqr;
  Result.BFieldTesla := B0;
  Result.BFieldMagnitudeTesla := Sqrt(BMagSq);

  if (ATargetDipoleMoment.LengthSqr > 1e-8) or
     (AFerromagneticSusceptibility > 1e-6) then
  begin
    BX1 := SampleBFieldTeslaAtWorld(ABodyWorldPos + Vector3(Eps, 0, 0));
    BX0 := SampleBFieldTeslaAtWorld(ABodyWorldPos - Vector3(Eps, 0, 0));
    BY1 := SampleBFieldTeslaAtWorld(ABodyWorldPos + Vector3(0, Eps, 0));
    BY0 := SampleBFieldTeslaAtWorld(ABodyWorldPos - Vector3(0, Eps, 0));
    BZ1 := SampleBFieldTeslaAtWorld(ABodyWorldPos + Vector3(0, 0, Eps));
    BZ0 := SampleBFieldTeslaAtWorld(ABodyWorldPos - Vector3(0, 0, Eps));

    { 1. Exact potential gradient force on permanent dipole: F = grad(m2 . B) }
    if ATargetDipoleMoment.LengthSqr > 1e-8 then
    begin
      U0 := 1.0 / (2.0 * Eps);
      UX1 := TVector3.DotProduct(ATargetDipoleMoment, BX1);
      UX0 := TVector3.DotProduct(ATargetDipoleMoment, BX0);
      UY1 := TVector3.DotProduct(ATargetDipoleMoment, BY1);
      UY0 := TVector3.DotProduct(ATargetDipoleMoment, BY0);
      UZ1 := TVector3.DotProduct(ATargetDipoleMoment, BZ1);
      UZ0 := TVector3.DotProduct(ATargetDipoleMoment, BZ0);
      Result.DipoleForceNewtons := Vector3(
        (UX1 - UX0) * U0,
        (UY1 - UY0) * U0,
        (UZ1 - UZ0) * U0);
    end;

    { 2. Induced soft-iron ferromagnetic pull toward higher |B|^2: F ~ grad(|B|^2) }
    if AFerromagneticSusceptibility > 1e-6 then
    begin
      E0 := (AFerromagneticSusceptibility * FFerromagneticGain) / (2.0 * Eps);
      EX1 := BX1.LengthSqr; EX0 := BX0.LengthSqr;
      EY1 := BY1.LengthSqr; EY0 := BY0.LengthSqr;
      EZ1 := BZ1.LengthSqr; EZ0 := BZ0.LengthSqr;
      Result.FerromagneticPullNewtons := Vector3(
        (EX1 - EX0) * E0,
        (EY1 - EY0) * E0,
        (EZ1 - EZ0) * E0);
    end;
  end;

  { 3. Lenz-law eddy-current velocity damping: F_eddy = -Gain * |B|^2 * v }
  if (FEddyConductivityGain > 0.0) and (ABodyVelocityMps.LengthSqr > 1e-8) then
    Result.EddyBrakeForceNewtons :=
      (-ABodyVelocityMps) * (FEddyConductivityGain * BMagSq);

  Result.TotalForceNewtons :=
    Result.DipoleForceNewtons +
    Result.FerromagneticPullNewtons +
    Result.EddyBrakeForceNewtons;
end;

function TCastleMagneticField.ProbeZeroGMagBootGrip(
  const AWorldRoot: TCastleAbstractRootTransform;
  const ABootWorldPos, ABootDownDir: TVector3): TMagBootGripResult;
var
  ActiveRoot: TCastleAbstractRootTransform;
  Dir: TVector3;
  BestDist, D: Single;
  RH: TRayCollision;
  K: Integer;
  Item: TCastleTransform;
begin
  Result := Default(TMagBootGripResult);
  if (not FCoilEnergized) or (ABootDownDir.LengthSqr < 1e-6) then Exit;

  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;
  if ActiveRoot = nil then Exit;

  Dir := ABootDownDir.Normalize;
  BestDist := Max(0.05, FMagBootSnapRangeMeters) + 1.0;

  RH := ActiveRoot.WorldRay(ABootWorldPos, Dir);
  try
    if RH = nil then Exit;
    for K := 0 to RH.Count - 1 do
    begin
      Item := RH[K].Item;
      if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
      if csTransient in Item.ComponentStyle then Continue;
      D := PointsDistance(ABootWorldPos, RH[K].Point);
      if (D >= 0.01) and (D <= FMagBootSnapRangeMeters) and (D < BestDist) then
      begin
        BestDist := D;
        Result.HullLocked := True;
        Result.SnapWorldPoint := RH[K].Point;
        if (RH[K].Triangle <> nil) and Item.HasWorldTransform then
        begin
          Result.HullSurfaceNormal :=
            Item.LocalToWorldDirection(RH[K].Triangle^.SceneSpace.Normal);
          if Result.HullSurfaceNormal.LengthSqr > 1e-8 then
            Result.HullSurfaceNormal := Result.HullSurfaceNormal.Normalize
          else
            Result.HullSurfaceNormal := -Dir;
        end else
          Result.HullSurfaceNormal := -Dir;
        Result.HoldForceNewtons := FMagBootHoldNewtons *
          (1.0 - 0.5 * (D / Max(0.05, FMagBootSnapRangeMeters)));
      end;
    end;
  finally
    FreeAndNil(RH);
  end;
end;

procedure TCastleMagneticField.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewLoopsScene := nil;
  end;
end;

procedure TCastleMagneticField.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  Pts: array[0..33] of TVector3;
  I: Integer;
  Theta, RLoop: Single;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'MagneticFieldPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewLoopsScene := TCastleScene.Create(FPreviewRoot);
  FPreviewLoopsScene.SetTransient;
  FPreviewLoopsScene.Name := 'MagneticFieldPreviewFlux';
  FPreviewLoopsScene.Pickable := False;
  FPreviewLoopsScene.Collides := False;
  FPreviewRoot.Add(FPreviewLoopsScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.35, 0.72, 1.0);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  { Two symmetric dipole flux lobes r = R0 * sin^2(theta) in +/-X }
  for I := 0 to 16 do
  begin
    Theta := Pi * I / 16.0;
    RLoop := 2.2 * Sqr(Sin(Theta));
    Pts[I] := Vector3(RLoop * Sin(Theta), RLoop * Cos(Theta), 0.0);
    Pts[17 + I] := Vector3(-RLoop * Sin(Theta), RLoop * Cos(Theta), 0.0);
  end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount([17, 17]);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewLoopsScene.Load(RootNode, True);
end;

function TCastleMagneticField.MagnetSummaryBadge: String;
begin
  if FCoilEnergized then
    Result := FormatDot('[Magnet:%.1fe6 A*m2 Eddy=%.0f]', [
      FDipoleMomentAmpSqM * 1e-6, FEddyConductivityGain])
  else
    Result := '[Magnet:OFF]';
end;

initialization
  RegisterSerializableComponent(TCastleMagneticField, 'Magnetic Dipole & Eddy Field');

end.
