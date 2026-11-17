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

{ Stateless helper for the Control Rig Procedural Multi-Bone Chain, FABRIK
  Solver, Twist Distribution & Aim-At Rig Studio (Phase 338). }
unit ToolControlRig;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleControlRig;

type
  TControlRigStudioSummary = record
    RigCount: Integer;
    TotalJoints: Integer;
    MaxLengthDriftMeters: Single;
    WarningsCount: Integer;
  end;

  TControlRigHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstControlRig(const ARoot: TComponent): TCastleControlRigBehavior; static;

    class function SpawnRoboticArmControlRigDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ARigHost, AEffectorTarget: TCastleTransform;
      out ARig: TCastleControlRigBehavior): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TControlRigStudioSummary; static;

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

class function TControlRigHelper.ResolveRootTransform(
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

class function TControlRigHelper.FindFirstControlRig(
  const ARoot: TComponent): TCastleControlRigBehavior;

  function ScanRec(const T: TCastleTransform): TCastleControlRigBehavior;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleControlRigBehavior then
        Exit(TCastleControlRigBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TControlRigHelper.SpawnRoboticArmControlRigDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ARigHost, AEffectorTarget: TCastleTransform;
  out ARig: TCastleControlRigBehavior): Boolean;
var
  RootT: TCastleTransform;
  BaseBox: TCastleBox;
  TargetSphere: TCastleSphere;
begin
  ARigHost := nil;
  AEffectorTarget := nil;
  ARig := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  TargetSphere := TCastleSphere.Create(ADesignOwner);
  TargetSphere.Name := MakeUniqueName(ADesignOwner, 'ControlRigEffectorTarget');
  TargetSphere.Radius := 0.22;
  TargetSphere.Translation := Vector3(1.2, 2.0, 1.5);
  TargetSphere.Color := Vector4(1.0, 0.78, 0.22, 1.0);
  RootT.Add(TargetSphere);
  AEffectorTarget := TargetSphere;

  BaseBox := TCastleBox.Create(ADesignOwner);
  BaseBox.Name := MakeUniqueName(ADesignOwner, 'ControlRigPedestal');
  BaseBox.Size := Vector3(0.6, 0.3, 0.6);
  BaseBox.Translation := Vector3(0.0, 0.0, 0.0);
  BaseBox.Color := Vector4(0.32, 0.42, 0.56, 1.0);
  RootT.Add(BaseBox);
  ARigHost := BaseBox;

  ARig := TCastleControlRigBehavior.Create(ADesignOwner);
  ARig.Name := MakeUniqueName(ADesignOwner, 'ControlRigArmBehavior');
  ARig.EffectorTargetName := TargetSphere.Name;
  BaseBox.AddBehavior(ARig);
  ARig.ApplyPreset(crpRoboticArmFabrik);
  ARig.SolveRig(0.0);
  Result := True;
end;

class function TControlRigHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TControlRigStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    R: TCastleControlRigBehavior;
    Drift: Single;
  begin
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleControlRigBehavior then
      begin
        R := TCastleControlRigBehavior(T.Behaviors[I]);
        Inc(Result.RigCount);
        Result.TotalJoints := Result.TotalJoints + R.JointCount;
        Drift := R.MaxSegmentLengthDrift;
        if Drift > Result.MaxLengthDriftMeters then
          Result.MaxLengthDriftMeters := Drift;
        if (not R.EnableProceduralWave) and (R.EffectorTargetName = '') then
        begin
          Inc(Result.WarningsCount);
          if AWarnings <> nil then
            AWarnings.Add(Format('%s has empty EffectorTargetName — bind a target transform.', [R.Name]));
        end;
      end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TControlRigStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TControlRigHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TControlRigStudioSummary;
  Rig: TCastleControlRigBehavior;
  SB: TStringBuilder;
  I: Integer;
  J: TControlRigJoint;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    Rig := FindFirstControlRig(ARoot);
    SB.AppendLine('# Castle Game Engine — Control Rig Multi-Bone FABRIK & Twist Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Control Rig Behaviors**: `%d` (`%d` total joints, max length drift `%.5f m`)', [
      Sum.RigCount, Sum.TotalJoints, Sum.MaxLengthDriftMeters]));
    if Rig <> nil then
    begin
      SB.AppendLine(Format('- **Active Chain (`%s`)**: `%d` joints, `%.2f m` reach, `%d` FABRIK iters, `%.4f m` tip error', [
        Rig.Name, Rig.JointCount, Rig.TotalChainLength,
        Rig.LastIterationsUsed, Rig.LastTipErrorMeters]));
      SB.AppendLine;
      SB.AppendLine('| Joint | World Position `(m)` | Seg Len `(m)` | Progressive Twist `(deg)` |');
      SB.AppendLine('| :--- | :--- | ---: | ---: |');
      for I := 0 to Rig.JointCount - 1 do
      begin
        J := Rig.GetJoint(I);
        SB.AppendLine(Format('| `%s` | `(%.2f, %.2f, %.2f)` | %.2f | %.1f° |', [
          J.Name, J.WorldPos.X, J.WorldPos.Y, J.WorldPos.Z,
          J.RestSegmentLength, J.TwistRollDeg]));
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
