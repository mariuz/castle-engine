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

{ Unreal Engine 5.5-style UMG Widget Animation Timeline & Anchor Slot Designer
  runtime (@link(TCastleWidgetAnimator)) featuring multi-track keyframed 2D UI
  animations (RenderOpacity, TranslationX/Y, ScaleUniform, RotationDeg, Color
  RGB), Cubic/Hermite/BackOvershoot/BounceOut easing curves, Forward/Reverse/
  PingPong/Loop PlayAnimation playback, UI Event Trigger bindings, and 14-mode
  9-Point + Stretch UMG Anchor Flower presets
  (Phase 386 — UE 5.5 UWidgetBlueprint & UWidgetAnimation Parity). }
unit CastleWidgetAnim;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleColors, CastleClassUtils,
  CastleComponentSerialize, CastleUIControls, CastleControls;

type
  { 14 UE5 UMG CanvasPanelSlot Anchor Flower presets (9 point anchors + 5 stretch slots). }
  TUmgAnchorPreset = (
    uapTopLeft,
    uapTopCenter,
    uapTopRight,
    uapCenterLeft,
    uapCenter,
    uapCenterRight,
    uapBottomLeft,
    uapBottomCenter,
    uapBottomRight,
    uapStretchHorizontalTop,
    uapStretchHorizontalBottom,
    uapStretchVerticalLeft,
    uapStretchVerticalRight,
    uapStretchFullScreen
  );

  { Keyframeable 2D UMG widget properties. }
  TUmgAnimProperty = (
    uapRenderOpacity,
    uapTranslationX,
    uapTranslationY,
    uapScaleUniform,
    uapRotationDeg,
    uapColorTintR,
    uapColorTintG,
    uapColorTintB
  );

  { Segment easing curve between adjacent UMG keyframes. }
  TUmgAnimEasing = (
    uaeLinear,
    uaeCubicEaseIn,
    uaeCubicEaseOut,
    uaeHermiteSmoothStep,
    uaeBackOvershootOut,
    uaeBounceOut
  );

  { UE5 UUMGSequencePlayMode parity. }
  TUmgPlaybackMode = (
    upmForward,
    upmReverse,
    upmPingPong,
    upmLoopForward
  );

  { Declarative UI event hooks triggering PlayAnimation automatically. }
  TUmgEventTriggerKind = (
    uetOnShow,
    uetOnButtonClick,
    uetOnHoverEnter,
    uetOnHoverLeave,
    uetOnDamagePulse
  );

  { Built-in UE 5.5 UMG Widget Animation starter presets. }
  TUmgWidgetAnimPreset = (
    uwapCustom,
    uwapModalPopupSlideBounceAndFade,
    uwapHudDamageToastAndHealthFlash,
    uwapBossHealthBannerStretchReveal
  );

  { Single keyframe sample along a TUmgAnimTrack. }
  TUmgKeyframe = record
    TimeSec: Single;
    Value: Single;
    EasingToNext: TUmgAnimEasing;
  end;
  TUmgKeyframeArray = array of TUmgKeyframe;

  { Single property animation track targeting a named widget slot. }
  TUmgAnimTrack = record
    TargetWidgetName: String;
    Prop: TUmgAnimProperty;
    Keys: TUmgKeyframeArray;
    function Evaluate(const ATimeSec: Single): Single;
  end;
  TUmgAnimTrackArray = array of TUmgAnimTrack;

  { Named UWidgetAnimation clip containing multiple synchronized tracks. }
  TUmgWidgetAnimClip = record
    ClipName: String;
    DurationSec: Single;
    Tracks: TUmgAnimTrackArray;
  end;
  TUmgWidgetAnimClipArray = array of TUmgWidgetAnimClip;

  { Declarative UI event -> PlayAnimation binding. }
  TUmgEventBinding = record
    SourceWidgetName: String;
    Trigger: TUmgEventTriggerKind;
    ClipName: String;
    PlayMode: TUmgPlaybackMode;
    PlaybackSpeed: Single;
  end;
  TUmgEventBindingArray = array of TUmgEventBinding;

  { Managed widget slot combining rest layout, 9-point anchor preset & live animated state. }
  TUmgManagedWidgetSlot = record
    WidgetName: String;
    AnchorPreset: TUmgAnchorPreset;
    RestTransX: Single;
    RestTransY: Single;
    RestWidth: Single;
    RestHeight: Single;
    RestColor: TCastleColor;
    { Live evaluated state }
    EvalTransX: Single;
    EvalTransY: Single;
    EvalScale: Single;
    EvalRotationDeg: Single;
    EvalOpacity: Single;
    EvalColorRGB: TVector3;
  end;
  TUmgManagedWidgetSlotArray = array of TUmgManagedWidgetSlot;

  { Unreal Engine 5.5-style UMG Widget Animation Timeline & Anchor Slot controller. }
  TCastleWidgetAnimator = class(TCastleUserInterface)
  private
    FPreset: TUmgWidgetAnimPreset;
    FShowPreviewCanvas: Boolean;
    FSlots: TUmgManagedWidgetSlotArray;
    FClips: TUmgWidgetAnimClipArray;
    FBindings: TUmgEventBindingArray;

    { Playback runtime state }
    FActiveClipIndex: Integer;
    FCurrentTimeSec: Single;
    FPlayMode: TUmgPlaybackMode;
    FPlaybackSpeed: Single;
    FPlaying: Boolean;
    FPingPongForward: Boolean;
    FRemainingLoops: Integer;
    FEventsTriggeredCount: Integer;

    FPreviewRoot: TCastleUserInterface;

    procedure SetPreset(const AValue: TUmgWidgetAnimPreset);
    procedure SetShowPreviewCanvas(const AValue: Boolean);
    function GetTimelineJson: String;
    procedure SetTimelineJson(const AValue: String);

    procedure ClearPreviewCanvas;
    procedure RebuildPreviewCanvas;
    function ResolveLiveUiControl(const AWidgetName: String): TCastleUserInterface;
    procedure ApplyEvaluatedSlotToControl(const ASlot: TUmgManagedWidgetSlot);
    procedure EvaluateClipAtCurrentTime;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Mathematical easing & anchor flower helpers }
    class function EvaluateUmgEasing(const AEasing: TUmgAnimEasing; const T: Single): Single; static;
    class procedure NormalizedAnchorFlowerMinMax(const APreset: TUmgAnchorPreset;
      out AMinUV, AMaxUV: TVector2); static;
    class function AnchorPresetTitle(const APreset: TUmgAnchorPreset): String; static;
    class function AnimPropertyTitle(const AProp: TUmgAnimProperty): String; static;
    class procedure ApplyAnchorPresetToControl(const AControl: TCastleUserInterface;
      const APreset: TUmgAnchorPreset; const AOffset: TVector2); static;

    { Authoring API }
    procedure ClearAll;
    procedure ApplyPreset(const APreset: TUmgWidgetAnimPreset);
    function AddOrUpdateSlot(const AWidgetName: String;
      const AAnchor: TUmgAnchorPreset;
      const ARestX, ARestY, ARestW, ARestH: Single;
      const ARestColor: TCastleColor): Integer;
    function FindSlotIndex(const AWidgetName: String): Integer;
    function SetWidgetAnchorPreset(const AWidgetName: String;
      const AAnchor: TUmgAnchorPreset): Boolean;
    function FindClipIndex(const AClipName: String): Integer;
    function AddClip(const AClip: TUmgWidgetAnimClip): Integer;
    procedure AddEventBinding(const ASourceWidget: String;
      const ATrigger: TUmgEventTriggerKind; const AClipName: String;
      const AMode: TUmgPlaybackMode; const ASpeed: Single = 1.0);

    { Sequencer & UUserWidget::PlayAnimation API }
    procedure ResetToRestState;
    function PlayAnimation(const AClipName: String;
      const AMode: TUmgPlaybackMode = upmForward;
      const ANumLoops: Integer = 1;
      const APlaybackSpeed: Single = 1.0): Boolean;
    procedure PauseAnimation;
    procedure StopAnimation(const ARestoreRestState: Boolean = True);
    procedure ScrubTimeline(const ATimeSec: Single);
    procedure StepAnimator(const ADeltaSeconds: Single);
    function FireUiEvent(const ASourceWidgetName: String;
      const ATrigger: TUmgEventTriggerKind): Integer;

    function TotalTrackCount: Integer;
    function TotalKeyframeCount: Integer;
    function WidgetAnimSummaryBadge: String;

    property Slots: TUmgManagedWidgetSlotArray read FSlots;
    property Clips: TUmgWidgetAnimClipArray read FClips;
    property Bindings: TUmgEventBindingArray read FBindings;
    property ActiveClipIndex: Integer read FActiveClipIndex write FActiveClipIndex;
    property CurrentTimeSec: Single read FCurrentTimeSec;
    property PlayMode: TUmgPlaybackMode read FPlayMode;
    property Playing: Boolean read FPlaying;
    property EventsTriggeredCount: Integer read FEventsTriggeredCount;
  published
    property ShowPreviewCanvas: Boolean read FShowPreviewCanvas write SetShowPreviewCanvas default True;
    property TimelineJson: String read GetTimelineJson write SetTimelineJson;
    property Preset: TUmgWidgetAnimPreset read FPreset write SetPreset default uwapModalPopupSlideBounceAndFade;
  end;

implementation

uses
  fpjson, jsonparser;

{ Easing & Track Evaluation -------------------------------------------------- }

class function TCastleWidgetAnimator.EvaluateUmgEasing(
  const AEasing: TUmgAnimEasing; const T: Single): Single;
const
  C1 = 1.70158;
  C3 = C1 + 1.0;
  N1 = 7.5625;
  D1 = 2.75;
var
  U, InvU, B: Single;
begin
  U := EnsureRange(T, 0.0, 1.0);
  if U <= 0.0 then Exit(0.0);
  if U >= 1.0 then Exit(1.0);

  case AEasing of
    uaeLinear:
      Result := U;
    uaeCubicEaseIn:
      Result := U * U * U;
    uaeCubicEaseOut:
      begin
        InvU := 1.0 - U;
        Result := 1.0 - InvU * InvU * InvU;
      end;
    uaeHermiteSmoothStep:
      Result := U * U * (3.0 - 2.0 * U);
    uaeBackOvershootOut:
      begin
        InvU := U - 1.0;
        Result := 1.0 + C3 * InvU * InvU * InvU + C1 * InvU * InvU;
      end;
    uaeBounceOut:
      begin
        B := U;
        if B < (1.0 / D1) then
          Result := N1 * B * B
        else if B < (2.0 / D1) then
        begin
          B := B - (1.5 / D1);
          Result := N1 * B * B + 0.75;
        end else if B < (2.5 / D1) then
        begin
          B := B - (2.25 / D1);
          Result := N1 * B * B + 0.9375;
        end else
        begin
          B := B - (2.625 / D1);
          Result := N1 * B * B + 0.984375;
        end;
      end;
  end;
end;

function TUmgAnimTrack.Evaluate(const ATimeSec: Single): Single;
var
  N, I: Integer;
  Span, LocalT, EasedT: Single;
begin
  N := Length(Keys);
  if N = 0 then Exit(0.0);
  if (N = 1) or (ATimeSec <= Keys[0].TimeSec) then
    Exit(Keys[0].Value);
  if ATimeSec >= Keys[N - 1].TimeSec then
    Exit(Keys[N - 1].Value);

  for I := 0 to N - 2 do
    if (ATimeSec >= Keys[I].TimeSec) and (ATimeSec <= Keys[I + 1].TimeSec) then
    begin
      Span := Max(1e-5, Keys[I + 1].TimeSec - Keys[I].TimeSec);
      LocalT := EnsureRange((ATimeSec - Keys[I].TimeSec) / Span, 0.0, 1.0);
      EasedT := TCastleWidgetAnimator.EvaluateUmgEasing(Keys[I].EasingToNext, LocalT);
      Exit(Keys[I].Value + (Keys[I + 1].Value - Keys[I].Value) * EasedT);
    end;
  Result := Keys[N - 1].Value;
end;

{ Anchor Flower Mapping ------------------------------------------------------ }

class procedure TCastleWidgetAnimator.NormalizedAnchorFlowerMinMax(
  const APreset: TUmgAnchorPreset; out AMinUV, AMaxUV: TVector2);
begin
  { UV in CGE bottom-left (0,0) -> top-right (1,1) screen coordinates }
  case APreset of
    uapTopLeft:                 begin AMinUV := Vector2(0.0, 1.0); AMaxUV := Vector2(0.0, 1.0); end;
    uapTopCenter:               begin AMinUV := Vector2(0.5, 1.0); AMaxUV := Vector2(0.5, 1.0); end;
    uapTopRight:                begin AMinUV := Vector2(1.0, 1.0); AMaxUV := Vector2(1.0, 1.0); end;
    uapCenterLeft:              begin AMinUV := Vector2(0.0, 0.5); AMaxUV := Vector2(0.0, 0.5); end;
    uapCenter:                  begin AMinUV := Vector2(0.5, 0.5); AMaxUV := Vector2(0.5, 0.5); end;
    uapCenterRight:             begin AMinUV := Vector2(1.0, 0.5); AMaxUV := Vector2(1.0, 0.5); end;
    uapBottomLeft:              begin AMinUV := Vector2(0.0, 0.0); AMaxUV := Vector2(0.0, 0.0); end;
    uapBottomCenter:            begin AMinUV := Vector2(0.5, 0.0); AMaxUV := Vector2(0.5, 0.0); end;
    uapBottomRight:             begin AMinUV := Vector2(1.0, 0.0); AMaxUV := Vector2(1.0, 0.0); end;
    uapStretchHorizontalTop:    begin AMinUV := Vector2(0.0, 1.0); AMaxUV := Vector2(1.0, 1.0); end;
    uapStretchHorizontalBottom: begin AMinUV := Vector2(0.0, 0.0); AMaxUV := Vector2(1.0, 0.0); end;
    uapStretchVerticalLeft:     begin AMinUV := Vector2(0.0, 0.0); AMaxUV := Vector2(0.0, 1.0); end;
    uapStretchVerticalRight:    begin AMinUV := Vector2(1.0, 0.0); AMaxUV := Vector2(1.0, 1.0); end;
    uapStretchFullScreen:       begin AMinUV := Vector2(0.0, 0.0); AMaxUV := Vector2(1.0, 1.0); end;
  end;
end;

class function TCastleWidgetAnimator.AnchorPresetTitle(
  const APreset: TUmgAnchorPreset): String;
begin
  case APreset of
    uapTopLeft:                 Result := 'Top-Left';
    uapTopCenter:               Result := 'Top-Center';
    uapTopRight:                Result := 'Top-Right';
    uapCenterLeft:              Result := 'Center-Left';
    uapCenter:                  Result := 'Center';
    uapCenterRight:             Result := 'Center-Right';
    uapBottomLeft:              Result := 'Bottom-Left';
    uapBottomCenter:            Result := 'Bottom-Center';
    uapBottomRight:             Result := 'Bottom-Right';
    uapStretchHorizontalTop:    Result := 'Stretch H-Top';
    uapStretchHorizontalBottom: Result := 'Stretch H-Bottom';
    uapStretchVerticalLeft:     Result := 'Stretch V-Left';
    uapStretchVerticalRight:    Result := 'Stretch V-Right';
    uapStretchFullScreen:       Result := 'Stretch Full';
  end;
end;

class function TCastleWidgetAnimator.AnimPropertyTitle(
  const AProp: TUmgAnimProperty): String;
begin
  case AProp of
    uapRenderOpacity: Result := 'RenderOpacity';
    uapTranslationX:  Result := 'Translation.X';
    uapTranslationY:  Result := 'Translation.Y';
    uapScaleUniform:  Result := 'RenderScale';
    uapRotationDeg:   Result := 'RenderAngle';
    uapColorTintR:    Result := 'Color.R';
    uapColorTintG:    Result := 'Color.G';
    uapColorTintB:    Result := 'Color.B';
  end;
end;

class procedure TCastleWidgetAnimator.ApplyAnchorPresetToControl(
  const AControl: TCastleUserInterface; const APreset: TUmgAnchorPreset;
  const AOffset: TVector2);
begin
  if AControl = nil then Exit;

  AControl.FullSize := False;
  AControl.WidthFraction := 0.0;
  AControl.HeightFraction := 0.0;

  case APreset of
    uapTopLeft:
      begin
        AControl.Anchor(hpLeft, AOffset.X);
        AControl.Anchor(vpTop, AOffset.Y);
      end;
    uapTopCenter:
      begin
        AControl.Anchor(hpMiddle, AOffset.X);
        AControl.Anchor(vpTop, AOffset.Y);
      end;
    uapTopRight:
      begin
        AControl.Anchor(hpRight, AOffset.X);
        AControl.Anchor(vpTop, AOffset.Y);
      end;
    uapCenterLeft:
      begin
        AControl.Anchor(hpLeft, AOffset.X);
        AControl.Anchor(vpMiddle, AOffset.Y);
      end;
    uapCenter:
      begin
        AControl.Anchor(hpMiddle, AOffset.X);
        AControl.Anchor(vpMiddle, AOffset.Y);
      end;
    uapCenterRight:
      begin
        AControl.Anchor(hpRight, AOffset.X);
        AControl.Anchor(vpMiddle, AOffset.Y);
      end;
    uapBottomLeft:
      begin
        AControl.Anchor(hpLeft, AOffset.X);
        AControl.Anchor(vpBottom, AOffset.Y);
      end;
    uapBottomCenter:
      begin
        AControl.Anchor(hpMiddle, AOffset.X);
        AControl.Anchor(vpBottom, AOffset.Y);
      end;
    uapBottomRight:
      begin
        AControl.Anchor(hpRight, AOffset.X);
        AControl.Anchor(vpBottom, AOffset.Y);
      end;
    uapStretchHorizontalTop:
      begin
        AControl.WidthFraction := 1.0;
        AControl.Anchor(hpMiddle, 0.0);
        AControl.Anchor(vpTop, AOffset.Y);
      end;
    uapStretchHorizontalBottom:
      begin
        AControl.WidthFraction := 1.0;
        AControl.Anchor(hpMiddle, 0.0);
        AControl.Anchor(vpBottom, AOffset.Y);
      end;
    uapStretchVerticalLeft:
      begin
        AControl.HeightFraction := 1.0;
        AControl.Anchor(hpLeft, AOffset.X);
        AControl.Anchor(vpMiddle, 0.0);
      end;
    uapStretchVerticalRight:
      begin
        AControl.HeightFraction := 1.0;
        AControl.Anchor(hpRight, AOffset.X);
        AControl.Anchor(vpMiddle, 0.0);
      end;
    uapStretchFullScreen:
      begin
        AControl.FullSize := True;
        AControl.Translation := TVector2.Zero;
      end;
  end;
end;

{ TCastleWidgetAnimator ------------------------------------------------------ }

constructor TCastleWidgetAnimator.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FullSize := True;
  FShowPreviewCanvas := True;
  FActiveClipIndex := -1;
  FPlaybackSpeed := 1.0;
  ApplyPreset(uwapModalPopupSlideBounceAndFade);
end;

destructor TCastleWidgetAnimator.Destroy;
begin
  ClearPreviewCanvas;
  inherited;
end;

procedure TCastleWidgetAnimator.Loaded;
begin
  inherited;
  RebuildPreviewCanvas;
  ResetToRestState;
end;

function TCastleWidgetAnimator.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'ShowPreviewCanvas') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleWidgetAnimator.SetPreset(const AValue: TUmgWidgetAnimPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleWidgetAnimator.SetShowPreviewCanvas(const AValue: Boolean);
begin
  if FShowPreviewCanvas <> AValue then
  begin
    FShowPreviewCanvas := AValue;
    if not FShowPreviewCanvas then
      ClearPreviewCanvas
    else
      RebuildPreviewCanvas;
  end;
end;

procedure TCastleWidgetAnimator.ClearPreviewCanvas;
begin
  if FPreviewRoot <> nil then
    FreeAndNil(FPreviewRoot);
end;

procedure TCastleWidgetAnimator.RebuildPreviewCanvas;
var
  I: Integer;
  RectCtrl: TCastleRectangleControl;
begin
  ClearPreviewCanvas;
  if not FShowPreviewCanvas then Exit;

  FPreviewRoot := TCastleUserInterface.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.FullSize := True;
  FPreviewRoot.Name := 'UMG_PreviewRoot';
  InsertFront(FPreviewRoot);

  for I := 0 to High(FSlots) do
  begin
    RectCtrl := TCastleRectangleControl.Create(FPreviewRoot);
    RectCtrl.SetTransient;
    RectCtrl.Name := FSlots[I].WidgetName;
    RectCtrl.Width := FSlots[I].RestWidth;
    RectCtrl.Height := FSlots[I].RestHeight;
    RectCtrl.Color := FSlots[I].RestColor;
    ApplyAnchorPresetToControl(RectCtrl, FSlots[I].AnchorPreset,
      Vector2(FSlots[I].RestTransX, FSlots[I].RestTransY));
    FPreviewRoot.InsertFront(RectCtrl);
    ApplyEvaluatedSlotToControl(FSlots[I]);
  end;
end;

function TCastleWidgetAnimator.ResolveLiveUiControl(
  const AWidgetName: String): TCastleUserInterface;
var
  Found: TComponent;
  I: Integer;
begin
  Result := nil;
  if AWidgetName = '' then Exit;

  if Owner <> nil then
  begin
    Found := Owner.FindComponent(AWidgetName);
    if (Found is TCastleUserInterface) and (Found <> Self) then
      Exit(TCastleUserInterface(Found));
  end;

  if FPreviewRoot <> nil then
    for I := 0 to FPreviewRoot.ControlsCount - 1 do
      if SameText(FPreviewRoot.Controls[I].Name, AWidgetName) then
        Exit(FPreviewRoot.Controls[I]);
end;

procedure TCastleWidgetAnimator.ApplyEvaluatedSlotToControl(
  const ASlot: TUmgManagedWidgetSlot);
var
  Ctrl: TCastleUserInterface;
  FinalColor: TCastleColor;
begin
  Ctrl := ResolveLiveUiControl(ASlot.WidgetName);
  if Ctrl = nil then Exit;

  ApplyAnchorPresetToControl(Ctrl, ASlot.AnchorPreset,
    Vector2(ASlot.EvalTransX, ASlot.EvalTransY));

  if not Ctrl.FullSize then
  begin
    if Ctrl.WidthFraction <= 0.0 then
      Ctrl.Width := Max(2.0, ASlot.RestWidth * Max(0.01, ASlot.EvalScale));
    if Ctrl.HeightFraction <= 0.0 then
      Ctrl.Height := Max(2.0, ASlot.RestHeight * Max(0.01, ASlot.EvalScale));
  end;

  FinalColor := Vector4(
    EnsureRange(ASlot.EvalColorRGB.X, 0.0, 1.0),
    EnsureRange(ASlot.EvalColorRGB.Y, 0.0, 1.0),
    EnsureRange(ASlot.EvalColorRGB.Z, 0.0, 1.0),
    EnsureRange(ASlot.RestColor.W * ASlot.EvalOpacity, 0.0, 1.0));

  if Ctrl is TCastleRectangleControl then
    TCastleRectangleControl(Ctrl).Color := FinalColor
  else if Ctrl is TCastleLabel then
    TCastleLabel(Ctrl).Color := FinalColor
  else if Ctrl is TCastleImageControl then
  begin
    TCastleImageControl(Ctrl).Color := FinalColor;
    TCastleImageControl(Ctrl).Rotation := DegToRad(ASlot.EvalRotationDeg);
  end;
end;

procedure TCastleWidgetAnimator.ClearAll;
begin
  FSlots := nil;
  FClips := nil;
  FBindings := nil;
  FActiveClipIndex := -1;
  FCurrentTimeSec := 0.0;
  FPlaying := False;
  FEventsTriggeredCount := 0;
  ClearPreviewCanvas;
end;

function TCastleWidgetAnimator.FindSlotIndex(const AWidgetName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].WidgetName, AWidgetName) then
      Exit(I);
  Result := -1;
end;

function TCastleWidgetAnimator.AddOrUpdateSlot(const AWidgetName: String;
  const AAnchor: TUmgAnchorPreset;
  const ARestX, ARestY, ARestW, ARestH: Single;
  const ARestColor: TCastleColor): Integer;
var
  S: TUmgManagedWidgetSlot;
begin
  Result := FindSlotIndex(AWidgetName);
  if Result < 0 then
  begin
    Result := Length(FSlots);
    SetLength(FSlots, Result + 1);
  end;
  S := Default(TUmgManagedWidgetSlot);
  S.WidgetName := AWidgetName;
  S.AnchorPreset := AAnchor;
  S.RestTransX := ARestX;
  S.RestTransY := ARestY;
  S.RestWidth := ARestW;
  S.RestHeight := ARestH;
  S.RestColor := ARestColor;
  S.EvalTransX := ARestX;
  S.EvalTransY := ARestY;
  S.EvalScale := 1.0;
  S.EvalRotationDeg := 0.0;
  S.EvalOpacity := 1.0;
  S.EvalColorRGB := Vector3(ARestColor.X, ARestColor.Y, ARestColor.Z);
  FSlots[Result] := S;
end;

function TCastleWidgetAnimator.SetWidgetAnchorPreset(
  const AWidgetName: String; const AAnchor: TUmgAnchorPreset): Boolean;
var
  Idx: Integer;
begin
  Idx := FindSlotIndex(AWidgetName);
  if Idx < 0 then Exit(False);
  FSlots[Idx].AnchorPreset := AAnchor;
  ApplyEvaluatedSlotToControl(FSlots[Idx]);
  Result := True;
end;

function TCastleWidgetAnimator.FindClipIndex(const AClipName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FClips) do
    if SameText(FClips[I].ClipName, AClipName) then
      Exit(I);
  Result := -1;
end;

function TCastleWidgetAnimator.AddClip(const AClip: TUmgWidgetAnimClip): Integer;
begin
  Result := FindClipIndex(AClip.ClipName);
  if Result < 0 then
  begin
    Result := Length(FClips);
    SetLength(FClips, Result + 1);
  end;
  FClips[Result] := AClip;
  if FActiveClipIndex < 0 then
    FActiveClipIndex := Result;
end;

procedure TCastleWidgetAnimator.AddEventBinding(const ASourceWidget: String;
  const ATrigger: TUmgEventTriggerKind; const AClipName: String;
  const AMode: TUmgPlaybackMode; const ASpeed: Single);
var
  N: Integer;
begin
  N := Length(FBindings);
  SetLength(FBindings, N + 1);
  FBindings[N].SourceWidgetName := ASourceWidget;
  FBindings[N].Trigger := ATrigger;
  FBindings[N].ClipName := AClipName;
  FBindings[N].PlayMode := AMode;
  FBindings[N].PlaybackSpeed := Max(0.05, ASpeed);
end;

procedure TCastleWidgetAnimator.ResetToRestState;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
  begin
    FSlots[I].EvalTransX := FSlots[I].RestTransX;
    FSlots[I].EvalTransY := FSlots[I].RestTransY;
    FSlots[I].EvalScale := 1.0;
    FSlots[I].EvalRotationDeg := 0.0;
    FSlots[I].EvalOpacity := 1.0;
    FSlots[I].EvalColorRGB := Vector3(
      FSlots[I].RestColor.X, FSlots[I].RestColor.Y, FSlots[I].RestColor.Z);
    ApplyEvaluatedSlotToControl(FSlots[I]);
  end;
end;

procedure TCastleWidgetAnimator.EvaluateClipAtCurrentTime;
var
  Clip: TUmgWidgetAnimClip;
  TIdx, SIdx: Integer;
  Val: Single;
begin
  if (FActiveClipIndex < 0) or (FActiveClipIndex > High(FClips)) then Exit;
  Clip := FClips[FActiveClipIndex];

  for TIdx := 0 to High(Clip.Tracks) do
  begin
    SIdx := FindSlotIndex(Clip.Tracks[TIdx].TargetWidgetName);
    if SIdx < 0 then Continue;
    Val := Clip.Tracks[TIdx].Evaluate(FCurrentTimeSec);
    case Clip.Tracks[TIdx].Prop of
      uapRenderOpacity: FSlots[SIdx].EvalOpacity := EnsureRange(Val, 0.0, 1.0);
      uapTranslationX:  FSlots[SIdx].EvalTransX := Val;
      uapTranslationY:  FSlots[SIdx].EvalTransY := Val;
      uapScaleUniform:  FSlots[SIdx].EvalScale := Max(0.01, Val);
      uapRotationDeg:   FSlots[SIdx].EvalRotationDeg := Val;
      uapColorTintR:    FSlots[SIdx].EvalColorRGB.X := EnsureRange(Val, 0.0, 1.0);
      uapColorTintG:    FSlots[SIdx].EvalColorRGB.Y := EnsureRange(Val, 0.0, 1.0);
      uapColorTintB:    FSlots[SIdx].EvalColorRGB.Z := EnsureRange(Val, 0.0, 1.0);
    end;
  end;

  for SIdx := 0 to High(FSlots) do
    ApplyEvaluatedSlotToControl(FSlots[SIdx]);
end;

function TCastleWidgetAnimator.PlayAnimation(const AClipName: String;
  const AMode: TUmgPlaybackMode; const ANumLoops: Integer;
  const APlaybackSpeed: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindClipIndex(AClipName);
  if Idx < 0 then Exit(False);

  FActiveClipIndex := Idx;
  FPlayMode := AMode;
  FPlaybackSpeed := Max(0.05, APlaybackSpeed);
  FRemainingLoops := Max(1, ANumLoops);
  FPingPongForward := True;
  FPlaying := True;

  if AMode = upmReverse then
    FCurrentTimeSec := FClips[Idx].DurationSec
  else
    FCurrentTimeSec := 0.0;

  EvaluateClipAtCurrentTime;
  Result := True;
end;

procedure TCastleWidgetAnimator.PauseAnimation;
begin
  FPlaying := False;
end;

procedure TCastleWidgetAnimator.StopAnimation(const ARestoreRestState: Boolean);
begin
  FPlaying := False;
  FCurrentTimeSec := 0.0;
  if ARestoreRestState then
    ResetToRestState;
end;

procedure TCastleWidgetAnimator.ScrubTimeline(const ATimeSec: Single);
var
  Dur: Single;
begin
  if (FActiveClipIndex < 0) or (FActiveClipIndex > High(FClips)) then Exit;
  Dur := Max(0.01, FClips[FActiveClipIndex].DurationSec);
  FCurrentTimeSec := EnsureRange(ATimeSec, 0.0, Dur);
  EvaluateClipAtCurrentTime;
end;

procedure TCastleWidgetAnimator.StepAnimator(const ADeltaSeconds: Single);
var
  Dt, Dur: Single;
begin
  if (not FPlaying) or (FActiveClipIndex < 0) or (FActiveClipIndex > High(FClips)) then
    Exit;
  Dt := Max(0.0, ADeltaSeconds) * FPlaybackSpeed;
  if Dt <= 0.0 then Exit;

  Dur := Max(0.01, FClips[FActiveClipIndex].DurationSec);

  case FPlayMode of
    upmForward:
      begin
        FCurrentTimeSec := FCurrentTimeSec + Dt;
        if FCurrentTimeSec >= Dur then
        begin
          Dec(FRemainingLoops);
          if FRemainingLoops > 0 then
            FCurrentTimeSec := FCurrentTimeSec - Dur
          else
          begin
            FCurrentTimeSec := Dur;
            FPlaying := False;
          end;
        end;
      end;

    upmReverse:
      begin
        FCurrentTimeSec := FCurrentTimeSec - Dt;
        if FCurrentTimeSec <= 0.0 then
        begin
          Dec(FRemainingLoops);
          if FRemainingLoops > 0 then
            FCurrentTimeSec := Dur + FCurrentTimeSec
          else
          begin
            FCurrentTimeSec := 0.0;
            FPlaying := False;
          end;
        end;
      end;

    upmLoopForward:
      begin
        FCurrentTimeSec := FCurrentTimeSec + Dt;
        while FCurrentTimeSec > Dur do
          FCurrentTimeSec := FCurrentTimeSec - Dur;
      end;

    upmPingPong:
      begin
        if FPingPongForward then
        begin
          FCurrentTimeSec := FCurrentTimeSec + Dt;
          if FCurrentTimeSec >= Dur then
          begin
            FCurrentTimeSec := Dur - (FCurrentTimeSec - Dur);
            FPingPongForward := False;
          end;
        end else
        begin
          FCurrentTimeSec := FCurrentTimeSec - Dt;
          if FCurrentTimeSec <= 0.0 then
          begin
            Dec(FRemainingLoops);
            if FRemainingLoops > 0 then
            begin
              FCurrentTimeSec := -FCurrentTimeSec;
              FPingPongForward := True;
            end else
            begin
              FCurrentTimeSec := 0.0;
              FPlaying := False;
            end;
          end;
        end;
      end;
  end;

  FCurrentTimeSec := EnsureRange(FCurrentTimeSec, 0.0, Dur);
  EvaluateClipAtCurrentTime;
end;

procedure TCastleWidgetAnimator.Update(const SecondsPassed: Single;
  var HandleInput: Boolean);
begin
  inherited;
  if FPlaying then
    StepAnimator(SecondsPassed);
end;

function TCastleWidgetAnimator.FireUiEvent(const ASourceWidgetName: String;
  const ATrigger: TUmgEventTriggerKind): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FBindings) do
    if (FBindings[I].Trigger = ATrigger) and
       ((FBindings[I].SourceWidgetName = '') or
        SameText(FBindings[I].SourceWidgetName, ASourceWidgetName)) then
    begin
      if PlayAnimation(FBindings[I].ClipName, FBindings[I].PlayMode, 1,
           FBindings[I].PlaybackSpeed) then
      begin
        Inc(Result);
        Inc(FEventsTriggeredCount);
      end;
    end;
end;

{ Built-In UE 5.5 UMG Starter Presets ---------------------------------------- }

procedure TCastleWidgetAnimator.ApplyPreset(const APreset: TUmgWidgetAnimPreset);

  function Make2KeyTrack(const AWidget: String; const AProp: TUmgAnimProperty;
    const T0, V0: Single; const E0: TUmgAnimEasing;
    const T1, V1: Single): TUmgAnimTrack;
  begin
    Result := Default(TUmgAnimTrack);
    Result.TargetWidgetName := AWidget;
    Result.Prop := AProp;
    SetLength(Result.Keys, 2);
    Result.Keys[0].TimeSec := T0;
    Result.Keys[0].Value := V0;
    Result.Keys[0].EasingToNext := E0;
    Result.Keys[1].TimeSec := T1;
    Result.Keys[1].Value := V1;
    Result.Keys[1].EasingToNext := uaeLinear;
  end;

var
  Clip: TUmgWidgetAnimClip;
begin
  FPreset := APreset;
  if APreset = uwapCustom then Exit;

  ClearAll;
  FPreset := APreset;

  case APreset of
    uwapModalPopupSlideBounceAndFade:
      begin
        AddOrUpdateSlot('ModalCard', uapCenter, 0.0, 0.0, 440.0, 260.0,
          Vector4(0.14, 0.17, 0.24, 0.96));
        AddOrUpdateSlot('HeaderBanner', uapTopCenter, 0.0, -28.0, 400.0, 48.0,
          Vector4(0.20, 0.52, 0.92, 1.00));
        AddOrUpdateSlot('ConfirmBtn', uapBottomCenter, 0.0, 36.0, 180.0, 46.0,
          Vector4(0.22, 0.78, 0.44, 1.00));

        Clip := Default(TUmgWidgetAnimClip);
        Clip.ClipName := 'Anim_ModalOpen';
        Clip.DurationSec := 0.60;
        SetLength(Clip.Tracks, 4);
        Clip.Tracks[0] := Make2KeyTrack('ModalCard', uapRenderOpacity, 0.0, 0.0, uaeCubicEaseOut, 0.45, 1.0);
        Clip.Tracks[1] := Make2KeyTrack('ModalCard', uapTranslationY, 0.0, -140.0, uaeBounceOut, 0.60, 0.0);
        Clip.Tracks[2] := Make2KeyTrack('ModalCard', uapScaleUniform, 0.0, 0.72, uaeBackOvershootOut, 0.60, 1.0);
        Clip.Tracks[3] := Make2KeyTrack('HeaderBanner', uapRenderOpacity, 0.10, 0.0, uaeHermiteSmoothStep, 0.60, 1.0);
        AddClip(Clip);

        Clip := Default(TUmgWidgetAnimClip);
        Clip.ClipName := 'Anim_ButtonHover';
        Clip.DurationSec := 0.20;
        SetLength(Clip.Tracks, 2);
        Clip.Tracks[0] := Make2KeyTrack('ConfirmBtn', uapScaleUniform, 0.0, 1.00, uaeCubicEaseOut, 0.20, 1.15);
        Clip.Tracks[1] := Make2KeyTrack('ConfirmBtn', uapColorTintG, 0.0, 0.78, uaeLinear, 0.20, 0.96);
        AddClip(Clip);

        AddEventBinding('', uetOnShow, 'Anim_ModalOpen', upmForward, 1.0);
        AddEventBinding('ConfirmBtn', uetOnHoverEnter, 'Anim_ButtonHover', upmForward, 1.0);
        AddEventBinding('ConfirmBtn', uetOnHoverLeave, 'Anim_ButtonHover', upmReverse, 1.0);
      end;

    uwapHudDamageToastAndHealthFlash:
      begin
        AddOrUpdateSlot('HealthBarCard', uapBottomLeft, 28.0, 28.0, 280.0, 38.0,
          Vector4(0.20, 0.82, 0.36, 0.95));
        AddOrUpdateSlot('QuestToastCard', uapTopRight, -24.0, -24.0, 310.0, 68.0,
          Vector4(0.18, 0.22, 0.30, 0.94));

        Clip := Default(TUmgWidgetAnimClip);
        Clip.ClipName := 'Anim_DamageFlash';
        Clip.DurationSec := 0.40;
        SetLength(Clip.Tracks, 3);
        Clip.Tracks[0] := Make2KeyTrack('HealthBarCard', uapColorTintR, 0.0, 0.20, uaeCubicEaseOut, 0.40, 1.00);
        Clip.Tracks[1] := Make2KeyTrack('HealthBarCard', uapColorTintG, 0.0, 0.82, uaeCubicEaseOut, 0.40, 0.14);
        Clip.Tracks[2] := Make2KeyTrack('HealthBarCard', uapScaleUniform, 0.0, 1.00, uaeBackOvershootOut, 0.40, 1.12);
        AddClip(Clip);

        Clip := Default(TUmgWidgetAnimClip);
        Clip.ClipName := 'Anim_ToastSlideIn';
        Clip.DurationSec := 0.50;
        SetLength(Clip.Tracks, 2);
        Clip.Tracks[0] := Make2KeyTrack('QuestToastCard', uapTranslationX, 0.0, 280.0, uaeCubicEaseOut, 0.50, -24.0);
        Clip.Tracks[1] := Make2KeyTrack('QuestToastCard', uapRenderOpacity, 0.0, 0.0, uaeHermiteSmoothStep, 0.35, 1.0);
        AddClip(Clip);

        AddEventBinding('HealthBarCard', uetOnDamagePulse, 'Anim_DamageFlash', upmPingPong, 1.0);
      end;

    uwapBossHealthBannerStretchReveal:
      begin
        AddOrUpdateSlot('BossTopBanner', uapStretchHorizontalTop, 0.0, -16.0, 800.0, 44.0,
          Vector4(0.76, 0.16, 0.22, 0.95));
        Clip := Default(TUmgWidgetAnimClip);
        Clip.ClipName := 'Anim_BossReveal';
        Clip.DurationSec := 0.75;
        SetLength(Clip.Tracks, 2);
        Clip.Tracks[0] := Make2KeyTrack('BossTopBanner', uapRenderOpacity, 0.0, 0.0, uaeHermiteSmoothStep, 0.75, 1.0);
        Clip.Tracks[1] := Make2KeyTrack('BossTopBanner', uapTranslationY, 0.0, 48.0, uaeBounceOut, 0.75, -16.0);
        AddClip(Clip);
      end;
  end;

  RebuildPreviewCanvas;
  FActiveClipIndex := 0;
  ResetToRestState;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleWidgetAnimator.GetTimelineJson: String;
var
  Root, SObj, CObj, TObj, KObj, BObj: TJSONObject;
  SArr, CArr, TArr, KArr, BArr, RgbaArr: TJSONArray;
  I, J, K: Integer;
begin
  Root := TJSONObject.Create;
  try
    SArr := TJSONArray.Create;
    for I := 0 to High(FSlots) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('name', FSlots[I].WidgetName);
      SObj.Add('anc', Ord(FSlots[I].AnchorPreset));
      SObj.Add('rx', FSlots[I].RestTransX);
      SObj.Add('ry', FSlots[I].RestTransY);
      SObj.Add('rw', FSlots[I].RestWidth);
      SObj.Add('rh', FSlots[I].RestHeight);
      RgbaArr := TJSONArray.Create;
      RgbaArr.Add(FSlots[I].RestColor.X);
      RgbaArr.Add(FSlots[I].RestColor.Y);
      RgbaArr.Add(FSlots[I].RestColor.Z);
      RgbaArr.Add(FSlots[I].RestColor.W);
      SObj.Add('col', RgbaArr);
      SArr.Add(SObj);
    end;
    Root.Add('slots', SArr);

    CArr := TJSONArray.Create;
    for I := 0 to High(FClips) do
    begin
      CObj := TJSONObject.Create;
      CObj.Add('name', FClips[I].ClipName);
      CObj.Add('dur', FClips[I].DurationSec);
      TArr := TJSONArray.Create;
      for J := 0 to High(FClips[I].Tracks) do
      begin
        TObj := TJSONObject.Create;
        TObj.Add('target', FClips[I].Tracks[J].TargetWidgetName);
        TObj.Add('prop', Ord(FClips[I].Tracks[J].Prop));
        KArr := TJSONArray.Create;
        for K := 0 to High(FClips[I].Tracks[J].Keys) do
        begin
          KObj := TJSONObject.Create;
          KObj.Add('t', FClips[I].Tracks[J].Keys[K].TimeSec);
          KObj.Add('v', FClips[I].Tracks[J].Keys[K].Value);
          KObj.Add('e', Ord(FClips[I].Tracks[J].Keys[K].EasingToNext));
          KArr.Add(KObj);
        end;
        TObj.Add('keys', KArr);
        TArr.Add(TObj);
      end;
      CObj.Add('tracks', TArr);
      CArr.Add(CObj);
    end;
    Root.Add('clips', CArr);

    BArr := TJSONArray.Create;
    for I := 0 to High(FBindings) do
    begin
      BObj := TJSONObject.Create;
      BObj.Add('src', FBindings[I].SourceWidgetName);
      BObj.Add('trig', Ord(FBindings[I].Trigger));
      BObj.Add('clip', FBindings[I].ClipName);
      BObj.Add('mode', Ord(FBindings[I].PlayMode));
      BObj.Add('spd', FBindings[I].PlaybackSpeed);
      BArr.Add(BObj);
    end;
    Root.Add('bindings', BArr);

    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleWidgetAnimator.SetTimelineJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, SObj, CObj, TObj, KObj, BObj: TJSONObject;
  SArr, CArr, TArr, KArr, BArr, RgbaArr: TJSONArray;
  I, J, K: Integer;
  Col: TCastleColor;
  Clip: TUmgWidgetAnimClip;
begin
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;
  try
    if not (Parsed is TJSONObject) then Exit;
    Root := TJSONObject(Parsed);
    ClearAll;
    FPreset := uwapCustom;

    SArr := Root.Find('slots', jtArray) as TJSONArray;
    if SArr <> nil then
      for I := 0 to SArr.Count - 1 do
        if SArr.Items[I] is TJSONObject then
        begin
          SObj := TJSONObject(SArr.Items[I]);
          Col := Vector4(1, 1, 1, 1);
          RgbaArr := SObj.Find('col', jtArray) as TJSONArray;
          if (RgbaArr <> nil) and (RgbaArr.Count >= 4) then
            Col := Vector4(RgbaArr.Floats[0], RgbaArr.Floats[1], RgbaArr.Floats[2], RgbaArr.Floats[3]);
          AddOrUpdateSlot(
            SObj.Get('name', 'Widget_' + IntToStr(I)),
            TUmgAnchorPreset(EnsureRange(SObj.Get('anc', 0), 0, Ord(High(TUmgAnchorPreset)))),
            SObj.Get('rx', 0.0), SObj.Get('ry', 0.0),
            SObj.Get('rw', 120.0), SObj.Get('rh', 48.0), Col);
        end;

    CArr := Root.Find('clips', jtArray) as TJSONArray;
    if CArr <> nil then
      for I := 0 to CArr.Count - 1 do
        if CArr.Items[I] is TJSONObject then
        begin
          CObj := TJSONObject(CArr.Items[I]);
          Clip := Default(TUmgWidgetAnimClip);
          Clip.ClipName := CObj.Get('name', 'Clip_' + IntToStr(I));
          Clip.DurationSec := Max(0.01, CObj.Get('dur', 0.5));
          TArr := CObj.Find('tracks', jtArray) as TJSONArray;
          if TArr <> nil then
          begin
            SetLength(Clip.Tracks, TArr.Count);
            for J := 0 to TArr.Count - 1 do
              if TArr.Items[J] is TJSONObject then
              begin
                TObj := TJSONObject(TArr.Items[J]);
                Clip.Tracks[J].TargetWidgetName := TObj.Get('target', '');
                Clip.Tracks[J].Prop := TUmgAnimProperty(
                  EnsureRange(TObj.Get('prop', 0), 0, Ord(High(TUmgAnimProperty))));
                KArr := TObj.Find('keys', jtArray) as TJSONArray;
                if KArr <> nil then
                begin
                  SetLength(Clip.Tracks[J].Keys, KArr.Count);
                  for K := 0 to KArr.Count - 1 do
                    if KArr.Items[K] is TJSONObject then
                    begin
                      KObj := TJSONObject(KArr.Items[K]);
                      Clip.Tracks[J].Keys[K].TimeSec := KObj.Get('t', 0.0);
                      Clip.Tracks[J].Keys[K].Value := KObj.Get('v', 0.0);
                      Clip.Tracks[J].Keys[K].EasingToNext := TUmgAnimEasing(
                        EnsureRange(KObj.Get('e', 0), 0, Ord(High(TUmgAnimEasing))));
                    end;
                end;
              end;
          end;
          AddClip(Clip);
        end;

    BArr := Root.Find('bindings', jtArray) as TJSONArray;
    if BArr <> nil then
      for I := 0 to BArr.Count - 1 do
        if BArr.Items[I] is TJSONObject then
        begin
          BObj := TJSONObject(BArr.Items[I]);
          AddEventBinding(
            BObj.Get('src', ''),
            TUmgEventTriggerKind(EnsureRange(BObj.Get('trig', 0), 0, Ord(High(TUmgEventTriggerKind)))),
            BObj.Get('clip', ''),
            TUmgPlaybackMode(EnsureRange(BObj.Get('mode', 0), 0, Ord(High(TUmgPlaybackMode)))),
            BObj.Get('spd', 1.0));
        end;

    RebuildPreviewCanvas;
    ResetToRestState;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleWidgetAnimator.TotalTrackCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FClips) do
    Inc(Result, Length(FClips[I].Tracks));
end;

function TCastleWidgetAnimator.TotalKeyframeCount: Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(FClips) do
    for J := 0 to High(FClips[I].Tracks) do
      Inc(Result, Length(FClips[I].Tracks[J].Keys));
end;

function TCastleWidgetAnimator.WidgetAnimSummaryBadge: String;
begin
  Result := Format('[UMG:Clips=%d Tracks=%d Slots=%d t=%.2fs]',
    [Length(FClips), TotalTrackCount, Length(FSlots), FCurrentTimeSec]);
end;

initialization
  RegisterSerializableComponent(TCastleWidgetAnimator, 'UMG Widget Animation Timeline');
end.
