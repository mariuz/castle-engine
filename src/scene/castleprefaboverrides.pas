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

{ Non-destructive per-instance child RTTI property overrides for
  @link(TCastleTransformDesign) and @link(TCastleDesign) prefabs
  (Phase 285 — UE 6.0 Scene Graph Prefab Overrides Parity). }
unit CastlePrefabOverrides;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, FpJson,
  CastleClassUtils, CastleTransform, CastleUIControls, CastleControls;

type
  { Non-visual component stored inside @code(NonVisualComponents) of a
    @link(TCastleTransformDesign) or @link(TCastleDesign) instance to persist
    and automatically apply per-child RTTI property overrides without unlinking
    the prefab's @code(Url). }
  TCastlePrefabOverride = class(TCastleComponent)
  private
    FEnabled: Boolean;
    FTargetDesign: TCastleComponent;
    FTargetObserver: TFreeNotificationObserver;
    FOverridesJson: String;
    procedure SetEnabled(const AValue: Boolean);
    procedure SetTargetDesign(const AValue: TCastleComponent);
    procedure SetOverridesJson(const AValue: String);
    procedure TargetFreeNotification(const Sender: TFreeNotificationObserver);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Return @code(DesignRoot) of @link(TargetDesign) (@link(TCastleTransformDesign)
      or @link(TCastleDesign)), or @nil if not loaded. }
    function ResolvePrefabRoot: TComponent;

    { Find a child component inside the loaded prefab by name
      (@code('$root') or matching @code(DesignRoot.Name) returns @code(DesignRoot)). }
    function FindPrefabChild(const ChildName: String): TComponent;

    { Apply all stored property overrides onto @link(TargetDesign)'s loaded
      children right now. Returns the number of successfully applied property values. }
    function ApplyOverridesNow: Integer;

    { Total count of overridden @code(ChildName.PropertyPath) entries. }
    function OverrideCount: Integer;

    { Set or update a single child property override using a JSON value
      (takes ownership of @code(AValue) and immediately applies if loaded). }
    procedure SetChildOverrideJson(const ChildName, PropPath: String;
      const AValue: TJSONData);

    { Remove a single child property override entry (does not reload the prefab by itself;
      call @code(ReloadAndReapply) to restore the reverted property from disk). }
    function RemoveChildOverrideEntry(const ChildName, PropPath: String): Boolean;

    { Clear all stored overrides. }
    procedure ClearAllOverrides;

    { Reload @link(TargetDesign)'s @code(Url) from disk and re-apply all active
      overrides so any removed override cleanly reverts to its source prefab default. }
    procedure ReloadTargetAndReapply;
  published
    property Enabled: Boolean read FEnabled write SetEnabled default true;
    property TargetDesign: TCastleComponent read FTargetDesign write SetTargetDesign;
    property OverridesJson: String read FOverridesJson write SetOverridesJson;
  end;

{ Apply a single @code(TJSONData) value onto a dotted RTTI property path
  (such as @code('Caption'), @code('Exists'), @code('TranslationPersistent.Y'),
  or @code('ColorPersistent.Red')) on @code(TargetObj). }
function ApplyRttiPropertyPathJson(const TargetObj: TObject;
  const PropPath: String; const JsonVal: TJSONData): Boolean;

{ Read the current value of a dotted RTTI property path on @code(TargetObj)
  as a newly allocated @code(TJSONData) (caller owns result; returns @nil if not found). }
function ReadRttiPropertyPathJson(const TargetObj: TObject;
  const PropPath: String): TJSONData;

implementation

uses
  TypInfo, JsonParser, CastleUtils, CastleStringUtils, CastleComponentSerialize;

function WalkDottedObjectPath(const StartObj: TObject; const PropPath: String;
  out LeafObj: TObject; out LeafPropInfo: PPropInfo): Boolean;
var
  Parts: TCastleStringList;
  CurObj, SubObj: TObject;
  PInfo: PPropInfo;
  I: Integer;
begin
  Result := false;
  LeafObj := nil;
  LeafPropInfo := nil;
  if (StartObj = nil) or (Trim(PropPath) = '') then
    Exit;

  Parts := SplitString(Trim(PropPath), '.');
  try
    if Parts.Count = 0 then
      Exit;
    CurObj := StartObj;
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

    LeafObj := CurObj;
    LeafPropInfo := PInfo;
    Result := true;
  finally
    FreeAndNil(Parts);
  end;
end;

function ApplyRttiPropertyPathJson(const TargetObj: TObject;
  const PropPath: String; const JsonVal: TJSONData): Boolean;
var
  LeafObj: TObject;
  PInfo: PPropInfo;
  Kind: TTypeKind;
  EnumVal: Integer;
  FloatTmp: Double;
begin
  Result := false;
  if JsonVal = nil then
    Exit;
  if not WalkDottedObjectPath(TargetObj, PropPath, LeafObj, PInfo) then
    Exit;
  if PInfo^.SetProc = nil then
    Exit;

  Kind := PInfo^.PropType^.Kind;
  case Kind of
    tkInteger, tkInt64, tkQWord:
      begin
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
      end;

    tkFloat:
      begin
        if JsonVal.JsonType = jtNumber then
        begin
          SetFloatProp(LeafObj, PInfo, JsonVal.AsFloat);
          Result := true;
        end else
        if JsonVal.JsonType = jtString then
        begin
          if TryStrToFloatDot(JsonVal.AsString, FloatTmp) then
          begin
            SetFloatProp(LeafObj, PInfo, FloatTmp);
            Result := true;
          end;
        end;
      end;

    tkBool:
      begin
        if JsonVal.JsonType = jtBoolean then
        begin
          SetOrdProp(LeafObj, PInfo, Ord(JsonVal.AsBoolean));
          Result := true;
        end else
        if JsonVal.JsonType = jtNumber then
        begin
          SetOrdProp(LeafObj, PInfo, Ord(JsonVal.AsInteger <> 0));
          Result := true;
        end else
        if JsonVal.JsonType = jtString then
        begin
          SetOrdProp(LeafObj, PInfo, Ord(SameText(Trim(JsonVal.AsString), 'true') or (Trim(JsonVal.AsString) = '1')));
          Result := true;
        end;
      end;

    tkSString, tkLString, tkAString, tkUString, tkWString:
      begin
        if JsonVal.JsonType in [jtString, jtNumber, jtBoolean] then
        begin
          SetStrProp(LeafObj, PInfo, JsonVal.AsString);
          Result := true;
        end;
      end;

    tkEnumeration:
      begin
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
  end;
end;

function ReadRttiPropertyPathJson(const TargetObj: TObject;
  const PropPath: String): TJSONData;
var
  LeafObj: TObject;
  PInfo: PPropInfo;
begin
  Result := nil;
  if not WalkDottedObjectPath(TargetObj, PropPath, LeafObj, PInfo) then
    Exit;

  case PInfo^.PropType^.Kind of
    tkInteger, tkInt64, tkQWord:
      Result := TJSONInt64Number.Create(GetInt64Prop(LeafObj, PInfo));
    tkFloat:
      Result := TJSONFloatNumber.Create(GetFloatProp(LeafObj, PInfo));
    tkBool:
      Result := TJSONBoolean.Create(GetOrdProp(LeafObj, PInfo) <> 0);
    tkSString, tkLString, tkAString, tkUString, tkWString:
      Result := TJSONString.Create(GetStrProp(LeafObj, PInfo));
    tkEnumeration:
      Result := TJSONString.Create(GetEnumName(PInfo^.PropType, GetOrdProp(LeafObj, PInfo)));
  end;
end;

function ParseOverridesObject(const JsonText: String): TJSONObject;
var
  Parsed: TJSONData;
begin
  if Trim(JsonText) = '' then
    Exit(TJSONObject.Create);
  Parsed := nil;
  try
    Parsed := GetJSON(JsonText);
    if Parsed is TJSONObject then
    begin
      Result := TJSONObject(Parsed);
      Parsed := nil;
    end else
      Result := TJSONObject.Create;
  except
    Result := TJSONObject.Create;
  end;
  FreeAndNil(Parsed);
end;

{ TCastlePrefabOverride ------------------------------------------------------ }

constructor TCastlePrefabOverride.Create(AOwner: TComponent);
begin
  inherited;
  FEnabled := true;
  FOverridesJson := '';
  FTargetObserver := TFreeNotificationObserver.Create(Self);
  FTargetObserver.OnFreeNotification := {$ifdef FPC}@{$endif}TargetFreeNotification;
end;

destructor TCastlePrefabOverride.Destroy;
begin
  if FTargetObserver <> nil then
    FTargetObserver.Observed := nil;
  FTargetDesign := nil;
  inherited;
end;

procedure TCastlePrefabOverride.TargetFreeNotification(
  const Sender: TFreeNotificationObserver);
begin
  FTargetDesign := nil;
end;

function TCastlePrefabOverride.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Enabled', 'TargetDesign', 'OverridesJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePrefabOverride.Loaded;
begin
  inherited;
  if FEnabled and (FTargetDesign <> nil) and (Trim(FOverridesJson) <> '') then
    ApplyOverridesNow;
end;

procedure TCastlePrefabOverride.SetEnabled(const AValue: Boolean);
begin
  if FEnabled = AValue then
    Exit;
  FEnabled := AValue;
  if not IsLoading then
    ReloadTargetAndReapply;
end;

procedure TCastlePrefabOverride.SetTargetDesign(const AValue: TCastleComponent);
begin
  if FTargetDesign = AValue then
    Exit;
  FTargetDesign := AValue;
  if FTargetObserver <> nil then
    FTargetObserver.Observed := AValue;
  if (not IsLoading) and FEnabled and (FTargetDesign <> nil) and (Trim(FOverridesJson) <> '') then
    ApplyOverridesNow;
end;

procedure TCastlePrefabOverride.SetOverridesJson(const AValue: String);
begin
  if FOverridesJson = AValue then
    Exit;
  FOverridesJson := AValue;
  if (not IsLoading) and FEnabled and (FTargetDesign <> nil) and (Trim(FOverridesJson) <> '') then
    ApplyOverridesNow;
end;

function TCastlePrefabOverride.ResolvePrefabRoot: TComponent;
begin
  Result := nil;
  if FTargetDesign is TCastleTransformDesign then
    Result := TCastleTransformDesign(FTargetDesign).DesignRoot
  else if FTargetDesign is TCastleDesign then
    Result := TCastleDesign(FTargetDesign).DesignRoot;
end;

function TCastlePrefabOverride.FindPrefabChild(const ChildName: String): TComponent;
var
  Root: TComponent;
begin
  Result := nil;
  Root := ResolvePrefabRoot;
  if Root = nil then
    Exit;
  if (ChildName = '$root') or SameText(ChildName, Root.Name) then
    Exit(Root);

  if FTargetDesign is TCastleTransformDesign then
    Result := TCastleTransformDesign(FTargetDesign).DesignedComponent(ChildName, false)
  else if FTargetDesign is TCastleDesign then
    Result := TCastleDesign(FTargetDesign).DesignedComponent(ChildName, false);
end;

function TCastlePrefabOverride.ApplyOverridesNow: Integer;
var
  RootObj, ChildPropsObj: TJSONObject;
  I, J: Integer;
  ChildName, PropPath: String;
  ChildComp: TComponent;
begin
  Result := 0;
  if (not FEnabled) or (FTargetDesign = nil) or (Trim(FOverridesJson) = '') then
    Exit;
  if ResolvePrefabRoot = nil then
    Exit;

  RootObj := ParseOverridesObject(FOverridesJson);
  try
    for I := 0 to RootObj.Count - 1 do
    begin
      ChildName := RootObj.Names[I];
      if not (RootObj.Items[I] is TJSONObject) then
        Continue;
      ChildComp := FindPrefabChild(ChildName);
      if ChildComp = nil then
        Continue;
      ChildPropsObj := TJSONObject(RootObj.Items[I]);
      for J := 0 to ChildPropsObj.Count - 1 do
      begin
        PropPath := ChildPropsObj.Names[J];
        if ApplyRttiPropertyPathJson(ChildComp, PropPath, ChildPropsObj.Items[J]) then
          Inc(Result);
      end;
    end;
  finally
    FreeAndNil(RootObj);
  end;
end;

function TCastlePrefabOverride.OverrideCount: Integer;
var
  RootObj: TJSONObject;
  I: Integer;
begin
  Result := 0;
  if Trim(FOverridesJson) = '' then
    Exit;
  RootObj := ParseOverridesObject(FOverridesJson);
  try
    for I := 0 to RootObj.Count - 1 do
      if RootObj.Items[I] is TJSONObject then
        Result := Result + TJSONObject(RootObj.Items[I]).Count;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastlePrefabOverride.SetChildOverrideJson(
  const ChildName, PropPath: String; const AValue: TJSONData);
var
  RootObj, ChildObj: TJSONObject;
  ExistingIdx: Integer;
  ChildComp: TComponent;
begin
  if (Trim(ChildName) = '') or (Trim(PropPath) = '') or (AValue = nil) then
  begin
    AValue.Free;
    Exit;
  end;

  RootObj := ParseOverridesObject(FOverridesJson);
  try
    ExistingIdx := RootObj.IndexOfName(ChildName);
    if (ExistingIdx >= 0) and (RootObj.Items[ExistingIdx] is TJSONObject) then
      ChildObj := TJSONObject(RootObj.Items[ExistingIdx])
    else
    begin
      if ExistingIdx >= 0 then
        RootObj.Delete(ExistingIdx);
      ChildObj := TJSONObject.Create;
      RootObj.Add(ChildName, ChildObj);
    end;

    ExistingIdx := ChildObj.IndexOfName(PropPath);
    if ExistingIdx >= 0 then
      ChildObj.Delete(ExistingIdx);
    ChildObj.Add(PropPath, AValue);

    FOverridesJson := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;

  if FEnabled and (FTargetDesign <> nil) then
  begin
    ChildComp := FindPrefabChild(ChildName);
    if ChildComp <> nil then
    begin
      RootObj := ParseOverridesObject(FOverridesJson);
      try
        ChildObj := RootObj.Find(ChildName, jtObject) as TJSONObject;
        if ChildObj <> nil then
          ApplyRttiPropertyPathJson(ChildComp, PropPath, ChildObj.Find(PropPath));
      finally
        FreeAndNil(RootObj);
      end;
    end;
  end;
end;

function TCastlePrefabOverride.RemoveChildOverrideEntry(
  const ChildName, PropPath: String): Boolean;
var
  RootObj, ChildObj: TJSONObject;
  CIdx, PIdx: Integer;
begin
  Result := false;
  if Trim(FOverridesJson) = '' then
    Exit;
  RootObj := ParseOverridesObject(FOverridesJson);
  try
    CIdx := RootObj.IndexOfName(ChildName);
    if (CIdx >= 0) and (RootObj.Items[CIdx] is TJSONObject) then
    begin
      ChildObj := TJSONObject(RootObj.Items[CIdx]);
      PIdx := ChildObj.IndexOfName(PropPath);
      if PIdx >= 0 then
      begin
        ChildObj.Delete(PIdx);
        if ChildObj.Count = 0 then
          RootObj.Delete(CIdx);
        if RootObj.Count = 0 then
          FOverridesJson := ''
        else
          FOverridesJson := RootObj.AsJSON;
        Result := true;
      end;
    end;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastlePrefabOverride.ClearAllOverrides;
begin
  FOverridesJson := '';
end;

procedure TCastlePrefabOverride.ReloadTargetAndReapply;
begin
  if FTargetDesign is TCastleTransformDesign then
    TCastleTransformDesign(FTargetDesign).ReloadUrl
  else if FTargetDesign is TCastleDesign then
    TCastleDesign(FTargetDesign).ReloadUrl;

  if FEnabled and (Trim(FOverridesJson) <> '') then
    ApplyOverridesNow;
end;

initialization
  RegisterSerializableComponent(TCastlePrefabOverride,
    ['Non-Visual', 'Prefab Property Overrides']);
end.
