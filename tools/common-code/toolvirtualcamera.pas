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

{ Stateless editor & headless test helpers for the Virtual Camera Priority
  Blending, Spline Dolly Rail, Deadzone Composer & Perlin Trauma Shake Studio
  (@link(TVirtualCameraHelper)) (Phase 312 — UE 6.0+ Gameplay Cameras Parity). }
unit ToolVirtualCamera;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleViewport,
  CastleUIControls, CastleSplinePath, CastleVirtualCamera;

type
  { Audit report summarizing all @link(TCastleVirtualCamera) rigs and
    @link(TCastleVirtualCameraBrain) directors in a design. }
  TVirtualCameraAuditReport = class
  public
    VCams: array of TCastleVirtualCamera;
    Brains: array of TCastleVirtualCameraBrain;
    WinningVCam: TCastleVirtualCamera;
    ActiveRigCount: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring, simulation & Markdown helper for Virtual Cameras. }
  TVirtualCameraHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TVirtualCameraAuditReport; static;

    class function ResolveTransformContainer(const RootComp: TComponent): TCastleTransform; static;
    class function ResolveMainCamera(const RootComp, DesignOwner: TComponent): TCastleCamera; static;

    { Ensure a @link(TCastleVirtualCameraBrain) is attached to the active
      @link(TCastleCamera) in the design (creating a camera if none exists). }
    class function EnsureBrainOnViewportCamera(
      const RootComp, DesignOwner: TComponent;
      const ABlendDurationSec: Single = 1.0): TCastleVirtualCameraBrain; static;

    { Spawn a fixed establishing wide-shot @link(TCastleVirtualCamera) rig. }
    class function SpawnFixedEstablishingVCam(
      const RootComp, DesignOwner: TComponent;
      const APos: TVector3;
      const ALookTarget: TCastleTransform;
      const APriority: Integer = 10;
      const ABaseName: String = 'VCamEstablishing'): TCastleVirtualCamera; static;

    { Spawn a damped third-person follow + screen-space deadzone composer rig. }
    class function SpawnThirdPersonFollowVCam(
      const RootComp, DesignOwner: TComponent;
      const AFollowAndLookTarget: TCastleTransform;
      const APriority: Integer = 20;
      const ABaseName: String = 'VCamThirdPerson'): TCastleVirtualCamera; static;

    { Spawn a @link(TCastleSplinePath) dolly rail + @link(TCastleVirtualCamera) rig. }
    class function SpawnSplineDollyVCam(
      const RootComp, DesignOwner: TComponent;
      const ALookTarget: TCastleTransform;
      const APriority: Integer = 30;
      const ABaseName: String = 'VCamDollyRail'): TCastleVirtualCamera; static;

    { Add normalized camera shake trauma to all @link(TCastleVirtualCameraBrain) instances. }
    class procedure TriggerTraumaOnAllBrains(
      const RootComp, DesignOwner: TComponent; const AAmount: Single); static;

    { Step all @link(TCastleVirtualCameraBrain) directors by @code(Dt). }
    class procedure StepAllCameraBrains(
      const RootComp, DesignOwner: TComponent; const Dt: Single); static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils, CastleBehaviors;

function MakeUniqueVCamName(const OwnerComp: TComponent; const Base: String): String;
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

function BodyModeToStr(const M: TVirtualCameraBodyMode): String;
begin
  case M of
    vcbFixedTransform:    Result := 'FixedTransform';
    vcbThirdPersonFollow: Result := 'ThirdPersonFollow';
    vcbSplineDollyRail:   Result := 'SplineDollyRail';
  end;
end;

function AimModeToStr(const M: TVirtualCameraAimMode): String;
begin
  case M of
    vcaFixedDirection:   Result := 'FixedDirection';
    vcaHardLookAt:       Result := 'HardLookAt';
    vcaDeadzoneComposer: Result := 'DeadzoneComposer';
  end;
end;

function BlendCurveToStr(const C: TVirtualCameraBlendCurve): String;
begin
  case C of
    vcbcHardCut:        Result := 'HardCut';
    vcbcLinear:         Result := 'Linear';
    vcbcSmoothStep:     Result := 'SmoothStep';
    vcbcEaseInOutCubic: Result := 'EaseInOutCubic';
  end;
end;

{ TVirtualCameraAuditReport -------------------------------------------------- }

constructor TVirtualCameraAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TVirtualCameraAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TVirtualCameraHelper ------------------------------------------------------- }

class function TVirtualCameraHelper.ResolveTransformContainer(
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

class function TVirtualCameraHelper.ResolveMainCamera(
  const RootComp, DesignOwner: TComponent): TCastleCamera;
var
  I: Integer;
  UI: TCastleUserInterface;
  T: TCastleTransform;
begin
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp).Camera);
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
      if UI.Controls[I] is TCastleViewport then
        Exit(TCastleViewport(UI.Controls[I]).Camera);
  end;
  if RootComp is TCastleTransform then
  begin
    T := TCastleTransform(RootComp);
    if T is TCastleCamera then
      Exit(TCastleCamera(T));
    for I := 0 to T.Count - 1 do
      if T[I] is TCastleCamera then
        Exit(TCastleCamera(T[I]));
  end;
  if DesignOwner <> nil then
    for I := 0 to DesignOwner.ComponentCount - 1 do
      if DesignOwner.Components[I] is TCastleCamera then
        Exit(TCastleCamera(DesignOwner.Components[I]));
  Result := nil;
end;

class function TVirtualCameraHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TVirtualCameraAuditReport;
var
  FoundVCams, FoundBrains: TList;

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if C = nil then
      Exit;
    if (C is TCastleVirtualCamera) and (FoundVCams.IndexOf(C) < 0) then
      FoundVCams.Add(C);
    if (C is TCastleVirtualCameraBrain) and (FoundBrains.IndexOf(C) < 0) then
      FoundBrains.Add(C);

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
      begin
        for I := 0 to T.BehaviorsCount - 1 do
          Traverse(T.Behaviors[I]);
        for I := 0 to T.Count - 1 do
          Traverse(T[I]);
      end;
    end;
  end;

var
  I: Integer;
  V: TCastleVirtualCamera;
begin
  Result := TVirtualCameraAuditReport.Create;
  FoundVCams := TList.Create;
  FoundBrains := TList.Create;
  try
    Traverse(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        Traverse(DesignOwner.Components[I]);

    SetLength(Result.VCams, FoundVCams.Count);
    for I := 0 to FoundVCams.Count - 1 do
    begin
      V := TCastleVirtualCamera(FoundVCams[I]);
      Result.VCams[I] := V;
      if V.ActiveRig and V.Exists then
      begin
        Inc(Result.ActiveRigCount);
        if (Result.WinningVCam = nil) or (V.Priority > Result.WinningVCam.Priority) then
          Result.WinningVCam := V;
      end;
      if (V.BodyMode = vcbThirdPersonFollow) and (V.FollowTarget = nil) then
        Result.Warnings.Add(Format('%s uses vcbThirdPersonFollow without a FollowTarget.', [V.Name]));
      if (V.BodyMode = vcbSplineDollyRail) and (V.DollySpline = nil) then
        Result.Warnings.Add(Format('%s uses vcbSplineDollyRail without a DollySpline.', [V.Name]));
      if (V.AimMode in [vcaHardLookAt, vcaDeadzoneComposer]) and (V.LookAtTarget = nil) then
        Result.Warnings.Add(Format('%s uses %s without a LookAtTarget.', [V.Name, AimModeToStr(V.AimMode)]));
    end;

    SetLength(Result.Brains, FoundBrains.Count);
    for I := 0 to FoundBrains.Count - 1 do
      Result.Brains[I] := TCastleVirtualCameraBrain(FoundBrains[I]);

    if (Length(Result.VCams) > 0) and (Length(Result.Brains) = 0) then
      Result.Warnings.Add('Virtual Camera rigs exist without a TCastleVirtualCameraBrain attached to the active camera.');
  finally
    FreeAndNil(FoundBrains);
    FreeAndNil(FoundVCams);
  end;
end;

class function TVirtualCameraHelper.EnsureBrainOnViewportCamera(
  const RootComp, DesignOwner: TComponent;
  const ABlendDurationSec: Single): TCastleVirtualCameraBrain;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
  Cam: TCastleCamera;
  Existing: TCastleBehavior;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Cam := ResolveMainCamera(RootComp, DesignOwner);
  if Cam = nil then
  begin
    Container := ResolveTransformContainer(RootComp);
    Cam := TCastleCamera.Create(OwnerToUse);
    Cam.Name := MakeUniqueVCamName(OwnerToUse, 'DrivenCamera');
    if Container <> nil then
      Container.Add(Cam);
  end;

  Existing := Cam.FindBehavior(TCastleVirtualCameraBrain);
  if Existing <> nil then
    Exit(TCastleVirtualCameraBrain(Existing));

  Result := TCastleVirtualCameraBrain.Create(OwnerToUse);
  Result.Name := MakeUniqueVCamName(OwnerToUse, 'VirtualCameraBrain');
  Result.BlendDurationSec := ABlendDurationSec;
  Result.TargetCamera := Cam;
  Cam.AddBehavior(Result);
end;

class function TVirtualCameraHelper.SpawnFixedEstablishingVCam(
  const RootComp, DesignOwner: TComponent;
  const APos: TVector3;
  const ALookTarget: TCastleTransform;
  const APriority: Integer;
  const ABaseName: String): TCastleVirtualCamera;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleVirtualCamera.Create(OwnerToUse);
  Result.Name := MakeUniqueVCamName(OwnerToUse, ABaseName);
  Result.SetView(APos, Vector3(0.0, -0.25, -1.0).Normalize, Vector3(0.0, 1.0, 0.0));
  Result.Priority := APriority;
  Result.FieldOfViewDeg := 62.0;
  Result.BodyMode := vcbFixedTransform;
  if ALookTarget <> nil then
  begin
    Result.AimMode := vcaHardLookAt;
    Result.LookAtTarget := ALookTarget;
  end else
    Result.AimMode := vcaFixedDirection;

  Container := ResolveTransformContainer(RootComp);
  if Container <> nil then
    Container.Add(Result);
end;

class function TVirtualCameraHelper.SpawnThirdPersonFollowVCam(
  const RootComp, DesignOwner: TComponent;
  const AFollowAndLookTarget: TCastleTransform;
  const APriority: Integer;
  const ABaseName: String): TCastleVirtualCamera;
var
  OwnerToUse: TComponent;
  Container, TargetT: TCastleTransform;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Container := ResolveTransformContainer(RootComp);
  TargetT := AFollowAndLookTarget;
  if (TargetT = nil) and (Container <> nil) then
  begin
    TargetT := TCastleTransform.Create(OwnerToUse);
    TargetT.Name := MakeUniqueVCamName(OwnerToUse, 'VCamSubjectPivot');
    TargetT.Translation := Vector3(0.0, 1.0, 0.0);
    Container.Add(TargetT);
  end;

  Result := TCastleVirtualCamera.Create(OwnerToUse);
  Result.Name := MakeUniqueVCamName(OwnerToUse, ABaseName);
  Result.SetView(Vector3(0.0, 3.2, 6.5), Vector3(0.0, -0.2, -1.0).Normalize, Vector3(0.0, 1.0, 0.0));
  Result.Priority := APriority;
  Result.FieldOfViewDeg := 52.0;
  Result.BodyMode := vcbThirdPersonFollow;
  Result.FollowTarget := TargetT;
  Result.FollowOffset := Vector3(0.0, 2.2, 5.5);
  Result.AimMode := vcaDeadzoneComposer;
  Result.LookAtTarget := TargetT;
  Result.DeadzoneWidthDeg := 12.0;
  Result.DeadzoneHeightDeg := 8.0;

  if Container <> nil then
    Container.Add(Result);
end;

class function TVirtualCameraHelper.SpawnSplineDollyVCam(
  const RootComp, DesignOwner: TComponent;
  const ALookTarget: TCastleTransform;
  const APriority: Integer;
  const ABaseName: String): TCastleVirtualCamera;
var
  OwnerToUse: TComponent;
  Container: TCastleTransform;
  Rail: TCastleSplinePath;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Container := ResolveTransformContainer(RootComp);

  Rail := TCastleSplinePath.Create(OwnerToUse);
  Rail.Name := MakeUniqueVCamName(OwnerToUse, ABaseName + 'Path');
  Rail.ClearControlPoints;
  Rail.AddControlPoint(Vector3(-8.0, 2.5, 8.0), 0.0, 1.0);
  Rail.AddControlPoint(Vector3(0.0, 3.5, 10.0), 0.0, 1.0);
  Rail.AddControlPoint(Vector3(8.0, 2.5, 6.0), 0.0, 1.0);
  Rail.MeshMode := smNone;
  if Container <> nil then
    Container.Add(Rail);

  Result := TCastleVirtualCamera.Create(OwnerToUse);
  Result.Name := MakeUniqueVCamName(OwnerToUse, ABaseName);
  Result.Priority := APriority;
  Result.FieldOfViewDeg := 45.0;
  Result.BodyMode := vcbSplineDollyRail;
  Result.DollySpline := Rail;
  Result.DollyNormalizedT := 0.0;
  if ALookTarget <> nil then
  begin
    Result.AimMode := vcaHardLookAt;
    Result.LookAtTarget := ALookTarget;
  end else
    Result.AimMode := vcaFixedDirection;

  if Container <> nil then
    Container.Add(Result);
end;

class procedure TVirtualCameraHelper.TriggerTraumaOnAllBrains(
  const RootComp, DesignOwner: TComponent; const AAmount: Single);
var
  Report: TVirtualCameraAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Brains) do
      Report.Brains[I].AddTrauma(AAmount);
  finally
    FreeAndNil(Report);
  end;
end;

class procedure TVirtualCameraHelper.StepAllCameraBrains(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Report: TVirtualCameraAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Brains) do
      Report.Brains[I].StepBrain(Dt);
  finally
    FreeAndNil(Report);
  end;
end;

class function TVirtualCameraHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TVirtualCameraAuditReport;
  SB: TStringBuilder;
  I: Integer;
  V: TCastleVirtualCamera;
  B: TCastleVirtualCameraBrain;
  WinName: String;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    if Report.WinningVCam <> nil then
      WinName := Report.WinningVCam.Name
    else
      WinName := 'None';

    SB.AppendLine('# Virtual Camera Director, Dolly Rail & Trauma Shake Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Virtual Cameras**: %d (`%d` active) | **Director Brains**: %d | **Winning Rig**: `%s`',
      [Length(Report.VCams), Report.ActiveRigCount, Length(Report.Brains), WinName]));
    SB.AppendLine;

    if Length(Report.Brains) > 0 then
    begin
      SB.AppendLine('## Director Brains');
      SB.AppendLine('| Brain |Blend Curve | Duration (s) | Trauma | Blending |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Report.Brains) do
      begin
        B := Report.Brains[I];
        SB.AppendLine(Format('| `%s` | %s | %.2f | %.2f | %s |',
          [B.Name, BlendCurveToStr(B.BlendCurve), B.BlendDurationSec,
           B.Trauma, BoolToStr(B.IsBlending, True)]));
      end;
      SB.AppendLine;
    end;

    if Length(Report.VCams) > 0 then
    begin
      SB.AppendLine('## Virtual Camera Rigs');
      SB.AppendLine('| Rig | Active | Priority | FOV (°) | Body Mode | Aim Mode | Dolly T |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Report.VCams) do
      begin
        V := Report.VCams[I];
        SB.AppendLine(Format('| `%s` | %s | %d | %.1f | %s | %s | %.2f |',
          [V.Name, BoolToStr(V.ActiveRig, True), V.Priority, V.FieldOfViewDeg,
           BodyModeToStr(V.BodyMode), AimModeToStr(V.AimMode), V.DollyNormalizedT]));
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
