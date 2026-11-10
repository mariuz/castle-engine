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

{ Inspection, live diff capture, selective revert, and source-prefab promotion
  for @link(TCastlePrefabOverride) on @link(TCastleTransformDesign) and
  @link(TCastleDesign) instances (Phase 285 — UE 6.0 Scene Graph Parity). }
unit ToolPrefabOverrides;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, FpJson,
  CastleClassUtils, CastleTransform, CastleUIControls, CastleControls,
  CastleViewport, CastlePrefabOverrides;

type
  { Single active child property override row for display & diffing. }
  TPrefabOverrideRow = record
    ChildName: String;
    ChildClass: String;
    PropPath: String;
    SourceDefaultText: String;
    OverriddenValueText: String;
  end;
  TPrefabOverrideRowArray = array of TPrefabOverrideRow;

  { Stateless Scene-Graph prefab override manager for @code(TCastleTransformDesign)
    and @code(TCastleDesign). }
  TPrefabOverrideManager = class
  public
    class function IsSupportedPrefabInstance(const C: TComponent): Boolean;
    class function GetPrefabUrl(const DesignInstance: TComponent): String;
    class function GetPrefabRoot(const DesignInstance: TComponent): TComponent;

    { Return existing @link(TCastlePrefabOverride) attached inside
      @code(DesignInstance.NonVisualComponents), or @nil. }
    class function FindOverrideComponent(
      const DesignInstance: TCastleComponent): TCastlePrefabOverride;

    { Return existing or newly attached @link(TCastlePrefabOverride) on
      @code(DesignInstance). }
    class function EnsureOverrideComponent(
      const DesignInstance: TCastleComponent;
      const DesignOwner: TComponent): TCastlePrefabOverride;

    { Return active override count on @code(DesignInstance) (0 if none). }
    class function ActiveOverrideCount(const DesignInstance: TComponent): Integer;

    { Re-apply overrides across every @code(TCastlePrefabOverride) found under
      @code(RootComp) (useful after reloading external prefab URLs). }
    class function ReapplyAllInHierarchy(const RootComp: TComponent): Integer;

    { Enumerate all named components inside @code(DesignInstance)'s loaded prefab. }
    class procedure ListPrefabChildren(const DesignInstance: TComponent;
      const OutNames: TStrings);

    { Enumerate scalar & persistent sub-component RTTI property paths on @code(ChildComp)
      (e.g. @code('Exists'), @code('Caption'), @code('TranslationPersistent.Y')). }
    class procedure ListEditablePropertyPaths(const ChildComp: TComponent;
      const OutPaths: TStrings);

    { Compare @code(DesignInstance)'s live loaded @code(DesignRoot) against a
      clean load of its @code(Url) on disk, recording any modified child RTTI
      properties into @link(TCastlePrefabOverride). Returns total active override count. }
    class function CaptureLiveEditsFromInstance(
      const DesignInstance: TCastleComponent;
      const DesignOwner: TComponent): Integer;

    { Parse @code(RawValueText) according to the target RTTI property's type and
      apply/store it as a non-destructive override on @code(DesignInstance). }
    class function SetOverrideFromString(
      const DesignInstance: TCastleComponent;
      const DesignOwner: TComponent;
      const ChildName, PropPath, RawValueText: String): Boolean;

    { Build a human-readable list of active overrides paired with their clean
      source prefab default values. }
    class function DescribeActiveOverrides(
      const DesignInstance: TCastleComponent;
      out Rows: TPrefabOverrideRowArray): Integer;

    { Revert a single overridden @code(ChildName.PropPath) back to the source prefab's value. }
    class function RevertSingleOverride(
      const DesignInstance: TCastleComponent;
      const ChildName, PropPath: String): Boolean;

    { Revert all overrides on @code(DesignInstance) and remove empty @link(TCastlePrefabOverride). }
    class function RevertAllOverrides(
      const DesignInstance: TCastleComponent): Boolean;

    { Promote (bake) all active overrides from @code(DesignInstance) permanently
      into the source @code(.castle-transform) or @code(.castle-user-interface) file
      referenced by @code(Url), then clear the now-redundant overrides on
      @code(DesignInstance) and reload @code(Url). }
    class function ApplyOverridesToSourcePrefab(
      const DesignInstance: TCastleComponent;
      out SavedPrefabUrl: String): Boolean;
  end;

implementation

uses
  TypInfo, Math, JsonParser,
  CastleUtils, CastleStringUtils, CastleUriUtils, CastleComponentSerialize;

function LoadCleanPrefabCopy(const DesignInstance: TComponent;
  const TempOwner: TComponent): TComponent;
var
  UrlStr: String;
begin
  Result := nil;
  UrlStr := Trim(TPrefabOverrideManager.GetPrefabUrl(DesignInstance));
  if (UrlStr = '') or (not UriFileExists(UrlStr)) then
    Exit;
  if DesignInstance is TCastleTransformDesign then
    Result := TransformLoad(UrlStr, TempOwner)
  else if DesignInstance is TCastleDesign then
    Result := UserInterfaceLoad(UrlStr, TempOwner);
end;

function FindComponentInPrefabTree(const RootComp: TComponent;
  const TargetName: String): TComponent;

  function Walk(const C: TComponent): TComponent;
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
  begin
    Result := nil;
    if C = nil then
      Exit;
    if SameText(C.Name, TargetName) then
      Exit(C);
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
      begin
        Result := Walk(T[I]);
        if Result <> nil then
          Exit;
      end;
    end else
    if C is TCastleViewport then
    begin
      for I := 0 to TCastleViewport(C).ControlsCount - 1 do
      begin
        Result := Walk(TCastleViewport(C).Controls[I]);
        if Result <> nil then
          Exit;
      end;
      Result := Walk(TCastleViewport(C).Items);
      if Result <> nil then
        Exit;
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := Walk(UI.Controls[I]);
        if Result <> nil then
          Exit;
      end;
    end;
  end;

begin
  if (RootComp <> nil) and ((TargetName = '$root') or SameText(RootComp.Name, TargetName)) then
    Exit(RootComp);
  Result := Walk(RootComp);
end;

function JsonDataCompactDisplay(const D: TJSONData): String;
begin
  if D = nil then
    Result := '<unknown>'
  else if D.JsonType = jtString then
    Result := '"' + D.AsString + '"'
  else if D is TJSONFloatNumber then
    Result := FloatToStrDot(D.AsFloat)
  else
    Result := D.AsJSON;
end;

function JsonValuesEqual(const A, B: TJSONData): Boolean;
begin
  if (A = nil) or (B = nil) then
    Exit(A = B);
  if (A.JsonType = jtNumber) and (B.JsonType = jtNumber) then
    Exit(SameValue(A.AsFloat, B.AsFloat, 1e-5));
  Result := (A.JsonType = B.JsonType) and (A.AsString = B.AsString);
end;

function MakeUniqueOverrideName(const AOwner: TComponent; const BasePrefix: String): String;
var
  Idx: Integer;
begin
  Idx := 1;
  repeat
    Result := BasePrefix + '_Overrides' + IntToStr(Idx);
    Inc(Idx);
  until (AOwner = nil) or (AOwner.FindComponent(Result) = nil);
end;

{ TPrefabOverrideManager ----------------------------------------------------- }

class function TPrefabOverrideManager.IsSupportedPrefabInstance(
  const C: TComponent): Boolean;
begin
  Result := (C is TCastleTransformDesign) or (C is TCastleDesign);
end;

class function TPrefabOverrideManager.GetPrefabUrl(
  const DesignInstance: TComponent): String;
begin
  if DesignInstance is TCastleTransformDesign then
    Result := TCastleTransformDesign(DesignInstance).Url
  else if DesignInstance is TCastleDesign then
    Result := TCastleDesign(DesignInstance).Url
  else
    Result := '';
end;

class function TPrefabOverrideManager.GetPrefabRoot(
  const DesignInstance: TComponent): TComponent;
begin
  if DesignInstance is TCastleTransformDesign then
    Result := TCastleTransformDesign(DesignInstance).DesignRoot
  else if DesignInstance is TCastleDesign then
    Result := TCastleDesign(DesignInstance).DesignRoot
  else
    Result := nil;
end;

class function TPrefabOverrideManager.FindOverrideComponent(
  const DesignInstance: TCastleComponent): TCastlePrefabOverride;
var
  I: Integer;
  NV: TComponent;
begin
  Result := nil;
  if DesignInstance = nil then
    Exit;
  for I := 0 to DesignInstance.NonVisualComponentsCount - 1 do
  begin
    NV := DesignInstance.NonVisualComponents[I];
    if NV is TCastlePrefabOverride then
      Exit(TCastlePrefabOverride(NV));
  end;
end;

class function TPrefabOverrideManager.EnsureOverrideComponent(
  const DesignInstance: TCastleComponent;
  const DesignOwner: TComponent): TCastlePrefabOverride;
var
  EffectiveOwner: TComponent;
begin
  Result := FindOverrideComponent(DesignInstance);
  if Result <> nil then
  begin
    if Result.TargetDesign <> DesignInstance then
      Result.TargetDesign := DesignInstance;
    Exit;
  end;
  if DesignInstance = nil then
    Exit(nil);

  if DesignOwner <> nil then
    EffectiveOwner := DesignOwner
  else
    EffectiveOwner := DesignInstance.Owner;

  Result := TCastlePrefabOverride.Create(EffectiveOwner);
  if DesignInstance.Name <> '' then
    Result.Name := MakeUniqueOverrideName(EffectiveOwner, DesignInstance.Name)
  else
    Result.Name := MakeUniqueOverrideName(EffectiveOwner, 'Prefab');
  Result.TargetDesign := DesignInstance;
  DesignInstance.AddNonVisualComponent(Result);
end;

class function TPrefabOverrideManager.ActiveOverrideCount(
  const DesignInstance: TComponent): Integer;
var
  Ov: TCastlePrefabOverride;
begin
  Result := 0;
  if not (DesignInstance is TCastleComponent) then
    Exit;
  Ov := FindOverrideComponent(TCastleComponent(DesignInstance));
  if (Ov <> nil) and Ov.Enabled then
    Result := Ov.OverrideCount;
end;

class function TPrefabOverrideManager.ReapplyAllInHierarchy(
  const RootComp: TComponent): Integer;

  function Walk(const C: TComponent): Integer;
  var
    I: Integer;
    CC: TCastleComponent;
    T: TCastleTransform;
    UI: TCastleUserInterface;
  begin
    Result := 0;
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastlePrefabOverride then
      Result := Result + TCastlePrefabOverride(C).ApplyOverridesNow;

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Result := Result + Walk(CC.NonVisualComponents[I]);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Result := Result + Walk(T[I]);
    end else
    if C is TCastleViewport then
    begin
      for I := 0 to TCastleViewport(C).ControlsCount - 1 do
        Result := Result + Walk(TCastleViewport(C).Controls[I]);
      Result := Result + Walk(TCastleViewport(C).Items);
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Result := Result + Walk(UI.Controls[I]);
    end;
  end;

begin
  Result := Walk(RootComp);
end;

class procedure TPrefabOverrideManager.ListPrefabChildren(
  const DesignInstance: TComponent; const OutNames: TStrings);

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
  begin
    if C = nil then
      Exit;
    if (C.Name <> '') and (OutNames.IndexOf(C.Name) = -1) then
      OutNames.AddObject(C.Name, C);

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end else
    if C is TCastleViewport then
    begin
      for I := 0 to TCastleViewport(C).ControlsCount - 1 do
        Walk(TCastleViewport(C).Controls[I]);
      Walk(TCastleViewport(C).Items);
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Walk(UI.Controls[I]);
    end;
  end;

var
  Root: TComponent;
begin
  OutNames.Clear;
  Root := GetPrefabRoot(DesignInstance);
  if Root <> nil then
    Walk(Root);
end;

class procedure TPrefabOverrideManager.ListEditablePropertyPaths(
  const ChildComp: TComponent; const OutPaths: TStrings);

  procedure CollectFromObject(const Obj: TObject; const Prefix: String; const Depth: Integer);
  var
    PropList: PPropList;
    PropCount, I: Integer;
    PInfo: PPropInfo;
    PropName, FullPath: String;
    SubObj: TObject;
  begin
    if (Obj = nil) or (Depth > 1) then
      Exit;
    PropCount := GetPropList(Obj.ClassInfo, tkAny, nil);
    if PropCount <= 0 then
      Exit;
    GetMem(PropList, PropCount * SizeOf(Pointer));
    try
      GetPropList(Obj.ClassInfo, tkAny, PropList);
      for I := 0 to PropCount - 1 do
      begin
        PInfo := PropList^[I];
        PropName := String(PInfo^.Name);
        if SameText(PropName, 'Name') or SameText(PropName, 'Tag') then
          Continue;
        if Prefix = '' then
          FullPath := PropName
        else
          FullPath := Prefix + '.' + PropName;

        case PInfo^.PropType^.Kind of
          tkInteger, tkInt64, tkQWord, tkFloat, tkBool,
          tkSString, tkLString, tkAString, tkUString, tkWString,
          tkEnumeration:
            if PInfo^.SetProc <> nil then
              OutPaths.Add(FullPath);
          tkClass:
            if Depth = 0 then
            begin
              SubObj := GetObjectProp(Obj, PInfo);
              if (SubObj is TComponent) and (csSubComponent in TComponent(SubObj).ComponentStyle) then
                CollectFromObject(SubObj, FullPath, Depth + 1);
            end;
        end;
      end;
    finally
      FreeMem(PropList);
    end;
  end;

begin
  OutPaths.Clear;
  CollectFromObject(ChildComp, '', 0);
end;

class function TPrefabOverrideManager.CaptureLiveEditsFromInstance(
  const DesignInstance: TCastleComponent;
  const DesignOwner: TComponent): Integer;
var
  TempOwner: TComponent;
  CleanRoot: TComponent;
  LiveChildren, Paths: TStringList;
  I, J: Integer;
  ChildName, PropPath: String;
  LiveChild, CleanChild: TComponent;
  LiveVal, CleanVal: TJSONData;
  Ov: TCastlePrefabOverride;
begin
  Result := 0;
  if not IsSupportedPrefabInstance(DesignInstance) then
    Exit;

  TempOwner := TComponent.Create(nil);
  LiveChildren := TStringList.Create;
  Paths := TStringList.Create;
  try
    CleanRoot := LoadCleanPrefabCopy(DesignInstance, TempOwner);
    if CleanRoot = nil then
      Exit;

    ListPrefabChildren(DesignInstance, LiveChildren);
    for I := 0 to LiveChildren.Count - 1 do
    begin
      ChildName := LiveChildren[I];
      LiveChild := TComponent(LiveChildren.Objects[I]);
      CleanChild := FindComponentInPrefabTree(CleanRoot, ChildName);
      if (LiveChild = nil) or (CleanChild = nil) or
         (LiveChild.ClassType <> CleanChild.ClassType) then
        Continue;

      { Skip Stretch-forced FullSize on root UI of TCastleDesign when Stretch=true }
      ListEditablePropertyPaths(LiveChild, Paths);
      for J := 0 to Paths.Count - 1 do
      begin
        PropPath := Paths[J];
        if (DesignInstance is TCastleDesign) and (LiveChild = TCastleDesign(DesignInstance).DesignRoot) and
           TCastleDesign(DesignInstance).Stretch and SameText(PropPath, 'FullSize') then
          Continue;

        LiveVal := ReadRttiPropertyPathJson(LiveChild, PropPath);
        CleanVal := ReadRttiPropertyPathJson(CleanChild, PropPath);
        try
          if (LiveVal <> nil) and (CleanVal <> nil) and
             (not JsonValuesEqual(LiveVal, CleanVal)) then
          begin
            Ov := EnsureOverrideComponent(DesignInstance, DesignOwner);
            Ov.SetChildOverrideJson(ChildName, PropPath, LiveVal.Clone);
          end;
        finally
          FreeAndNil(LiveVal);
          FreeAndNil(CleanVal);
        end;
      end;
    end;

    Ov := FindOverrideComponent(DesignInstance);
    if Ov <> nil then
      Result := Ov.OverrideCount;
  finally
    FreeAndNil(Paths);
    FreeAndNil(LiveChildren);
    FreeAndNil(TempOwner);
  end;
end;

class function TPrefabOverrideManager.SetOverrideFromString(
  const DesignInstance: TCastleComponent;
  const DesignOwner: TComponent;
  const ChildName, PropPath, RawValueText: String): Boolean;
var
  Ov: TCastlePrefabOverride;
  ChildComp: TComponent;
  CurrentVal, NewVal: TJSONData;
  Trimmed: String;
  FloatV: Double;
  IntV: Int64;
begin
  Result := false;
  if not IsSupportedPrefabInstance(DesignInstance) then
    Exit;
  Ov := EnsureOverrideComponent(DesignInstance, DesignOwner);
  if Ov = nil then
    Exit;

  ChildComp := Ov.FindPrefabChild(ChildName);
  if ChildComp = nil then
    Exit;

  CurrentVal := ReadRttiPropertyPathJson(ChildComp, PropPath);
  if CurrentVal = nil then
    Exit;
  try
    Trimmed := Trim(RawValueText);
    NewVal := nil;
    case CurrentVal.JsonType of
      jtBoolean:
        NewVal := TJSONBoolean.Create(
          SameText(Trimmed, 'true') or (Trimmed = '1') or SameText(Trimmed, 'yes'));
      jtNumber:
        if CurrentVal is TJSONFloatNumber then
        begin
          if not TryStrToFloatDot(Trimmed, FloatV) then
            Exit(false);
          NewVal := TJSONFloatNumber.Create(FloatV);
        end else
        begin
          if not TryStrToInt64(Trimmed, IntV) then
            Exit(false);
          NewVal := TJSONInt64Number.Create(IntV);
        end;
    else
      begin
        { Strip optional surrounding double quotes if user typed "foo" }
        if (Length(Trimmed) >= 2) and (Trimmed[1] = '"') and (Trimmed[Length(Trimmed)] = '"') then
          Trimmed := Copy(Trimmed, 2, Length(Trimmed) - 2);
        NewVal := TJSONString.Create(Trimmed);
      end;
    end;

    if ApplyRttiPropertyPathJson(ChildComp, PropPath, NewVal) then
    begin
      Ov.SetChildOverrideJson(ChildName, PropPath, NewVal);
      Result := true;
    end else
      FreeAndNil(NewVal);
  finally
    FreeAndNil(CurrentVal);
  end;
end;

class function TPrefabOverrideManager.DescribeActiveOverrides(
  const DesignInstance: TCastleComponent;
  out Rows: TPrefabOverrideRowArray): Integer;
var
  Ov: TCastlePrefabOverride;
  TempOwner: TComponent;
  CleanRoot, CleanChild, LiveChild: TComponent;
  RootObj, ChildObj: TJSONObject;
  CleanVal: TJSONData;
  I, J, OutIdx: Integer;
  ChildName, PropPath: String;
begin
  SetLength(Rows, 0);
  Result := 0;
  Ov := FindOverrideComponent(DesignInstance);
  if (Ov = nil) or (Trim(Ov.OverridesJson) = '') then
    Exit;

  TempOwner := TComponent.Create(nil);
  RootObj := nil;
  try
    CleanRoot := LoadCleanPrefabCopy(DesignInstance, TempOwner);
    try
      RootObj := GetJSON(Ov.OverridesJson) as TJSONObject;
    except
      RootObj := nil;
    end;
    if RootObj = nil then
      Exit;

    SetLength(Rows, Ov.OverrideCount);
    OutIdx := 0;
    for I := 0 to RootObj.Count - 1 do
    begin
      ChildName := RootObj.Names[I];
      if not (RootObj.Items[I] is TJSONObject) then
        Continue;
      ChildObj := TJSONObject(RootObj.Items[I]);
      LiveChild := Ov.FindPrefabChild(ChildName);
      if CleanRoot <> nil then
        CleanChild := FindComponentInPrefabTree(CleanRoot, ChildName)
      else
        CleanChild := nil;

      for J := 0 to ChildObj.Count - 1 do
      begin
        PropPath := ChildObj.Names[J];
        if OutIdx >= Length(Rows) then
          SetLength(Rows, OutIdx + 8);
        Rows[OutIdx].ChildName := ChildName;
        if LiveChild <> nil then
          Rows[OutIdx].ChildClass := LiveChild.ClassName
        else if CleanChild <> nil then
          Rows[OutIdx].ChildClass := CleanChild.ClassName
        else
          Rows[OutIdx].ChildClass := '';
        Rows[OutIdx].PropPath := PropPath;
        Rows[OutIdx].OverriddenValueText := JsonDataCompactDisplay(ChildObj.Items[J]);

        if CleanChild <> nil then
        begin
          CleanVal := ReadRttiPropertyPathJson(CleanChild, PropPath);
          try
            Rows[OutIdx].SourceDefaultText := JsonDataCompactDisplay(CleanVal);
          finally
            FreeAndNil(CleanVal);
          end;
        end else
          Rows[OutIdx].SourceDefaultText := '<prefab default>';

        Inc(OutIdx);
      end;
    end;
    SetLength(Rows, OutIdx);
    Result := OutIdx;
  finally
    FreeAndNil(RootObj);
    FreeAndNil(TempOwner);
  end;
end;

class function TPrefabOverrideManager.RevertSingleOverride(
  const DesignInstance: TCastleComponent;
  const ChildName, PropPath: String): Boolean;
var
  Ov: TCastlePrefabOverride;
begin
  Result := false;
  Ov := FindOverrideComponent(DesignInstance);
  if Ov = nil then
    Exit;
  if not Ov.RemoveChildOverrideEntry(ChildName, PropPath) then
    Exit;

  Ov.ReloadTargetAndReapply;
  if Ov.OverrideCount = 0 then
  begin
    DesignInstance.RemoveNonVisualComponent(Ov);
    FreeAndNil(Ov);
  end;
  Result := true;
end;

class function TPrefabOverrideManager.RevertAllOverrides(
  const DesignInstance: TCastleComponent): Boolean;
var
  Ov: TCastlePrefabOverride;
begin
  Result := false;
  Ov := FindOverrideComponent(DesignInstance);
  if Ov = nil then
    Exit;
  Ov.ClearAllOverrides;
  Ov.ReloadTargetAndReapply;
  DesignInstance.RemoveNonVisualComponent(Ov);
  FreeAndNil(Ov);
  Result := true;
end;

class function TPrefabOverrideManager.ApplyOverridesToSourcePrefab(
  const DesignInstance: TCastleComponent;
  out SavedPrefabUrl: String): Boolean;
var
  Ov: TCastlePrefabOverride;
  TempOwner: TComponent;
  CleanRoot, TargetChild: TComponent;
  RootObj, ChildObj: TJSONObject;
  I, J, AppliedCount: Integer;
begin
  Result := false;
  SavedPrefabUrl := Trim(GetPrefabUrl(DesignInstance));
  if SavedPrefabUrl = '' then
    Exit;
  Ov := FindOverrideComponent(DesignInstance);
  if (Ov = nil) or (Ov.OverrideCount = 0) then
    Exit;

  TempOwner := TComponent.Create(nil);
  RootObj := nil;
  try
    CleanRoot := LoadCleanPrefabCopy(DesignInstance, TempOwner);
    if CleanRoot = nil then
      Exit;

    RootObj := GetJSON(Ov.OverridesJson) as TJSONObject;
    AppliedCount := 0;
    for I := 0 to RootObj.Count - 1 do
    begin
      if not (RootObj.Items[I] is TJSONObject) then
        Continue;
      TargetChild := FindComponentInPrefabTree(CleanRoot, RootObj.Names[I]);
      if TargetChild = nil then
        Continue;
      ChildObj := TJSONObject(RootObj.Items[I]);
      for J := 0 to ChildObj.Count - 1 do
        if ApplyRttiPropertyPathJson(TargetChild, ChildObj.Names[J], ChildObj.Items[J]) then
          Inc(AppliedCount);
    end;

    if AppliedCount = 0 then
      Exit;

    if CleanRoot is TCastleTransform then
      TransformSave(TCastleTransform(CleanRoot), SavedPrefabUrl)
    else if CleanRoot is TCastleUserInterface then
      UserInterfaceSave(TCastleUserInterface(CleanRoot), SavedPrefabUrl)
    else
      Exit;

    { Source prefab on disk now contains all changes; remove instance overrides and reload }
    Ov.ClearAllOverrides;
    Ov.ReloadTargetAndReapply;
    DesignInstance.RemoveNonVisualComponent(Ov);
    FreeAndNil(Ov);
    Result := true;
  finally
    FreeAndNil(RootObj);
    FreeAndNil(TempOwner);
  end;
end;

end.
