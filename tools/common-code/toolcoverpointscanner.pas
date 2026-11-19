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

{ Design-time helper for Tactical Cover Point Scanner, Crouch-Peek / Corner-Lean
  & Threat Exposure Studio (Phase 384). }
unit ToolCoverPointScanner;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene, CastleColors,
  CastleCoverPointScanner;

type
  TCoverScannerStudioSummary = record
    ScannerCount: Integer;
    TotalCoverNodes: Integer;
    WaistPeekNodes: Integer;
    FullCornerNodes: Integer;
    SafeNodesCount: Integer;
  end;

  TCoverPointScannerHelper = class
  public
    class function FindFirstScanner(const ARoot: TComponent): TCastleCoverPointScanner;
    class function SpawnKillhouseCoverArena(const ADesignRoot, ADesignOwner: TComponent;
      out AScanner: TCastleCoverPointScanner): Boolean;
    class function CollectSummary(const ADesignRoot: TComponent): TCoverScannerStudioSummary;
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

class function TCoverPointScannerHelper.FindFirstScanner(
  const ARoot: TComponent): TCastleCoverPointScanner;
var
  I: Integer;
  T: TCastleTransform;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if (ARoot is TCastleCoverPointScanner) and (not (csTransient in ARoot.ComponentStyle)) then
    Exit(TCastleCoverPointScanner(ARoot));
  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindFirstScanner(T[I]);
      if Result <> nil then Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindFirstScanner(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TCoverPointScannerHelper.SpawnKillhouseCoverArena(
  const ADesignRoot, ADesignOwner: TComponent;
  out AScanner: TCastleCoverPointScanner): Boolean;
var
  Vp: TCastleViewport;
  OwnerToUse: TComponent;
  FloorBox, WaistBarrier, TallPillar: TCastleBox;
begin
  AScanner := nil;
  Vp := FindViewport(ADesignRoot);
  if Vp = nil then Exit(False);
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := Vp;

  FloorBox := TCastleBox.Create(OwnerToUse);
  FloorBox.Name := 'KillhouseFloor';
  FloorBox.Size := Vector3(28.0, 0.5, 28.0);
  FloorBox.Translation := Vector3(0.0, -0.25, 0.0);
  FloorBox.Color := Vector4(0.32, 0.34, 0.36, 1.0);
  Vp.Items.Add(FloorBox);

  { 1.15m waist-high Jersey barrier along X in front of North (-Z) }
  WaistBarrier := TCastleBox.Create(OwnerToUse);
  WaistBarrier.Name := 'WaistJerseyBarrier';
  WaistBarrier.Size := Vector3(6.0, 1.15, 0.80);
  WaistBarrier.Translation := Vector3(-3.5, 0.575, 0.0);
  WaistBarrier.Color := Vector4(0.62, 0.60, 0.54, 1.0);
  Vp.Items.Add(WaistBarrier);

  { 2.60m full-height concrete pillar affording Left/Right corner leans }
  TallPillar := TCastleBox.Create(OwnerToUse);
  TallPillar.Name := 'FullHeightPillar';
  TallPillar.Size := Vector3(1.5, 2.60, 1.5);
  TallPillar.Translation := Vector3(4.5, 1.30, 0.0);
  TallPillar.Color := Vector4(0.46, 0.48, 0.52, 1.0);
  Vp.Items.Add(TallPillar);

  AScanner := TCastleCoverPointScanner.Create(OwnerToUse);
  AScanner.Name := 'KillhouseCoverScanner';
  AScanner.ApplyPreset(cspInfantryFirefightGrid);
  Vp.Items.Add(AScanner);

  AScanner.BakeCoverNodes(Vp.Items);
  Result := True;
end;

class function TCoverPointScannerHelper.CollectSummary(
  const ADesignRoot: TComponent): TCoverScannerStudioSummary;

  procedure Scan(const ANode: TComponent);
  var
    I: Integer;
    S: TCastleCoverPointScanner;
    T: TCastleTransform;
  begin
    if ANode = nil then Exit;
    if (ANode is TCastleCoverPointScanner) and (not (csTransient in ANode.ComponentStyle)) then
    begin
      S := TCastleCoverPointScanner(ANode);
      Inc(Result.ScannerCount);
      Inc(Result.TotalCoverNodes, S.CoverNodeCount);
      Inc(Result.WaistPeekNodes, S.WaistCoverCount);
      Inc(Result.FullCornerNodes, S.FullCoverCount);
      Inc(Result.SafeNodesCount, S.LastSafeNodeCount);
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
  Result := Default(TCoverScannerStudioSummary);
  Scan(ADesignRoot);
end;

class function TCoverPointScannerHelper.BuildMarkdownReport(
  const ADesignRoot: TComponent): String;
var
  Sum: TCoverScannerStudioSummary;
begin
  Sum := CollectSummary(ADesignRoot);
  Result :=
    '# Tactical Cover Point Scanner & Threat Flanking Report (Phase 384)' + NL + NL +
    FormatDot('- **Active Cover Scanners**: `%d`' + NL, [Sum.ScannerCount]) +
    FormatDot('- **Total Baked Cover Points**: `%d` (`%d` Waist Over-Peek, `%d` Full Corner-Lean)' + NL,
      [Sum.TotalCoverNodes, Sum.WaistPeekNodes, Sum.FullCornerNodes]) +
    FormatDot('- **Un-Flanked Safe Cover Nodes**: `%d`' + NL, [Sum.SafeNodesCount]);
end;

end.
