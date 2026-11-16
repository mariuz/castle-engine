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

{ Stateless Editor & Headless Helper for MetaSound Procedural PCM Synthesis,
  Surface-Tagged Footstep Raycasting & Quartz Beat-Quantized Music Stems
  (@link(TMetaSoundStudioHelper), @link(TMetaSoundAuditReport))
  (Phase 322 — UE 6.0+ MetaSounds & Quartz Interactive Music Parity). }
unit ToolMetaSoundStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTransform, CastleViewport, CastleMetaSound;

type
  TMetaSynthArray = array of TCastleMetaSoundSynth;
  TFootstepBehaviorArray = array of TCastleFootstepSurfaceBehavior;
  TMusicDirectorArray = array of TCastleMusicStemDirector;

  { QA summary across all MetaSound synths, footstep behaviors, and Quartz directors. }
  TMetaSoundAuditReport = class
  public
    SynthCount: Integer;
    FootstepCount: Integer;
    MusicDirectorCount: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    Phase 322 procedural audio & interactive music components. }
  TMetaSoundStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanMetaSound(const RootComp, DesignOwner: TComponent;
      out OutSynths: TMetaSynthArray;
      out OutFootsteps: TFootstepBehaviorArray;
      out OutDirectors: TMusicDirectorArray); static;

    class procedure SpawnAudioPlaygroundDemo(
      const RootComp, DesignOwner: TComponent;
      out OutSynth: TCastleMetaSoundSynth;
      out OutWalker: TCastleTransform;
      out OutFootstep: TCastleFootstepSurfaceBehavior;
      out OutDirector: TCastleMusicStemDirector); static;

    class function AuditMetaSound(
      const RootComp, DesignOwner: TComponent): TMetaSoundAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleScene;

constructor TMetaSoundAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TMetaSoundAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TMetaSoundStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
end;

class procedure TMetaSoundStudioHelper.ScanMetaSound(
  const RootComp, DesignOwner: TComponent;
  out OutSynths: TMetaSynthArray;
  out OutFootsteps: TFootstepBehaviorArray;
  out OutDirectors: TMusicDirectorArray);

  procedure AddSynth(const S: TCastleMetaSoundSynth);
  var K: Integer;
  begin
    for K := 0 to High(OutSynths) do if OutSynths[K] = S then Exit;
    SetLength(OutSynths, Length(OutSynths) + 1);
    OutSynths[High(OutSynths)] := S;
  end;

  procedure AddFoot(const F: TCastleFootstepSurfaceBehavior);
  var K: Integer;
  begin
    for K := 0 to High(OutFootsteps) do if OutFootsteps[K] = F then Exit;
    SetLength(OutFootsteps, Length(OutFootsteps) + 1);
    OutFootsteps[High(OutFootsteps)] := F;
  end;

  procedure AddDir(const D: TCastleMusicStemDirector);
  var K: Integer;
  begin
    for K := 0 to High(OutDirectors) do if OutDirectors[K] = D then Exit;
    SetLength(OutDirectors, Length(OutDirectors) + 1);
    OutDirectors[High(OutDirectors)] := D;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleMetaSoundSynth then
      AddSynth(TCastleMetaSoundSynth(C))
    else if C is TCastleFootstepSurfaceBehavior then
      AddFoot(TCastleFootstepSurfaceBehavior(C))
    else if C is TCastleMusicStemDirector then
      AddDir(TCastleMusicStemDirector(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutSynths := nil;
  OutFootsteps := nil;
  OutDirectors := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TMetaSoundStudioHelper.SpawnAudioPlaygroundDemo(
  const RootComp, DesignOwner: TComponent;
  out OutSynth: TCastleMetaSoundSynth;
  out OutWalker: TCastleTransform;
  out OutFootstep: TCastleFootstepSurfaceBehavior;
  out OutDirector: TCastleMusicStemDirector);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  StonePad, WoodPad, MetalPad, WalkerBox: TCastleBox;
  Idx: Integer;
begin
  OutSynth := nil;
  OutWalker := nil;
  OutFootstep := nil;
  OutDirector := nil;

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
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('MetaSoundSynth_' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  StonePad := TCastleBox.Create(OwnerToUse);
  StonePad.Name := 'StoneWalkwayPad' + IntToStr(Idx);
  StonePad.Size := Vector3(5.0, 0.4, 5.0);
  StonePad.Translation := Vector3(-5.0, -0.2, 0.0);
  StonePad.Color := Vector4(0.52, 0.54, 0.58, 1.0);
  ParentTrans.Add(StonePad);

  WoodPad := TCastleBox.Create(OwnerToUse);
  WoodPad.Name := 'WoodenBridgePad' + IntToStr(Idx);
  WoodPad.Size := Vector3(5.0, 0.4, 5.0);
  WoodPad.Translation := Vector3(0.0, -0.2, 0.0);
  WoodPad.Color := Vector4(0.58, 0.38, 0.22, 1.0);
  ParentTrans.Add(WoodPad);

  MetalPad := TCastleBox.Create(OwnerToUse);
  MetalPad.Name := 'MetalGratePad' + IntToStr(Idx);
  MetalPad.Size := Vector3(5.0, 0.4, 5.0);
  MetalPad.Translation := Vector3(5.0, -0.2, 0.0);
  MetalPad.Color := Vector4(0.68, 0.74, 0.82, 1.0);
  ParentTrans.Add(MetalPad);

  WalkerBox := TCastleBox.Create(OwnerToUse);
  WalkerBox.Name := 'FootstepWalkerActor' + IntToStr(Idx);
  WalkerBox.Size := Vector3(0.75, 1.80, 0.55);
  WalkerBox.Translation := Vector3(-5.0, 0.90, 0.0);
  WalkerBox.Color := Vector4(0.28, 0.78, 0.94, 1.0);
  ParentTrans.Add(WalkerBox);

  OutFootstep := TCastleFootstepSurfaceBehavior.Create(OwnerToUse);
  OutFootstep.Name := 'FootstepSurface_' + IntToStr(Idx);
  WalkerBox.AddBehavior(OutFootstep);
  OutFootstep.DetectSurfaceUnderFoot;

  OutSynth := TCastleMetaSoundSynth.Create(OwnerToUse);
  OutSynth.Name := 'MetaSoundSynth_' + IntToStr(Idx);
  OutSynth.ApplyPreset(mspLaserZapDownSweep);

  OutDirector := TCastleMusicStemDirector.Create(OwnerToUse);
  OutDirector.Name := 'QuartzMusicDirector_' + IntToStr(Idx);

  OutWalker := WalkerBox;
end;

class function TMetaSoundStudioHelper.AuditMetaSound(
  const RootComp, DesignOwner: TComponent): TMetaSoundAuditReport;
var
  Synths: TMetaSynthArray;
  Foots: TFootstepBehaviorArray;
  Dirs: TMusicDirectorArray;
  I: Integer;
begin
  Result := TMetaSoundAuditReport.Create;
  ScanMetaSound(RootComp, DesignOwner, Synths, Foots, Dirs);
  Result.SynthCount := Length(Synths);
  Result.FootstepCount := Length(Foots);
  Result.MusicDirectorCount := Length(Dirs);

  for I := 0 to High(Synths) do
    if Synths[I].MasterGain <= 0.001 then
      Result.Warnings.Add(Format(
        'MetaSoundSynth "%s" has MasterGain = 0 — synthesized WAV output will be silent.',
        [Synths[I].Name]));
end;

class function TMetaSoundStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Synths: TMetaSynthArray;
  Foots: TFootstepBehaviorArray;
  Dirs: TMusicDirectorArray;
  Rep: TMetaSoundAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanMetaSound(RootComp, DesignOwner, Synths, Foots, Dirs);
  Rep := AuditMetaSound(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# MetaSound Procedural Synth, Surface Footsteps & Quartz Music Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **MetaSound Synths:** %d  |  **Surface Footsteps:** %d  |  **Quartz Directors:** %d',
      [Rep.SynthCount, Rep.FootstepCount, Rep.MusicDirectorCount]));
    SB.AppendLine('');
    for I := 0 to High(Synths) do
      SB.AppendLine(Format('- `%s`: %s', [Synths[I].Name, Synths[I].SynthSummaryBadge]));
    for I := 0 to High(Foots) do
      SB.AppendLine(Format('- `%s`: %s', [Foots[I].Name, Foots[I].FootstepSummaryBadge]));
    for I := 0 to High(Dirs) do
      SB.AppendLine(Format('- `%s`: %s', [Dirs[I].Name, Dirs[I].MusicSummaryBadge]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
