{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless scene helper, preset spawner, Interchange pipeline auditor &
  Markdown report generator for Interchange Asset Import Pipeline & Reimport
  Rules (Phase 398). }
unit ToolInterchange;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleClassUtils, CastleVectors, CastleTransform, CastleViewport,
  CastleUIControls, CastleInterchange;

type
  TInterchangeSceneAudit = record
    PipelineCount: Integer;
    TotalTranslatedAssets: Integer;
    TotalVisualTriangles: Integer;
    TotalExtractedColliders: Integer;
    TotalExtractedSockets: Integer;
    TotalLockedOverrides: Integer;
  end;

  TInterchangeHelper = class
  public
    class procedure CollectInterchangePipelines(const ARoot: TComponent;
      const AList: TList); static;
    class function FindFirstInterchangePipeline(const ARoot: TComponent): TCastleInterchangePipeline; static;
    class function FindInterchangePipelineByName(const ARoot, AOwner: TComponent;
      const AName: String): TCastleInterchangePipeline; static;

    class function SpawnInterchangePresetInDesign(const ARoot, AOwner: TComponent;
      const APreset: TInterchangePipelinePreset;
      const APosition: TVector3): TCastleInterchangePipeline; static;

    class function AuditInterchangeInDesign(const ARoot: TComponent): TInterchangeSceneAudit; static;
    class function GenerateMarkdownReport(const ARoot: TComponent;
      const ActivePipe: TCastleInterchangePipeline): String; static;
  end;

implementation

class procedure TInterchangeHelper.CollectInterchangePipelines(
  const ARoot: TComponent; const AList: TList);

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleInterchangePipeline) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Traverse(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Traverse(T[I]);
    end;
  end;

begin
  if (ARoot = nil) or (AList = nil) then Exit;
  Traverse(ARoot);
end;

class function TInterchangeHelper.FindFirstInterchangePipeline(
  const ARoot: TComponent): TCastleInterchangePipeline;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectInterchangePipelines(ARoot, L);
    if L.Count > 0 then
      Result := TCastleInterchangePipeline(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TInterchangeHelper.FindInterchangePipelineByName(
  const ARoot, AOwner: TComponent; const AName: String): TCastleInterchangePipeline;
var
  L: TList;
  I: Integer;
  C: TComponent;
begin
  if Trim(AName) = '' then
    Exit(FindFirstInterchangePipeline(ARoot));

  Result := nil;
  if AOwner <> nil then
  begin
    C := AOwner.FindComponent(AName);
    if C is TCastleInterchangePipeline then
      Exit(TCastleInterchangePipeline(C));
  end;

  L := TList.Create;
  try
    CollectInterchangePipelines(ARoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleInterchangePipeline(L[I]).Name, AName) then
        Exit(TCastleInterchangePipeline(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TInterchangeHelper.SpawnInterchangePresetInDesign(
  const ARoot, AOwner: TComponent;
  const APreset: TInterchangePipelinePreset;
  const APosition: TVector3): TCastleInterchangePipeline;
var
  ParentItems: TCastleTransform;
  VP: TCastleViewport;
  I: Integer;
  BaseName: String;
begin
  Result := nil;
  if ARoot = nil then Exit;

  ParentItems := nil;
  if ARoot is TCastleViewport then
    ParentItems := TCastleViewport(ARoot).Items
  else if ARoot is TCastleTransform then
    ParentItems := TCastleTransform(ARoot)
  else if ARoot is TCastleUserInterface then
  begin
    for I := 0 to TCastleUserInterface(ARoot).ControlsCount - 1 do
      if TCastleUserInterface(ARoot).Controls[I] is TCastleViewport then
      begin
        VP := TCastleViewport(TCastleUserInterface(ARoot).Controls[I]);
        ParentItems := VP.Items;
        Break;
      end;
  end;
  if ParentItems = nil then Exit;

  Result := TCastleInterchangePipeline.Create(AOwner);
  case APreset of
    ippModularArchitectureProps:     BaseName := 'Interchange_FortressGate';
    ippSkeletalHeroRigAndAnimations: BaseName := 'Interchange_PaladinRig';
    ippFoliageWindAndBillboardLod:   BaseName := 'Interchange_OakCanopy';
  end;
  if AOwner <> nil then
    Result.Name := ProposeComponentName(TCastleInterchangePipeline, AOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Preset := APreset;
  Result.Translation := APosition;
  ParentItems.Add(Result);
end;

class function TInterchangeHelper.AuditInterchangeInDesign(
  const ARoot: TComponent): TInterchangeSceneAudit;
var
  L: TList;
  I: Integer;
  P: TCastleInterchangePipeline;
begin
  Result := Default(TInterchangeSceneAudit);
  L := TList.Create;
  try
    CollectInterchangePipelines(ARoot, L);
    Result.PipelineCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      P := TCastleInterchangePipeline(L[I]);
      Inc(Result.TotalTranslatedAssets, P.TranslatedAssetCount);
      Inc(Result.TotalVisualTriangles, P.TotalVisualTriangles);
      Inc(Result.TotalExtractedColliders, P.ExtractedColliderCount);
      Inc(Result.TotalExtractedSockets, P.ExtractedSocketCount);
      Inc(Result.TotalLockedOverrides, P.LockedSlotOverrideCount);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TInterchangeHelper.GenerateMarkdownReport(
  const ARoot: TComponent; const ActivePipe: TCastleInterchangePipeline): String;
var
  Audit: TInterchangeSceneAudit;
  SB: TStringBuilder;
  I: Integer;
  A: TInterchangeTranslatedAsset;
begin
  Audit := AuditInterchangeInDesign(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Interchange Asset Import Pipeline Report (Phase 398 — UE 5.5 UInterchangeManager Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Pipelines | `%d` Translated Assets | `%d` Colliders | `%d` Sockets | `%d` Preserved Overrides',
      [Audit.PipelineCount, Audit.TotalTranslatedAssets,
       Audit.TotalExtractedColliders, Audit.TotalExtractedSockets,
       Audit.TotalLockedOverrides]));
    if ActivePipe <> nil then
    begin
      SB.AppendLine(Format('- **Active Source**: `%s` (Rev `v%d` | `%s` | `%s`)',
        [ActivePipe.SourceFileUrl, ActivePipe.ReimportRevision,
         InterchangeAxisDisplayName(ActivePipe.SourceAxisSystem),
         InterchangeUnitDisplayName(ActivePipe.SourceUnit)]));
      SB.AppendLine;
      SB.AppendLine('| Translated Asset | UE Class | Pipeline Output & Color-Space / Override Rules |');
      SB.AppendLine('| :--- | :--- | :--- |');
      for I := 0 to ActivePipe.TranslatedAssetCount - 1 do
      begin
        A := ActivePipe.TranslatedAssets[I];
        SB.AppendLine(Format('| `%s` | `%s` | `%s` |',
          [A.AssetName, A.AssetClass, A.Notes]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
