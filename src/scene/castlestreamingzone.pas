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

{ Distance-based World Partition sub-design streaming zone
  (@link(TCastleStreamingZone)) with load/unload hysteresis and transient
  hierarchy ownership (Phase 286 — UE 6.0 Composable Entities & Streaming Parity). }
unit CastleStreamingZone;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Distance-based open-world streaming volume that dynamically loads and unloads
    a referenced @code(.castle-transform) or 3D scene (@link(DesignUrl)) based on
    camera/observer proximity with configurable hysteresis
    (@link(LoadRadius) <= @link(UnloadRadius)).

    Streamed content is mounted inside an internal @code(csTransient) child
    container so editor saves and @code(ComponentToString) roundtrips never
    duplicate or bake streamed children into the parent world file. }
  TCastleStreamingZone = class(TCastleTransform)
  strict private
    FDesignUrl: String;
    FLoadRadius: Single;
    FUnloadRadius: Single;
    FUse2DHorizontalDistance: Boolean;
    FAutoStreamInRuntime: Boolean;
    FPreviewLoadedInEditor: Boolean;
    FShowBoundsInViewport: Boolean;
    FZoneLabel: String;
    FZoneColor: TCastleColorRGB;
    FZoneColorPersistent: TCastleColorRGBPersistent;

    FTransientHolder: TCastleTransform;
    FStreamedContentOwner: TComponent;
    FLoadedDesignRoot: TCastleTransform;
    FLastObserverDistance: Single;
    FLoadCount: Integer;
    FUnloadCount: Integer;

    procedure SetDesignUrl(const Value: String);
    procedure SetLoadRadius(const Value: Single);
    procedure SetUnloadRadius(const Value: Single);
    procedure SetPreviewLoadedInEditor(const Value: Boolean);
    function GetZoneColorForPersistent: TCastleColorRGB;
    procedure SetZoneColorForPersistent(const AValue: TCastleColorRGB);
    procedure EnsureTransientHolder;
  protected
    procedure Loaded; override;
  public
    const
      DefaultLoadRadius = 60.0;
      DefaultUnloadRadius = 80.0;
      DefaultUse2DHorizontalDistance = true;
      DefaultAutoStreamInRuntime = true;
      DefaultPreviewLoadedInEditor = false;
      DefaultShowBoundsInViewport = true;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Effective unload distance, guaranteed >= @link(LoadRadius). }
    function EffectiveUnloadRadius: Single;

    { Compute 2D XZ or 3D Euclidean distance from this zone's world origin to
      @code(WorldPt). }
    function ComputeDistanceToWorldPoint(const WorldPt: TVector3): Single;

    { Immediately stream in @link(DesignUrl) if not already loaded.
      Returns @true when the zone is loaded after the call. }
    function LoadZoneNow: Boolean;

    { Immediately unload any streamed child hierarchy and reclaim its memory. }
    procedure UnloadZoneNow;

    { Evaluate observer world position against @link(LoadRadius) and
      @link(EffectiveUnloadRadius) with hysteresis:
      - When unloaded and distance <= @link(LoadRadius), calls @link(LoadZoneNow).
      - When loaded and distance > @link(EffectiveUnloadRadius), calls @link(UnloadZoneNow).
      - Inside the hysteresis band (@code(LoadRadius < Dist <= EffectiveUnloadRadius)),
        preserves the current loaded/unloaded state without thrashing.
      Returns @link(IsZoneLoaded) after evaluation. }
    function EvaluateObserverPosition(const WorldObserverPos: TVector3): Boolean;

    { Concise badge for Hierarchy tree and 3D Viewport overlays. }
    function ZoneSummaryBadge: String;

    { @true when @link(DesignUrl) is currently resident in memory. }
    function IsZoneLoaded: Boolean;

    { Root transform of the currently streamed sub-design, or @nil when unloaded. }
    property LoadedDesignRoot: TCastleTransform read FLoadedDesignRoot;

    { Most recent distance measured by @link(EvaluateObserverPosition), or @code(-1)
      if not yet evaluated. }
    property LastObserverDistance: Single read FLastObserverDistance;

    { Telemetry counters tracking how many times this zone streamed in / out. }
    property LoadCount: Integer read FLoadCount;
    property UnloadCount: Integer read FUnloadCount;

    { Editor wireframe & minimap ring color (RGB). }
    property ZoneColor: TCastleColorRGB read FZoneColor write FZoneColor;
  published
    { URL of the @code(.castle-transform) sub-design (or 3D model) to stream in/out. }
    property DesignUrl: String read FDesignUrl write SetDesignUrl;

    { Optional human-readable sector title displayed on the 2D World Minimap
      and 3D Viewport callout pill. }
    property ZoneLabel: String read FZoneLabel write FZoneLabel;

    { Distance in world units within which this zone streams in. }
    property LoadRadius: Single read FLoadRadius write SetLoadRadius
      {$ifdef FPC}default DefaultLoadRadius{$endif};

    { Distance in world units beyond which an already-loaded zone unloads.
      Keep >= @link(LoadRadius) to provide hysteresis and avoid boundary thrashing. }
    property UnloadRadius: Single read FUnloadRadius write SetUnloadRadius
      {$ifdef FPC}default DefaultUnloadRadius{$endif};

    { Measure horizontal XZ distance (standard open-world grid streaming) when
      @true, or full 3D spherical distance when @false. }
    property Use2DHorizontalDistance: Boolean
      read FUse2DHorizontalDistance write FUse2DHorizontalDistance
      default DefaultUse2DHorizontalDistance;

    { Automatically evaluate @code(World.MainCamera) every frame at game runtime
      (@code(not CastleDesignMode)). }
    property AutoStreamInRuntime: Boolean
      read FAutoStreamInRuntime write FAutoStreamInRuntime
      default DefaultAutoStreamInRuntime;

    { Stream @link(DesignUrl) in while editing in CGE Editor so level designers
      can inspect sector transitions in place without baking children into the
      parent file. }
    property PreviewLoadedInEditor: Boolean
      read FPreviewLoadedInEditor write SetPreviewLoadedInEditor
      default DefaultPreviewLoadedInEditor;

    { Draw @link(LoadRadius) / @link(UnloadRadius) rings in the 3D Viewport and
      2D World Partition Minimap. }
    property ShowBoundsInViewport: Boolean
      read FShowBoundsInViewport write FShowBoundsInViewport
      default DefaultShowBoundsInViewport;

    { Wireframe & minimap ring color. }
    property ZoneColorPersistent: TCastleColorRGBPersistent read FZoneColorPersistent;
  end;

implementation

uses
  Math,
  CastleComponentSerialize, CastleScene, CastleLog, CastleUriUtils;

{ TCastleStreamingZone ------------------------------------------------------- }

constructor TCastleStreamingZone.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLoadRadius := DefaultLoadRadius;
  FUnloadRadius := DefaultUnloadRadius;
  FUse2DHorizontalDistance := DefaultUse2DHorizontalDistance;
  FAutoStreamInRuntime := DefaultAutoStreamInRuntime;
  FPreviewLoadedInEditor := DefaultPreviewLoadedInEditor;
  FShowBoundsInViewport := DefaultShowBoundsInViewport;
  FZoneColor := Vector3(0.15, 0.85, 0.72);
  FLastObserverDistance := -1.0;

  FZoneColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FZoneColorPersistent.SetSubComponent(true);
  FZoneColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetZoneColorForPersistent;
  FZoneColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetZoneColorForPersistent;
  FZoneColorPersistent.InternalDefaultValue := FZoneColor;
end;

destructor TCastleStreamingZone.Destroy;
begin
  UnloadZoneNow;
  FreeAndNil(FTransientHolder);
  FreeAndNil(FZoneColorPersistent);
  inherited;
end;

function TCastleStreamingZone.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'DesignUrl', 'ZoneLabel', 'LoadRadius', 'UnloadRadius',
       'Use2DHorizontalDistance', 'AutoStreamInRuntime',
       'PreviewLoadedInEditor', 'ShowBoundsInViewport',
       'ZoneColorPersistent'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleStreamingZone.GetZoneColorForPersistent: TCastleColorRGB;
begin
  Result := FZoneColor;
end;

procedure TCastleStreamingZone.SetZoneColorForPersistent(
  const AValue: TCastleColorRGB);
begin
  FZoneColor := AValue;
end;

procedure TCastleStreamingZone.SetDesignUrl(const Value: String);
var
  WasLoaded: Boolean;
begin
  if FDesignUrl = Value then
    Exit;
  WasLoaded := IsZoneLoaded;
  UnloadZoneNow;
  FDesignUrl := Value;
  if not (csLoading in ComponentState) then
  begin
    if CastleDesignMode then
    begin
      if FPreviewLoadedInEditor and (Trim(FDesignUrl) <> '') then
        LoadZoneNow;
    end else
    if WasLoaded and (Trim(FDesignUrl) <> '') then
      LoadZoneNow;
  end;
end;

procedure TCastleStreamingZone.SetLoadRadius(const Value: Single);
begin
  FLoadRadius := Max(0.1, Value);
end;

procedure TCastleStreamingZone.SetUnloadRadius(const Value: Single);
begin
  FUnloadRadius := Max(0.1, Value);
end;

procedure TCastleStreamingZone.SetPreviewLoadedInEditor(const Value: Boolean);
begin
  if FPreviewLoadedInEditor = Value then
    Exit;
  FPreviewLoadedInEditor := Value;
  if not (csLoading in ComponentState) then
  begin
    if FPreviewLoadedInEditor then
      LoadZoneNow
    else if CastleDesignMode then
      UnloadZoneNow;
  end;
end;

procedure TCastleStreamingZone.Loaded;
begin
  inherited;
  if FPreviewLoadedInEditor and (Trim(FDesignUrl) <> '') then
    LoadZoneNow;
end;

procedure TCastleStreamingZone.EnsureTransientHolder;
begin
  if FTransientHolder = nil then
  begin
    FTransientHolder := TCastleTransform.Create(nil);
    FTransientHolder.SetTransient;
    Add(FTransientHolder);
  end;
end;

function TCastleStreamingZone.EffectiveUnloadRadius: Single;
begin
  Result := Max(FLoadRadius, FUnloadRadius);
end;

function TCastleStreamingZone.IsZoneLoaded: Boolean;
begin
  Result := FLoadedDesignRoot <> nil;
end;

function TCastleStreamingZone.ComputeDistanceToWorldPoint(
  const WorldPt: TVector3): Single;
var
  ZoneOrigin: TVector3;
  DX, DZ: Single;
begin
  if World <> nil then
    ZoneOrigin := LocalToWorld(TVector3.Zero)
  else
    ZoneOrigin := Translation;

  if FUse2DHorizontalDistance then
  begin
    DX := WorldPt.X - ZoneOrigin.X;
    DZ := WorldPt.Z - ZoneOrigin.Z;
    Result := Sqrt(DX * DX + DZ * DZ);
  end else
    Result := PointsDistance(WorldPt, ZoneOrigin);
end;

function TCastleStreamingZone.LoadZoneNow: Boolean;
var
  Ext: String;
  SceneChild: TCastleScene;
begin
  if IsZoneLoaded then
    Exit(true);
  if Trim(FDesignUrl) = '' then
    Exit(false);

  EnsureTransientHolder;
  FStreamedContentOwner := TComponent.Create(nil);
  try
    Ext := LowerCase(ExtractFileExt(UriDeleteAnchor(FDesignUrl)));
    if SameText(Ext, '.castle-transform') then
      FLoadedDesignRoot := TransformLoad(FDesignUrl, FStreamedContentOwner)
    else
    begin
      SceneChild := TCastleScene.Create(FStreamedContentOwner);
      SceneChild.Url := FDesignUrl;
      FLoadedDesignRoot := SceneChild;
    end;
    FTransientHolder.Add(FLoadedDesignRoot);
    Inc(FLoadCount);
    Result := true;
  except
    on E: Exception do
    begin
      WritelnWarning('TCastleStreamingZone',
        'Failed to stream DesignUrl "%s" on zone "%s": %s',
        [FDesignUrl, Name, E.Message]);
      FLoadedDesignRoot := nil;
      FreeAndNil(FStreamedContentOwner);
      Result := false;
    end;
  end;
end;

procedure TCastleStreamingZone.UnloadZoneNow;
begin
  if FLoadedDesignRoot <> nil then
  begin
    if FTransientHolder <> nil then
      FTransientHolder.Remove(FLoadedDesignRoot);
    FLoadedDesignRoot := nil;
    Inc(FUnloadCount);
  end;
  FreeAndNil(FStreamedContentOwner);
end;

function TCastleStreamingZone.EvaluateObserverPosition(
  const WorldObserverPos: TVector3): Boolean;
var
  Dist: Single;
begin
  Dist := ComputeDistanceToWorldPoint(WorldObserverPos);
  FLastObserverDistance := Dist;
  if not IsZoneLoaded then
  begin
    if (Dist <= FLoadRadius) and (Trim(FDesignUrl) <> '') then
      LoadZoneNow;
  end else
  begin
    if Dist > EffectiveUnloadRadius then
      UnloadZoneNow;
  end;
  Result := IsZoneLoaded;
end;

procedure TCastleStreamingZone.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
var
  CamPos, CamDir, CamUp: TVector3;
begin
  inherited;
  if (not CastleDesignMode) and FAutoStreamInRuntime and
     (World <> nil) and (World.MainCamera <> nil) then
  begin
    World.MainCamera.GetWorldView(CamPos, CamDir, CamUp);
    EvaluateObserverPosition(CamPos);
  end;
end;

function TCastleStreamingZone.LocalBoundingBox: TBox3D;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
    Result := Result + Box3D(
      Vector3(-0.75, -0.75, -0.75),
      Vector3( 0.75,  0.75,  0.75));
end;

function TCastleStreamingZone.ZoneSummaryBadge: String;
var
  StateTag, LabelPrefix: String;
begin
  if IsZoneLoaded then
    StateTag := 'LOADED'
  else
    StateTag := 'UNLOADED';

  if Trim(FZoneLabel) <> '' then
    LabelPrefix := Trim(FZoneLabel) + ' '
  else
    LabelPrefix := '';

  Result := Format('[Zone:%s%s %.0f/%.0fm]',
    [LabelPrefix, StateTag, FLoadRadius, EffectiveUnloadRadius]);
end;

initialization
  RegisterSerializableComponent(TCastleStreamingZone,
    ['Transform', 'Streaming Zone (World Partition)']);
end.
