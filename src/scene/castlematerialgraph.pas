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

{ Visual node-based PBR Material & X3D Shader Effect Graph component and
  behavior (@link(TCastleMaterialGraph), @link(TCastleMaterialGraphBehavior))
  compiling directed acyclic shader graphs into Castle Game Engine @code(PLUG_*)
  GLSL vertex & fragment shaders (Phase 307 — UE 6.0+ Substrate & Material Graph Parity). }
unit CastleMaterialGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleCameras, CastleTransform,
  CastleBehaviors, CastleScene, X3DNodes, X3DFields;

type
  { Typed shader graph node kinds supported by @link(TCastleMaterialGraph). }
  TMaterialNodeKind = (
    mnkTime,
    mnkObjectPos,
    mnkWorldNormal,
    mnkFresnel,
    mnkConstantFloat,
    mnkConstantColor,
    mnkNoise3D,
    mnkVoronoi3D,
    mnkChecker3D,
    mnkSineWave,
    mnkAdd,
    mnkMultiply,
    mnkMixColor,
    mnkRemapSmoothstep,
    mnkVertexWaveOffset,
    mnkPbrOutput
  );

  { Built-in 1-click PBR & procedural shader graph presets. }
  TMaterialGraphPreset = (
    mgpCustom,
    mgpTriplanarMossyRock,
    mgpHologramScanline,
    mgpMoltenLavaCracks,
    mgpBrushedGoldMetal,
    mgpAnimatedWindWaveFoliage
  );

  { Value dimensionality of a node's output in GLSL & CPU evaluation. }
  TMaterialValueType = (
    mvtFloat,
    mvtVec3
  );

  { Single node inside a @link(TCastleMaterialGraph) DAG. }
  TMaterialGraphNode = record
    NodeId: String;
    Kind: TMaterialNodeKind;
    PosX: Single;
    PosY: Single;
    ParamA: Single;
    ParamB: Single;
    ParamC: Single;
    ColorVal: TVector3;
    SecondaryColor: TVector3;
    { Source NodeIds connected to input pins 0..5 (empty string = disconnected).
      For mnkPbrOutput:
        Inputs[0] = BaseColor (vec3)
        Inputs[1] = Metallic (float)
        Inputs[2] = Roughness (float)
        Inputs[3] = Emissive (vec3)
        Inputs[4] = Opacity (float)
        Inputs[5] = PositionOffset (vec3, vertex shader) }
    Inputs: array[0..5] of String;
  end;

  TMaterialGraphNodeArray = array of TMaterialGraphNode;

  { Reusable non-visual directed acyclic PBR shader graph asset component.
    Serializes all nodes, connections, parameters, and canvas layout inside
    diff-friendly @link(GraphJson), validates DAG integrity via @link(ValidateGraph),
    evaluates a software raytraced PBR preview sphere via @link(EvaluatePreviewPixel),
    and compiles CGE @code(PLUG_*) Vertex & Fragment GLSL shaders. }
  TCastleMaterialGraph = class(TCastleComponent)
  public
    const
      DefaultAlphaClipThreshold = 0.0;
  strict private
    FPreset: TMaterialGraphPreset;
    FAlphaClipThreshold: Single;
    FNodes: TMaterialGraphNodeArray;
    FRevision: Cardinal;

    function GetGraphJson: String;
    procedure SetGraphJson(const Value: String);
    procedure SetPreset(const Value: TMaterialGraphPreset);
    procedure SetAlphaClipThreshold(const Value: Single);
    procedure BumpRevision;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function NodeKindDisplayName(const AKind: TMaterialNodeKind): String; static;
    class function NodeOutputType(const AKind: TMaterialNodeKind): TMaterialValueType; static;
    class function NodeInputCount(const AKind: TMaterialNodeKind): Integer; static;
    class function NodeInputPinName(const AKind: TMaterialNodeKind; const PinIndex: Integer): String; static;
    class function PresetDisplayName(const APreset: TMaterialGraphPreset): String; static;
    class function MakeDefaultNode(const ANodeId: String; const AKind: TMaterialNodeKind;
      const AX: Single = 100.0; const AY: Single = 100.0): TMaterialGraphNode; static;

    { Direct access to the graph's node array. Call @link(SetNodes) after mutating. }
    property Nodes: TMaterialGraphNodeArray read FNodes;
    procedure SetNodes(const ANodes: TMaterialGraphNodeArray);

    function NodeCount: Integer;
    function FindNodeIndex(const ANodeId: String): Integer;
    function FindOutputNodeIndex: Integer;
    function HasVertexOffsetConnection: Boolean;

    procedure ClearNodes;
    function AddOrUpdateNode(const ANode: TMaterialGraphNode): Integer;
    function RemoveNode(const ANodeId: String): Boolean;
    function ConnectPin(const TargetNodeId: String; const TargetPinIndex: Integer;
      const SourceNodeId: String): Boolean;

    { Populate the graph with one of the 5 built-in presets. }
    procedure LoadPreset(const APreset: TMaterialGraphPreset);

    { Validate unique NodeIds, broken pin references, missing mnkPbrOutput,
      and directed cycles (3-color DFS). Appends human-readable diagnostics
      to @code(Errors) and returns @true iff the graph is a valid acyclic DAG. }
    function ValidateGraph(const Errors: TStrings): Boolean;

    { Compute a deterministic topological evaluation order for the subgraph
      reachable from @code(RootNodeIndices). Returns @false if a cycle exists. }
    function BuildTopologicalOrder(const RootNodeIndices: array of Integer;
      out OrderedIndices: array of Integer; out OrderedCount: Integer): Boolean;

    { Compile CGE GLSL Vertex Shader (@code(PLUG_vertex_object_space) or
      @code(PLUG_vertex_object_space_change)). }
    function BuildVertexShaderSource: String;

    { Compile CGE GLSL Fragment Shader (@code(PLUG_main_texture_apply),
      @code(PLUG_material_metallic_roughness), and @code(PLUG_lighting_apply)). }
    function BuildFragmentShaderSource: String;

    { Evaluate a software-raytraced PBR preview sphere at normalized canvas
      coordinates @code(U, V in [0..1]) at animation time @code(TimeSec).
      Alpha-clipped or background pixels return @code(Alpha < 1) over a dark
      studio checker pattern when @code(CompositeBackground = true). }
    function EvaluatePreviewPixel(const U, V, TimeSec: Single;
      const CompositeBackground: Boolean = true): TCastleColor;

    { Monotonically increasing revision counter so bound behaviors know when
      to rebuild their X3D @link(TEffectNode). }
    property Revision: Cardinal read FRevision;

    function GraphSummaryBadge: String;
  published
    property Preset: TMaterialGraphPreset read FPreset write SetPreset default mgpTriplanarMossyRock;
    property AlphaClipThreshold: Single read FAlphaClipThreshold write SetAlphaClipThreshold
      {$ifdef FPC}default DefaultAlphaClipThreshold{$endif};
    property GraphJson: String read GetGraphJson write SetGraphJson stored true;
  end;

  { Behavior attaching a @link(TCastleMaterialGraph) (or an inline fallback
    preset graph) as a live X3D @link(TEffectNode) with @code(stVertex) and
    @code(stFragment) GLSL parts plus an animated @code(cge_mat_time) uniform
    onto any @link(TCastleScene), @link(TCastleAbstractPrimitive), or
    @link(TCastleImageTransform). }
  TCastleMaterialGraphBehavior = class(TCastleBehavior)
  public
    const
      EffectNodeName = 'CastleMaterialGraphEffect';
  strict private
    FEnabled: Boolean;
    FMaterialGraph: TCastleMaterialGraph;
    FFallbackPreset: TMaterialGraphPreset;
    FTimeScale: Single;
    FElapsedTime: Single;
    FEffectNode: TEffectNode;
    FFdTime: TSFFloat;
    FAppliedRootNode: TX3DRootNode;
    FLastGraphRevision: Cardinal;
    FDirty: Boolean;

    procedure SetEnabled(const Value: Boolean);
    procedure SetMaterialGraph(const Value: TCastleMaterialGraph);
    procedure SetFallbackPreset(const Value: TMaterialGraphPreset);
    procedure SetTimeScale(const Value: Single);
    procedure ReleaseCurrentEffectNode;
    procedure DetachCurrentEffectFromParent(const TargetParent: TCastleTransform);
    procedure AttachEffectToParent(const TargetParent: TCastleTransform);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function CanAttachToParent(const NewParent: TCastleTransform;
      out ReasonWhyCannot: String): Boolean; override;
    procedure ParentAfterAttach; override;
    procedure ParentBeforeDetach; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    procedure BeforeRender(
      const CameraView: TViewVectors;
      const ParentParentWorldTransformation: TTransformation); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    property ActiveEffectNode: TEffectNode read FEffectNode;
    property ActiveTimeField: TSFFloat read FFdTime;
    property ElapsedTime: Single read FElapsedTime write FElapsedTime;

    function BuildEffectNode: TEffectNode;
    procedure RebuildAndApplyEffect;
    function BehaviorSummaryBadge: String;
  published
    property Enabled: Boolean read FEnabled write SetEnabled default true;
    property MaterialGraph: TCastleMaterialGraph read FMaterialGraph write SetMaterialGraph;
    property FallbackPreset: TMaterialGraphPreset read FFallbackPreset write SetFallbackPreset
      default mgpTriplanarMossyRock;
    property TimeScale: Single read FTimeScale write SetTimeScale {$ifdef FPC}default 1.0{$endif};
  end;

function ProceduralNoise3D(const P: TVector3): Single;
function ProceduralVoronoi3D(const P: TVector3; const Jitter: Single): Single;
function ProceduralChecker3D(const P: TVector3): Single;

implementation

uses
  Math, TypInfo, fpjson, jsonparser,
  CastleUtils, CastleStringUtils, CastleRenderOptions, CastleComponentSerialize;

{ Procedural CPU Noise / Voronoi / Checker Helpers --------------------------- }

function FractFloat(const X: Single): Single; inline;
begin
  Result := X - Floor(X);
end;

function SmoothStepFloat(const Edge0, Edge1, X: Single): Single; inline;
var
  T: Single;
begin
  if SameValue(Edge0, Edge1, 1e-6) then
  begin
    if X >= Edge0 then
      Result := 1.0
    else
      Result := 0.0;
    Exit;
  end;
  T := Clamped((X - Edge0) / (Edge1 - Edge0), 0.0, 1.0);
  Result := T * T * (3.0 - 2.0 * T);
end;

function Hash3To1(const P: TVector3): Single; inline;
var
  QX, QY, QZ, D: Single;
begin
  QX := FractFloat(P.X * 0.1031);
  QY := FractFloat(P.Y * 0.1030);
  QZ := FractFloat(P.Z * 0.0973);
  D := QX * (QY + 33.33) + QY * (QX + 33.33) + QZ * (QZ + 33.33);
  QX := QX + D;
  QY := QY + D;
  QZ := QZ + D;
  Result := FractFloat((QX + QY) * QZ);
end;

function Hash3To3(const P: TVector3): TVector3; inline;
begin
  Result := Vector3(
    Hash3To1(P),
    Hash3To1(P + Vector3(17.13, 31.71, 47.29)),
    Hash3To1(P + Vector3(59.41, 73.19, 89.53)));
end;

function ProceduralNoise3D(const P: TVector3): Single;
var
  Cell, F: TVector3;
  C000, C100, C010, C110, C001, C101, C011, C111: Single;
  NX00, NX10, NX01, NX11, NY0, NY1: Single;
begin
  Cell := Vector3(Floor(P.X), Floor(P.Y), Floor(P.Z));
  F := Vector3(
    SmoothStepFloat(0.0, 1.0, P.X - Cell.X),
    SmoothStepFloat(0.0, 1.0, P.Y - Cell.Y),
    SmoothStepFloat(0.0, 1.0, P.Z - Cell.Z));
  C000 := Hash3To1(Cell);
  C100 := Hash3To1(Cell + Vector3(1, 0, 0));
  C010 := Hash3To1(Cell + Vector3(0, 1, 0));
  C110 := Hash3To1(Cell + Vector3(1, 1, 0));
  C001 := Hash3To1(Cell + Vector3(0, 0, 1));
  C101 := Hash3To1(Cell + Vector3(1, 0, 1));
  C011 := Hash3To1(Cell + Vector3(0, 1, 1));
  C111 := Hash3To1(Cell + Vector3(1, 1, 1));
  NX00 := Lerp(F.X, C000, C100);
  NX10 := Lerp(F.X, C010, C110);
  NX01 := Lerp(F.X, C001, C101);
  NX11 := Lerp(F.X, C011, C111);
  NY0 := Lerp(F.Y, NX00, NX10);
  NY1 := Lerp(F.Y, NX01, NX11);
  Result := Clamped(Lerp(F.Z, NY0, NY1), 0.0, 1.0);
end;

function ProceduralVoronoi3D(const P: TVector3; const Jitter: Single): Single;
var
  BaseCell, Neighbor, SeedOffset, Diff: TVector3;
  IX, IY, IZ: Integer;
  MinDistSq, DistSq, Jit: Single;
begin
  BaseCell := Vector3(Floor(P.X), Floor(P.Y), Floor(P.Z));
  Jit := Clamped(Jitter, 0.0, 1.0);
  MinDistSq := 100.0;
  for IZ := -1 to 1 do
    for IY := -1 to 1 do
      for IX := -1 to 1 do
      begin
        Neighbor := BaseCell + Vector3(IX, IY, IZ);
        SeedOffset := Vector3(0.5, 0.5, 0.5) +
          (Hash3To3(Neighbor) - Vector3(0.5, 0.5, 0.5)) * Jit;
        Diff := (Neighbor + SeedOffset) - P;
        DistSq := Diff.LengthSqr;
        if DistSq < MinDistSq then
          MinDistSq := DistSq;
      end;
  Result := Clamped(Sqrt(Max(0.0, MinDistSq)), 0.0, 1.0);
end;

function ProceduralChecker3D(const P: TVector3): Single;
var
  Parity: Int64;
begin
  Parity := Int64(Floor(P.X + 1e-4)) + Int64(Floor(P.Y + 1e-4)) + Int64(Floor(P.Z + 1e-4));
  if (Parity and 1) <> 0 then
    Result := 1.0
  else
    Result := 0.0;
end;

function SanitizeGlslIdent(const S: String): String;
var
  I: Integer;
  Ch: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Ch := S[I];
    if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Result := Result + Ch
    else
      Result := Result + '_';
  end;
  if Result = '' then
    Result := 'node';
  if CharInSet(Result[1], ['0'..'9']) then
    Result := 'n_' + Result;
end;

{ TCastleMaterialGraph ------------------------------------------------------- }

constructor TCastleMaterialGraph.Create(AOwner: TComponent);
begin
  inherited;
  FAlphaClipThreshold := DefaultAlphaClipThreshold;
  FRevision := 1;
  LoadPreset(mgpTriplanarMossyRock);
end;

function TCastleMaterialGraph.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'AlphaClipThreshold', 'GraphJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMaterialGraph.BumpRevision;
begin
  Inc(FRevision);
  if FRevision = 0 then
    FRevision := 1;
end;

class function TCastleMaterialGraph.NodeKindDisplayName(
  const AKind: TMaterialNodeKind): String;
begin
  case AKind of
    mnkTime: Result := 'Time (Seconds)';
    mnkObjectPos: Result := 'Object Position (XYZ)';
    mnkWorldNormal: Result := 'Surface Normal (XYZ)';
    mnkFresnel: Result := 'Fresnel Rim (N·V)';
    mnkConstantFloat: Result := 'Constant Float';
    mnkConstantColor: Result := 'Constant RGB Color';
    mnkNoise3D: Result := '3D Value Noise';
    mnkVoronoi3D: Result := '3D Voronoi Cellular';
    mnkChecker3D: Result := '3D Box Checker';
    mnkSineWave: Result := 'Sine Wave Oscillator';
    mnkAdd: Result := 'Add (A + B)';
    mnkMultiply: Result := 'Multiply (A * B)';
    mnkMixColor: Result := 'Mix / Lerp RGB';
    mnkRemapSmoothstep: Result := 'Smoothstep Remap';
    mnkVertexWaveOffset: Result := 'Vertex Wave Offset';
    mnkPbrOutput: Result := 'PBR Material Output';
  end;
end;

class function TCastleMaterialGraph.NodeOutputType(
  const AKind: TMaterialNodeKind): TMaterialValueType;
begin
  case AKind of
    mnkObjectPos,
    mnkWorldNormal,
    mnkConstantColor,
    mnkMixColor,
    mnkVertexWaveOffset,
    mnkPbrOutput:
      Result := mvtVec3;
    mnkAdd,
    mnkMultiply:
      Result := mvtVec3;
  else
    Result := mvtFloat;
  end;
end;

class function TCastleMaterialGraph.NodeInputCount(
  const AKind: TMaterialNodeKind): Integer;
begin
  case AKind of
    mnkTime,
    mnkObjectPos,
    mnkWorldNormal,
    mnkFresnel,
    mnkConstantFloat,
    mnkConstantColor:
      Result := 0;
    mnkNoise3D,
    mnkVoronoi3D,
    mnkChecker3D,
    mnkSineWave,
    mnkRemapSmoothstep,
    mnkVertexWaveOffset:
      Result := 1;
    mnkAdd,
    mnkMultiply:
      Result := 2;
    mnkMixColor:
      Result := 3;
    mnkPbrOutput:
      Result := 6;
  end;
end;

class function TCastleMaterialGraph.NodeInputPinName(
  const AKind: TMaterialNodeKind; const PinIndex: Integer): String;
begin
  case AKind of
    mnkNoise3D, mnkVoronoi3D, mnkChecker3D:
      Result := 'Coord';
    mnkSineWave:
      Result := 'Phase';
    mnkRemapSmoothstep:
      Result := 'Value';
    mnkVertexWaveOffset:
      Result := 'Mask';
    mnkAdd, mnkMultiply:
      if PinIndex = 0 then Result := 'A' else Result := 'B';
    mnkMixColor:
      case PinIndex of
        0: Result := 'ColorA';
        1: Result := 'ColorB';
      else
        Result := 'Alpha';
      end;
    mnkPbrOutput:
      case PinIndex of
        0: Result := 'BaseColor';
        1: Result := 'Metallic';
        2: Result := 'Roughness';
        3: Result := 'Emissive';
        4: Result := 'Opacity';
      else
        Result := 'PositionOffset';
      end;
  else
    Result := 'In' + IntToStr(PinIndex);
  end;
end;

class function TCastleMaterialGraph.PresetDisplayName(
  const APreset: TMaterialGraphPreset): String;
begin
  case APreset of
    mgpCustom: Result := 'Custom Graph';
    mgpTriplanarMossyRock: Result := 'Triplanar Mossy Rock';
    mgpHologramScanline: Result := 'Sci-Fi Hologram Scanline';
    mgpMoltenLavaCracks: Result := 'Molten Lava Cracks';
    mgpBrushedGoldMetal: Result := 'Brushed Gold Metal';
    mgpAnimatedWindWaveFoliage: Result := 'Animated Wind-Wave Foliage';
  end;
end;

class function TCastleMaterialGraph.MakeDefaultNode(
  const ANodeId: String; const AKind: TMaterialNodeKind;
  const AX, AY: Single): TMaterialGraphNode;
var
  I: Integer;
begin
  Result := Default(TMaterialGraphNode);
  Result.NodeId := Trim(ANodeId);
  if Result.NodeId = '' then
    Result.NodeId := 'Node1';
  Result.Kind := AKind;
  Result.PosX := AX;
  Result.PosY := AY;
  Result.ParamA := 1.0;
  Result.ParamB := 0.0;
  Result.ParamC := 0.5;
  Result.ColorVal := Vector3(0.75, 0.75, 0.78);
  Result.SecondaryColor := Vector3(0.0, 0.0, 0.0);
  for I := 0 to High(Result.Inputs) do
    Result.Inputs[I] := '';

  case AKind of
    mnkFresnel:
      Result.ParamA := 3.0;
    mnkConstantFloat:
      Result.ParamA := 0.5;
    mnkNoise3D:
      begin
        Result.ParamA := 3.5;
        Result.ParamB := 0.0;
      end;
    mnkVoronoi3D:
      begin
        Result.ParamA := 4.0;
        Result.ParamB := 0.85;
      end;
    mnkChecker3D:
      Result.ParamA := 4.0;
    mnkSineWave:
      begin
        Result.ParamA := 12.0;
        Result.ParamB := 2.5;
      end;
    mnkMixColor:
      begin
        Result.ColorVal := Vector3(0.25, 0.26, 0.28);
        Result.SecondaryColor := Vector3(0.18, 0.52, 0.16);
        Result.ParamA := 0.5;
      end;
    mnkRemapSmoothstep:
      begin
        Result.ParamA := 0.30;
        Result.ParamB := 0.70;
      end;
    mnkVertexWaveOffset:
      begin
        Result.ParamA := 3.0;
        Result.ParamB := 2.4;
        Result.ParamC := 0.12;
      end;
    mnkPbrOutput:
      begin
        Result.ParamA := 1.0;  // BaseColor blend [0..1]
        Result.ParamB := 0.12; // Default Metallic
        Result.ParamC := 0.55; // Default Roughness
        Result.ColorVal := Vector3(0.72, 0.74, 0.78);
        Result.SecondaryColor := Vector3(0.0, 0.0, 0.0);
      end;
  else ;
  end;
end;

procedure TCastleMaterialGraph.SetNodes(const ANodes: TMaterialGraphNodeArray);
var
  I: Integer;
begin
  SetLength(FNodes, Length(ANodes));
  for I := 0 to High(ANodes) do
    FNodes[I] := ANodes[I];
  BumpRevision;
end;

function TCastleMaterialGraph.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TCastleMaterialGraph.FindNodeIndex(const ANodeId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].NodeId, ANodeId) then
      Exit(I);
  Result := -1;
end;

function TCastleMaterialGraph.FindOutputNodeIndex: Integer;
var
  I: Integer;
begin
  for I := High(FNodes) downto 0 do
    if FNodes[I].Kind = mnkPbrOutput then
      Exit(I);
  Result := -1;
end;

function TCastleMaterialGraph.HasVertexOffsetConnection: Boolean;
var
  OutIdx: Integer;
begin
  OutIdx := FindOutputNodeIndex;
  Result := (OutIdx >= 0) and (Trim(FNodes[OutIdx].Inputs[5]) <> '') and
    (FindNodeIndex(Trim(FNodes[OutIdx].Inputs[5])) >= 0);
end;

procedure TCastleMaterialGraph.ClearNodes;
begin
  SetLength(FNodes, 0);
  BumpRevision;
end;

function TCastleMaterialGraph.AddOrUpdateNode(const ANode: TMaterialGraphNode): Integer;
begin
  Result := FindNodeIndex(ANode.NodeId);
  if Result < 0 then
  begin
    Result := Length(FNodes);
    SetLength(FNodes, Result + 1);
  end;
  FNodes[Result] := ANode;
  BumpRevision;
end;

function TCastleMaterialGraph.RemoveNode(const ANodeId: String): Boolean;
var
  Idx, I, P: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then
    Exit(false);
  for I := Idx to High(FNodes) - 1 do
    FNodes[I] := FNodes[I + 1];
  SetLength(FNodes, Length(FNodes) - 1);
  for I := 0 to High(FNodes) do
    for P := 0 to High(FNodes[I].Inputs) do
      if SameText(FNodes[I].Inputs[P], ANodeId) then
        FNodes[I].Inputs[P] := '';
  BumpRevision;
  Result := true;
end;

function TCastleMaterialGraph.ConnectPin(const TargetNodeId: String;
  const TargetPinIndex: Integer; const SourceNodeId: String): Boolean;
var
  TIdx: Integer;
begin
  TIdx := FindNodeIndex(TargetNodeId);
  if (TIdx < 0) or (TargetPinIndex < 0) or (TargetPinIndex > High(FNodes[TIdx].Inputs)) then
    Exit(false);
  if (SourceNodeId <> '') and (FindNodeIndex(SourceNodeId) < 0) then
    Exit(false);
  FNodes[TIdx].Inputs[TargetPinIndex] := Trim(SourceNodeId);
  FPreset := mgpCustom;
  BumpRevision;
  Result := true;
end;

procedure TCastleMaterialGraph.SetPreset(const Value: TMaterialGraphPreset);
begin
  if FPreset <> Value then
  begin
    if Value = mgpCustom then
      FPreset := mgpCustom
    else
      LoadPreset(Value);
  end;
end;

procedure TCastleMaterialGraph.SetAlphaClipThreshold(const Value: Single);
var
  ClampedVal: Single;
begin
  ClampedVal := Clamped(Value, 0.0, 0.99);
  if not SameValue(FAlphaClipThreshold, ClampedVal) then
  begin
    FAlphaClipThreshold := ClampedVal;
    BumpRevision;
  end;
end;

procedure TCastleMaterialGraph.LoadPreset(const APreset: TMaterialGraphPreset);
var
  N: TMaterialGraphNode;
begin
  FPreset := APreset;
  SetLength(FNodes, 0);

  case APreset of
    mgpCustom,
    mgpTriplanarMossyRock:
      begin
        if APreset = mgpCustom then
          FPreset := mgpCustom
        else
          FPreset := mgpTriplanarMossyRock;
        FAlphaClipThreshold := 0.0;

        N := MakeDefaultNode('ObjPos', mnkObjectPos, 40, 60);
        N.ParamA := 1.8;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('RockNoise', mnkNoise3D, 220, 60);
        N.ParamA := 2.4;
        N.Inputs[0] := 'ObjPos';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('MossMask', mnkRemapSmoothstep, 410, 60);
        N.ParamA := 0.42;
        N.ParamB := 0.68;
        N.Inputs[0] := 'RockNoise';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('RockMossMix', mnkMixColor, 410, 190);
        N.ColorVal := Vector3(0.28, 0.27, 0.25);      // Granite rock
        N.SecondaryColor := Vector3(0.16, 0.48, 0.14); // Alpine moss
        N.Inputs[2] := 'MossMask';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('RoughRemap', mnkRemapSmoothstep, 410, 310);
        N.ParamA := 0.10;
        N.ParamB := 0.95;
        N.Inputs[0] := 'RockNoise';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Output', mnkPbrOutput, 640, 160);
        N.ParamA := 1.0;
        N.ParamB := 0.05;
        N.ParamC := 0.78;
        N.Inputs[0] := 'RockMossMix';
        N.Inputs[2] := 'RoughRemap';
        AddOrUpdateNode(N);
      end;

    mgpHologramScanline:
      begin
        FAlphaClipThreshold := 0.28;

        N := MakeDefaultNode('RimFresnel', mnkFresnel, 60, 60);
        N.ParamA := 2.4;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('ScanLines', mnkSineWave, 60, 190);
        N.ParamA := 28.0;
        N.ParamB := 4.5;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('HoloAlpha', mnkRemapSmoothstep, 270, 190);
        N.ParamA := 0.15;
        N.ParamB := 0.85;
        N.Inputs[0] := 'ScanLines';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('HoloBase', mnkConstantColor, 270, 60);
        N.ColorVal := Vector3(0.06, 0.45, 0.72);
        AddOrUpdateNode(N);

        N := MakeDefaultNode('HoloGlow', mnkMixColor, 460, 90);
        N.ColorVal := Vector3(0.04, 0.28, 0.48);
        N.SecondaryColor := Vector3(0.22, 0.95, 1.00);
        N.Inputs[2] := 'RimFresnel';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Output', mnkPbrOutput, 660, 130);
        N.ParamA := 1.0;
        N.ParamB := 0.10;
        N.ParamC := 0.20;
        N.Inputs[0] := 'HoloBase';
        N.Inputs[3] := 'HoloGlow';
        N.Inputs[4] := 'HoloAlpha';
        AddOrUpdateNode(N);
      end;

    mgpMoltenLavaCracks:
      begin
        FAlphaClipThreshold := 0.0;

        N := MakeDefaultNode('LavaCells', mnkVoronoi3D, 60, 90);
        N.ParamA := 3.6;
        N.ParamB := 0.90;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('CrackMask', mnkRemapSmoothstep, 260, 90);
        N.ParamA := 0.26; // Inverted-like: small Voronoi dist = glowing core, large = crust
        N.ParamB := 0.04;
        N.Inputs[0] := 'LavaCells';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('CrustColor', mnkMixColor, 450, 70);
        N.ColorVal := Vector3(0.09, 0.08, 0.08);
        N.SecondaryColor := Vector3(0.95, 0.28, 0.03);
        N.Inputs[2] := 'CrackMask';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('MagmaGlow', mnkMixColor, 450, 220);
        N.ColorVal := Vector3(0.0, 0.0, 0.0);
        N.SecondaryColor := Vector3(1.65, 0.48, 0.04);
        N.Inputs[2] := 'CrackMask';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Output', mnkPbrOutput, 660, 140);
        N.ParamA := 1.0;
        N.ParamB := 0.08;
        N.ParamC := 0.82;
        N.Inputs[0] := 'CrustColor';
        N.Inputs[3] := 'MagmaGlow';
        AddOrUpdateNode(N);
      end;

    mgpBrushedGoldMetal:
      begin
        FAlphaClipThreshold := 0.0;

        N := MakeDefaultNode('GoldColor', mnkConstantColor, 120, 60);
        N.ColorVal := Vector3(0.96, 0.76, 0.30);
        AddOrUpdateNode(N);

        N := MakeDefaultNode('MetalConst', mnkConstantFloat, 120, 170);
        N.ParamA := 0.96;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('BrushGrain', mnkSineWave, 120, 270);
        N.ParamA := 55.0;
        N.ParamB := 0.0;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('MicroRough', mnkRemapSmoothstep, 350, 270);
        N.ParamA := -0.4;
        N.ParamB := 2.6;
        N.Inputs[0] := 'BrushGrain';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Output', mnkPbrOutput, 600, 150);
        N.ParamA := 1.0;
        N.ParamB := 0.96;
        N.ParamC := 0.22;
        N.Inputs[0] := 'GoldColor';
        N.Inputs[1] := 'MetalConst';
        N.Inputs[2] := 'MicroRough';
        AddOrUpdateNode(N);
      end;

    mgpAnimatedWindWaveFoliage:
      begin
        FAlphaClipThreshold := 0.0;

        N := MakeDefaultNode('LeafNoise', mnkNoise3D, 70, 70);
        N.ParamA := 3.2;
        N.ParamB := 0.35;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('LeafColor', mnkMixColor, 300, 70);
        N.ColorVal := Vector3(0.10, 0.38, 0.12);
        N.SecondaryColor := Vector3(0.32, 0.68, 0.18);
        N.Inputs[2] := 'LeafNoise';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('WindOffset', mnkVertexWaveOffset, 300, 230);
        N.ParamA := 2.8;
        N.ParamB := 3.2;
        N.ParamC := 0.14;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Output', mnkPbrOutput, 580, 140);
        N.ParamA := 1.0;
        N.ParamB := 0.02;
        N.ParamC := 0.58;
        N.Inputs[0] := 'LeafColor';
        N.Inputs[5] := 'WindOffset';
        AddOrUpdateNode(N);
      end;
  end;
  BumpRevision;
end;

function TCastleMaterialGraph.GetGraphJson: String;
var
  RootObj, NodeObj: TJSONObject;
  NodesArr, InArr, ColArr, SecArr: TJSONArray;
  I, P: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', GetEnumName(TypeInfo(TMaterialGraphPreset), Ord(FPreset)));
    RootObj.Add('alphaClip', FAlphaClipThreshold);
    NodesArr := TJSONArray.Create;
    RootObj.Add('nodes', NodesArr);
    for I := 0 to High(FNodes) do
    begin
      NodeObj := TJSONObject.Create;
      NodeObj.Add('id', FNodes[I].NodeId);
      NodeObj.Add('kind', GetEnumName(TypeInfo(TMaterialNodeKind), Ord(FNodes[I].Kind)));
      NodeObj.Add('x', FNodes[I].PosX);
      NodeObj.Add('y', FNodes[I].PosY);
      NodeObj.Add('a', FNodes[I].ParamA);
      NodeObj.Add('b', FNodes[I].ParamB);
      NodeObj.Add('c', FNodes[I].ParamC);

      ColArr := TJSONArray.Create;
      ColArr.Add(FNodes[I].ColorVal.X);
      ColArr.Add(FNodes[I].ColorVal.Y);
      ColArr.Add(FNodes[I].ColorVal.Z);
      NodeObj.Add('col', ColArr);

      SecArr := TJSONArray.Create;
      SecArr.Add(FNodes[I].SecondaryColor.X);
      SecArr.Add(FNodes[I].SecondaryColor.Y);
      SecArr.Add(FNodes[I].SecondaryColor.Z);
      NodeObj.Add('sec', SecArr);

      InArr := TJSONArray.Create;
      for P := 0 to High(FNodes[I].Inputs) do
        InArr.Add(FNodes[I].Inputs[P]);
      NodeObj.Add('in', InArr);

      NodesArr.Add(NodeObj);
    end;
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleMaterialGraph.SetGraphJson(const Value: String);
var
  Data: TJSONData;
  RootObj, NodeObj: TJSONObject;
  NodesArr, InArr, ColArr, SecArr: TJSONArray;
  ParsedNodes: TMaterialGraphNodeArray;
  I, P, EnumVal: Integer;
  N: TMaterialGraphNode;
  KindStr, PresetStr: String;
begin
  if Trim(Value) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);

    PresetStr := RootObj.Get('preset', '');
    if PresetStr <> '' then
    begin
      EnumVal := GetEnumValue(TypeInfo(TMaterialGraphPreset), PresetStr);
      if EnumVal >= 0 then
        FPreset := TMaterialGraphPreset(EnumVal);
    end;
    FAlphaClipThreshold := Clamped(RootObj.Get('alphaClip', FAlphaClipThreshold), 0.0, 0.99);

    NodesArr := RootObj.Find('nodes', jtArray) as TJSONArray;
    if NodesArr <> nil then
    begin
      SetLength(ParsedNodes, NodesArr.Count);
      for I := 0 to NodesArr.Count - 1 do
      begin
        if not (NodesArr.Items[I] is TJSONObject) then
          Continue;
        NodeObj := TJSONObject(NodesArr.Items[I]);
        KindStr := NodeObj.Get('kind', 'mnkConstantFloat');
        EnumVal := GetEnumValue(TypeInfo(TMaterialNodeKind), KindStr);
        if EnumVal < 0 then
          EnumVal := Ord(mnkConstantFloat);
        N := MakeDefaultNode(NodeObj.Get('id', 'Node' + IntToStr(I)),
          TMaterialNodeKind(EnumVal),
          NodeObj.Get('x', 100.0),
          NodeObj.Get('y', 100.0));
        N.ParamA := NodeObj.Get('a', N.ParamA);
        N.ParamB := NodeObj.Get('b', N.ParamB);
        N.ParamC := NodeObj.Get('c', N.ParamC);

        ColArr := NodeObj.Find('col', jtArray) as TJSONArray;
        if (ColArr <> nil) and (ColArr.Count >= 3) then
          N.ColorVal := Vector3(ColArr.Floats[0], ColArr.Floats[1], ColArr.Floats[2]);

        SecArr := NodeObj.Find('sec', jtArray) as TJSONArray;
        if (SecArr <> nil) and (SecArr.Count >= 3) then
          N.SecondaryColor := Vector3(SecArr.Floats[0], SecArr.Floats[1], SecArr.Floats[2]);

        InArr := NodeObj.Find('in', jtArray) as TJSONArray;
        if InArr <> nil then
          for P := 0 to Min(High(N.Inputs), InArr.Count - 1) do
            N.Inputs[P] := InArr.Strings[P];

        ParsedNodes[I] := N;
      end;
      FNodes := ParsedNodes;
    end;
    BumpRevision;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleMaterialGraph.ValidateGraph(const Errors: TStrings): Boolean;
var
  State: array of Integer; // 0 = unvisited, 1 = visiting, 2 = visited
  I, J, P, SrcIdx, OutputCount: Integer;

  procedure VisitDfs(const NodeIdx: Integer);
  var
    Pin, DepIdx: Integer;
    SrcId: String;
  begin
    State[NodeIdx] := 1;
    for Pin := 0 to NodeInputCount(FNodes[NodeIdx].Kind) - 1 do
    begin
      SrcId := Trim(FNodes[NodeIdx].Inputs[Pin]);
      if SrcId = '' then
        Continue;
      DepIdx := FindNodeIndex(SrcId);
      if DepIdx < 0 then
        Continue;
      if State[DepIdx] = 1 then
      begin
        if Errors <> nil then
          Errors.Add(Format('Cycle detected in MaterialGraph "%s" involving node "%s" -> "%s".',
            [Name, FNodes[NodeIdx].NodeId, FNodes[DepIdx].NodeId]));
      end else
      if State[DepIdx] = 0 then
        VisitDfs(DepIdx);
    end;
    State[NodeIdx] := 2;
  end;

var
  InitialErrorCount: Integer;
begin
  if Errors <> nil then
    InitialErrorCount := Errors.Count
  else
    InitialErrorCount := 0;

  OutputCount := 0;
  for I := 0 to High(FNodes) do
  begin
    if Trim(FNodes[I].NodeId) = '' then
    begin
      if Errors <> nil then
        Errors.Add(Format('Node #%d in MaterialGraph "%s" has an empty NodeId.', [I, Name]));
    end;
    if FNodes[I].Kind = mnkPbrOutput then
      Inc(OutputCount);
    for J := I + 1 to High(FNodes) do
      if SameText(FNodes[I].NodeId, FNodes[J].NodeId) then
        if Errors <> nil then
          Errors.Add(Format('Duplicate NodeId "%s" in MaterialGraph "%s".',
            [FNodes[I].NodeId, Name]));

    for P := 0 to NodeInputCount(FNodes[I].Kind) - 1 do
      if (Trim(FNodes[I].Inputs[P]) <> '') and
         (FindNodeIndex(Trim(FNodes[I].Inputs[P])) < 0) then
        if Errors <> nil then
          Errors.Add(Format('Node "%s" pin "%s" references missing node "%s".',
            [FNodes[I].NodeId, NodeInputPinName(FNodes[I].Kind, P), FNodes[I].Inputs[P]]));
  end;

  if OutputCount = 0 then
    if Errors <> nil then
      Errors.Add(Format('MaterialGraph "%s" has no mnkPbrOutput sink node.', [Name]));

  SetLength(State, Length(FNodes));
  for I := 0 to High(State) do
    State[I] := 0;
  for I := 0 to High(FNodes) do
    if State[I] = 0 then
      VisitDfs(I);

  if Errors <> nil then
    Result := Errors.Count = InitialErrorCount
  else
  begin
    { Re-run with temporary list when caller passed nil }
    Result := OutputCount > 0;
    if Result then
    begin
      for I := 0 to High(FNodes) do
      begin
        if Trim(FNodes[I].NodeId) = '' then
          Exit(false);
        for P := 0 to NodeInputCount(FNodes[I].Kind) - 1 do
        begin
          if Trim(FNodes[I].Inputs[P]) <> '' then
          begin
            SrcIdx := FindNodeIndex(Trim(FNodes[I].Inputs[P]));
            if SrcIdx < 0 then
              Exit(false);
          end;
        end;
      end;
    end;
  end;
end;

function TCastleMaterialGraph.BuildTopologicalOrder(
  const RootNodeIndices: array of Integer;
  out OrderedIndices: array of Integer; out OrderedCount: Integer): Boolean;
var
  State: array of Integer;
  CycleFound: Boolean;
  I: Integer;

  procedure DfsPostOrder(const Idx: Integer);
  var
    Pin, DepIdx: Integer;
    SrcId: String;
  begin
    if (Idx < 0) or (Idx >= Length(FNodes)) or CycleFound then
      Exit;
    if State[Idx] = 2 then
      Exit;
    if State[Idx] = 1 then
    begin
      CycleFound := true;
      Exit;
    end;
    State[Idx] := 1;
    for Pin := 0 to NodeInputCount(FNodes[Idx].Kind) - 1 do
    begin
      SrcId := Trim(FNodes[Idx].Inputs[Pin]);
      if SrcId <> '' then
      begin
        DepIdx := FindNodeIndex(SrcId);
        if DepIdx >= 0 then
          DfsPostOrder(DepIdx);
      end;
    end;
    State[Idx] := 2;
    if OrderedCount <= High(OrderedIndices) then
    begin
      OrderedIndices[OrderedCount] := Idx;
      Inc(OrderedCount);
    end;
  end;

begin
  OrderedCount := 0;
  CycleFound := false;
  SetLength(State, Length(FNodes));
  for I := 0 to High(State) do
    State[I] := 0;
  for I := 0 to High(RootNodeIndices) do
    if (RootNodeIndices[I] >= 0) and (RootNodeIndices[I] < Length(FNodes)) then
      DfsPostOrder(RootNodeIndices[I]);
  Result := not CycleFound;
end;

function GlslVarNameForNode(const Node: TMaterialGraphNode; const Index: Integer): String;
begin
  Result := Format('v_%d_%s', [Index, SanitizeGlslIdent(Node.NodeId)]);
end;

function EmitNodeGlslDeclaration(const Nodes: TMaterialGraphNodeArray;
  const NodeIdx: Integer; const InVertexStage, InLightingStage: Boolean): String;

  function InputAsFloat(const Pin: Integer; const FallbackLiteral: String): String;
  var
    SrcId, VarRef: String;
    DepIdx: Integer;
  begin
    SrcId := Trim(Nodes[NodeIdx].Inputs[Pin]);
    DepIdx := -1;
    if SrcId <> '' then
    begin
      for DepIdx := 0 to High(Nodes) do
        if SameText(Nodes[DepIdx].NodeId, SrcId) then
          Break;
      if (DepIdx >= 0) and (DepIdx <= High(Nodes)) and SameText(Nodes[DepIdx].NodeId, SrcId) then
      begin
        VarRef := GlslVarNameForNode(Nodes[DepIdx], DepIdx);
        if TCastleMaterialGraph.NodeOutputType(Nodes[DepIdx].Kind) = mvtVec3 then
          Exit('(' + VarRef + '.x)')
        else
          Exit(VarRef);
      end;
    end;
    Result := FallbackLiteral;
  end;

  function InputAsVec3(const Pin: Integer; const FallbackLiteral: String): String;
  var
    SrcId, VarRef: String;
    DepIdx: Integer;
  begin
    SrcId := Trim(Nodes[NodeIdx].Inputs[Pin]);
    if SrcId <> '' then
    begin
      for DepIdx := 0 to High(Nodes) do
        if SameText(Nodes[DepIdx].NodeId, SrcId) then
          Break;
      if (DepIdx >= 0) and (DepIdx <= High(Nodes)) and SameText(Nodes[DepIdx].NodeId, SrcId) then
      begin
        VarRef := GlslVarNameForNode(Nodes[DepIdx], DepIdx);
        if TCastleMaterialGraph.NodeOutputType(Nodes[DepIdx].Kind) = mvtFloat then
          Exit('vec3(' + VarRef + ')')
        else
          Exit(VarRef);
      end;
    end;
    Result := FallbackLiteral;
  end;

var
  N: TMaterialGraphNode;
  VName, PosExpr, NormExpr: String;
begin
  N := Nodes[NodeIdx];
  VName := GlslVarNameForNode(N, NodeIdx);
  if InVertexStage then
  begin
    PosExpr := 'vec3(vertex_object)';
    NormExpr := 'normalize(normal_object)';
  end else
  begin
    PosExpr := 'cge_mat_obj_pos';
    NormExpr := 'normalize(cge_mat_obj_normal)';
  end;

  case N.Kind of
    mnkTime:
      Result := FormatDot('  float %s = cge_mat_time * %.4f;', [VName, N.ParamA]);
    mnkObjectPos:
      Result := FormatDot('  vec3 %s = (%s) * %.4f;', [VName, PosExpr, N.ParamA]);
    mnkWorldNormal:
      Result := Format('  vec3 %s = %s;', [VName, NormExpr]);
    mnkFresnel:
      if InVertexStage then
        Result := FormatDot('  float %s = pow(0.5, %.4f);', [VName, Max(0.05, N.ParamA)])
      else if InLightingStage then
        Result := FormatDot(
          '  float %s = pow(1.0 - clamp(abs(dot(normalize(normal_eye_fragment), normalize(-vertex_eye.xyz))), 0.0, 1.0), %.4f);',
          [VName, Max(0.05, N.ParamA)])
      else
        Result := FormatDot(
          '  float %s = pow(1.0 - clamp(abs(normalize(cge_mat_obj_normal).z), 0.0, 1.0), %.4f);',
          [VName, Max(0.05, N.ParamA)]);
    mnkConstantFloat:
      Result := FormatDot('  float %s = %.4f;', [VName, N.ParamA]);
    mnkConstantColor:
      Result := FormatDot('  vec3 %s = vec3(%.4f, %.4f, %.4f);',
        [VName, N.ColorVal.X, N.ColorVal.Y, N.ColorVal.Z]);
    mnkNoise3D:
      Result := FormatDot(
        '  float %s = cge_mg_noise3((%s) * %.4f + vec3(0.0, cge_mat_time * %.4f, 0.0));',
        [VName, InputAsVec3(0, PosExpr), N.ParamA, N.ParamB]);
    mnkVoronoi3D:
      Result := FormatDot(
        '  float %s = cge_mg_voronoi3((%s) * %.4f, %.4f);',
        [VName, InputAsVec3(0, PosExpr), N.ParamA, Clamped(N.ParamB, 0.0, 1.0)]);
    mnkChecker3D:
      Result := FormatDot(
        '  float %s = cge_mg_checker3((%s) * %.4f);',
        [VName, InputAsVec3(0, PosExpr), N.ParamA]);
    mnkSineWave:
      Result := FormatDot(
        '  float %s = 0.5 + 0.5 * sin((%s) * %.4f + cge_mat_time * %.4f);',
        [VName, InputAsFloat(0, '(' + PosExpr + ').y'), N.ParamA, N.ParamB]);
    mnkAdd:
      Result := Format(
        '  vec3 %s = (%s) + (%s);',
        [VName,
         InputAsVec3(0, FormatDot('vec3(%.4f)', [N.ParamA])),
         InputAsVec3(1, FormatDot('vec3(%.4f)', [N.ParamB]))]);
    mnkMultiply:
      Result := Format(
        '  vec3 %s = (%s) * (%s);',
        [VName,
         InputAsVec3(0, FormatDot('vec3(%.4f)', [N.ParamA])),
         InputAsVec3(1, FormatDot('vec3(%.4f)', [N.ParamB]))]);
    mnkMixColor:
      Result := Format(
        '  vec3 %s = mix(%s, %s, clamp(%s, 0.0, 1.0));',
        [VName,
         InputAsVec3(0, FormatDot('vec3(%.4f, %.4f, %.4f)', [N.ColorVal.X, N.ColorVal.Y, N.ColorVal.Z])),
         InputAsVec3(1, FormatDot('vec3(%.4f, %.4f, %.4f)', [N.SecondaryColor.X, N.SecondaryColor.Y, N.SecondaryColor.Z])),
         InputAsFloat(2, FormatDot('%.4f', [N.ParamA]))]);
    mnkRemapSmoothstep:
      begin
        { Note: GLSL smoothstep requires edge0 < edge1; support inverted remaps safely! }
        if N.ParamA <= N.ParamB then
          Result := FormatDot('  float %s = smoothstep(%.4f, %.4f, %s);',
            [VName, N.ParamA, Max(N.ParamA + 0.0001, N.ParamB), InputAsFloat(0, '0.5')])
        else
          Result := FormatDot('  float %s = 1.0 - smoothstep(%.4f, %.4f, %s);',
            [VName, N.ParamB, Max(N.ParamB + 0.0001, N.ParamA), InputAsFloat(0, '0.5')]);
      end;
    mnkVertexWaveOffset:
      Result := FormatDot(
        '  vec3 %s = vec3(0.0, sin((%s).x * %.4f + cge_mat_time * %.4f) * (%.4f * (%s)), 0.0);',
        [VName, PosExpr, N.ParamA, N.ParamB, N.ParamC, InputAsFloat(0, '1.0')]);
    mnkPbrOutput:
      Result := '';
  end;
end;

function GlslProceduralHelperLibrary: String;
begin
  Result :=
    'float cge_mg_hash3(const in vec3 p)' + NL +
    '{' + NL +
    '  vec3 q = fract(p * vec3(0.1031, 0.1030, 0.0973));' + NL +
    '  q += dot(q, q.yxz + 33.33);' + NL +
    '  return fract((q.x + q.y) * q.z);' + NL +
    '}' + NL +
    'vec3 cge_mg_hash33(const in vec3 p)' + NL +
    '{' + NL +
    '  return vec3(cge_mg_hash3(p),' + NL +
    '              cge_mg_hash3(p + vec3(17.13, 31.71, 47.29)),' + NL +
    '              cge_mg_hash3(p + vec3(59.41, 73.19, 89.53)));' + NL +
    '}' + NL +
    'float cge_mg_noise3(const in vec3 p)' + NL +
    '{' + NL +
    '  vec3 cell = floor(p);' + NL +
    '  vec3 f = smoothstep(0.0, 1.0, fract(p));' + NL +
    '  float n00 = mix(cge_mg_hash3(cell), cge_mg_hash3(cell + vec3(1.0, 0.0, 0.0)), f.x);' + NL +
    '  float n10 = mix(cge_mg_hash3(cell + vec3(0.0, 1.0, 0.0)), cge_mg_hash3(cell + vec3(1.0, 1.0, 0.0)), f.x);' + NL +
    '  float n01 = mix(cge_mg_hash3(cell + vec3(0.0, 0.0, 1.0)), cge_mg_hash3(cell + vec3(1.0, 0.0, 1.0)), f.x);' + NL +
    '  float n11 = mix(cge_mg_hash3(cell + vec3(0.0, 1.0, 1.0)), cge_mg_hash3(cell + vec3(1.0, 1.0, 1.0)), f.x);' + NL +
    '  return mix(mix(n00, n10, f.y), mix(n01, n11, f.y), f.z);' + NL +
    '}' + NL +
    'float cge_mg_voronoi3(const in vec3 p, const in float jitter)' + NL +
    '{' + NL +
    '  vec3 baseCell = floor(p);' + NL +
    '  float minDist = 8.0;' + NL +
    '  for (int z = -1; z <= 1; z++)' + NL +
    '    for (int y = -1; y <= 1; y++)' + NL +
    '      for (int x = -1; x <= 1; x++) {' + NL +
    '        vec3 nb = baseCell + vec3(float(x), float(y), float(z));' + NL +
    '        vec3 seed = vec3(0.5) + (cge_mg_hash33(nb) - vec3(0.5)) * jitter;' + NL +
    '        vec3 d = (nb + seed) - p;' + NL +
    '        minDist = min(minDist, dot(d, d));' + NL +
    '      }' + NL +
    '  return clamp(sqrt(max(minDist, 0.0)), 0.0, 1.0);' + NL +
    '}' + NL +
    'float cge_mg_checker3(const in vec3 p)' + NL +
    '{' + NL +
    '  vec3 fl = floor(p + vec3(0.0001));' + NL +
    '  return mod(fl.x + fl.y + fl.z, 2.0);' + NL +
    '}' + NL;
end;

function TCastleMaterialGraph.BuildVertexShaderSource: String;
var
  SB: TStringBuilder;
  OutIdx, PosRootIdx, OrderCount, I, Idx: Integer;
  Order: array of Integer;
  PosVarRef: String;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('/* Castle Material Graph Studio: Vertex Shader */');
    SB.AppendLine('uniform float cge_mat_time;');
    SB.AppendLine('varying highp vec3 cge_mat_obj_pos;');
    SB.AppendLine('varying vec3 cge_mat_obj_normal;');

    OutIdx := FindOutputNodeIndex;
    PosRootIdx := -1;
    if (OutIdx >= 0) and (Trim(FNodes[OutIdx].Inputs[5]) <> '') then
      PosRootIdx := FindNodeIndex(Trim(FNodes[OutIdx].Inputs[5]));

    SetLength(Order, Length(FNodes));
    if (PosRootIdx >= 0) and BuildTopologicalOrder([PosRootIdx], Order, OrderCount) and
       (OrderCount > 0) then
    begin
      SB.Append(GlslProceduralHelperLibrary);
      SB.AppendLine('void PLUG_vertex_object_space_change(');
      SB.AppendLine('  inout vec4 vertex_object, inout vec3 normal_object)');
      SB.AppendLine('{');
      for I := 0 to OrderCount - 1 do
      begin
        Idx := Order[I];
        if FNodes[Idx].Kind <> mnkPbrOutput then
          SB.AppendLine(EmitNodeGlslDeclaration(FNodes, Idx, true, false));
      end;
      PosVarRef := GlslVarNameForNode(FNodes[PosRootIdx], PosRootIdx);
      if NodeOutputType(FNodes[PosRootIdx].Kind) = mvtFloat then
        SB.AppendLine(Format('  vertex_object.xyz += vec3(0.0, %s, 0.0);', [PosVarRef]))
      else
        SB.AppendLine(Format('  vertex_object.xyz += %s;', [PosVarRef]));
      SB.AppendLine('  cge_mat_obj_pos = vec3(vertex_object);');
      SB.AppendLine('  cge_mat_obj_normal = normal_object;');
      SB.AppendLine('}');
    end else
    begin
      SB.AppendLine('void PLUG_vertex_object_space(');
      SB.AppendLine('  const in vec4 vertex_object, const in vec3 normal_object)');
      SB.AppendLine('{');
      SB.AppendLine('  cge_mat_obj_pos = vec3(vertex_object);');
      SB.AppendLine('  cge_mat_obj_normal = normal_object;');
      SB.AppendLine('}');
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function TCastleMaterialGraph.BuildFragmentShaderSource: String;
var
  SB: TStringBuilder;
  OutIdx, BaseIdx, MetIdx, RoughIdx, EmissIdx, OpacIdx: Integer;
  Order: array of Integer;
  OrderCount, I, Idx: Integer;
  OutNode: TMaterialGraphNode;

  function PinScalarExpr(const RootIdx: Integer; const FallbackVal: Single): String;
  var
    VRef: String;
  begin
    if RootIdx >= 0 then
    begin
      VRef := GlslVarNameForNode(FNodes[RootIdx], RootIdx);
      if NodeOutputType(FNodes[RootIdx].Kind) = mvtVec3 then
        Result := '(' + VRef + '.x)'
      else
        Result := VRef;
    end else
      Result := FormatDot('%.4f', [FallbackVal]);
  end;

  function PinVec3Expr(const RootIdx: Integer; const FallbackCol: TVector3): String;
  var
    VRef: String;
  begin
    if RootIdx >= 0 then
    begin
      VRef := GlslVarNameForNode(FNodes[RootIdx], RootIdx);
      if NodeOutputType(FNodes[RootIdx].Kind) = mvtFloat then
        Result := 'vec3(' + VRef + ')'
      else
        Result := VRef;
    end else
      Result := FormatDot('vec3(%.4f, %.4f, %.4f)',
        [FallbackCol.X, FallbackCol.Y, FallbackCol.Z]);
  end;

begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('/* Castle Material Graph Studio: Fragment Shader */');
    SB.AppendLine('uniform float cge_mat_time;');
    SB.AppendLine('varying highp vec3 cge_mat_obj_pos;');
    SB.AppendLine('varying vec3 cge_mat_obj_normal;');
    SB.Append(GlslProceduralHelperLibrary);

    OutIdx := FindOutputNodeIndex;
    if OutIdx < 0 then
    begin
      Result := SB.ToString;
      Exit;
    end;
    OutNode := FNodes[OutIdx];
    BaseIdx := FindNodeIndex(Trim(OutNode.Inputs[0]));
    MetIdx := FindNodeIndex(Trim(OutNode.Inputs[1]));
    RoughIdx := FindNodeIndex(Trim(OutNode.Inputs[2]));
    EmissIdx := FindNodeIndex(Trim(OutNode.Inputs[3]));
    OpacIdx := FindNodeIndex(Trim(OutNode.Inputs[4]));

    SetLength(Order, Length(FNodes));

    { 1. BaseColor stage (PLUG_main_texture_apply) }
    SB.AppendLine('void PLUG_main_texture_apply(inout vec4 fragment_color, const in vec3 normal)');
    SB.AppendLine('{');
    if (BaseIdx >= 0) and BuildTopologicalOrder([BaseIdx], Order, OrderCount) then
      for I := 0 to OrderCount - 1 do
      begin
        Idx := Order[I];
        if FNodes[Idx].Kind <> mnkPbrOutput then
          SB.AppendLine(EmitNodeGlslDeclaration(FNodes, Idx, false, false));
      end;
    SB.AppendLine(FormatDot(
      '  vec3 mg_base_color = clamp(%s, vec3(0.0), vec3(1.0));' + NL +
      '  fragment_color.rgb = mix(fragment_color.rgb, mg_base_color, clamp(%.4f, 0.0, 1.0));',
      [PinVec3Expr(BaseIdx, OutNode.ColorVal), OutNode.ParamA]));
    SB.AppendLine('}');

    { 2. Metallic & Roughness stage (PLUG_material_metallic_roughness) }
    SB.AppendLine('void PLUG_material_metallic_roughness(inout float metallic_final, inout float roughness_final)');
    SB.AppendLine('{');
    if ((MetIdx >= 0) or (RoughIdx >= 0)) and
       BuildTopologicalOrder([MetIdx, RoughIdx], Order, OrderCount) then
      for I := 0 to OrderCount - 1 do
      begin
        Idx := Order[I];
        if FNodes[Idx].Kind <> mnkPbrOutput then
          SB.AppendLine(EmitNodeGlslDeclaration(FNodes, Idx, false, false));
      end;
    SB.AppendLine(Format('  metallic_final = clamp(%s, 0.0, 1.0);',
      [PinScalarExpr(MetIdx, OutNode.ParamB)]));
    SB.AppendLine(Format('  roughness_final = clamp(%s, 0.04, 1.0);',
      [PinScalarExpr(RoughIdx, OutNode.ParamC)]));
    SB.AppendLine('}');

    { 3. Emissive, Fresnel & Alpha-Clip stage (PLUG_lighting_apply) }
    SB.AppendLine('void PLUG_lighting_apply(inout vec4 fragment_color,');
    SB.AppendLine('  const in vec4 vertex_eye, const in vec3 normal_eye_fragment)');
    SB.AppendLine('{');
    if ((EmissIdx >= 0) or (OpacIdx >= 0)) and
       BuildTopologicalOrder([EmissIdx, OpacIdx], Order, OrderCount) then
      for I := 0 to OrderCount - 1 do
      begin
        Idx := Order[I];
        if FNodes[Idx].Kind <> mnkPbrOutput then
          SB.AppendLine(EmitNodeGlslDeclaration(FNodes, Idx, false, true));
      end;
    SB.AppendLine(Format('  float mg_opacity = clamp(%s, 0.0, 1.0);',
      [PinScalarExpr(OpacIdx, 1.0)]));
    if FAlphaClipThreshold > 0.0001 then
      SB.AppendLine(FormatDot('  if (mg_opacity < %.4f) discard;', [FAlphaClipThreshold]));
    SB.AppendLine('  fragment_color.a *= mg_opacity;');
    SB.AppendLine(Format('  fragment_color.rgb += max(%s, vec3(0.0));',
      [PinVec3Expr(EmissIdx, OutNode.SecondaryColor)]));
    SB.AppendLine('}');

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function TCastleMaterialGraph.EvaluatePreviewPixel(
  const U, V, TimeSec: Single; const CompositeBackground: Boolean): TCastleColor;
var
  SX, SY, R2, SZ, CheckerBg: Single;
  BgColor: TVector3;
  ObjPos, ObjNormal, ViewDir, KeyDir, HalfVec: TVector3;
  OutIdx, OrderCount, I, Idx: Integer;
  Order: array of Integer;
  EvalValues: array of TVector3;

  function ReadPinVec3(const Node: TMaterialGraphNode; const Pin: Integer;
    const Fallback: TVector3): TVector3;
  var
    SrcId: String;
    DepIdx: Integer;
  begin
    SrcId := Trim(Node.Inputs[Pin]);
    if SrcId <> '' then
    begin
      DepIdx := FindNodeIndex(SrcId);
      if (DepIdx >= 0) and (DepIdx < Length(EvalValues)) then
      begin
        if NodeOutputType(FNodes[DepIdx].Kind) = mvtFloat then
          Exit(Vector3(EvalValues[DepIdx].X, EvalValues[DepIdx].X, EvalValues[DepIdx].X))
        else
          Exit(EvalValues[DepIdx]);
      end;
    end;
    Result := Fallback;
  end;

  function ReadPinScalar(const Node: TMaterialGraphNode; const Pin: Integer;
    const Fallback: Single): Single;
  var
    SrcId: String;
    DepIdx: Integer;
  begin
    SrcId := Trim(Node.Inputs[Pin]);
    if SrcId <> '' then
    begin
      DepIdx := FindNodeIndex(SrcId);
      if (DepIdx >= 0) and (DepIdx < Length(EvalValues)) then
        Exit(EvalValues[DepIdx].X);
    end;
    Result := Fallback;
  end;

var
  N: TMaterialGraphNode;
  SVal, NdotL, NdotV, NdotH, Metallic, Roughness, Opacity, SpecPower, SpecStrength: Single;
  BaseCol, EmissiveCol, DiffuseTerm, SpecColor, LitRgb: TVector3;
begin
  { Studio checker background }
  if ((Trunc(Floor(Clamped(U, 0.0, 1.0) * 12.0)) +
       Trunc(Floor(Clamped(V, 0.0, 1.0) * 12.0))) and 1) <> 0 then
    CheckerBg := 0.16
  else
    CheckerBg := 0.11;
  BgColor := Vector3(CheckerBg, CheckerBg, CheckerBg + 0.015);

  SX := (U * 2.0 - 1.0) * 1.12;
  SY := (1.0 - V * 2.0) * 1.12;
  R2 := SX * SX + SY * SY;
  if R2 > 1.0 then
  begin
    if CompositeBackground then
      Exit(Vector4(BgColor.X, BgColor.Y, BgColor.Z, 1.0))
    else
      Exit(Vector4(0.0, 0.0, 0.0, 0.0));
  end;

  SZ := Sqrt(Max(0.0, 1.0 - R2));
  ObjNormal := Vector3(SX, SY, SZ).Normalize;
  ObjPos := ObjNormal;
  ViewDir := Vector3(0.0, 0.0, 1.0);
  NdotV := Clamped(TVector3.DotProduct(ObjNormal, ViewDir), 0.0, 1.0);

  OutIdx := FindOutputNodeIndex;
  if OutIdx < 0 then
    Exit(Vector4(0.6, 0.6, 0.6, 1.0));

  SetLength(Order, Length(FNodes));
  SetLength(EvalValues, Length(FNodes));
  for I := 0 to High(EvalValues) do
    EvalValues[I] := TVector3.Zero;

  if BuildTopologicalOrder([OutIdx], Order, OrderCount) then
  begin
    for I := 0 to OrderCount - 1 do
    begin
      Idx := Order[I];
      N := FNodes[Idx];
      case N.Kind of
        mnkTime:
          EvalValues[Idx] := Vector3(TimeSec * N.ParamA, 0, 0);
        mnkObjectPos:
          EvalValues[Idx] := ObjPos * N.ParamA;
        mnkWorldNormal:
          EvalValues[Idx] := ObjNormal;
        mnkFresnel:
          EvalValues[Idx] := Vector3(Power(1.0 - NdotV, Max(0.05, N.ParamA)), 0, 0);
        mnkConstantFloat:
          EvalValues[Idx] := Vector3(N.ParamA, 0, 0);
        mnkConstantColor:
          EvalValues[Idx] := N.ColorVal;
        mnkNoise3D:
          begin
            SVal := ProceduralNoise3D(ReadPinVec3(N, 0, ObjPos) * N.ParamA +
              Vector3(0.0, TimeSec * N.ParamB, 0.0));
            EvalValues[Idx] := Vector3(SVal, 0, 0);
          end;
        mnkVoronoi3D:
          begin
            SVal := ProceduralVoronoi3D(ReadPinVec3(N, 0, ObjPos) * N.ParamA, N.ParamB);
            EvalValues[Idx] := Vector3(SVal, 0, 0);
          end;
        mnkChecker3D:
          begin
            SVal := ProceduralChecker3D(ReadPinVec3(N, 0, ObjPos) * N.ParamA);
            EvalValues[Idx] := Vector3(SVal, 0, 0);
          end;
        mnkSineWave:
          begin
            SVal := 0.5 + 0.5 * Sin(ReadPinScalar(N, 0, ObjPos.Y) * N.ParamA + TimeSec * N.ParamB);
            EvalValues[Idx] := Vector3(SVal, 0, 0);
          end;
        mnkAdd:
          EvalValues[Idx] := ReadPinVec3(N, 0, Vector3(N.ParamA, N.ParamA, N.ParamA)) +
            ReadPinVec3(N, 1, Vector3(N.ParamB, N.ParamB, N.ParamB));
        mnkMultiply:
          EvalValues[Idx] := ReadPinVec3(N, 0, Vector3(N.ParamA, N.ParamA, N.ParamA)) *
            ReadPinVec3(N, 1, Vector3(N.ParamB, N.ParamB, N.ParamB));
        mnkMixColor:
          EvalValues[Idx] := Lerp(
            Clamped(ReadPinScalar(N, 2, N.ParamA), 0.0, 1.0),
            ReadPinVec3(N, 0, N.ColorVal),
            ReadPinVec3(N, 1, N.SecondaryColor));
        mnkRemapSmoothstep:
          EvalValues[Idx] := Vector3(
            SmoothStepFloat(N.ParamA, N.ParamB, ReadPinScalar(N, 0, 0.5)), 0, 0);
        mnkVertexWaveOffset:
          EvalValues[Idx] := Vector3(0.0,
            Sin(ObjPos.X * N.ParamA + TimeSec * N.ParamB) * N.ParamC * ReadPinScalar(N, 0, 1.0),
            0.0);
        mnkPbrOutput: ;
      end;
    end;
  end;

  N := FNodes[OutIdx];
  BaseCol := ReadPinVec3(N, 0, N.ColorVal);
  BaseCol := Vector3(
    Clamped(BaseCol.X, 0.0, 1.0),
    Clamped(BaseCol.Y, 0.0, 1.0),
    Clamped(BaseCol.Z, 0.0, 1.0));
  Metallic := Clamped(ReadPinScalar(N, 1, N.ParamB), 0.0, 1.0);
  Roughness := Clamped(ReadPinScalar(N, 2, N.ParamC), 0.04, 1.0);
  EmissiveCol := ReadPinVec3(N, 3, N.SecondaryColor);
  EmissiveCol := Vector3(Max(0.0, EmissiveCol.X), Max(0.0, EmissiveCol.Y), Max(0.0, EmissiveCol.Z));
  Opacity := Clamped(ReadPinScalar(N, 4, 1.0), 0.0, 1.0);

  if (FAlphaClipThreshold > 0.0001) and (Opacity < FAlphaClipThreshold) then
  begin
    if CompositeBackground then
      Exit(Vector4(BgColor.X, BgColor.Y, BgColor.Z, 0.0))
    else
      Exit(Vector4(0.0, 0.0, 0.0, 0.0));
  end;

  KeyDir := Vector3(0.48, 0.62, 0.62).Normalize;
  HalfVec := (KeyDir + ViewDir).Normalize;
  NdotL := Clamped(TVector3.DotProduct(ObjNormal, KeyDir), 0.0, 1.0);
  NdotH := Clamped(TVector3.DotProduct(ObjNormal, HalfVec), 0.0, 1.0);

  DiffuseTerm := BaseCol * ((1.0 - Metallic) * (0.18 + 0.88 * NdotL));
  SpecColor := Lerp(Metallic, Vector3(0.04, 0.04, 0.04), BaseCol);
  SpecPower := Max(2.0, 2.0 / Max(0.002, Sqr(Roughness * Roughness)) - 2.0);
  SpecStrength := Power(NdotH, Min(256.0, SpecPower)) * (0.25 + 0.75 * (1.0 - Roughness));

  LitRgb := DiffuseTerm + SpecColor * (SpecStrength * (0.35 + 0.65 * NdotL)) + EmissiveCol;
  { Reinhard-like soft shoulder so HDR emissive glow looks crisp }
  LitRgb := Vector3(
    LitRgb.X / (1.0 + Max(0.0, LitRgb.X - 0.85) * 0.55),
    LitRgb.Y / (1.0 + Max(0.0, LitRgb.Y - 0.85) * 0.55),
    LitRgb.Z / (1.0 + Max(0.0, LitRgb.Z - 0.85) * 0.55));
  LitRgb := Vector3(
    Clamped(LitRgb.X, 0.0, 1.0),
    Clamped(LitRgb.Y, 0.0, 1.0),
    Clamped(LitRgb.Z, 0.0, 1.0));

  if CompositeBackground and (Opacity < 0.999) then
  begin
    LitRgb := Lerp(Opacity, BgColor, LitRgb);
    Result := Vector4(LitRgb.X, LitRgb.Y, LitRgb.Z, Opacity);
  end else
    Result := Vector4(LitRgb.X, LitRgb.Y, LitRgb.Z, Opacity);
end;

function TCastleMaterialGraph.GraphSummaryBadge: String;
begin
  Result := Format('[MatGraph:%s %d nodes]',
    [PresetDisplayName(FPreset), Length(FNodes)]);
end;

{ TCastleMaterialGraphBehavior ----------------------------------------------- }

constructor TCastleMaterialGraphBehavior.Create(AOwner: TComponent);
begin
  inherited;
  FEnabled := true;
  FMaterialGraph := nil;
  FFallbackPreset := mgpTriplanarMossyRock;
  FTimeScale := 1.0;
  FElapsedTime := 0.0;
  FEffectNode := nil;
  FFdTime := nil;
  FAppliedRootNode := nil;
  FLastGraphRevision := 0;
  FDirty := true;
end;

destructor TCastleMaterialGraphBehavior.Destroy;
begin
  SetMaterialGraph(nil);
  ReleaseCurrentEffectNode;
  inherited;
end;

procedure TCastleMaterialGraphBehavior.ReleaseCurrentEffectNode;
begin
  FFdTime := nil;
  if FEffectNode <> nil then
    NodeRelease(FEffectNode);
end;

procedure TCastleMaterialGraphBehavior.Notification(
  AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FMaterialGraph) then
  begin
    FMaterialGraph := nil;
    FDirty := true;
  end;
end;

function TCastleMaterialGraphBehavior.CanAttachToParent(
  const NewParent: TCastleTransform; out ReasonWhyCannot: String): Boolean;
begin
  Result := inherited;
  if not Result then
    Exit;
  if NewParent.FindBehavior(TCastleMaterialGraphBehavior) <> nil then
  begin
    ReasonWhyCannot := 'Only one TCastleMaterialGraphBehavior can be attached to a given TCastleTransform';
    Result := false;
  end;
end;

function TCastleMaterialGraphBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Enabled', 'MaterialGraph', 'FallbackPreset', 'TimeScale'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMaterialGraphBehavior.SetEnabled(const Value: Boolean);
begin
  if FEnabled <> Value then
  begin
    FEnabled := Value;
    if FEffectNode <> nil then
      FEffectNode.Enabled := FEnabled
    else
      RebuildAndApplyEffect;
  end;
end;

procedure TCastleMaterialGraphBehavior.SetMaterialGraph(const Value: TCastleMaterialGraph);
begin
  if FMaterialGraph <> Value then
  begin
    if FMaterialGraph <> nil then
      FMaterialGraph.RemoveFreeNotification(Self);
    FMaterialGraph := Value;
    if FMaterialGraph <> nil then
      FMaterialGraph.FreeNotification(Self);
    FDirty := true;
    RebuildAndApplyEffect;
  end;
end;

procedure TCastleMaterialGraphBehavior.SetFallbackPreset(const Value: TMaterialGraphPreset);
begin
  if FFallbackPreset <> Value then
  begin
    FFallbackPreset := Value;
    FDirty := true;
    RebuildAndApplyEffect;
  end;
end;

procedure TCastleMaterialGraphBehavior.SetTimeScale(const Value: Single);
begin
  FTimeScale := Clamped(Value, -20.0, 20.0);
end;

function TCastleMaterialGraphBehavior.BuildEffectNode: TEffectNode;
var
  TempGraph: TCastleMaterialGraph;
  ActiveGraph: TCastleMaterialGraph;
  VertPart, FragPart: TEffectPartNode;
begin
  TempGraph := nil;
  try
    if FMaterialGraph <> nil then
      ActiveGraph := FMaterialGraph
    else
    begin
      TempGraph := TCastleMaterialGraph.Create(nil);
      TempGraph.LoadPreset(FFallbackPreset);
      ActiveGraph := TempGraph;
    end;

    Result := TEffectNode.Create(EffectNodeName);
    Result.Language := slGLSL;
    Result.Enabled := FEnabled;

    FFdTime := TSFFloat.Create(Result, true, 'cge_mat_time', FElapsedTime);
    Result.AddCustomField(FFdTime);

    VertPart := TEffectPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.Contents := ActiveGraph.BuildVertexShaderSource;

    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents := ActiveGraph.BuildFragmentShaderSource;

    Result.SetParts([VertPart, FragPart]);
    if FMaterialGraph <> nil then
      FLastGraphRevision := FMaterialGraph.Revision;
  finally
    FreeAndNil(TempGraph);
  end;
end;

procedure TCastleMaterialGraphBehavior.DetachCurrentEffectFromParent(
  const TargetParent: TCastleTransform);
var
  Scene: TCastleScene;
  OtherEffects: array of TEffectNode;
  I, KeepCount: Integer;
  ChildNode: TX3DNode;
begin
  if (TargetParent = nil) or (FEffectNode = nil) then
    Exit;

  if TargetParent is TCastleScene then
  begin
    Scene := TCastleScene(TargetParent);
    if Scene.RootNode <> nil then
    begin
      KeepCount := 0;
      SetLength(OtherEffects, Scene.RootNode.FdChildren.Count);
      for I := 0 to Scene.RootNode.FdChildren.Count - 1 do
      begin
        ChildNode := Scene.RootNode.FdChildren[I];
        if (ChildNode is TEffectNode) and (ChildNode <> FEffectNode) and
           (ChildNode.X3DName <> EffectNodeName) then
        begin
          OtherEffects[KeepCount] := TEffectNode(ChildNode);
          Inc(KeepCount);
        end;
      end;
      SetLength(OtherEffects, KeepCount);
      Scene.SetEffects(OtherEffects);
    end;
  end else
  if TargetParent is TCastleAbstractPrimitive then
    TCastleAbstractPrimitive(TargetParent).SetEffects([])
  else
  if TargetParent is TCastleImageTransform then
    TCastleImageTransform(TargetParent).SetEffects([]);

  FAppliedRootNode := nil;
end;

procedure TCastleMaterialGraphBehavior.AttachEffectToParent(
  const TargetParent: TCastleTransform);
var
  Scene: TCastleScene;
  CombinedEffects: array of TEffectNode;
  I, KeepCount: Integer;
  ChildNode: TX3DNode;
begin
  if (TargetParent = nil) or (FEffectNode = nil) then
    Exit;

  if TargetParent is TCastleScene then
  begin
    Scene := TCastleScene(TargetParent);
    if Scene.RootNode <> nil then
    begin
      Scene.RenderOptions.PhongShading := true;
      KeepCount := 0;
      SetLength(CombinedEffects, Scene.RootNode.FdChildren.Count + 1);
      for I := 0 to Scene.RootNode.FdChildren.Count - 1 do
      begin
        ChildNode := Scene.RootNode.FdChildren[I];
        if (ChildNode is TEffectNode) and (ChildNode <> FEffectNode) and
           (ChildNode.X3DName <> EffectNodeName) then
        begin
          CombinedEffects[KeepCount] := TEffectNode(ChildNode);
          Inc(KeepCount);
        end;
      end;
      CombinedEffects[KeepCount] := FEffectNode;
      SetLength(CombinedEffects, KeepCount + 1);
      Scene.SetEffects(CombinedEffects);
      FAppliedRootNode := Scene.RootNode;
      FDirty := false;
    end;
  end else
  if TargetParent is TCastleAbstractPrimitive then
  begin
    TCastleAbstractPrimitive(TargetParent).SetEffects([FEffectNode]);
    FDirty := false;
  end else
  if TargetParent is TCastleImageTransform then
  begin
    TCastleImageTransform(TargetParent).SetEffects([FEffectNode]);
    FDirty := false;
  end;
end;

procedure TCastleMaterialGraphBehavior.RebuildAndApplyEffect;
begin
  if Parent <> nil then
    DetachCurrentEffectFromParent(Parent);
  ReleaseCurrentEffectNode;

  if Parent = nil then
    Exit;

  FEffectNode := BuildEffectNode;
  FEffectNode.WaitForRelease;
  AttachEffectToParent(Parent);
end;

procedure TCastleMaterialGraphBehavior.ParentAfterAttach;
begin
  inherited;
  FDirty := true;
  RebuildAndApplyEffect;
end;

procedure TCastleMaterialGraphBehavior.ParentBeforeDetach;
begin
  if Parent <> nil then
    DetachCurrentEffectFromParent(Parent);
  ReleaseCurrentEffectNode;
  inherited;
end;

procedure TCastleMaterialGraphBehavior.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if FEnabled then
  begin
    if (FMaterialGraph <> nil) and (FMaterialGraph.Revision <> FLastGraphRevision) then
      RebuildAndApplyEffect;
    FElapsedTime := FElapsedTime + SecondsPassed * FTimeScale;
    if FFdTime <> nil then
      FFdTime.Send(FElapsedTime);
  end;
end;

procedure TCastleMaterialGraphBehavior.BeforeRender(
  const CameraView: TViewVectors;
  const ParentParentWorldTransformation: TTransformation);
begin
  inherited;
  if FDirty or
     ((FMaterialGraph <> nil) and (FMaterialGraph.Revision <> FLastGraphRevision)) or
     ((Parent is TCastleScene) and (TCastleScene(Parent).RootNode <> FAppliedRootNode)) then
    RebuildAndApplyEffect;
end;

function TCastleMaterialGraphBehavior.BehaviorSummaryBadge: String;
begin
  if FMaterialGraph <> nil then
    Result := Format('[Shader:%s]', [FMaterialGraph.Name])
  else
    Result := Format('[Shader:%s]', [TCastleMaterialGraph.PresetDisplayName(FFallbackPreset)]);
end;

initialization
  RegisterSerializableComponent(TCastleMaterialGraph, 'Material Shader Graph');
  RegisterSerializableComponent(TCastleMaterialGraphBehavior, 'Material Graph Shader');
end.
