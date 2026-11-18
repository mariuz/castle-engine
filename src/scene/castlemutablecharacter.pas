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

{ Mutable-style Modular Character Customizer with slot mutual-exclusion rules,
  parametric body proportion morph sliders, single-draw-call mesh merging,
  and compact shareable recipe codes (Phase 360 — UE UCustomizableObject). }
unit CastleMutableCharacter;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Built-in modular RPG character archetype presets. }
  TMutableArchetypePreset = (
    mapCustom,
    mapPaladinPlateKnight,
    mapRangerHoodedScout,
    mapArcaneBattleMage
  );

  { Modular character customizer matching Unreal Engine 6.0+ Mutable
    (UCustomizableObject) with helm-vs-hair anti-clipping exclusion,
    parametric height/shoulder/build morphs, and 1-draw-call merged mesh output. }
  TCastleMutableCharacter = class(TCastleTransform)
  private
    FPreset: TMutableArchetypePreset;
    FHeadgearSlot: Integer;
    FHairStyleSlot: Integer;
    FTorsoArmorSlot: Integer;
    FCapeBackSlot: Integer;
    FWeaponHandSlot: Integer;
    FHeightScale: Single;
    FShoulderBulkMorph: Single;
    FBuildMuscularityMorph: Single;
    FPrimaryArmorRGB: TVector3;
    FAccentTrimRGB: TVector3;
    FHairColorRGB: TVector3;
    FShowMergedMesh: Boolean;
    FMergedPartCount: Integer;
    FGeneratedTriangleCount: Integer;
    FTotalBoundsHeightMeters: Single;
    FShoulderSpanMeters: Single;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TMutableArchetypePreset);
    procedure SetHeadgearSlot(const AValue: Integer);
    procedure SetHairStyleSlot(const AValue: Integer);
    procedure SetTorsoArmorSlot(const AValue: Integer);
    procedure SetCapeBackSlot(const AValue: Integer);
    procedure SetWeaponHandSlot(const AValue: Integer);
    procedure SetHeightScale(const AValue: Single);
    procedure SetShoulderBulkMorph(const AValue: Single);
    procedure SetBuildMuscularityMorph(const AValue: Single);
    procedure SetShowMergedMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetValuesOnly(const APreset: TMutableArchetypePreset);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function IsHairAutoHiddenByHelm: Boolean;
    function ExportRecipeCode: String;
    function ImportRecipeCode(const ACode: String): Boolean;
    procedure RandomizeCharacter(const ASeed: Integer);
    procedure RebuildMergedCharacterMesh;
    function MutableSummaryBadge: String;
    property MergedPartCount: Integer read FMergedPartCount;
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
    property TotalBoundsHeightMeters: Single read FTotalBoundsHeightMeters;
    property ShoulderSpanMeters: Single read FShoulderSpanMeters;
    property PrimaryArmorRGB: TVector3 read FPrimaryArmorRGB write FPrimaryArmorRGB;
    property AccentTrimRGB: TVector3 read FAccentTrimRGB write FAccentTrimRGB;
  published
    property Preset: TMutableArchetypePreset read FPreset write SetPreset default mapPaladinPlateKnight;
    property HeadgearSlot: Integer read FHeadgearSlot write SetHeadgearSlot default 1;
    property HairStyleSlot: Integer read FHairStyleSlot write SetHairStyleSlot default 1;
    property TorsoArmorSlot: Integer read FTorsoArmorSlot write SetTorsoArmorSlot default 1;
    property CapeBackSlot: Integer read FCapeBackSlot write SetCapeBackSlot default 1;
    property WeaponHandSlot: Integer read FWeaponHandSlot write SetWeaponHandSlot default 1;
    property HeightScale: Single read FHeightScale write SetHeightScale {$ifdef FPC}default 1.00{$endif};
    property ShoulderBulkMorph: Single read FShoulderBulkMorph write SetShoulderBulkMorph {$ifdef FPC}default 0.70{$endif};
    property BuildMuscularityMorph: Single read FBuildMuscularityMorph write SetBuildMuscularityMorph {$ifdef FPC}default 0.65{$endif};
    property ShowMergedMesh: Boolean read FShowMergedMesh write SetShowMergedMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function MutablePresetToString(const APreset: TMutableArchetypePreset): String;

implementation

uses StrUtils, fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function MutablePresetToString(const APreset: TMutableArchetypePreset): String;
begin
  case APreset of
    mapCustom: Result := 'Custom Modular Hero';
    mapPaladinPlateKnight: Result := 'Paladin Full-Plate Knight';
    mapRangerHoodedScout: Result := 'Ranger Hooded Woodland Scout';
    mapArcaneBattleMage: Result := 'Arcane Circlet Battle-Mage';
  end;
end;

function RGBToHex6(const C: TVector3): String;
begin
  Result := Format('%.2X%.2X%.2X', [
    EnsureRange(Round(C.X * 255), 0, 255),
    EnsureRange(Round(C.Y * 255), 0, 255),
    EnsureRange(Round(C.Z * 255), 0, 255)]);
end;

function Hex6ToRGB(const S: String; const Fallback: TVector3): TVector3;
var
  V: Integer;
begin
  if Length(S) <> 6 then Exit(Fallback);
  V := StrToIntDef('$' + S, -1);
  if V < 0 then Exit(Fallback);
  Result := Vector3(((V shr 16) and $FF) / 255.0,
                    ((V shr 8) and $FF) / 255.0,
                    (V and $FF) / 255.0);
end;

{ TCastleMutableCharacter ---------------------------------------------------- }

constructor TCastleMutableCharacter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := mapPaladinPlateKnight;
  FShowMergedMesh := True;
  FHairColorRGB := Vector3(0.42, 0.26, 0.14);
  ApplyPresetValuesOnly(mapPaladinPlateKnight);
  RebuildMergedCharacterMesh;
end;

destructor TCastleMutableCharacter.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleMutableCharacter.ApplyPresetValuesOnly(const APreset: TMutableArchetypePreset);
begin
  case APreset of
    mapPaladinPlateKnight, mapCustom:
      begin
        { Headgear 1 = Closed Greathelm -> auto-excludes HairStyleSlot 1! }
        FHeadgearSlot := 1;
        FHairStyleSlot := 1;
        FTorsoArmorSlot := 1;
        FCapeBackSlot := 1;
        FWeaponHandSlot := 1;
        FHeightScale := 1.00;
        FShoulderBulkMorph := 0.70;
        FBuildMuscularityMorph := 0.65;
        FPrimaryArmorRGB := Vector3(0.76, 0.80, 0.86);
        FAccentTrimRGB := Vector3(0.95, 0.76, 0.22);
        FHairColorRGB := Vector3(0.42, 0.26, 0.14);
      end;
    mapRangerHoodedScout:
      begin
        FHeadgearSlot := 2;
        FHairStyleSlot := 2;
        FTorsoArmorSlot := 2;
        FCapeBackSlot := 2;
        FWeaponHandSlot := 2;
        FHeightScale := 0.96;
        FShoulderBulkMorph := 0.35;
        FBuildMuscularityMorph := 0.45;
        FPrimaryArmorRGB := Vector3(0.24, 0.46, 0.28);
        FAccentTrimRGB := Vector3(0.56, 0.38, 0.20);
        FHairColorRGB := Vector3(0.20, 0.14, 0.10);
      end;
    mapArcaneBattleMage:
      begin
        { Headgear 3 = Open Circlet -> HairStyleSlot 2 remains visible! }
        FHeadgearSlot := 3;
        FHairStyleSlot := 2;
        FTorsoArmorSlot := 3;
        FCapeBackSlot := 1;
        FWeaponHandSlot := 3;
        FHeightScale := 1.04;
        FShoulderBulkMorph := 0.40;
        FBuildMuscularityMorph := 0.35;
        FPrimaryArmorRGB := Vector3(0.32, 0.22, 0.68);
        FAccentTrimRGB := Vector3(0.30, 0.86, 0.96);
        FHairColorRGB := Vector3(0.88, 0.90, 0.96);
      end;
  end;
end;

procedure TCastleMutableCharacter.SetPreset(const AValue: TMutableArchetypePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> mapCustom then
  begin
    ApplyPresetValuesOnly(AValue);
    RebuildMergedCharacterMesh;
  end;
end;

procedure TCastleMutableCharacter.SetHeadgearSlot(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 3);
  if FHeadgearSlot = V then Exit;
  FHeadgearSlot := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetHairStyleSlot(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 2);
  if FHairStyleSlot = V then Exit;
  FHairStyleSlot := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetTorsoArmorSlot(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 3);
  if FTorsoArmorSlot = V then Exit;
  FTorsoArmorSlot := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetCapeBackSlot(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 2);
  if FCapeBackSlot = V then Exit;
  FCapeBackSlot := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetWeaponHandSlot(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 3);
  if FWeaponHandSlot = V then Exit;
  FWeaponHandSlot := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetHeightScale(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.80, 1.25);
  if SameValue(FHeightScale, V, 1e-4) then Exit;
  FHeightScale := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetShoulderBulkMorph(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FShoulderBulkMorph, V, 1e-4) then Exit;
  FShoulderBulkMorph := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetBuildMuscularityMorph(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FBuildMuscularityMorph, V, 1e-4) then Exit;
  FBuildMuscularityMorph := V;
  FPreset := mapCustom;
  RebuildMergedCharacterMesh;
end;

procedure TCastleMutableCharacter.SetShowMergedMesh(const AValue: Boolean);
begin
  if FShowMergedMesh = AValue then Exit;
  FShowMergedMesh := AValue;
  if not FShowMergedMesh then
    ClearTransientScene
  else
    RebuildMergedCharacterMesh;
end;

function TCastleMutableCharacter.IsHairAutoHiddenByHelm: Boolean;
begin
  { Slot 1 = FullClosedGreathelm clips/hides hair completely so zero strands poke through! }
  Result := (FHeadgearSlot = 1) and (FHairStyleSlot > 0);
end;

function TCastleMutableCharacter.ExportRecipeCode: String;
begin
  Result := Format('MUT1:%d%d%d%d%d:%d:%d:%d:%s:%s', [
    FHeadgearSlot, FHairStyleSlot, FTorsoArmorSlot, FCapeBackSlot, FWeaponHandSlot,
    Round(FHeightScale * 100),
    Round(FShoulderBulkMorph * 100),
    Round(FBuildMuscularityMorph * 100),
    RGBToHex6(FPrimaryArmorRGB),
    RGBToHex6(FAccentTrimRGB)]);
end;

function TCastleMutableCharacter.ImportRecipeCode(const ACode: String): Boolean;
var
  Parts: TStringList;
  Slots: String;
begin
  Result := False;
  if Pos('MUT1:', ACode) <> 1 then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Trim(ACode);
    if Parts.Count < 7 then Exit;
    Slots := Parts[1];
    if Length(Slots) < 5 then Exit;

    FPreset := mapCustom;
    FHeadgearSlot := EnsureRange(Ord(Slots[1]) - Ord('0'), 0, 3);
    FHairStyleSlot := EnsureRange(Ord(Slots[2]) - Ord('0'), 0, 2);
    FTorsoArmorSlot := EnsureRange(Ord(Slots[3]) - Ord('0'), 0, 3);
    FCapeBackSlot := EnsureRange(Ord(Slots[4]) - Ord('0'), 0, 2);
    FWeaponHandSlot := EnsureRange(Ord(Slots[5]) - Ord('0'), 0, 3);
    FHeightScale := EnsureRange(StrToIntDef(Parts[2], 100) / 100.0, 0.80, 1.25);
    FShoulderBulkMorph := EnsureRange(StrToIntDef(Parts[3], 50) / 100.0, 0.0, 1.0);
    FBuildMuscularityMorph := EnsureRange(StrToIntDef(Parts[4], 50) / 100.0, 0.0, 1.0);
    FPrimaryArmorRGB := Hex6ToRGB(Parts[5], FPrimaryArmorRGB);
    FAccentTrimRGB := Hex6ToRGB(Parts[6], FAccentTrimRGB);
    RebuildMergedCharacterMesh;
    Result := True;
  finally
    FreeAndNil(Parts);
  end;
end;

{$PUSH}{$Q-}{$R-}
procedure TCastleMutableCharacter.RandomizeCharacter(const ASeed: Integer);
var
  S: Cardinal;

  function NextU: Single;
  begin
    S := S * 1664525 + 1013904223;
    Result := (S shr 8) / 16777216.0;
  end;

begin
  S := Cardinal(ASeed);
  FPreset := mapCustom;
  FHeadgearSlot := Trunc(NextU * 4.0) mod 4;
  FHairStyleSlot := Trunc(NextU * 3.0) mod 3;
  FTorsoArmorSlot := Trunc(NextU * 4.0) mod 4;
  FCapeBackSlot := Trunc(NextU * 3.0) mod 3;
  FWeaponHandSlot := Trunc(NextU * 4.0) mod 4;
  FHeightScale := 0.88 + NextU * 0.28;
  FShoulderBulkMorph := NextU;
  FBuildMuscularityMorph := NextU;
  FPrimaryArmorRGB := Vector3(0.2 + 0.7 * NextU, 0.2 + 0.7 * NextU, 0.2 + 0.7 * NextU);
  FAccentTrimRGB := Vector3(0.3 + 0.7 * NextU, 0.3 + 0.7 * NextU, 0.2 + 0.7 * NextU);
  RebuildMergedCharacterMesh;
end;
{$POP}

procedure TCastleMutableCharacter.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientMutableCharacterMesh';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := Vector3(1, 1, 1);
  Mat.Roughness := 0.40;
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

procedure TCastleMutableCharacter.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleMutableCharacter.RebuildMergedCharacterMesh;
var
  Verts, Cols: TVector3List;
  BuildW, ShoulderW, HScale: Single;

  procedure EmitBoxPart(const BoxCenter, BoxSize, Col: TVector3);
  var
    HX, HY, HZ: Single;
    C000, C100, C010, C110, C001, C101, C011, C111: TVector3;

    procedure EmitQuad(const A, B, C, D: TVector3);
    begin
      Verts.Add(A); Verts.Add(B); Verts.Add(C);
      Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
      Verts.Add(A); Verts.Add(C); Verts.Add(D);
      Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    end;

  begin
    Inc(FMergedPartCount);
    HX := BoxSize.X * 0.5;
    HY := BoxSize.Y * 0.5;
    HZ := BoxSize.Z * 0.5;
    C000 := BoxCenter + Vector3(-HX, -HY, -HZ);
    C100 := BoxCenter + Vector3( HX, -HY, -HZ);
    C010 := BoxCenter + Vector3(-HX,  HY, -HZ);
    C110 := BoxCenter + Vector3( HX,  HY, -HZ);
    C001 := BoxCenter + Vector3(-HX, -HY,  HZ);
    C101 := BoxCenter + Vector3( HX, -HY,  HZ);
    C011 := BoxCenter + Vector3(-HX,  HY,  HZ);
    C111 := BoxCenter + Vector3( HX,  HY,  HZ);

    EmitQuad(C001, C101, C111, C011);
    EmitQuad(C100, C000, C010, C110);
    EmitQuad(C011, C111, C110, C010);
    EmitQuad(C000, C100, C101, C001);
    EmitQuad(C101, C100, C110, C111);
    EmitQuad(C000, C001, C011, C010);
  end;

begin
  FMergedPartCount := 0;
  HScale := FHeightScale;
  BuildW := 0.42 + FBuildMuscularityMorph * 0.22;
  ShoulderW := BuildW + 0.16 + FShoulderBulkMorph * 0.36;
  FShoulderSpanMeters := ShoulderW;
  FTotalBoundsHeightMeters := 1.80 * HScale;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    { 1. Base Legs + Pelvis }
    EmitBoxPart(Vector3(-0.14, 0.42 * HScale, 0.0), Vector3(0.18 + 0.06 * FBuildMuscularityMorph, 0.84 * HScale, 0.20),
      FPrimaryArmorRGB * 0.72);
    EmitBoxPart(Vector3( 0.14, 0.42 * HScale, 0.0), Vector3(0.18 + 0.06 * FBuildMuscularityMorph, 0.84 * HScale, 0.20),
      FPrimaryArmorRGB * 0.72);

    { 2. Torso Armor Slot + Pauldron Shoulders }
    EmitBoxPart(Vector3(0.0, 1.14 * HScale, 0.0),
      Vector3(BuildW, 0.62 * HScale, 0.28 + 0.05 * FTorsoArmorSlot), FPrimaryArmorRGB);
    if FTorsoArmorSlot > 0 then
      EmitBoxPart(Vector3(0.0, 1.38 * HScale, 0.0),
        Vector3(ShoulderW, 0.18 * HScale, 0.30), FAccentTrimRGB);

    { 3. Head Base }
    EmitBoxPart(Vector3(0.0, 1.62 * HScale, 0.0), Vector3(0.28, 0.28 * HScale, 0.28),
      Vector3(0.88, 0.72, 0.60));

    { 4. Headgear Slot }
    if FHeadgearSlot = 1 then
    begin
      EmitBoxPart(Vector3(0.0, 1.65 * HScale, 0.0), Vector3(0.34, 0.34 * HScale, 0.34), FPrimaryArmorRGB);
      FTotalBoundsHeightMeters := 1.84 * HScale;
    end else
    if FHeadgearSlot = 2 then
      EmitBoxPart(Vector3(0.0, 1.67 * HScale, 0.02), Vector3(0.33, 0.32 * HScale, 0.33), FPrimaryArmorRGB * 0.85)
    else
    if FHeadgearSlot = 3 then
      EmitBoxPart(Vector3(0.0, 1.72 * HScale, 0.0), Vector3(0.31, 0.07 * HScale, 0.31), FAccentTrimRGB);

    { 5. Hair Style Slot (auto-hidden when HeadgearSlot = 1 Closed Greathelm!) }
    if (FHairStyleSlot > 0) and (not IsHairAutoHiddenByHelm) then
    begin
      if FHeadgearSlot = 2 then
        { Tucked under Ranger Hood }
        EmitBoxPart(Vector3(0.0, 1.54 * HScale, 0.14), Vector3(0.22, 0.16 * HScale, 0.10), FHairColorRGB)
      else
      begin
        EmitBoxPart(Vector3(0.0, 1.79 * HScale, 0.02),
          Vector3(0.30, (0.14 + 0.08 * FHairStyleSlot) * HScale, 0.30), FHairColorRGB);
        FTotalBoundsHeightMeters := (1.79 + 0.07 + 0.04 * FHairStyleSlot) * HScale;
      end;
    end;

    { 6. Cape / Quiver Back Slot }
    if FCapeBackSlot = 1 then
      EmitBoxPart(Vector3(0.0, 0.96 * HScale, 0.20), Vector3(ShoulderW * 0.88, 0.92 * HScale, 0.05), FAccentTrimRGB)
    else if FCapeBackSlot = 2 then
      EmitBoxPart(Vector3(0.14, 1.18 * HScale, 0.22), Vector3(0.18, 0.56 * HScale, 0.14), FAccentTrimRGB);

    { 7. Weapon Hand Slot }
    if FWeaponHandSlot > 0 then
      EmitBoxPart(Vector3(ShoulderW * 0.58, 1.05 * HScale, -0.35),
        Vector3(0.08, 0.10, 0.85 + 0.20 * FWeaponHandSlot), FAccentTrimRGB);

    FGeneratedTriangleCount := Verts.Count div 3;

    if FShowMergedMesh then
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

function TCastleMutableCharacter.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('recipe', ExportRecipeCode);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleMutableCharacter.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd: Integer;
  Rec: String;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      Rec := Obj.Get('recipe', '');
      if Rec <> '' then
        ImportRecipeCode(Rec);
      PresetOrd := Obj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TMutableArchetypePreset))) and
         (PresetOrd <= Ord(High(TMutableArchetypePreset))) then
        FPreset := TMutableArchetypePreset(PresetOrd);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleMutableCharacter.MutableSummaryBadge: String;
begin
  Result := Format('[Mutable:%d parts %d tris H=%.2fm %s]', [
    FMergedPartCount,
    FGeneratedTriangleCount,
    FTotalBoundsHeightMeters,
    IfThen(IsHairAutoHiddenByHelm, 'HelmClipsHair', 'OpenHair')]);
end;

initialization
  RegisterSerializableComponent(TCastleMutableCharacter, ['Characters', 'Mutable Modular Character Customizer']);
end.
