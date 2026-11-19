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

{ Design-time helper for Interactive Snow, Mud & Sand Persistent Deformation
  Trail Stamper Studio (Phase 383). }
unit ToolTrailStamper;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleTrailStamper;

type
  TTrailStamperStudioSummary = record
    StamperCount: Integer;
    TotalDeformedCells: Integer;
    DeepestTroughMeters: Single;
    HighestBermMeters: Single;
  end;

  TTrailStamperHelper = class
  public
    class function FindFirstStamper(const ARoot: TComponent): TCastleTrailStamper;
    class function SpawnAlpineSnowTrailDemo(const ADesignRoot, ADesignOwner: TComponent;
      out AStamper: TCastleTrailStamper): Boolean;
    class function CollectSummary(const ADesignRoot: TComponent): TTrailStamperStudioSummary;
    class function BuildMarkdownReport(const ADesignRoot: TComponent): String;
  end;

implementation

uses CastleUtils;

function FindViewport(const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
begin
  if ARoot = nil then Exit(nil);
  if ARoot is TCastleViewport then Exit(TCastleViewport(ARoot));
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindViewport(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

class function TTrailStamperHelper.FindFirstStamper(
  const ARoot: TComponent): TCastleTrailStamper;
var
  I: Integer;
  T: TCastleTransform;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if (ARoot is TCastleTrailStamper) and (not (csTransient in ARoot.ComponentStyle)) then
    Exit(TCastleTrailStamper(ARoot));
  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindFirstStamper(T[I]);
      if Result <> nil then Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindFirstStamper(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TTrailStamperHelper.SpawnAlpineSnowTrailDemo(
  const ADesignRoot, ADesignOwner: TComponent;
  out AStamper: TCastleTrailStamper): Boolean;
var
  Vp: TCastleViewport;
  OwnerToUse: TComponent;
begin
  AStamper := nil;
  Vp := FindViewport(ADesignRoot);
  if Vp = nil then Exit(False);
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := Vp;

  AStamper := TCastleTrailStamper.Create(OwnerToUse);
  AStamper.Name := 'AlpineSnowfieldStamper';
  AStamper.ApplyPreset(tmpDeepAlpineSnow);
  Vp.Items.Add(AStamper);

  { Carve an initial diagonal sled furrow across the center of the snowfield }
  AStamper.StampFurrowSegmentWorld(Vector3(-7.0, 0.0, -6.0), Vector3(7.0, 0.0, 6.0), 1.35, 0.34);
  Result := True;
end;

class function TTrailStamperHelper.CollectSummary(
  const ADesignRoot: TComponent): TTrailStamperStudioSummary;

  procedure Scan(const ANode: TComponent);
  var
    I: Integer;
    S: TCastleTrailStamper;
    T: TCastleTransform;
  begin
    if ANode = nil then Exit;
    if (ANode is TCastleTrailStamper) and (not (csTransient in ANode.ComponentStyle)) then
    begin
      S := TCastleTrailStamper(ANode);
      Inc(Result.StamperCount);
      Inc(Result.TotalDeformedCells, S.ActiveDeformedCellCount);
      if S.MinDisplacementMeters < Result.DeepestTroughMeters then
        Result.DeepestTroughMeters := S.MinDisplacementMeters;
      if S.MaxBermHeightMeters > Result.HighestBermMeters then
        Result.HighestBermMeters := S.MaxBermHeightMeters;
    end;
    if ANode is TCastleTransform then
    begin
      T := TCastleTransform(ANode);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
    for I := 0 to ANode.ComponentCount - 1 do
      if not (ANode.Components[I] is TCastleTransform) or
         (TCastleTransform(ANode.Components[I]).Parent = nil) then
        Scan(ANode.Components[I]);
  end;

begin
  Result := Default(TTrailStamperStudioSummary);
  Scan(ADesignRoot);
end;

class function TTrailStamperHelper.BuildMarkdownReport(
  const ADesignRoot: TComponent): String;
var
  Sum: TTrailStamperStudioSummary;
begin
  Sum := CollectSummary(ADesignRoot);
  Result :=
    '# Interactive Snow, Mud & Sand Persistent Deformation Trail Report (Phase 383)' + NL + NL +
    FormatDot('- **Active Deformation Stampers**: `%d`' + NL, [Sum.StamperCount]) +
    FormatDot('- **Active Deformed Grid Cells**: `%d`' + NL, [Sum.TotalDeformedCells]) +
    FormatDot('- **Deepest Furrow Depression**: `%.3f m`' + NL, [Sum.DeepestTroughMeters]) +
    FormatDot('- **Highest Raised Rim Berm**: `+%.3f m`' + NL, [Sum.HighestBermMeters]);
end;

end.
