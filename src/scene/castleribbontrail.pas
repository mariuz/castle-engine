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

{ Niagara-style melee weapon dual-socket slash & projectile ribbon trails with
  Catmull-Rom arc subdivision, width/color tapering, UV scrolling, and
  midpoint-displaced 3D arc-lightning beam VFX (Phase 334 — UE 6.0+ Niagara Ribbons parity). }
unit CastleRibbonTrail;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Emission geometry mode for TCastleRibbonTrail. }
  TRibbonTrailMode = (
    { Connects two blade sockets (Hilt -> Tip) across consecutive frames for
      crisp melee weapon slash arcs. }
    rtmDualSocketBladeArc,
    { Expands a single moving point perpendicular to travel & up vector with
      StartWidth -> EndWidth tapering for projectiles and vehicle drift trails. }
    rtmSinglePointWidthTaper
  );

  { Visual color & width presets for TCastleRibbonTrail. }
  TRibbonTrailPreset = (
    rtpKatanaSunfireSlash,
    rtpArcaneProjectileComet,
    rtpCyberNeonDriftTrail
  );

  { Historical sample recorded in the ribbon trail buffer. }
  TRibbonSample = record
    PosBase: TVector3;
    PosTip: TVector3;
    CenterPos: TVector3;
    AgeSec: Single;
  end;

  { 3D segment emitted by TCastleLightningBeam. }
  TLightningSegment = record
    A: TVector3;
    B: TVector3;
    Thickness: Single;
    IsFork: Boolean;
  end;

  { Continuous Catmull-Rom subdivided weapon-slash or projectile ribbon trail
    rendering into a double-sided csTransient X3D TTriangleSetNode. }
  TCastleRibbonTrail = class(TCastleTransform)
  private
    FTrailMode: TRibbonTrailMode;
    FPreset: TRibbonTrailPreset;
    FLifetimeSec: Single;
    FMaxSamples: Integer;
    FCatmullSubdivisions: Integer;
    FStartWidth: Single;
    FEndWidth: Single;
    FBladeHiltOffset: Single;
    FBladeLength: Single;
    FUvScrollSpeed: Single;
    FEmitting: Boolean;
    FHeadColorRGB: TVector3;
    FTailColorRGB: TVector3;
    FUvScrollPhase: Single;

    FSamples: array of TRibbonSample;
    FSampleCount: Integer;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    FTexCoordNode: TTextureCoordinateNode;
    FGeneratedTriangleCount: Integer;
    FTotalArcLengthMeters: Single;

    procedure SetPreset(const AValue: TRibbonTrailPreset);
    procedure SetLifetimeSec(const AValue: Single);
    procedure SetMaxSamples(const AValue: Integer);
    procedure SetCatmullSubdivisions(const AValue: Integer);
    procedure SetStartWidth(const AValue: Single);
    procedure SetEndWidth(const AValue: Single);
    procedure SetBladeLength(const AValue: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure EnsureTransientRibbonScene;
    procedure RebuildRibbonMesh;
    procedure PushSamplePair(const ABase, ATip: TVector3);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TRibbonTrailPreset);
    procedure ClearTrail;

    { Record an explicit world-space dual-socket blade sample (Hilt & Tip). }
    procedure RecordBladeSampleWorld(const AHiltWorld, ATipWorld: TVector3);

    { Record an explicit world-space projectile/comet center sample. }
    procedure RecordPointSampleWorld(const ACenterWorld: TVector3);

    { Advance sample ages by Dt, prune expired samples (>= LifetimeSec),
      optionally sample current WorldTransform if Emitting, and rebuild the
      Catmull-Rom subdivided ribbon strip. }
    procedure StepTrail(const Dt: Single; const AAutoSampleTransform: Boolean = True);

    function ActiveSampleCount: Integer;
    function GetSample(const AIndex: Integer): TRibbonSample;
    function RibbonSummaryBadge: String;

    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
    property TotalArcLengthMeters: Single read FTotalArcLengthMeters;
    property HeadColorRGB: TVector3 read FHeadColorRGB write FHeadColorRGB;
    property TailColorRGB: TVector3 read FTailColorRGB write FTailColorRGB;
  published
    property TrailMode: TRibbonTrailMode read FTrailMode write FTrailMode default rtmDualSocketBladeArc;
    property Preset: TRibbonTrailPreset read FPreset write SetPreset default rtpKatanaSunfireSlash;
    property LifetimeSec: Single read FLifetimeSec write SetLifetimeSec {$ifdef FPC}default 0.45{$endif};
    property MaxSamples: Integer read FMaxSamples write SetMaxSamples default 48;
    property CatmullSubdivisions: Integer read FCatmullSubdivisions write SetCatmullSubdivisions default 3;
    property StartWidth: Single read FStartWidth write SetStartWidth {$ifdef FPC}default 0.55{$endif};
    property EndWidth: Single read FEndWidth write SetEndWidth {$ifdef FPC}default 0.04{$endif};
    property BladeHiltOffset: Single read FBladeHiltOffset write FBladeHiltOffset {$ifdef FPC}default 0.20{$endif};
    property BladeLength: Single read FBladeLength write SetBladeLength {$ifdef FPC}default 1.20{$endif};
    property UvScrollSpeed: Single read FUvScrollSpeed write FUvScrollSpeed {$ifdef FPC}default 2.5{$endif};
    property Emitting: Boolean read FEmitting write FEmitting default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

  { Recursive midpoint-displaced 3D arc-lightning beam emitter with seeded
    deterministic flicker and forked secondary tendrils. }
  TCastleLightningBeam = class(TCastleTransform)
  private
    FTargetTransformName: String;
    FEndOffsetX: Single;
    FEndOffsetY: Single;
    FEndOffsetZ: Single;
    FSubdivisionDepth: Integer;
    FJitterAmplitude: Single;
    FBranchCount: Integer;
    FBoltThickness: Single;
    FReseedIntervalSec: Single;
    FRandomSeed: Integer;
    FBoltColorRGB: TVector3;
    FFlickerAccumSec: Single;

    FSegments: array of TLightningSegment;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    FTotalBoltTriangles: Integer;
    FMaxLateralDisplacement: Single;
    FBoltStartWorld: TVector3;
    FBoltEndWorld: TVector3;

    procedure SetSubdivisionDepth(const AValue: Integer);
    procedure SetJitterAmplitude(const AValue: Single);
    procedure SetBranchCount(const AValue: Integer);
    procedure SetBoltThickness(const AValue: Single);
    procedure EnsureTransientBoltScene;
    function ResolveTargetWorldPos: TVector3;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Deterministically generate the main midpoint-displaced lightning chain
      plus forked branches between AStartWorld and AEndWorld. }
    procedure RebuildLightningBolt(const AStartWorld, AEndWorld: TVector3;
      const ASeed: Integer);

    { Convenience rebuild resolving Start from WorldTranslation and End from
      TargetTransformName (or EndOffset). }
    procedure StrikeNow(const ANewSeed: Integer = -1);

    function MainSegmentCount: Integer;
    function TotalSegmentCount: Integer;
    function GetSegment(const AIndex: Integer): TLightningSegment;
    function LightningSummaryBadge: String;

    property TotalBoltTriangles: Integer read FTotalBoltTriangles;
    property MaxLateralDisplacement: Single read FMaxLateralDisplacement;
    property BoltStartWorld: TVector3 read FBoltStartWorld;
    property BoltEndWorld: TVector3 read FBoltEndWorld;
    property BoltColorRGB: TVector3 read FBoltColorRGB write FBoltColorRGB;
  published
    property TargetTransformName: String read FTargetTransformName write FTargetTransformName;
    property EndOffsetX: Single read FEndOffsetX write FEndOffsetX {$ifdef FPC}default 0.0{$endif};
    property EndOffsetY: Single read FEndOffsetY write FEndOffsetY {$ifdef FPC}default 0.0{$endif};
    property EndOffsetZ: Single read FEndOffsetZ write FEndOffsetZ {$ifdef FPC}default -8.5{$endif};
    property SubdivisionDepth: Integer read FSubdivisionDepth write SetSubdivisionDepth default 4;
    property JitterAmplitude: Single read FJitterAmplitude write SetJitterAmplitude {$ifdef FPC}default 0.75{$endif};
    property BranchCount: Integer read FBranchCount write SetBranchCount default 3;
    property BoltThickness: Single read FBoltThickness write SetBoltThickness {$ifdef FPC}default 0.10{$endif};
    property ReseedIntervalSec: Single read FReseedIntervalSec write FReseedIntervalSec {$ifdef FPC}default 0.07{$endif};
    property RandomSeed: Integer read FRandomSeed write FRandomSeed default 1337;
  end;

{ Standard Catmull-Rom spline evaluation between P1 (T = 0) and P2 (T = 1)
  using P0 and P3 for C1 tangent continuity. }
function EvaluateCatmullRomVec3(const P0, P1, P2, P3: TVector3; const T: Single): TVector3;
function RibbonPresetToDisplayName(const APreset: TRibbonTrailPreset): String;

implementation

uses
  fpjson, jsonparser,
  CastleComponentSerialize;

function EvaluateCatmullRomVec3(const P0, P1, P2, P3: TVector3; const T: Single): TVector3;
var
  T2, T3: Single;
begin
  T2 := T * T;
  T3 := T2 * T;
  Result := 0.5 * (
    (2.0 * P1) +
    (-P0 + P2) * T +
    (2.0 * P0 - 5.0 * P1 + 4.0 * P2 - P3) * T2 +
    (-P0 + 3.0 * P1 - 3.0 * P2 + P3) * T3
  );
end;

function RibbonPresetToDisplayName(const APreset: TRibbonTrailPreset): String;
begin
  case APreset of
    rtpKatanaSunfireSlash: Result := 'Katana Sunfire Slash';
    rtpArcaneProjectileComet: Result := 'Arcane Projectile Comet';
    rtpCyberNeonDriftTrail: Result := 'Cyber Neon Drift Trail';
  end;
end;

{$PUSH}{$Q-}{$R-}
function NextXorShiftUnitSigned(var State: Cardinal): Single;
begin
  if State = 0 then
    State := 2463534242;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := ( (State and $FFFF) / 32767.5 ) - 1.0;
end;
{$POP}

{ TCastleRibbonTrail --------------------------------------------------------- }

constructor TCastleRibbonTrail.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTrailMode := rtmDualSocketBladeArc;
  FLifetimeSec := 0.45;
  FMaxSamples := 48;
  FCatmullSubdivisions := 3;
  FStartWidth := 0.55;
  FEndWidth := 0.04;
  FBladeHiltOffset := 0.20;
  FBladeLength := 1.20;
  FUvScrollSpeed := 2.5;
  FEmitting := True;
  ApplyPreset(rtpKatanaSunfireSlash);
end;

destructor TCastleRibbonTrail.Destroy;
begin
  FreeAndNil(FTransientScene);
  SetLength(FSamples, 0);
  inherited Destroy;
end;

function TCastleRibbonTrail.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'TrailMode', 'Preset', 'LifetimeSec', 'MaxSamples',
       'CatmullSubdivisions', 'StartWidth', 'EndWidth',
       'BladeHiltOffset', 'BladeLength', 'UvScrollSpeed',
       'Emitting', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleRibbonTrail.ApplyPreset(const APreset: TRibbonTrailPreset);
begin
  FPreset := APreset;
  case APreset of
    rtpKatanaSunfireSlash:
      begin
        FTrailMode := rtmDualSocketBladeArc;
        FHeadColorRGB := Vector3(1.00, 0.86, 0.32);
        FTailColorRGB := Vector3(0.92, 0.18, 0.04);
      end;
    rtpArcaneProjectileComet:
      begin
        FTrailMode := rtmSinglePointWidthTaper;
        FHeadColorRGB := Vector3(0.45, 0.88, 1.00);
        FTailColorRGB := Vector3(0.24, 0.12, 0.72);
      end;
    rtpCyberNeonDriftTrail:
      begin
        FTrailMode := rtmSinglePointWidthTaper;
        FHeadColorRGB := Vector3(1.00, 0.24, 0.86);
        FTailColorRGB := Vector3(0.10, 0.92, 0.88);
      end;
  end;
  if FSampleCount >= 2 then
    RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.SetPreset(const AValue: TRibbonTrailPreset);
begin
  if FPreset = AValue then
    Exit;
  ApplyPreset(AValue);
end;

procedure TCastleRibbonTrail.SetLifetimeSec(const AValue: Single);
begin
  FLifetimeSec := Max(0.05, AValue);
end;

procedure TCastleRibbonTrail.SetMaxSamples(const AValue: Integer);
begin
  FMaxSamples := EnsureRange(AValue, 4, 512);
end;

procedure TCastleRibbonTrail.SetCatmullSubdivisions(const AValue: Integer);
begin
  FCatmullSubdivisions := EnsureRange(AValue, 1, 8);
  if FSampleCount >= 2 then
    RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.SetStartWidth(const AValue: Single);
begin
  FStartWidth := Max(0.01, AValue);
  if FSampleCount >= 2 then
    RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.SetEndWidth(const AValue: Single);
begin
  FEndWidth := Max(0.0, AValue);
  if FSampleCount >= 2 then
    RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.SetBladeLength(const AValue: Single);
begin
  FBladeLength := Max(0.05, AValue);
end;

procedure TCastleRibbonTrail.ClearTrail;
begin
  FSampleCount := 0;
  FGeneratedTriangleCount := 0;
  FTotalArcLengthMeters := 0.0;
  if FCoordNode <> nil then
  begin
    FCoordNode.FdPoint.Count := 0;
    FCoordNode.FdPoint.Changed;
  end;
  if FColorNode <> nil then
  begin
    FColorNode.FdColor.Count := 0;
    FColorNode.FdColor.Changed;
  end;
  if FTexCoordNode <> nil then
  begin
    FTexCoordNode.FdPoint.Count := 0;
    FTexCoordNode.FdPoint.Changed;
  end;
end;

procedure TCastleRibbonTrail.EnsureTransientRibbonScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then
    Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientRibbonMesh';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(1, 1, 1);
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  FTexCoordNode := TTextureCoordinateNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  TriSet.TexCoord := FTexCoordNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);

  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleRibbonTrail.PushSamplePair(const ABase, ATip: TVector3);
var
  I: Integer;
  S: TRibbonSample;
begin
  if Length(FSamples) < FMaxSamples then
    SetLength(FSamples, FMaxSamples);

  { Index 0 = newest head sample; shift older samples toward tail }
  if FSampleCount < FMaxSamples then
    Inc(FSampleCount);
  for I := FSampleCount - 1 downto 1 do
    FSamples[I] := FSamples[I - 1];

  S := Default(TRibbonSample);
  S.PosBase := ABase;
  S.PosTip := ATip;
  S.CenterPos := 0.5 * (ABase + ATip);
  S.AgeSec := 0.0;
  FSamples[0] := S;
end;

procedure TCastleRibbonTrail.RecordBladeSampleWorld(
  const AHiltWorld, ATipWorld: TVector3);
begin
  PushSamplePair(AHiltWorld, ATipWorld);
  RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.RecordPointSampleWorld(const ACenterWorld: TVector3);
begin
  PushSamplePair(ACenterWorld, ACenterWorld + Vector3(0, FStartWidth, 0));
  RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.RebuildRibbonMesh;
var
  TotalKnots, SegIdx, SubIdx, K, TotalRows: Integer;
  RowBase, RowTip: array of TVector3;
  RowAgeRatio: array of Single;
  I0, I1, I2, I3: Integer;
  T, AgeR, HalfW, Fade, U0, U1: Single;
  C0, C1, Tangent, SideDir, Col0, Col1: TVector3;
  InvWorld: TMatrix4;
  Verts, Colors: TVector3List;
  UVs: TVector2List;
begin
  EnsureTransientRibbonScene;
  if FSampleCount < 2 then
  begin
    FGeneratedTriangleCount := 0;
    FTotalArcLengthMeters := 0.0;
    FCoordNode.FdPoint.Count := 0;
    FCoordNode.FdPoint.Changed;
    FColorNode.FdColor.Count := 0;
    FColorNode.FdColor.Changed;
    FTexCoordNode.FdPoint.Count := 0;
    FTexCoordNode.FdPoint.Changed;
    Exit;
  end;

  TotalRows := (FSampleCount - 1) * FCatmullSubdivisions + 1;
  SetLength(RowBase, TotalRows);
  SetLength(RowTip, TotalRows);
  SetLength(RowAgeRatio, TotalRows);

  K := 0;
  for SegIdx := 0 to FSampleCount - 2 do
  begin
    I0 := Max(0, SegIdx - 1);
    I1 := SegIdx;
    I2 := SegIdx + 1;
    I3 := Min(FSampleCount - 1, SegIdx + 2);
    for SubIdx := 0 to FCatmullSubdivisions - 1 do
    begin
      T := SubIdx / Single(FCatmullSubdivisions);
      if FTrailMode = rtmDualSocketBladeArc then
      begin
        RowBase[K] := EvaluateCatmullRomVec3(
          FSamples[I0].PosBase, FSamples[I1].PosBase, FSamples[I2].PosBase, FSamples[I3].PosBase, T);
        RowTip[K] := EvaluateCatmullRomVec3(
          FSamples[I0].PosTip, FSamples[I1].PosTip, FSamples[I2].PosTip, FSamples[I3].PosTip, T);
      end else
      begin
        C0 := EvaluateCatmullRomVec3(
          FSamples[I0].CenterPos, FSamples[I1].CenterPos, FSamples[I2].CenterPos, FSamples[I3].CenterPos, T);
        RowBase[K] := C0;
        RowTip[K] := C0;
      end;
      AgeR := Lerp(T, FSamples[I1].AgeSec, FSamples[I2].AgeSec) / Max(0.01, FLifetimeSec);
      RowAgeRatio[K] := EnsureRange(AgeR, 0.0, 1.0);
      Inc(K);
    end;
  end;

  { Final tail row }
  RowBase[TotalRows - 1] := FSamples[FSampleCount - 1].PosBase;
  RowTip[TotalRows - 1] := FSamples[FSampleCount - 1].PosTip;
  RowAgeRatio[TotalRows - 1] := EnsureRange(FSamples[FSampleCount - 1].AgeSec / Max(0.01, FLifetimeSec), 0.0, 1.0);

  { If single-point taper mode, expand RowBase / RowTip around Center along cross(Tangent, Up) }
  if FTrailMode = rtmSinglePointWidthTaper then
  begin
    for TotalKnots := 0 to TotalRows - 1 do
    begin
      C0 := RowBase[TotalKnots];
      if TotalKnots < TotalRows - 1 then
        Tangent := RowBase[TotalKnots + 1] - C0
      else
        Tangent := C0 - RowBase[TotalKnots - 1];
      if Tangent.LengthSqr < 1e-6 then
        SideDir := Vector3(0, 1, 0)
      else
      begin
        SideDir := TVector3.CrossProduct(Tangent.Normalize, Vector3(0, 1, 0));
        if SideDir.LengthSqr < 1e-4 then
          SideDir := Vector3(1, 0, 0)
        else
          SideDir := SideDir.Normalize;
      end;
      HalfW := 0.5 * Lerp(RowAgeRatio[TotalKnots], FStartWidth, FEndWidth);
      RowBase[TotalKnots] := C0 - SideDir * HalfW;
      RowTip[TotalKnots] := C0 + SideDir * HalfW;
    end;
  end else
  begin
    { Apply EndWidth / StartWidth blade taper toward tail while keeping tip edge crisp }
    for TotalKnots := 0 to TotalRows - 1 do
    begin
      Fade := Lerp(RowAgeRatio[TotalKnots], 1.0, EnsureRange(FEndWidth / Max(0.01, FStartWidth), 0.05, 1.0));
      RowBase[TotalKnots] := Lerp(Fade, RowTip[TotalKnots], RowBase[TotalKnots]);
    end;
  end;

  { Transform world-space vertices into Self local space so child FTransientScene aligns }
  if (not HasParent) or (not WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  FTotalArcLengthMeters := 0.0;
  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  UVs := TVector2List.Create;
  try
    Verts.Capacity := (TotalRows - 1) * 6;
    Colors.Capacity := (TotalRows - 1) * 6;
    UVs.Capacity := (TotalRows - 1) * 6;

    for K := 0 to TotalRows - 2 do
    begin
      C0 := 0.5 * (RowBase[K] + RowTip[K]);
      C1 := 0.5 * (RowBase[K + 1] + RowTip[K + 1]);
      FTotalArcLengthMeters := FTotalArcLengthMeters + PointsDistance(C0, C1);

      Fade := 1.0 - RowAgeRatio[K];
      Col0 := Lerp(RowAgeRatio[K], FHeadColorRGB, FTailColorRGB) * Fade;
      Fade := 1.0 - RowAgeRatio[K + 1];
      Col1 := Lerp(RowAgeRatio[K + 1], FHeadColorRGB, FTailColorRGB) * Fade;

      U0 := (K / Single(Max(1, TotalRows - 1))) - FUvScrollPhase;
      U1 := ((K + 1) / Single(Max(1, TotalRows - 1))) - FUvScrollPhase;

      Verts.Add(InvWorld.MultPoint(RowBase[K]));
      Verts.Add(InvWorld.MultPoint(RowTip[K]));
      Verts.Add(InvWorld.MultPoint(RowTip[K + 1]));
      Colors.Add(Col0); Colors.Add(Col0); Colors.Add(Col1);
      UVs.Add(Vector2(U0, 0.0)); UVs.Add(Vector2(U0, 1.0)); UVs.Add(Vector2(U1, 1.0));

      Verts.Add(InvWorld.MultPoint(RowBase[K]));
      Verts.Add(InvWorld.MultPoint(RowTip[K + 1]));
      Verts.Add(InvWorld.MultPoint(RowBase[K + 1]));
      Colors.Add(Col0); Colors.Add(Col1); Colors.Add(Col1);
      UVs.Add(Vector2(U0, 0.0)); UVs.Add(Vector2(U1, 1.0)); UVs.Add(Vector2(U1, 0.0));
    end;

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
    FTexCoordNode.SetPoint(UVs);
    FTexCoordNode.FdPoint.Changed;
    FGeneratedTriangleCount := Verts.Count div 3;
  finally
    FreeAndNil(UVs);
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

procedure TCastleRibbonTrail.StepTrail(const Dt: Single;
  const AAutoSampleTransform: Boolean);
var
  I, WriteIdx: Integer;
  WT: TMatrix4;
  HiltW, TipW: TVector3;
begin
  if Dt <= 0.0 then
    Exit;
  FUvScrollPhase := Frac(FUvScrollPhase + Dt * FUvScrollSpeed);

  WriteIdx := 0;
  for I := 0 to FSampleCount - 1 do
  begin
    FSamples[I].AgeSec := FSamples[I].AgeSec + Dt;
    if FSamples[I].AgeSec < FLifetimeSec then
    begin
      if WriteIdx <> I then
        FSamples[WriteIdx] := FSamples[I];
      Inc(WriteIdx);
    end;
  end;
  FSampleCount := WriteIdx;

  if FEmitting and AAutoSampleTransform then
  begin
    WT := WorldTransform;
    HiltW := WT.MultPoint(Vector3(0.0, FBladeHiltOffset, 0.0));
    TipW := WT.MultPoint(Vector3(0.0, FBladeHiltOffset + FBladeLength, 0.0));
    if (FSampleCount = 0) or
       (PointsDistance(TipW, FSamples[0].PosTip) > 0.02) or
       (PointsDistance(HiltW, FSamples[0].PosBase) > 0.02) then
      PushSamplePair(HiltW, TipW);
  end;

  RebuildRibbonMesh;
end;

procedure TCastleRibbonTrail.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  StepTrail(Min(SecondsPassed, 0.1), True);
end;

function TCastleRibbonTrail.ActiveSampleCount: Integer;
begin
  Result := FSampleCount;
end;

function TCastleRibbonTrail.GetSample(const AIndex: Integer): TRibbonSample;
begin
  if (AIndex >= 0) and (AIndex < FSampleCount) then
    Result := FSamples[AIndex]
  else
    Result := Default(TRibbonSample);
end;

function TCastleRibbonTrail.RibbonSummaryBadge: String;
begin
  Result := Format('[Ribbon:%s %d smp %d tris]', [
    RibbonPresetToDisplayName(FPreset),
    FSampleCount,
    FGeneratedTriangleCount
  ]);
end;

function TCastleRibbonTrail.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('headR', FHeadColorRGB.X);
    Obj.Add('headG', FHeadColorRGB.Y);
    Obj.Add('headB', FHeadColorRGB.Z);
    Obj.Add('tailR', FTailColorRGB.X);
    Obj.Add('tailG', FTailColorRGB.Y);
    Obj.Add('tailB', FTailColorRGB.Z);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleRibbonTrail.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
begin
  if Trim(AValue) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      FHeadColorRGB := Vector3(
        Obj.Get('headR', FHeadColorRGB.X),
        Obj.Get('headG', FHeadColorRGB.Y),
        Obj.Get('headB', FHeadColorRGB.Z));
      FTailColorRGB := Vector3(
        Obj.Get('tailR', FTailColorRGB.X),
        Obj.Get('tailG', FTailColorRGB.Y),
        Obj.Get('tailB', FTailColorRGB.Z));
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleLightningBeam ------------------------------------------------------- }

constructor TCastleLightningBeam.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEndOffsetX := 0.0;
  FEndOffsetY := 0.0;
  FEndOffsetZ := -8.5;
  FSubdivisionDepth := 4;
  FJitterAmplitude := 0.75;
  FBranchCount := 3;
  FBoltThickness := 0.10;
  FReseedIntervalSec := 0.07;
  FRandomSeed := 1337;
  FBoltColorRGB := Vector3(0.56, 0.86, 1.00);
end;

destructor TCastleLightningBeam.Destroy;
begin
  FreeAndNil(FTransientScene);
  SetLength(FSegments, 0);
  inherited Destroy;
end;

function TCastleLightningBeam.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'TargetTransformName', 'EndOffsetX', 'EndOffsetY', 'EndOffsetZ',
       'SubdivisionDepth', 'JitterAmplitude', 'BranchCount',
       'BoltThickness', 'ReseedIntervalSec', 'RandomSeed'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLightningBeam.SetSubdivisionDepth(const AValue: Integer);
begin
  FSubdivisionDepth := EnsureRange(AValue, 1, 6);
end;

procedure TCastleLightningBeam.SetJitterAmplitude(const AValue: Single);
begin
  FJitterAmplitude := Max(0.0, AValue);
end;

procedure TCastleLightningBeam.SetBranchCount(const AValue: Integer);
begin
  FBranchCount := EnsureRange(AValue, 0, 8);
end;

procedure TCastleLightningBeam.SetBoltThickness(const AValue: Single);
begin
  FBoltThickness := Max(0.01, AValue);
end;

procedure TCastleLightningBeam.EnsureTransientBoltScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then
    Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientLightningMesh';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(1, 1, 1);
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

function TCastleLightningBeam.ResolveTargetWorldPos: TVector3;
var
  Comp: TComponent;
begin
  if (FTargetTransformName <> '') and (Owner <> nil) then
  begin
    Comp := Owner.FindComponent(FTargetTransformName);
    if Comp is TCastleTransform then
      Exit(TCastleTransform(Comp).WorldTranslation);
  end;
  Result := WorldTranslation + Vector3(FEndOffsetX, FEndOffsetY, FEndOffsetZ);
end;

procedure TCastleLightningBeam.RebuildLightningBolt(
  const AStartWorld, AEndWorld: TVector3; const ASeed: Integer);
var
  Rng: Cardinal;
  NMain, Level, StepSz, HalfSz, Idx, B, SrcIdx, SegOutIdx: Integer;
  Pts: array of TVector3;
  Chord, ChordDir, BasisU, BasisV, Mid, ForkMid, ForkEnd, SegDir, SideA, SideB: TVector3;
  ScaleAmp, DistLine, HalfT: Single;
  InvWorld: TMatrix4;
  Verts, Colors: TVector3List;
  CoreCol, ForkCol: TVector3;

  procedure AddQuadWorld(const P0, P1, AxisOffset, Col: TVector3);
  begin
    Verts.Add(InvWorld.MultPoint(P0 - AxisOffset));
    Verts.Add(InvWorld.MultPoint(P0 + AxisOffset));
    Verts.Add(InvWorld.MultPoint(P1 + AxisOffset));
    Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);

    Verts.Add(InvWorld.MultPoint(P0 - AxisOffset));
    Verts.Add(InvWorld.MultPoint(P1 + AxisOffset));
    Verts.Add(InvWorld.MultPoint(P1 - AxisOffset));
    Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);
  end;

begin
  EnsureTransientBoltScene;
  FBoltStartWorld := AStartWorld;
  FBoltEndWorld := AEndWorld;
  FRandomSeed := ASeed;
  {$PUSH}{$Q-}{$R-}
  Rng := Cardinal((UInt64(Cardinal(Abs(ASeed))) * UInt64(747796405) + UInt64(2891336453)) and $FFFFFFFF);
  {$POP}

  Chord := AEndWorld - AStartWorld;
  if Chord.LengthSqr < 1e-6 then
    ChordDir := Vector3(0, 0, -1)
  else
    ChordDir := Chord.Normalize;

  BasisU := TVector3.CrossProduct(ChordDir, Vector3(0, 1, 0));
  if BasisU.LengthSqr < 1e-4 then
    BasisU := TVector3.CrossProduct(ChordDir, Vector3(1, 0, 0));
  BasisU := BasisU.Normalize;
  BasisV := TVector3.CrossProduct(ChordDir, BasisU).Normalize;

  NMain := 1 shl FSubdivisionDepth;
  SetLength(Pts, NMain + 1);
  Pts[0] := AStartWorld;
  Pts[NMain] := AEndWorld;

  StepSz := NMain;
  ScaleAmp := FJitterAmplitude;
  for Level := 1 to FSubdivisionDepth do
  begin
    HalfSz := StepSz div 2;
    Idx := HalfSz;
    while Idx < NMain do
    begin
      Mid := 0.5 * (Pts[Idx - HalfSz] + Pts[Idx + HalfSz]);
      Mid := Mid
        + BasisU * (NextXorShiftUnitSigned(Rng) * ScaleAmp)
        + BasisV * (NextXorShiftUnitSigned(Rng) * ScaleAmp);
      Pts[Idx] := Mid;
      Inc(Idx, StepSz);
    end;
    StepSz := HalfSz;
    ScaleAmp := ScaleAmp * 0.52;
  end;

  { Measure max lateral displacement from straight chord & emit segments }
  FMaxLateralDisplacement := 0.0;
  for Idx := 1 to NMain - 1 do
  begin
    DistLine := TVector3.CrossProduct(Pts[Idx] - AStartWorld, ChordDir).Length;
    if DistLine > FMaxLateralDisplacement then
      FMaxLateralDisplacement := DistLine;
  end;

  SetLength(FSegments, NMain + FBranchCount * 2);
  SegOutIdx := 0;
  for Idx := 0 to NMain - 1 do
  begin
    FSegments[SegOutIdx] := Default(TLightningSegment);
    FSegments[SegOutIdx].A := Pts[Idx];
    FSegments[SegOutIdx].B := Pts[Idx + 1];
    FSegments[SegOutIdx].Thickness := FBoltThickness;
    FSegments[SegOutIdx].IsFork := False;
    Inc(SegOutIdx);
  end;

  { Add 2-segment forked lightning tendrils off interior vertices }
  for B := 0 to FBranchCount - 1 do
  begin
    SrcIdx := EnsureRange(((B + 1) * NMain) div (FBranchCount + 2), 1, NMain - 1);
    ForkEnd := Pts[SrcIdx]
      + ChordDir * (Chord.Length * 0.22)
      + BasisU * (NextXorShiftUnitSigned(Rng) * Max(0.35, FJitterAmplitude * 1.15))
      + BasisV * (NextXorShiftUnitSigned(Rng) * Max(0.35, FJitterAmplitude * 1.15));
    ForkMid := 0.5 * (Pts[SrcIdx] + ForkEnd)
      + BasisU * (NextXorShiftUnitSigned(Rng) * Max(0.15, FJitterAmplitude * 0.45));

    FSegments[SegOutIdx] := Default(TLightningSegment);
    FSegments[SegOutIdx].A := Pts[SrcIdx];
    FSegments[SegOutIdx].B := ForkMid;
    FSegments[SegOutIdx].Thickness := FBoltThickness * 0.45;
    FSegments[SegOutIdx].IsFork := True;
    Inc(SegOutIdx);

    FSegments[SegOutIdx] := Default(TLightningSegment);
    FSegments[SegOutIdx].A := ForkMid;
    FSegments[SegOutIdx].B := ForkEnd;
    FSegments[SegOutIdx].Thickness := FBoltThickness * 0.28;
    FSegments[SegOutIdx].IsFork := True;
    Inc(SegOutIdx);
  end;
  SetLength(FSegments, SegOutIdx);

  if (not HasParent) or (not WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    Verts.Capacity := Length(FSegments) * 12;
    Colors.Capacity := Length(FSegments) * 12;
    CoreCol := FBoltColorRGB;
    ForkCol := FBoltColorRGB * 0.72;
    for Idx := 0 to High(FSegments) do
    begin
      SegDir := FSegments[Idx].B - FSegments[Idx].A;
      if SegDir.LengthSqr < 1e-6 then
        Continue;
      SegDir := SegDir.Normalize;
      SideA := TVector3.CrossProduct(SegDir, Vector3(0, 1, 0));
      if SideA.LengthSqr < 1e-4 then
        SideA := TVector3.CrossProduct(SegDir, Vector3(1, 0, 0));
      SideA := SideA.Normalize;
      SideB := TVector3.CrossProduct(SegDir, SideA).Normalize;
      HalfT := 0.5 * FSegments[Idx].Thickness;

      if FSegments[Idx].IsFork then
      begin
        AddQuadWorld(FSegments[Idx].A, FSegments[Idx].B, SideA * HalfT, ForkCol);
        AddQuadWorld(FSegments[Idx].A, FSegments[Idx].B, SideB * HalfT, ForkCol);
      end else
      begin
        AddQuadWorld(FSegments[Idx].A, FSegments[Idx].B, SideA * HalfT, CoreCol);
        AddQuadWorld(FSegments[Idx].A, FSegments[Idx].B, SideB * HalfT, CoreCol);
      end;
    end;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
    FTotalBoltTriangles := Verts.Count div 3;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

procedure TCastleLightningBeam.StrikeNow(const ANewSeed: Integer);
var
  UseSeed: Integer;
begin
  if ANewSeed >= 0 then
    UseSeed := ANewSeed
  else
    UseSeed := FRandomSeed;
  RebuildLightningBolt(WorldTranslation, ResolveTargetWorldPos, UseSeed);
end;

procedure TCastleLightningBeam.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  FFlickerAccumSec := FFlickerAccumSec + SecondsPassed;
  if (FReseedIntervalSec > 0.0) and (FFlickerAccumSec >= FReseedIntervalSec) then
  begin
    FFlickerAccumSec := 0.0;
    StrikeNow(FRandomSeed + 1);
  end;
end;

function TCastleLightningBeam.MainSegmentCount: Integer;
begin
  Result := 1 shl FSubdivisionDepth;
end;

function TCastleLightningBeam.TotalSegmentCount: Integer;
begin
  Result := Length(FSegments);
end;

function TCastleLightningBeam.GetSegment(const AIndex: Integer): TLightningSegment;
begin
  if (AIndex >= 0) and (AIndex <= High(FSegments)) then
    Result := FSegments[AIndex]
  else
    Result := Default(TLightningSegment);
end;

function TCastleLightningBeam.LightningSummaryBadge: String;
begin
  Result := Format('[Lightning:Depth=%d Forks=%d %d tris]', [
    FSubdivisionDepth, FBranchCount, FTotalBoltTriangles
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleRibbonTrail,
    ['VFX & Particles', 'Ribbon Slash & Trail VFX (TCastleRibbonTrail)']);
  RegisterSerializableComponent(TCastleLightningBeam,
    ['VFX & Particles', 'Arc Lightning Beam VFX (TCastleLightningBeam)']);

end.
