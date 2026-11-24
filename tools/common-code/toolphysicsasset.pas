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

{ Stateless scene authoring, ragdoll poke driver, and diagnostic auditor for the
  Unreal Engine 5.5-style Physics Asset Editor (PhAT)
  (@link(TPhysicsAssetHelper), @link(TPhysicsAssetAuditReport))
  (Phase 388 — UE 5.5 UPhysicsAsset Parity + 31st MCP Tool). }
unit ToolPhysicsAsset;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastlePhysicsAsset;

type
  { Summary audit across all @link(TCastlePhysicsAsset) components in a design. }
  TPhysicsAssetAuditReport = record
    AssetCount: Integer;
    TotalBodies: Integer;
    TotalConstraints: Integer;
    TotalDisabledPairs: Integer;
    TotalMassKg: Single;
    MaxConeViolationDeg: Single;
  end;

  { Scene spawner, batch PhAT auditor, and Markdown report builder. }
  TPhysicsAssetHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectPhysicsAssets(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstPhysicsAsset(const ADesignRoot: TComponent): TCastlePhysicsAsset; static;
    class function FindPhysicsAssetByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastlePhysicsAsset; static;

    class function SpawnPhysicsAssetPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TPhAtAssetPreset;
      const AWorldPos: TVector3): TCastlePhysicsAsset; static;

    class function AuditPhysicsAssetsInDesign(
      const ADesignRoot: TComponent): TPhysicsAssetAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedAsset: TCastlePhysicsAsset): String; static;
  end;

implementation

uses
  Math, CastleUtils, CastleClassUtils, CastleUIControls;

class function TPhysicsAssetHelper.FindParentViewportItems(
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

class procedure TPhysicsAssetHelper.CollectPhysicsAssets(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastlePhysicsAsset) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

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
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class function TPhysicsAssetHelper.FindFirstPhysicsAsset(
  const ADesignRoot: TComponent): TCastlePhysicsAsset;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectPhysicsAssets(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastlePhysicsAsset(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TPhysicsAssetHelper.FindPhysicsAssetByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastlePhysicsAsset;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstPhysicsAsset(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastlePhysicsAsset then
      Exit(TCastlePhysicsAsset(Found));
  end;

  L := TList.Create;
  try
    CollectPhysicsAssets(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastlePhysicsAsset(L[I]).Name, AName) then
        Exit(TCastlePhysicsAsset(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TPhAtAssetPreset;
  const AWorldPos: TVector3): TCastlePhysicsAsset;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastlePhysicsAsset.Create(ADesignOwner);
  case APreset of
    papKinematicPinnedUpperBodyTest: BaseName := 'PA_PinnedHangingRagdoll';
    papHeavyArmoredBruteRagdoll:     BaseName := 'PA_HeavyArmoredBrute';
  else
    BaseName := 'PA_HumanoidRagdoll';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastlePhysicsAsset, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TPhysicsAssetHelper.AuditPhysicsAssetsInDesign(
  const ADesignRoot: TComponent): TPhysicsAssetAuditReport;
var
  L: TList;
  PA: TCastlePhysicsAsset;
  I: Integer;
begin
  Result := Default(TPhysicsAssetAuditReport);
  L := TList.Create;
  try
    CollectPhysicsAssets(ADesignRoot, L);
    Result.AssetCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      PA := TCastlePhysicsAsset(L[I]);
      Inc(Result.TotalBodies, Length(PA.Bodies));
      Inc(Result.TotalConstraints, Length(PA.Constraints));
      Inc(Result.TotalDisabledPairs, PA.DisabledPairCount);
      Result.TotalMassKg := Result.TotalMassKg + PA.TotalMassKg;
      Result.MaxConeViolationDeg := Max(
        Result.MaxConeViolationDeg, PA.MaxConstraintConeViolationDeg);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TPhysicsAssetHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedAsset: TCastlePhysicsAsset): String;
var
  Audit: TPhysicsAssetAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditPhysicsAssetsInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Physics Asset Editor (PhAT) Report (Phase 388 — UE 5.5 UPhysicsAsset Parity)');
    SB.Add('');
    SB.Add(Format('- **Physics Assets**: `%d` | **Bodies**: `%d` | **Constraints**: `%d`',
      [Audit.AssetCount, Audit.TotalBodies, Audit.TotalConstraints]));
    SB.Add(Format('- **Disabled Pairs**: `%d` | **Total Mass**: `%.2f kg` | **Max Cone Violation**: `%.3f deg`',
      [Audit.TotalDisabledPairs, Audit.TotalMassKg, Audit.MaxConeViolationDeg]));
    if ASelectedAsset <> nil then
    begin
      SB.Add('');
      SB.Add('## Active Physics Asset: `' + ASelectedAsset.Name + '` ' + ASelectedAsset.PhAtSummaryBadge);
      for I := 0 to High(ASelectedAsset.Bodies) do
        SB.Add(Format('- Body **%s** (`%s`, `%s`) Mass=`%.2f kg` Pos=`(%.2f, %.2f, %.2f)`',
          [ASelectedAsset.Bodies[I].BodyName,
           TCastlePhysicsAsset.ShapeKindTitle(ASelectedAsset.Bodies[I].ShapeKind),
           BoolToStr(ASelectedAsset.Bodies[I].PhysicsType = pptKinematic, 'Kinematic', 'Simulated'),
           ASelectedAsset.Bodies[I].MassKg,
           ASelectedAsset.Bodies[I].Position.X,
           ASelectedAsset.Bodies[I].Position.Y,
           ASelectedAsset.Bodies[I].Position.Z]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
