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

{ CommonUI Gamepad Spatial 2D Focus Router, Activatable Modal Layer Stack,
  Input-Device Prompt Glyph Switcher & Declarative Two-Way MVVM ViewModel
  RTTI Binder Runtime (@link(TCastleCommonUiRouter), @link(TCastleMvvmBinder),
  @link(ResolveInputPromptGlyph), @link(EvaluateSpatialNavScore))
  (Phase 332 — UE 6.0+ CommonUI & UMG MVVM ViewModel Parity). }
unit CastleCommonUiMvvm;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleUIControls, CastleControls;

type
  { Input hardware family driving dynamic prompt glyph substitution. }
  TCommonInputDeviceFamily = (
    idfKeyboardMouse,
    idfXboxController,
    idfPlayStationDualSense,
    idfSteamDeckHandheld,
    idfTouchMobile
  );

  { Cardinal 2D D-Pad / stick spatial navigation direction. }
  TCommonNavDirection = (
    cndUp,
    cndDown,
    cndLeft,
    cndRight
  );

  { Pushed modal layer entry in @link(TCastleCommonUiRouter)'s activatable stack. }
  TCommonModalLayerEntry = record
    LayerRoot: TCastleUserInterface;
    SavedPriorFocus: TCastleUserInterface;
  end;

  { Prompt template entry mapping a @link(TCastleLabel) to a template containing
    tokens such as @code(Prompt:Confirm), @code(Prompt:Back), @code(Prompt:Context), etc. }
  TCommonPromptTemplate = record
    TargetLabelName: String;
    TemplateText: String;
  end;
  TCommonPromptTemplateArray = array of TCommonPromptTemplate;

  { CommonUI-style spatial 2D focus router, modal activatable widget stack &
    automatic input-device glyph switcher (@link(TCastleComponent)). }
  TCastleCommonUiRouter = class(TCastleComponent)
  public
    const
      DefaultMaxConeHalfAngleDeg = 65.0;
      DefaultCrossAxisPenalty = 2.60;
  strict private
    FActiveDevice: TCommonInputDeviceFamily;
    FMaxConeHalfAngleDeg: Single;
    FCrossAxisPenalty: Single;
    FWrapAroundEdges: Boolean;
    FRootUi: TCastleUserInterface;
    FFocusedControl: TCastleUserInterface;
    FModalStack: array of TCommonModalLayerEntry;
    FPromptTemplates: TCommonPromptTemplateArray;

    procedure SetActiveDevice(const Value: TCommonInputDeviceFamily);
    procedure SetRootUi(const Value: TCastleUserInterface);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function ActiveScopeRoot: TCastleUserInterface;
    function FindComponentAnywhere(const AName: String;
      const DesignOwner: TComponent): TComponent;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function DeviceDisplayName(const ADev: TCommonInputDeviceFamily): String; static;
    class function ComputeControlCenter2D(const AControl: TCastleUserInterface): TVector2; static;
    class function IsFocusableWidget(const AControl: TCastleUserInterface): Boolean; static;

    procedure CollectFocusableControls(out OutControls: array of TCastleUserInterface;
      out OutCount: Integer);
    function FocusableCountInActiveLayer: Integer;
    procedure SetFocusedControl(const AControl: TCastleUserInterface);

    { Move focus to the optimal neighbor in @code(ADir) within the active modal
      layer using UE CommonUI's weighted cone metric. Returns @true if focus moved. }
    function NavigateDirection(const ADir: TCommonNavDirection): Boolean;

    { Push an activatable modal layer (e.g. confirmation popup), isolating D-Pad
      navigation inside @code(ALayerRoot) and remembering prior focus. }
    procedure PushActivatableLayer(const ALayerRoot: TCastleUserInterface);

    { Pop the top modal layer, hiding it (@code(Exists := False)) and restoring
      exact focus to the underlying layer's previously focused control. }
    function PopActivatableLayer: Boolean;
    function ModalStackDepth: Integer;

    procedure ClearPromptTemplates;
    procedure RegisterPromptTemplate(const ALabelName, ATemplateText: String);
    procedure RefreshPromptLabels(const DesignOwner: TComponent = nil);

    function RouterSummaryBadge: String;

    property RootUi: TCastleUserInterface read FRootUi write SetRootUi;
    property FocusedControl: TCastleUserInterface read FFocusedControl;
  published
    property ActiveDevice: TCommonInputDeviceFamily
      read FActiveDevice write SetActiveDevice default idfKeyboardMouse;
    property MaxConeHalfAngleDeg: Single
      read FMaxConeHalfAngleDeg write FMaxConeHalfAngleDeg {$ifdef FPC}default DefaultMaxConeHalfAngleDeg{$endif};
    property CrossAxisPenalty: Single
      read FCrossAxisPenalty write FCrossAxisPenalty {$ifdef FPC}default DefaultCrossAxisPenalty{$endif};
    property WrapAroundEdges: Boolean
      read FWrapAroundEdges write FWrapAroundEdges default False;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Declarative ViewModel-to-Component RTTI property binding rule. }
  TMvvmPropertyBinding = record
    ViewModelKey: String;
    TargetComponentName: String;
    TargetPropertyName: String;
    FormatPattern: String; // Optional Format() string e.g. 'HP: %.0f%%' for String targets
    ScaleFactor: Single;   // Multiplier applied to Float ViewModel values (default 1.0)
    TwoWay: Boolean;
    Enabled: Boolean;
  end;
  TMvvmPropertyBindingArray = array of TMvvmPropertyBinding;

  { UMG ViewModel-style observable key/value store & declarative two-way RTTI
    property binder (@link(TCastleComponent)). }
  TCastleMvvmBinder = class(TCastleComponent)
  strict private
    FValues: TStringList;
    FBindings: TMvvmPropertyBindingArray;
    FSyncCounter: Integer;

    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    function ResolveNamedComponent(const RootComp, DesignOwner: TComponent;
      const AName: String): TComponent;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure SetFloat(const AKey: String; const AValue: Single);
    function GetFloat(const AKey: String; const ADefault: Single = 0.0): Single;
    procedure SetInt(const AKey: String; const AValue: Integer);
    function GetInt(const AKey: String; const ADefault: Integer = 0): Integer;
    procedure SetBool(const AKey: String; const AValue: Boolean);
    function GetBool(const AKey: String; const ADefault: Boolean = False): Boolean;
    procedure SetStr(const AKey, AValue: String);
    function GetStr(const AKey: String; const ADefault: String = ''): String;

    procedure ClearBindings;
    function AddBinding(const AViewModelKey, ATargetCompName, ATargetPropName: String;
      const AFormatPattern: String = ''; const AScaleFactor: Single = 1.0;
      const ATwoWay: Boolean = False): Integer;
    function BindingCount: Integer;
    function GetBinding(const Index: Integer): TMvvmPropertyBinding;

    { Push all enabled ViewModel bindings onto target components via RTTI. }
    function PushViewModelToUi(const RootComp, DesignOwner: TComponent): Integer;

    { Pull all enabled @code(TwoWay = True) UI component RTTI properties back
      into the ViewModel store. }
    function PullUiToViewModel(const RootComp, DesignOwner: TComponent): Integer;

    function MvvmSummaryBadge: String;

    property SyncCounter: Integer read FSyncCounter;
  published
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Map a semantic UI action (@code('Confirm'), @code('Back'), @code('Context'),
  @code('TabPrev'), @code('TabNext'), @code('Inventory')) to a device glyph string. }
function ResolveInputPromptGlyph(const ADevice: TCommonInputDeviceFamily;
  const AActionSemantic: String): String;

{ Evaluate UE CommonUI's directional cone navigation cost from @code(Origin2D)
  to @code(Candidate2D). Returns @code(< 0) if @code(Candidate2D) lies outside
  @code(MaxConeHalfAngleDeg); otherwise returns @code(PrimaryDist + CrossPenalty * |PerpDist|)
  (lower positive score = better match). }
function EvaluateSpatialNavScore(const Origin2D, Candidate2D: TVector2;
  const ADir: TCommonNavDirection; const MaxConeHalfAngleDeg, CrossPenalty: Single): Single;

implementation

uses
  Math, TypInfo, FpJson, JsonParser,
  CastleUtils, CastleRectangles, CastleComponentSerialize;

function ResolveInputPromptGlyph(const ADevice: TCommonInputDeviceFamily;
  const AActionSemantic: String): String;
begin
  if SameText(AActionSemantic, 'Confirm') then
    case ADevice of
      idfKeyboardMouse:        Exit('[Enter]');
      idfXboxController:       Exit('(A)');
      idfPlayStationDualSense: Exit('(Cross)');
      idfSteamDeckHandheld:    Exit('(A)');
      idfTouchMobile:          Exit('[Tap]');
    end
  else if SameText(AActionSemantic, 'Back') then
    case ADevice of
      idfKeyboardMouse:        Exit('[Esc]');
      idfXboxController:       Exit('(B)');
      idfPlayStationDualSense: Exit('(Circle)');
      idfSteamDeckHandheld:    Exit('(B)');
      idfTouchMobile:          Exit('[Back]');
    end
  else if SameText(AActionSemantic, 'Context') then
    case ADevice of
      idfKeyboardMouse:        Exit('[F]');
      idfXboxController:       Exit('(X)');
      idfPlayStationDualSense: Exit('(Square)');
      idfSteamDeckHandheld:    Exit('(X)');
      idfTouchMobile:          Exit('[Hold]');
    end
  else if SameText(AActionSemantic, 'TabPrev') then
    case ADevice of
      idfKeyboardMouse:        Exit('[Q]');
      idfXboxController:       Exit('[LB]');
      idfPlayStationDualSense: Exit('[L1]');
      idfSteamDeckHandheld:    Exit('[L1]');
      idfTouchMobile:          Exit('[<]');
    end
  else if SameText(AActionSemantic, 'TabNext') then
    case ADevice of
      idfKeyboardMouse:        Exit('[E]');
      idfXboxController:       Exit('[RB]');
      idfPlayStationDualSense: Exit('[R1]');
      idfSteamDeckHandheld:    Exit('[R1]');
      idfTouchMobile:          Exit('[>]');
    end;
  Result := '[' + AActionSemantic + ']';
end;

function ExpandPromptTokens(const ATemplate: String;
  const ADevice: TCommonInputDeviceFamily): String;
const
  Actions: array [0..4] of String = ('Confirm', 'Back', 'Context', 'TabPrev', 'TabNext');
var
  I: Integer;
begin
  Result := ATemplate;
  for I := 0 to High(Actions) do
    Result := StringReplace(Result, '{Prompt:' + Actions[I] + '}',
      ResolveInputPromptGlyph(ADevice, Actions[I]), [rfReplaceAll, rfIgnoreCase]);
end;

function EvaluateSpatialNavScore(const Origin2D, Candidate2D: TVector2;
  const ADir: TCommonNavDirection;
  const MaxConeHalfAngleDeg, CrossPenalty: Single): Single;
var
  Delta, DirVec, UnitDelta: TVector2;
  Len, PrimaryProj, PerpDist, CosLimit: Single;
begin
  Delta := Candidate2D - Origin2D;
  Len := Delta.Length;
  if Len <= 0.5 then
    Exit(-1.0);

  case ADir of
    cndUp:    DirVec := Vector2(0.0, 1.0);
    cndDown:  DirVec := Vector2(0.0, -1.0);
    cndLeft:  DirVec := Vector2(-1.0, 0.0);
    cndRight: DirVec := Vector2(1.0, 0.0);
  end;

  PrimaryProj := Delta.X * DirVec.X + Delta.Y * DirVec.Y;
  if PrimaryProj <= 0.5 then
    Exit(-1.0);

  UnitDelta := Delta / Len;
  CosLimit := Cos(DegToRad(Clamped(MaxConeHalfAngleDeg, 5.0, 89.0)));
  if (UnitDelta.X * DirVec.X + UnitDelta.Y * DirVec.Y) < CosLimit then
    Exit(-1.0);

  PerpDist := Abs(Delta.X * (-DirVec.Y) + Delta.Y * DirVec.X);
  Result := PrimaryProj + Max(0.0, CrossPenalty) * PerpDist;
end;

{ TCastleCommonUiRouter ------------------------------------------------------ }

constructor TCastleCommonUiRouter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActiveDevice := idfKeyboardMouse;
  FMaxConeHalfAngleDeg := DefaultMaxConeHalfAngleDeg;
  FCrossAxisPenalty := DefaultCrossAxisPenalty;
  FWrapAroundEdges := False;
end;

procedure TCastleCommonUiRouter.Notification(
  AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FRootUi then
      FRootUi := nil;
    if AComponent = FFocusedControl then
      FFocusedControl := nil;
    for I := 0 to High(FModalStack) do
    begin
      if FModalStack[I].LayerRoot = AComponent then
        FModalStack[I].LayerRoot := nil;
      if FModalStack[I].SavedPriorFocus = AComponent then
        FModalStack[I].SavedPriorFocus := nil;
    end;
  end;
end;

function TCastleCommonUiRouter.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ActiveDevice', 'MaxConeHalfAngleDeg', 'CrossAxisPenalty',
       'WrapAroundEdges', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleCommonUiRouter.DeviceDisplayName(
  const ADev: TCommonInputDeviceFamily): String;
begin
  case ADev of
    idfKeyboardMouse:        Result := 'Keyboard & Mouse';
    idfXboxController:       Result := 'Xbox Wireless Controller';
    idfPlayStationDualSense: Result := 'PlayStation DualSense';
    idfSteamDeckHandheld:    Result := 'Steam Deck Handheld';
    idfTouchMobile:          Result := 'Mobile Touch';
  end;
end;

class function TCastleCommonUiRouter.ComputeControlCenter2D(
  const AControl: TCastleUserInterface): TVector2;
var
  Cur: TCastleUserInterface;
  R: TFloatRectangle;
begin
  if AControl = nil then
    Exit(TVector2.Zero);
  if AControl.Container <> nil then
  begin
    R := AControl.RenderRect;
    if not R.IsEmpty then
      Exit(R.Center);
  end;

  Result := Vector2(Max(16.0, AControl.Width) * 0.5, Max(16.0, AControl.Height) * 0.5);
  Cur := AControl;
  while Cur <> nil do
  begin
    Result := Result + Cur.Translation;
    Cur := Cur.Parent;
  end;
end;

class function TCastleCommonUiRouter.IsFocusableWidget(
  const AControl: TCastleUserInterface): Boolean;
begin
  Result := (AControl <> nil) and AControl.Exists and
    (not (csTransient in AControl.ComponentStyle)) and
    ((AControl is TCastleButton) or (AControl is TCastleCheckbox) or
     (AControl is TCastleFloatSlider) or (AControl is TCastleIntegerSlider) or
     (AControl is TCastleEdit));
end;

procedure TCastleCommonUiRouter.SetActiveDevice(
  const Value: TCommonInputDeviceFamily);
begin
  if FActiveDevice = Value then Exit;
  FActiveDevice := Value;
  RefreshPromptLabels(Owner);
end;

procedure TCastleCommonUiRouter.SetRootUi(const Value: TCastleUserInterface);
begin
  if FRootUi = Value then Exit;
  if FRootUi <> nil then
    FRootUi.RemoveFreeNotification(Self);
  FRootUi := Value;
  if FRootUi <> nil then
    FRootUi.FreeNotification(Self);
end;

function TCastleCommonUiRouter.ActiveScopeRoot: TCastleUserInterface;
var
  I: Integer;
begin
  for I := High(FModalStack) downto 0 do
    if (FModalStack[I].LayerRoot <> nil) and FModalStack[I].LayerRoot.Exists then
      Exit(FModalStack[I].LayerRoot);
  Result := FRootUi;
end;

procedure TCastleCommonUiRouter.CollectFocusableControls(
  out OutControls: array of TCastleUserInterface; out OutCount: Integer);
var
  Scope: TCastleUserInterface;
  MaxCap: Integer;

  procedure WalkUi(const U: TCastleUserInterface; const InsideBlockedModal: Boolean);
  var
    K, M: Integer;
    IsOtherModal: Boolean;
  begin
    if (U = nil) or (not U.Exists) or (csTransient in U.ComponentStyle) then
      Exit;

    { When at RootUi (ModalStack empty), skip hidden modal roots naturally via Exists=False;
      if another modal root is somehow visible, only traverse ActiveScopeRoot! }
    IsOtherModal := False;
    for M := 0 to High(FModalStack) do
      if (FModalStack[M].LayerRoot = U) and (U <> Scope) then
        IsOtherModal := True;
    if IsOtherModal or InsideBlockedModal then
      Exit;

    if IsFocusableWidget(U) and (OutCount < MaxCap) then
    begin
      OutControls[OutCount] := U;
      Inc(OutCount);
    end;

    for K := 0 to U.ControlsCount - 1 do
      WalkUi(U.Controls[K], False);
  end;

begin
  OutCount := 0;
  MaxCap := Length(OutControls);
  Scope := ActiveScopeRoot;
  if Scope <> nil then
    WalkUi(Scope, False);
end;

function TCastleCommonUiRouter.FocusableCountInActiveLayer: Integer;
var
  Buf: array [0..255] of TCastleUserInterface;
begin
  CollectFocusableControls(Buf, Result);
end;

procedure TCastleCommonUiRouter.SetFocusedControl(
  const AControl: TCastleUserInterface);
begin
  if FFocusedControl = AControl then Exit;
  if FFocusedControl <> nil then
    FFocusedControl.RemoveFreeNotification(Self);
  FFocusedControl := AControl;
  if FFocusedControl <> nil then
    FFocusedControl.FreeNotification(Self);
end;

function TCastleCommonUiRouter.NavigateDirection(
  const ADir: TCommonNavDirection): Boolean;
var
  Candidates: array [0..255] of TCastleUserInterface;
  Count, I, BestIdx: Integer;
  OriginPos, CandPos: TVector2;
  Score, BestScore: Single;
begin
  Result := False;
  CollectFocusableControls(Candidates, Count);
  if Count = 0 then
    Exit;

  if FFocusedControl = nil then
  begin
    SetFocusedControl(Candidates[0]);
    Exit(True);
  end;

  OriginPos := ComputeControlCenter2D(FFocusedControl);
  BestIdx := -1;
  BestScore := 1e30;

  for I := 0 to Count - 1 do
    if Candidates[I] <> FFocusedControl then
    begin
      CandPos := ComputeControlCenter2D(Candidates[I]);
      Score := EvaluateSpatialNavScore(
        OriginPos, CandPos, ADir, FMaxConeHalfAngleDeg, FCrossAxisPenalty);
      if (Score >= 0.0) and (Score < BestScore) then
      begin
        BestScore := Score;
        BestIdx := I;
      end;
    end;

  if BestIdx >= 0 then
  begin
    SetFocusedControl(Candidates[BestIdx]);
    Result := True;
  end;
end;

procedure TCastleCommonUiRouter.PushActivatableLayer(
  const ALayerRoot: TCastleUserInterface);
var
  N, Count: Integer;
  Candidates: array [0..255] of TCastleUserInterface;
begin
  if ALayerRoot = nil then Exit;
  ALayerRoot.Exists := True;
  ALayerRoot.FreeNotification(Self);

  N := Length(FModalStack);
  SetLength(FModalStack, N + 1);
  FModalStack[N].LayerRoot := ALayerRoot;
  FModalStack[N].SavedPriorFocus := FFocusedControl;

  CollectFocusableControls(Candidates, Count);
  if Count > 0 then
    SetFocusedControl(Candidates[0])
  else
    SetFocusedControl(nil);
end;

function TCastleCommonUiRouter.PopActivatableLayer: Boolean;
var
  N: Integer;
  TopEntry: TCommonModalLayerEntry;
begin
  N := Length(FModalStack);
  if N = 0 then
    Exit(False);
  TopEntry := FModalStack[N - 1];
  SetLength(FModalStack, N - 1);
  if TopEntry.LayerRoot <> nil then
    TopEntry.LayerRoot.Exists := False;
  SetFocusedControl(TopEntry.SavedPriorFocus);
  Result := True;
end;

function TCastleCommonUiRouter.ModalStackDepth: Integer;
begin
  Result := Length(FModalStack);
end;

procedure TCastleCommonUiRouter.ClearPromptTemplates;
begin
  FPromptTemplates := nil;
end;

procedure TCastleCommonUiRouter.RegisterPromptTemplate(
  const ALabelName, ATemplateText: String);
var
  I, N: Integer;
begin
  for I := 0 to High(FPromptTemplates) do
    if SameText(FPromptTemplates[I].TargetLabelName, ALabelName) then
    begin
      FPromptTemplates[I].TemplateText := ATemplateText;
      RefreshPromptLabels(Owner);
      Exit;
    end;
  N := Length(FPromptTemplates);
  SetLength(FPromptTemplates, N + 1);
  FPromptTemplates[N].TargetLabelName := ALabelName;
  FPromptTemplates[N].TemplateText := ATemplateText;
  RefreshPromptLabels(Owner);
end;

function TCastleCommonUiRouter.FindComponentAnywhere(
  const AName: String; const DesignOwner: TComponent): TComponent;

  function WalkUi(const U: TCastleUserInterface): TComponent;
  var
    K: Integer;
  begin
    Result := nil;
    if U = nil then Exit;
    if SameText(U.Name, AName) then Exit(U);
    for K := 0 to U.ControlsCount - 1 do
    begin
      Result := WalkUi(U.Controls[K]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := nil;
  if AName = '' then Exit;
  if DesignOwner <> nil then
  begin
    Result := DesignOwner.FindComponent(AName);
    if Result <> nil then Exit;
  end;
  if Owner <> nil then
  begin
    Result := Owner.FindComponent(AName);
    if Result <> nil then Exit;
  end;
  Result := WalkUi(FRootUi);
end;

procedure TCastleCommonUiRouter.RefreshPromptLabels(const DesignOwner: TComponent);
var
  I: Integer;
  C: TComponent;
begin
  for I := 0 to High(FPromptTemplates) do
  begin
    C := FindComponentAnywhere(FPromptTemplates[I].TargetLabelName, DesignOwner);
    if C is TCastleLabel then
      TCastleLabel(C).Caption := ExpandPromptTokens(
        FPromptTemplates[I].TemplateText, FActiveDevice);
  end;
end;

function TCastleCommonUiRouter.GetConfigJson: String;
var
  Root, PObj: TJSONObject;
  PArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('device', Ord(FActiveDevice));
    PArr := TJSONArray.Create;
    for I := 0 to High(FPromptTemplates) do
    begin
      PObj := TJSONObject.Create;
      PObj.Add('label', FPromptTemplates[I].TargetLabelName);
      PObj.Add('tpl', FPromptTemplates[I].TemplateText);
      PArr.Add(PObj);
    end;
    Root.Add('prompts', PArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleCommonUiRouter.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, PObj: TJSONObject;
  PArr: TJSONArray;
  I, DevOrd: Integer;
begin
  if Trim(Value) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      DevOrd := Root.Get('device', Ord(FActiveDevice));
      if (DevOrd >= Ord(Low(TCommonInputDeviceFamily))) and
         (DevOrd <= Ord(High(TCommonInputDeviceFamily))) then
        FActiveDevice := TCommonInputDeviceFamily(DevOrd);
      if Root.Find('prompts') is TJSONArray then
      begin
        ClearPromptTemplates;
        PArr := TJSONArray(Root.Find('prompts'));
        for I := 0 to PArr.Count - 1 do
          if PArr.Items[I] is TJSONObject then
          begin
            PObj := TJSONObject(PArr.Items[I]);
            RegisterPromptTemplate(PObj.Get('label', ''), PObj.Get('tpl', ''));
          end;
      end;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleCommonUiRouter.RouterSummaryBadge: String;
var
  FocusName: String;
begin
  if FFocusedControl <> nil then
    FocusName := FFocusedControl.Name
  else
    FocusName := 'none';
  Result := Format('[CommonUI:%s Focus=%s Modals=%d]',
    [DeviceDisplayName(FActiveDevice), FocusName, Length(FModalStack)]);
end;

{ TCastleMvvmBinder ---------------------------------------------------------- }

constructor TCastleMvvmBinder.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FValues := TStringList.Create;
  FValues.NameValueSeparator := '=';
  FSyncCounter := 0;
end;

destructor TCastleMvvmBinder.Destroy;
begin
  FreeAndNil(FValues);
  inherited;
end;

function TCastleMvvmBinder.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, ['ConfigJson']) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMvvmBinder.SetFloat(const AKey: String; const AValue: Single);
begin
  FValues.Values[Trim(AKey)] := FloatToStrDot(AValue);
end;

function TCastleMvvmBinder.GetFloat(const AKey: String;
  const ADefault: Single): Single;
var
  Idx: Integer;
begin
  Idx := FValues.IndexOfName(Trim(AKey));
  if Idx >= 0 then
    Result := StrToFloatDefDot(FValues.ValueFromIndex[Idx], ADefault)
  else
    Result := ADefault;
end;

procedure TCastleMvvmBinder.SetInt(const AKey: String; const AValue: Integer);
begin
  FValues.Values[Trim(AKey)] := IntToStr(AValue);
end;

function TCastleMvvmBinder.GetInt(const AKey: String;
  const ADefault: Integer): Integer;
var
  Idx: Integer;
begin
  Idx := FValues.IndexOfName(Trim(AKey));
  if Idx >= 0 then
    Result := StrToIntDef(FValues.ValueFromIndex[Idx], ADefault)
  else
    Result := ADefault;
end;

procedure TCastleMvvmBinder.SetBool(const AKey: String; const AValue: Boolean);
begin
  if AValue then
    FValues.Values[Trim(AKey)] := '1'
  else
    FValues.Values[Trim(AKey)] := '0';
end;

function TCastleMvvmBinder.GetBool(const AKey: String;
  const ADefault: Boolean): Boolean;
var
  S: String;
  Idx: Integer;
begin
  Idx := FValues.IndexOfName(Trim(AKey));
  if Idx < 0 then Exit(ADefault);
  S := LowerCase(Trim(FValues.ValueFromIndex[Idx]));
  Result := (S = '1') or (S = 'true') or (S = 'yes');
end;

procedure TCastleMvvmBinder.SetStr(const AKey, AValue: String);
begin
  FValues.Values[Trim(AKey)] := AValue;
end;

function TCastleMvvmBinder.GetStr(const AKey, ADefault: String): String;
var
  Idx: Integer;
begin
  Idx := FValues.IndexOfName(Trim(AKey));
  if Idx >= 0 then
    Result := FValues.ValueFromIndex[Idx]
  else
    Result := ADefault;
end;

procedure TCastleMvvmBinder.ClearBindings;
begin
  FBindings := nil;
end;

function TCastleMvvmBinder.AddBinding(const AViewModelKey, ATargetCompName,
  ATargetPropName, AFormatPattern: String; const AScaleFactor: Single;
  const ATwoWay: Boolean): Integer;
begin
  Result := Length(FBindings);
  SetLength(FBindings, Result + 1);
  FBindings[Result].ViewModelKey := Trim(AViewModelKey);
  FBindings[Result].TargetComponentName := Trim(ATargetCompName);
  FBindings[Result].TargetPropertyName := Trim(ATargetPropName);
  FBindings[Result].FormatPattern := AFormatPattern;
  if Abs(AScaleFactor) < 1e-8 then
    FBindings[Result].ScaleFactor := 1.0
  else
    FBindings[Result].ScaleFactor := AScaleFactor;
  FBindings[Result].TwoWay := ATwoWay;
  FBindings[Result].Enabled := True;
end;

function TCastleMvvmBinder.BindingCount: Integer;
begin
  Result := Length(FBindings);
end;

function TCastleMvvmBinder.GetBinding(const Index: Integer): TMvvmPropertyBinding;
begin
  if (Index >= 0) and (Index < Length(FBindings)) then
    Result := FBindings[Index]
  else
    Result := Default(TMvvmPropertyBinding);
end;

function TCastleMvvmBinder.ResolveNamedComponent(
  const RootComp, DesignOwner: TComponent; const AName: String): TComponent;

  function Walk(const C: TComponent): TComponent;
  var
    K: Integer;
    UI: TCastleUserInterface;
  begin
    Result := nil;
    if C = nil then Exit;
    if SameText(C.Name, AName) then Exit(C);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for K := 0 to UI.ControlsCount - 1 do
      begin
        Result := Walk(UI.Controls[K]);
        if Result <> nil then Exit;
      end;
    end;
  end;

begin
  Result := nil;
  if AName = '' then Exit;
  if DesignOwner <> nil then
  begin
    Result := DesignOwner.FindComponent(AName);
    if Result <> nil then Exit;
  end;
  if Owner <> nil then
  begin
    Result := Owner.FindComponent(AName);
    if Result <> nil then Exit;
  end;
  Result := Walk(RootComp);
end;

function TCastleMvvmBinder.PushViewModelToUi(
  const RootComp, DesignOwner: TComponent): Integer;
var
  I: Integer;
  Target: TComponent;
  PInfo: PPropInfo;
  FVal: Single;
  RawS, FormattedS: String;
begin
  Result := 0;
  for I := 0 to High(FBindings) do
  begin
    if not FBindings[I].Enabled then Continue;
    Target := ResolveNamedComponent(RootComp, DesignOwner, FBindings[I].TargetComponentName);
    if Target = nil then Continue;
    PInfo := GetPropInfo(Target, FBindings[I].TargetPropertyName);
    if PInfo = nil then Continue;

    case PInfo^.PropType^.Kind of
      tkFloat:
        begin
          FVal := GetFloat(FBindings[I].ViewModelKey, 0.0) * FBindings[I].ScaleFactor;
          SetFloatProp(Target, PInfo, FVal);
          Inc(Result);
        end;
      tkInteger, tkInt64:
        begin
          SetOrdProp(Target, PInfo, Round(GetFloat(FBindings[I].ViewModelKey, 0.0) * FBindings[I].ScaleFactor));
          Inc(Result);
        end;
      tkBool:
        begin
          SetOrdProp(Target, PInfo, Ord(GetBool(FBindings[I].ViewModelKey, False)));
          Inc(Result);
        end;
      tkAString, tkSString, tkLString, tkUString:
        begin
          RawS := GetStr(FBindings[I].ViewModelKey, '');
          if FBindings[I].FormatPattern <> '' then
          begin
            FVal := GetFloat(FBindings[I].ViewModelKey, 0.0) * FBindings[I].ScaleFactor;
            FormattedS := Format(FBindings[I].FormatPattern, [FVal]);
          end else
            FormattedS := RawS;
          SetStrProp(Target, PInfo, FormattedS);
          Inc(Result);
        end;
    end;
  end;
  Inc(FSyncCounter);
end;

function TCastleMvvmBinder.PullUiToViewModel(
  const RootComp, DesignOwner: TComponent): Integer;
var
  I: Integer;
  Target: TComponent;
  PInfo: PPropInfo;
  ScaleDiv: Single;
begin
  Result := 0;
  for I := 0 to High(FBindings) do
  begin
    if (not FBindings[I].Enabled) or (not FBindings[I].TwoWay) then Continue;
    Target := ResolveNamedComponent(RootComp, DesignOwner, FBindings[I].TargetComponentName);
    if Target = nil then Continue;
    PInfo := GetPropInfo(Target, FBindings[I].TargetPropertyName);
    if PInfo = nil then Continue;

    ScaleDiv := FBindings[I].ScaleFactor;
    if Abs(ScaleDiv) < 1e-8 then ScaleDiv := 1.0;

    case PInfo^.PropType^.Kind of
      tkFloat:
        begin
          SetFloat(FBindings[I].ViewModelKey, GetFloatProp(Target, PInfo) / ScaleDiv);
          Inc(Result);
        end;
      tkInteger, tkInt64:
        begin
          SetInt(FBindings[I].ViewModelKey, Round(GetOrdProp(Target, PInfo) / ScaleDiv));
          Inc(Result);
        end;
      tkBool:
        begin
          SetBool(FBindings[I].ViewModelKey, GetOrdProp(Target, PInfo) <> 0);
          Inc(Result);
        end;
      tkAString, tkSString, tkLString, tkUString:
        begin
          SetStr(FBindings[I].ViewModelKey, GetStrProp(Target, PInfo));
          Inc(Result);
        end;
    end;
  end;
  Inc(FSyncCounter);
end;

function TCastleMvvmBinder.GetConfigJson: String;
var
  Root, ValObj, BObj: TJSONObject;
  BArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    ValObj := TJSONObject.Create;
    for I := 0 to FValues.Count - 1 do
      ValObj.Add(FValues.Names[I], FValues.ValueFromIndex[I]);
    Root.Add('values', ValObj);

    BArr := TJSONArray.Create;
    for I := 0 to High(FBindings) do
    begin
      BObj := TJSONObject.Create;
      BObj.Add('key', FBindings[I].ViewModelKey);
      BObj.Add('comp', FBindings[I].TargetComponentName);
      BObj.Add('prop', FBindings[I].TargetPropertyName);
      BObj.Add('fmt', FBindings[I].FormatPattern);
      BObj.Add('scale', FBindings[I].ScaleFactor);
      BObj.Add('twoway', FBindings[I].TwoWay);
      BObj.Add('en', FBindings[I].Enabled);
      BArr.Add(BObj);
    end;
    Root.Add('bindings', BArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMvvmBinder.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, ValObj, BObj: TJSONObject;
  BArr: TJSONArray;
  I: Integer;
begin
  if Trim(Value) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FValues.Clear;
      if Root.Find('values') is TJSONObject then
      begin
        ValObj := TJSONObject(Root.Find('values'));
        for I := 0 to ValObj.Count - 1 do
          FValues.Values[ValObj.Names[I]] := ValObj.Items[I].AsString;
      end;

      ClearBindings;
      if Root.Find('bindings') is TJSONArray then
      begin
        BArr := TJSONArray(Root.Find('bindings'));
        for I := 0 to BArr.Count - 1 do
          if BArr.Items[I] is TJSONObject then
          begin
            BObj := TJSONObject(BArr.Items[I]);
            AddBinding(
              BObj.Get('key', ''),
              BObj.Get('comp', ''),
              BObj.Get('prop', ''),
              BObj.Get('fmt', ''),
              BObj.Get('scale', 1.0),
              BObj.Get('twoway', False));
            FBindings[High(FBindings)].Enabled := BObj.Get('en', True);
          end;
      end;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleMvvmBinder.MvvmSummaryBadge: String;
begin
  Result := Format('[MVVM:%d vars %d bindings Sync#%d]',
    [FValues.Count, Length(FBindings), FSyncCounter]);
end;

initialization
  RegisterSerializableComponent(TCastleCommonUiRouter,
    ['User Interface', 'CommonUI Gamepad Spatial Router & Glyph Switcher']);
  RegisterSerializableComponent(TCastleMvvmBinder,
    ['User Interface', 'MVVM ViewModel & Two-Way RTTI Binder']);
end.
