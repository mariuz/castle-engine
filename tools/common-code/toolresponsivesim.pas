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

{ Multi-resolution 2D responsive UI layout simulator, notch/home-indicator
  safe-area auditor, sibling overlap detector, and 44 px touch-target validator
  (@link(TResponsiveUiSimulator))
  (Phase 295 — UE 5.9 / 6.0 CommonUI Responsive Parity). }
unit ToolResponsiveSim;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleRectangles;

type
  { Standard cross-platform display & safe-area hardware profiles. }
  TResponsiveDeviceProfileKind = (
    rdpDesktop16x9,
    rdpUltrawide21x9,
    rdpHandheld16x10,
    rdpMobileNotch195x9,
    rdpTablet4x3
  );

  { Responsive UI layout violation categories. }
  TResponsiveIssueKind = (
    rikOffScreenClipped,
    rikUnsafeNotchOrHomeBar,
    rikSiblingOverlap,
    rikUndersizedTouchTarget
  );

  TResponsiveDeviceSpec = record
    Profile: TResponsiveDeviceProfileKind;
    DisplayName: String;
    AspectLabel: String;
    WidthPx: Integer;
    HeightPx: Integer;
    InsetLeftPx: Single;
    InsetRightPx: Single;
    InsetTopPx: Single;
    InsetBottomPx: Single;
    RequiresTouchTargets: Boolean;
  end;

  TSimulatedControlBox = record
    ComponentName: String;
    ClassNameStr: String;
    ParentName: String;
    DeviceRect: TFloatRectangle;
    IsInteractive: Boolean;
    IsBackgroundContainer: Boolean;
    HasViolation: Boolean;
  end;
  TSimulatedControlBoxArray = array of TSimulatedControlBox;

  TResponsiveIssue = record
    Profile: TResponsiveDeviceProfileKind;
    Kind: TResponsiveIssueKind;
    ComponentName: String;
    SecondaryComponentName: String;
    Message: String;
  end;
  TResponsiveIssueArray = array of TResponsiveIssue;

  TResponsiveProfileSimResult = record
    Spec: TResponsiveDeviceSpec;
    SafeRectPx: TFloatRectangle;
    UiScale: Single;
    UnscaledWidth: Single;
    UnscaledHeight: Single;
    Boxes: TSimulatedControlBoxArray;
    Issues: TResponsiveIssueArray;
  end;

  TResponsiveAuditSummary = record
    Results: array [TResponsiveDeviceProfileKind] of TResponsiveProfileSimResult;
    TotalIssueCount: Integer;
    OffScreenCount: Integer;
    SafeAreaCount: Integer;
    OverlapCount: Integer;
    TouchTargetCount: Integer;
  end;

  TResponsiveUiSimulator = class
  public const
    MinRecommendedTouchTargetPx = 44.0;
    DefaultReferenceWidth = 1920.0;
    DefaultReferenceHeight = 1080.0;
  public
    class function GetProfileSpec(
      const AProfile: TResponsiveDeviceProfileKind): TResponsiveDeviceSpec;

    { Simulate CGE @code(usEncloseReferenceSize) anchor/fraction/size layout of
      @code(ARoot) on @code(AProfile) without requiring an OpenGL context. }
    class function SimulateProfile(const ARoot: TComponent;
      const AProfile: TResponsiveDeviceProfileKind;
      const ARefWidth: Single = DefaultReferenceWidth;
      const ARefHeight: Single = DefaultReferenceHeight): TResponsiveProfileSimResult;

    { Run @link(SimulateProfile) across all 5 hardware aspect/notch profiles
      and aggregate diagnostic counts. }
    class function AuditAllProfiles(const ARoot: TComponent;
      const ARefWidth: Single = DefaultReferenceWidth;
      const ARefHeight: Single = DefaultReferenceHeight): TResponsiveAuditSummary;

    { Export a Markdown responsive UI audit matrix across all 5 profiles. }
    class function FormatResponsiveAuditMarkdown(const ARoot: TComponent;
      const ARefWidth: Single = DefaultReferenceWidth;
      const ARefHeight: Single = DefaultReferenceHeight): String;
  end;

function ResponsiveIssueKindToLabel(const AKind: TResponsiveIssueKind): String;

implementation

uses
  Math, StrUtils,
  CastleUtils, CastleVectors, CastleUIControls, CastleControls, CastleViewport;

function ResponsiveIssueKindToLabel(const AKind: TResponsiveIssueKind): String;
begin
  case AKind of
    rikOffScreenClipped:      Result := 'Off-Screen Clip';
    rikUnsafeNotchOrHomeBar:  Result := 'Safe-Area / Notch';
    rikSiblingOverlap:        Result := 'Sibling Overlap';
    rikUndersizedTouchTarget: Result := 'Touch < 44px';
  end;
end;

function IsInteractiveUiControl(const C: TCastleUserInterface): Boolean;
begin
  Result :=
    (C is TCastleButton) or
    (C is TCastleCheckbox) or
    (C is TCastleEdit) or
    (C is TCastleIntegerEdit) or
    (C is TCastleFloatEdit);
end;

function EstimateUnscaledControlSize(const C: TCastleUserInterface;
  const AParentUnscaledW, AParentUnscaledH: Single): TVector2;
var
  W, H, FontPx: Single;
  Btn: TCastleButton;
  Lbl: TCastleLabel;
begin
  if C.EffectiveFullSize then
    Exit(Vector2(AParentUnscaledW, AParentUnscaledH));

  if C.WidthFraction > 0.0 then
    W := AParentUnscaledW * C.WidthFraction
  else
    W := C.Width;

  if C.HeightFraction > 0.0 then
    H := AParentUnscaledH * C.HeightFraction
  else
    H := C.Height;

  if C is TCastleButton then
  begin
    Btn := TCastleButton(C);
    if Btn.FontSize > 1.0 then
      FontPx := Btn.FontSize
    else
      FontPx := 20.0;
    if Btn.AutoSize and Btn.AutoSizeWidth then
      W := Max(Btn.MinWidth, Length(Btn.Caption) * (FontPx * 0.56) + Btn.PaddingHorizontal * 2.0);
    if Btn.AutoSize and Btn.AutoSizeHeight then
      H := Max(Btn.MinHeight, FontPx * 1.25 + Btn.PaddingVertical * 2.0);
  end else
  if C is TCastleLabel then
  begin
    Lbl := TCastleLabel(C);
    if Lbl.FontSize > 1.0 then
      FontPx := Lbl.FontSize
    else
      FontPx := 20.0;
    if Lbl.AutoSize then
    begin
      W := Max(8.0, Length(Lbl.Caption) * (FontPx * 0.56));
      H := Max(8.0, FontPx * 1.20);
    end;
  end;

  Result := Vector2(Max(0.0, W), Max(0.0, H));
end;

function ComputeUnscaledAnchoredRect(const C: TCastleUserInterface;
  const AParentRect: TFloatRectangle): TFloatRectangle;
var
  Sz: TVector2;
  ParentPivotX, SelfOffsetX, FinalLeft: Single;
  ParentPivotY, SelfOffsetY, FinalBottom: Single;
begin
  if C.EffectiveFullSize then
    Exit(AParentRect);

  Sz := EstimateUnscaledControlSize(C, AParentRect.Width, AParentRect.Height);

  case C.HorizontalAnchorParent of
    hpLeft:   ParentPivotX := AParentRect.Left;
    hpMiddle: ParentPivotX := AParentRect.Left + AParentRect.Width * 0.5;
    hpRight:  ParentPivotX := AParentRect.Left + AParentRect.Width;
  end;
  case C.HorizontalAnchorSelf of
    hpLeft:   SelfOffsetX := 0.0;
    hpMiddle: SelfOffsetX := -Sz.X * 0.5;
    hpRight:  SelfOffsetX := -Sz.X;
  end;
  FinalLeft := ParentPivotX + SelfOffsetX + C.Translation.X;

  case C.VerticalAnchorParent of
    vpBottom: ParentPivotY := AParentRect.Bottom;
    vpMiddle: ParentPivotY := AParentRect.Bottom + AParentRect.Height * 0.5;
    vpTop:    ParentPivotY := AParentRect.Bottom + AParentRect.Height;
  end;
  case C.VerticalAnchorSelf of
    vpBottom: SelfOffsetY := 0.0;
    vpMiddle: SelfOffsetY := -Sz.Y * 0.5;
    vpTop:    SelfOffsetY := -Sz.Y;
  end;
  FinalBottom := ParentPivotY + SelfOffsetY + C.Translation.Y;

  Result := FloatRectangle(FinalLeft, FinalBottom, Sz.X, Sz.Y);
end;

function IntersectArea(const A, B: TFloatRectangle): Single;
var
  X1, Y1, X2, Y2: Single;
begin
  X1 := Max(A.Left, B.Left);
  Y1 := Max(A.Bottom, B.Bottom);
  X2 := Min(A.Left + A.Width, B.Left + B.Width);
  Y2 := Min(A.Bottom + A.Height, B.Bottom + B.Height);
  if (X2 > X1) and (Y2 > Y1) then
    Result := (X2 - X1) * (Y2 - Y1)
  else
    Result := 0.0;
end;

{ TResponsiveUiSimulator ----------------------------------------------------- }

class function TResponsiveUiSimulator.GetProfileSpec(
  const AProfile: TResponsiveDeviceProfileKind): TResponsiveDeviceSpec;
begin
  Result.Profile := AProfile;
  case AProfile of
    rdpDesktop16x9:
      begin
        Result.DisplayName := 'Desktop 1080p';
        Result.AspectLabel := '16:9';
        Result.WidthPx := 1920;
        Result.HeightPx := 1080;
        Result.InsetLeftPx := 0;
        Result.InsetRightPx := 0;
        Result.InsetTopPx := 0;
        Result.InsetBottomPx := 0;
        Result.RequiresTouchTargets := false;
      end;
    rdpUltrawide21x9:
      begin
        Result.DisplayName := 'Ultrawide Cinema';
        Result.AspectLabel := '21:9';
        Result.WidthPx := 2560;
        Result.HeightPx := 1080;
        Result.InsetLeftPx := 0;
        Result.InsetRightPx := 0;
        Result.InsetTopPx := 0;
        Result.InsetBottomPx := 0;
        Result.RequiresTouchTargets := false;
      end;
    rdpHandheld16x10:
      begin
        Result.DisplayName := 'Handheld Deck';
        Result.AspectLabel := '16:10';
        Result.WidthPx := 1280;
        Result.HeightPx := 800;
        Result.InsetLeftPx := 0;
        Result.InsetRightPx := 0;
        Result.InsetTopPx := 0;
        Result.InsetBottomPx := 0;
        Result.RequiresTouchTargets := true;
      end;
    rdpMobileNotch195x9:
      begin
        Result.DisplayName := 'Mobile Notch Landscape';
        Result.AspectLabel := '19.5:9';
        Result.WidthPx := 2532;
        Result.HeightPx := 1170;
        Result.InsetLeftPx := 132;
        Result.InsetRightPx := 132;
        Result.InsetTopPx := 0;
        Result.InsetBottomPx := 63;
        Result.RequiresTouchTargets := true;
      end;
    rdpTablet4x3:
      begin
        Result.DisplayName := 'Tablet 4:3';
        Result.AspectLabel := '4:3';
        Result.WidthPx := 2048;
        Result.HeightPx := 1536;
        Result.InsetLeftPx := 0;
        Result.InsetRightPx := 0;
        Result.InsetTopPx := 0;
        Result.InsetBottomPx := 40;
        Result.RequiresTouchTargets := true;
      end;
  end;
end;

class function TResponsiveUiSimulator.SimulateProfile(const ARoot: TComponent;
  const AProfile: TResponsiveDeviceProfileKind;
  const ARefWidth, ARefHeight: Single): TResponsiveProfileSimResult;
const
  EpsPx = 0.75;

  procedure MarkBoxViolation(const ACompName: String);
  var
    K: Integer;
  begin
    for K := 0 to High(Result.Boxes) do
      if SameText(Result.Boxes[K].ComponentName, ACompName) then
        Result.Boxes[K].HasViolation := true;
  end;

  procedure AddIssue(const AKind: TResponsiveIssueKind;
    const AComp1, AComp2, AMsg: String);
  var
    N: Integer;
  begin
    N := Length(Result.Issues);
    SetLength(Result.Issues, N + 1);
    Result.Issues[N].Profile := AProfile;
    Result.Issues[N].Kind := AKind;
    Result.Issues[N].ComponentName := AComp1;
    Result.Issues[N].SecondaryComponentName := AComp2;
    Result.Issues[N].Message := AMsg;
    MarkBoxViolation(AComp1);
    if AComp2 <> '' then
      MarkBoxViolation(AComp2);
  end;

  procedure WalkUi(const C: TCastleUserInterface;
    const AParentUnscaledRect: TFloatRectangle;
    const AParentName: String;
    const AIsRoot: Boolean);
  var
    UnscaledR, DevR: TFloatRectangle;
    ScaleFactor: Single;
    BIdx, I: Integer;
    CName: String;
    IsBg: Boolean;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) or (not C.Exists) then
      Exit;

    if AIsRoot and (C.EffectiveFullSize or (C.ClassType = TCastleUserInterface)) then
      UnscaledR := AParentUnscaledRect
    else
      UnscaledR := ComputeUnscaledAnchoredRect(C, AParentUnscaledRect);

    if C.EnableUIScaling then
      ScaleFactor := Result.UiScale
    else
      ScaleFactor := 1.0;

    DevR := FloatRectangle(
      UnscaledR.Left * ScaleFactor,
      UnscaledR.Bottom * ScaleFactor,
      UnscaledR.Width * ScaleFactor,
      UnscaledR.Height * ScaleFactor);

    if C.Name <> '' then
      CName := C.Name
    else
      CName := '(' + C.ClassName + ')';

    IsBg := C.EffectiveFullSize or (C is TCastleViewport) or AIsRoot;

    BIdx := Length(Result.Boxes);
    SetLength(Result.Boxes, BIdx + 1);
    Result.Boxes[BIdx].ComponentName := CName;
    Result.Boxes[BIdx].ClassNameStr := C.ClassName;
    Result.Boxes[BIdx].ParentName := AParentName;
    Result.Boxes[BIdx].DeviceRect := DevR;
    Result.Boxes[BIdx].IsInteractive := IsInteractiveUiControl(C);
    Result.Boxes[BIdx].IsBackgroundContainer := IsBg;
    Result.Boxes[BIdx].HasViolation := false;

    if not IsBg then
    begin
      { 1. Off-screen clipping check }
      if (DevR.Left < -EpsPx) or
         (DevR.Bottom < -EpsPx) or
         (DevR.Left + DevR.Width > Result.Spec.WidthPx + EpsPx) or
         (DevR.Bottom + DevR.Height > Result.Spec.HeightPx + EpsPx) then
      begin
        AddIssue(rikOffScreenClipped, CName, '',
          Format('Control "%s" [%.0f, %.0f .. %.0f, %.0f] clips outside %dx%d screen.',
            [CName, DevR.Left, DevR.Bottom,
             DevR.Left + DevR.Width, DevR.Bottom + DevR.Height,
             Result.Spec.WidthPx, Result.Spec.HeightPx]));
      end else
      { 2. Safe-area notch / home-indicator check }
      if (DevR.Left < Result.SafeRectPx.Left - EpsPx) or
         (DevR.Bottom < Result.SafeRectPx.Bottom - EpsPx) or
         (DevR.Left + DevR.Width > Result.SafeRectPx.Left + Result.SafeRectPx.Width + EpsPx) or
         (DevR.Bottom + DevR.Height > Result.SafeRectPx.Bottom + Result.SafeRectPx.Height + EpsPx) then
      begin
        AddIssue(rikUnsafeNotchOrHomeBar, CName, '',
          Format('Control "%s" intrudes into %s hardware notch / home-indicator unsafe margin.',
            [CName, Result.Spec.DisplayName]));
      end;

      { 3. Physical touch-target minimum 44 px check }
      if Result.Spec.RequiresTouchTargets and Result.Boxes[BIdx].IsInteractive and
         ((DevR.Width < MinRecommendedTouchTargetPx - EpsPx) or
          (DevR.Height < MinRecommendedTouchTargetPx - EpsPx)) then
      begin
        AddIssue(rikUndersizedTouchTarget, CName, '',
          Format('Interactive control "%s" renders at %.0fx%.0f px on %s (< 44x44 px touch target).',
            [CName, DevR.Width, DevR.Height, Result.Spec.DisplayName]));
      end;
    end;

    for I := 0 to C.ControlsCount - 1 do
      WalkUi(C.Controls[I], UnscaledR, CName, false);
  end;

var
  RefW, RefH: Single;
  RootContainerRect: TFloatRectangle;
  I, J: Integer;
  OverlapPx2: Single;
begin
  Result := Default(TResponsiveProfileSimResult);
  Result.Spec := GetProfileSpec(AProfile);
  Result.SafeRectPx := FloatRectangle(
    Result.Spec.InsetLeftPx,
    Result.Spec.InsetBottomPx,
    Max(0.0, Result.Spec.WidthPx - Result.Spec.InsetLeftPx - Result.Spec.InsetRightPx),
    Max(0.0, Result.Spec.HeightPx - Result.Spec.InsetTopPx - Result.Spec.InsetBottomPx));

  RefW := Max(64.0, ARefWidth);
  RefH := Max(64.0, ARefHeight);
  Result.UiScale := Min(Result.Spec.WidthPx / RefW, Result.Spec.HeightPx / RefH);
  if Result.UiScale <= 0.0001 then
    Result.UiScale := 1.0;
  Result.UnscaledWidth := Result.Spec.WidthPx / Result.UiScale;
  Result.UnscaledHeight := Result.Spec.HeightPx / Result.UiScale;

  if not (ARoot is TCastleUserInterface) then
    Exit;

  RootContainerRect := FloatRectangle(0.0, 0.0, Result.UnscaledWidth, Result.UnscaledHeight);
  WalkUi(TCastleUserInterface(ARoot), RootContainerRect, '', true);

  { 4. Sibling control collision / overlap check }
  for I := 0 to High(Result.Boxes) do
  begin
    if Result.Boxes[I].IsBackgroundContainer or (Result.Boxes[I].ParentName = '') then
      Continue;
    for J := I + 1 to High(Result.Boxes) do
    begin
      if Result.Boxes[J].IsBackgroundContainer then
        Continue;
      if not SameText(Result.Boxes[I].ParentName, Result.Boxes[J].ParentName) then
        Continue;
      OverlapPx2 := IntersectArea(Result.Boxes[I].DeviceRect, Result.Boxes[J].DeviceRect);
      if OverlapPx2 > 4.0 then
        AddIssue(rikSiblingOverlap,
          Result.Boxes[I].ComponentName,
          Result.Boxes[J].ComponentName,
          Format('Sibling controls "%s" and "%s" overlap by %.0f px² on %s (%s).',
            [Result.Boxes[I].ComponentName, Result.Boxes[J].ComponentName,
             OverlapPx2, Result.Spec.DisplayName, Result.Spec.AspectLabel]));
    end;
  end;
end;

class function TResponsiveUiSimulator.AuditAllProfiles(const ARoot: TComponent;
  const ARefWidth, ARefHeight: Single): TResponsiveAuditSummary;
var
  P: TResponsiveDeviceProfileKind;
  I: Integer;
begin
  Result := Default(TResponsiveAuditSummary);
  for P := Low(TResponsiveDeviceProfileKind) to High(TResponsiveDeviceProfileKind) do
  begin
    Result.Results[P] := SimulateProfile(ARoot, P, ARefWidth, ARefHeight);
    for I := 0 to High(Result.Results[P].Issues) do
    begin
      Inc(Result.TotalIssueCount);
      case Result.Results[P].Issues[I].Kind of
        rikOffScreenClipped:      Inc(Result.OffScreenCount);
        rikUnsafeNotchOrHomeBar:  Inc(Result.SafeAreaCount);
        rikSiblingOverlap:        Inc(Result.OverlapCount);
        rikUndersizedTouchTarget: Inc(Result.TouchTargetCount);
      end;
    end;
  end;
end;

class function TResponsiveUiSimulator.FormatResponsiveAuditMarkdown(
  const ARoot: TComponent; const ARefWidth, ARefHeight: Single): String;
var
  Sum: TResponsiveAuditSummary;
  P: TResponsiveDeviceProfileKind;
  SB: TStringBuilder;
  I: Integer;
begin
  Sum := AuditAllProfiles(ARoot, ARefWidth, ARefHeight);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Multi-Resolution Responsive UI & Safe-Area Audit');
    SB.AppendLine;
    SB.AppendLine(Format('- **Total Violations**: `%d` (Off-Screen `%d` | Safe-Area/Notch `%d` | Sibling Overlaps `%d` | Touch < 44px `%d`)',
      [Sum.TotalIssueCount, Sum.OffScreenCount, Sum.SafeAreaCount,
       Sum.OverlapCount, Sum.TouchTargetCount]));
    SB.AppendLine;
    SB.AppendLine('| Profile | Aspect | Resolution | UI Scale | Safe Area | Issues |');
    SB.AppendLine('| :--- | :---: | :---: | :---: | :---: | :---: |');
    for P := Low(TResponsiveDeviceProfileKind) to High(TResponsiveDeviceProfileKind) do
      SB.AppendLine(Format('| **%s** | `%s` | `%dx%d` | `%.2fx` | `%.0fx%.0f` | `%d` |',
        [Sum.Results[P].Spec.DisplayName,
         Sum.Results[P].Spec.AspectLabel,
         Sum.Results[P].Spec.WidthPx, Sum.Results[P].Spec.HeightPx,
         Sum.Results[P].UiScale,
         Sum.Results[P].SafeRectPx.Width, Sum.Results[P].SafeRectPx.Height,
         Length(Sum.Results[P].Issues)]));
    SB.AppendLine;

    if Sum.TotalIssueCount > 0 then
    begin
      SB.AppendLine('## Detailed Findings');
      SB.AppendLine;
      for P := Low(TResponsiveDeviceProfileKind) to High(TResponsiveDeviceProfileKind) do
        for I := 0 to High(Sum.Results[P].Issues) do
          SB.AppendLine(Format('- **[%s — %s]** %s',
            [Sum.Results[P].Spec.DisplayName,
             ResponsiveIssueKindToLabel(Sum.Results[P].Issues[I].Kind),
             Sum.Results[P].Issues[I].Message]));
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
