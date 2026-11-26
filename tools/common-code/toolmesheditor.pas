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

{ Stateless scene authoring, Socket attachment helper, and V-HACD / MikkTSpace
  mesh audit engine (@link(TMeshEditorHelper), @link(TMeshEditorSceneAudit))
  (Phase 392 — UE 5.5 UStaticMeshEditor & USkeletalMeshEditor Parity + 35th MCP Tool). }
unit ToolMeshEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport, CastleScene,
  CastleMeshEditor;

type
  { Scene-wide Static & Skeletal Mesh Editor audit summary. }
  TMeshEditorSceneAudit = record
    MeshAssetCount: Integer;
    SkeletalMeshCount: Integer;
    TotalSocketCount: Integer;
    TotalConvexHullCount: Integer;
    TotalLod0Triangles: Integer;
  end;

  { Scene spawner, socket prop attacher, and Markdown report builder for Phase 392. }
  TMeshEditorHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectMeshEditorAssets(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstMeshEditorAsset(
      const ADesignRoot: TComponent): TCastleMeshEditorAsset; static;
    class function FindMeshEditorAssetByName(
      const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleMeshEditorAsset; static;

    class function SpawnMeshEditorPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TMeshEditorPreset;
      const AWorldPos: TVector3): TCastleMeshEditorAsset; static;

    { Spawns a visible preview prop box attached directly onto a named Socket }
    class function SpawnPreviewPropOnSocket(
      const AMeshAsset: TCastleMeshEditorAsset;
      const ADesignOwner: TComponent;
      const ASocketName: String): TCastleBox; static;

    class function AuditMeshAssetsInDesign(
      const ADesignRoot: TComponent): TMeshEditorSceneAudit; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const AActiveMesh: TCastleMeshEditorAsset): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TMeshEditorHelper.FindParentViewportItems(
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

class procedure TMeshEditorHelper.CollectMeshEditorAssets(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleMeshEditorAsset) and (AList.IndexOf(C) < 0) then
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

class function TMeshEditorHelper.FindFirstMeshEditorAsset(
  const ADesignRoot: TComponent): TCastleMeshEditorAsset;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectMeshEditorAssets(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleMeshEditorAsset(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TMeshEditorHelper.FindMeshEditorAssetByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleMeshEditorAsset;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstMeshEditorAsset(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleMeshEditorAsset then
      Exit(TCastleMeshEditorAsset(Found));
  end;

  L := TList.Create;
  try
    CollectMeshEditorAssets(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleMeshEditorAsset(L[I]).Name, AName) then
        Exit(TCastleMeshEditorAsset(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TMeshEditorPreset;
  const AWorldPos: TVector3): TCastleMeshEditorAsset;
var
  ParentT: TCastleTransform;
  BaseName: String;
  OwnerToUse: TComponent;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  OwnerToUse := ADesignOwner;
  if OwnerToUse = nil then
    OwnerToUse := ADesignRoot;

  Result := TCastleMeshEditorAsset.Create(OwnerToUse);
  case APreset of
    mepSkeletalHalberdWeapon4Sockets: BaseName := 'SK_RoyalHalberd';
    mepSciFiDefenseTurretMultiPart:   BaseName := 'SM_AegisTurret';
  else
    BaseName := 'SM_GothicArchway';
  end;

  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleMeshEditorAsset, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TMeshEditorHelper.SpawnPreviewPropOnSocket(
  const AMeshAsset: TCastleMeshEditorAsset;
  const ADesignOwner: TComponent;
  const ASocketName: String): TCastleBox;
var
  OwnerToUse: TComponent;
begin
  Result := nil;
  if AMeshAsset = nil then Exit;
  if AMeshAsset.FindSocketIndex(ASocketName) < 0 then Exit;

  OwnerToUse := ADesignOwner;
  if OwnerToUse = nil then
    OwnerToUse := AMeshAsset.Owner;

  Result := TCastleBox.Create(OwnerToUse);
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleBox, ADesignOwner, 'Prop_' + ASocketName)
  else
    Result.Name := 'Prop_' + ASocketName;
  Result.Size := Vector3(0.28, 0.28, 0.28);
  Result.Color := Vector4(1.0, 0.68, 0.20, 1.0);
  if not AMeshAsset.AttachTransformToSocket(Result, ASocketName) then
    FreeAndNil(Result);
end;

class function TMeshEditorHelper.AuditMeshAssetsInDesign(
  const ADesignRoot: TComponent): TMeshEditorSceneAudit;
var
  L: TList;
  M: TCastleMeshEditorAsset;
  I: Integer;
begin
  Result := Default(TMeshEditorSceneAudit);
  L := TList.Create;
  try
    CollectMeshEditorAssets(ADesignRoot, L);
    Result.MeshAssetCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      M := TCastleMeshEditorAsset(L[I]);
      if M.IsSkeletalMesh then
        Inc(Result.SkeletalMeshCount);
      Inc(Result.TotalSocketCount, Length(M.Sockets));
      Inc(Result.TotalConvexHullCount, Length(M.ConvexHulls));
      Inc(Result.TotalLod0Triangles, M.BaseLod0Triangles);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TMeshEditorHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const AActiveMesh: TCastleMeshEditorAsset): String;
var
  Audit: TMeshEditorSceneAudit;
  TanAudit: TMeshTangentAudit;
  SB: TStringBuilder;
  I: Integer;
  DoorwayOpen: Boolean;
begin
  Audit := AuditMeshAssetsInDesign(ADesignRoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Static & Skeletal Mesh Asset Editor Report (Phase 392 — UE 5.5 Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Mesh Assets (`%d` Skeletal) | `%d` Sockets | `%d` Convex Hulls | `%d` LOD0 Triangles',
      [Audit.MeshAssetCount, Audit.SkeletalMeshCount,
       Audit.TotalSocketCount, Audit.TotalConvexHullCount,
       Audit.TotalLod0Triangles]));

    if AActiveMesh <> nil then
    begin
      TanAudit := AActiveMesh.LastTangentAudit;
      DoorwayOpen := not AActiveMesh.PointHitsAnyConvexHull(Vector3(0.0, 1.2, 0.0));
      SB.AppendLine(Format('- **Active Asset**: `%s` (`%s`) | **Convex Volume**: `%.2f m^3` across `%d` Hulls | **Center Walkable Clearance**: `%s`',
        [AActiveMesh.MeshAssetKey,
         BoolToStr(AActiveMesh.IsSkeletalMesh, 'USkeletalMesh', 'UStaticMesh'),
         AActiveMesh.TotalConvexHullVolumeM3,
         Length(AActiveMesh.ConvexHulls),
         BoolToStr(DoorwayOpen, 'OPEN (Clear)', 'BLOCKED')]));
      SB.AppendLine(Format('- **MikkTSpace Tangent Audit**: `%d` Samples | `%d` Hard Seams | `%d` Mirrored (`w=-1`) | `MaxOrthoErr=%.6f` (`%d` Non-Orthogonal)',
        [TanAudit.SampleVertexCount, TanAudit.HardSeamCount,
         TanAudit.MirroredUvVertexCount, TanAudit.MaxOrthogonalityError,
         TanAudit.NonOrthogonalTangentCount]));
      SB.AppendLine;
      SB.AppendLine('| Socket Name | Bone | Local Pos `(X, Y, Z)` | Preview Prop |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to High(AActiveMesh.Sockets) do
        SB.AppendLine(Format('| `%s` | `%s` | `(%.2f, %.2f, %.2f)` | `%s` |',
          [AActiveMesh.Sockets[I].SocketName,
           AActiveMesh.Sockets[I].TargetBoneName,
           AActiveMesh.Sockets[I].BoneRefPos.X + AActiveMesh.Sockets[I].LocalOffset.X,
           AActiveMesh.Sockets[I].BoneRefPos.Y + AActiveMesh.Sockets[I].LocalOffset.Y,
           AActiveMesh.Sockets[I].BoneRefPos.Z + AActiveMesh.Sockets[I].LocalOffset.Z,
           AActiveMesh.Sockets[I].PreviewPropTag]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
