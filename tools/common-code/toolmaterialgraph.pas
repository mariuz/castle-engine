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

{ Stateless editor & headless test helpers for the Visual Node-Based PBR
  Material & X3D Shader Effect Graph Studio (@link(TMaterialGraphHelper))
  (Phase 307 — UE 6.0+ Substrate & Material Editor Parity). }
unit ToolMaterialGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleUIControls, CastleMaterialGraph;

type
  { Audit summary across all @link(TCastleMaterialGraph) assets and
    @link(TCastleMaterialGraphBehavior) bindings in a design. }
  TMaterialGraphAuditReport = class
  public
    Graphs: array of TCastleMaterialGraph;
    Behaviors: array of TCastleMaterialGraphBehavior;
    TotalNodes: Integer;
    VertexOffsetGraphs: Integer;
    AlphaClipGraphs: Integer;
    UnboundBehaviors: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless studio operations for @link(TCastleMaterialGraph) and
    @link(TCastleMaterialGraphBehavior). }
  TMaterialGraphHelper = class
  public
    { Discover all @link(TCastleMaterialGraph) and @link(TCastleMaterialGraphBehavior)
      instances in @code(RootComp) and @code(DesignOwner), running @code(ValidateGraph)
      on every graph. Caller owns the returned @link(TMaterialGraphAuditReport). }
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TMaterialGraphAuditReport; static;

    { Create a new uniquely named @link(TCastleMaterialGraph) registered on
      @code(DesignOwner) (and added to @code(RootComp.NonVisualComponents) when
      @code(RootComp) is a @link(TCastleUserInterface) or @link(TCastleTransform)). }
    class function CreateMaterialGraphInDesign(
      const RootComp, DesignOwner: TComponent;
      const APreset: TMaterialGraphPreset;
      const BaseName: String = 'MaterialGraph'): TCastleMaterialGraph; static;

    { Attach or update @link(TCastleMaterialGraphBehavior) on @code(Target)
      referencing @code(AGraph). }
    class function AttachGraphToTransform(
      const Target: TCastleTransform;
      const DesignOwner: TComponent;
      const AGraph: TCastleMaterialGraph): TCastleMaterialGraphBehavior; static;

    { Spawn a preview @link(TCastleSphere) inside the active @link(TCastleViewport)
      (or under @code(RootComp) if it is a @link(TCastleTransform)) and bind
      @code(AGraph) via @link(TCastleMaterialGraphBehavior). }
    class function SpawnPreviewSphereWithGraph(
      const RootComp, DesignOwner: TComponent;
      const AGraph: TCastleMaterialGraph): TCastleSphere; static;

    { Generate a Markdown summary + GLSL listing report. }
    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent;
      const SelectedGraph: TCastleMaterialGraph = nil): String; static;
  end;

implementation

uses
  CastleComponentSerialize, CastleStringUtils;

function MakeUniqueCompName(const OwnerComp: TComponent; const Base: String): String;
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

function FindFirstViewportInRoot(const C: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  if C = nil then
    Exit(nil);
  if C is TCastleViewport then
    Exit(TCastleViewport(C));
  if C is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(C);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindFirstViewportInRoot(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
  for I := 0 to C.ComponentCount - 1 do
    if C.Components[I] is TCastleViewport then
      Exit(TCastleViewport(C.Components[I]));
  Result := nil;
end;

{ TMaterialGraphAuditReport -------------------------------------------------- }

constructor TMaterialGraphAuditReport.Create;
begin
  inherited;
  Warnings := TStringList.Create;
end;

destructor TMaterialGraphAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TMaterialGraphHelper ------------------------------------------------------- }

class function TMaterialGraphHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TMaterialGraphAuditReport;
var
  Visited: array of TComponent;

  function AlreadyVisited(const C: TComponent): Boolean;
  var
    I: Integer;
  begin
    if C = nil then
      Exit(true);
    for I := 0 to High(Visited) do
      if Visited[I] = C then
        Exit(true);
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := C;
    Result := false;
  end;

  procedure InspectSingle(const C: TComponent);
  var
    G: TCastleMaterialGraph;
    B: TCastleMaterialGraphBehavior;
  begin
    if AlreadyVisited(C) then
      Exit;
    if C is TCastleMaterialGraph then
    begin
      G := TCastleMaterialGraph(C);
      SetLength(Result.Graphs, Length(Result.Graphs) + 1);
      Result.Graphs[High(Result.Graphs)] := G;
      Inc(Result.TotalNodes, G.NodeCount);
      if G.HasVertexOffsetConnection then
        Inc(Result.VertexOffsetGraphs);
      if G.AlphaClipThreshold > 0.0001 then
        Inc(Result.AlphaClipGraphs);
      G.ValidateGraph(Result.Warnings);
    end else
    if C is TCastleMaterialGraphBehavior then
    begin
      B := TCastleMaterialGraphBehavior(C);
      SetLength(Result.Behaviors, Length(Result.Behaviors) + 1);
      Result.Behaviors[High(Result.Behaviors)] := B;
      if B.MaterialGraph = nil then
      begin
        Inc(Result.UnboundBehaviors);
        Result.Warnings.Add(Format(
          'Behavior "%s" has MaterialGraph = nil (using FallbackPreset "%s").',
          [B.Name, TCastleMaterialGraph.PresetDisplayName(B.FallbackPreset)]));
      end;
    end;
  end;

  procedure TraverseHierarchy(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if C = nil then
      Exit;
    InspectSingle(C);

    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        TraverseHierarchy(VP.Items);
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        TraverseHierarchy(UI.Controls[I]);
      for I := 0 to UI.NonVisualComponentsCount - 1 do
        TraverseHierarchy(UI.NonVisualComponents[I]);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        TraverseHierarchy(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        TraverseHierarchy(T.Items[I]);
      for I := 0 to T.NonVisualComponentsCount - 1 do
        TraverseHierarchy(T.NonVisualComponents[I]);
    end;
  end;

var
  I: Integer;
begin
  Result := TMaterialGraphAuditReport.Create;
  TraverseHierarchy(RootComp);
  if DesignOwner <> nil then
    for I := 0 to DesignOwner.ComponentCount - 1 do
      TraverseHierarchy(DesignOwner.Components[I]);
end;

class function TMaterialGraphHelper.CreateMaterialGraphInDesign(
  const RootComp, DesignOwner: TComponent;
  const APreset: TMaterialGraphPreset;
  const BaseName: String): TCastleMaterialGraph;
var
  OwnerToUse: TComponent;
begin
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleMaterialGraph.Create(OwnerToUse);
  Result.Name := MakeUniqueCompName(OwnerToUse, BaseName);
  Result.LoadPreset(APreset);

  if RootComp is TCastleUserInterface then
    TCastleUserInterface(RootComp).AddNonVisualComponent(Result)
  else
  if RootComp is TCastleTransform then
    TCastleTransform(RootComp).AddNonVisualComponent(Result);
end;

class function TMaterialGraphHelper.AttachGraphToTransform(
  const Target: TCastleTransform;
  const DesignOwner: TComponent;
  const AGraph: TCastleMaterialGraph): TCastleMaterialGraphBehavior;
var
  OwnerToUse: TComponent;
begin
  if Target = nil then
    Exit(nil);
  Result := Target.FindBehavior(TCastleMaterialGraphBehavior) as TCastleMaterialGraphBehavior;
  if Result = nil then
  begin
    if DesignOwner <> nil then
      OwnerToUse := DesignOwner
    else
      OwnerToUse := Target.Owner;
    Result := TCastleMaterialGraphBehavior.Create(OwnerToUse);
    Result.Name := MakeUniqueCompName(OwnerToUse, 'MaterialGraphShader');
    Target.AddBehavior(Result);
  end;
  Result.MaterialGraph := AGraph;
  Result.Enabled := true;
  Result.RebuildAndApplyEffect;
end;

class function TMaterialGraphHelper.SpawnPreviewSphereWithGraph(
  const RootComp, DesignOwner: TComponent;
  const AGraph: TCastleMaterialGraph): TCastleSphere;
var
  VP: TCastleViewport;
  ParentTransform: TCastleTransform;
  OwnerToUse: TComponent;
begin
  ParentTransform := nil;
  VP := FindFirstViewportInRoot(RootComp);
  if (VP <> nil) and (VP.Items <> nil) then
    ParentTransform := VP.Items
  else
  if RootComp is TCastleTransform then
    ParentTransform := TCastleTransform(RootComp);

  if ParentTransform = nil then
    Exit(nil);

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleSphere.Create(OwnerToUse);
  Result.Name := MakeUniqueCompName(OwnerToUse, 'MaterialPreviewSphere');
  Result.Radius := 1.0;
  Result.Slices := 32;
  Result.Stacks := 24;
  Result.Translation := Vector3(0.0, 1.2, 0.0);
  ParentTransform.Add(Result);

  if AGraph <> nil then
    AttachGraphToTransform(Result, OwnerToUse, AGraph);
end;

class function TMaterialGraphHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent;
  const SelectedGraph: TCastleMaterialGraph): String;
var
  Report: TMaterialGraphAuditReport;
  SB: TStringBuilder;
  I: Integer;
  G: TCastleMaterialGraph;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Material & Shader Effect Graph Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Material Graphs**: `%d` (`%d` total nodes, `%d` vertex-offset, `%d` alpha-clipped)',
      [Length(Report.Graphs), Report.TotalNodes, Report.VertexOffsetGraphs, Report.AlphaClipGraphs]));
    SB.AppendLine(Format('- **Bound Shader Behaviors**: `%d` (`%d` unbound fallback)',
      [Length(Report.Behaviors), Report.UnboundBehaviors]));
    SB.AppendLine(Format('- **DAG Validation Warnings**: `%d`', [Report.Warnings.Count]));
    SB.AppendLine;

    if Length(Report.Graphs) > 0 then
    begin
      SB.AppendLine('## Material Graphs');
      SB.AppendLine('| Name | Preset | Nodes | AlphaClip | VertexOffset |');
      SB.AppendLine('| :--- | :--- | :---: | :---: | :---: |');
      for I := 0 to High(Report.Graphs) do
      begin
        G := Report.Graphs[I];
        SB.AppendLine(Format('| `%s` | %s | %d | %.2f | %s |',
          [G.Name, TCastleMaterialGraph.PresetDisplayName(G.Preset),
           G.NodeCount, G.AlphaClipThreshold,
           BoolToStr(G.HasVertexOffsetConnection, 'Yes', 'No')]));
      end;
      SB.AppendLine;
    end;

    if Report.Warnings.Count > 0 then
    begin
      SB.AppendLine('## Diagnostics & Warnings');
      for I := 0 to Report.Warnings.Count - 1 do
        SB.AppendLine('- ' + Report.Warnings[I]);
      SB.AppendLine;
    end;

    if SelectedGraph <> nil then
    begin
      SB.AppendLine('## Compiled Vertex GLSL (`' + SelectedGraph.Name + '`)');
      SB.AppendLine('```glsl');
      SB.Append(SelectedGraph.BuildVertexShaderSource);
      SB.AppendLine('```');
      SB.AppendLine;
      SB.AppendLine('## Compiled Fragment GLSL (`' + SelectedGraph.Name + '`)');
      SB.AppendLine('```glsl');
      SB.Append(SelectedGraph.BuildFragmentShaderSource);
      SB.AppendLine('```');
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
