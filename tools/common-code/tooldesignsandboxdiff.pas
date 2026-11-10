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

{ Non-destructive Design Sandboxes (@link(TDesignSandboxManager)) and
  Visual Scene/UI Hierarchy + RTTI Property Diff & Selective Merge engine
  (@link(TDesignDiffEngine)), inspired by Unreal Engine 5.8/5.9 Content
  Sandboxes and Asset Diff/Merge workflows. }
unit ToolDesignSandboxDiff;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Generics.Collections, FpJson;

type
  { Lightweight named experimental snapshot of a CGE design hierarchy. }
  TDesignSandboxEntry = class
  public
    Name: String;
    Description: String;
    DesignUrl: String;
    CreatedAtIso: String;
    RootClassName: String;
    ComponentCount: Integer;
    SerializedJson: String;
  end;

  TDesignSandboxEntryList = {$ifdef FPC}specialize{$endif} TObjectList<TDesignSandboxEntry>;

  { Manages named non-destructive design sandboxes in memory and on disk. }
  TDesignSandboxManager = class
  strict private
    FEntries: TDesignSandboxEntryList;
    function GetCount: Integer;
    function GetEntry(const Index: Integer): TDesignSandboxEntry;
    class procedure InspectSerializedJson(const AJson: String;
      out ARootClassName: String; out AComponentCount: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;

    { Create a new sandbox or overwrite an existing sandbox with the same Name + DesignUrl. }
    function CreateOrUpdateSandbox(const AName, ADescription, ADesignUrl: String;
      const DesignRoot: TComponent): TDesignSandboxEntry;
    function CreateOrUpdateSandboxFromJson(const AName, ADescription, ADesignUrl,
      ASerializedJson: String): TDesignSandboxEntry;

    function FindSandbox(const AName: String;
      const ADesignUrl: String = ''): TDesignSandboxEntry;
    function DeleteSandbox(const AName: String;
      const ADesignUrl: String = ''): Boolean;
    function RenameSandbox(const OldName, NewName: String;
      const ADesignUrl: String = ''): Boolean;

    { Populate OutList with TDesignSandboxEntry pointers matching ADesignUrl
      (or all sandboxes when ADesignUrl = ''). OutList does not own the items. }
    procedure ListSandboxesForDesign(const ADesignUrl: String; const OutList: Classes.TList);

    { Instantiate Entry.SerializedJson into NewOwner, optionally preserving
      3D design-time viewport camera/navigation state from PreserveDataFrom. }
    function InstantiateSandbox(const Entry: TDesignSandboxEntry;
      const NewOwner: TComponent;
      const PreserveDataFrom: TComponent = nil): TComponent;

    function SaveToJsonString: String;
    procedure LoadFromJsonString(const JsonText: String);
    procedure SaveToFile(const FileName: String);
    procedure LoadFromFile(const FileName: String);

    property Count: Integer read GetCount;
    property Entries[const Index: Integer]: TDesignSandboxEntry read GetEntry; default;
  end;

  { Classification of a component between Base and Target designs. }
  TDesignDiffKind = (
    ddkAdded,
    ddkRemoved,
    ddkModified,
    ddkUnchanged
  );

  { A single RTTI / serialized property difference on a component. }
  TDesignPropertyDiff = class
  public
    { Dot-separated property path relative to the component, e.g. 'Caption'
      or 'TranslationPersistent.Value' or 'Border.AllSides'. }
    PropertyPath: String;
    { Canonical value in Base ('<default>' when omitted because at default). }
    BaseValueText: String;
    { Canonical value in Target ('<default>' when omitted because at default). }
    TargetValueText: String;
  end;

  TDesignPropertyDiffList = {$ifdef FPC}specialize{$endif} TObjectList<TDesignPropertyDiff>;

  { Hierarchy and property diff record for a single named component. }
  TDesignComponentDiff = class
  public
    ComponentName: String;
    BaseClassName: String;
    TargetClassName: String;
    BaseHierarchyPath: String;
    TargetHierarchyPath: String;
    BaseParentName: String;
    TargetParentName: String;
    BaseContainerKey: String;
    TargetContainerKey: String;
    DiffKind: TDesignDiffKind;
    PropertyDiffs: TDesignPropertyDiffList;

    constructor Create;
    destructor Destroy; override;
    function DisplayClassName: String;
    function SummaryBadge: String;
  end;

  TDesignComponentDiffList = {$ifdef FPC}specialize{$endif} TObjectList<TDesignComponentDiff>;

  { Complete diff report between a Base design and a Target design. }
  TDesignDiffReport = class
  public
    BaseLabel: String;
    TargetLabel: String;
    Components: TDesignComponentDiffList;
    AddedCount: Integer;
    RemovedCount: Integer;
    ModifiedCount: Integer;
    UnchangedCount: Integer;
    TotalPropertyChanges: Integer;

    constructor Create;
    destructor Destroy; override;
    function HasDifferences: Boolean;
    function FindComponentDiff(const AComponentName: String): TDesignComponentDiff;
    function SummaryLine: String;
    function FormatUnifiedSummary: String;
  end;

  { Structural JSON diff & selective revert/merge engine for CGE designs. }
  TDesignDiffEngine = class
  public
    { Compare two CGE serialized JSON strings (from ComponentToString or disk files). }
    class function CompareJson(const BaseJson, TargetJson: String;
      const BaseLabel: String = 'Saved / Base';
      const TargetLabel: String = 'Current Design';
      const IncludeUnchanged: Boolean = false): TDesignDiffReport;

    { Compare two live TComponent hierarchies directly in memory. }
    class function CompareComponents(const BaseRoot, TargetRoot: TComponent;
      const BaseLabel: String = 'Base';
      const TargetLabel: String = 'Current';
      const IncludeUnchanged: Boolean = false): TDesignDiffReport;

    { Selectively revert chosen components and/or individual properties in
      TargetJson back to their BaseJson state, returning valid CGE design JSON.
      - RevertComponents: component names to revert completely:
          * ddkAdded   -> removed from TargetJson
          * ddkRemoved -> restored from BaseJson into TargetJson
          * ddkModified -> all component properties reverted to BaseJson while
                           keeping TargetJson's child component lists intact
      - RevertProperties: entries formatted as 'ComponentName::PropertyPath'
        (e.g. 'Crate1::TranslationPersistent.Value' or 'LabelTitle::Caption'). }
    class function RevertSelectedToBase(const BaseJson, TargetJson: String;
      const RevertComponents: TStrings;
      const RevertProperties: TStrings): String;
  end;

function DesignDiffKindToBadge(const Kind: TDesignDiffKind): String;

implementation

uses Contnrs, DateUtils, JsonParser,
  CastleUtils, CastleStringUtils, CastleComponentSerialize;

const
  DefaultOmittedMarker = '<default>';

function DesignDiffKindToBadge(const Kind: TDesignDiffKind): String;
begin
  case Kind of
    ddkAdded: Result := '[+ Added]';
    ddkRemoved: Result := '[- Removed]';
    ddkModified: Result := '[~ Modified]';
    ddkUnchanged: Result := '[= Unchanged]';
  end;
end;

{ Canonical JSON value formatting so float representation noise does not cause false diffs }

function CanonicalJsonData(const Data: TJSONData): String;
var
  I: Integer;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Keys: TStringList;
  Builder: String;
begin
  if Data = nil then
    Exit('null');

  case Data.JSONType of
    jtNull:
      Result := 'null';
    jtBoolean:
      if Data.AsBoolean then
        Result := 'true'
      else
        Result := 'false';
    jtNumber:
      begin
        if TJSONNumber(Data).NumberType = ntFloat then
          Result := FormatFloat('0.######', Data.AsFloat, DefaultFormatSettings)
        else
          Result := IntToStr(Data.AsInt64);
      end;
    jtString:
      Result := '"' + StringReplace(StringReplace(Data.AsString, '\', '\\', [rfReplaceAll]),
        '"', '\"', [rfReplaceAll]) + '"';
    jtArray:
      begin
        Arr := TJSONArray(Data);
        Builder := '[';
        for I := 0 to Arr.Count - 1 do
        begin
          if I > 0 then
            Builder := Builder + ', ';
          Builder := Builder + CanonicalJsonData(Arr.Items[I]);
        end;
        Result := Builder + ']';
      end;
    jtObject:
      begin
        Obj := TJSONObject(Data);
        Keys := TStringList.Create;
        try
          Keys.CaseSensitive := true;
          for I := 0 to Obj.Count - 1 do
            Keys.Add(Obj.Names[I]);
          Keys.Sort;
          Builder := '{';
          for I := 0 to Keys.Count - 1 do
          begin
            if I > 0 then
              Builder := Builder + ', ';
            Builder := Builder + '"' + Keys[I] + '": ' +
              CanonicalJsonData(Obj.Find(Keys[I]));
          end;
          Result := Builder + '}';
        finally
          FreeAndNil(Keys);
        end;
      end;
  else
    Result := Data.AsJSON;
  end;
end;

type
  { Internal indexed representation of a named component inside a CGE JSON AST. }
  TIndexedJsonComponent = class
  public
    ComponentName: String;
    ClassNameStr: String;
    HierarchyPath: String;
    ParentName: String;
    ContainerKey: String;
    JsonObj: TJSONObject;
    ParentCompObj: TJSONObject;
    ParentArray: TJSONArray;
    { Sorted 'PropertyPath=CanonicalValue' pairs }
    Properties: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  TIndexedJsonComponentList = {$ifdef FPC}specialize{$endif} TObjectList<TIndexedJsonComponent>;

constructor TIndexedJsonComponent.Create;
begin
  inherited Create;
  Properties := TStringList.Create;
  Properties.NameValueSeparator := '=';
  Properties.CaseSensitive := true;
end;

destructor TIndexedJsonComponent.Destroy;
begin
  FreeAndNil(Properties);
  inherited;
end;

function FindIndexedComponent(const List: TIndexedJsonComponentList;
  const AName: String): TIndexedJsonComponent;
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
    if List[I].ComponentName = AName then
      Exit(List[I]);
  Result := nil;
end;

procedure IndexDesignJsonTree(const RootObj: TJSONObject;
  const OutList: TIndexedJsonComponentList);

  procedure CollectComponentPropertiesAndChildren(const CompEntry: TIndexedJsonComponent;
    const CurrentObj: TJSONObject; const SubPrefix: String);
  var
    I, J: Integer;
    Key, FullKey, ChildName: String;
    Val, ArrItem: TJSONData;
    SubObj, ChildObj: TJSONObject;
    ChildArr: TJSONArray;
    ChildEntry: TIndexedJsonComponent;
  begin
    for I := 0 to CurrentObj.Count - 1 do
    begin
      Key := CurrentObj.Names[I];
      Val := CurrentObj.Items[I];

      if (SubPrefix = '') and ((Key = '$$ClassName') or (Key = 'Name')) then
        Continue;
      if (SubPrefix <> '') and (Key = '$$ClassName') then
        Continue;

      FullKey := SubPrefix + Key;

      { Child component lists in CGE JSON start with '$' (e.g. '$Children',
        '$Behaviors', '$NonVisualComponents', or 'Items.$Children'). }
      if (Length(Key) > 0) and (Key[1] = '$') and (Val is TJSONArray) then
      begin
        ChildArr := TJSONArray(Val);
        for J := 0 to ChildArr.Count - 1 do
        begin
          ArrItem := ChildArr.Items[J];
          if ArrItem is TJSONObject then
          begin
            ChildObj := TJSONObject(ArrItem);
            ChildName := ChildObj.Get('Name', '');
            if ChildName = '' then
              ChildName := Format('%s#%d', [ChildObj.Get('$$ClassName', 'Component'), J]);

            ChildEntry := TIndexedJsonComponent.Create;
            ChildEntry.ComponentName := ChildName;
            ChildEntry.ClassNameStr := ChildObj.Get('$$ClassName', '');
            ChildEntry.ParentName := CompEntry.ComponentName;
            ChildEntry.ContainerKey := FullKey;
            ChildEntry.HierarchyPath := CompEntry.HierarchyPath + '/' + ChildName;
            ChildEntry.JsonObj := ChildObj;
            ChildEntry.ParentCompObj := CompEntry.JsonObj;
            ChildEntry.ParentArray := ChildArr;
            OutList.Add(ChildEntry);

            CollectComponentPropertiesAndChildren(ChildEntry, ChildObj, '');
          end;
        end;
      end else
      if (Val is TJSONObject) and (TJSONObject(Val).Find('Name') = nil) then
      begin
        { Subcomponent without its own Name (e.g. TranslationPersistent,
          ScalePersistent, RotationPersistent, Border, Projection, Items). }
        SubObj := TJSONObject(Val);
        CollectComponentPropertiesAndChildren(CompEntry, SubObj, FullKey + '.');
      end else
      if (Val is TJSONObject) and (TJSONObject(Val).Find('Name') <> nil) then
      begin
        { Named inline object property }
        ChildObj := TJSONObject(Val);
        ChildName := ChildObj.Get('Name', '');
        ChildEntry := TIndexedJsonComponent.Create;
        ChildEntry.ComponentName := ChildName;
        ChildEntry.ClassNameStr := ChildObj.Get('$$ClassName', '');
        ChildEntry.ParentName := CompEntry.ComponentName;
        ChildEntry.ContainerKey := FullKey;
        ChildEntry.HierarchyPath := CompEntry.HierarchyPath + '/' + ChildName;
        ChildEntry.JsonObj := ChildObj;
        ChildEntry.ParentCompObj := CompEntry.JsonObj;
        ChildEntry.ParentArray := nil;
        OutList.Add(ChildEntry);
        CollectComponentPropertiesAndChildren(ChildEntry, ChildObj, '');
      end else
      begin
        CompEntry.Properties.Values[FullKey] := CanonicalJsonData(Val);
      end;
    end;
  end;

var
  RootEntry: TIndexedJsonComponent;
  RootName: String;
begin
  if RootObj = nil then
    Exit;

  RootName := RootObj.Get('Name', '');
  if RootName = '' then
    RootName := RootObj.Get('$$ClassName', 'Root');

  RootEntry := TIndexedJsonComponent.Create;
  RootEntry.ComponentName := RootName;
  RootEntry.ClassNameStr := RootObj.Get('$$ClassName', '');
  RootEntry.ParentName := '';
  RootEntry.ContainerKey := '';
  RootEntry.HierarchyPath := RootName;
  RootEntry.JsonObj := RootObj;
  RootEntry.ParentCompObj := nil;
  RootEntry.ParentArray := nil;
  OutList.Add(RootEntry);

  CollectComponentPropertiesAndChildren(RootEntry, RootObj, '');
end;

{ TDesignSandboxManager ------------------------------------------------------ }

constructor TDesignSandboxManager.Create;
begin
  inherited Create;
  FEntries := TDesignSandboxEntryList.Create(true);
end;

destructor TDesignSandboxManager.Destroy;
begin
  FreeAndNil(FEntries);
  inherited;
end;

function TDesignSandboxManager.GetCount: Integer;
begin
  Result := FEntries.Count;
end;

function TDesignSandboxManager.GetEntry(const Index: Integer): TDesignSandboxEntry;
begin
  Result := FEntries[Index];
end;

procedure TDesignSandboxManager.Clear;
begin
  FEntries.Clear;
end;

class procedure TDesignSandboxManager.InspectSerializedJson(const AJson: String;
  out ARootClassName: String; out AComponentCount: Integer);
var
  Parsed: TJSONData;
  Indexed: TIndexedJsonComponentList;
begin
  ARootClassName := '';
  AComponentCount := 0;
  if Trim(AJson) = '' then
    Exit;

  Parsed := nil;
  Indexed := TIndexedJsonComponentList.Create(true);
  try
    try
      Parsed := GetJSON(AJson);
      if Parsed is TJSONObject then
      begin
        IndexDesignJsonTree(TJSONObject(Parsed), Indexed);
        AComponentCount := Indexed.Count;
        if Indexed.Count > 0 then
          ARootClassName := Indexed[0].ClassNameStr;
      end;
    except
      { Keep fallback empty metadata if invalid JSON }
    end;
  finally
    FreeAndNil(Indexed);
    FreeAndNil(Parsed);
  end;
end;

function TDesignSandboxManager.CreateOrUpdateSandbox(
  const AName, ADescription, ADesignUrl: String;
  const DesignRoot: TComponent): TDesignSandboxEntry;
begin
  if DesignRoot = nil then
    raise Exception.Create('Cannot create a Design Sandbox from a nil DesignRoot.');
  Result := CreateOrUpdateSandboxFromJson(
    AName, ADescription, ADesignUrl, ComponentToString(DesignRoot));
end;

function TDesignSandboxManager.CreateOrUpdateSandboxFromJson(
  const AName, ADescription, ADesignUrl, ASerializedJson: String): TDesignSandboxEntry;
var
  CleanName: String;
  RootCls: String;
  CompCnt: Integer;
begin
  CleanName := Trim(AName);
  if CleanName = '' then
    raise Exception.Create('Design Sandbox name cannot be empty.');

  InspectSerializedJson(ASerializedJson, RootCls, CompCnt);

  Result := FindSandbox(CleanName, ADesignUrl);
  if Result = nil then
  begin
    Result := TDesignSandboxEntry.Create;
    FEntries.Add(Result);
  end;

  Result.Name := CleanName;
  Result.Description := Trim(ADescription);
  Result.DesignUrl := ADesignUrl;
  Result.CreatedAtIso := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', Now);
  Result.RootClassName := RootCls;
  Result.ComponentCount := CompCnt;
  Result.SerializedJson := ASerializedJson;
end;

function TDesignSandboxManager.FindSandbox(const AName: String;
  const ADesignUrl: String): TDesignSandboxEntry;
var
  I: Integer;
  E: TDesignSandboxEntry;
begin
  for I := 0 to FEntries.Count - 1 do
  begin
    E := FEntries[I];
    if SameText(E.Name, Trim(AName)) and
       ((ADesignUrl = '') or (E.DesignUrl = '') or SameText(E.DesignUrl, ADesignUrl)) then
      Exit(E);
  end;
  Result := nil;
end;

function TDesignSandboxManager.DeleteSandbox(const AName: String;
  const ADesignUrl: String): Boolean;
var
  E: TDesignSandboxEntry;
begin
  E := FindSandbox(AName, ADesignUrl);
  Result := E <> nil;
  if Result then
    FEntries.Remove(E);
end;

function TDesignSandboxManager.RenameSandbox(const OldName, NewName: String;
  const ADesignUrl: String): Boolean;
var
  E, Existing: TDesignSandboxEntry;
  CleanNew: String;
begin
  CleanNew := Trim(NewName);
  if CleanNew = '' then
    Exit(false);
  E := FindSandbox(OldName, ADesignUrl);
  if E = nil then
    Exit(false);
  Existing := FindSandbox(CleanNew, ADesignUrl);
  if (Existing <> nil) and (Existing <> E) then
    Exit(false);
  E.Name := CleanNew;
  Result := true;
end;

procedure TDesignSandboxManager.ListSandboxesForDesign(const ADesignUrl: String;
  const OutList: Classes.TList);
var
  I: Integer;
  E: TDesignSandboxEntry;
begin
  OutList.Clear;
  for I := 0 to FEntries.Count - 1 do
  begin
    E := FEntries[I];
    if (ADesignUrl = '') or (E.DesignUrl = '') or SameText(E.DesignUrl, ADesignUrl) then
      OutList.Add(E);
  end;
end;

function TDesignSandboxManager.InstantiateSandbox(
  const Entry: TDesignSandboxEntry; const NewOwner: TComponent;
  const PreserveDataFrom: TComponent): TComponent;
var
  LoadInfo: TInternalComponentLoadInfo;
begin
  if Entry = nil then
    raise Exception.Create('Cannot instantiate nil Design Sandbox.');

  LoadInfo := TInternalComponentLoadInfo.Create;
  try
    LoadInfo.PreserveDataAcrossUndo := PreserveDataFrom;
    Result := InternalStringToComponent(Entry.SerializedJson, NewOwner, LoadInfo);
  finally
    FreeAndNil(LoadInfo);
  end;
end;

function TDesignSandboxManager.SaveToJsonString: String;
var
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  E: TDesignSandboxEntry;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('version', 1);
    Arr := TJSONArray.Create;
    for I := 0 to FEntries.Count - 1 do
    begin
      E := FEntries[I];
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', E.Name);
      ItemObj.Add('description', E.Description);
      ItemObj.Add('designUrl', E.DesignUrl);
      ItemObj.Add('createdAtIso', E.CreatedAtIso);
      ItemObj.Add('rootClassName', E.RootClassName);
      ItemObj.Add('componentCount', E.ComponentCount);
      ItemObj.Add('serializedJson', E.SerializedJson);
      Arr.Add(ItemObj);
    end;
    RootObj.Add('sandboxes', Arr);
    Result := RootObj.FormatJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TDesignSandboxManager.LoadFromJsonString(const JsonText: String);
var
  Parsed, ArrNode: TJSONData;
  Arr: TJSONArray;
  ItemObj: TJSONObject;
  I: Integer;
  E: TDesignSandboxEntry;
begin
  Clear;
  if Trim(JsonText) = '' then
    Exit;

  Parsed := GetJSON(JsonText);
  try
    if not (Parsed is TJSONObject) then
      Exit;
    ArrNode := TJSONObject(Parsed).Find('sandboxes');
    if not (ArrNode is TJSONArray) then
      Exit;
    Arr := TJSONArray(ArrNode);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        ItemObj := TJSONObject(Arr.Items[I]);
        E := TDesignSandboxEntry.Create;
        E.Name := ItemObj.Get('name', '');
        E.Description := ItemObj.Get('description', '');
        E.DesignUrl := ItemObj.Get('designUrl', '');
        E.CreatedAtIso := ItemObj.Get('createdAtIso', '');
        E.RootClassName := ItemObj.Get('rootClassName', '');
        E.ComponentCount := ItemObj.Get('componentCount', 0);
        E.SerializedJson := ItemObj.Get('serializedJson', '');
        if E.Name <> '' then
          FEntries.Add(E)
        else
          FreeAndNil(E);
      end;
  finally
    FreeAndNil(Parsed);
  end;
end;

procedure TDesignSandboxManager.SaveToFile(const FileName: String);
var
  DirPath: String;
  SL: TStringList;
begin
  DirPath := ExtractFileDir(FileName);
  if (DirPath <> '') and (not DirectoryExists(DirPath)) then
    ForceDirectories(DirPath);

  SL := TStringList.Create;
  try
    SL.Text := SaveToJsonString;
    SL.SaveToFile(FileName);
  finally
    FreeAndNil(SL);
  end;
end;

procedure TDesignSandboxManager.LoadFromFile(const FileName: String);
var
  SL: TStringList;
begin
  Clear;
  if not FileExists(FileName) then
    Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    LoadFromJsonString(SL.Text);
  finally
    FreeAndNil(SL);
  end;
end;

{ TDesignComponentDiff ------------------------------------------------------- }

constructor TDesignComponentDiff.Create;
begin
  inherited Create;
  PropertyDiffs := TDesignPropertyDiffList.Create(true);
end;

destructor TDesignComponentDiff.Destroy;
begin
  FreeAndNil(PropertyDiffs);
  inherited;
end;

function TDesignComponentDiff.DisplayClassName: String;
begin
  if TargetClassName <> '' then
    Result := TargetClassName
  else
    Result := BaseClassName;
end;

function TDesignComponentDiff.SummaryBadge: String;
begin
  Result := DesignDiffKindToBadge(DiffKind);
end;

{ TDesignDiffReport ---------------------------------------------------------- }

constructor TDesignDiffReport.Create;
begin
  inherited Create;
  Components := TDesignComponentDiffList.Create(true);
end;

destructor TDesignDiffReport.Destroy;
begin
  FreeAndNil(Components);
  inherited;
end;

function TDesignDiffReport.HasDifferences: Boolean;
begin
  Result := (AddedCount > 0) or (RemovedCount > 0) or (ModifiedCount > 0);
end;

function TDesignDiffReport.FindComponentDiff(
  const AComponentName: String): TDesignComponentDiff;
var
  I: Integer;
begin
  for I := 0 to Components.Count - 1 do
    if Components[I].ComponentName = AComponentName then
      Exit(Components[I]);
  Result := nil;
end;

function TDesignDiffReport.SummaryLine: String;
begin
  if not HasDifferences then
    Result := Format('[%s] vs [%s]: Identical (0 differences across %d components)',
      [BaseLabel, TargetLabel, UnchangedCount])
  else
    Result := Format('[%s] -> [%s]: +%d Added, -%d Removed, ~%d Modified (%d property changes)',
      [BaseLabel, TargetLabel, AddedCount, RemovedCount, ModifiedCount, TotalPropertyChanges]);
end;

function TDesignDiffReport.FormatUnifiedSummary: String;
var
  SL: TStringList;
  I, J: Integer;
  CD: TDesignComponentDiff;
  PD: TDesignPropertyDiff;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Castle Game Engine Visual Design Diff Report');
    SL.Add(SummaryLine);
    SL.Add('');
    for I := 0 to Components.Count - 1 do
    begin
      CD := Components[I];
      case CD.DiffKind of
        ddkAdded:
          SL.Add(Format('+ %s (%s) at %s',
            [CD.ComponentName, CD.TargetClassName, CD.TargetHierarchyPath]));
        ddkRemoved:
          SL.Add(Format('- %s (%s) was at %s',
            [CD.ComponentName, CD.BaseClassName, CD.BaseHierarchyPath]));
        ddkModified:
          begin
            SL.Add(Format('~ %s (%s)', [CD.ComponentName, CD.DisplayClassName]));
            for J := 0 to CD.PropertyDiffs.Count - 1 do
            begin
              PD := CD.PropertyDiffs[J];
              SL.Add(Format('    * %s: %s -> %s',
                [PD.PropertyPath, PD.BaseValueText, PD.TargetValueText]));
            end;
          end;
        ddkUnchanged:
          SL.Add(Format('= %s (%s)', [CD.ComponentName, CD.DisplayClassName]));
      end;
    end;
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

{ TDesignDiffEngine ---------------------------------------------------------- }

class function TDesignDiffEngine.CompareComponents(
  const BaseRoot, TargetRoot: TComponent;
  const BaseLabel, TargetLabel: String;
  const IncludeUnchanged: Boolean): TDesignDiffReport;
var
  BaseStr, TargetStr: String;
begin
  if BaseRoot <> nil then
    BaseStr := ComponentToString(BaseRoot)
  else
    BaseStr := '';
  if TargetRoot <> nil then
    TargetStr := ComponentToString(TargetRoot)
  else
    TargetStr := '';
  Result := CompareJson(BaseStr, TargetStr, BaseLabel, TargetLabel, IncludeUnchanged);
end;

class function TDesignDiffEngine.CompareJson(
  const BaseJson, TargetJson: String;
  const BaseLabel, TargetLabel: String;
  const IncludeUnchanged: Boolean): TDesignDiffReport;
var
  BaseData, TargetData: TJSONData;
  BaseList, TargetList: TIndexedJsonComponentList;
  BaseComp, TargetComp: TIndexedJsonComponent;
  AllPropKeys: TStringList;
  CompDiff: TDesignComponentDiff;
  PropDiff: TDesignPropertyDiff;
  I, J: Integer;
  PropKey, BaseVal, TargetVal: String;
begin
  Result := TDesignDiffReport.Create;
  Result.BaseLabel := BaseLabel;
  Result.TargetLabel := TargetLabel;

  BaseData := nil;
  TargetData := nil;
  BaseList := TIndexedJsonComponentList.Create(true);
  TargetList := TIndexedJsonComponentList.Create(true);
  AllPropKeys := TStringList.Create;
  try
    AllPropKeys.CaseSensitive := true;
    AllPropKeys.Sorted := true;
    AllPropKeys.Duplicates := dupIgnore;

    if Trim(BaseJson) <> '' then
    begin
      BaseData := GetJSON(BaseJson);
      if BaseData is TJSONObject then
        IndexDesignJsonTree(TJSONObject(BaseData), BaseList);
    end;

    if Trim(TargetJson) <> '' then
    begin
      TargetData := GetJSON(TargetJson);
      if TargetData is TJSONObject then
        IndexDesignJsonTree(TJSONObject(TargetData), TargetList);
    end;

    { 1. Inspect all components present in Target (Added, Modified, or Unchanged) }
    for I := 0 to TargetList.Count - 1 do
    begin
      TargetComp := TargetList[I];
      BaseComp := FindIndexedComponent(BaseList, TargetComp.ComponentName);

      if BaseComp = nil then
      begin
        CompDiff := TDesignComponentDiff.Create;
        CompDiff.ComponentName := TargetComp.ComponentName;
        CompDiff.TargetClassName := TargetComp.ClassNameStr;
        CompDiff.TargetHierarchyPath := TargetComp.HierarchyPath;
        CompDiff.TargetParentName := TargetComp.ParentName;
        CompDiff.TargetContainerKey := TargetComp.ContainerKey;
        CompDiff.DiffKind := ddkAdded;
        Result.Components.Add(CompDiff);
        Inc(Result.AddedCount);
      end else
      begin
        CompDiff := TDesignComponentDiff.Create;
        CompDiff.ComponentName := TargetComp.ComponentName;
        CompDiff.BaseClassName := BaseComp.ClassNameStr;
        CompDiff.TargetClassName := TargetComp.ClassNameStr;
        CompDiff.BaseHierarchyPath := BaseComp.HierarchyPath;
        CompDiff.TargetHierarchyPath := TargetComp.HierarchyPath;
        CompDiff.BaseParentName := BaseComp.ParentName;
        CompDiff.TargetParentName := TargetComp.ParentName;
        CompDiff.BaseContainerKey := BaseComp.ContainerKey;
        CompDiff.TargetContainerKey := TargetComp.ContainerKey;

        if BaseComp.ClassNameStr <> TargetComp.ClassNameStr then
        begin
          PropDiff := TDesignPropertyDiff.Create;
          PropDiff.PropertyPath := '$$ClassName';
          PropDiff.BaseValueText := '"' + BaseComp.ClassNameStr + '"';
          PropDiff.TargetValueText := '"' + TargetComp.ClassNameStr + '"';
          CompDiff.PropertyDiffs.Add(PropDiff);
        end;

        if BaseComp.ParentName <> TargetComp.ParentName then
        begin
          PropDiff := TDesignPropertyDiff.Create;
          PropDiff.PropertyPath := '$Parent';
          PropDiff.BaseValueText := '"' + BaseComp.ParentName + '"';
          PropDiff.TargetValueText := '"' + TargetComp.ParentName + '"';
          CompDiff.PropertyDiffs.Add(PropDiff);
        end;

        AllPropKeys.Clear;
        for J := 0 to BaseComp.Properties.Count - 1 do
          AllPropKeys.Add(BaseComp.Properties.Names[J]);
        for J := 0 to TargetComp.Properties.Count - 1 do
          AllPropKeys.Add(TargetComp.Properties.Names[J]);

        for J := 0 to AllPropKeys.Count - 1 do
        begin
          PropKey := AllPropKeys[J];
          if BaseComp.Properties.IndexOfName(PropKey) >= 0 then
            BaseVal := BaseComp.Properties.Values[PropKey]
          else
            BaseVal := DefaultOmittedMarker;

          if TargetComp.Properties.IndexOfName(PropKey) >= 0 then
            TargetVal := TargetComp.Properties.Values[PropKey]
          else
            TargetVal := DefaultOmittedMarker;

          if BaseVal <> TargetVal then
          begin
            PropDiff := TDesignPropertyDiff.Create;
            PropDiff.PropertyPath := PropKey;
            PropDiff.BaseValueText := BaseVal;
            PropDiff.TargetValueText := TargetVal;
            CompDiff.PropertyDiffs.Add(PropDiff);
          end;
        end;

        if CompDiff.PropertyDiffs.Count > 0 then
        begin
          CompDiff.DiffKind := ddkModified;
          Inc(Result.ModifiedCount);
          Inc(Result.TotalPropertyChanges, CompDiff.PropertyDiffs.Count);
          Result.Components.Add(CompDiff);
        end else
        begin
          Inc(Result.UnchangedCount);
          if IncludeUnchanged then
          begin
            CompDiff.DiffKind := ddkUnchanged;
            Result.Components.Add(CompDiff);
          end else
            FreeAndNil(CompDiff);
        end;
      end;
    end;

    { 2. Inspect components present in Base but missing in Target (Removed) }
    for I := 0 to BaseList.Count - 1 do
    begin
      BaseComp := BaseList[I];
      if FindIndexedComponent(TargetList, BaseComp.ComponentName) = nil then
      begin
        CompDiff := TDesignComponentDiff.Create;
        CompDiff.ComponentName := BaseComp.ComponentName;
        CompDiff.BaseClassName := BaseComp.ClassNameStr;
        CompDiff.BaseHierarchyPath := BaseComp.HierarchyPath;
        CompDiff.BaseParentName := BaseComp.ParentName;
        CompDiff.BaseContainerKey := BaseComp.ContainerKey;
        CompDiff.DiffKind := ddkRemoved;
        Result.Components.Add(CompDiff);
        Inc(Result.RemovedCount);
      end;
    end;
  finally
    FreeAndNil(AllPropKeys);
    FreeAndNil(TargetList);
    FreeAndNil(BaseList);
    FreeAndNil(TargetData);
    FreeAndNil(BaseData);
  end;
end;

{ JSON manipulation helpers for RevertSelectedToBase }

function SplitDotPath(const DotPath: String): TCastleStringList;
begin
  Result := CreateTokens(DotPath, ['.']);
end;

function FindJsonByPath(const RootObj: TJSONObject;
  const Parts: TCastleStringList): TJSONData;
var
  Curr: TJSONData;
  I: Integer;
begin
  Result := nil;
  if (RootObj = nil) or (Parts.Count = 0) then
    Exit;
  Curr := RootObj;
  for I := 0 to Parts.Count - 1 do
  begin
    if not (Curr is TJSONObject) then
      Exit(nil);
    Curr := TJSONObject(Curr).Find(Parts[I]);
    if Curr = nil then
      Exit(nil);
  end;
  Result := Curr;
end;

function EnsureJsonObjectPath(const TargetObj, BaseObj: TJSONObject;
  const Parts: TCastleStringList; const CountToEnsure: Integer): TJSONObject;
var
  CurrTarget, CurrBase, NextTarget: TJSONObject;
  BaseSubNode, ExistingNode: TJSONData;
  I: Integer;
  SubClassName: String;
begin
  CurrTarget := TargetObj;
  CurrBase := BaseObj;
  for I := 0 to CountToEnsure - 1 do
  begin
    BaseSubNode := nil;
    if CurrBase <> nil then
      BaseSubNode := CurrBase.Find(Parts[I]);

    ExistingNode := CurrTarget.Find(Parts[I]);
    if ExistingNode is TJSONObject then
      NextTarget := TJSONObject(ExistingNode)
    else
    begin
      if ExistingNode <> nil then
        CurrTarget.Delete(Parts[I]);
      NextTarget := TJSONObject.Create;
      if BaseSubNode is TJSONObject then
      begin
        SubClassName := TJSONObject(BaseSubNode).Get('$$ClassName', '');
        if SubClassName <> '' then
          NextTarget.Add('$$ClassName', SubClassName);
      end else
      if Parts[I] = 'Items' then
        NextTarget.Add('$$ClassName', 'TCastleRootTransform');
      CurrTarget.Add(Parts[I], NextTarget);
    end;

    CurrTarget := NextTarget;
    if BaseSubNode is TJSONObject then
      CurrBase := TJSONObject(BaseSubNode)
    else
      CurrBase := nil;
  end;
  Result := CurrTarget;
end;

function IsEmptySubcomponentJsonObject(const Obj: TJSONObject): Boolean;
var
  I: Integer;
  K: String;
begin
  for I := 0 to Obj.Count - 1 do
  begin
    K := Obj.Names[I];
    if K <> '$$ClassName' then
      Exit(false);
  end;
  Result := true;
end;

procedure RemoveJsonByPathAndPrune(const TargetObj: TJSONObject;
  const Parts: TCastleStringList);
var
  Chain: array of TJSONObject;
  Curr: TJSONData;
  I: Integer;
begin
  if (TargetObj = nil) or (Parts.Count = 0) then
    Exit;

  SetLength(Chain, Parts.Count);
  Curr := TargetObj;
  for I := 0 to Parts.Count - 2 do
  begin
    Chain[I] := TJSONObject(Curr);
    Curr := TJSONObject(Curr).Find(Parts[I]);
    if not (Curr is TJSONObject) then
      Exit;
  end;
  Chain[Parts.Count - 1] := TJSONObject(Curr);

  Chain[Parts.Count - 1].Delete(Parts[Parts.Count - 1]);

  { Walk upwards pruning subcomponent objects that now only hold $$ClassName }
  for I := Parts.Count - 1 downto 1 do
  begin
    if IsEmptySubcomponentJsonObject(Chain[I]) then
      Chain[I - 1].Delete(Parts[I - 1])
    else
      Break;
  end;
end;

function CloneWithoutDollarChildArrays(const SrcObj: TJSONObject): TJSONObject;
var
  I: Integer;
  K: String;
  V: TJSONData;
begin
  Result := TJSONObject.Create;
  for I := 0 to SrcObj.Count - 1 do
  begin
    K := SrcObj.Names[I];
    V := SrcObj.Items[I];
    if (Length(K) > 0) and (K[1] = '$') and (V is TJSONArray) then
      Continue;
    if (V is TJSONObject) and (TJSONObject(V).Find('Name') = nil) then
      Result.Add(K, CloneWithoutDollarChildArrays(TJSONObject(V)))
    else
      Result.Add(K, V.Clone);
  end;
end;

procedure CollectDollarChildArrays(const SrcObj: TJSONObject;
  const Prefix: String; const OutPaths: TStringList; const OutClones: TObjectList);
var
  I: Integer;
  K, FullPath: String;
  V: TJSONData;
begin
  for I := 0 to SrcObj.Count - 1 do
  begin
    K := SrcObj.Names[I];
    V := SrcObj.Items[I];
    FullPath := Prefix + K;
    if (Length(K) > 0) and (K[1] = '$') and (V is TJSONArray) then
    begin
      OutPaths.Add(FullPath);
      OutClones.Add(V.Clone);
    end else
    if (V is TJSONObject) and (TJSONObject(V).Find('Name') = nil) then
      CollectDollarChildArrays(TJSONObject(V), FullPath + '.', OutPaths, OutClones);
  end;
end;

procedure RevertComponentPropertiesPreservingChildren(
  const BaseCompObj, TargetCompObj: TJSONObject);
var
  SavedPaths: TStringList;
  SavedArrays: TObjectList;
  CleanBaseClone, DestParentObj: TJSONObject;
  Parts: TCastleStringList;
  I: Integer;
  LeafKey: String;
begin
  SavedPaths := TStringList.Create;
  SavedArrays := TObjectList.Create(true);
  CleanBaseClone := nil;
  try
    CollectDollarChildArrays(TargetCompObj, '', SavedPaths, SavedArrays);
    CleanBaseClone := CloneWithoutDollarChildArrays(BaseCompObj);

    TargetCompObj.Clear;
    for I := 0 to CleanBaseClone.Count - 1 do
      TargetCompObj.Add(CleanBaseClone.Names[I], CleanBaseClone.Items[I].Clone);

    for I := 0 to SavedPaths.Count - 1 do
    begin
      Parts := SplitDotPath(SavedPaths[I]);
      try
        if Parts.Count > 0 then
        begin
          DestParentObj := EnsureJsonObjectPath(
            TargetCompObj, BaseCompObj, Parts, Parts.Count - 1);
          LeafKey := Parts[Parts.Count - 1];
          DestParentObj.Delete(LeafKey);
          DestParentObj.Add(LeafKey, TJSONData(SavedArrays[I]).Clone);
        end;
      finally
        FreeAndNil(Parts);
      end;
    end;

    { Remove any subcomponent objects from Base (such as an empty Items) that ended up empty }
    for I := TargetCompObj.Count - 1 downto 0 do
      if (TargetCompObj.Items[I] is TJSONObject) and
         (TJSONObject(TargetCompObj.Items[I]).Find('Name') = nil) and
         IsEmptySubcomponentJsonObject(TJSONObject(TargetCompObj.Items[I])) then
        TargetCompObj.Delete(I);
  finally
    FreeAndNil(CleanBaseClone);
    FreeAndNil(SavedArrays);
    FreeAndNil(SavedPaths);
  end;
end;

class function TDesignDiffEngine.RevertSelectedToBase(
  const BaseJson, TargetJson: String;
  const RevertComponents: TStrings;
  const RevertProperties: TStrings): String;
var
  BaseData, TargetData, BaseLeaf: TJSONData;
  BaseRootObj, TargetRootObj, DestParentObj, DestContainerOwner: TJSONObject;
  BaseList, TargetList: TIndexedJsonComponentList;
  BaseComp, TargetComp, TargetParentComp, BaseParentComp: TIndexedJsonComponent;
  Parts: TCastleStringList;
  DestArray: TJSONArray;
  I, J, SepPos: Integer;
  CompName, EntryStr, PropPath, ContainerPath, ArrayKey: String;
begin
  if Trim(TargetJson) = '' then
    Exit(BaseJson);
  if Trim(BaseJson) = '' then
    Exit(TargetJson);

  BaseData := GetJSON(BaseJson);
  TargetData := GetJSON(TargetJson);
  BaseList := TIndexedJsonComponentList.Create(true);
  TargetList := TIndexedJsonComponentList.Create(true);
  try
    if (not (BaseData is TJSONObject)) or (not (TargetData is TJSONObject)) then
      Exit(TargetJson);

    BaseRootObj := TJSONObject(BaseData);
    TargetRootObj := TJSONObject(TargetData);
    IndexDesignJsonTree(BaseRootObj, BaseList);
    IndexDesignJsonTree(TargetRootObj, TargetList);

    { 1. Process full-component reverts (Added -> Delete, Removed -> Restore, Modified -> Revert props) }
    if RevertComponents <> nil then
    begin
      for I := 0 to RevertComponents.Count - 1 do
      begin
        CompName := Trim(RevertComponents[I]);
        if CompName = '' then
          Continue;

        TargetList.Clear;
        IndexDesignJsonTree(TargetRootObj, TargetList);

        BaseComp := FindIndexedComponent(BaseList, CompName);
        TargetComp := FindIndexedComponent(TargetList, CompName);

        if (TargetComp <> nil) and (BaseComp = nil) then
        begin
          { Component was Added in Target -> remove it from its parent array }
          if TargetComp.ParentArray <> nil then
          begin
            for J := TargetComp.ParentArray.Count - 1 downto 0 do
              if TargetComp.ParentArray.Items[J] = TargetComp.JsonObj then
              begin
                TargetComp.ParentArray.Delete(J);
                Break;
              end;
            if (TargetComp.ParentArray.Count = 0) and
               (TargetComp.ParentCompObj <> nil) and
               (TargetComp.ContainerKey <> '') then
            begin
              Parts := SplitDotPath(TargetComp.ContainerKey);
              try
                RemoveJsonByPathAndPrune(TargetComp.ParentCompObj, Parts);
              finally
                FreeAndNil(Parts);
              end;
            end;
          end;
        end else
        if (BaseComp <> nil) and (TargetComp = nil) then
        begin
          { Component was Removed in Target -> restore clone from Base into parent }
          TargetParentComp := FindIndexedComponent(TargetList, BaseComp.ParentName);
          BaseParentComp := FindIndexedComponent(BaseList, BaseComp.ParentName);
          if TargetParentComp = nil then
          begin
            TargetParentComp := TargetList[0];
            ContainerPath := '$Children';
          end else
          begin
            ContainerPath := BaseComp.ContainerKey;
            if ContainerPath = '' then
              ContainerPath := '$Children';
          end;

          Parts := SplitDotPath(ContainerPath);
          try
            if BaseParentComp <> nil then
              DestContainerOwner := EnsureJsonObjectPath(
                TargetParentComp.JsonObj, BaseParentComp.JsonObj, Parts, Parts.Count - 1)
            else
              DestContainerOwner := EnsureJsonObjectPath(
                TargetParentComp.JsonObj, nil, Parts, Parts.Count - 1);

            ArrayKey := Parts[Parts.Count - 1];
            if DestContainerOwner.Find(ArrayKey) is TJSONArray then
              DestArray := TJSONArray(DestContainerOwner.Find(ArrayKey))
            else
            begin
              DestContainerOwner.Delete(ArrayKey);
              DestArray := TJSONArray.Create;
              DestContainerOwner.Add(ArrayKey, DestArray);
            end;
            DestArray.Add(BaseComp.JsonObj.Clone);
          finally
            FreeAndNil(Parts);
          end;
        end else
        if (BaseComp <> nil) and (TargetComp <> nil) then
        begin
          { Component was Modified -> revert all properties while keeping Target children }
          RevertComponentPropertiesPreservingChildren(BaseComp.JsonObj, TargetComp.JsonObj);
        end;
      end;
    end;

    { 2. Process individual property reverts ('ComponentName::PropertyPath') }
    if RevertProperties <> nil then
    begin
      TargetList.Clear;
      IndexDesignJsonTree(TargetRootObj, TargetList);

      for I := 0 to RevertProperties.Count - 1 do
      begin
        EntryStr := Trim(RevertProperties[I]);
        SepPos := Pos('::', EntryStr);
        if SepPos <= 1 then
          Continue;
        CompName := Copy(EntryStr, 1, SepPos - 1);
        PropPath := Copy(EntryStr, SepPos + 2, MaxInt);
        if (PropPath = '') or (PropPath = '$Parent') then
          Continue;

        if (RevertComponents <> nil) and (RevertComponents.IndexOf(CompName) >= 0) then
          Continue;

        BaseComp := FindIndexedComponent(BaseList, CompName);
        TargetComp := FindIndexedComponent(TargetList, CompName);
        if (BaseComp = nil) or (TargetComp = nil) then
          Continue;

        if PropPath = '$$ClassName' then
        begin
          TargetComp.JsonObj.Strings['$$ClassName'] := BaseComp.ClassNameStr;
          Continue;
        end;

        Parts := SplitDotPath(PropPath);
        try
          if Parts.Count = 0 then
            Continue;
          BaseLeaf := FindJsonByPath(BaseComp.JsonObj, Parts);
          if BaseLeaf <> nil then
          begin
            DestParentObj := EnsureJsonObjectPath(
              TargetComp.JsonObj, BaseComp.JsonObj, Parts, Parts.Count - 1);
            DestParentObj.Delete(Parts[Parts.Count - 1]);
            DestParentObj.Add(Parts[Parts.Count - 1], BaseLeaf.Clone);
          end else
          begin
            RemoveJsonByPathAndPrune(TargetComp.JsonObj, Parts);
          end;
        finally
          FreeAndNil(Parts);
        end;
      end;
    end;

    Result := TargetRootObj.FormatJSON;
  finally
    FreeAndNil(TargetList);
    FreeAndNil(BaseList);
    FreeAndNil(TargetData);
    FreeAndNil(BaseData);
  end;
end;

end.
