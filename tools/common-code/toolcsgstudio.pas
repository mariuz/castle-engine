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

{ Stateless editor & headless test helpers for the CSG / Boolean Greybox
  Architecture & Procedural Mesh Modeler Studio (@link(TCsgStudioHelper))
  (Phase 309 — UE 6.0+ Modeling Mode & CubeGrid Parity). }
unit ToolCsgStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleTransform, CastleScene,
  CastleViewport, CastleUIControls, CastleCsgModeler;

type
  { Audit report summarizing all @link(TCastleCsgModeler) nodes in a design. }
  TCsgStudioAuditReport = class
  public
    Modelers: array of TCastleCsgModeler;
    TotalBrushCount: Integer;
    TotalOutputTriangles: Integer;
    TotalVolumeCubicMeters: Single;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring & audit helper for @link(TCastleCsgModeler). }
  TCsgStudioHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TCsgStudioAuditReport; static;

    class function SpawnCsgModeler(
      const RootComp, DesignOwner: TComponent;
      const APreset: TCsgArchitecturalPreset;
      const SpawnPos: TVector3): TCastleCsgModeler; static;

    class function AddArchitecturalBrush(
      const Modeler: TCastleCsgModeler;
      const ABrushId: String;
      const AOp: TCsgBooleanOperation;
      const AShape: TCsgBrushShape;
      const ACenter, ASize: TVector3;
      const AYawDeg: Single = 0.0;
      const ASegments: Integer = 8): Integer; static;

    class procedure RebuildAllModelers(const RootComp, DesignOwner: TComponent); static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils;

function MakeUniqueCsgName(const OwnerComp: TComponent; const Base: String): String;
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

function ResolveParentTransform(const RootComp: TComponent): TCastleTransform;
var
  I: Integer;
  Sub: TCastleTransform;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp).Items);
  if RootComp is TCastleTransform then
    Exit(TCastleTransform(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    for I := 0 to TCastleUserInterface(RootComp).ControlsCount - 1 do
    begin
      Sub := ResolveParentTransform(TCastleUserInterface(RootComp).Controls[I]);
      if Sub <> nil then
        Exit(Sub);
    end;
  end;
end;

procedure CollectFromTransform(const T: TCastleTransform; const DynamicArr: TList);
var
  I: Integer;
begin
  if T = nil then
    Exit;
  if (csTransient in T.ComponentStyle) then
    Exit;
  if (T is TCastleCsgModeler) and (DynamicArr.IndexOf(T) < 0) then
    DynamicArr.Add(T);
  for I := 0 to T.Count - 1 do
    CollectFromTransform(T[I], DynamicArr);
end;

procedure GatherModelers(const RootComp, DesignOwner: TComponent; const OutList: TList);
var
  I: Integer;
begin
  if RootComp is TCastleTransform then
    CollectFromTransform(TCastleTransform(RootComp), OutList)
  else if RootComp is TCastleUserInterface then
  begin
    if RootComp is TCastleViewport then
      CollectFromTransform(TCastleViewport(RootComp).Items, OutList);
    for I := 0 to TCastleUserInterface(RootComp).ControlsCount - 1 do
      GatherModelers(TCastleUserInterface(RootComp).Controls[I], nil, OutList);
  end;

  if DesignOwner <> nil then
    for I := 0 to DesignOwner.ComponentCount - 1 do
      if (DesignOwner.Components[I] is TCastleCsgModeler) and
         (OutList.IndexOf(DesignOwner.Components[I]) < 0) then
        OutList.Add(DesignOwner.Components[I]);
end;

{ TCsgStudioAuditReport ------------------------------------------------------ }

constructor TCsgStudioAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TCsgStudioAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TCsgStudioHelper ----------------------------------------------------------- }

class function TCsgStudioHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TCsgStudioAuditReport;
var
  Found: TList;
  I: Integer;
  M: TCastleCsgModeler;
begin
  Result := TCsgStudioAuditReport.Create;
  Found := TList.Create;
  try
    GatherModelers(RootComp, DesignOwner, Found);
    SetLength(Result.Modelers, Found.Count);
    for I := 0 to Found.Count - 1 do
    begin
      M := TCastleCsgModeler(Found[I]);
      Result.Modelers[I] := M;
      Inc(Result.TotalBrushCount, M.Brushes.Count);
      Inc(Result.TotalOutputTriangles, M.OutputTriangleCount);
      Result.TotalVolumeCubicMeters := Result.TotalVolumeCubicMeters + M.OutputVolumeCubicMeters;

      if M.OutputTriangleCount = 0 then
        Result.Warnings.Add(Format(
          '%s produces 0 triangles (ensure at least one enabled Union brush is at the bottom of the stack).',
          [M.Name]));
      if not M.GenerateCollider then
        Result.Warnings.Add(Format(
          '%s has GenerateCollider = False (players & raycasts will pass through greybox walls).',
          [M.Name]));
      if M.Brushes.Count > 24 then
        Result.Warnings.Add(Format(
          '%s has %d brushes (> 24); consider splitting large multi-wing architecture into separate TCastleCsgModeler rooms.',
          [M.Name, M.Brushes.Count]));
    end;
  finally
    FreeAndNil(Found);
  end;
end;

class function TCsgStudioHelper.SpawnCsgModeler(
  const RootComp, DesignOwner: TComponent;
  const APreset: TCsgArchitecturalPreset;
  const SpawnPos: TVector3): TCastleCsgModeler;
var
  ParentTrans: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentTrans := ResolveParentTransform(RootComp);
  if ParentTrans = nil then
    Exit;

  case APreset of
    capHollowRoomWithArchDoorway: BaseName := 'CsgHollowRoom';
    capVaultedCrossHallway:       BaseName := 'CsgVaultedCross';
    capMezzanineRampAndStairs:    BaseName := 'CsgMezzanineStairs';
    capPillaredCourtyardCloister: BaseName := 'CsgCourtyardCloister';
  else
    BaseName := 'CsgModeler';
  end;

  Result := TCastleCsgModeler.Create(DesignOwner);
  Result.Name := MakeUniqueCsgName(DesignOwner, BaseName);
  Result.Translation := SpawnPos;
  if APreset = capCustom then
  begin
    Result.ClearBrushes;
    TCsgStudioHelper.AddArchitecturalBrush(
      Result, 'BaseBlock', cboUnion, cbsBox,
      Vector3(0.0, 1.5, 0.0), Vector3(6.0, 3.0, 6.0));
  end else
    Result.ApplyPreset(APreset);

  ParentTrans.Add(Result);
end;

class function TCsgStudioHelper.AddArchitecturalBrush(
  const Modeler: TCastleCsgModeler;
  const ABrushId: String;
  const AOp: TCsgBooleanOperation;
  const AShape: TCsgBrushShape;
  const ACenter, ASize: TVector3;
  const AYawDeg: Single;
  const ASegments: Integer): Integer;
var
  B: TCsgBrushItem;
begin
  if Modeler = nil then
    Exit(-1);
  B := TCsgBrushItem.DefaultBox(ABrushId);
  B.Operation := AOp;
  B.Shape := AShape;
  B.Center := ACenter;
  B.Size := ASize;
  B.YawDeg := AYawDeg;
  B.Segments := ASegments;
  if AOp = cboSubtract then
    B.TintColor := Vector3(0.86, 0.80, 0.70)
  else if AOp = cboIntersect then
    B.TintColor := Vector3(0.72, 0.84, 0.82)
  else
    B.TintColor := Vector3(0.74, 0.77, 0.82);
  Result := Modeler.AddBrush(B);
end;

class procedure TCsgStudioHelper.RebuildAllModelers(
  const RootComp, DesignOwner: TComponent);
var
  Report: TCsgStudioAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Modelers) do
      Report.Modelers[I].RebuildMesh;
  finally
    FreeAndNil(Report);
  end;
end;

class function TCsgStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TCsgStudioAuditReport;
  SB: TStringBuilder;
  I, J: Integer;
  M: TCastleCsgModeler;
  B: TCsgBrushItem;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# CSG / Boolean Greybox Architecture Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **CSG Modeler Nodes**: %d', [Length(Report.Modelers)]));
    SB.AppendLine(Format('- **Total Brushes**: %d', [Report.TotalBrushCount]));
    SB.AppendLine(Format('- **Total Output Triangles**: %d', [Report.TotalOutputTriangles]));
    SB.AppendLine(Format('- **Total Solid Volume**: %.2f m^3', [Report.TotalVolumeCubicMeters]));
    SB.AppendLine;

    for I := 0 to High(Report.Modelers) do
    begin
      M := Report.Modelers[I];
      SB.AppendLine(Format('## `%s` (%s)', [M.Name, M.CsgSummaryBadge]));
      SB.AppendLine(Format('- **Volume**: `%.2f m^3` | **UV Tiling**: `%.2f /m` | **Collider Sync**: `%s`',
        [M.OutputVolumeCubicMeters, M.UvTilingScale, BoolToStr(M.GenerateCollider, True)]));
      SB.AppendLine('| # | Brush ID | Op | Shape | Center (m) | Size (m) | Yaw | Segs |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for J := 0 to M.Brushes.Count - 1 do
      begin
        B := M.Brushes[J];
        SB.AppendLine(Format('| %d | `%s` | %s | %s | `(%.2f, %.2f, %.2f)` | `(%.2f, %.2f, %.2f)` | `%.0f°` | %d |',
          [J + 1, B.BrushId, CsgOperationToString(B.Operation), CsgShapeToString(B.Shape),
           B.Center.X, B.Center.Y, B.Center.Z, B.Size.X, B.Size.Y, B.Size.Z,
           B.YawDeg, B.Segments]));
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
