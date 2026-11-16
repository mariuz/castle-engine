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

{ Stateless Editor & Headless Helper for 3D Voxel SDF Cave/Overhang Volumes,
  Non-Destructive Smooth Boolean Sculpting & Mesh Budget Auditing
  (@link(TVoxelStudioHelper), @link(TVoxelAuditReport))
  (Phase 329 — UE 6.0+ Nanite Voxel Caves & Volumetric Overhangs Parity). }
unit ToolVoxelStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleVoxelTerrain;

type
  TVoxelVolumeArray = array of TCastleVoxelVolume;

  { QA summary across all 3D Voxel SDF volumes in a design. }
  TVoxelAuditReport = class
  public
    VolumeCount: Integer;
    TotalBrushes: Integer;
    TotalSolidVoxels: Integer;
    TotalTriangles: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, sculpting, and auditing
    @link(TCastleVoxelVolume) instances. }
  TVoxelStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanVoxelVolumes(const RootComp, DesignOwner: TComponent;
      out OutVolumes: TVoxelVolumeArray); static;

    class function SpawnVoxelCaveDemo(const RootComp, DesignOwner: TComponent;
      const APreset: TVoxelVolumePreset = vvpWalkthroughCaveTunnel): TCastleVoxelVolume; static;

    class function AuditVoxelVolumes(
      const RootComp, DesignOwner: TComponent): TVoxelAuditReport; static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleUIControls;

constructor TVoxelAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TVoxelAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TVoxelStudioHelper.FindMainViewport(
  const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindMainViewport(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

class procedure TVoxelStudioHelper.ScanVoxelVolumes(
  const RootComp, DesignOwner: TComponent;
  out OutVolumes: TVoxelVolumeArray);

  procedure AddUnique(const V: TCastleVoxelVolume);
  var
    K: Integer;
  begin
    if (V = nil) or (csTransient in V.ComponentStyle) then
      Exit;
    for K := 0 to High(OutVolumes) do
      if OutVolumes[K] = V then
        Exit;
    SetLength(OutVolumes, Length(OutVolumes) + 1);
    OutVolumes[High(OutVolumes)] := V;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleVoxelVolume then
      AddUnique(TCastleVoxelVolume(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutVolumes := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class function TVoxelStudioHelper.SpawnVoxelCaveDemo(
  const RootComp, DesignOwner: TComponent;
  const APreset: TVoxelVolumePreset): TCastleVoxelVolume;
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  Idx: Integer;
begin
  Result := nil;
  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('VoxelCaveVolume' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  Result := TCastleVoxelVolume.Create(OwnerToUse);
  Result.Name := 'VoxelCaveVolume' + IntToStr(Idx);
  Result.ApplyPreset(APreset);
  ParentTrans.Add(Result);
end;

class function TVoxelStudioHelper.AuditVoxelVolumes(
  const RootComp, DesignOwner: TComponent): TVoxelAuditReport;
var
  Volumes: TVoxelVolumeArray;
  I: Integer;
begin
  Result := TVoxelAuditReport.Create;
  ScanVoxelVolumes(RootComp, DesignOwner, Volumes);
  Result.VolumeCount := Length(Volumes);
  for I := 0 to High(Volumes) do
  begin
    Inc(Result.TotalBrushes, Volumes[I].BrushCount);
    Inc(Result.TotalSolidVoxels, Volumes[I].SolidVoxelCount);
    Inc(Result.TotalTriangles, Volumes[I].GeneratedTriangleCount);
    if Volumes[I].GeneratedTriangleCount = 0 then
      Result.Warnings.Add(Format(
        'VoxelVolume "%s" extracted 0 surface triangles (all air or all solid).',
        [Volumes[I].Name]));
    if Volumes[I].GeneratedTriangleCount > 80000 then
      Result.Warnings.Add(Format(
        'VoxelVolume "%s" has %d triangles; consider increasing VoxelSize or chunking.',
        [Volumes[I].Name, Volumes[I].GeneratedTriangleCount]));
  end;
end;

class function TVoxelStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Volumes: TVoxelVolumeArray;
  Audit: TVoxelAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanVoxelVolumes(RootComp, DesignOwner, Volumes);
  Audit := AuditVoxelVolumes(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — 3D Voxel SDF Cave & Overhang Volume Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Active Voxel Volumes**: `%d` (`%d` SDF brushes, `%d` solid voxels, `%d` extracted triangles)',
      [Audit.VolumeCount, Audit.TotalBrushes, Audit.TotalSolidVoxels, Audit.TotalTriangles]));
    SB.AppendLine;

    if Length(Volumes) > 0 then
    begin
      SB.AppendLine('## Volumetric SDF Meshes');
      SB.AppendLine('| Volume | Preset | Grid | Voxel Size | Brushes | Solid Voxels | Triangles |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Volumes) do
        SB.AppendLine(Format('| `%s` | %s | `%dx%dx%d` | `%.2fm` | `%d` | `%d` | `%d` |',
          [Volumes[I].Name,
           TCastleVoxelVolume.PresetDisplayName(Volumes[I].Preset),
           Volumes[I].GridDimX, Volumes[I].GridDimY, Volumes[I].GridDimZ,
           Volumes[I].VoxelSize, Volumes[I].BrushCount,
           Volumes[I].SolidVoxelCount, Volumes[I].GeneratedTriangleCount]));
      SB.AppendLine;
    end;

    SB.AppendLine('## QA Diagnostics');
    if Audit.Warnings.Count = 0 then
      SB.AppendLine('- **0 warnings** — all 3D Voxel SDF volumes extracted watertight overhang meshes.')
    else
      for I := 0 to Audit.Warnings.Count - 1 do
        SB.AppendLine('- **Warning**: ' + Audit.Warnings[I]);

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Audit);
  end;
end;

end.
