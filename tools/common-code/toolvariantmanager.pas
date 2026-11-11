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

{ Design-time Variant Manager discovery, live baseline-vs-edited property diff
  auto-capture, and Markdown configuration matrix export for
  @link(TCastleVariantSetManager) (Phase 296). }
unit ToolVariantManager;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVariantSet;

type
  TVariantManagerHelper = class
  public
    class function FindManagerInDesign(const ARoot: TComponent): TCastleVariantSetManager;
    class function EnsureManagerInDesign(const ARoot, ADesignOwner: TComponent): TCastleVariantSetManager;

    { Compare a serialized baseline @code(ABaselineJson) (captured via
      @code(ComponentToString(ARoot))) against the live @code(ALiveRoot) and
      automatically record every changed RTTI / persistent-vector property into
      @code((ASetName, AVariantName)). Returns number of captured differences. }
    class function CaptureHierarchyDifferenceIntoVariant(
      const ABaselineJson: String;
      const ALiveRoot: TComponent;
      const AManager: TCastleVariantSetManager;
      const ASetName, AVariantName: String): Integer;

    { Export a Markdown configuration matrix of all variant sets, variants,
      and property bindings. }
    class function FormatVariantManagerMarkdown(const ARoot: TComponent): String;
  end;

implementation

uses
  StrUtils,
  CastleClassUtils, CastleComponentSerialize,
  CastleTransform, CastleUIControls, CastleViewport;

const
  DiffTrackedPropertyPaths: array [0..22] of String = (
    'Exists',
    'TranslationPersistent.X',
    'TranslationPersistent.Y',
    'TranslationPersistent.Z',
    'RotationPersistent.X',
    'RotationPersistent.Y',
    'RotationPersistent.Z',
    'RotationPersistent.W',
    'ScalePersistent.X',
    'ScalePersistent.Y',
    'ScalePersistent.Z',
    'Intensity',
    'ColorPersistent.Red',
    'ColorPersistent.Green',
    'ColorPersistent.Blue',
    'Caption',
    'FontSize',
    'Url',
    'ExposureEV',
    'Contrast',
    'Saturation',
    'VignetteIntensity',
    'Shadows'
  );

function ProposeUniqueVarMgrName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

{ TVariantManagerHelper ------------------------------------------------------ }

class function TVariantManagerHelper.FindManagerInDesign(
  const ARoot: TComponent): TCastleVariantSetManager;
var
  I: Integer;
  CC: TCastleComponent;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleVariantSetManager then
    Exit(TCastleVariantSetManager(ARoot));

  if ARoot is TCastleComponent then
  begin
    CC := TCastleComponent(ARoot);
    for I := 0 to CC.NonVisualComponentsCount - 1 do
      if CC.NonVisualComponents[I] is TCastleVariantSetManager then
        Exit(TCastleVariantSetManager(CC.NonVisualComponents[I]));
  end;

  if ARoot.Owner <> nil then
    for I := 0 to ARoot.Owner.ComponentCount - 1 do
      if ARoot.Owner.Components[I] is TCastleVariantSetManager then
        Exit(TCastleVariantSetManager(ARoot.Owner.Components[I]));
end;

class function TVariantManagerHelper.EnsureManagerInDesign(
  const ARoot, ADesignOwner: TComponent): TCastleVariantSetManager;
var
  OwnerToUse: TComponent;
begin
  Result := FindManagerInDesign(ARoot);
  if Result <> nil then
    Exit;
  if ARoot = nil then
    Exit(nil);

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastleVariantSetManager.Create(OwnerToUse);
  Result.Name := ProposeUniqueVarMgrName(OwnerToUse, 'VariantSetManager');
  if ARoot is TCastleComponent then
    TCastleComponent(ARoot).AddNonVisualComponent(Result);
end;

class function TVariantManagerHelper.CaptureHierarchyDifferenceIntoVariant(
  const ABaselineJson: String;
  const ALiveRoot: TComponent;
  const AManager: TCastleVariantSetManager;
  const ASetName, AVariantName: String): Integer;
var
  TempOwner: TComponent;
  BaseRoot: TComponent;
  Visited: array of TComponent;
  CapturedCount: Integer;

  function MarkSeen(const C: TComponent): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(Visited) do
      if Visited[K] = C then
        Exit(false);
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := C;
    Result := true;
  end;

  procedure CompareNode(const ALiveComp: TComponent);
  var
    I, P: Integer;
    BaseComp: TComponent;
    BaseVal, LiveVal: String;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (ALiveComp = nil) or (csTransient in ALiveComp.ComponentStyle) or
       (ALiveComp is TCastleVariantSetManager) or (not MarkSeen(ALiveComp)) then
      Exit;

    if ALiveComp.Name <> '' then
    begin
      BaseComp := TCastleVariantSetManager.FindComponentInHierarchy(BaseRoot, ALiveComp.Name);
      if BaseComp <> nil then
        for P := Low(DiffTrackedPropertyPaths) to High(DiffTrackedPropertyPaths) do
        begin
          LiveVal := TCastleVariantSetManager.ReadPropertyPathAsJson(
            ALiveComp, DiffTrackedPropertyPaths[P]);
          if LiveVal = '' then
            Continue;
          BaseVal := TCastleVariantSetManager.ReadPropertyPathAsJson(
            BaseComp, DiffTrackedPropertyPaths[P]);
          if BaseVal <> LiveVal then
          begin
            AManager.SetVariantBinding(ASetName, AVariantName,
              ALiveComp.Name, DiffTrackedPropertyPaths[P], LiveVal);
            Inc(CapturedCount);
          end;
        end;
    end;

    if ALiveComp is TCastleTransform then
    begin
      T := TCastleTransform(ALiveComp);
      for I := 0 to T.Count - 1 do
        CompareNode(T[I]);
    end else
    if ALiveComp is TCastleUserInterface then
    begin
      if ALiveComp is TCastleViewport then
      begin
        VP := TCastleViewport(ALiveComp);
        if VP.Items <> nil then
          CompareNode(VP.Items);
      end;
      UI := TCastleUserInterface(ALiveComp);
      for I := 0 to UI.ControlsCount - 1 do
        CompareNode(UI.Controls[I]);
    end;
  end;

begin
  Result := 0;
  if (Trim(ABaselineJson) = '') or (ALiveRoot = nil) or (AManager = nil) then
    Exit;

  TempOwner := TComponent.Create(nil);
  try
    BaseRoot := StringToComponent(ABaselineJson, TempOwner);
    if BaseRoot = nil then
      Exit;
    CapturedCount := 0;
    SetLength(Visited, 0);
    CompareNode(ALiveRoot);
    Result := CapturedCount;
  finally
    FreeAndNil(TempOwner);
  end;
end;

class function TVariantManagerHelper.FormatVariantManagerMarkdown(
  const ARoot: TComponent): String;
var
  Mgr: TCastleVariantSetManager;
  SB: TStringBuilder;
  S, V, B: Integer;
  Grp: TVariantSetGroup;
  Opt: TVariantOption;
begin
  Mgr := FindManagerInDesign(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Scene Variant Manager Configuration Report');
    SB.AppendLine;
    if Mgr = nil then
    begin
      SB.AppendLine('_No `TCastleVariantSetManager` present in design._');
      Exit(SB.ToString);
    end;

    SB.AppendLine(Format('- **Variant Sets**: `%d`', [Mgr.SetCount]));
    SB.AppendLine;
    for S := 0 to Mgr.SetCount - 1 do
    begin
      Grp := Mgr.GetSet(S);
      SB.AppendLine(Format('## Variant Set: `%s` (Active: `%s`)',
        [Grp.SetName, IfThen(Grp.ActiveVariantName <> '', Grp.ActiveVariantName, 'none')]));
      SB.AppendLine;
      for V := 0 to High(Grp.Variants) do
      begin
        Opt := Grp.Variants[V];
        SB.AppendLine(Format('### Variant `%s` (%d bindings)',
          [Opt.VariantName, Length(Opt.Bindings)]));
        for B := 0 to High(Opt.Bindings) do
          SB.AppendLine(Format('- `%s.%s` = `%s`',
            [Opt.Bindings[B].ComponentName, Opt.Bindings[B].PropertyPath,
             Opt.Bindings[B].ValueJson]));
        SB.AppendLine;
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
