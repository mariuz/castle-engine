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

{ Live Coding RTTI State Snapshot / Field-Alias Hot-Rehydration Broker and
  Release Package Cook Dependency & Readiness Auditor (Phase 356). }
unit ToolLiveCookAuditor;

{$I castleconf.inc}

interface

uses SysUtils, Classes, fpjson;

type
  { CoreRedirect-style property rename rule applied during Live Coding hot-rehydration. }
  TRttiFieldAliasRule = record
    OldPropName: String;
    NewPropName: String;
    class function Make(const AOldName, ANewName: String): TRttiFieldAliasRule; static;
  end;

  { Summary counters returned after rehydrating a live RTTI snapshot onto a hierarchy. }
  TLiveRehydrateStats = record
    ComponentsMatched: Integer;
    PropertiesRestored: Integer;
    AliasesApplied: Integer;
    UnmatchedSkipped: Integer;
  end;

  { In-memory JSON-backed RTTI property snapshot of all named components in a design. }
  TLiveRttiSnapshot = class
  private
    FRootJson: TJSONObject;
    FCapturedComponentCount: Integer;
    FCapturedPropertyCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function ExportSnapshotJson: String;
    function ImportSnapshotJson(const AJson: String): Boolean;
    procedure SetLegacyPropertyForComponent(const ACompName, APropName: String;
      const AValue: TJSONData);
    property RootJson: TJSONObject read FRootJson;
    property CapturedComponentCount: Integer read FCapturedComponentCount;
    property CapturedPropertyCount: Integer read FCapturedPropertyCount;
  end;

  { Release Package Cook readiness & asset/subsystem validation report. }
  TCookAuditReport = class
  public
    CookReadinessScore: Integer;
    CookReadyToShip: Boolean;
    TotalCookableComponents: Integer;
    BrokenAssetUrlCount: Integer;
    ChooserIssueCount: Integer;
    InvertedSoftBodyCount: Integer;
    TrafficHazardCount: Integer;
    WorldIntegrationIssueCount: Integer;
    EstimatedCookedPayloadKB: Integer;
    Findings: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless Live Coding RTTI snapshot/rehydrate broker and Release Cook auditor. }
  TLiveCodingCookBroker = class
  public
    class function CaptureLiveRttiSnapshot(const RootComp, DesignOwner: TComponent): TLiveRttiSnapshot;
    class function RehydrateLiveRttiSnapshot(const Snap: TLiveRttiSnapshot;
      const RootComp, DesignOwner: TComponent;
      const Aliases: array of TRttiFieldAliasRule): TLiveRehydrateStats;
    class function AuditPackageCookReadiness(const RootComp, DesignOwner: TComponent;
      const CheckDiskUrls: Boolean = False): TCookAuditReport;
    class function GenerateCookAndLiveCodingMarkdown(const RootComp, DesignOwner: TComponent): String;
  end;

implementation

uses Math, TypInfo, jsonparser,
  CastleVectors, CastleUtils, CastleClassUtils, CastleInternalRttiUtils,
  CastleUriUtils, CastleTransform, CastleScene, CastleViewport,
  CastleUIControls, CastleControls,
  CastleChooserTable, CastleTetSoftBody, CastleMassTraffic, ToolStudioHub;

{ TRttiFieldAliasRule -------------------------------------------------------- }

class function TRttiFieldAliasRule.Make(const AOldName, ANewName: String): TRttiFieldAliasRule;
begin
  Result.OldPropName := AOldName;
  Result.NewPropName := ANewName;
end;

{ TLiveRttiSnapshot ---------------------------------------------------------- }

constructor TLiveRttiSnapshot.Create;
begin
  inherited Create;
  FRootJson := TJSONObject.Create;
  Clear;
end;

destructor TLiveRttiSnapshot.Destroy;
begin
  FreeAndNil(FRootJson);
  inherited Destroy;
end;

procedure TLiveRttiSnapshot.Clear;
begin
  FRootJson.Clear;
  FRootJson.Add('components', TJSONObject.Create);
  FCapturedComponentCount := 0;
  FCapturedPropertyCount := 0;
end;

function TLiveRttiSnapshot.ExportSnapshotJson: String;
begin
  Result := FRootJson.AsJSON;
end;

function TLiveRttiSnapshot.ImportSnapshotJson(const AJson: String): Boolean;
var
  Parsed: TJSONData;
  CompsObj: TJSONObject;
  I: Integer;
begin
  Result := False;
  if Trim(AJson) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AJson);
    if (Parsed is TJSONObject) and (TJSONObject(Parsed).Find('components', jtObject) <> nil) then
    begin
      FreeAndNil(FRootJson);
      FRootJson := TJSONObject(Parsed);
      Parsed := nil;
      CompsObj := FRootJson.Objects['components'];
      FCapturedComponentCount := CompsObj.Count;
      FCapturedPropertyCount := 0;
      for I := 0 to CompsObj.Count - 1 do
        if (CompsObj.Items[I] is TJSONObject) and
           (TJSONObject(CompsObj.Items[I]).Find('properties', jtObject) <> nil) then
          Inc(FCapturedPropertyCount, TJSONObject(CompsObj.Items[I]).Objects['properties'].Count);
      Result := True;
    end;
  except
    Result := False;
  end;
  FreeAndNil(Parsed);
end;

procedure TLiveRttiSnapshot.SetLegacyPropertyForComponent(const ACompName, APropName: String;
  const AValue: TJSONData);
var
  CompsObj, CompEntry, PropsObj: TJSONObject;
  Idx: Integer;
begin
  if (Trim(ACompName) = '') or (Trim(APropName) = '') or (AValue = nil) then
  begin
    AValue.Free;
    Exit;
  end;
  CompsObj := FRootJson.Objects['components'];
  CompEntry := CompsObj.Find(ACompName, jtObject) as TJSONObject;
  if CompEntry = nil then
  begin
    CompEntry := TJSONObject.Create;
    CompEntry.Add('className', '');
    PropsObj := TJSONObject.Create;
    CompEntry.Add('properties', PropsObj);
    CompsObj.Add(ACompName, CompEntry);
    Inc(FCapturedComponentCount);
  end else
    PropsObj := CompEntry.Objects['properties'];

  Idx := PropsObj.IndexOfName(APropName);
  if Idx >= 0 then
    PropsObj.Delete(Idx)
  else
    Inc(FCapturedPropertyCount);
  PropsObj.Add(APropName, AValue);
end;

{ TCookAuditReport ----------------------------------------------------------- }

constructor TCookAuditReport.Create;
begin
  inherited Create;
  CookReadinessScore := 100;
  CookReadyToShip := True;
  Findings := TStringList.Create;
end;

destructor TCookAuditReport.Destroy;
begin
  FreeAndNil(Findings);
  inherited Destroy;
end;

{ TLiveCodingCookBroker ------------------------------------------------------ }

class function TLiveCodingCookBroker.CaptureLiveRttiSnapshot(
  const RootComp, DesignOwner: TComponent): TLiveRttiSnapshot;
var
  Visited: TList;
  CompsObj: TJSONObject;

  procedure CaptureObjectProperties(const TargetObj: TObject; const PropsObj: TJSONObject);
  var
    PropList: PPropList;
    PropCount, I: Integer;
    PInfo: PPropInfo;
    PName: String;
    PType: TPropertyType;
    SubObj: TObject;
    Arr: TJSONArray;
    V2: TVector2;
    V3: TVector3;
    V4: TVector4;
  begin
    PropCount := GetPropList(TargetObj.ClassInfo, tkProperties, nil);
    if PropCount <= 0 then Exit;
    GetMem(PropList, PropCount * SizeOf(Pointer));
    try
      GetPropList(TargetObj.ClassInfo, tkProperties, PropList);
      for I := 0 to PropCount - 1 do
      begin
        PInfo := PropList^[I];
        if PInfo^.GetProc = nil then Continue;
        PName := PInfo^.Name;
        if SameText(PName, 'Name') or SameText(PName, 'Tag') then Continue;

        PType := PropertyType(PInfo);
        if (PType <> ptInstance) and (PInfo^.SetProc = nil) then Continue;
        case PType of
          ptInteger:
            begin
              PropsObj.Add(PName, PropertyGetInteger(TargetObj, PInfo));
              Inc(Result.FCapturedPropertyCount);
            end;
          ptFloat:
            begin
              PropsObj.Add(PName, PropertyGetFloat(TargetObj, PInfo));
              Inc(Result.FCapturedPropertyCount);
            end;
          ptString:
            begin
              PropsObj.Add(PName, PropertyGetString(TargetObj, PInfo));
              Inc(Result.FCapturedPropertyCount);
            end;
          ptBoolean:
            begin
              PropsObj.Add(PName, PropertyGetBoolean(TargetObj, PInfo));
              Inc(Result.FCapturedPropertyCount);
            end;
          ptEnumeration:
            begin
              PropsObj.Add(PName, PropertyGetEnum(TargetObj, PInfo));
              Inc(Result.FCapturedPropertyCount);
            end;
          ptInstance:
            begin
              SubObj := PropertyGetInstance(TargetObj, PInfo);
              if SubObj is TCastleVector2Persistent then
              begin
                V2 := TCastleVector2Persistent(SubObj).Value;
                Arr := TJSONArray.Create([V2.X, V2.Y]);
                PropsObj.Add(PName, Arr);
                Inc(Result.FCapturedPropertyCount);
              end else
              if SubObj is TCastleVector3Persistent then
              begin
                V3 := TCastleVector3Persistent(SubObj).Value;
                Arr := TJSONArray.Create([V3.X, V3.Y, V3.Z]);
                PropsObj.Add(PName, Arr);
                Inc(Result.FCapturedPropertyCount);
              end else
              if SubObj is TCastleVector4Persistent then
              begin
                V4 := TCastleVector4Persistent(SubObj).Value;
                Arr := TJSONArray.Create([V4.X, V4.Y, V4.Z, V4.W]);
                PropsObj.Add(PName, Arr);
                Inc(Result.FCapturedPropertyCount);
              end;
            end;
          else ;
        end;
      end;
    finally
      FreeMem(PropList);
    end;
  end;

  procedure VisitComp(const C: TComponent);
  var
    I: Integer;
    CompEntry, PropsObj: TJSONObject;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (Visited.IndexOf(C) >= 0) then Exit;
    Visited.Add(C);
    if csTransient in C.ComponentStyle then Exit;

    if Trim(C.Name) <> '' then
    begin
      CompEntry := TJSONObject.Create;
      CompEntry.Add('className', C.ClassName);
      PropsObj := TJSONObject.Create;
      CaptureObjectProperties(C, PropsObj);
      CompEntry.Add('properties', PropsObj);
      if CompsObj.IndexOfName(C.Name) < 0 then
      begin
        CompsObj.Add(C.Name, CompEntry);
        Inc(Result.FCapturedComponentCount);
      end else
        FreeAndNil(CompEntry);
    end;

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        VisitComp(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      VisitComp(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        VisitComp(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        VisitComp(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        VisitComp(T[I]);
    end;
  end;

var
  I: Integer;
begin
  Result := TLiveRttiSnapshot.Create;
  CompsObj := Result.FRootJson.Objects['components'];
  Visited := TList.Create;
  try
    VisitComp(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        VisitComp(DesignOwner.Components[I]);
  finally
    FreeAndNil(Visited);
  end;
end;

class function TLiveCodingCookBroker.RehydrateLiveRttiSnapshot(
  const Snap: TLiveRttiSnapshot;
  const RootComp, DesignOwner: TComponent;
  const Aliases: array of TRttiFieldAliasRule): TLiveRehydrateStats;

  function FindNamedComp(const AName: String): TComponent;

    function SearchTree(const Node: TComponent): TComponent;
    var
      K: Integer;
      T: TCastleTransform;
      UI: TCastleUserInterface;
    begin
      Result := nil;
      if Node = nil then Exit;
      if SameText(Node.Name, AName) then Exit(Node);
      if Node is TCastleViewport then
      begin
        Result := SearchTree(TCastleViewport(Node).Items);
        if Result <> nil then Exit;
      end;
      if Node is TCastleUserInterface then
      begin
        UI := TCastleUserInterface(Node);
        for K := 0 to UI.ControlsCount - 1 do
        begin
          Result := SearchTree(UI.Controls[K]);
          if Result <> nil then Exit;
        end;
      end;
      if Node is TCastleTransform then
      begin
        T := TCastleTransform(Node);
        for K := 0 to T.BehaviorsCount - 1 do
        begin
          Result := SearchTree(T.Behaviors[K]);
          if Result <> nil then Exit;
        end;
        for K := 0 to T.Count - 1 do
        begin
          Result := SearchTree(T[K]);
          if Result <> nil then Exit;
        end;
      end;
    end;

  begin
    Result := nil;
    if DesignOwner <> nil then
      Result := DesignOwner.FindComponent(AName);
    if (Result = nil) and (RootComp <> nil) then
      Result := RootComp.FindComponent(AName);
    if Result = nil then
      Result := SearchTree(RootComp);
  end;

  function ResolveAlias(const APropName: String; out WasAliased: Boolean): String;
  var
    K: Integer;
  begin
    WasAliased := False;
    Result := APropName;
    for K := 0 to High(Aliases) do
      if SameText(Aliases[K].OldPropName, APropName) then
      begin
        Result := Aliases[K].NewPropName;
        WasAliased := True;
        Exit;
      end;
  end;

  function ApplySingleProp(const TargetObj: TObject; const PropName: String;
    const Val: TJSONData): Boolean;
  var
    PInfo: PPropInfo;
    PType: TPropertyType;
    SubObj: TObject;
    Arr: TJSONArray;
  begin
    Result := False;
    PInfo := GetPropInfo(TargetObj, PropName);
    if (PInfo = nil) or ((PropertyType(PInfo) <> ptInstance) and (PInfo^.SetProc = nil)) then
      PInfo := GetPropInfo(TargetObj, PropName + 'Persistent');
    if PInfo = nil then Exit;

    PType := PropertyType(PInfo);
    try
      case PType of
        ptInteger:
          if Val.JSONType = jtNumber then
          begin
            PropertySetInteger(TargetObj, PInfo, Val.AsInt64);
            Result := True;
          end;
        ptFloat:
          if Val.JSONType = jtNumber then
          begin
            PropertySetFloat(TargetObj, PInfo, Val.AsFloat);
            Result := True;
          end;
        ptString:
          if Val.JSONType = jtString then
          begin
            PropertySetString(TargetObj, PInfo, Val.AsString);
            Result := True;
          end;
        ptBoolean:
          if Val.JSONType = jtBoolean then
          begin
            PropertySetBoolean(TargetObj, PInfo, Val.AsBoolean);
            Result := True;
          end;
        ptEnumeration:
          if Val.JSONType = jtNumber then
          begin
            PropertySetEnum(TargetObj, PInfo, Val.AsInteger);
            Result := True;
          end;
        ptInstance:
          begin
            SubObj := PropertyGetInstance(TargetObj, PInfo);
            if (SubObj is TCastleVector2Persistent) and (Val is TJSONArray) and (TJSONArray(Val).Count >= 2) then
            begin
              Arr := TJSONArray(Val);
              TCastleVector2Persistent(SubObj).Value := Vector2(Arr.Floats[0], Arr.Floats[1]);
              Result := True;
            end else
            if (SubObj is TCastleVector3Persistent) and (Val is TJSONArray) and (TJSONArray(Val).Count >= 3) then
            begin
              Arr := TJSONArray(Val);
              TCastleVector3Persistent(SubObj).Value := Vector3(Arr.Floats[0], Arr.Floats[1], Arr.Floats[2]);
              Result := True;
            end else
            if (SubObj is TCastleVector4Persistent) and (Val is TJSONArray) and (TJSONArray(Val).Count >= 4) then
            begin
              Arr := TJSONArray(Val);
              TCastleVector4Persistent(SubObj).Value := Vector4(Arr.Floats[0], Arr.Floats[1], Arr.Floats[2], Arr.Floats[3]);
              Result := True;
            end;
          end;
        else ;
      end;
    except
      Result := False;
    end;
  end;

var
  CompsObj, CompEntry, PropsObj: TJSONObject;
  CIdx, PIdx: Integer;
  CompName, RawProp, EffectiveProp: String;
  Target: TComponent;
  UsedAlias: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  if (Snap = nil) or (Snap.FRootJson = nil) then Exit;
  CompsObj := Snap.FRootJson.Find('components', jtObject) as TJSONObject;
  if CompsObj = nil then Exit;

  for CIdx := 0 to CompsObj.Count - 1 do
  begin
    CompName := CompsObj.Names[CIdx];
    Target := FindNamedComp(CompName);
    if Target = nil then
    begin
      Inc(Result.UnmatchedSkipped);
      Continue;
    end;
    if not (CompsObj.Items[CIdx] is TJSONObject) then Continue;
    CompEntry := TJSONObject(CompsObj.Items[CIdx]);
    PropsObj := CompEntry.Find('properties', jtObject) as TJSONObject;
    if PropsObj = nil then Continue;

    Inc(Result.ComponentsMatched);
    for PIdx := 0 to PropsObj.Count - 1 do
    begin
      RawProp := PropsObj.Names[PIdx];
      EffectiveProp := ResolveAlias(RawProp, UsedAlias);
      if ApplySingleProp(Target, EffectiveProp, PropsObj.Items[PIdx]) then
      begin
        Inc(Result.PropertiesRestored);
        if UsedAlias then
          Inc(Result.AliasesApplied);
      end else
        Inc(Result.UnmatchedSkipped);
    end;
  end;
end;

class function TLiveCodingCookBroker.AuditPackageCookReadiness(
  const RootComp, DesignOwner: TComponent;
  const CheckDiskUrls: Boolean): TCookAuditReport;
var
  Visited: TList;
  ChooserErrs: TStringList;
  WorldHealth: TStudioWorldHealthReport;

  procedure CheckAssetUrl(const Comp: TComponent; const AUrl: String);
  var
    Trimmed: String;
  begin
    Trimmed := Trim(AUrl);
    if Trimmed = '' then Exit;
    if (Pos('..', Trimmed) > 0) or (AUrl <> Trimmed) then
    begin
      Inc(Result.BrokenAssetUrlCount);
      Result.Findings.Add(Format('[COOK-URL] %s (%s) has unsafe/traversal URL "%s".',
        [Comp.Name, Comp.ClassName, AUrl]));
    end else
    if CheckDiskUrls and (not URIFileExists(Trimmed)) then
    begin
      Inc(Result.BrokenAssetUrlCount);
      Result.Findings.Add(Format('[COOK-URL] %s (%s) references missing asset "%s".',
        [Comp.Name, Comp.ClassName, Trimmed]));
    end;
  end;

  procedure InspectCookComp(const C: TComponent);
  var
    I, PropCount: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
    PropList: PPropList;
    PInfo: PPropInfo;
    PName: String;
  begin
    if (C = nil) or (Visited.IndexOf(C) >= 0) then Exit;
    Visited.Add(C);
    if csTransient in C.ComponentStyle then Exit;

    Inc(Result.TotalCookableComponents);
    Inc(Result.EstimatedCookedPayloadKB, 4);

    PropCount := GetPropList(C.ClassInfo, tkProperties, nil);
    if PropCount > 0 then
    begin
      GetMem(PropList, PropCount * SizeOf(Pointer));
      try
        GetPropList(C.ClassInfo, tkProperties, PropList);
        for I := 0 to PropCount - 1 do
        begin
          PInfo := PropList^[I];
          if (PInfo^.GetProc <> nil) and (PropertyType(PInfo) = ptString) then
          begin
            PName := UpperCase(PInfo^.Name);
            if (PName = 'URL') or
               ((Length(PName) > 3) and (Copy(PName, Length(PName) - 2, 3) = 'URL')) then
              CheckAssetUrl(C, PropertyGetString(C, PInfo));
          end;
        end;
      finally
        FreeMem(PropList);
      end;
    end;

    if C is TCastleChooserTable then
    begin
      ChooserErrs.Clear;
      if (TCastleChooserTable(C).RowCount = 0) or
         (not TCastleChooserTable(C).ValidateRows(ChooserErrs)) then
      begin
        Inc(Result.ChooserIssueCount);
        if ChooserErrs.Count > 0 then
          Result.Findings.Add(Format('[COOK-CHOOSER] %s: %s', [C.Name, ChooserErrs[0]]))
        else
          Result.Findings.Add(Format('[COOK-CHOOSER] %s has 0 rows configured.', [C.Name]));
      end;
    end;

    if (C is TCastleTetSoftBody) and (TCastleTetSoftBody(C).Stats.InvertedTetCount > 0) then
    begin
      Inc(Result.InvertedSoftBodyCount);
      Result.Findings.Add(Format('[COOK-FLESH] %s has %d inverted tetrahedra.',
        [C.Name, TCastleTetSoftBody(C).Stats.InvertedTetCount]));
    end;

    if C is TCastleMassTrafficManager then
    begin
      if (TCastleMassTrafficManager(C).Stats.SignalConflictCount > 0) or
         (TCastleMassTrafficManager(C).Stats.RearEndOverlapCount > 0) then
      begin
        Inc(Result.TrafficHazardCount);
        Result.Findings.Add(Format('[COOK-TRAFFIC] %s has signal/overlap safety violations.', [C.Name]));
      end;
    end;

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        InspectCookComp(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      InspectCookComp(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        InspectCookComp(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        InspectCookComp(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        InspectCookComp(T[I]);
    end;
  end;

var
  I, Penalty: Integer;
begin
  Result := TCookAuditReport.Create;
  Visited := TList.Create;
  ChooserErrs := TStringList.Create;
  WorldHealth := TStudioHubManager.AuditEntireDesign(RootComp, DesignOwner);
  try
    InspectCookComp(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        InspectCookComp(DesignOwner.Components[I]);

    Result.WorldIntegrationIssueCount := Length(WorldHealth.Issues);
    for I := 0 to High(WorldHealth.Issues) do
      Result.Findings.Add(Format('[WORLD-%s] %s', [
        WorldHealth.Issues[I].RecommendedStudioId,
        WorldHealth.Issues[I].MessageText]));

    Penalty :=
      Result.BrokenAssetUrlCount * 25 +
      Result.ChooserIssueCount * 20 +
      Result.InvertedSoftBodyCount * 25 +
      Result.TrafficHazardCount * 20 +
      (100 - WorldHealth.ReadinessScore);

    Result.CookReadinessScore := EnsureRange(100 - Penalty, 0, 100);
    Result.CookReadyToShip :=
      (Result.BrokenAssetUrlCount = 0) and
      (Result.ChooserIssueCount = 0) and
      (Result.InvertedSoftBodyCount = 0) and
      (Result.TrafficHazardCount = 0) and
      (Result.CookReadinessScore >= 90);
  finally
    FreeAndNil(WorldHealth);
    FreeAndNil(ChooserErrs);
    FreeAndNil(Visited);
  end;
end;

class function TLiveCodingCookBroker.GenerateCookAndLiveCodingMarkdown(
  const RootComp, DesignOwner: TComponent): String;
var
  CookRep: TCookAuditReport;
  Snap: TLiveRttiSnapshot;
  I: Integer;
begin
  CookRep := AuditPackageCookReadiness(RootComp, DesignOwner, False);
  Snap := CaptureLiveRttiSnapshot(RootComp, DesignOwner);
  try
    Result :=
      '# Live Coding RTTI Broker & Release Package Cook Report (Phase 356)' + LineEnding + LineEnding +
      '| Metric | Value |' + LineEnding +
      '| :--- | :--- |' + LineEnding +
      Format('| **Cook Readiness Score** | **`%d / 100`** (`ReadyToShip = %s`) |', [
        CookRep.CookReadinessScore, BoolToStr(CookRep.CookReadyToShip, True)]) + LineEnding +
      Format('| **Unified Studio Hub Catalog** | **`%d` Studios** across `6` Domains (`19` MCP Tools) |', [
        TStudioHubManager.StudioCount]) + LineEnding +
      Format('| **Cookable Components & Payload** | `%d` components (`~%d KB` cooked archive) |', [
        CookRep.TotalCookableComponents, CookRep.EstimatedCookedPayloadKB]) + LineEnding +
      Format('| **Live Coding RTTI Snapshot** | `%d` named components / `%d` hot-rehydratable properties |', [
        Snap.CapturedComponentCount, Snap.CapturedPropertyCount]) + LineEnding +
      Format('| **Cook Hazards (URL / Chooser / Flesh / Traffic)** | `%d` / `%d` / `%d` / `%d` |', [
        CookRep.BrokenAssetUrlCount, CookRep.ChooserIssueCount,
        CookRep.InvertedSoftBodyCount, CookRep.TrafficHazardCount]) + LineEnding;

    if CookRep.Findings.Count > 0 then
    begin
      Result := Result + LineEnding + '### Actionable Cook & Integration Findings' + LineEnding;
      for I := 0 to CookRep.Findings.Count - 1 do
        Result := Result + '- ' + CookRep.Findings[I] + LineEnding;
    end;
  finally
    FreeAndNil(Snap);
    FreeAndNil(CookRep);
  end;
end;

end.
