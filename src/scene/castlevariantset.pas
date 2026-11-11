{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Atomic multi-component scene configuration sets & runtime/design-time
  preset switcher (@link(TCastleVariantSetManager))
  (Phase 296 — UE 5.9 / 6.0 Variant Manager Parity). }
unit CastleVariantSet;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleClassUtils;

type
  { Single component dotted-RTTI property value stored inside a variant. }
  TVariantPropertyBinding = record
    ComponentName: String;
    PropertyPath: String;
    ValueJson: String;
  end;
  TVariantPropertyBindingArray = array of TVariantPropertyBinding;

  { Named variant (e.g. @code('Day'), @code('Sunset'), @code('Night')) inside a
    @link(TVariantSetGroup). }
  TVariantOption = record
    VariantName: String;
    Bindings: TVariantPropertyBindingArray;
  end;
  TVariantOptionArray = array of TVariantOption;

  { Named group of mutually exclusive variants (e.g. @code('Lighting'),
    @code('Quality'), @code('Props')). }
  TVariantSetGroup = record
    SetName: String;
    ActiveVariantName: String;
    Variants: TVariantOptionArray;
  end;
  TVariantSetGroupArray = array of TVariantSetGroup;

  { Non-visual component storing named variant sets & variants in diff-friendly
    JSON (@link(VariantSetsJson)) that atomically apply multi-component RTTI and
    persistent-vector snapshots at runtime or design time. }
  TCastleVariantSetManager = class(TCastleComponent)
  strict private
    FSets: TVariantSetGroupArray;
    function GetVariantSetsJson: String;
    procedure SetVariantSetsJson(const AValue: String);
    function FindSetIndex(const ASetName: String): Integer;
    function FindVariantIndex(const ASetIdx: Integer; const AVariantName: String): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearSets;
    function SetCount: Integer;
    function GetSet(const AIndex: Integer): TVariantSetGroup;

    function EnsureVariantSet(const ASetName: String): Integer;
    function EnsureVariant(const ASetName, AVariantName: String): Integer;

    { Insert or update a single JSON-encoded property binding in
      @code((ASetName, AVariantName)). }
    procedure SetVariantBinding(const ASetName, AVariantName,
      AComponentName, APropertyPath, AValueJson: String);

    { Read live dotted RTTI property @code(APropertyPath) on @code(AComponentName)
      inside @code(ARoot) and store it into @code((ASetName, AVariantName)). }
    function CaptureComponentPropertyIntoVariant(const ARoot: TComponent;
      const ASetName, AVariantName, AComponentName, APropertyPath: String): Boolean;

    { Capture standard configuration properties (@code(Exists),
      @code(TranslationPersistent.X/Y/Z), @code(ScalePersistent.X/Y/Z),
      @code(Intensity), @code(ColorPersistent.X/Y/Z), @code(Caption), @code(Url),
      @code(ExposureEV)) from @code(ATarget) into @code((ASetName, AVariantName)). }
    function CaptureComponentSnapshotIntoVariant(const ATarget: TComponent;
      const ASetName, AVariantName: String): Integer;

    { Atomically apply every binding in @code((ASetName, AVariantName)) across
      @code(ARoot) and mark @code(AVariantName) as the active variant of
      @code(ASetName). Returns number of applied bindings. }
    function ApplyVariant(const ARoot: TComponent;
      const ASetName, AVariantName: String): Integer;

    { Re-apply the active variant of every group onto @code(ARoot). }
    function ApplyAllActiveVariants(const ARoot: TComponent): Integer;

    { Read live dotted RTTI property on @code(ATarget) as a compact JSON literal
      (or @code('') if the property path does not exist on @code(ATarget)). }
    class function ReadPropertyPathAsJson(const ATarget: TObject;
      const APropPath: String): String;

    { Apply a compact JSON literal onto dotted RTTI property @code(APropPath)
      of @code(ATarget). }
    class function WritePropertyPathFromJson(const ATarget: TObject;
      const APropPath, AValueJson: String): Boolean;

    { Resolve a named component anywhere inside @code(ARoot) or its @code(Owner). }
    class function FindComponentInHierarchy(const ARoot: TComponent;
      const AName: String): TComponent;

    function VariantManagerSummaryBadge: String;
  published
    property VariantSetsJson: String read GetVariantSetsJson write SetVariantSetsJson;
  end;

implementation

uses
  TypInfo, StrUtils, fpjson, jsonparser,
  CastleUtils, CastleStringUtils, CastleComponentSerialize,
  CastleTransform, CastleUIControls, CastleViewport;

function WalkVariantDottedObjectPath(const ARootObj: TObject;
  const APropPath: String; out OutLeafObj: TObject;
  out OutLeafPropInfo: PPropInfo): Boolean;
var
  Parts: TCastleStringList;
  CurObj, SubObj: TObject;
  I: Integer;
  PInfo: PPropInfo;
begin
  Result := false;
  OutLeafObj := nil;
  OutLeafPropInfo := nil;
  if (ARootObj = nil) or (Trim(APropPath) = '') then
    Exit;

  Parts := SplitString(Trim(APropPath), '.');
  try
    if Parts.Count = 0 then
      Exit;
    CurObj := ARootObj;
    for I := 0 to Parts.Count - 2 do
    begin
      if CurObj = nil then
        Exit;
      PInfo := GetPropInfo(CurObj.ClassInfo, Parts[I]);
      if (PInfo = nil) or (PInfo^.PropType^.Kind <> tkClass) then
        Exit;
      SubObj := GetObjectProp(CurObj, PInfo);
      if SubObj = nil then
        Exit;
      CurObj := SubObj;
    end;

    if CurObj = nil then
      Exit;
    PInfo := GetPropInfo(CurObj.ClassInfo, Parts[Parts.Count - 1]);
    if PInfo = nil then
      Exit;

    OutLeafObj := CurObj;
    OutLeafPropInfo := PInfo;
    Result := true;
  finally
    FreeAndNil(Parts);
  end;
end;

{ TCastleVariantSetManager --------------------------------------------------- }

constructor TCastleVariantSetManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetLength(FSets, 0);
end;

function TCastleVariantSetManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if PropertyName = 'VariantSetsJson' then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleVariantSetManager.ClearSets;
begin
  SetLength(FSets, 0);
end;

function TCastleVariantSetManager.SetCount: Integer;
begin
  Result := Length(FSets);
end;

function TCastleVariantSetManager.GetSet(
  const AIndex: Integer): TVariantSetGroup;
begin
  if (AIndex >= 0) and (AIndex < Length(FSets)) then
    Result := FSets[AIndex]
  else
    Result := Default(TVariantSetGroup);
end;

function TCastleVariantSetManager.FindSetIndex(const ASetName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSets) do
    if SameText(FSets[I].SetName, ASetName) then
      Exit(I);
  Result := -1;
end;

function TCastleVariantSetManager.FindVariantIndex(const ASetIdx: Integer;
  const AVariantName: String): Integer;
var
  I: Integer;
begin
  if (ASetIdx >= 0) and (ASetIdx < Length(FSets)) then
    for I := 0 to High(FSets[ASetIdx].Variants) do
      if SameText(FSets[ASetIdx].Variants[I].VariantName, AVariantName) then
        Exit(I);
  Result := -1;
end;

function TCastleVariantSetManager.EnsureVariantSet(
  const ASetName: String): Integer;
begin
  Result := FindSetIndex(Trim(ASetName));
  if Result >= 0 then
    Exit;
  Result := Length(FSets);
  SetLength(FSets, Result + 1);
  FSets[Result].SetName := Trim(ASetName);
  FSets[Result].ActiveVariantName := '';
  SetLength(FSets[Result].Variants, 0);
end;

function TCastleVariantSetManager.EnsureVariant(
  const ASetName, AVariantName: String): Integer;
var
  SIdx: Integer;
begin
  SIdx := EnsureVariantSet(ASetName);
  Result := FindVariantIndex(SIdx, Trim(AVariantName));
  if Result >= 0 then
    Exit;
  Result := Length(FSets[SIdx].Variants);
  SetLength(FSets[SIdx].Variants, Result + 1);
  FSets[SIdx].Variants[Result].VariantName := Trim(AVariantName);
  SetLength(FSets[SIdx].Variants[Result].Bindings, 0);
  if FSets[SIdx].ActiveVariantName = '' then
    FSets[SIdx].ActiveVariantName := Trim(AVariantName);
end;

procedure TCastleVariantSetManager.SetVariantBinding(
  const ASetName, AVariantName, AComponentName, APropertyPath, AValueJson: String);
var
  SIdx, VIdx, BIdx: Integer;
begin
  if (Trim(ASetName) = '') or (Trim(AVariantName) = '') or
     (Trim(AComponentName) = '') or (Trim(APropertyPath) = '') then
    Exit;

  EnsureVariant(ASetName, AVariantName);
  SIdx := FindSetIndex(Trim(ASetName));
  VIdx := FindVariantIndex(SIdx, Trim(AVariantName));
  if (SIdx < 0) or (VIdx < 0) then
    Exit;

  for BIdx := 0 to High(FSets[SIdx].Variants[VIdx].Bindings) do
    if SameText(FSets[SIdx].Variants[VIdx].Bindings[BIdx].ComponentName, Trim(AComponentName)) and
       SameText(FSets[SIdx].Variants[VIdx].Bindings[BIdx].PropertyPath, Trim(APropertyPath)) then
    begin
      FSets[SIdx].Variants[VIdx].Bindings[BIdx].ValueJson := AValueJson;
      Exit;
    end;

  BIdx := Length(FSets[SIdx].Variants[VIdx].Bindings);
  SetLength(FSets[SIdx].Variants[VIdx].Bindings, BIdx + 1);
  FSets[SIdx].Variants[VIdx].Bindings[BIdx].ComponentName := Trim(AComponentName);
  FSets[SIdx].Variants[VIdx].Bindings[BIdx].PropertyPath := Trim(APropertyPath);
  FSets[SIdx].Variants[VIdx].Bindings[BIdx].ValueJson := AValueJson;
end;

class function TCastleVariantSetManager.ReadPropertyPathAsJson(
  const ATarget: TObject; const APropPath: String): String;
var
  LeafObj: TObject;
  PInfo: PPropInfo;
  Data: TJSONData;
begin
  Result := '';
  if not WalkVariantDottedObjectPath(ATarget, APropPath, LeafObj, PInfo) then
    Exit;

  Data := nil;
  case PInfo^.PropType^.Kind of
    tkInteger, tkInt64, tkQWord:
      Data := TJSONInt64Number.Create(GetInt64Prop(LeafObj, PInfo));
    tkFloat:
      Data := TJSONFloatNumber.Create(GetFloatProp(LeafObj, PInfo));
    tkBool:
      Data := TJSONBoolean.Create(GetOrdProp(LeafObj, PInfo) <> 0);
    tkSString, tkLString, tkAString, tkUString, tkWString:
      Data := TJSONString.Create(GetStrProp(LeafObj, PInfo));
    tkEnumeration:
      Data := TJSONString.Create(GetEnumName(PInfo^.PropType, GetOrdProp(LeafObj, PInfo)));
  end;

  if Data <> nil then
  try
    Result := Data.AsJSON;
  finally
    FreeAndNil(Data);
  end;
end;

class function TCastleVariantSetManager.WritePropertyPathFromJson(
  const ATarget: TObject; const APropPath, AValueJson: String): Boolean;
var
  LeafObj: TObject;
  PInfo: PPropInfo;
  JsonVal: TJSONData;
  EnumVal: Integer;
  FloatTmp: Double;
begin
  Result := false;
  if Trim(AValueJson) = '' then
    Exit;
  if not WalkVariantDottedObjectPath(ATarget, APropPath, LeafObj, PInfo) then
    Exit;
  if PInfo^.SetProc = nil then
    Exit;

  JsonVal := nil;
  try
    JsonVal := GetJSON(AValueJson);
  except
    { Fallback: treat unquoted string literal as TJSONString }
    JsonVal := TJSONString.Create(AValueJson);
  end;

  try
    case PInfo^.PropType^.Kind of
      tkInteger, tkInt64, tkQWord:
        if JsonVal.JsonType = jtNumber then
        begin
          SetInt64Prop(LeafObj, PInfo, JsonVal.AsInt64);
          Result := true;
        end else
        if JsonVal.JsonType = jtString then
        begin
          SetInt64Prop(LeafObj, PInfo, StrToInt64Def(JsonVal.AsString, GetInt64Prop(LeafObj, PInfo)));
          Result := true;
        end;

      tkFloat:
        if JsonVal.JsonType = jtNumber then
        begin
          SetFloatProp(LeafObj, PInfo, JsonVal.AsFloat);
          Result := true;
        end else
        if (JsonVal.JsonType = jtString) and TryStrToFloatDot(JsonVal.AsString, FloatTmp) then
        begin
          SetFloatProp(LeafObj, PInfo, FloatTmp);
          Result := true;
        end;

      tkBool:
        if JsonVal.JsonType = jtBoolean then
        begin
          SetOrdProp(LeafObj, PInfo, Ord(JsonVal.AsBoolean));
          Result := true;
        end else
        if JsonVal.JsonType = jtString then
        begin
          SetOrdProp(LeafObj, PInfo,
            Ord(SameText(Trim(JsonVal.AsString), 'true') or (Trim(JsonVal.AsString) = '1')));
          Result := true;
        end;

      tkSString, tkLString, tkAString, tkUString, tkWString:
        if JsonVal.JsonType in [jtString, jtNumber, jtBoolean] then
        begin
          SetStrProp(LeafObj, PInfo, JsonVal.AsString);
          Result := true;
        end;

      tkEnumeration:
        if JsonVal.JsonType = jtString then
        begin
          EnumVal := GetEnumValue(PInfo^.PropType, JsonVal.AsString);
          if EnumVal >= 0 then
          begin
            SetOrdProp(LeafObj, PInfo, EnumVal);
            Result := true;
          end;
        end else
        if JsonVal.JsonType = jtNumber then
        begin
          SetOrdProp(LeafObj, PInfo, JsonVal.AsInteger);
          Result := true;
        end;
    end;
  finally
    FreeAndNil(JsonVal);
  end;
end;

class function TCastleVariantSetManager.FindComponentInHierarchy(
  const ARoot: TComponent; const AName: String): TComponent;
var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  VP: TCastleViewport;
  CC: TCastleComponent;
begin
  Result := nil;
  if (ARoot = nil) or (AName = '') or (csTransient in ARoot.ComponentStyle) then
    Exit;
  if SameText(ARoot.Name, AName) then
    Exit(ARoot);

  if ARoot.Owner <> nil then
  begin
    Result := ARoot.Owner.FindComponent(AName);
    if Result <> nil then
      Exit;
  end;

  if ARoot is TCastleComponent then
  begin
    CC := TCastleComponent(ARoot);
    for I := 0 to CC.NonVisualComponentsCount - 1 do
    begin
      Result := FindComponentInHierarchy(CC.NonVisualComponents[I], AName);
      if Result <> nil then
        Exit;
    end;
  end;

  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindComponentInHierarchy(T[I], AName);
      if Result <> nil then
        Exit;
    end;
  end else
  if ARoot is TCastleUserInterface then
  begin
    if ARoot is TCastleViewport then
    begin
      VP := TCastleViewport(ARoot);
      if VP.Items <> nil then
      begin
        Result := FindComponentInHierarchy(VP.Items, AName);
        if Result <> nil then
          Exit;
      end;
    end;
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindComponentInHierarchy(UI.Controls[I], AName);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function TCastleVariantSetManager.CaptureComponentPropertyIntoVariant(
  const ARoot: TComponent; const ASetName, AVariantName,
  AComponentName, APropertyPath: String): Boolean;
var
  Comp: TComponent;
  ValJson: String;
begin
  Result := false;
  Comp := FindComponentInHierarchy(ARoot, AComponentName);
  if Comp = nil then
    Exit;
  ValJson := ReadPropertyPathAsJson(Comp, APropertyPath);
  if ValJson = '' then
    Exit;
  SetVariantBinding(ASetName, AVariantName, Comp.Name, APropertyPath, ValJson);
  Result := true;
end;

function TCastleVariantSetManager.CaptureComponentSnapshotIntoVariant(
  const ATarget: TComponent; const ASetName, AVariantName: String): Integer;
const
  StandardPaths: array [0..14] of String = (
    'Exists',
    'TranslationPersistent.X',
    'TranslationPersistent.Y',
    'TranslationPersistent.Z',
    'ScalePersistent.X',
    'ScalePersistent.Y',
    'ScalePersistent.Z',
    'Intensity',
    'ColorPersistent.Red',
    'ColorPersistent.Green',
    'ColorPersistent.Blue',
    'Caption',
    'Url',
    'ExposureEV',
    'VignetteIntensity'
  );
var
  I: Integer;
  ValJson: String;
begin
  Result := 0;
  if (ATarget = nil) or (ATarget.Name = '') then
    Exit;
  for I := Low(StandardPaths) to High(StandardPaths) do
  begin
    ValJson := ReadPropertyPathAsJson(ATarget, StandardPaths[I]);
    if ValJson <> '' then
    begin
      SetVariantBinding(ASetName, AVariantName, ATarget.Name, StandardPaths[I], ValJson);
      Inc(Result);
    end;
  end;
end;

function TCastleVariantSetManager.ApplyVariant(const ARoot: TComponent;
  const ASetName, AVariantName: String): Integer;
var
  SIdx, VIdx, BIdx: Integer;
  B: TVariantPropertyBinding;
  Comp: TComponent;
begin
  Result := 0;
  if ARoot = nil then
    Exit;
  SIdx := FindSetIndex(Trim(ASetName));
  if SIdx < 0 then
    Exit;
  VIdx := FindVariantIndex(SIdx, Trim(AVariantName));
  if VIdx < 0 then
    Exit;

  FSets[SIdx].ActiveVariantName := FSets[SIdx].Variants[VIdx].VariantName;
  for BIdx := 0 to High(FSets[SIdx].Variants[VIdx].Bindings) do
  begin
    B := FSets[SIdx].Variants[VIdx].Bindings[BIdx];
    Comp := FindComponentInHierarchy(ARoot, B.ComponentName);
    if (Comp <> nil) and WritePropertyPathFromJson(Comp, B.PropertyPath, B.ValueJson) then
      Inc(Result);
  end;
end;

function TCastleVariantSetManager.ApplyAllActiveVariants(
  const ARoot: TComponent): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSets) do
    if FSets[I].ActiveVariantName <> '' then
      Result := Result + ApplyVariant(ARoot, FSets[I].SetName, FSets[I].ActiveVariantName);
end;

function TCastleVariantSetManager.GetVariantSetsJson: String;
var
  RootArr, VarArr, BindArr: TJSONArray;
  SetObj, VarObj, BindObj: TJSONObject;
  S, V, B: Integer;
begin
  if Length(FSets) = 0 then
    Exit('');

  RootArr := TJSONArray.Create;
  try
    for S := 0 to High(FSets) do
    begin
      SetObj := TJSONObject.Create;
      SetObj.Add('set', FSets[S].SetName);
      SetObj.Add('active', FSets[S].ActiveVariantName);
      VarArr := TJSONArray.Create;
      for V := 0 to High(FSets[S].Variants) do
      begin
        VarObj := TJSONObject.Create;
        VarObj.Add('name', FSets[S].Variants[V].VariantName);
        BindArr := TJSONArray.Create;
        for B := 0 to High(FSets[S].Variants[V].Bindings) do
        begin
          BindObj := TJSONObject.Create;
          BindObj.Add('comp', FSets[S].Variants[V].Bindings[B].ComponentName);
          BindObj.Add('prop', FSets[S].Variants[V].Bindings[B].PropertyPath);
          BindObj.Add('val', FSets[S].Variants[V].Bindings[B].ValueJson);
          BindArr.Add(BindObj);
        end;
        VarObj.Add('bindings', BindArr);
        VarArr.Add(VarObj);
      end;
      SetObj.Add('variants', VarArr);
      RootArr.Add(SetObj);
    end;
    Result := RootArr.AsJSON;
  finally
    FreeAndNil(RootArr);
  end;
end;

procedure TCastleVariantSetManager.SetVariantSetsJson(const AValue: String);
var
  Parsed: TJSONData;
  RootArr, VarArr, BindArr: TJSONArray;
  SetObj, VarObj, BindObj: TJSONObject;
  S, V, B, SIdx: Integer;
  SetNameStr, ActiveStr, VarNameStr, CompStr, PropStr, ValStr: String;
begin
  ClearSets;
  if Trim(AValue) = '' then
    Exit;

  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;

  try
    if not (Parsed is TJSONArray) then
      Exit;
    RootArr := TJSONArray(Parsed);
    for S := 0 to RootArr.Count - 1 do
      if RootArr.Items[S] is TJSONObject then
      begin
        SetObj := TJSONObject(RootArr.Items[S]);
        SetNameStr := SetObj.Get('set', '');
        if SetNameStr = '' then
          Continue;
        SIdx := EnsureVariantSet(SetNameStr);
        ActiveStr := SetObj.Get('active', '');
        VarArr := SetObj.Find('variants', jtArray) as TJSONArray;
        if VarArr <> nil then
          for V := 0 to VarArr.Count - 1 do
            if VarArr.Items[V] is TJSONObject then
            begin
              VarObj := TJSONObject(VarArr.Items[V]);
              VarNameStr := VarObj.Get('name', '');
              if VarNameStr = '' then
                Continue;
              EnsureVariant(SetNameStr, VarNameStr);
              BindArr := VarObj.Find('bindings', jtArray) as TJSONArray;
              if BindArr <> nil then
                for B := 0 to BindArr.Count - 1 do
                  if BindArr.Items[B] is TJSONObject then
                  begin
                    BindObj := TJSONObject(BindArr.Items[B]);
                    CompStr := BindObj.Get('comp', '');
                    PropStr := BindObj.Get('prop', '');
                    ValStr := BindObj.Get('val', '');
                    if (CompStr <> '') and (PropStr <> '') then
                      SetVariantBinding(SetNameStr, VarNameStr, CompStr, PropStr, ValStr);
                  end;
            end;
        if ActiveStr <> '' then
          FSets[SIdx].ActiveVariantName := ActiveStr;
      end;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleVariantSetManager.VariantManagerSummaryBadge: String;
begin
  Result := Format('[Variants:%d sets]', [Length(FSets)]);
end;

initialization
  RegisterSerializableComponent(TCastleVariantSetManager, 'Variant Set Manager');
end.
