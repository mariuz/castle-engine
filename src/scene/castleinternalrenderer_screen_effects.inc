{%MainUnit castleinternalrenderer.pas}
{
  Copyright 2002-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_interface}
//type
  { Rendering resource for TScreenEffectNode. }
  TScreenEffectResource = class(TRendererResource)
  strict private
    { Did we try to initialize ShaderProgram, i.e. was PrepareCore called.

      We guarantee "ShaderLoaded=false => ShaderProgram=nil".

      So when ShaderLoaded=true, it may be be that ShaderProgram<>nil
      (if shader compiled OK) or ShaderProgram=nil (if shader compilation
      failed). }
    ShaderLoaded: Boolean;
    FNode: TScreenEffectNode;
    FRHIVertexShader: TRHIShaderModule;
    FRHIFragmentShader: TRHIShaderModule;
    FRHIDescriptorLayout: TRHIDescriptorSetLayout;
    FRHIPipeline: TRHIPipeline;
    FRHIVertexGLSL: String;
    FRHIFragmentGLSL: String;
  protected
    procedure PrepareCore(const RenderOptions: TCastleRenderOptions); override;
    procedure UnprepareCore; override;
  public
    { GLSL shader for the ScreenEffect node.
      @nil if not prepared, or failed to be prepared (e.g. shader didn't compile). }
    ShaderProgram: TX3DGLSLProgram;

    constructor Create(const ANode: TX3DNode); override;

    { Associated node.
      This obscures parent Node property,
      which is OK -- in this class Node is always guaranteed to be
      TScreenEffectNode. }
    property Node: TScreenEffectNode read FNode;
    property RHIPipeline: TRHIPipeline read FRHIPipeline;
    property RHIVertexShader: TRHIShaderModule read FRHIVertexShader;
    property RHIFragmentShader: TRHIShaderModule read FRHIFragmentShader;
    property RHIDescriptorLayout: TRHIDescriptorSetLayout read FRHIDescriptorLayout;
    property RHIVertexGLSL: String read FRHIVertexGLSL;
    property RHIFragmentGLSL: String read FRHIFragmentGLSL;
  end;

  { Manage TScreenEffectResource connected to X3D nodes.

    Non-instantiable class (has only class methods).

    This should be the only code accessing
    TScreenEffectNode.InternalRendererResource field,
    everything else should go through this class. }
  TScreenEffectResources = class abstract
  public
    { Prepare renderer resources for given node. }
    class procedure Prepare(
      const RenderOptions: TCastleRenderOptions;
      const Node: TScreenEffectNode);

    { Renderer resource associated with given TScreenEffectNode.
      Returns @nil if no resource is associated yet (call Prepare to initialize it). }
    class function Get(const Node: TScreenEffectNode): TScreenEffectResource;
  end;
{$endif read_interface}

{$ifdef read_implementation}

{ TScreenEffectResources ---------------------------------------------------- }

class procedure TScreenEffectResources.Prepare(const RenderOptions: TCastleRenderOptions;
  const Node: TScreenEffectNode);
var
  RendererResource: TScreenEffectResource;
begin
  { Unlike TTextureResources.Prepare, we don't allow nil argument.
    This is more consistent in CGE, see
    https://castle-engine.io/coding_conventions#nil }
  Assert(Node <> nil);
  if Node.InternalRendererResource = nil then
  begin
    RendererResource := TScreenEffectResource.Create(Node);
    RendererResource.Prepare(RenderOptions);
    Node.InternalRendererResource := RendererResource;
  end;
end;

class function TScreenEffectResources.Get(const Node: TScreenEffectNode):
  TScreenEffectResource;
begin
  Result := Node.InternalRendererResource as TScreenEffectResource;
end;

{ TScreenEffectResource ----------------------------------------------------- }

procedure TScreenEffectResource.PrepareCore(const RenderOptions: TCastleRenderOptions);
const
  FallbackScreenVS: array[0..9] of UInt32 = (
    $07230203, $00010500, $00000000, $00000008, $00000000,
    ($00050000 or 15), 0, 1, $6E69616D, $00000000
  );
  FallbackScreenFS: array[0..9] of UInt32 = (
    $07230203, $00010500, $00000000, $00000008, $00000000,
    ($00050000 or 15), 4, 1, $6E69616D, $00000000
  );

  procedure PrepareIDecls(const IDecls: TX3DInterfaceDeclarationList);

    { If TextureNode <> @nil and is a texture node, prepare it. }
    procedure PrepareTexture(TextureNode: TX3DNode);
    begin
      if (TextureNode <> nil) and
         (TextureNode is TAbstractTextureNode) then
        TTextureResources.Prepare(RenderOptions, TAbstractTextureNode(TextureNode));
    end;

  var
    I, J: Integer;
    UniformField: TX3DField;
  begin
    if IDecls = nil then Exit; { ignore nodes without interface declararations }

    for I := 0 to IDecls.Count - 1 do
    begin
      UniformField := IDecls.Items[I].Field;

      if UniformField <> nil then
      begin
        if UniformField is TSFNode then
        begin
          PrepareTexture(TSFNode(UniformField).Value);
        end else
        if UniformField is TMFNode then
        begin
          for J := 0 to TMFNode(UniformField).Count - 1 do
            PrepareTexture(TMFNode(UniformField)[J]);
        end;
      end;
    end;
  end;

  { Prepare all textures within X3D "interface declarations" of the given Nodes. }
  procedure PrepareIDeclsList(Nodes: TMFNode);
  var
    I: Integer;
  begin
    for I := 0 to Nodes.Count - 1 do
      PrepareIDecls(Nodes[I].InterfaceDeclarations);
  end;

  procedure PrepareRHIScreenEffect;
  var
    I, J: Integer;
    CompShader: TComposedShaderNode;
    Part: TShaderPartNode;
    UserFragSource, ScreenLibFrag: String;
    ShaderGen: TCastleShaderGeneratorRHI;
    Bindings: array of TRHIDescriptorBindingDesc;
    PipeDesc: TRHIGraphicsPipelineDesc;
    NeedsDepth: Boolean;
  begin
    CompShader := nil;
    UserFragSource := '';
    for I := 0 to Node.FdShaders.Count - 1 do
      if (Node.FdShaders[I] is TComposedShaderNode) and
         (TComposedShaderNode(Node.FdShaders[I]).Language in [slDefault, slGLSL]) then
      begin
        CompShader := TComposedShaderNode(Node.FdShaders[I]);
        for J := 0 to CompShader.FdParts.Count - 1 do
          if (CompShader.FdParts[J] is TShaderPartNode) and
             (TShaderPartNode(CompShader.FdParts[J]).ShaderType = stFragment) then
          begin
            Part := TShaderPartNode(CompShader.FdParts[J]);
            if Part.Contents <> '' then
              UserFragSource := UserFragSource + Part.Contents + LineEnding;
          end;
        Break;
      end;

    if (CompShader = nil) or (Trim(UserFragSource) = '') then
      Exit;

    NeedsDepth := Node.FdNeedsDepth.Value;
    ShaderGen := TCastleShaderGeneratorRHI.Create(RHIDevice.Capabilities.Backend);
    try
      FRHIVertexGLSL :=
        ShaderGen.GenerateScreenEffectPreamble(ssVertex, NeedsDepth) + LineEnding +
        'void main(void)' + LineEnding +
        '{' + LineEnding +
        '  v_tex_coord = tex_coord;' + LineEnding +
        '  gl_Position = vec4(vertex, 0.0, 1.0);' + LineEnding +
        '}' + LineEnding;

      ScreenLibFrag :=
        'ivec2 screen_position() { return ivec2(tex_coord * castle_Screen.screen_size); }' + LineEnding +
        'int screen_x() { return int(tex_coord.x * castle_Screen.screen_size.x); }' + LineEnding +
        'int screen_y() { return int(tex_coord.y * castle_Screen.screen_size.y); }' + LineEnding +
        'vec4 screen_get_color(ivec2 position) { return texture(screen, vec2(position) / castle_Screen.screen_size); }' + LineEnding;
      if NeedsDepth then
        ScreenLibFrag := ScreenLibFrag +
          'float screen_get_depth_fast(ivec2 position) { return texture(screen_depth, vec2(position) / castle_Screen.screen_size).r; }' + LineEnding +
          'float screen_get_depth(ivec2 position) { return screen_get_depth_fast(position); }' + LineEnding;

      FRHIFragmentGLSL :=
        ShaderGen.GenerateScreenEffectPreamble(ssFragment, NeedsDepth) + LineEnding +
        ScreenLibFrag + LineEnding +
        ShaderGen.SanitizeVulkanShaderSource(UserFragSource);
    finally
      FreeAndNil(ShaderGen);
    end;

    FRHIVertexShader := RHIDevice.CreateShaderModuleFromSPIRV(ssVertex,
      @FallbackScreenVS[0], SizeOf(FallbackScreenVS), 'ScreenEffectVS');
    FRHIFragmentShader := RHIDevice.CreateShaderModuleFromSPIRV(ssFragment,
      @FallbackScreenFS[0], SizeOf(FallbackScreenFS), 'ScreenEffectFS');

    if NeedsDepth then
      SetLength(Bindings, 2)
    else
      SetLength(Bindings, 1);
    FillChar(Bindings[0], Length(Bindings) * SizeOf(TRHIDescriptorBindingDesc), 0);
    Bindings[0].Binding := 0;
    Bindings[0].DescriptorType := dtCombinedImageSampler;
    Bindings[0].Count := 1;
    Bindings[0].StageFlags := [ssFragment];
    if NeedsDepth then
    begin
      Bindings[1].Binding := 1;
      Bindings[1].DescriptorType := dtCombinedImageSampler;
      Bindings[1].Count := 1;
      Bindings[1].StageFlags := [ssFragment];
    end;
    FRHIDescriptorLayout := RHIDevice.CreateDescriptorSetLayout(Bindings);

    FillChar(PipeDesc, SizeOf(PipeDesc), 0);
    PipeDesc.VertexShader := FRHIVertexShader;
    PipeDesc.FragmentShader := FRHIFragmentShader;
    PipeDesc.Topology := ptTriangleList;
    PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    PipeDesc.Rasterizer.CullMode := cmNone;
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
    PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    SetLength(PipeDesc.VertexInput.Bindings, 1);
    PipeDesc.VertexInput.Bindings[0].Binding := 0;
    PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector2) * 2;
    PipeDesc.VertexInput.Bindings[0].PerInstance := False;
    SetLength(PipeDesc.VertexInput.Attributes, 2);
    PipeDesc.VertexInput.Attributes[0].Location := 0;
    PipeDesc.VertexInput.Attributes[0].Binding := 0;
    PipeDesc.VertexInput.Attributes[0].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[0].Offset := 0;
    PipeDesc.VertexInput.Attributes[1].Location := 1;
    PipeDesc.VertexInput.Attributes[1].Binding := 0;
    PipeDesc.VertexInput.Attributes[1].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[1].Offset := SizeOf(TVector2);
    SetLength(PipeDesc.ColorAttachmentFormats, 1);
    PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
    PipeDesc.SampleCount := 1;
    SetLength(PipeDesc.DescriptorSetLayouts, 1);
    PipeDesc.DescriptorSetLayouts[0] := FRHIDescriptorLayout;
    PipeDesc.PushConstantSize := 32; // SizeOf(TCastleScreenPushConstants)
    PipeDesc.PushConstantStages := [ssVertex, ssFragment];
    PipeDesc.DebugName := 'ScreenEffectPSO.' + Node.NiceName;
    FRHIPipeline := RHIDevice.GetOrCreatePipeline(PipeDesc);
  end;

var
  Shader: TShader;
  ShaderNode: TComposedShaderNode;
  DummyCamera: TRenderingCamera;
begin
  if not ShaderLoaded then
  begin
    Assert(ShaderProgram = nil);
    ShaderLoaded := true;

    if RHIDevice <> nil then
    begin
      if Node.FdEnabled.Value then
      begin
        PrepareIDeclsList(Node.FdShaders);
        PrepareRHIScreenEffect;
      end;
      Exit;
    end;

    { Note: Strictly speaking, we should not need to check
      "not GLFeatures.EnableFixedFunction" below.
      Without this check, TX3DGLSLProgram.Create below will raise an exception
      which will cause to abort.

      But:
      - This is a bit inefficient way to abort.
      - It causes unknown issues: castle-model-viewer --debug-fixed-function,
        enable any (like "visualize depth") screen effect,
        and you may experience crash in TCastleScene.ScreenEffectsCount
        as if ScreenEffectNodes was nil.

        Not debugged to the end:
        situation seems impossible and in debugger mysteriously
        doesn't occur. And logging inconclusive:

          WritelnLog('TCastleScene.ScreenEffectsCount %s', [BoolToStr(ScreenEffectNodes <> nil, true)]);

        sometimes shown we indeed have nil right before crash,
        but sometimes not...
    }

    if Node.FdEnabled.Value and (GLFeatures <> nil) and (not GLFeatures.EnableFixedFunction) then
    begin
      { make sure that textures inside shaders are prepared }
      PrepareIDeclsList(Node.FdShaders);

      Shader := TShader.Create;
      try
        DummyCamera := TRenderingCamera.Create;
        try
          Shader.RenderingCamera := DummyCamera;

          { for ScreenEffect, we require that some ComposedShader was present.
            Rendering with default TShader shader makes no sense. }
          if Shader.EnableCustomShaderCode(Node.FdShaders, ShaderNode) then
          try
            ShaderProgram := TX3DGLSLProgram.Create;
            Shader.AddScreenEffectCode(Node.FdNeedsDepth.Value);
            Shader.LinkProgram(ShaderProgram, Node.NiceName);

            { We have to ignore invalid uniforms, as it's normal that when
              rendering screen effect we will pass some screen_* variables
              that you will not use. }
            ShaderProgram.UniformMissing := umIgnore;
          except on E: EGLSLError do
            begin
              FreeAndNil(ShaderProgram);
              WritelnWarning('Renderer', Format('Cannot use GLSL shader for ScreenEffect: %s',
                [E.Message]));
            end;
          end;
        finally FreeAndNil(DummyCamera) end;
      finally FreeAndNil(Shader) end;
    end;
  end;
end;

procedure TScreenEffectResource.UnprepareCore;
begin
  FreeAndNil(ShaderProgram);
  FreeAndNil(FRHIDescriptorLayout);
  FreeAndNil(FRHIFragmentShader);
  FreeAndNil(FRHIVertexShader);
  FRHIPipeline := nil; // Owned by RHIDevice pipeline cache
  FRHIVertexGLSL := '';
  FRHIFragmentGLSL := '';
  ShaderLoaded := false;
end;

constructor TScreenEffectResource.Create(const ANode: TX3DNode);
begin
  inherited;
  if not (ANode is TScreenEffectNode) then
    raise EInternalError.Create('TScreenEffectResource.Create: ANode must be TScreenEffectNode');
  FNode := TScreenEffectNode(ANode);
end;

{$endif read_implementation}