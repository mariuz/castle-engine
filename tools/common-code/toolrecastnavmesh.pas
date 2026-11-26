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

{ Stateless scene authoring, multi-floor 3D Recast NavMesh auditor, and
  ANavLinkProxy pathfinding report helper (@link(TRecastNavMeshHelper),
  @link(TRecastSceneAudit))
  (Phase 393 — UE 5.5 ANavMeshBoundsVolume & ANavLinkProxy Parity + 36th MCP Tool). }
unit ToolRecastNavMesh;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleRecastNavMesh;

type
  { Scene-wide 3D Recast NavMesh & NavLinkProxy audit summary. }
  TRecastSceneAudit = record
    NavVolumeCount: Integer;
    TotalPolys: Integer;
    TotalNavTriangles: Integer;
    TotalNavLinks: Integer;
    TotalStackedFloorPairs: Integer;
    TotalWalkableAreaM2: Single;
  end;

  { Scene spawner, 3D path solver wrapper, and Markdown report generator. }
  TRecastNavMeshHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectRecastNavMeshes(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstRecastNavMesh(
      const ADesignRoot: TComponent): TCastleRecastNavMesh; static;
    class function FindRecastNavMeshByName(
      const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleRecastNavMesh; static;

    class function SpawnRecastPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TRecastNavPreset;
      const AWorldPos: TVector3): TCastleRecastNavMesh; static;

    class function AuditRecastNavMeshesInDesign(
      const ADesignRoot: TComponent): TRecastSceneAudit; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const AActiveNav: TCastleRecastNavMesh): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TRecastNavMeshHelper.FindParentViewportItems(
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

class procedure TRecastNavMeshHelper.CollectRecastNavMeshes(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleRecastNavMesh) and (AList.IndexOf(C) < 0) then
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

class function TRecastNavMeshHelper.FindFirstRecastNavMesh(
  const ADesignRoot: TComponent): TCastleRecastNavMesh;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectRecastNavMeshes(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleRecastNavMesh(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TRecastNavMeshHelper.FindRecastNavMeshByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleRecastNavMesh;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstRecastNavMesh(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleRecastNavMesh then
      Exit(TCastleRecastNavMesh(Found));
  end;

  L := TList.Create;
  try
    CollectRecastNavMeshes(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleRecastNavMesh(L[I]).Name, AName) then
        Exit(TCastleRecastNavMesh(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TRecastNavMeshHelper.SpawnRecastPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TRecastNavPreset;
  const AWorldPos: TVector3): TCastleRecastNavMesh;
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

  Result := TCastleRecastNavMesh.Create(OwnerToUse);
  case APreset of
    rnpMultiFloorDungeonKeep:    BaseName := 'NavMesh_DungeonKeep3F';
    rnpSteepCanyonParkourLinks:  BaseName := 'NavMesh_CanyonParkour';
  else
    BaseName := 'NavMesh_CitadelBridge';
  end;

  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleRecastNavMesh, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TRecastNavMeshHelper.AuditRecastNavMeshesInDesign(
  const ADesignRoot: TComponent): TRecastSceneAudit;
var
  L: TList;
  Nav: TCastleRecastNavMesh;
  I: Integer;
begin
  Result := Default(TRecastSceneAudit);
  L := TList.Create;
  try
    CollectRecastNavMeshes(ADesignRoot, L);
    Result.NavVolumeCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      Nav := TCastleRecastNavMesh(L[I]);
      Inc(Result.TotalPolys, Length(Nav.Polys));
      Inc(Result.TotalNavTriangles, Nav.TotalNavTriangles);
      Inc(Result.TotalNavLinks, Length(Nav.NavLinks));
      Inc(Result.TotalStackedFloorPairs, Nav.CountStackedMultiFloorPairs);
      Result.TotalWalkableAreaM2 := Result.TotalWalkableAreaM2 + Nav.TotalWalkableAreaM2;
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TRecastNavMeshHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const AActiveNav: TCastleRecastNavMesh): String;
var
  Audit: TRecastSceneAudit;
  SB: TStringBuilder;
  DirStr: String;
  I: Integer;
begin
  Audit := AuditRecastNavMeshesInDesign(ADesignRoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# 3D Polygonal Recast NavMesh & NavLinkProxy Report (Phase 393 — UE 5.5 Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Volumes | `%d` Polygons (`%d` Tris) | `%.1f m^2` Walkable Area | `%d` Stacked Multi-Floor Overlaps | `%d` NavLinks',
      [Audit.NavVolumeCount, Audit.TotalPolys, Audit.TotalNavTriangles,
       Audit.TotalWalkableAreaM2, Audit.TotalStackedFloorPairs, Audit.TotalNavLinks]));

    if AActiveNav <> nil then
    begin
      SB.AppendLine(Format('- **Agent Params (`%s`)**: `Radius=%.2fm` | `Height=%.2fm` | `MaxSlope=%.0f deg` | `MaxStep=%.2fm`',
        [AActiveNav.NavVolumeKey, AActiveNav.AgentRadius, AActiveNav.AgentHeight,
         AActiveNav.AgentMaxSlopeDeg, AActiveNav.AgentMaxStepHeight]));
      SB.AppendLine(Format('- **Active 3D Path**: `Found=%s` | `Distance=%.2fm` | `Waypoints=%d` | `NavLinks Used=%d`',
        [BoolToStr(AActiveNav.LastPath.Found, 'True', 'False'),
         AActiveNav.LastPath.TotalDistanceM,
         Length(AActiveNav.LastPath.Points),
         AActiveNav.LastPath.UsedLinkCount]));
      SB.AppendLine;
      SB.AppendLine('| NavLinkProxy | Direction | Action | Left `(X,Y,Z)` | Right `(X,Y,Z)` | Enabled |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :---: |');
      for I := 0 to High(AActiveNav.NavLinks) do
      begin
        case AActiveNav.NavLinks[I].Direction of
          nldBothWays:        DirStr := 'BothWays (<->)';
          nldLeftToRightOnly: DirStr := 'OneWay (L->R)';
          nldRightToLeftOnly: DirStr := 'OneWay (R->L)';
        end;
        SB.AppendLine(Format('| `%s` | %s | `%s` | `(%.1f, %.1f, %.1f)` | `(%.1f, %.1f, %.1f)` | %s |',
          [AActiveNav.NavLinks[I].LinkName, DirStr, AActiveNav.NavLinks[I].ActionTag,
           AActiveNav.NavLinks[I].LeftPos.X, AActiveNav.NavLinks[I].LeftPos.Y, AActiveNav.NavLinks[I].LeftPos.Z,
           AActiveNav.NavLinks[I].RightPos.X, AActiveNav.NavLinks[I].RightPos.Y, AActiveNav.NavLinks[I].RightPos.Z,
           BoolToStr(AActiveNav.NavLinks[I].Enabled, 'Yes', 'No')]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
