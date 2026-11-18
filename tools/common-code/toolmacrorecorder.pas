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

{ Editor Action Macro Recorder & Parameterized Batch Transform Replay (Phase 376).
  Records multi-step scene editing operations (filtered translation offsets,
  non-uniform scale multipliers, integer tag assignment, idempotent prefix
  renaming, and primitive RGB tinting), exports/imports portable JSON macros,
  and replays them deterministically across live CGE hierarchies. }
unit ToolMacroRecorder;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions,
  CastleViewport, CastleColors;

type
  TMacroStepKind = (
    mskAddTranslate,
    mskMultiplyScale,
    mskSetTag,
    mskRenamePrefix,
    mskSetBoxColorRgb
  );

  TEditorMacroStep = record
    Kind: TMacroStepKind;
    TargetFilter: String;
    VecParam: TVector3;
    ScalarParam: Single;
    StrParam: String;
  end;

  TEditorMacroRecorder = class
  private
    FMacroName: String;
    FIsRecording: Boolean;
    FSteps: array of TEditorMacroStep;
    FReplayCount: Integer;
    FLastAffectedCount: Integer;
  public
    constructor Create;
    class function SharedRecorder: TEditorMacroRecorder;

    class function StepKindToString(const AKind: TMacroStepKind): String;
    class function StringToStepKind(const S: String; out AKind: TMacroStepKind): Boolean;

    procedure StartRecording(const AMacroName: String = 'SceneBatchMacro');
    procedure StopRecording;
    procedure ClearSteps;

    function RecordStep(const AKind: TMacroStepKind; const ATargetFilter: String;
      const AVecParam: TVector3; const AScalarParam: Single = 0.0;
      const AStrParam: String = ''): Integer;

    { Replay all recorded macro steps across matching non-transient TCastleTransform nodes. }
    function ReplayMacro(const Root: TComponent; const DeltaMultiplier: Single = 1.0): Integer;

    function ExportMacroJson: String;
    function ImportMacroJson(const JsonText: String): Boolean;

    function StepCount: Integer;
    function GetStep(const Index: Integer): TEditorMacroStep;

    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function SpawnCratePillarsDemo(const Root, DesignOwner: TComponent): Integer;
    function GenerateMacroReport(const Root: TComponent): String;

    property MacroName: String read FMacroName write FMacroName;
    property IsRecording: Boolean read FIsRecording;
    property ReplayCount: Integer read FReplayCount;
    property LastAffectedCount: Integer read FLastAffectedCount;
  end;

implementation

uses fpjson, jsonparser, CastleUtils, ToolStudioHub;

var
  GSharedMacroRecorder: TEditorMacroRecorder;

constructor TEditorMacroRecorder.Create;
begin
  inherited Create;
  FMacroName := 'SceneBatchMacro';
  FIsRecording := False;
  FSteps := nil;
  FReplayCount := 0;
  FLastAffectedCount := 0;
end;

class function TEditorMacroRecorder.SharedRecorder: TEditorMacroRecorder;
begin
  if GSharedMacroRecorder = nil then
    GSharedMacroRecorder := TEditorMacroRecorder.Create;
  Result := GSharedMacroRecorder;
end;

class function TEditorMacroRecorder.StepKindToString(const AKind: TMacroStepKind): String;
begin
  case AKind of
    mskAddTranslate: Result := 'add_translate';
    mskMultiplyScale: Result := 'multiply_scale';
    mskSetTag: Result := 'set_tag';
    mskRenamePrefix: Result := 'rename_prefix';
    mskSetBoxColorRgb: Result := 'set_color_rgb';
  end;
end;

class function TEditorMacroRecorder.StringToStepKind(const S: String;
  out AKind: TMacroStepKind): Boolean;
var
  Norm: String;
begin
  Norm := LowerCase(Trim(S));
  Result := True;
  if Norm = 'add_translate' then AKind := mskAddTranslate
  else if Norm = 'multiply_scale' then AKind := mskMultiplyScale
  else if Norm = 'set_tag' then AKind := mskSetTag
  else if Norm = 'rename_prefix' then AKind := mskRenamePrefix
  else if (Norm = 'set_color_rgb') or (Norm = 'set_box_color_rgb') then AKind := mskSetBoxColorRgb
  else
  begin
    AKind := mskAddTranslate;
    Result := False;
  end;
end;

procedure TEditorMacroRecorder.StartRecording(const AMacroName: String);
begin
  if Trim(AMacroName) <> '' then
    FMacroName := Trim(AMacroName);
  FIsRecording := True;
end;

procedure TEditorMacroRecorder.StopRecording;
begin
  FIsRecording := False;
end;

procedure TEditorMacroRecorder.ClearSteps;
begin
  FSteps := nil;
  FLastAffectedCount := 0;
end;

function TEditorMacroRecorder.RecordStep(const AKind: TMacroStepKind;
  const ATargetFilter: String; const AVecParam: TVector3;
  const AScalarParam: Single; const AStrParam: String): Integer;
var
  Idx: Integer;
begin
  Idx := Length(FSteps);
  SetLength(FSteps, Idx + 1);
  FSteps[Idx].Kind := AKind;
  FSteps[Idx].TargetFilter := Trim(ATargetFilter);
  FSteps[Idx].VecParam := AVecParam;
  FSteps[Idx].ScalarParam := AScalarParam;
  FSteps[Idx].StrParam := AStrParam;
  Result := Idx;
end;

function TEditorMacroRecorder.ReplayMacro(const Root: TComponent;
  const DeltaMultiplier: Single): Integer;
var
  Targets: Classes.TList;

  procedure CollectTransforms(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;
    if (not (T is TCastleAbstractRootTransform)) and (Targets.IndexOf(T) < 0) then
      Targets.Add(T);
    for I := 0 to T.Count - 1 do
      CollectTransforms(T[I]);
  end;

  function MatchesFilter(const T: TCastleTransform; const FilterText: String): Boolean;
  begin
    if (FilterText = '') or (FilterText = '*') then
      Exit(True);
    Result := Pos(LowerCase(FilterText), LowerCase(T.Name)) > 0;
  end;

var
  Vp: TCastleViewport;
  SIdx, TIdx: Integer;
  Step: TEditorMacroStep;
  T: TCastleTransform;
  TouchedTransforms: Classes.TList;
  Mult: Single;
begin
  Result := 0;
  if (Root = nil) or (Length(FSteps) = 0) then
    Exit;

  Mult := DeltaMultiplier;
  Targets := Classes.TList.Create;
  TouchedTransforms := Classes.TList.Create;
  try
    if Root is TCastleTransform then
      CollectTransforms(TCastleTransform(Root))
    else
    begin
      Vp := FindViewport(Root);
      if (Vp <> nil) and (Vp.Items <> nil) then
        CollectTransforms(Vp.Items);
    end;

    for SIdx := 0 to High(FSteps) do
    begin
      Step := FSteps[SIdx];
      for TIdx := 0 to Targets.Count - 1 do
      begin
        T := TCastleTransform(Targets[TIdx]);
        if not MatchesFilter(T, Step.TargetFilter) then
          Continue;

        case Step.Kind of
          mskAddTranslate:
            T.Translation := T.Translation + Step.VecParam * Mult;
          mskMultiplyScale:
            T.Scale := Vector3(
              T.Scale.X * Step.VecParam.X,
              T.Scale.Y * Step.VecParam.Y,
              T.Scale.Z * Step.VecParam.Z);
          mskSetTag:
            T.Tag := Round(Step.ScalarParam * Mult);
          mskRenamePrefix:
            if (Step.StrParam <> '') and (Pos(Step.StrParam, T.Name) <> 1) then
              T.Name := Step.StrParam + T.Name;
          mskSetBoxColorRgb:
            if T is TCastleBox then
              TCastleBox(T).Color := Vector4(
                EnsureRange(Step.VecParam.X, 0.0, 1.0),
                EnsureRange(Step.VecParam.Y, 0.0, 1.0),
                EnsureRange(Step.VecParam.Z, 0.0, 1.0),
                TCastleBox(T).Color.W);
        end;

        if TouchedTransforms.IndexOf(T) < 0 then
          TouchedTransforms.Add(T);
      end;
    end;

    Result := TouchedTransforms.Count;
    FLastAffectedCount := Result;
    Inc(FReplayCount);
  finally
    FreeAndNil(TouchedTransforms);
    FreeAndNil(Targets);
  end;
end;

function TEditorMacroRecorder.ExportMacroJson: String;
var
  RootObj, StepObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  Arr := TJSONArray.Create;
  try
    for I := 0 to High(FSteps) do
    begin
      StepObj := TJSONObject.Create;
      StepObj.Add('kind', StepKindToString(FSteps[I].Kind));
      StepObj.Add('targetFilter', FSteps[I].TargetFilter);
      StepObj.Add('vecX', FSteps[I].VecParam.X);
      StepObj.Add('vecY', FSteps[I].VecParam.Y);
      StepObj.Add('vecZ', FSteps[I].VecParam.Z);
      StepObj.Add('scalarParam', FSteps[I].ScalarParam);
      StepObj.Add('strParam', FSteps[I].StrParam);
      Arr.Add(StepObj);
    end;
    RootObj.Add('macroName', FMacroName);
    RootObj.Add('steps', Arr);
    Arr := nil;
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(Arr);
    FreeAndNil(RootObj);
  end;
end;

function TEditorMacroRecorder.ImportMacroJson(const JsonText: String): Boolean;
var
  Data: TJSONData;
  Obj, StepObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  ParsedKind: TMacroStepKind;
begin
  Result := False;
  if Trim(JsonText) = '' then Exit;
  try
    Data := GetJSON(JsonText);
  except
    Exit;
  end;
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    FMacroName := Obj.Get('macroName', 'ImportedMacro');
    ClearSteps;
    Arr := Obj.Find('steps', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          StepObj := TJSONObject(Arr.Items[I]);
          if StringToStepKind(StepObj.Get('kind', 'add_translate'), ParsedKind) then
            RecordStep(
              ParsedKind,
              StepObj.Get('targetFilter', ''),
              Vector3(
                StepObj.Get('vecX', 0.0),
                StepObj.Get('vecY', 0.0),
                StepObj.Get('vecZ', 0.0)),
              StepObj.Get('scalarParam', 0.0),
              StepObj.Get('strParam', ''));
        end;
    Result := True;
  finally
    FreeAndNil(Data);
  end;
end;

function TEditorMacroRecorder.StepCount: Integer;
begin
  Result := Length(FSteps);
end;

function TEditorMacroRecorder.GetStep(const Index: Integer): TEditorMacroStep;
begin
  if (Index >= 0) and (Index < Length(FSteps)) then
    Result := FSteps[Index]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

class function TEditorMacroRecorder.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TEditorMacroRecorder.SpawnCratePillarsDemo(
  const Root, DesignOwner: TComponent): Integer;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  I: Integer;
  CrateBox, LampBox: TCastleBox;
  CrateName: String;
begin
  Result := 0;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  for I := 1 to 4 do
  begin
    CrateName := Format('MacroCrate_%d', [I]);
    if OwnerComp.FindComponent(CrateName) = nil then
    begin
      CrateBox := TCastleBox.Create(OwnerComp);
      CrateBox.Name := CrateName;
      CrateBox.Size := Vector3(1.2, 1.2, 1.2);
      CrateBox.Translation := Vector3((I - 2.5) * 2.5, 0.6, 0.0);
      CrateBox.Material := pmPhysical;
      CrateBox.Color := Vector4(0.76, 0.56, 0.30, 1.0);
      Vp.Items.Add(CrateBox);
      Inc(Result);
    end;
  end;

  if OwnerComp.FindComponent('PropStreetLamp') = nil then
  begin
    LampBox := TCastleBox.Create(OwnerComp);
    LampBox.Name := 'PropStreetLamp';
    LampBox.Size := Vector3(0.35, 3.8, 0.35);
    LampBox.Translation := Vector3(0.0, 1.9, -4.0);
    LampBox.Material := pmPhysical;
    LampBox.Color := Vector4(0.32, 0.36, 0.42, 1.0);
    Vp.Items.Add(LampBox);
  end;
end;

function TEditorMacroRecorder.GenerateMacroReport(const Root: TComponent): String;
var
  I: Integer;
  S: TEditorMacroStep;
begin
  Result :=
    '# Editor Action Macro Recorder & 96-Studio Hub Report (Phase 376)' + NL + NL +
    Format('- **Macro Name**: `%s` (`%d` steps, Recording: `%s`)', [
      FMacroName, StepCount, BoolToStr(FIsRecording, 'ACTIVE', 'IDLE')]) + NL +
    Format('- **Batch Replay Telemetry**: Replays Executed `%d` | Last Affected Transforms `%d`', [
      FReplayCount, FLastAffectedCount]) + NL +
    Format('- **Unified Horizon 2–11 Catalog**: **`%d` Studios** across `6` Domains (`19` MCP Tools incl. `cge_run_editor_macro`)', [
      TStudioHubManager.StudioCount]) + NL + NL +
    '## Recorded Macro Pipeline' + NL;

  if StepCount = 0 then
    Result := Result + '_No steps recorded yet._' + NL
  else
    for I := 0 to StepCount - 1 do
    begin
      S := FSteps[I];
      Result := Result + Format(
        '%d. **`%s`** | Filter=`"%s"` | Vec=`(%.2f, %.2f, %.2f)` | Scalar=`%.2f` | Str=`"%s"`' + NL,
        [I + 1, StepKindToString(S.Kind), S.TargetFilter,
         S.VecParam.X, S.VecParam.Y, S.VecParam.Z, S.ScalarParam, S.StrParam]);
    end;
end;

initialization
  GSharedMacroRecorder := nil;
finalization
  FreeAndNil(GSharedMacroRecorder);
end.
