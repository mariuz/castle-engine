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

{ Stateless editor & headless test helpers for the Verlet Cloth / Cape / Banner
  & Rope Soft-Body Wind Simulation Studio (@link(TClothStudioHelper))
  (Phase 313 — UE 6.0+ Chaos Cloth & Cable Parity). }
unit ToolClothStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleScene, CastleViewport,
  CastleUIControls, CastleClothRope;

type
  { Audit report summarizing all @link(TCastleClothSurface) and
    @link(TCastleVerletRope) instances in a design. }
  TClothStudioAuditReport = class
  public
    Cloths: array of TCastleClothSurface;
    Ropes: array of TCastleVerletRope;
    TotalParticles: Integer;
    TotalTriangles: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring, simulation & Markdown helper for Cloth & Ropes. }
  TClothStudioHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TClothStudioAuditReport; static;
    class function ResolveTransformContainer(const RootComp: TComponent): TCastleTransform; static;

    class function SpawnClothInDesign(
      const RootComp, DesignOwner: TComponent;
      const APreset: TClothPreset;
      const APos: TVector3;
      const ABaseName: String = 'ClothBanner'): TCastleClothSurface; static;

    class function SpawnColliderSphereForCloth(
      const RootComp, DesignOwner: TComponent;
      const ATargetCloth: TCastleClothSurface;
      const AWorldPos: TVector3;
      const ARadius: Single = 0.60): TCastleSphere; static;

    class function SpawnVerletRopeInDesign(
      const RootComp, DesignOwner: TComponent;
      const APinMode: TRopePinMode;
      const AStartPos, AEndOffset: TVector3;
      const ATotalLength: Single = 6.0;
      const ABaseName: String = 'VerletRope'): TCastleVerletRope; static;

    class procedure StepAllClothAndRopes(
      const RootComp, DesignOwner: TComponent; const Dt: Single); static;

    class procedure ResetAllClothAndRopes(
      const RootComp, DesignOwner: TComponent); static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils;

function MakeUniqueClothName(const OwnerComp: TComponent; const Base: String): String;
var
  Idx: Integer;
begin
  if (OwnerComp = nil) or (OwnerComp.FindComponent(Base) = nil) then
    Exit(Base);
  Idx := 1;
  repeat
    Result := Base + IntToStr(Idx);
    Inc(Idx);
  until OwnerComp.FindComponent(Result) = nil;
end;

{ TClothStudioAuditReport ---------------------------------------------------- }

constructor TClothStudioAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TClothStudioAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TClothStudioHelper --------------------------------------------------------- }

class function TClothStudioHelper.ResolveTransformContainer(
  const RootComp: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp).Items);
  if RootComp is TCastleTransform then
    Exit(TCastleTransform(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
      if UI.Controls[I] is TCastleViewport then
        Exit(TCastleViewport(UI.Controls[I]).Items);
  end;
  Result := nil;
end;

class function TClothStudioHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TClothStudioAuditReport;
var
  FoundCloths, FoundRopes: TList;

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if C = nil then
      Exit;
    if (C is TCastleClothSurface) and (FoundCloths.IndexOf(C) < 0) then
      FoundCloths.Add(C);
    if (C is TCastleVerletRope) and (FoundRopes.IndexOf(C) < 0) then
      FoundRopes.Add(C);

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
      if not (csTransient in T.ComponentStyle) then
        for I := 0 to T.Count - 1 do
          Traverse(T[I]);
    end;
  end;

var
  I: Integer;
  Cl: TCastleClothSurface;
  Rp: TCastleVerletRope;
begin
  Result := TClothStudioAuditReport.Create;
  FoundCloths := TList.Create;
  FoundRopes := TList.Create;
  try
    Traverse(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        Traverse(DesignOwner.Components[I]);

    SetLength(Result.Cloths, FoundCloths.Count);
    for I := 0 to FoundCloths.Count - 1 do
    begin
      Cl := TCastleClothSurface(FoundCloths[I]);
      Result.Cloths[I] := Cl;
      Inc(Result.TotalParticles, Cl.ParticleCount);
      Inc(Result.TotalTriangles, Cl.OutputTriangleCount);
      if Cl.SyncWithWeather and (Cl.WeatherController = nil) then
        Result.Warnings.Add(Cl.Name + ' has SyncWithWeather = True without a WeatherController assigned.');
    end;

    SetLength(Result.Ropes, FoundRopes.Count);
    for I := 0 to FoundRopes.Count - 1 do
    begin
      Rp := TCastleVerletRope(FoundRopes[I]);
      Result.Ropes[I] := Rp;
      Inc(Result.TotalParticles, Rp.NodeCount);
      Inc(Result.TotalTriangles, Rp.OutputTriangleCount);
      if (Rp.PinMode = rpmBothEndsCatenary) and
         (Rp.EndAnchorTransform = nil) and
         (Rp.TotalLength < Rp.EndOffset.Length) then
        Result.Warnings.Add(Rp.Name + ' TotalLength is shorter than EndOffset span (rope is over-tensioned).');
    end;
  finally
    FreeAndNil(FoundRopes);
    FreeAndNil(FoundCloths);
  end;
end;

class function TClothStudioHelper.SpawnClothInDesign(
  const RootComp, DesignOwner: TComponent;
  const APreset: TClothPreset;
  const APos: TVector3;
  const ABaseName: String): TCastleClothSurface;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleClothSurface.Create(OwnerToUse);
  Result.Name := MakeUniqueClothName(OwnerToUse, ABaseName);
  Result.Translation := APos;
  Result.ApplyPreset(APreset);

  Container := ResolveTransformContainer(RootComp);
  if Container <> nil then
    Container.Add(Result);
end;

class function TClothStudioHelper.SpawnColliderSphereForCloth(
  const RootComp, DesignOwner: TComponent;
  const ATargetCloth: TCastleClothSurface;
  const AWorldPos: TVector3;
  const ARadius: Single): TCastleSphere;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleSphere.Create(OwnerToUse);
  Result.Name := MakeUniqueClothName(OwnerToUse, 'ClothColliderSphere');
  Result.Radius := ARadius;
  Result.Translation := AWorldPos;
  Result.Color := Vector4(0.32, 0.72, 0.92, 1.0);

  Container := ResolveTransformContainer(RootComp);
  if Container <> nil then
    Container.Add(Result);

  if ATargetCloth <> nil then
  begin
    ATargetCloth.ColliderTransform := Result;
    ATargetCloth.ColliderRadius := ARadius;
  end;
end;

class function TClothStudioHelper.SpawnVerletRopeInDesign(
  const RootComp, DesignOwner: TComponent;
  const APinMode: TRopePinMode;
  const AStartPos, AEndOffset: TVector3;
  const ATotalLength: Single;
  const ABaseName: String): TCastleVerletRope;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleVerletRope.Create(OwnerToUse);
  Result.Name := MakeUniqueClothName(OwnerToUse, ABaseName);
  Result.Translation := AStartPos;
  Result.PinMode := APinMode;
  Result.EndOffset := AEndOffset;
  Result.TotalLength := ATotalLength;
  Result.ResetRope;

  Container := ResolveTransformContainer(RootComp);
  if Container <> nil then
    Container.Add(Result);
end;

class procedure TClothStudioHelper.StepAllClothAndRopes(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Report: TClothStudioAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Cloths) do
      Report.Cloths[I].StepSimulation(Dt);
    for I := 0 to High(Report.Ropes) do
      Report.Ropes[I].StepSimulation(Dt);
  finally
    FreeAndNil(Report);
  end;
end;

class procedure TClothStudioHelper.ResetAllClothAndRopes(
  const RootComp, DesignOwner: TComponent);
var
  Report: TClothStudioAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Cloths) do
      Report.Cloths[I].ResetClothGrid;
    for I := 0 to High(Report.Ropes) do
      Report.Ropes[I].ResetRope;
  finally
    FreeAndNil(Report);
  end;
end;

class function TClothStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TClothStudioAuditReport;
  SB: TStringBuilder;
  I: Integer;
  Cl: TCastleClothSurface;
  Rp: TCastleVerletRope;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Verlet Cloth, Banner & Catenary Rope Wind Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Cloth Surfaces**: %d | **Verlet Ropes**: %d | **Total Particles**: %d | **Total Triangles**: %d',
      [Length(Report.Cloths), Length(Report.Ropes), Report.TotalParticles, Report.TotalTriangles]));
    SB.AppendLine;

    if Length(Report.Cloths) > 0 then
    begin
      SB.AppendLine('## Cloth Surfaces');
      SB.AppendLine('| Name | Grid | Dimensions (m) | Iters | Max Stretch | Wind (m/s) |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Report.Cloths) do
      begin
        Cl := Report.Cloths[I];
        SB.AppendLine(Format('| `%s` | %dx%d | %.2fx%.2f | %d | %.3fx | `(%.1f, %.1f, %.1f)` |',
          [Cl.Name, Cl.Cols, Cl.Rows, Cl.Width, Cl.Height, Cl.SolverIterations,
           Cl.MaxStretchRatio, Cl.EffectiveWindWorld.X, Cl.EffectiveWindWorld.Y, Cl.EffectiveWindWorld.Z]));
      end;
      SB.AppendLine;
    end;

    if Length(Report.Ropes) > 0 then
    begin
      SB.AppendLine('## Verlet Ropes');
      SB.AppendLine('| Name | Segments | Length (m) | Lowest Sag Y (m) | Max Stretch |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Report.Ropes) do
      begin
        Rp := Report.Ropes[I];
        SB.AppendLine(Format('| `%s` | %d | %.2f | %.2f | %.3fx |',
          [Rp.Name, Rp.SegmentCount, Rp.TotalLength, Rp.LowestSagLocalY, Rp.MaxStretchRatio]));
      end;
      SB.AppendLine;
    end;

    if Report.Warnings.Count > 0 then
    begin
      SB.AppendLine('## Warnings');
      for I := 0 to Report.Warnings.Count - 1 do
        SB.AppendLine('- ' + Report.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
