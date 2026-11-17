{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for the Gameplay Cue Combat Feedback, Hit-Stop Time-Dilation,
  Camera Punch & Floating Damage-Number Pool Studio (Phase 342). }
unit ToolGameplayCue;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleGameplayCue;

type
  TGameplayCueStudioSummary = record
    DirectorCount: Integer;
    ActivePopups: Integer;
    PoolCapacity: Integer;
    TotalTriggered: Integer;
    EffectiveTimeScale: Single;
    WarningsCount: Integer;
  end;

  TGameplayCueHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstDirector(const ARoot: TComponent): TCastleGameplayCueDirector; static;

    class function SpawnCombatTrainingDummyCueDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ADummy: TCastleTransform;
      out ADirector: TCastleGameplayCueDirector): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TGameplayCueStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TGameplayCueHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TGameplayCueHelper.FindFirstDirector(
  const ARoot: TComponent): TCastleGameplayCueDirector;

  function ScanRec(const T: TCastleTransform): TCastleGameplayCueDirector;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleGameplayCueDirector then
      Exit(TCastleGameplayCueDirector(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TGameplayCueHelper.SpawnCombatTrainingDummyCueDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ADummy: TCastleTransform;
  out ADirector: TCastleGameplayCueDirector): Boolean;
var
  RootT: TCastleTransform;
  DummyCyl: TCastleCylinder;
begin
  ADummy := nil;
  ADirector := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  DummyCyl := TCastleCylinder.Create(ADesignOwner);
  DummyCyl.Name := MakeUniqueName(ADesignOwner, 'CueTrainingDummy');
  DummyCyl.Radius := 0.50;
  DummyCyl.Height := 1.90;
  DummyCyl.Translation := Vector3(0.0, 0.95, 0.0);
  DummyCyl.Color := Vector4(0.82, 0.42, 0.28, 1.0);
  RootT.Add(DummyCyl);
  ADummy := DummyCyl;

  ADirector := TCastleGameplayCueDirector.Create(ADesignOwner);
  ADirector.Name := MakeUniqueName(ADesignOwner, 'GameplayCueDirector');
  ADirector.MaxPooledPopups := 48;
  RootT.Add(ADirector);
  Result := True;
end;

class function TGameplayCueHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TGameplayCueStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    D: TCastleGameplayCueDirector;
  begin
    if T = nil then Exit;
    if T is TCastleGameplayCueDirector then
    begin
      D := TCastleGameplayCueDirector(T);
      Inc(Result.DirectorCount);
      Result.ActivePopups := Result.ActivePopups + D.ActivePopupCount;
      Result.PoolCapacity := Result.PoolCapacity + D.PoolCapacity;
      Result.TotalTriggered := Result.TotalTriggered + D.TotalCuesTriggered;
      Result.EffectiveTimeScale := Min(Result.EffectiveTimeScale, D.EffectiveWorldTimeScale);
      if D.CritHitStopDurationSec > 0.35 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s has CritHitStopDurationSec = %.2fs (> 0.35s), which may feel sluggish.', [
            D.Name, D.CritHitStopDurationSec]));
      end;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TGameplayCueStudioSummary);
  Result.EffectiveTimeScale := 1.0;
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TGameplayCueHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TGameplayCueStudioSummary;
  D: TCastleGameplayCueDirector;
  SB: TStringBuilder;
  I: Integer;
  Slot: TGameplayCuePopupSlot;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    D := FindFirstDirector(ARoot);
    SB.AppendLine('# Castle Game Engine — Gameplay Cue, Hit-Stop & Combat Feedback Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Gameplay Cue Directors**: `%d` (`%d / %d` active pooled popups, `%d` total dispatched)', [
      Sum.DirectorCount, Sum.ActivePopups, Sum.PoolCapacity, Sum.TotalTriggered]));
    SB.AppendLine(Format('- **Effective World Time-Dilation**: `%.2fx`', [Sum.EffectiveTimeScale]));
    if (D <> nil) and (D.ActivePopupCount > 0) then
    begin
      SB.AppendLine;
      SB.AppendLine('| Cue Tag | Text | World Pos `(m)` | Age / Life `(s)` |');
      SB.AppendLine('| :--- | :--- | :--- | ---: |');
      for I := 0 to D.PoolCapacity - 1 do
      begin
        Slot := D.GetPopupSlot(I);
        if Slot.Active then
          SB.AppendLine(Format('| `%s` | **%s** | `(%.2f, %.2f, %.2f)` | `%.2f / %.2f` |', [
            Slot.CueTag, Slot.DisplayText,
            Slot.WorldPos.X, Slot.WorldPos.Y, Slot.WorldPos.Z,
            Slot.AgeSec, Slot.LifetimeSec]));
      end;
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
