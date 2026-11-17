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

{ Stateless helper for the Secondary-Motion Jiggle Bone Springs, Gravity /
  Centrifugal Inertia & Spherical Limit Cone Studio (Phase 344). }
unit ToolJiggleBone;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleJiggleBone;

type
  TJiggleBoneStudioSummary = record
    JiggleBehaviorCount: Integer;
    ConeClampedCount: Integer;
    PeakDeflectionDeg: Single;
    PeakTipSpeedMps: Single;
    WarningsCount: Integer;
  end;

  TJiggleBoneHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstJiggleBehavior(const ARoot: TComponent): TCastleJiggleBoneBehavior; static;

    { Spawn a character bust carrier with 2 bouncy fox ears + 1 heavy hanging
      leather belt pouch, each driving a visible 3D tip marker sphere. }
    class function SpawnCharacterJiggleRigDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ACarrier: TCastleTransform): Boolean; static;

    { Displace the first character carrier or jiggle parent by AWorldImpulse and
      step all jiggle springs so secondary-motion whip is immediately visible. }
    class procedure JoltCarrierImpulse(const ARoot: TComponent;
      const AWorldDelta: TVector3; const AStepDt: Single = 0.02); static;

    class procedure StepAllJiggleBones(const ARoot: TComponent;
      const ADt: Single); static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TJiggleBoneStudioSummary; static;

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

class function TJiggleBoneHelper.ResolveRootTransform(
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

class function TJiggleBoneHelper.FindFirstJiggleBehavior(
  const ARoot: TComponent): TCastleJiggleBoneBehavior;

  function ScanRec(const T: TCastleTransform): TCastleJiggleBoneBehavior;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleJiggleBoneBehavior then
        Exit(TCastleJiggleBoneBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TJiggleBoneHelper.SpawnCharacterJiggleRigDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ACarrier: TCastleTransform): Boolean;
var
  RootT: TCastleTransform;
  Torso: TCastleCylinder;

  procedure AddJiggleAttachment(const ABaseName: String;
    const ALocalPivot: TVector3; const APreset: TJiggleSpringPreset;
    const ATipColor: TVector4);
  var
    Mount: TCastleTransform;
    TipSphere: TCastleSphere;
    Jig: TCastleJiggleBoneBehavior;
  begin
    Mount := TCastleTransform.Create(ADesignOwner);
    Mount.Name := MakeUniqueName(ADesignOwner, ABaseName);
    Mount.Translation := ALocalPivot;
    ACarrier.Add(Mount);

    TipSphere := TCastleSphere.Create(ADesignOwner);
    TipSphere.Name := MakeUniqueName(ADesignOwner, ABaseName + '_Tip');
    TipSphere.Radius := 0.13;
    TipSphere.Color := ATipColor;
    Mount.Add(TipSphere);

    Jig := TCastleJiggleBoneBehavior.Create(ADesignOwner);
    Jig.Name := MakeUniqueName(ADesignOwner, ABaseName + '_Spring');
    Jig.DrivenTipTransformName := TipSphere.Name;
    Mount.AddBehavior(Jig);
    Jig.ApplySpringPreset(APreset);
  end;

begin
  ACarrier := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  ACarrier := TCastleTransform.Create(ADesignOwner);
  ACarrier.Name := MakeUniqueName(ADesignOwner, 'JiggleCharacterRig');
  ACarrier.Translation := Vector3(0.0, 0.0, 0.0);
  RootT.Add(ACarrier);

  Torso := TCastleCylinder.Create(ADesignOwner);
  Torso.Name := MakeUniqueName(ADesignOwner, 'CharacterBustTorso');
  Torso.Radius := 0.42;
  Torso.Height := 1.70;
  Torso.Translation := Vector3(0.0, 0.85, 0.0);
  Torso.Color := Vector4(0.36, 0.52, 0.78, 1.0);
  ACarrier.Add(Torso);

  AddJiggleAttachment('FoxEar_Left', Vector3(-0.28, 1.72, 0.0),
    jspBouncyFoxEars, Vector4(0.96, 0.62, 0.24, 1.0));
  AddJiggleAttachment('FoxEar_Right', Vector3(+0.28, 1.72, 0.0),
    jspBouncyFoxEars, Vector4(0.96, 0.62, 0.24, 1.0));
  AddJiggleAttachment('LeatherBeltPouch', Vector3(+0.46, 0.95, 0.12),
    jspHeavyLeatherPouch, Vector4(0.68, 0.44, 0.24, 1.0));

  StepAllJiggleBones(ARoot, 0.016);
  Result := True;
end;

class procedure TJiggleBoneHelper.StepAllJiggleBones(const ARoot: TComponent;
  const ADt: Single);

  procedure StepRec(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleJiggleBoneBehavior then
        TCastleJiggleBoneBehavior(T.Behaviors[I]).StepSpring(ADt);
    for I := 0 to T.Count - 1 do
      StepRec(T[I]);
  end;

begin
  StepRec(ResolveRootTransform(ARoot));
end;

class procedure TJiggleBoneHelper.JoltCarrierImpulse(const ARoot: TComponent;
  const AWorldDelta: TVector3; const AStepDt: Single);
var
  RootT, Carrier: TCastleTransform;
  FirstJig: TCastleJiggleBoneBehavior;
  I: Integer;
begin
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then Exit;

  Carrier := nil;
  for I := 0 to RootT.Count - 1 do
    if Pos('JiggleCharacterRig', RootT[I].Name) = 1 then
    begin
      Carrier := RootT[I];
      Break;
    end;

  if Carrier = nil then
  begin
    FirstJig := FindFirstJiggleBehavior(ARoot);
    if FirstJig <> nil then
      Carrier := FirstJig.Parent;
  end;

  if Carrier <> nil then
    Carrier.Translation := Carrier.Translation + AWorldDelta;

  StepAllJiggleBones(ARoot, AStepDt);
end;

class function TJiggleBoneHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TJiggleBoneStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    J: TCastleJiggleBoneBehavior;
  begin
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleJiggleBoneBehavior then
      begin
        J := TCastleJiggleBoneBehavior(T.Behaviors[I]);
        Inc(Result.JiggleBehaviorCount);
        Result.PeakDeflectionDeg := Max(Result.PeakDeflectionDeg, J.CurrentDeflectionDeg);
        Result.PeakTipSpeedMps := Max(Result.PeakTipSpeedMps, J.TipSpeedMetersPerSec);
        if J.CurrentDeflectionDeg >= J.MaxConeAngleDeg - 0.25 then
          Inc(Result.ConeClampedCount);
        if J.DampingRatio < 0.08 then
        begin
          Inc(Result.WarningsCount);
          if AWarnings <> nil then
            AWarnings.Add(Format('%s has very low DampingRatio = %.2f (< 0.08), causing prolonged ringing.', [
              J.Name, J.DampingRatio]));
        end;
      end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TJiggleBoneStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TJiggleBoneHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TJiggleBoneStudioSummary;
  SB: TStringBuilder;
  I: Integer;

  procedure AppendRowsRec(const T: TCastleTransform);
  var
    K: Integer;
    J: TCastleJiggleBoneBehavior;
  begin
    if T = nil then Exit;
    for K := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[K] is TCastleJiggleBoneBehavior then
      begin
        J := TCastleJiggleBoneBehavior(T.Behaviors[K]);
        SB.AppendLine(Format('| `%s` | `%s` | `%.0f` / `%.2f` | `%.1f° / %.1f°` | `%.2f m/s` |', [
          T.Name, JigglePresetToDisplayName(J.Preset),
          J.Stiffness, J.DampingRatio,
          J.CurrentDeflectionDeg, J.MaxConeAngleDeg,
          J.TipSpeedMetersPerSec]));
      end;
    for K := 0 to T.Count - 1 do
      AppendRowsRec(T[K]);
  end;

begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    SB.AppendLine('# Castle Game Engine — Secondary-Motion Jiggle Bone Springs Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Jiggle Bone Springs**: `%d` (`%d` currently at cone limit)', [
      Sum.JiggleBehaviorCount, Sum.ConeClampedCount]));
    SB.AppendLine(Format('- **Peak Deflection / Tip Speed**: `%.1f°` / `%.2f m/s`', [
      Sum.PeakDeflectionDeg, Sum.PeakTipSpeedMps]));
    if Sum.JiggleBehaviorCount > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('| Bone Mount | Preset | `k` / `zeta` | Deflection / Cone | Tip Speed |');
      SB.AppendLine('| :--- | :--- | :---: | :---: | ---: |');
      AppendRowsRec(ResolveRootTransform(ARoot));
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
