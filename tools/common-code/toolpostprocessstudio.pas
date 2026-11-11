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

{ Design-time post-processing volume discovery, priority-blend evaluation,
  CPU color-grading preview, and Markdown/GLSL reporting for
  @link(TCastlePostProcessVolume) and @link(TCastlePostProcessStack)
  (Phase 293). }
unit ToolPostProcessStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleViewport, CastlePostProcessVolume;

type
  TPostProcessVolumeArray = array of TCastlePostProcessVolume;
  TPostProcessStackArray = array of TCastlePostProcessStack;

  TPostProcessStudioSummary = record
    Volumes: TPostProcessVolumeArray;
    Stacks: TPostProcessStackArray;
    Blended: TPostProcessSettings;
    ActiveVolumeCount: Integer;
  end;

  TPostProcessStudioHelper = class
  public
    { Discover all @link(TCastlePostProcessVolume) and
      @link(TCastlePostProcessStack) components in @code(ARoot) and evaluate
      blended settings at @code(AObserverWorldPos). }
    class function ScanVolumesAndBlend(const ARoot: TComponent;
      const AObserverWorldPos: TVector3): TPostProcessStudioSummary;

    { Return existing @link(TCastlePostProcessStack) or create one in
      @code(ARoot)'s non-visual components. }
    class function EnsureStackInDesign(const ARoot, ADesignOwner: TComponent): TCastlePostProcessStack;

    { Create a new global (@code(AUnbound = true)) or bounded 3D
      @link(TCastlePostProcessVolume) inside @code(ARoot)'s world. }
    class function CreateVolumeInDesign(const ARoot, ADesignOwner: TComponent;
      const APreset: TCastlePostProcessPreset;
      const AUnbound: Boolean;
      const AWorldPos: TVector3): TCastlePostProcessVolume;

    { Find first @link(TCastleViewport) in @code(ARoot), or @code(nil). }
    class function FindFirstViewport(const ARoot: TComponent): TCastleViewport;

    { Exact CPU twin of @link(TCastlePostProcessStack.BuildPostProcessFragmentGlsl)
      for split-screen Before/After studio swatch rendering and unit testing. }
    class function EvaluateColorGradeCpuPreview(
      const ASettings: TPostProcessSettings;
      const ABaseRgb: TVector3;
      const AUv01: TVector2): TVector3;

    { Generate Markdown + GLSL summary report. }
    class function FormatPostProcessMarkdown(const ARoot: TComponent;
      const AObserverWorldPos: TVector3): String;
  end;

implementation

uses
  Math, StrUtils,
  CastleUtils, CastleClassUtils, CastleTransform, CastleUIControls;

function ProposeUniquePpName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindWorldItems(const ARoot: TComponent): TCastleTransform;
var
  VP: TCastleViewport;
begin
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  VP := TPostProcessStudioHelper.FindFirstViewport(ARoot);
  if VP <> nil then
    Result := VP.Items
  else
    Result := nil;
end;

function AcesChannel(const X: Single): Single;
begin
  Result := Clamped((X * (2.51 * X + 0.03)) / (X * (2.43 * X + 0.59) + 0.14), 0.0, 1.0);
end;

{ TPostProcessStudioHelper --------------------------------------------------- }

class function TPostProcessStudioHelper.FindFirstViewport(
  const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindFirstViewport(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

class function TPostProcessStudioHelper.ScanVolumesAndBlend(
  const ARoot: TComponent;
  const AObserverWorldPos: TVector3): TPostProcessStudioSummary;
var
  Visited: array of TComponent;

  function MarkSeen(const C: TComponent): Boolean;
  var
    K: Integer;
  begin
    for K := 0 to High(Visited) do
      if Visited[K] = C then
        Exit(false);
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := C;
    Result := true;
  end;

  procedure Visit(const C: TComponent);
  var
    I, N: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) or (not MarkSeen(C)) then
      Exit;

    if C is TCastlePostProcessVolume then
    begin
      N := Length(Result.Volumes);
      SetLength(Result.Volumes, N + 1);
      Result.Volumes[N] := TCastlePostProcessVolume(C);
    end else
    if C is TCastlePostProcessStack then
    begin
      N := Length(Result.Stacks);
      SetLength(Result.Stacks, N + 1);
      Result.Stacks[N] := TCastlePostProcessStack(C);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end else
    if C is TCastleUserInterface then
    begin
      if C is TCastleViewport then
      begin
        VP := TCastleViewport(C);
        if VP.Items <> nil then
          Visit(VP.Items);
      end;
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;

    if C is TCastleComponent then
      for I := 0 to TCastleComponent(C).NonVisualComponentsCount - 1 do
        Visit(TCastleComponent(C).NonVisualComponents[I]);
  end;

var
  I: Integer;
begin
  Result := Default(TPostProcessStudioSummary);
  Result.Blended := TPostProcessSettings.Neutral;
  if ARoot = nil then
    Exit;

  SetLength(Visited, 0);
  Visit(ARoot);
  if ARoot.Owner <> nil then
    for I := 0 to ARoot.Owner.ComponentCount - 1 do
      if ARoot.Owner.Components[I] is TCastlePostProcessStack then
        Visit(ARoot.Owner.Components[I]);

  Result.Blended := TCastlePostProcessStack.EvaluateBlendedWorldSettings(
    ARoot, AObserverWorldPos, Result.ActiveVolumeCount);
end;

class function TPostProcessStudioHelper.EnsureStackInDesign(
  const ARoot, ADesignOwner: TComponent): TCastlePostProcessStack;
var
  Sum: TPostProcessStudioSummary;
  OwnerToUse: TComponent;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  Sum := ScanVolumesAndBlend(ARoot, TVector3.Zero);
  if Length(Sum.Stacks) > 0 then
    Exit(Sum.Stacks[0]);

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastlePostProcessStack.Create(OwnerToUse);
  Result.Name := ProposeUniquePpName(OwnerToUse, 'PostProcessStack');
  if ARoot is TCastleComponent then
    TCastleComponent(ARoot).AddNonVisualComponent(Result);
end;

class function TPostProcessStudioHelper.CreateVolumeInDesign(
  const ARoot, ADesignOwner: TComponent;
  const APreset: TCastlePostProcessPreset;
  const AUnbound: Boolean;
  const AWorldPos: TVector3): TCastlePostProcessVolume;
var
  ItemsRoot: TCastleTransform;
  OwnerToUse: TComponent;
begin
  Result := nil;
  ItemsRoot := FindWorldItems(ARoot);
  if ItemsRoot = nil then
    Exit;

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastlePostProcessVolume.Create(OwnerToUse);
  Result.Name := ProposeUniquePpName(OwnerToUse, 'PostProcessVolume');
  Result.IsUnbound := AUnbound;
  Result.Translation := AWorldPos;
  if AUnbound then
    Result.Priority := 0
  else
    Result.Priority := 10;
  Result.ApplyLookPreset(APreset);
  Result.VolumeLabel := PostProcessPresetToDisplayName(APreset);
  ItemsRoot.Add(Result);
end;

class function TPostProcessStudioHelper.EvaluateColorGradeCpuPreview(
  const ASettings: TPostProcessSettings;
  const ABaseRgb: TVector3;
  const AUv01: TVector2): TVector3;
var
  ExpMul, Luma, DX, DY, R2, Vig: Single;
  Col, AcesCol: TVector3;
begin
  ExpMul := Power(2.0, ASettings.ExposureEV);
  Col.X := ABaseRgb.X * ExpMul * ASettings.TintRed;
  Col.Y := ABaseRgb.Y * ExpMul * ASettings.TintGreen;
  Col.Z := ABaseRgb.Z * ExpMul * ASettings.TintBlue;

  Luma := Col.X * 0.2126 + Col.Y * 0.7152 + Col.Z * 0.0722;
  Col.X := Lerp(ASettings.Saturation, Luma, Col.X);
  Col.Y := Lerp(ASettings.Saturation, Luma, Col.Y);
  Col.Z := Lerp(ASettings.Saturation, Luma, Col.Z);

  Col.X := Max(0.0, (Col.X - 0.5) * ASettings.Contrast + 0.5);
  Col.Y := Max(0.0, (Col.Y - 0.5) * ASettings.Contrast + 0.5);
  Col.Z := Max(0.0, (Col.Z - 0.5) * ASettings.Contrast + 0.5);

  if ASettings.AcesTonemapMix > 0.001 then
  begin
    AcesCol := Vector3(AcesChannel(Col.X), AcesChannel(Col.Y), AcesChannel(Col.Z));
    Col.X := Lerp(ASettings.AcesTonemapMix, Clamped(Col.X, 0.0, 1.0), AcesCol.X);
    Col.Y := Lerp(ASettings.AcesTonemapMix, Clamped(Col.Y, 0.0, 1.0), AcesCol.Y);
    Col.Z := Lerp(ASettings.AcesTonemapMix, Clamped(Col.Z, 0.0, 1.0), AcesCol.Z);
  end;

  if ASettings.VignetteIntensity > 0.001 then
  begin
    DX := AUv01.X - 0.5;
    DY := AUv01.Y - 0.5;
    R2 := (DX * DX + DY * DY) * 2.4;
    Vig := Clamped(1.0 - R2 * ASettings.VignetteIntensity, 0.0, 1.0);
    Col := Col * Vig;
  end;

  Result := Vector3(
    Clamped(Col.X, 0.0, 1.0),
    Clamped(Col.Y, 0.0, 1.0),
    Clamped(Col.Z, 0.0, 1.0));
end;

class function TPostProcessStudioHelper.FormatPostProcessMarkdown(
  const ARoot: TComponent; const AObserverWorldPos: TVector3): String;
var
  Sum: TPostProcessStudioSummary;
  SB: TStringBuilder;
  I: Integer;
begin
  Sum := ScanVolumesAndBlend(ARoot, AObserverWorldPos);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Post-Processing Volume Stack Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Total Volumes**: `%d` | **Active @ Observer**: `%d` | **Stacks**: `%d`',
      [Length(Sum.Volumes), Sum.ActiveVolumeCount, Length(Sum.Stacks)]));
    SB.AppendLine(Format('- **Blended Output**: Exposure `%+.2f EV`, ACES `%.0f%%`, Contrast `%.2f`, Saturation `%.2f`, Vignette `%.2f`, Chromatic `%.1f px`',
      [Sum.Blended.ExposureEV, Sum.Blended.AcesTonemapMix * 100.0,
       Sum.Blended.Contrast, Sum.Blended.Saturation,
       Sum.Blended.VignetteIntensity, Sum.Blended.ChromaticAberrationPx]));
    SB.AppendLine;

    if Length(Sum.Volumes) > 0 then
    begin
      SB.AppendLine('## Volumes');
      SB.AppendLine;
      for I := 0 to High(Sum.Volumes) do
        SB.AppendLine(Format('- **`%s`** (%s): Priority `%d` | Mode `%s` | Observer Weight `%.0f%%`',
          [Sum.Volumes[I].Name,
           PostProcessPresetToDisplayName(Sum.Volumes[I].LookPreset),
           Sum.Volumes[I].Priority,
           IfThen(Sum.Volumes[I].IsUnbound, 'Global Unbound',
             Format('Bounded %.1f+%.1fm', [Sum.Volumes[I].CoreRadius, Sum.Volumes[I].BlendRadius])),
           Sum.Volumes[I].EvaluateObserverWeight(AObserverWorldPos) * 100.0]));
      SB.AppendLine;
    end;

    SB.AppendLine('## Generated X3D ScreenEffect GLSL');
    SB.AppendLine;
    SB.AppendLine('```glsl');
    SB.AppendLine(TCastlePostProcessStack.BuildPostProcessFragmentGlsl);
    SB.AppendLine('```');

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
