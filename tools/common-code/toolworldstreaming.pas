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

{ Composable entity behavior card helpers (@link(TBehaviorCompositionHelper))
  and World Partition streaming zone & 2D top-down minimap inspector
  (@link(TWorldStreamingInspector)) for @link(TCastleBehavior) and
  @link(TCastleStreamingZone) (Phase 286 — UE 6.0 Composable Entities &
  Streaming Parity). }
unit ToolWorldStreaming;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleBoxes, CastleColors, CastleClassUtils,
  CastleTransform, CastleViewport, CastleStreamingZone;

type
  { Compact summary card for an attached @link(TCastleBehavior) on a
    @link(TCastleTransform). }
  TBehaviorCardSummary = record
    Behavior: TCastleBehavior;
    BehaviorName: String;
    BehaviorClassName: String;
    DisplayCaption: String;
    PropertyPreview: String;
  end;
  TBehaviorCardSummaryArray = array of TBehaviorCardSummary;

  { Registered @link(TCastleBehavior) class entry for the "+ Add Behavior" menu. }
  TRegisteredBehaviorEntry = record
    BehaviorClass: TCastleBehaviorClass;
    ClassNameText: String;
    Caption: String;
  end;
  TRegisteredBehaviorEntryArray = array of TRegisteredBehaviorEntry;

  { Helper for inspecting, attaching, and removing @link(TCastleBehavior)
    components directly inside the Object Inspector panel. }
  TBehaviorCompositionHelper = class
  public
    { Resolve the target @link(TCastleTransform) for the Inspector Behavior Cards bar:
      - If @code(C) is a @link(TCastleTransform), returns @code(C) with
        @code(InspectingBehavior = nil).
      - If @code(C) is an attached @link(TCastleBehavior) whose @code(Parent <> nil),
        returns @code(C.Parent) with @code(InspectingBehavior = C) so the user
        can keep seeing sibling behavior cards and jump back to the parent transform.
      - Otherwise returns @nil. }
    class function ResolveSelectedTransformForBehaviors(const C: TComponent;
      out InspectingBehavior: TCastleBehavior): TCastleTransform;

    { Build compact Inspector card summaries for all behaviors attached to @code(T). }
    class function DescribeAttachedBehaviors(
      const T: TCastleTransform): TBehaviorCardSummaryArray;

    { Return a short RTTI preview of salient scalar/enum/string properties on @code(B). }
    class function BuildBehaviorPropertyPreview(
      const B: TCastleBehavior; const MaxProps: Integer = 3): String;

    { List all non-deprecated @link(TCastleBehavior) classes registered with
      @code(RegisterSerializableComponent), sorted alphabetically by caption. }
    class function ListRegisteredBehaviorClasses: TRegisteredBehaviorEntryArray;

    { Instantiate @code(BehaviorClass) with a unique name on @code(AOwner) and
      attach it to @code(T) via @code(T.AddBehavior). }
    class function AttachNewBehavior(const T: TCastleTransform;
      const AOwner: TComponent;
      const BehaviorClass: TCastleBehaviorClass): TCastleBehavior;

    { Detach @code(ABehavior) from @code(T) and free it cleanly. }
    class function DetachAndFreeBehavior(const T: TCastleTransform;
      const ABehavior: TCastleBehavior): Boolean;
  end;

  { Single @link(TCastleStreamingZone) row in a @link(TWorldStreamingReport). }
  TWorldStreamingZoneRow = record
    Zone: TCastleStreamingZone;
    Name: String;
    ZoneLabel: String;
    DesignUrl: String;
    WorldPos: TVector3;
    LoadRadius: Single;
    UnloadRadius: Single;
    DistanceToObserver: Single;
    IsLoaded: Boolean;
    WouldChangeAtObserver: Boolean;
    ZoneColor: TCastleColorRGB;
  end;
  TWorldStreamingZoneRowArray = array of TWorldStreamingZoneRow;

  { Top-down XZ world footprint item for rendering on the 2D World Partition Minimap. }
  TWorldTopDownFootprint = record
    Transform: TCastleTransform;
    Name: String;
    WorldBox: TBox3D;
    WorldOrigin: TVector3;
    IsStreamingZone: Boolean;
  end;
  TWorldTopDownFootprintArray = array of TWorldTopDownFootprint;

  { Aggregated World Partition & Streaming snapshot for @code(TWorldMinimapForm)
    and automated auditing. }
  TWorldStreamingReport = class
  public
    Zones: TWorldStreamingZoneRowArray;
    Footprints: TWorldTopDownFootprintArray;
    TotalZones: Integer;
    LoadedZones: Integer;
    UnloadedZones: Integer;
    MissingUrlZones: Integer;
    WorldMinX, WorldMaxX: Single;
    WorldMinZ, WorldMaxZ: Single;
    HasBounds: Boolean;
    function FormatMarkdownSummary: String;
  end;

  { Stateless World Partition scanner, streaming simulator, and zone factory. }
  TWorldStreamingInspector = class
  public
    { Scan @code(RootComponent) (either a @code(TCastleUserInterface) containing
      viewports or a @code(TCastleTransform) subtree) and collect all
      @link(TCastleStreamingZone) instances plus top-down XZ footprints. }
    class function ScanWorld(const RootComponent: TComponent;
      const ObserverWorldPos: TVector3;
      const HasObserver: Boolean = false): TWorldStreamingReport;

    { Evaluate @link(TCastleStreamingZone.EvaluateObserverPosition) across every
      zone in @code(RootComponent) and return how many zones are currently loaded. }
    class function SimulateObserverAcrossWorld(const RootComponent: TComponent;
      const ObserverWorldPos: TVector3): Integer;

    { Force-load all zones with non-empty @code(DesignUrl) for full-world preview. }
    class function LoadAllZonesForPreview(const RootComponent: TComponent): Integer;

    { Force-unload all resident zones in @code(RootComponent) to reclaim memory. }
    class function UnloadAllZones(const RootComponent: TComponent): Integer;

    { Spawn a new uniquely named @link(TCastleStreamingZone) inside
      @code(ParentTransform) at @code(WorldPos). }
    class function CreateStreamingZoneAtPosition(
      const ParentTransform: TCastleTransform;
      const AOwner: TComponent;
      const WorldPos: TVector3;
      const ADesignUrl: String = '';
      const ALoadRadius: Single = TCastleStreamingZone.DefaultLoadRadius;
      const AUnloadRadius: Single = TCastleStreamingZone.DefaultUnloadRadius): TCastleStreamingZone;
  end;

implementation

uses
  Math, TypInfo,
  CastleComponentSerialize, CastleUIControls, CastleUtils;

function MakeUniqueComponentName(const AOwner: TComponent;
  const BaseClassName: String): String;
var
  CleanBase: String;
  Idx: Integer;
begin
  CleanBase := BaseClassName;
  if (Length(CleanBase) > 7) and SameText(Copy(CleanBase, 1, 7), 'TCastle') then
    Delete(CleanBase, 1, 7)
  else if (Length(CleanBase) > 1) and (UpCase(CleanBase[1]) = 'T') then
    Delete(CleanBase, 1, 1);
  if CleanBase = '' then
    CleanBase := 'Behavior';

  Idx := 1;
  repeat
    Result := CleanBase + IntToStr(Idx);
    Inc(Idx);
  until (AOwner = nil) or (AOwner.FindComponent(Result) = nil);
end;

{ TBehaviorCompositionHelper ------------------------------------------------- }

class function TBehaviorCompositionHelper.ResolveSelectedTransformForBehaviors(
  const C: TComponent; out InspectingBehavior: TCastleBehavior): TCastleTransform;
begin
  InspectingBehavior := nil;
  Result := nil;
  if C is TCastleTransform then
    Result := TCastleTransform(C)
  else if (C is TCastleBehavior) and (TCastleBehavior(C).Parent <> nil) then
  begin
    InspectingBehavior := TCastleBehavior(C);
    Result := InspectingBehavior.Parent;
  end;
end;

class function TBehaviorCompositionHelper.BuildBehaviorPropertyPreview(
  const B: TCastleBehavior; const MaxProps: Integer): String;
var
  PropList: PPropList;
  PropCount, I, Added, Pass: Integer;
  PInfo: PPropInfo;
  PName, ValStr: String;
  Kind: TTypeKind;
  IsNonDefault: Boolean;
begin
  Result := '';
  if (B = nil) or (MaxProps <= 0) then
    Exit;

  PropCount := GetPropList(B.ClassInfo, tkAny, nil);
  if PropCount <= 0 then
    Exit;

  GetMem(PropList, PropCount * SizeOf(Pointer));
  try
    GetPropList(B.ClassInfo, tkAny, PropList);
    Added := 0;
    { Pass 0: show customized (non-default) properties first; Pass 1: fill up to MaxProps }
    for Pass := 0 to 1 do
    begin
      for I := 0 to PropCount - 1 do
      begin
        if Added >= MaxProps then
          Break;
        PInfo := PropList^[I];
        PName := PInfo^.Name;
        if SameText(PName, 'Name') or SameText(PName, 'Tag') or
           SameText(PName, 'ListenWorldChange') then
          Continue;

        ValStr := '';
        IsNonDefault := false;
        Kind := PInfo^.PropType^.Kind;
        case Kind of
          tkBool:
            begin
              IsNonDefault := (PInfo^.Default <> LongInt($80000000)) and
                (GetOrdProp(B, PInfo) <> PInfo^.Default);
              if GetOrdProp(B, PInfo) <> 0 then
                ValStr := 'True'
              else
                ValStr := 'False';
            end;
          tkEnumeration:
            begin
              IsNonDefault := (PInfo^.Default <> LongInt($80000000)) and
                (GetOrdProp(B, PInfo) <> PInfo^.Default);
              ValStr := GetEnumName(PInfo^.PropType, GetOrdProp(B, PInfo));
            end;
          tkInteger, tkInt64, tkQWord:
            begin
              IsNonDefault := (PInfo^.Default <> LongInt($80000000)) and
                (GetOrdProp(B, PInfo) <> PInfo^.Default);
              ValStr := IntToStr(GetInt64Prop(B, PInfo));
            end;
          tkFloat:
            begin
              if PInfo^.Default <> LongInt($80000000) then
                IsNonDefault := not SameValue(GetFloatProp(B, PInfo),
                  PSingle(@PInfo^.Default)^, 1e-4);
              ValStr := FormatFloat('0.##', GetFloatProp(B, PInfo));
            end;
          tkSString, tkLString, tkAString:
            begin
              ValStr := Trim(GetStrProp(B, PInfo));
              if ValStr = '' then
                Continue;
              IsNonDefault := true;
              if Length(ValStr) > 18 then
                ValStr := '...' + Copy(ValStr, Length(ValStr) - 14, 15);
              ValStr := '"' + ValStr + '"';
            end;
        else
          Continue;
        end;

        if ((Pass = 0) and IsNonDefault) or ((Pass = 1) and (not IsNonDefault)) then
        begin
          if ValStr <> '' then
          begin
            if Result <> '' then
              Result := Result + ', ';
            Result := Result + PName + '=' + ValStr;
            Inc(Added);
          end;
        end;
      end;
    end;
  finally
    FreeMem(PropList);
  end;
end;

class function TBehaviorCompositionHelper.DescribeAttachedBehaviors(
  const T: TCastleTransform): TBehaviorCardSummaryArray;
var
  I: Integer;
  B: TCastleBehavior;
begin
  Result := nil;
  if T = nil then
    Exit;
  SetLength(Result, T.BehaviorsCount);
  for I := 0 to T.BehaviorsCount - 1 do
  begin
    B := T.Behaviors[I];
    Result[I].Behavior := B;
    if B.Name <> '' then
      Result[I].BehaviorName := B.Name
    else
      Result[I].BehaviorName := '<unnamed>';
    Result[I].BehaviorClassName := B.ClassName;
    Result[I].PropertyPreview := BuildBehaviorPropertyPreview(B, 3);
    if B.Name <> '' then
      Result[I].DisplayCaption := B.Name + ' (' + B.ClassName + ')'
    else
      Result[I].DisplayCaption := B.ClassName;
  end;
end;

class function TBehaviorCompositionHelper.ListRegisteredBehaviorClasses: TRegisteredBehaviorEntryArray;
var
  RC: TRegisteredComponent;
  Cap: String;
  I, J, K: Integer;
  Tmp: TRegisteredBehaviorEntry;
begin
  Result := nil;
  if RegisteredComponents = nil then
    Exit;

  for I := 0 to RegisteredComponents.Count - 1 do
  begin
    RC := RegisteredComponents[I];
    if (RC.ComponentClass = nil) or RC.IsDeprecated then
      Continue;
    if not RC.ComponentClass.InheritsFrom(TCastleBehavior) then
      Continue;
    if RC.ComponentClass = TCastleBehavior then
      Continue;

    Cap := '';
    for K := 0 to High(RC.Caption) do
    begin
      if (K = 0) and SameText(RC.Caption[K], 'Behavior') and (Length(RC.Caption) > 1) then
        Continue;
      if Cap <> '' then
        Cap := Cap + ' / ';
      Cap := Cap + RC.Caption[K];
    end;
    if Cap = '' then
      Cap := RC.ComponentClass.ClassName;

    J := Length(Result);
    SetLength(Result, J + 1);
    Result[J].BehaviorClass := TCastleBehaviorClass(RC.ComponentClass);
    Result[J].ClassNameText := RC.ComponentClass.ClassName;
    Result[J].Caption := Cap + ' (' + RC.ComponentClass.ClassName + ')';
  end;

  { Simple alphabetical sort by Caption }
  for I := 0 to High(Result) - 1 do
    for J := I + 1 to High(Result) do
      if CompareText(Result[J].Caption, Result[I].Caption) < 0 then
      begin
        Tmp := Result[I];
        Result[I] := Result[J];
        Result[J] := Tmp;
      end;
end;

class function TBehaviorCompositionHelper.AttachNewBehavior(
  const T: TCastleTransform; const AOwner: TComponent;
  const BehaviorClass: TCastleBehaviorClass): TCastleBehavior;
var
  RC: TRegisteredComponent;
  I: Integer;
begin
  Result := nil;
  if (T = nil) or (BehaviorClass = nil) then
    Exit;

  Result := BehaviorClass.Create(AOwner);
  Result.Name := MakeUniqueComponentName(AOwner, BehaviorClass.ClassName);

  if RegisteredComponents <> nil then
    for I := 0 to RegisteredComponents.Count - 1 do
    begin
      RC := RegisteredComponents[I];
      if (RC.ComponentClass = BehaviorClass) and Assigned(RC.OnCreate) then
      begin
        RC.OnCreate(Result);
        Break;
      end;
    end;

  T.AddBehavior(Result);
end;

class function TBehaviorCompositionHelper.DetachAndFreeBehavior(
  const T: TCastleTransform; const ABehavior: TCastleBehavior): Boolean;
begin
  Result := false;
  if (T = nil) or (ABehavior = nil) then
    Exit;
  if ABehavior.Parent <> T then
    Exit;
  T.RemoveBehavior(ABehavior);
  ABehavior.Free;
  Result := true;
end;

{ TWorldStreamingReport ------------------------------------------------------ }

function TWorldStreamingReport.FormatMarkdownSummary: String;
var
  SB: TStringBuilder;
  I: Integer;
  StateStr: String;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('### World Partition & Streaming Zones Summary');
    SB.AppendLine(Format('- **Total Streaming Zones:** `%d` (`%d` Loaded, `%d` Unloaded, `%d` Missing URL)',
      [TotalZones, LoadedZones, UnloadedZones, MissingUrlZones]));
    if HasBounds then
      SB.AppendLine(Format('- **World XZ Span:** `X [%.1f .. %.1f]`, `Z [%.1f .. %.1f]` (`%.1f x %.1f` m)',
        [WorldMinX, WorldMaxX, WorldMinZ, WorldMaxZ,
         WorldMaxX - WorldMinX, WorldMaxZ - WorldMinZ]));
    SB.AppendLine('');
    if Length(Zones) > 0 then
    begin
      SB.AppendLine('| Zone | Label | State | Load / Unload (m) | Dist (m) | DesignUrl |');
      SB.AppendLine('| --- | --- | --- | --- | --- | --- |');
      for I := 0 to High(Zones) do
      begin
        if Zones[I].IsLoaded then
          StateStr := 'LOADED'
        else
          StateStr := 'UNLOADED';
        SB.AppendLine(Format('| `%s` | %s | **%s** | `%.1f / %.1f` | `%.1f` | `%s` |',
          [Zones[I].Name, Zones[I].ZoneLabel, StateStr,
           Zones[I].LoadRadius, Zones[I].UnloadRadius,
           Zones[I].DistanceToObserver, Zones[I].DesignUrl]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

{ TWorldStreamingInspector --------------------------------------------------- }

procedure CollectAllStreamingZones(const Root: TComponent; const OutList: TList);

  procedure WalkTransform(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;
    if T is TCastleStreamingZone then
      OutList.Add(T);
    for I := 0 to T.Count - 1 do
      WalkTransform(T[I]);
  end;

  procedure WalkUi(const U: TCastleUserInterface);
  var
    I: Integer;
  begin
    if (U = nil) or (csTransient in U.ComponentStyle) then
      Exit;
    if (U is TCastleViewport) and (TCastleViewport(U).Items <> nil) then
      WalkTransform(TCastleViewport(U).Items);
    for I := 0 to U.ControlsCount - 1 do
      WalkUi(U.Controls[I]);
  end;

begin
  if Root is TCastleTransform then
    WalkTransform(TCastleTransform(Root))
  else if Root is TCastleUserInterface then
    WalkUi(TCastleUserInterface(Root));
end;

class function TWorldStreamingInspector.ScanWorld(
  const RootComponent: TComponent; const ObserverWorldPos: TVector3;
  const HasObserver: Boolean): TWorldStreamingReport;
var
  Report: TWorldStreamingReport;

  procedure ExpandBoundsXZ(const X1, Z1, X2, Z2: Single);
  begin
    if not Report.HasBounds then
    begin
      Report.WorldMinX := Min(X1, X2);
      Report.WorldMaxX := Max(X1, X2);
      Report.WorldMinZ := Min(Z1, Z2);
      Report.WorldMaxZ := Max(Z1, Z2);
      Report.HasBounds := true;
    end else
    begin
      Report.WorldMinX := Min(Report.WorldMinX, Min(X1, X2));
      Report.WorldMaxX := Max(Report.WorldMaxX, Max(X1, X2));
      Report.WorldMinZ := Min(Report.WorldMinZ, Min(Z1, Z2));
      Report.WorldMaxZ := Max(Report.WorldMaxZ, Max(Z1, Z2));
    end;
  end;

  procedure WalkTransform(const T: TCastleTransform; const IsRootItems: Boolean);
  var
    I, Idx: Integer;
    Z: TCastleStreamingZone;
    WPos: TVector3;
    WBox: TBox3D;
    Dist, UnloadR: Single;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;

    if T is TCastleStreamingZone then
    begin
      Z := TCastleStreamingZone(T);
      if Z.World <> nil then
        WPos := Z.LocalToWorld(TVector3.Zero)
      else
        WPos := Z.Translation;
      UnloadR := Z.EffectiveUnloadRadius;

      Idx := Length(Report.Zones);
      SetLength(Report.Zones, Idx + 1);
      if Z.Name <> '' then
        Report.Zones[Idx].Name := Z.Name
      else
        Report.Zones[Idx].Name := '<unnamed>';
      Report.Zones[Idx].Zone := Z;
      Report.Zones[Idx].ZoneLabel := Z.ZoneLabel;
      Report.Zones[Idx].DesignUrl := Z.DesignUrl;
      Report.Zones[Idx].WorldPos := WPos;
      Report.Zones[Idx].LoadRadius := Z.LoadRadius;
      Report.Zones[Idx].UnloadRadius := UnloadR;
      Report.Zones[Idx].IsLoaded := Z.IsZoneLoaded;
      Report.Zones[Idx].ZoneColor := Z.ZoneColor;

      if HasObserver then
      begin
        Dist := Z.ComputeDistanceToWorldPoint(ObserverWorldPos);
        Report.Zones[Idx].DistanceToObserver := Dist;
        Report.Zones[Idx].WouldChangeAtObserver :=
          ((not Z.IsZoneLoaded) and (Dist <= Z.LoadRadius) and (Trim(Z.DesignUrl) <> '')) or
          (Z.IsZoneLoaded and (Dist > UnloadR));
      end else
      begin
        Report.Zones[Idx].DistanceToObserver := Z.LastObserverDistance;
        Report.Zones[Idx].WouldChangeAtObserver := false;
      end;

      Inc(Report.TotalZones);
      if Z.IsZoneLoaded then
        Inc(Report.LoadedZones)
      else
        Inc(Report.UnloadedZones);
      if Trim(Z.DesignUrl) = '' then
        Inc(Report.MissingUrlZones);

      ExpandBoundsXZ(WPos.X - UnloadR, WPos.Z - UnloadR,
        WPos.X + UnloadR, WPos.Z + UnloadR);
    end;

    if (not IsRootItems) and T.Exists then
    begin
      WBox := T.WorldBoundingBox;
      if WBox.IsEmpty then
      begin
        if T.World <> nil then
          WPos := T.LocalToWorld(TVector3.Zero)
        else
          WPos := T.Translation;
        WBox := Box3D(WPos - Vector3(0.5, 0.5, 0.5), WPos + Vector3(0.5, 0.5, 0.5));
      end else
        WPos := WBox.Center;

      Idx := Length(Report.Footprints);
      SetLength(Report.Footprints, Idx + 1);
      Report.Footprints[Idx].Transform := T;
      Report.Footprints[Idx].Name := T.Name;
      Report.Footprints[Idx].WorldBox := WBox;
      Report.Footprints[Idx].WorldOrigin := WPos;
      Report.Footprints[Idx].IsStreamingZone := T is TCastleStreamingZone;

      ExpandBoundsXZ(WBox.Data[0].X, WBox.Data[0].Z, WBox.Data[1].X, WBox.Data[1].Z);
    end;

    for I := 0 to T.Count - 1 do
      WalkTransform(T[I], false);
  end;

  procedure WalkUi(const U: TCastleUserInterface);
  var
    I: Integer;
  begin
    if (U = nil) or (csTransient in U.ComponentStyle) then
      Exit;
    if (U is TCastleViewport) and (TCastleViewport(U).Items <> nil) then
      WalkTransform(TCastleViewport(U).Items, true);
    for I := 0 to U.ControlsCount - 1 do
      WalkUi(U.Controls[I]);
  end;

begin
  Report := TWorldStreamingReport.Create;
  if HasObserver then
    ExpandBoundsXZ(ObserverWorldPos.X - 5.0, ObserverWorldPos.Z - 5.0,
      ObserverWorldPos.X + 5.0, ObserverWorldPos.Z + 5.0);

  if RootComponent is TCastleTransform then
    WalkTransform(TCastleTransform(RootComponent), true)
  else if RootComponent is TCastleUserInterface then
    WalkUi(TCastleUserInterface(RootComponent));

  Result := Report;
end;

class function TWorldStreamingInspector.SimulateObserverAcrossWorld(
  const RootComponent: TComponent; const ObserverWorldPos: TVector3): Integer;
var
  ZoneList: TList;
  I: Integer;
  Z: TCastleStreamingZone;
begin
  Result := 0;
  ZoneList := TList.Create;
  try
    CollectAllStreamingZones(RootComponent, ZoneList);
    for I := 0 to ZoneList.Count - 1 do
    begin
      Z := TCastleStreamingZone(ZoneList[I]);
      if Z.EvaluateObserverPosition(ObserverWorldPos) then
        Inc(Result);
    end;
  finally
    FreeAndNil(ZoneList);
  end;
end;

class function TWorldStreamingInspector.LoadAllZonesForPreview(
  const RootComponent: TComponent): Integer;
var
  ZoneList: TList;
  I: Integer;
  Z: TCastleStreamingZone;
begin
  Result := 0;
  ZoneList := TList.Create;
  try
    CollectAllStreamingZones(RootComponent, ZoneList);
    for I := 0 to ZoneList.Count - 1 do
    begin
      Z := TCastleStreamingZone(ZoneList[I]);
      if Z.LoadZoneNow then
        Inc(Result);
    end;
  finally
    FreeAndNil(ZoneList);
  end;
end;

class function TWorldStreamingInspector.UnloadAllZones(
  const RootComponent: TComponent): Integer;
var
  ZoneList: TList;
  I: Integer;
  Z: TCastleStreamingZone;
begin
  Result := 0;
  ZoneList := TList.Create;
  try
    CollectAllStreamingZones(RootComponent, ZoneList);
    for I := 0 to ZoneList.Count - 1 do
    begin
      Z := TCastleStreamingZone(ZoneList[I]);
      if Z.IsZoneLoaded then
      begin
        Z.UnloadZoneNow;
        Inc(Result);
      end;
    end;
  finally
    FreeAndNil(ZoneList);
  end;
end;

class function TWorldStreamingInspector.CreateStreamingZoneAtPosition(
  const ParentTransform: TCastleTransform; const AOwner: TComponent;
  const WorldPos: TVector3; const ADesignUrl: String;
  const ALoadRadius, AUnloadRadius: Single): TCastleStreamingZone;
var
  LocalPos: TVector3;
begin
  Result := nil;
  if ParentTransform = nil then
    Exit;

  if ParentTransform.World <> nil then
    LocalPos := ParentTransform.WorldToLocal(WorldPos)
  else
    LocalPos := WorldPos;

  Result := TCastleStreamingZone.Create(AOwner);
  Result.Name := MakeUniqueComponentName(AOwner, 'StreamingZone');
  Result.Translation := LocalPos;
  Result.LoadRadius := ALoadRadius;
  Result.UnloadRadius := Max(ALoadRadius, AUnloadRadius);
  Result.DesignUrl := ADesignUrl;
  ParentTransform.Add(Result);
end;

end.
