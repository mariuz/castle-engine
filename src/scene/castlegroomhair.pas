{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Groom strand hair & fur component providing Fibonacci scalp guide distribution,
  root-to-tip lock clumping, helical curl & frizz profiles, tapered root-to-tip
  melanin hair card strip generation, head-sphere anti-clipping collision, and
  Verlet wind/head-turn inertia (Phase 348 — Unreal Engine 6.0+ UGroomComponent Parity). }
unit CastleGroomHair;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Built-in Groom hair & fur style presets. }
  TGroomStylePreset = (
    gspCustom,
    gspStylizedHeroBob,
    gspCurlyRinglets,
    gspWolfManeFur,
    gspWindblownPonytail
  );

  { Guide strand state storing local scalp root/normal and simulated points. }
  TGroomGuideStrand = record
    RootLocal: TVector3;
    NormalLocal: TVector3;
    PointsLocal: array of TVector3;
    PrevPointsLocal: array of TVector3;
  end;

  { Procedural Groom strand/clump-card hair & fur component. }
  TCastleGroomComponent = class(TCastleTransform)
  private
    FPreset: TGroomStylePreset;
    FGuideCount: Integer;
    FStrandsPerClump: Integer;
    FSegmentsPerStrand: Integer;
    FStrandLength: Single;
    FScalpRadius: Single;
    FCardRootWidth: Single;
    FClumpTightness: Single;
    FCurlAmplitude: Single;
    FCurlTurns: Single;
    FFrizzAmount: Single;
    FGravitySag: Single;
    FStiffness: Single;
    FDamping: Single;
    FWindVelocity: TVector3;
    FWindVelocityPersistent: TCastleVector3Persistent;
    FRootColorRGB: TVector3;
    FTipColorRGB: TVector3;
    FBuildVisualGroomMesh: Boolean;
    FAutoStepInUpdate: Boolean;

    FGuides: array of TGroomGuideStrand;
    FGeneratedTriangleCount: Integer;
    FSimTimeSec: Single;
    FPrevWorldPos: TVector3;
    FHasPrevWorldPos: Boolean;

    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;

    procedure SetPreset(const AValue: TGroomStylePreset);
    procedure SetGuideCount(const AValue: Integer);
    procedure SetStrandsPerClump(const AValue: Integer);
    procedure SetSegmentsPerStrand(const AValue: Integer);
    procedure SetStrandLength(const AValue: Single);
    procedure SetScalpRadius(const AValue: Single);
    procedure SetCardRootWidth(const AValue: Single);
    procedure SetClumpTightness(const AValue: Single);
    procedure SetCurlAmplitude(const AValue: Single);
    procedure SetCurlTurns(const AValue: Single);
    procedure SetFrizzAmount(const AValue: Single);
    procedure SetBuildVisualGroomMesh(const AValue: Boolean);

    function GetWindVelocityForPersistent: TVector3;
    procedure SetWindVelocityForPersistent(const AValue: TVector3);

    procedure ApplyPresetValuesOnly(const APreset: TGroomStylePreset);
    procedure EnsureVisualScene;
    procedure RebuildCardStripMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Rebuild Fibonacci scalp guide strands at rest and regenerate card mesh. }
    procedure RebuildGroomGuides;

    procedure ApplyStylePreset(const APreset: TGroomStylePreset);

    { Advance Verlet guide-strand dynamics (gravity, wind, head inertia,
      inextensible segment constraints & scalp-sphere anti-clip pushout). }
    procedure StepGroomPhysics(const ADt: Single);

    { Evaluate local position of child strand AChildIdx (0..StrandsPerClump-1)
      along guide AGuideIdx at segment vertex K (0..SegmentsPerStrand). }
    function EvaluateChildStrandPointLocal(const AGuideIdx, AChildIdx, ASegVertex: Integer): TVector3;

    function GuideTipLocal(const AGuideIdx: Integer): TVector3;
    function MeanTipDeflectionX: Single;
    function MinDistanceFromScalpCenter: Single;
    function TotalStrandCount: Integer;
    function GroomSummaryBadge: String;

    property WindVelocity: TVector3 read FWindVelocity write SetWindVelocityForPersistent;
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
  published
    property Preset: TGroomStylePreset
      read FPreset write SetPreset default gspStylizedHeroBob;
    property GuideCount: Integer
      read FGuideCount write SetGuideCount default 12;
    property StrandsPerClump: Integer
      read FStrandsPerClump write SetStrandsPerClump default 5;
    property SegmentsPerStrand: Integer
      read FSegmentsPerStrand write SetSegmentsPerStrand default 6;
    property StrandLength: Single
      read FStrandLength write SetStrandLength {$ifdef FPC}default 0.55{$endif};
    property ScalpRadius: Single
      read FScalpRadius write SetScalpRadius {$ifdef FPC}default 0.26{$endif};
    property CardRootWidth: Single
      read FCardRootWidth write SetCardRootWidth {$ifdef FPC}default 0.038{$endif};
    property ClumpTightness: Single
      read FClumpTightness write SetClumpTightness {$ifdef FPC}default 0.78{$endif};
    property CurlAmplitude: Single
      read FCurlAmplitude write SetCurlAmplitude {$ifdef FPC}default 0.015{$endif};
    property CurlTurns: Single
      read FCurlTurns write SetCurlTurns {$ifdef FPC}default 1.5{$endif};
    property FrizzAmount: Single
      read FFrizzAmount write SetFrizzAmount {$ifdef FPC}default 0.012{$endif};
    property GravitySag: Single
      read FGravitySag write FGravitySag {$ifdef FPC}default 3.8{$endif};
    property Stiffness: Single
      read FStiffness write FStiffness {$ifdef FPC}default 0.42{$endif};
    property Damping: Single
      read FDamping write FDamping {$ifdef FPC}default 0.92{$endif};
    property WindVelocityPersistent: TCastleVector3Persistent read FWindVelocityPersistent;
    property BuildVisualGroomMesh: Boolean
      read FBuildVisualGroomMesh write SetBuildVisualGroomMesh default True;
    property AutoStepInUpdate: Boolean
      read FAutoStepInUpdate write FAutoStepInUpdate default True;
  end;

function GroomPresetToDisplayName(const APreset: TGroomStylePreset): String;

implementation

uses
  CastleComponentSerialize;

function GroomPresetToDisplayName(const APreset: TGroomStylePreset): String;
begin
  case APreset of
    gspCustom:            Result := 'Custom Groom';
    gspStylizedHeroBob:   Result := 'Stylized Hero Bob';
    gspCurlyRinglets:     Result := 'Curly Helical Ringlets';
    gspWolfManeFur:       Result := 'Dense Wolf Mane Fur';
    gspWindblownPonytail: Result := 'Long Windblown Locks';
  end;
end;

procedure BuildOrthonormalFrame(const ANormal: TVector3; out ATan1, ATan2: TVector3);
var
  UpRef: TVector3;
begin
  if Abs(ANormal.Y) < 0.92 then
    UpRef := Vector3(0, 1, 0)
  else
    UpRef := Vector3(1, 0, 0);
  ATan1 := TVector3.CrossProduct(UpRef, ANormal).Normalize;
  ATan2 := TVector3.CrossProduct(ANormal, ATan1).Normalize;
end;

{$PUSH}{$Q-}{$R-}
function HashDetUnit(const ASeed: Cardinal): Single;
var
  S: Cardinal;
begin
  S := Cardinal(QWord(ASeed) * QWord(747796405) + QWord(2891336453));
  S := Cardinal(QWord((S shr ((S shr 28) + 4)) xor S) * QWord(277803737));
  S := (S shr 22) xor S;
  Result := ((S and $FFFF) / 32767.5) - 1.0;
end;
{$POP}

{ TCastleGroomComponent ------------------------------------------------------ }

constructor TCastleGroomComponent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWindVelocity := TVector3.Zero;
  FWindVelocityPersistent := TCastleVector3Persistent.Create(nil);
  FWindVelocityPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalDefaultValue := FWindVelocity;

  FBuildVisualGroomMesh := True;
  FAutoStepInUpdate := True;
  FPreset := gspStylizedHeroBob;
  ApplyPresetValuesOnly(gspStylizedHeroBob);
  RebuildGroomGuides;
end;

destructor TCastleGroomComponent.Destroy;
var
  I: Integer;
begin
  FCoordNode := nil;
  FColorNode := nil;
  FreeAndNil(FTransientScene);
  FreeAndNil(FWindVelocityPersistent);
  for I := 0 to High(FGuides) do
  begin
    SetLength(FGuides[I].PointsLocal, 0);
    SetLength(FGuides[I].PrevPointsLocal, 0);
  end;
  SetLength(FGuides, 0);
  inherited Destroy;
end;

function TCastleGroomComponent.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'GuideCount', 'StrandsPerClump', 'SegmentsPerStrand',
       'StrandLength', 'ScalpRadius', 'CardRootWidth', 'ClumpTightness',
       'CurlAmplitude', 'CurlTurns', 'FrizzAmount', 'GravitySag',
       'Stiffness', 'Damping', 'WindVelocityPersistent',
       'BuildVisualGroomMesh', 'AutoStepInUpdate'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleGroomComponent.ApplyPresetValuesOnly(const APreset: TGroomStylePreset);
begin
  case APreset of
    gspStylizedHeroBob:
      begin
        FGuideCount := 12;
        FStrandsPerClump := 5;
        FSegmentsPerStrand := 6;
        FStrandLength := 0.55;
        FScalpRadius := 0.26;
        FCardRootWidth := 0.038;
        FClumpTightness := 0.78;
        FCurlAmplitude := 0.015;
        FCurlTurns := 1.5;
        FFrizzAmount := 0.012;
        FGravitySag := 3.8;
        FStiffness := 0.42;
        FDamping := 0.92;
        FRootColorRGB := Vector3(0.16, 0.10, 0.07);
        FTipColorRGB := Vector3(0.62, 0.36, 0.18);
      end;
    gspCurlyRinglets:
      begin
        FGuideCount := 14;
        FStrandsPerClump := 6;
        FSegmentsPerStrand := 8;
        FStrandLength := 0.62;
        FScalpRadius := 0.26;
        FCardRootWidth := 0.032;
        FClumpTightness := 0.86;
        FCurlAmplitude := 0.055;
        FCurlTurns := 3.5;
        FFrizzAmount := 0.016;
        FGravitySag := 3.2;
        FStiffness := 0.48;
        FDamping := 0.92;
        FRootColorRGB := Vector3(0.22, 0.08, 0.06);
        FTipColorRGB := Vector3(0.84, 0.38, 0.16);
      end;
    gspWolfManeFur:
      begin
        FGuideCount := 20;
        FStrandsPerClump := 5;
        FSegmentsPerStrand := 4;
        FStrandLength := 0.28;
        FScalpRadius := 0.30;
        FCardRootWidth := 0.042;
        FClumpTightness := 0.90;
        FCurlAmplitude := 0.005;
        FCurlTurns := 0.5;
        FFrizzAmount := 0.022;
        FGravitySag := 2.0;
        FStiffness := 0.72;
        FDamping := 0.90;
        FRootColorRGB := Vector3(0.20, 0.22, 0.26);
        FTipColorRGB := Vector3(0.76, 0.78, 0.84);
      end;
    gspWindblownPonytail:
      begin
        FGuideCount := 10;
        FStrandsPerClump := 6;
        FSegmentsPerStrand := 8;
        FStrandLength := 0.85;
        FScalpRadius := 0.25;
        FCardRootWidth := 0.036;
        FClumpTightness := 0.82;
        FCurlAmplitude := 0.020;
        FCurlTurns := 1.2;
        FFrizzAmount := 0.010;
        FGravitySag := 4.4;
        FStiffness := 0.30;
        FDamping := 0.94;
        FRootColorRGB := Vector3(0.12, 0.14, 0.28);
        FTipColorRGB := Vector3(0.36, 0.72, 0.96);
      end;
  else ;
  end;
end;

procedure TCastleGroomComponent.ApplyStylePreset(const APreset: TGroomStylePreset);
begin
  FPreset := APreset;
  if APreset <> gspCustom then
    ApplyPresetValuesOnly(APreset);
  RebuildGroomGuides;
end;

procedure TCastleGroomComponent.SetPreset(const AValue: TGroomStylePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> gspCustom then
  begin
    ApplyPresetValuesOnly(AValue);
    RebuildGroomGuides;
  end;
end;

procedure TCastleGroomComponent.SetGuideCount(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 2, 64);
  if V = FGuideCount then Exit;
  FGuideCount := V;
  FPreset := gspCustom;
  RebuildGroomGuides;
end;

procedure TCastleGroomComponent.SetStrandsPerClump(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 1, 16);
  if V = FStrandsPerClump then Exit;
  FStrandsPerClump := V;
  FPreset := gspCustom;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.SetSegmentsPerStrand(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 2, 16);
  if V = FSegmentsPerStrand then Exit;
  FSegmentsPerStrand := V;
  FPreset := gspCustom;
  RebuildGroomGuides;
end;

procedure TCastleGroomComponent.SetStrandLength(const AValue: Single);
begin
  FStrandLength := EnsureRange(AValue, 0.05, 3.0);
  FPreset := gspCustom;
  RebuildGroomGuides;
end;

procedure TCastleGroomComponent.SetScalpRadius(const AValue: Single);
begin
  FScalpRadius := EnsureRange(AValue, 0.05, 2.0);
  FPreset := gspCustom;
  RebuildGroomGuides;
end;

procedure TCastleGroomComponent.SetCardRootWidth(const AValue: Single);
begin
  FCardRootWidth := EnsureRange(AValue, 0.004, 0.25);
  FPreset := gspCustom;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.SetClumpTightness(const AValue: Single);
begin
  FClumpTightness := EnsureRange(AValue, 0.0, 1.0);
  FPreset := gspCustom;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.SetCurlAmplitude(const AValue: Single);
begin
  FCurlAmplitude := EnsureRange(AValue, 0.0, 0.30);
  FPreset := gspCustom;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.SetCurlTurns(const AValue: Single);
begin
  FCurlTurns := EnsureRange(AValue, 0.0, 12.0);
  FPreset := gspCustom;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.SetFrizzAmount(const AValue: Single);
begin
  FFrizzAmount := EnsureRange(AValue, 0.0, 0.15);
  FPreset := gspCustom;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.SetBuildVisualGroomMesh(const AValue: Boolean);
begin
  if FBuildVisualGroomMesh = AValue then Exit;
  FBuildVisualGroomMesh := AValue;
  if not FBuildVisualGroomMesh then
  begin
    FCoordNode := nil;
    FColorNode := nil;
    FreeAndNil(FTransientScene);
  end else
    RebuildCardStripMesh;
end;

function TCastleGroomComponent.GetWindVelocityForPersistent: TVector3;
begin
  Result := FWindVelocity;
end;

procedure TCastleGroomComponent.SetWindVelocityForPersistent(const AValue: TVector3);
begin
  FWindVelocity := AValue;
end;

procedure TCastleGroomComponent.RebuildGroomGuides;
const
  GoldenAngle = 2.39996323;
var
  G, K: Integer;
  U, Y, RadXZ, Theta, SegLen, Frac: Single;
  Norm, Pos: TVector3;
begin
  SetLength(FGuides, FGuideCount);
  SegLen := FStrandLength / Single(Max(1, FSegmentsPerStrand));

  for G := 0 to FGuideCount - 1 do
  begin
    { Upper scalp dome cap: Y in [0.22 .. 0.98] }
    if FGuideCount = 1 then
      U := 0.5
    else
      U := G / Single(FGuideCount - 1);
    Y := Lerp(U, 0.25, 0.98);
    RadXZ := Sqrt(Max(0.0, 1.0 - Y * Y));
    Theta := G * GoldenAngle;

    Norm := Vector3(Cos(Theta) * RadXZ, Y, Sin(Theta) * RadXZ).Normalize;
    FGuides[G].NormalLocal := Norm;
    FGuides[G].RootLocal := Norm * FScalpRadius;

    SetLength(FGuides[G].PointsLocal, FSegmentsPerStrand + 1);
    SetLength(FGuides[G].PrevPointsLocal, FSegmentsPerStrand + 1);
    Pos := FGuides[G].RootLocal;
    FGuides[G].PointsLocal[0] := Pos;
    FGuides[G].PrevPointsLocal[0] := Pos;

    for K := 1 to FSegmentsPerStrand do
    begin
      Frac := K / Single(FSegmentsPerStrand);
      { Natural outward + downward drape outside head sphere }
      Pos := Pos + (Norm * (1.0 - 0.55 * Frac) + Vector3(0.0, -0.65 * Frac, 0.0)).Normalize * SegLen;
      if Pos.Length < FScalpRadius * 1.03 then
        Pos := Pos.Normalize * (FScalpRadius * 1.03);
      FGuides[G].PointsLocal[K] := Pos;
      FGuides[G].PrevPointsLocal[K] := Pos;
    end;
  end;

  FHasPrevWorldPos := False;
  RebuildCardStripMesh;
end;

procedure TCastleGroomComponent.StepGroomPhysics(const ADt: Single);
var
  Dt, SegLen, Gust: Single;
  G, K, Iter: Integer;
  CurWorld, HeadDeltaLocal, Vel, Accel, RestTarget, Delta, PushDir: TVector3;
  Dist, MinHeadDist: Single;
begin
  Dt := EnsureRange(ADt, 0.0, 0.05);
  if Dt <= 0.0 then Exit;
  if Length(FGuides) <> FGuideCount then
    RebuildGroomGuides;

  FSimTimeSec := FSimTimeSec + Dt;
  if HasParent then
    CurWorld := WorldTranslation
  else
    CurWorld := Translation;

  if FHasPrevWorldPos then
    HeadDeltaLocal := CurWorld - FPrevWorldPos
  else
    HeadDeltaLocal := TVector3.Zero;
  FPrevWorldPos := CurWorld;
  FHasPrevWorldPos := True;

  SegLen := FStrandLength / Single(Max(1, FSegmentsPerStrand));
  MinHeadDist := FScalpRadius * 1.01;
  Gust := 1.0 + 0.25 * Sin(FSimTimeSec * 4.5);

  for G := 0 to High(FGuides) do
  begin
    FGuides[G].PointsLocal[0] := FGuides[G].RootLocal;
    for K := 1 to FSegmentsPerStrand do
    begin
      Vel := (FGuides[G].PointsLocal[K] - FGuides[G].PrevPointsLocal[K]) * FDamping
             - HeadDeltaLocal * 0.35;
      FGuides[G].PrevPointsLocal[K] := FGuides[G].PointsLocal[K];

      RestTarget := FGuides[G].RootLocal + FGuides[G].NormalLocal * (SegLen * K);
      Accel := Vector3(0.0, -FGravitySag, 0.0)
             + FWindVelocity * Gust
             + (RestTarget - FGuides[G].PointsLocal[K]) * (FStiffness * 18.0);

      FGuides[G].PointsLocal[K] := FGuides[G].PointsLocal[K] + Vel + Accel * (Dt * Dt);
    end;

    { 3 PBD constraint solver passes: inextensible rod + scalp sphere anti-clip }
    for Iter := 1 to 3 do
    begin
      FGuides[G].PointsLocal[0] := FGuides[G].RootLocal;
      for K := 1 to FSegmentsPerStrand do
      begin
        Delta := FGuides[G].PointsLocal[K] - FGuides[G].PointsLocal[K - 1];
        Dist := Delta.Length;
        if Dist > 1e-6 then
          FGuides[G].PointsLocal[K] := FGuides[G].PointsLocal[K - 1] + Delta * (SegLen / Dist);

        { Push strand vertex outside scalp sphere so hair never clips into head }
        Dist := FGuides[G].PointsLocal[K].Length;
        if Dist < MinHeadDist then
        begin
          if Dist > 1e-6 then
            PushDir := FGuides[G].PointsLocal[K] / Dist
          else
            PushDir := FGuides[G].NormalLocal;
          FGuides[G].PointsLocal[K] := PushDir * MinHeadDist;
        end;
      end;
    end;
  end;

  RebuildCardStripMesh;
end;

function TCastleGroomComponent.EvaluateChildStrandPointLocal(
  const AGuideIdx, AChildIdx, ASegVertex: Integer): TVector3;
var
  ClampedG, ClampedK: Integer;
  Tan1, Tan2, RootJitter, CurlOffset, FrizzOffset: TVector3;
  U, Angle, SpreadR, ClumpKeep, CurlPhase: Single;
  SeedBase: Cardinal;
begin
  ClampedG := EnsureRange(AGuideIdx, 0, High(FGuides));
  ClampedK := EnsureRange(ASegVertex, 0, FSegmentsPerStrand);
  Result := FGuides[ClampedG].PointsLocal[ClampedK];
  if FStrandsPerClump <= 1 then
    Exit;

  BuildOrthonormalFrame(FGuides[ClampedG].NormalLocal, Tan1, Tan2);
  U := ClampedK / Single(Max(1, FSegmentsPerStrand));

  if AChildIdx = 0 then
    RootJitter := TVector3.Zero
  else
  begin
    Angle := (AChildIdx / Single(Max(1, FStrandsPerClump - 1))) * 2.0 * Pi + ClampedG * 0.7;
    SpreadR := FScalpRadius * 0.24;
    RootJitter := (Tan1 * Cos(Angle) + Tan2 * Sin(Angle)) * SpreadR;
  end;

  { ClumpTightness pulls child strand toward guide tip as U -> 1 }
  ClumpKeep := 1.0 - (FClumpTightness * U);
  CurlPhase := 2.0 * Pi * FCurlTurns * U + AChildIdx * 1.1;
  CurlOffset := (Tan1 * Cos(CurlPhase) + Tan2 * Sin(CurlPhase)) * (FCurlAmplitude * U);

  SeedBase := Cardinal(ClampedG * 977 + AChildIdx * 131 + ClampedK * 17 + 1);
  FrizzOffset := (Tan1 * HashDetUnit(SeedBase) + Tan2 * HashDetUnit(SeedBase + 7)) * (FFrizzAmount * U);

  Result := Result + RootJitter * ClumpKeep + CurlOffset + FrizzOffset;
  if (ClampedK > 0) and (Result.Length < FScalpRadius * 0.99) then
    Result := Result.Normalize * (FScalpRadius * 0.99);
end;

procedure TCastleGroomComponent.EnsureVisualScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if not FBuildVisualGroomMesh then Exit;
  if FTransientScene <> nil then Exit;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientGroomCards';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := Vector3(1, 1, 1);
  Mat.Roughness := 0.42;
  App.Material := Mat;
  Shape.Appearance := App;

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

procedure TCastleGroomComponent.RebuildCardStripMesh;
var
  Verts, Colors: TVector3List;
  G, C, K: Integer;
  P0, P1, Tangent, Side0, Side1, Col0, Col1: TVector3;
  U0, U1, W0, W1: Single;
begin
  FGeneratedTriangleCount := Length(FGuides) * FStrandsPerClump * FSegmentsPerStrand * 2;
  if not FBuildVisualGroomMesh then Exit;
  EnsureVisualScene;
  if FTransientScene = nil then Exit;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    Verts.Capacity := FGeneratedTriangleCount * 3;
    Colors.Capacity := FGeneratedTriangleCount * 3;

    for G := 0 to High(FGuides) do
      for C := 0 to FStrandsPerClump - 1 do
        for K := 0 to FSegmentsPerStrand - 1 do
        begin
          P0 := EvaluateChildStrandPointLocal(G, C, K);
          P1 := EvaluateChildStrandPointLocal(G, C, K + 1);
          Tangent := P1 - P0;
          if Tangent.IsZero then
            Tangent := Vector3(0, -1, 0)
          else
            Tangent := Tangent.Normalize;

          U0 := K / Single(FSegmentsPerStrand);
          U1 := (K + 1) / Single(FSegmentsPerStrand);
          W0 := 0.5 * FCardRootWidth * (1.0 - 0.82 * U0);
          W1 := 0.5 * FCardRootWidth * (1.0 - 0.82 * U1);

          Side0 := TVector3.CrossProduct(Tangent, FGuides[G].NormalLocal);
          if Side0.LengthSqr < 1e-8 then
            Side0 := Vector3(1, 0, 0)
          else
            Side0 := Side0.Normalize;
          Side1 := Side0 * W1;
          Side0 := Side0 * W0;

          Col0 := Lerp(U0, FRootColorRGB, FTipColorRGB);
          Col1 := Lerp(U1, FRootColorRGB, FTipColorRGB);

          Verts.Add(P0 - Side0); Verts.Add(P0 + Side0); Verts.Add(P1 + Side1);
          Colors.Add(Col0); Colors.Add(Col0); Colors.Add(Col1);

          Verts.Add(P0 - Side0); Verts.Add(P1 + Side1); Verts.Add(P1 - Side1);
          Colors.Add(Col0); Colors.Add(Col1); Colors.Add(Col1);
        end;

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

procedure TCastleGroomComponent.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoStepInUpdate then
    StepGroomPhysics(Min(SecondsPassed, 0.04));
end;

function TCastleGroomComponent.GuideTipLocal(const AGuideIdx: Integer): TVector3;
var
  G: Integer;
begin
  if Length(FGuides) = 0 then
    Exit(TVector3.Zero);
  G := EnsureRange(AGuideIdx, 0, High(FGuides));
  Result := FGuides[G].PointsLocal[High(FGuides[G].PointsLocal)];
end;

function TCastleGroomComponent.MeanTipDeflectionX: Single;
var
  G: Integer;
begin
  Result := 0.0;
  if Length(FGuides) = 0 then Exit;
  for G := 0 to High(FGuides) do
    Result := Result + (GuideTipLocal(G).X - FGuides[G].RootLocal.X);
  Result := Result / Single(Length(FGuides));
end;

function TCastleGroomComponent.MinDistanceFromScalpCenter: Single;
var
  G, K: Integer;
begin
  Result := 1e9;
  for G := 0 to High(FGuides) do
    for K := 1 to High(FGuides[G].PointsLocal) do
      Result := Min(Result, FGuides[G].PointsLocal[K].Length);
  if Result > 1e8 then
    Result := FScalpRadius;
end;

function TCastleGroomComponent.TotalStrandCount: Integer;
begin
  Result := FGuideCount * FStrandsPerClump;
end;

function TCastleGroomComponent.GroomSummaryBadge: String;
begin
  Result := Format('[Groom:%d strands Clump=%.2f %d tris]', [
    TotalStrandCount, FClumpTightness, FGeneratedTriangleCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleGroomComponent,
    ['Animation & Rigging', 'Groom Hair & Fur Clump Cards (TCastleGroomComponent)']);

end.
