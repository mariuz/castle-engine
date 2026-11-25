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

{ Stateless scene authoring, Parent->Child Material Instance hierarchy builder,
  and global Material Parameter Collection (MPC) broadcast helper
  (@link(TMaterialInstanceHelper), @link(TMaterialInstanceAuditReport))
  (Phase 391 — UE 5.5 UMaterialInstanceConstant & MPC Parity + 34th MCP Tool). }
unit ToolMaterialInstance;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport, CastleScene,
  CastleMaterialInstance;

type
  { Scene-wide Material Instance & MPC audit metrics. }
  TMaterialInstanceAuditReport = record
    MaterialInstanceCount: Integer;
    MpcCount: Integer;
    ParentLinkedInstanceCount: Integer;
    TotalOverriddenSlots: Integer;
    TotalShaderPermutations: Integer;
  end;

  { Scene spawner, MPC broadcaster, and Markdown report generator for Phase 391. }
  TMaterialInstanceHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectMaterialInstances(const ADesignRoot: TComponent;
      const AList: TList); static;
    class procedure CollectMpcs(const ADesignRoot: TComponent;
      const AList: TList); static;

    class function FindFirstMaterialInstance(
      const ADesignRoot: TComponent): TCastleMaterialInstance; static;
    class function FindMaterialInstanceByName(
      const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleMaterialInstance; static;
    class function FindFirstMpc(
      const ADesignRoot: TComponent): TCastleMaterialParameterCollection; static;

    { Spawns a complete 3-actor Parent->Child Material Instance + Global MPC showcase:
      - MPC_GlobalEnvironment
      - StoneParentSphere (MI_CastleStone_Parent)
      - MossyChildSphere (MI_MossyDungeon_Child -> ParentInstance = MI_CastleStone_Parent)
      - SciFiTrimSphere (MI_SciFiTitanium_Child) }
    class function SpawnParentChildMpcShowcaseInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      out OutMpc: TCastleMaterialParameterCollection;
      out OutParentMi, OutChildMi: TCastleMaterialInstance): Integer; static;

    { Broadcasts a global MPC preset or scalar update to all subscribed Material Instances }
    class function BroadcastMpcPresetInDesign(
      const ADesignRoot: TComponent;
      const APreset: TMpcEnvironmentPreset): Integer; static;

    class function RefreshAllMaterialInstancesInDesign(
      const ADesignRoot: TComponent): Integer; static;

    class function AuditMaterialInstancesInDesign(
      const ADesignRoot: TComponent): TMaterialInstanceAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const AActiveMi: TCastleMaterialInstance;
      const AActiveMpc: TCastleMaterialParameterCollection): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TMaterialInstanceHelper.FindParentViewportItems(
  const ADesignRoot: TComponent): TCastleTransform;

  function SearchVp(const C: TComponent): TCastleViewport;
  var
    UI: TCastleUserInterface;
    I: Integer;
  begin
    Result := nil;
    if C = nil then Exit;
    if C is TCastleViewport then Exit(TCastleViewport(C));
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := SearchVp(UI.Controls[I]);
        if Result <> nil then Exit;
      end;
    end;
  end;

var
  VP: TCastleViewport;
begin
  Result := nil;
  if ADesignRoot = nil then Exit;
  if ADesignRoot is TCastleTransform then
    Exit(TCastleTransform(ADesignRoot));
  VP := SearchVp(ADesignRoot);
  if VP <> nil then
    Result := VP.Items;
end;

class procedure TMaterialInstanceHelper.CollectMaterialInstances(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleMaterialInstance) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Scan(TCastleComponent(C).NonVisualComponents[I]);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Scan(UI.Controls[I]);
    end;
    if C is TCastleViewport then
      Scan(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Scan(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
    for I := 0 to C.ComponentCount - 1 do
      if C.Components[I] is TCastleMaterialInstance then
        Scan(C.Components[I]);
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class procedure TMaterialInstanceHelper.CollectMpcs(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleMaterialParameterCollection) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Scan(TCastleComponent(C).NonVisualComponents[I]);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Scan(UI.Controls[I]);
    end;
    if C is TCastleViewport then
    begin
      for I := 0 to C.ComponentCount - 1 do
        Scan(C.Components[I]);
      Scan(TCastleViewport(C).Items);
    end else
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
    for I := 0 to C.ComponentCount - 1 do
      if C.Components[I] is TCastleMaterialParameterCollection then
        Scan(C.Components[I]);
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class function TMaterialInstanceHelper.FindFirstMaterialInstance(
  const ADesignRoot: TComponent): TCastleMaterialInstance;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectMaterialInstances(ADesignRoot, L);
    { Prefer a child instance with a ParentInstance if present so Studio opens on the richest view }
    if L.Count > 1 then
    begin
      if TCastleMaterialInstance(L[1]).ParentInstance <> nil then
        Exit(TCastleMaterialInstance(L[1]));
    end;
    if L.Count > 0 then
      Result := TCastleMaterialInstance(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TMaterialInstanceHelper.FindMaterialInstanceByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleMaterialInstance;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstMaterialInstance(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleMaterialInstance then
      Exit(TCastleMaterialInstance(Found));
  end;

  L := TList.Create;
  try
    CollectMaterialInstances(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleMaterialInstance(L[I]).Name, AName) then
        Exit(TCastleMaterialInstance(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TMaterialInstanceHelper.FindFirstMpc(
  const ADesignRoot: TComponent): TCastleMaterialParameterCollection;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectMpcs(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleMaterialParameterCollection(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TMaterialInstanceHelper.SpawnParentChildMpcShowcaseInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  out OutMpc: TCastleMaterialParameterCollection;
  out OutParentMi, OutChildMi: TCastleMaterialInstance): Integer;
var
  ParentT: TCastleTransform;
  SphereParent, SphereChild, SphereTrim: TCastleSphere;
  TrimMi: TCastleMaterialInstance;
  OwnerToUse: TComponent;
begin
  Result := 0;
  OutMpc := nil;
  OutParentMi := nil;
  OutChildMi := nil;

  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  OwnerToUse := ADesignOwner;
  if OwnerToUse = nil then
    OwnerToUse := ADesignRoot;

  { 1. Reuse or create Global MPC }
  OutMpc := FindFirstMpc(ADesignRoot);
  if OutMpc = nil then
  begin
    OutMpc := TCastleMaterialParameterCollection.Create(OwnerToUse);
    if ADesignOwner <> nil then
      OutMpc.Name := ProposeComponentName(TCastleMaterialParameterCollection, ADesignOwner, 'MPC_GlobalEnvironment')
    else
      OutMpc.Name := 'MPC_GlobalEnvironment';
    OutMpc.ApplyPreset(mpcpMonsoonRainStorm);
    ParentT.AddNonVisualComponent(OutMpc);
  end;

  { 2. Parent Material Instance Sphere }
  SphereParent := TCastleSphere.Create(OwnerToUse);
  if ADesignOwner <> nil then
    SphereParent.Name := ProposeComponentName(TCastleSphere, ADesignOwner, 'Sphere_StoneParent')
  else
    SphereParent.Name := 'Sphere_StoneParent';
  SphereParent.Radius := 1.1;
  SphereParent.Translation := Vector3(-2.8, 1.1, 0.0);
  ParentT.Add(SphereParent);

  OutParentMi := TCastleMaterialInstance.Create(OwnerToUse);
  if ADesignOwner <> nil then
    OutParentMi.Name := ProposeComponentName(TCastleMaterialInstance, ADesignOwner, 'MI_CastleStone_Parent')
  else
    OutParentMi.Name := 'MI_CastleStone_Parent';
  OutParentMi.ParameterCollection := OutMpc;
  SphereParent.AddBehavior(OutParentMi);
  OutParentMi.ApplyPreset(mipWeatheredCastleStoneParent);
  Inc(Result);

  { 3. Child Material Instance Sphere inheriting from MI_CastleStone_Parent }
  SphereChild := TCastleSphere.Create(OwnerToUse);
  if ADesignOwner <> nil then
    SphereChild.Name := ProposeComponentName(TCastleSphere, ADesignOwner, 'Sphere_MossyChild')
  else
    SphereChild.Name := 'Sphere_MossyChild';
  SphereChild.Radius := 1.1;
  SphereChild.Translation := Vector3(0.0, 1.1, 0.0);
  ParentT.Add(SphereChild);

  OutChildMi := TCastleMaterialInstance.Create(OwnerToUse);
  if ADesignOwner <> nil then
    OutChildMi.Name := ProposeComponentName(TCastleMaterialInstance, ADesignOwner, 'MI_MossyDungeon_Child')
  else
    OutChildMi.Name := 'MI_MossyDungeon_Child';
  OutChildMi.ParentInstance := OutParentMi;
  OutChildMi.ParameterCollection := OutMpc;
  SphereChild.AddBehavior(OutChildMi);
  OutChildMi.ApplyPreset(mipMossyDungeonChild);
  Inc(Result);

  { 4. Sci-Fi Emissive Trim Instance Sphere }
  SphereTrim := TCastleSphere.Create(OwnerToUse);
  if ADesignOwner <> nil then
    SphereTrim.Name := ProposeComponentName(TCastleSphere, ADesignOwner, 'Sphere_SciFiTrim')
  else
    SphereTrim.Name := 'Sphere_SciFiTrim';
  SphereTrim.Radius := 1.1;
  SphereTrim.Translation := Vector3(2.8, 1.1, 0.0);
  ParentT.Add(SphereTrim);

  TrimMi := TCastleMaterialInstance.Create(OwnerToUse);
  if ADesignOwner <> nil then
    TrimMi.Name := ProposeComponentName(TCastleMaterialInstance, ADesignOwner, 'MI_SciFiTitanium_Trim')
  else
    TrimMi.Name := 'MI_SciFiTitanium_Trim';
  TrimMi.ParameterCollection := OutMpc;
  SphereTrim.AddBehavior(TrimMi);
  TrimMi.ApplyPreset(mipSciFiTitaniumTrim);
  Inc(Result);
end;

class function TMaterialInstanceHelper.BroadcastMpcPresetInDesign(
  const ADesignRoot: TComponent;
  const APreset: TMpcEnvironmentPreset): Integer;
var
  MpcList: TList;
  I: Integer;
begin
  MpcList := TList.Create;
  try
    CollectMpcs(ADesignRoot, MpcList);
    for I := 0 to MpcList.Count - 1 do
      TCastleMaterialParameterCollection(MpcList[I]).ApplyPreset(APreset);
  finally
    FreeAndNil(MpcList);
  end;
  Result := RefreshAllMaterialInstancesInDesign(ADesignRoot);
end;

class function TMaterialInstanceHelper.RefreshAllMaterialInstancesInDesign(
  const ADesignRoot: TComponent): Integer;
var
  MiList: TList;
  I: Integer;
begin
  Result := 0;
  MiList := TList.Create;
  try
    CollectMaterialInstances(ADesignRoot, MiList);
    Result := MiList.Count;
    for I := 0 to MiList.Count - 1 do
      TCastleMaterialInstance(MiList[I]).SyncToAttachedTransform;
  finally
    FreeAndNil(MiList);
  end;
end;

class function TMaterialInstanceHelper.AuditMaterialInstancesInDesign(
  const ADesignRoot: TComponent): TMaterialInstanceAuditReport;
var
  MiList, MpcList: TList;
  Mi: TCastleMaterialInstance;
  I: Integer;
begin
  Result := Default(TMaterialInstanceAuditReport);
  MiList := TList.Create;
  MpcList := TList.Create;
  try
    CollectMaterialInstances(ADesignRoot, MiList);
    CollectMpcs(ADesignRoot, MpcList);
    Result.MaterialInstanceCount := MiList.Count;
    Result.MpcCount := MpcList.Count;
    for I := 0 to MiList.Count - 1 do
    begin
      Mi := TCastleMaterialInstance(MiList[I]);
      if Mi.ParentInstance <> nil then
        Inc(Result.ParentLinkedInstanceCount);
      Inc(Result.TotalOverriddenSlots, Mi.OverriddenParameterCount);
      Inc(Result.TotalShaderPermutations, Mi.ShaderPermutationsCompiled);
    end;
  finally
    FreeAndNil(MpcList);
    FreeAndNil(MiList);
  end;
end;

class function TMaterialInstanceHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const AActiveMi: TCastleMaterialInstance;
  const AActiveMpc: TCastleMaterialParameterCollection): String;
var
  Rep: TMaterialInstanceAuditReport;
  Surf: TResolvedPbrSurface;
  Slot: TMaterialParameterSlot;
  Src, OvMark: String;
  SB: TStringBuilder;
  I: Integer;
begin
  Rep := AuditMaterialInstancesInDesign(ADesignRoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Material Instance & MPC Report (Phase 391 — UE 5.5 Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Material Instances (`%d` Child Inherited) | `%d` MPCs | `%d` Total Overridden Slots',
      [Rep.MaterialInstanceCount, Rep.ParentLinkedInstanceCount,
       Rep.MpcCount, Rep.TotalOverriddenSlots]));

    if AActiveMpc <> nil then
      SB.AppendLine(Format('- **Active Global MPC**: `%s` (`Wetness=%.2f`, `Snow=%.2f`, `Wind=%.2f`, `Pulse=%.2f`)',
        [AActiveMpc.CollectionKey, AActiveMpc.GlobalWetness,
         AActiveMpc.SnowCoverage, AActiveMpc.WindStrength,
         AActiveMpc.EmissivePulsePhase]));

    if AActiveMi <> nil then
    begin
      Surf := AActiveMi.EvaluateEffectiveSurface(AActiveMpc);
      SB.AppendLine(Format('- **Active Instance Chain**: `%s`', [AActiveMi.HierarchyChainString]));
      SB.AppendLine(Format('- **Resolved PBR Surface**: `RGBA=(%.2f, %.2f, %.2f, %.2f)` | `Metallic=%.2f` | `Roughness=%.2f` | `ClearCoat=%.2f` | `PermMask=%s` (`%d` shader compiles)',
        [Surf.FinalBaseColor.X, Surf.FinalBaseColor.Y, Surf.FinalBaseColor.Z, Surf.FinalBaseColor.W,
         Surf.FinalMetallic, Surf.FinalRoughness, Surf.FinalClearCoat,
         Surf.StaticSwitchMaskHex, Surf.ShaderPermutationsCompiled]));
      SB.AppendLine;
      SB.AppendLine('| Override | Parameter | Kind | Effective Value | Source |');
      SB.AppendLine('| :---: | :--- | :--- | :--- | :--- |');
      for I := 0 to High(AActiveMi.Slots) do
        if AActiveMi.GetEffectiveSlot(AActiveMi.Slots[I].ParamName, Slot, Src) then
        begin
          if AActiveMi.Slots[I].IsOverridden then OvMark := '[x]' else OvMark := '[ ]';
          case Slot.Kind of
            mpkScalar:
              SB.AppendLine(Format('| %s | `%s` | Scalar | `%.2f` | %s |',
                [OvMark, Slot.ParamName, Slot.ScalarValue, Src]));
            mpkVector:
              SB.AppendLine(Format('| %s | `%s` | Vector | `(%.2f, %.2f, %.2f)` | %s |',
                [OvMark, Slot.ParamName, Slot.VectorValue.X, Slot.VectorValue.Y, Slot.VectorValue.Z, Src]));
            mpkTexture:
              SB.AppendLine(Format('| %s | `%s` | Texture | `%s` | %s |',
                [OvMark, Slot.ParamName, Slot.TextureSlot, Src]));
            mpkStaticSwitch:
              SB.AppendLine(Format('| %s | `%s` | StaticSwitch | `%s` | %s |',
                [OvMark, Slot.ParamName, BoolToStr(Slot.SwitchValue, 'True', 'False'), Src]));
          end;
        end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
