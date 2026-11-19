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

{ Design-time helper for Procedural Catenary Cable, Powerline Sag & Hanging
  Lantern Garland Studio (Phase 385). }
unit ToolCatenaryCable;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene, CastleColors,
  CastleCatenaryCable;

type
  TCatenaryStudioSummary = record
    CableCount: Integer;
    TotalArcLengthMeters: Single;
    MaxMidpointSagMeters: Single;
    TotalLanternAttachments: Integer;
  end;

  TCatenaryCableHelper = class
  public
    class function FindFirstCable(const ARoot: TComponent): TCastleCatenaryCable;
    class function SpawnFestivalGarlandDemo(const ADesignRoot, ADesignOwner: TComponent;
      out ACable: TCastleCatenaryCable): Boolean;
    class function CollectSummary(const ADesignRoot: TComponent): TCatenaryStudioSummary;
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

class function TCatenaryCableHelper.FindFirstCable(
  const ARoot: TComponent): TCastleCatenaryCable;
var
  I: Integer;
  T: TCastleTransform;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if (ARoot is TCastleCatenaryCable) and (not (csTransient in ARoot.ComponentStyle)) then
    Exit(TCastleCatenaryCable(ARoot));
  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindFirstCable(T[I]);
      if Result <> nil then Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindFirstCable(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TCatenaryCableHelper.SpawnFestivalGarlandDemo(
  const ADesignRoot, ADesignOwner: TComponent;
  out ACable: TCastleCatenaryCable): Boolean;
var
  Vp: TCastleViewport;
  OwnerToUse: TComponent;
  PoleLeft, PoleRight: TCastleCylinder;
begin
  ACable := nil;
  Vp := FindViewport(ADesignRoot);
  if Vp = nil then Exit(False);
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := Vp;

  PoleLeft := TCastleCylinder.Create(OwnerToUse);
  PoleLeft.Name := 'CatenaryPoleWest';
  PoleLeft.Radius := 0.16;
  PoleLeft.Height := 6.2;
  PoleLeft.Translation := Vector3(-8.0, 3.1, 0.0);
  PoleLeft.Color := Vector4(0.38, 0.30, 0.22, 1.0);
  Vp.Items.Add(PoleLeft);

  PoleRight := TCastleCylinder.Create(OwnerToUse);
  PoleRight.Name := 'CatenaryPoleEast';
  PoleRight.Radius := 0.16;
  PoleRight.Height := 6.2;
  PoleRight.Translation := Vector3(8.0, 3.1, 0.0);
  PoleRight.Color := Vector4(0.38, 0.30, 0.22, 1.0);
  Vp.Items.Add(PoleRight);

  ACable := TCastleCatenaryCable.Create(OwnerToUse);
  ACable.Name := 'FestivalLanternGarland';
  ACable.ApplyPreset(ccpFestivalLanternGarland);
  Vp.Items.Add(ACable);
  ACable.RebuildCatenary;
  Result := True;
end;

class function TCatenaryCableHelper.CollectSummary(
  const ADesignRoot: TComponent): TCatenaryStudioSummary;

  procedure Scan(const ANode: TComponent);
  var
    I: Integer;
    C: TCastleCatenaryCable;
    T: TCastleTransform;
  begin
    if ANode = nil then Exit;
    if (ANode is TCastleCatenaryCable) and (not (csTransient in ANode.ComponentStyle)) then
    begin
      C := TCastleCatenaryCable(ANode);
      Inc(Result.CableCount);
      Result.TotalArcLengthMeters := Result.TotalArcLengthMeters + C.TotalArcLengthMeters;
      if C.MidpointSagMeters > Result.MaxMidpointSagMeters then
        Result.MaxMidpointSagMeters := C.MidpointSagMeters;
      Inc(Result.TotalLanternAttachments, C.AttachmentCount);
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
  Result := Default(TCatenaryStudioSummary);
  Scan(ADesignRoot);
end;

class function TCatenaryCableHelper.BuildMarkdownReport(
  const ADesignRoot: TComponent): String;
var
  Sum: TCatenaryStudioSummary;
begin
  Sum := CollectSummary(ADesignRoot);
  Result :=
    '# Procedural Catenary Cable, Powerline Sag & Lantern Garland Report (Phase 385)' + NL + NL +
    FormatDot('- **Active Catenary Spans**: `%d`' + NL, [Sum.CableCount]) +
    FormatDot('- **Combined Solved Arc Length**: `%.2f m`' + NL, [Sum.TotalArcLengthMeters]) +
    FormatDot('- **Max Hyperbolic Midpoint Sag**: `%.2f m`' + NL, [Sum.MaxMidpointSagMeters]) +
    FormatDot('- **Hanging Lantern / Insulator Attachments**: `%d`' + NL, [Sum.TotalLanternAttachments]);
end;

end.
