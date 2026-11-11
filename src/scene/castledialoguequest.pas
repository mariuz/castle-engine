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

{ Directed branching dialogue graphs (@link(TCastleDialogueTree)), multi-stage
  quest objective & blackboard trackers (@link(TCastleQuestTracker)), and 3D NPC
  conversation behaviors (@link(TCastleNpcDialogueBehavior))
  (Phase 302 — UE 6.0 Narrative / Parley & Quest Objectives Parity). }
unit CastleDialogueQuest;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleClassUtils, CastleUtils, CastleTransform;

type
  { Lifecycle state of a quest in @link(TCastleQuestTracker). }
  TQuestState = (
    qsLocked,
    qsActive,
    qsCompleted,
    qsFailed
  );

  { Guard condition evaluated before showing a player dialogue choice. }
  TDialogueConditionOp = (
    dcoNone,
    dcoVarGte,
    dcoVarLte,
    dcoVarEq,
    dcoHasTag,
    dcoQuestState
  );

  { Consequence action executed when a player selects a dialogue choice. }
  TDialogueActionKind = (
    dakNone,
    dakSetVar,
    dakAddVar,
    dakGrantTag,
    dakStartQuest,
    dakAdvanceObjective,
    dakCompleteQuest,
    dakFailQuest
  );

  TDialogueStringArray = array of String;

  { Single player-selectable choice inside a @link(TDialogueNodeDef). }
  TDialogueChoiceDef = record
    ChoiceId: String;
    ChoiceText: String;
    LocalizationKey: String;
    TargetNodeId: String;
    ConditionOp: TDialogueConditionOp;
    ConditionKey: String;
    ConditionValue: String;
    ActionKind: TDialogueActionKind;
    ActionKey: String;
    ActionValue: String;
  end;
  TDialogueChoiceDefArray = array of TDialogueChoiceDef;

  { Directed speaker node in @link(TCastleDialogueTree). }
  TDialogueNodeDef = record
    NodeId: String;
    SpeakerName: String;
    PortraitKey: String;
    DialogueText: String;
    LocalizationKey: String;
    VoiceEventKey: String;
    CanvasX: Single;
    CanvasY: Single;
    Choices: TDialogueChoiceDefArray;
  end;

  { Quantified objective inside a @link(TQuestDefinition). }
  TQuestObjectiveDef = record
    ObjectiveId: String;
    Description: String;
    CurrentCount: Integer;
    RequiredCount: Integer;
    Optional: Boolean;
    function IsSatisfied: Boolean;
  end;
  TQuestObjectiveDefArray = array of TQuestObjectiveDef;

  { Multi-objective quest definition managed by @link(TCastleQuestTracker). }
  TQuestDefinition = record
    QuestId: String;
    Title: String;
    Summary: String;
    State: TQuestState;
    RewardXp: Integer;
    RewardTag: String;
    Objectives: TQuestObjectiveDefArray;
  end;

  { Key/value entry on @link(TCastleQuestTracker)'s narrative blackboard. }
  TNarrativeVariableEntry = record
    Key: String;
    Value: String;
  end;

  { Non-visual component tracking multi-stage quests, objective counters,
    narrative blackboard variables, and granted Gameplay Tags. }
  TCastleQuestTracker = class(TCastleComponent)
  strict private
    FQuests: array of TQuestDefinition;
    FVariables: array of TNarrativeVariableEntry;
    FActiveTagsCsv: String;

    function GetQuestsJson: String;
    procedure SetQuestsJson(const Value: String);
    procedure SetActiveTagsCsv(const Value: String);
    function FindVarIndex(const AKey: String): Integer;
    procedure CheckAutoCompleteQuest(const QIdx: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function QuestStateToName(const AState: TQuestState): String; static;
    class function NameToQuestState(const S: String;
      const ADefault: TQuestState = qsLocked): TQuestState; static;

    procedure ClearAll;

    function QuestCount: Integer;
    function FindQuestIndex(const AQuestId: String): Integer;
    function GetQuest(const AIndex: Integer): TQuestDefinition;
    function AddOrUpdateQuest(const AQuestId, ATitle, ASummary: String;
      const AInitialState: TQuestState = qsLocked;
      const ARewardXp: Integer = 100;
      const ARewardTag: String = ''): Integer;
    function AddObjective(const AQuestId, AObjectiveId, ADescription: String;
      const ARequiredCount: Integer = 1;
      const AOptional: Boolean = false): Boolean;

    function GetQuestState(const AQuestId: String): TQuestState;
    function StartQuest(const AQuestId: String): Boolean;
    function AdvanceObjective(const AQuestId, AObjectiveId: String;
      const ADelta: Integer = 1): Boolean;
    function CompleteQuest(const AQuestId: String): Boolean;
    function FailQuest(const AQuestId: String): Boolean;

    { Narrative blackboard variable accessors }
    function VariableCount: Integer;
    function GetVariableEntry(const AIndex: Integer): TNarrativeVariableEntry;
    procedure SetVariableString(const AKey, AValue: String);
    function GetVariableString(const AKey: String;
      const ADefault: String = ''): String;
    procedure SetVariableFloat(const AKey: String; const AValue: Single);
    function GetVariableFloat(const AKey: String;
      const ADefault: Single = 0.0): Single;

    { Narrative Gameplay Tag helpers }
    procedure GrantGameplayTag(const ATag: String);
    function HasGameplayTag(const AQueryPattern: String): Boolean;

    function QuestSummaryBadge: String;
  published
    property QuestsJson: String read GetQuestsJson write SetQuestsJson;
    property ActiveTagsCsv: String read FActiveTagsCsv write SetActiveTagsCsv;
  end;

  { Non-visual directed branching dialogue asset with choice conditions,
    consequence actions, localization export, and graph validation. }
  TCastleDialogueTree = class(TCastleComponent)
  strict private
    FDialogueTitle: String;
    FDefaultSpeaker: String;
    FEntryNodeId: String;
    FQuestTracker: TCastleQuestTracker;
    FNodes: array of TDialogueNodeDef;

    function GetDialogueJson: String;
    procedure SetDialogueJson(const Value: String);
    procedure SetQuestTracker(const Value: TCastleQuestTracker);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function ConditionOpToName(const AOp: TDialogueConditionOp): String; static;
    class function NameToConditionOp(const S: String): TDialogueConditionOp; static;
    class function ActionKindToName(const AKind: TDialogueActionKind): String; static;
    class function NameToActionKind(const S: String): TDialogueActionKind; static;

    procedure ClearAll;

    function NodeCount: Integer;
    function FindNodeIndex(const ANodeId: String): Integer;
    function GetNode(const AIndex: Integer): TDialogueNodeDef;
    function AddNode(const ANodeId, ASpeakerName, ADialogueText: String;
      const ALocalizationKey: String = '';
      const ACanvasX: Single = 60.0;
      const ACanvasY: Single = 60.0): Integer;
    procedure UpdateNodeText(const ANodeId, ASpeakerName, ADialogueText,
      ALocalizationKey: String);
    procedure SetNodeCanvasPos(const ANodeId: String; const AX, AY: Single);
    function RemoveNode(const ANodeId: String): Boolean;

    function AddChoice(const ANodeId, AChoiceId, AChoiceText, ATargetNodeId: String;
      const ALocalizationKey: String = '';
      const ACondOp: TDialogueConditionOp = dcoNone;
      const ACondKey: String = '';
      const ACondValue: String = '';
      const AActionKind: TDialogueActionKind = dakNone;
      const AActionKey: String = '';
      const AActionValue: String = ''): Boolean;

    { Evaluate whether @code(AChoice) passes its guard condition against
      @code(ATracker) (or @link(QuestTracker) when @code(ATracker = nil)). }
    function IsChoiceAvailable(const AChoice: TDialogueChoiceDef;
      const ATracker: TCastleQuestTracker = nil): Boolean;

    { Execute @code(AChoice)'s consequence action against @code(ATracker)
      (or @link(QuestTracker) when @code(ATracker = nil)). }
    procedure ExecuteChoiceAction(const AChoice: TDialogueChoiceDef;
      const ATracker: TCastleQuestTracker = nil);

    { Return all player choices on @code(ANodeId) whose guard conditions pass. }
    function GetAvailableChoices(const ANodeId: String;
      const ATracker: TCastleQuestTracker = nil): TDialogueChoiceDefArray;

    { Select choice @code(AAvailableChoiceIndex) among @link(GetAvailableChoices)
      for @code(ACurrentNodeId), execute its consequence action, and output
      @code(OutNextNodeId) (@code('') when conversation ends). }
    function StepConversation(const ACurrentNodeId: String;
      const AAvailableChoiceIndex: Integer;
      out OutNextNodeId: String;
      const ATracker: TCastleQuestTracker = nil): Boolean;

    { Validate entry node existence, broken choice targets, and unreachable
      orphan nodes via BFS from @link(EntryNodeId). }
    function ValidateGraph(out OutWarnings: TDialogueStringArray): Boolean;

    function DialogueSummaryBadge: String;
  published
    property DialogueTitle: String read FDialogueTitle write FDialogueTitle;
    property DefaultSpeaker: String read FDefaultSpeaker write FDefaultSpeaker;
    property EntryNodeId: String read FEntryNodeId write FEntryNodeId;
    property DialogueJson: String read GetDialogueJson write SetDialogueJson;
    property QuestTracker: TCastleQuestTracker
      read FQuestTracker write SetQuestTracker;
  end;

  { 3D NPC interaction behavior binding a @link(TCastleTransform) actor to a
    @link(TCastleDialogueTree) with configurable interaction radius. }
  TCastleNpcDialogueBehavior = class(TCastleBehavior)
  public const
    DefaultInteractionRadius = Single(3.0);
  strict private
    FNpcDisplayName: String;
    FDialogueTree: TCastleDialogueTree;
    FInteractionRadius: Single;
    FShowSpeechIndicatorInViewport: Boolean;
    procedure SetDialogueTree(const Value: TCastleDialogueTree);
    procedure SetInteractionRadius(const Value: Single);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function NpcDialogueBadge: String;
  published
    property NpcDisplayName: String read FNpcDisplayName write FNpcDisplayName;
    property DialogueTree: TCastleDialogueTree
      read FDialogueTree write SetDialogueTree;
    property InteractionRadius: Single
      read FInteractionRadius write SetInteractionRadius
      {$ifdef FPC}default DefaultInteractionRadius{$endif};
    property ShowSpeechIndicatorInViewport: Boolean
      read FShowSpeechIndicatorInViewport write FShowSpeechIndicatorInViewport
      default true;
  end;

implementation

uses
  StrUtils, fpjson, jsonparser,
  CastleComponentSerialize;

function InvariantFs: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function MatchNarrativeTag(const ATag, APattern: String): Boolean;
var
  CleanTag, CleanPat, Prefix: String;
begin
  CleanTag := LowerCase(Trim(ATag));
  CleanPat := LowerCase(Trim(APattern));
  if (CleanTag = '') or (CleanPat = '') then
    Exit(false);
  if CleanPat = '*' then
    Exit(true);
  if (Length(CleanPat) >= 3) and (Copy(CleanPat, Length(CleanPat) - 1, 2) = '.*') then
  begin
    Prefix := Copy(CleanPat, 1, Length(CleanPat) - 2);
    Result := (CleanTag = Prefix) or
      ((Length(CleanTag) > Length(Prefix)) and
       (Copy(CleanTag, 1, Length(Prefix) + 1) = Prefix + '.'));
  end else
    Result := (CleanTag = CleanPat) or
      ((Length(CleanTag) > Length(CleanPat)) and
       (Copy(CleanTag, 1, Length(CleanPat) + 1) = CleanPat + '.'));
end;

function SplitTagCsv(const S: String): TDialogueStringArray;
var
  OutArr: TDialogueStringArray;
  Cur, Trimmed: String;
  I, N: Integer;
  Ch: Char;
begin
  OutArr := nil;
  Cur := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if (Ch = ',') or (Ch = ';') or (Ch = #10) or (Ch = #13) then
    begin
      Trimmed := Trim(Cur);
      Cur := '';
      if Trimmed <> '' then
      begin
        N := Length(OutArr);
        SetLength(OutArr, N + 1);
        OutArr[N] := Trimmed;
      end;
    end else
      Cur := Cur + Ch;
  end;
  Trimmed := Trim(Cur);
  if Trimmed <> '' then
  begin
    N := Length(OutArr);
    SetLength(OutArr, N + 1);
    OutArr[N] := Trimmed;
  end;
  Result := OutArr;
end;

{ TQuestObjectiveDef --------------------------------------------------------- }

function TQuestObjectiveDef.IsSatisfied: Boolean;
begin
  Result := CurrentCount >= Max(1, RequiredCount);
end;

{ TCastleQuestTracker -------------------------------------------------------- }

constructor TCastleQuestTracker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FQuests := nil;
  FVariables := nil;
  FActiveTagsCsv := '';
end;

function TCastleQuestTracker.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, ['QuestsJson', 'ActiveTagsCsv']) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleQuestTracker.QuestStateToName(
  const AState: TQuestState): String;
begin
  case AState of
    qsLocked: Result := 'Locked';
    qsActive: Result := 'Active';
    qsCompleted: Result := 'Completed';
    qsFailed: Result := 'Failed';
  end;
end;

class function TCastleQuestTracker.NameToQuestState(const S: String;
  const ADefault: TQuestState): TQuestState;
var
  T: String;
begin
  T := LowerCase(Trim(S));
  if (T = 'locked') or (T = 'qslocked') then
    Result := qsLocked
  else
  if (T = 'active') or (T = 'qsactive') then
    Result := qsActive
  else
  if (T = 'completed') or (T = 'qscompleted') or (T = 'done') then
    Result := qsCompleted
  else
  if (T = 'failed') or (T = 'qsfailed') then
    Result := qsFailed
  else
    Result := ADefault;
end;

procedure TCastleQuestTracker.ClearAll;
begin
  FQuests := nil;
  FVariables := nil;
  FActiveTagsCsv := '';
end;

procedure TCastleQuestTracker.SetActiveTagsCsv(const Value: String);
begin
  FActiveTagsCsv := Trim(Value);
end;

function TCastleQuestTracker.QuestCount: Integer;
begin
  Result := Length(FQuests);
end;

function TCastleQuestTracker.FindQuestIndex(const AQuestId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FQuests) do
    if SameText(FQuests[I].QuestId, Trim(AQuestId)) then
      Exit(I);
  Result := -1;
end;

function TCastleQuestTracker.GetQuest(const AIndex: Integer): TQuestDefinition;
begin
  if (AIndex >= 0) and (AIndex < Length(FQuests)) then
    Result := FQuests[AIndex]
  else
    Result := Default(TQuestDefinition);
end;

function TCastleQuestTracker.AddOrUpdateQuest(
  const AQuestId, ATitle, ASummary: String;
  const AInitialState: TQuestState;
  const ARewardXp: Integer;
  const ARewardTag: String): Integer;
var
  CleanId: String;
begin
  CleanId := Trim(AQuestId);
  if CleanId = '' then
    Exit(-1);
  Result := FindQuestIndex(CleanId);
  if Result < 0 then
  begin
    Result := Length(FQuests);
    SetLength(FQuests, Result + 1);
    FQuests[Result] := Default(TQuestDefinition);
    FQuests[Result].QuestId := CleanId;
  end;
  FQuests[Result].Title := ATitle;
  FQuests[Result].Summary := ASummary;
  FQuests[Result].State := AInitialState;
  FQuests[Result].RewardXp := Max(0, ARewardXp);
  FQuests[Result].RewardTag := Trim(ARewardTag);
end;

function TCastleQuestTracker.AddObjective(
  const AQuestId, AObjectiveId, ADescription: String;
  const ARequiredCount: Integer;
  const AOptional: Boolean): Boolean;
var
  QIdx, OIdx, I: Integer;
  CleanObj: String;
begin
  Result := false;
  QIdx := FindQuestIndex(AQuestId);
  CleanObj := Trim(AObjectiveId);
  if (QIdx < 0) or (CleanObj = '') then
    Exit;

  OIdx := -1;
  for I := 0 to High(FQuests[QIdx].Objectives) do
    if SameText(FQuests[QIdx].Objectives[I].ObjectiveId, CleanObj) then
    begin
      OIdx := I;
      Break;
    end;

  if OIdx < 0 then
  begin
    OIdx := Length(FQuests[QIdx].Objectives);
    SetLength(FQuests[QIdx].Objectives, OIdx + 1);
    FQuests[QIdx].Objectives[OIdx] := Default(TQuestObjectiveDef);
    FQuests[QIdx].Objectives[OIdx].ObjectiveId := CleanObj;
    FQuests[QIdx].Objectives[OIdx].CurrentCount := 0;
  end;
  FQuests[QIdx].Objectives[OIdx].Description := ADescription;
  FQuests[QIdx].Objectives[OIdx].RequiredCount := Max(1, ARequiredCount);
  FQuests[QIdx].Objectives[OIdx].Optional := AOptional;
  Result := true;
end;

function TCastleQuestTracker.GetQuestState(const AQuestId: String): TQuestState;
var
  QIdx: Integer;
begin
  QIdx := FindQuestIndex(AQuestId);
  if QIdx >= 0 then
    Result := FQuests[QIdx].State
  else
    Result := qsLocked;
end;

function TCastleQuestTracker.StartQuest(const AQuestId: String): Boolean;
var
  QIdx: Integer;
begin
  QIdx := FindQuestIndex(AQuestId);
  if QIdx < 0 then
    Exit(false);
  if FQuests[QIdx].State = qsLocked then
    FQuests[QIdx].State := qsActive;
  Result := FQuests[QIdx].State = qsActive;
end;

procedure TCastleQuestTracker.CheckAutoCompleteQuest(const QIdx: Integer);
var
  I, NonOptCount: Integer;
begin
  if (QIdx < 0) or (QIdx >= Length(FQuests)) then
    Exit;
  if FQuests[QIdx].State <> qsActive then
    Exit;

  NonOptCount := 0;
  for I := 0 to High(FQuests[QIdx].Objectives) do
    if not FQuests[QIdx].Objectives[I].Optional then
    begin
      Inc(NonOptCount);
      if not FQuests[QIdx].Objectives[I].IsSatisfied then
        Exit;
    end;

  if NonOptCount > 0 then
    CompleteQuest(FQuests[QIdx].QuestId);
end;

function TCastleQuestTracker.AdvanceObjective(
  const AQuestId, AObjectiveId: String;
  const ADelta: Integer): Boolean;
var
  QIdx, I: Integer;
begin
  Result := false;
  QIdx := FindQuestIndex(AQuestId);
  if QIdx < 0 then
    Exit;
  if FQuests[QIdx].State = qsLocked then
    FQuests[QIdx].State := qsActive;
  if FQuests[QIdx].State <> qsActive then
    Exit;

  for I := 0 to High(FQuests[QIdx].Objectives) do
    if SameText(FQuests[QIdx].Objectives[I].ObjectiveId, Trim(AObjectiveId)) then
    begin
      FQuests[QIdx].Objectives[I].CurrentCount := Clamped(
        FQuests[QIdx].Objectives[I].CurrentCount + ADelta,
        0, FQuests[QIdx].Objectives[I].RequiredCount);
      CheckAutoCompleteQuest(QIdx);
      Exit(true);
    end;
end;

function TCastleQuestTracker.CompleteQuest(const AQuestId: String): Boolean;
var
  QIdx: Integer;
begin
  QIdx := FindQuestIndex(AQuestId);
  if QIdx < 0 then
    Exit(false);
  if FQuests[QIdx].State = qsCompleted then
    Exit(true);

  FQuests[QIdx].State := qsCompleted;
  if FQuests[QIdx].RewardXp > 0 then
    SetVariableFloat('XP', GetVariableFloat('XP', 0.0) + FQuests[QIdx].RewardXp);
  if FQuests[QIdx].RewardTag <> '' then
    GrantGameplayTag(FQuests[QIdx].RewardTag);
  Result := true;
end;

function TCastleQuestTracker.FailQuest(const AQuestId: String): Boolean;
var
  QIdx: Integer;
begin
  QIdx := FindQuestIndex(AQuestId);
  if QIdx < 0 then
    Exit(false);
  FQuests[QIdx].State := qsFailed;
  Result := true;
end;

function TCastleQuestTracker.FindVarIndex(const AKey: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FVariables) do
    if SameText(FVariables[I].Key, Trim(AKey)) then
      Exit(I);
  Result := -1;
end;

function TCastleQuestTracker.VariableCount: Integer;
begin
  Result := Length(FVariables);
end;

function TCastleQuestTracker.GetVariableEntry(
  const AIndex: Integer): TNarrativeVariableEntry;
begin
  if (AIndex >= 0) and (AIndex < Length(FVariables)) then
    Result := FVariables[AIndex]
  else
    Result := Default(TNarrativeVariableEntry);
end;

procedure TCastleQuestTracker.SetVariableString(const AKey, AValue: String);
var
  Idx: Integer;
  CleanK: String;
begin
  CleanK := Trim(AKey);
  if CleanK = '' then
    Exit;
  Idx := FindVarIndex(CleanK);
  if Idx < 0 then
  begin
    Idx := Length(FVariables);
    SetLength(FVariables, Idx + 1);
    FVariables[Idx].Key := CleanK;
  end;
  FVariables[Idx].Value := AValue;
end;

function TCastleQuestTracker.GetVariableString(const AKey, ADefault: String): String;
var
  Idx: Integer;
begin
  Idx := FindVarIndex(AKey);
  if Idx >= 0 then
    Result := FVariables[Idx].Value
  else
    Result := ADefault;
end;

procedure TCastleQuestTracker.SetVariableFloat(const AKey: String;
  const AValue: Single);
begin
  SetVariableString(AKey, FormatFloat('0.####', AValue, InvariantFs));
end;

function TCastleQuestTracker.GetVariableFloat(const AKey: String;
  const ADefault: Single): Single;
var
  S: String;
  D: Double;
begin
  S := GetVariableString(AKey, '');
  if (S <> '') and TryStrToFloat(S, D, InvariantFs) then
    Result := Single(D)
  else
    Result := ADefault;
end;

procedure TCastleQuestTracker.GrantGameplayTag(const ATag: String);
var
  CleanTag: String;
  Existing: TDialogueStringArray;
  I: Integer;
begin
  CleanTag := Trim(ATag);
  if CleanTag = '' then
    Exit;
  Existing := SplitTagCsv(FActiveTagsCsv);
  for I := 0 to High(Existing) do
    if SameText(Existing[I], CleanTag) then
      Exit;
  if FActiveTagsCsv = '' then
    FActiveTagsCsv := CleanTag
  else
    FActiveTagsCsv := FActiveTagsCsv + ', ' + CleanTag;
end;

function TCastleQuestTracker.HasGameplayTag(const AQueryPattern: String): Boolean;
var
  Existing: TDialogueStringArray;
  I: Integer;
begin
  Result := false;
  if Trim(AQueryPattern) = '' then
    Exit(true);
  Existing := SplitTagCsv(FActiveTagsCsv);
  for I := 0 to High(Existing) do
    if MatchNarrativeTag(Existing[I], AQueryPattern) then
      Exit(true);
end;

function TCastleQuestTracker.GetQuestsJson: String;
var
  RootObj, QObj, ObjItem, VObj: TJSONObject;
  QuestsArr, ObjArr, VarsArr: TJSONArray;
  I, J: Integer;
begin
  if (Length(FQuests) = 0) and (Length(FVariables) = 0) then
    Exit('');

  RootObj := TJSONObject.Create;
  try
    QuestsArr := TJSONArray.Create;
    for I := 0 to High(FQuests) do
    begin
      QObj := TJSONObject.Create;
      QObj.Add('id', FQuests[I].QuestId);
      QObj.Add('title', FQuests[I].Title);
      QObj.Add('summary', FQuests[I].Summary);
      QObj.Add('state', QuestStateToName(FQuests[I].State));
      QObj.Add('rewardXp', FQuests[I].RewardXp);
      QObj.Add('rewardTag', FQuests[I].RewardTag);

      ObjArr := TJSONArray.Create;
      for J := 0 to High(FQuests[I].Objectives) do
      begin
        ObjItem := TJSONObject.Create;
        ObjItem.Add('id', FQuests[I].Objectives[J].ObjectiveId);
        ObjItem.Add('desc', FQuests[I].Objectives[J].Description);
        ObjItem.Add('cur', FQuests[I].Objectives[J].CurrentCount);
        ObjItem.Add('req', FQuests[I].Objectives[J].RequiredCount);
        ObjItem.Add('opt', FQuests[I].Objectives[J].Optional);
        ObjArr.Add(ObjItem);
      end;
      QObj.Add('objectives', ObjArr);
      QuestsArr.Add(QObj);
    end;
    RootObj.Add('quests', QuestsArr);

    VarsArr := TJSONArray.Create;
    for I := 0 to High(FVariables) do
    begin
      VObj := TJSONObject.Create;
      VObj.Add('k', FVariables[I].Key);
      VObj.Add('v', FVariables[I].Value);
      VarsArr.Add(VObj);
    end;
    RootObj.Add('vars', VarsArr);

    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleQuestTracker.SetQuestsJson(const Value: String);
var
  Data: TJSONData;
  RootObj, QObj, ObjItem, VObj: TJSONObject;
  QuestsArr, ObjArr, VarsArr: TJSONArray;
  I, J, QIdx: Integer;
begin
  FQuests := nil;
  FVariables := nil;
  if Trim(Value) = '' then
    Exit;

  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then
      Exit;

    RootObj := TJSONObject(Data);
    QuestsArr := RootObj.Find('quests', jtArray) as TJSONArray;
    if QuestsArr <> nil then
      for I := 0 to QuestsArr.Count - 1 do
        if QuestsArr.Items[I] is TJSONObject then
        begin
          QObj := TJSONObject(QuestsArr.Items[I]);
          QIdx := AddOrUpdateQuest(
            QObj.Get('id', ''),
            QObj.Get('title', ''),
            QObj.Get('summary', ''),
            NameToQuestState(QObj.Get('state', 'Locked')),
            QObj.Get('rewardXp', 0),
            QObj.Get('rewardTag', ''));
          if QIdx >= 0 then
          begin
            ObjArr := QObj.Find('objectives', jtArray) as TJSONArray;
            if ObjArr <> nil then
              for J := 0 to ObjArr.Count - 1 do
                if ObjArr.Items[J] is TJSONObject then
                begin
                  ObjItem := TJSONObject(ObjArr.Items[J]);
                  if AddObjective(
                       FQuests[QIdx].QuestId,
                       ObjItem.Get('id', ''),
                       ObjItem.Get('desc', ''),
                       ObjItem.Get('req', 1),
                       ObjItem.Get('opt', false)) then
                    FQuests[QIdx].Objectives[High(FQuests[QIdx].Objectives)].CurrentCount :=
                      Clamped(ObjItem.Get('cur', 0), 0, Max(1, ObjItem.Get('req', 1)));
                end;
          end;
        end;

    VarsArr := RootObj.Find('vars', jtArray) as TJSONArray;
    if VarsArr <> nil then
      for I := 0 to VarsArr.Count - 1 do
        if VarsArr.Items[I] is TJSONObject then
        begin
          VObj := TJSONObject(VarsArr.Items[I]);
          SetVariableString(VObj.Get('k', ''), VObj.Get('v', ''));
        end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleQuestTracker.QuestSummaryBadge: String;
var
  I, ActCnt, CompCnt: Integer;
begin
  ActCnt := 0;
  CompCnt := 0;
  for I := 0 to High(FQuests) do
    case FQuests[I].State of
      qsActive: Inc(ActCnt);
      qsCompleted: Inc(CompCnt);
    else ;
    end;
  Result := Format('[Quests:%d (%d active, %d done)]',
    [Length(FQuests), ActCnt, CompCnt]);
end;

{ TCastleDialogueTree -------------------------------------------------------- }

constructor TCastleDialogueTree.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDialogueTitle := 'Conversation';
  FDefaultSpeaker := 'Villager';
  FEntryNodeId := '';
  FQuestTracker := nil;
  FNodes := nil;
end;

destructor TCastleDialogueTree.Destroy;
begin
  SetQuestTracker(nil);
  inherited;
end;

procedure TCastleDialogueTree.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FQuestTracker) then
    FQuestTracker := nil;
end;

procedure TCastleDialogueTree.SetQuestTracker(const Value: TCastleQuestTracker);
begin
  if FQuestTracker <> Value then
  begin
    if FQuestTracker <> nil then
      FQuestTracker.RemoveFreeNotification(Self);
    FQuestTracker := Value;
    if FQuestTracker <> nil then
      FQuestTracker.FreeNotification(Self);
  end;
end;

function TCastleDialogueTree.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'DialogueTitle', 'DefaultSpeaker', 'EntryNodeId',
       'DialogueJson', 'QuestTracker'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleDialogueTree.ConditionOpToName(
  const AOp: TDialogueConditionOp): String;
begin
  case AOp of
    dcoNone: Result := 'None';
    dcoVarGte: Result := 'VarGte';
    dcoVarLte: Result := 'VarLte';
    dcoVarEq: Result := 'VarEq';
    dcoHasTag: Result := 'HasTag';
    dcoQuestState: Result := 'QuestState';
  end;
end;

class function TCastleDialogueTree.NameToConditionOp(
  const S: String): TDialogueConditionOp;
var
  T: String;
begin
  T := LowerCase(Trim(S));
  if T = 'vargte' then Result := dcoVarGte
  else if T = 'varlte' then Result := dcoVarLte
  else if T = 'vareq' then Result := dcoVarEq
  else if T = 'hastag' then Result := dcoHasTag
  else if T = 'queststate' then Result := dcoQuestState
  else Result := dcoNone;
end;

class function TCastleDialogueTree.ActionKindToName(
  const AKind: TDialogueActionKind): String;
begin
  case AKind of
    dakNone: Result := 'None';
    dakSetVar: Result := 'SetVar';
    dakAddVar: Result := 'AddVar';
    dakGrantTag: Result := 'GrantTag';
    dakStartQuest: Result := 'StartQuest';
    dakAdvanceObjective: Result := 'AdvanceObjective';
    dakCompleteQuest: Result := 'CompleteQuest';
    dakFailQuest: Result := 'FailQuest';
  end;
end;

class function TCastleDialogueTree.NameToActionKind(
  const S: String): TDialogueActionKind;
var
  T: String;
begin
  T := LowerCase(Trim(S));
  if T = 'setvar' then Result := dakSetVar
  else if T = 'addvar' then Result := dakAddVar
  else if T = 'granttag' then Result := dakGrantTag
  else if T = 'startquest' then Result := dakStartQuest
  else if T = 'advanceobjective' then Result := dakAdvanceObjective
  else if T = 'completequest' then Result := dakCompleteQuest
  else if T = 'failquest' then Result := dakFailQuest
  else Result := dakNone;
end;

procedure TCastleDialogueTree.ClearAll;
begin
  FNodes := nil;
  FEntryNodeId := '';
end;

function TCastleDialogueTree.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TCastleDialogueTree.FindNodeIndex(const ANodeId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].NodeId, Trim(ANodeId)) then
      Exit(I);
  Result := -1;
end;

function TCastleDialogueTree.GetNode(const AIndex: Integer): TDialogueNodeDef;
begin
  if (AIndex >= 0) and (AIndex < Length(FNodes)) then
    Result := FNodes[AIndex]
  else
    Result := Default(TDialogueNodeDef);
end;

function TCastleDialogueTree.AddNode(
  const ANodeId, ASpeakerName, ADialogueText, ALocalizationKey: String;
  const ACanvasX, ACanvasY: Single): Integer;
var
  CleanId: String;
begin
  CleanId := Trim(ANodeId);
  if CleanId = '' then
    Exit(-1);
  Result := FindNodeIndex(CleanId);
  if Result < 0 then
  begin
    Result := Length(FNodes);
    SetLength(FNodes, Result + 1);
    FNodes[Result] := Default(TDialogueNodeDef);
    FNodes[Result].NodeId := CleanId;
  end;
  if Trim(ASpeakerName) <> '' then
    FNodes[Result].SpeakerName := Trim(ASpeakerName)
  else
    FNodes[Result].SpeakerName := FDefaultSpeaker;
  FNodes[Result].DialogueText := ADialogueText;
  if Trim(ALocalizationKey) <> '' then
    FNodes[Result].LocalizationKey := Trim(ALocalizationKey)
  else
    FNodes[Result].LocalizationKey := 'dlg.' + LowerCase(CleanId);
  FNodes[Result].CanvasX := ACanvasX;
  FNodes[Result].CanvasY := ACanvasY;

  if FEntryNodeId = '' then
    FEntryNodeId := CleanId;
end;

procedure TCastleDialogueTree.UpdateNodeText(
  const ANodeId, ASpeakerName, ADialogueText, ALocalizationKey: String);
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then
    Exit;
  if Trim(ASpeakerName) <> '' then
    FNodes[Idx].SpeakerName := Trim(ASpeakerName);
  FNodes[Idx].DialogueText := ADialogueText;
  if Trim(ALocalizationKey) <> '' then
    FNodes[Idx].LocalizationKey := Trim(ALocalizationKey);
end;

procedure TCastleDialogueTree.SetNodeCanvasPos(const ANodeId: String;
  const AX, AY: Single);
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx >= 0 then
  begin
    FNodes[Idx].CanvasX := AX;
    FNodes[Idx].CanvasY := AY;
  end;
end;

function TCastleDialogueTree.RemoveNode(const ANodeId: String): Boolean;
var
  Idx, I: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then
    Exit(false);
  for I := Idx to High(FNodes) - 1 do
    FNodes[I] := FNodes[I + 1];
  SetLength(FNodes, Length(FNodes) - 1);
  if SameText(FEntryNodeId, ANodeId) then
  begin
    if Length(FNodes) > 0 then
      FEntryNodeId := FNodes[0].NodeId
    else
      FEntryNodeId := '';
  end;
  Result := true;
end;

function TCastleDialogueTree.AddChoice(
  const ANodeId, AChoiceId, AChoiceText, ATargetNodeId, ALocalizationKey: String;
  const ACondOp: TDialogueConditionOp;
  const ACondKey, ACondValue: String;
  const AActionKind: TDialogueActionKind;
  const AActionKey, AActionValue: String): Boolean;
var
  NIdx, CIdx: Integer;
  C: TDialogueChoiceDef;
begin
  Result := false;
  NIdx := FindNodeIndex(ANodeId);
  if NIdx < 0 then
    Exit;

  C := Default(TDialogueChoiceDef);
  if Trim(AChoiceId) <> '' then
    C.ChoiceId := Trim(AChoiceId)
  else
    C.ChoiceId := Format('choice_%d', [Length(FNodes[NIdx].Choices) + 1]);
  C.ChoiceText := AChoiceText;
  if Trim(ALocalizationKey) <> '' then
    C.LocalizationKey := Trim(ALocalizationKey)
  else
    C.LocalizationKey := FNodes[NIdx].LocalizationKey + '.' + LowerCase(C.ChoiceId);
  C.TargetNodeId := Trim(ATargetNodeId);
  C.ConditionOp := ACondOp;
  C.ConditionKey := Trim(ACondKey);
  C.ConditionValue := Trim(ACondValue);
  C.ActionKind := AActionKind;
  C.ActionKey := Trim(AActionKey);
  C.ActionValue := Trim(AActionValue);

  CIdx := Length(FNodes[NIdx].Choices);
  SetLength(FNodes[NIdx].Choices, CIdx + 1);
  FNodes[NIdx].Choices[CIdx] := C;
  Result := true;
end;

function TCastleDialogueTree.IsChoiceAvailable(
  const AChoice: TDialogueChoiceDef;
  const ATracker: TCastleQuestTracker): Boolean;
var
  TrackerToUse: TCastleQuestTracker;
  TargetFloat, CurFloat: Double;
  CurStr: String;
begin
  if AChoice.ConditionOp = dcoNone then
    Exit(true);

  if ATracker <> nil then
    TrackerToUse := ATracker
  else
    TrackerToUse := FQuestTracker;

  if TrackerToUse = nil then
    Exit(false);

  case AChoice.ConditionOp of
    dcoVarGte:
      begin
        if not TryStrToFloat(AChoice.ConditionValue, TargetFloat, InvariantFs) then
          TargetFloat := 0.0;
        CurFloat := TrackerToUse.GetVariableFloat(AChoice.ConditionKey, 0.0);
        Result := CurFloat >= TargetFloat - 1e-5;
      end;
    dcoVarLte:
      begin
        if not TryStrToFloat(AChoice.ConditionValue, TargetFloat, InvariantFs) then
          TargetFloat := 0.0;
        CurFloat := TrackerToUse.GetVariableFloat(AChoice.ConditionKey, 0.0);
        Result := CurFloat <= TargetFloat + 1e-5;
      end;
    dcoVarEq:
      begin
        CurStr := TrackerToUse.GetVariableString(AChoice.ConditionKey, '');
        if TryStrToFloat(AChoice.ConditionValue, TargetFloat, InvariantFs) and
           TryStrToFloat(CurStr, CurFloat, InvariantFs) then
          Result := SameValue(CurFloat, TargetFloat, 1e-4)
        else
          Result := SameText(Trim(CurStr), AChoice.ConditionValue);
      end;
    dcoHasTag:
      Result := TrackerToUse.HasGameplayTag(AChoice.ConditionKey);
    dcoQuestState:
      Result := TrackerToUse.GetQuestState(AChoice.ConditionKey) =
        TCastleQuestTracker.NameToQuestState(AChoice.ConditionValue, qsActive);
  else
    Result := true;
  end;
end;

procedure TCastleDialogueTree.ExecuteChoiceAction(
  const AChoice: TDialogueChoiceDef;
  const ATracker: TCastleQuestTracker);
var
  TrackerToUse: TCastleQuestTracker;
  DeltaF: Double;
  ColonPos, DeltaInt: Integer;
  QId, ObjId: String;
begin
  if AChoice.ActionKind = dakNone then
    Exit;

  if ATracker <> nil then
    TrackerToUse := ATracker
  else
    TrackerToUse := FQuestTracker;

  if TrackerToUse = nil then
    Exit;

  case AChoice.ActionKind of
    dakSetVar:
      TrackerToUse.SetVariableString(AChoice.ActionKey, AChoice.ActionValue);
    dakAddVar:
      begin
        if not TryStrToFloat(AChoice.ActionValue, DeltaF, InvariantFs) then
          DeltaF := 1.0;
        TrackerToUse.SetVariableFloat(AChoice.ActionKey,
          TrackerToUse.GetVariableFloat(AChoice.ActionKey, 0.0) + Single(DeltaF));
      end;
    dakGrantTag:
      TrackerToUse.GrantGameplayTag(AChoice.ActionKey);
    dakStartQuest:
      TrackerToUse.StartQuest(AChoice.ActionKey);
    dakAdvanceObjective:
      begin
        ColonPos := Pos(':', AChoice.ActionKey);
        if ColonPos > 1 then
        begin
          QId := Copy(AChoice.ActionKey, 1, ColonPos - 1);
          ObjId := Copy(AChoice.ActionKey, ColonPos + 1, MaxInt);
        end else
        begin
          QId := AChoice.ActionKey;
          ObjId := AChoice.ActionValue;
        end;
        DeltaInt := StrToIntDef(AChoice.ActionValue, 1);
        if DeltaInt <= 0 then
          DeltaInt := 1;
        TrackerToUse.AdvanceObjective(QId, ObjId, DeltaInt);
      end;
    dakCompleteQuest:
      TrackerToUse.CompleteQuest(AChoice.ActionKey);
    dakFailQuest:
      TrackerToUse.FailQuest(AChoice.ActionKey);
  else ;
  end;
end;

function TCastleDialogueTree.GetAvailableChoices(
  const ANodeId: String;
  const ATracker: TCastleQuestTracker): TDialogueChoiceDefArray;
var
  OutArr: TDialogueChoiceDefArray;
  NIdx, I, N: Integer;
begin
  OutArr := nil;
  NIdx := FindNodeIndex(ANodeId);
  if NIdx >= 0 then
    for I := 0 to High(FNodes[NIdx].Choices) do
      if IsChoiceAvailable(FNodes[NIdx].Choices[I], ATracker) then
      begin
        N := Length(OutArr);
        SetLength(OutArr, N + 1);
        OutArr[N] := FNodes[NIdx].Choices[I];
      end;
  Result := OutArr;
end;

function TCastleDialogueTree.StepConversation(
  const ACurrentNodeId: String;
  const AAvailableChoiceIndex: Integer;
  out OutNextNodeId: String;
  const ATracker: TCastleQuestTracker): Boolean;
var
  Avail: TDialogueChoiceDefArray;
  Chosen: TDialogueChoiceDef;
begin
  Result := false;
  OutNextNodeId := '';
  Avail := GetAvailableChoices(ACurrentNodeId, ATracker);
  if (AAvailableChoiceIndex < 0) or (AAvailableChoiceIndex >= Length(Avail)) then
    Exit;

  Chosen := Avail[AAvailableChoiceIndex];
  ExecuteChoiceAction(Chosen, ATracker);
  if (Chosen.TargetNodeId = '') or SameText(Chosen.TargetNodeId, 'END') then
    OutNextNodeId := ''
  else
    OutNextNodeId := Chosen.TargetNodeId;
  Result := true;
end;

function TCastleDialogueTree.ValidateGraph(
  out OutWarnings: TDialogueStringArray): Boolean;
var
  WarnList: TDialogueStringArray;
  Visited: array of Boolean;
  Queue: array of Integer;
  Head, Tail, EntryIdx, CurIdx, TgtIdx, I, J: Integer;
  Tgt: String;

  procedure AppendWarn(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(WarnList);
    SetLength(WarnList, N + 1);
    WarnList[N] := Msg;
  end;

begin
  WarnList := nil;
  if Length(FNodes) = 0 then
  begin
    AppendWarn(Format('Dialogue "%s" has 0 nodes.', [Name]));
    OutWarnings := WarnList;
    Exit(false);
  end;

  EntryIdx := FindNodeIndex(FEntryNodeId);
  if EntryIdx < 0 then
    AppendWarn(Format('Dialogue "%s": EntryNodeId "%s" does not exist.',
      [Name, FEntryNodeId]));

  for I := 0 to High(FNodes) do
    for J := 0 to High(FNodes[I].Choices) do
    begin
      Tgt := FNodes[I].Choices[J].TargetNodeId;
      if (Tgt <> '') and (not SameText(Tgt, 'END')) and
         (FindNodeIndex(Tgt) < 0) then
        AppendWarn(Format('Dialogue "%s" node "%s" choice "%s" points to missing node "%s".',
          [Name, FNodes[I].NodeId, FNodes[I].Choices[J].ChoiceId, Tgt]));
    end;

  if EntryIdx >= 0 then
  begin
    Visited := nil;
    Queue := nil;
    SetLength(Visited, Length(FNodes));
    SetLength(Queue, Length(FNodes));
    Visited[EntryIdx] := true;
    Queue[0] := EntryIdx;
    Head := 0;
    Tail := 1;
    while Head < Tail do
    begin
      CurIdx := Queue[Head];
      Inc(Head);
      for J := 0 to High(FNodes[CurIdx].Choices) do
      begin
        Tgt := FNodes[CurIdx].Choices[J].TargetNodeId;
        if (Tgt <> '') and (not SameText(Tgt, 'END')) then
        begin
          TgtIdx := FindNodeIndex(Tgt);
          if (TgtIdx >= 0) and (not Visited[TgtIdx]) then
          begin
            Visited[TgtIdx] := true;
            Queue[Tail] := TgtIdx;
            Inc(Tail);
          end;
        end;
      end;
    end;

    for I := 0 to High(FNodes) do
      if not Visited[I] then
        AppendWarn(Format('Dialogue "%s" node "%s" is unreachable from EntryNodeId "%s".',
          [Name, FNodes[I].NodeId, FEntryNodeId]));
  end;

  OutWarnings := WarnList;
  Result := Length(WarnList) = 0;
end;

function TCastleDialogueTree.GetDialogueJson: String;
var
  RootObj, NObj, CObj: TJSONObject;
  NodesArr, ChoicesArr: TJSONArray;
  I, J: Integer;
begin
  if Length(FNodes) = 0 then
    Exit('');

  RootObj := TJSONObject.Create;
  try
    NodesArr := TJSONArray.Create;
    for I := 0 to High(FNodes) do
    begin
      NObj := TJSONObject.Create;
      NObj.Add('id', FNodes[I].NodeId);
      NObj.Add('speaker', FNodes[I].SpeakerName);
      NObj.Add('portrait', FNodes[I].PortraitKey);
      NObj.Add('text', FNodes[I].DialogueText);
      NObj.Add('loc', FNodes[I].LocalizationKey);
      NObj.Add('voice', FNodes[I].VoiceEventKey);
      NObj.Add('x', FNodes[I].CanvasX);
      NObj.Add('y', FNodes[I].CanvasY);

      ChoicesArr := TJSONArray.Create;
      for J := 0 to High(FNodes[I].Choices) do
      begin
        CObj := TJSONObject.Create;
        CObj.Add('id', FNodes[I].Choices[J].ChoiceId);
        CObj.Add('text', FNodes[I].Choices[J].ChoiceText);
        CObj.Add('loc', FNodes[I].Choices[J].LocalizationKey);
        CObj.Add('target', FNodes[I].Choices[J].TargetNodeId);
        CObj.Add('condOp', ConditionOpToName(FNodes[I].Choices[J].ConditionOp));
        CObj.Add('condKey', FNodes[I].Choices[J].ConditionKey);
        CObj.Add('condVal', FNodes[I].Choices[J].ConditionValue);
        CObj.Add('actKind', ActionKindToName(FNodes[I].Choices[J].ActionKind));
        CObj.Add('actKey', FNodes[I].Choices[J].ActionKey);
        CObj.Add('actVal', FNodes[I].Choices[J].ActionValue);
        ChoicesArr.Add(CObj);
      end;
      NObj.Add('choices', ChoicesArr);
      NodesArr.Add(NObj);
    end;
    RootObj.Add('nodes', NodesArr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleDialogueTree.SetDialogueJson(const Value: String);
var
  Data: TJSONData;
  RootObj, NObj, CObj: TJSONObject;
  NodesArr, ChoicesArr: TJSONArray;
  I, J, NIdx: Integer;
begin
  FNodes := nil;
  if Trim(Value) = '' then
    Exit;

  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then
      Exit;

    RootObj := TJSONObject(Data);
    NodesArr := RootObj.Find('nodes', jtArray) as TJSONArray;
    if NodesArr = nil then
      Exit;

    for I := 0 to NodesArr.Count - 1 do
      if NodesArr.Items[I] is TJSONObject then
      begin
        NObj := TJSONObject(NodesArr.Items[I]);
        NIdx := AddNode(
          NObj.Get('id', ''),
          NObj.Get('speaker', FDefaultSpeaker),
          NObj.Get('text', ''),
          NObj.Get('loc', ''),
          NObj.Get('x', 60.0),
          NObj.Get('y', 60.0));
        if NIdx >= 0 then
        begin
          FNodes[NIdx].PortraitKey := NObj.Get('portrait', '');
          FNodes[NIdx].VoiceEventKey := NObj.Get('voice', '');
          ChoicesArr := NObj.Find('choices', jtArray) as TJSONArray;
          if ChoicesArr <> nil then
            for J := 0 to ChoicesArr.Count - 1 do
              if ChoicesArr.Items[J] is TJSONObject then
              begin
                CObj := TJSONObject(ChoicesArr.Items[J]);
                AddChoice(
                  FNodes[NIdx].NodeId,
                  CObj.Get('id', ''),
                  CObj.Get('text', ''),
                  CObj.Get('target', ''),
                  CObj.Get('loc', ''),
                  NameToConditionOp(CObj.Get('condOp', 'None')),
                  CObj.Get('condKey', ''),
                  CObj.Get('condVal', ''),
                  NameToActionKind(CObj.Get('actKind', 'None')),
                  CObj.Get('actKey', ''),
                  CObj.Get('actVal', ''));
              end;
        end;
      end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleDialogueTree.DialogueSummaryBadge: String;
begin
  Result := Format('[Dialogue:%d nodes]', [Length(FNodes)]);
end;

{ TCastleNpcDialogueBehavior ------------------------------------------------- }

constructor TCastleNpcDialogueBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNpcDisplayName := 'Villager';
  FDialogueTree := nil;
  FInteractionRadius := DefaultInteractionRadius;
  FShowSpeechIndicatorInViewport := true;
end;

destructor TCastleNpcDialogueBehavior.Destroy;
begin
  SetDialogueTree(nil);
  inherited;
end;

procedure TCastleNpcDialogueBehavior.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FDialogueTree) then
    FDialogueTree := nil;
end;

procedure TCastleNpcDialogueBehavior.SetDialogueTree(
  const Value: TCastleDialogueTree);
begin
  if FDialogueTree <> Value then
  begin
    if FDialogueTree <> nil then
      FDialogueTree.RemoveFreeNotification(Self);
    FDialogueTree := Value;
    if FDialogueTree <> nil then
      FDialogueTree.FreeNotification(Self);
  end;
end;

procedure TCastleNpcDialogueBehavior.SetInteractionRadius(const Value: Single);
begin
  FInteractionRadius := Max(0.25, Value);
end;

function TCastleNpcDialogueBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'NpcDisplayName', 'DialogueTree', 'InteractionRadius',
       'ShowSpeechIndicatorInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleNpcDialogueBehavior.NpcDialogueBadge: String;
begin
  if FDialogueTree <> nil then
    Result := Format('[NPC:%s -> %s]', [FNpcDisplayName, FDialogueTree.Name])
  else
    Result := Format('[NPC:%s (unassigned)]', [FNpcDisplayName]);
end;

initialization
  RegisterSerializableComponent(TCastleDialogueTree,
    ['Narrative & Quests', 'Dialogue Tree']);
  RegisterSerializableComponent(TCastleQuestTracker,
    ['Narrative & Quests', 'Quest Tracker']);
  RegisterSerializableComponent(TCastleNpcDialogueBehavior,
    ['Narrative & Quests', 'NPC Dialogue Behavior']);
end.
