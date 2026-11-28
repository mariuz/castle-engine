{%MainUnit testcastlevulkanrhi.pas}
{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}

{$ifdef read_implementation}

procedure TTestCastleVulkanRHI.TestDrawableImageBlendModesAndRotationBatch2DRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  VkCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Batcher: TCastleBatch2DRenderer;
  ImgA, ImgB: TRGBAlphaImage;
  DrawA, DrawB: TDrawableImage;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6703)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.Viewport := Rectangle(0, 0, 800, 600);
  DrawA := nil;
  DrawB := nil;
  try
    ImgA := TRGBAlphaImage.Create(32, 32);
    ImgA.Clear(Vector4Byte(255, 200, 100, 200));
    DrawA := TDrawableImage.Create(ImgA, True, True);

    ImgB := TRGBAlphaImage.Create(48, 48);
    ImgB.Clear(Vector4Byte(100, 255, 150, 255));
    DrawB := TDrawableImage.Create(ImgB, False, True);

    Cmd := Device.BeginFrame;
    VkCmd := Cmd as TVulkanRHICommandList;
    SetActiveCommandList(Cmd);

    Batcher := EnsureBatch2DRenderer(Device);
    Batcher.Begin2DPass(Cmd, 800, 600);
    try
      { 1. Standard alpha-blended rotated sprite }
      DrawA.Alpha := acBlending;
      DrawA.Rotation := Pi / 4;
      DrawA.RotationCenter := Vector2(0.5, 0.5);
      DrawA.Draw(FloatRectangle(50, 50, 64, 64));

      { 2. Additive blend mode on same texture -> triggers batch flush }
      DrawA.BlendingSourceFactor := bsSrcAlpha;
      DrawA.BlendingDestinationFactor := bdOne;
      DrawA.Draw(FloatRectangle(120, 50, 64, 64));

      { 3. 9-slice Draw3x3 with rotation on second texture -> triggers batch flush + 9 quads }
      DrawB.Rotation := Pi / 6;
      DrawB.Draw3x3(FloatRectangle(200, 100, 120, 80), Vector4Integer(8, 8, 8, 8));
    finally
      Batcher.End2DPass;
    end;

    AssertEquals('Total quads in 2D pass (1 + 1 + 9)', 11, Batcher.FrameQuadCount);
    AssertEquals('Three distinct state batches must flush 3 times', 3, Batcher.BatchFlushCount);
    AssertTrue('Each flushed batch must bind a 2D graphics pipeline on the command list',
      VkCmd.PipelineBindCount >= 3);

    Device.EndFrameAndPresent;
  finally
    FreeAndNil(DrawB);
    FreeAndNil(DrawA);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestDrawPrimitive2DFanAndLineLoopExpansionAndShadersRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Pipe: TRHIPipeline;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  SavedCtx := RenderContext;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6801)), True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  TestCtx := TRenderContext.Create(nil);
  try
    SetRHIDevice(VkDev);
    RenderContext := TestCtx;
    TestCtx.Viewport := Rectangle(0, 0, 800, 600);
    CmdList.BeginRecording;
    SetActiveCommandList(CmdList);
    RHIPrimitive2DResetStats;

    { 1. DrawRectangle (pmTriangleFan with 4 input vertices -> expanded to 6 triangle-list vertices) }
    DrawRectangle(FloatRectangle(10, 20, 100, 50), Red);
    AssertEquals('DrawRectangle input vertex count is 4', 4, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawRectangle submitted vertex count is expanded to 6 (2 triangles)',
      6, RHIPrimitive2DLastSubmittedVertexCount);
    Pipe := RHIPrimitive2DPipeline as TRHIPipeline;
    AssertTrue('DrawRectangle RHI pipeline must be created', Pipe <> nil);
    AssertTrue('DrawRectangle RHI pipeline must have compiled VertexShader',
      Pipe.Desc.VertexShader <> nil);
    AssertTrue('DrawRectangle RHI pipeline must have compiled FragmentShader',
      Pipe.Desc.FragmentShader <> nil);
    AssertEquals('DrawRectangle RHI pipeline PushConstantSize must be 32 bytes',
      32, Pipe.Desc.PushConstantSize);
    AssertTrue('DrawRectangle RHI pipeline PushConstantStages must include ssVertex and ssFragment',
      (ssVertex in Pipe.Desc.PushConstantStages) and (ssFragment in Pipe.Desc.PushConstantStages));
    AssertFalse('Opaque DrawRectangle must have BlendEnable = False',
      Pipe.Desc.BlendState.BlendEnable);

    { 2. DrawRectangleOutline (pmLineLoop with 4 input vertices -> expanded to 5 line-strip vertices) }
    DrawRectangleOutline(FloatRectangle(10, 20, 100, 50), Green, 2.0);
    AssertEquals('DrawRectangleOutline input vertex count is 4', 4, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawRectangleOutline submitted vertex count is expanded to 5 to close the loop',
      5, RHIPrimitive2DLastSubmittedVertexCount);

    { 3. DrawCircle (12 slices -> 36 pre-expanded triangle vertices, must not double-expand) }
    DrawCircle(Vector2(50, 50), 25, 25, Blue, 12);
    AssertEquals('DrawCircle input vertex count is 36', 36, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawCircle submitted vertex count remains 36 without double-expansion',
      36, RHIPrimitive2DLastSubmittedVertexCount);

    { 4. DrawCircleOutline (16 slices -> 16 input vertices, 17 submitted line-strip vertices) }
    DrawCircleOutline(Vector2(50, 50), 25, 25, Yellow, 1.5, 16);
    AssertEquals('DrawCircleOutline input vertex count is 16', 16, RHIPrimitive2DLastVertexCount);
    AssertEquals('DrawCircleOutline submitted vertex count is 17 to close the loop',
      17, RHIPrimitive2DLastSubmittedVertexCount);

    { 5. Multiplicative blend mode via DrawRectangle with ForceBlending (used by GLFadeRectangleDark) }
    DrawRectangle(Rectangle(0, 0, 800, 600), Vector4(0.5, 0.2, 0.2, 1.0),
      bsZero, bdSrcColor, True);
    Pipe := RHIPrimitive2DPipeline as TRHIPipeline;
    AssertTrue('ForceBlending DrawRectangle must have BlendEnable = True',
      Pipe.Desc.BlendState.BlendEnable);
    AssertEquals('SrcColorBlendFactor must map bsZero -> bfZero',
      Ord(bfZero), Ord(Pipe.Desc.BlendState.SrcColorBlendFactor));
    AssertEquals('DstColorBlendFactor must map bdSrcColor -> bfSrcColor',
      Ord(bfSrcColor), Ord(Pipe.Desc.BlendState.DstColorBlendFactor));

    CmdList.EndRecording;
  finally
    RHIPrimitive2DResetStats;
    SetActiveCommandList(SavedCmdList);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedDevice);
    FreeAndNil(TestCtx);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderUnlitMeshShadersPushConstantsAndDepthStateRHI;
var
  SavedDevice: TRHIDevice;
  SavedCmdList: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  VkDev: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  Mesh: TCastleRenderUnlitMesh;
begin
  SavedDevice := RHIDevice;
  SavedCmdList := ActiveCommandList;
  SavedCtx := RenderContext;
  VkDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6802)), True, True, VK_API_VERSION_1_3);
  CmdList := TVulkanRHICommandList.Create(VkDev, 0, cllPrimary);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  try
    SetRHIDevice(VkDev);
    CmdList.BeginRecording;
    SetActiveCommandList(CmdList);

    Mesh := TCastleRenderUnlitMesh.Create(True);
    try
      Mesh.Color := Vector4(1, 0.5, 0.25, 1);
      Mesh.ModelViewProjection := TMatrix4.Identity;
      Mesh.SetVertexes([
        Vector4(0, 0, 0, 1),
        Vector4(1, 0, 0, 1),
        Vector4(0, 1, 0, 1)
      ], False);

      { 1. Render with DepthTest = True and UseColor = True }
      TestCtx.DepthTest := True;
      Mesh.Render(pmTriangles);
      AssertTrue('UnlitMesh must compile RHIVertShader', Mesh.RHIVertShader <> nil);
      AssertTrue('UnlitMesh must compile RHIFragShader', Mesh.RHIFragShader <> nil);
      AssertTrue('UnlitMesh RHIPipeline must bind RHIVertShader',
        Mesh.RHIPipeline.Desc.VertexShader = Mesh.RHIVertShader);
      AssertTrue('UnlitMesh RHIPipeline must bind RHIFragShader',
        Mesh.RHIPipeline.Desc.FragmentShader = Mesh.RHIFragShader);
      AssertEquals('UnlitMesh PushConstantSize must be 80 bytes (mat4 + vec4)',
        SizeOf(TMatrix4) + SizeOf(TVector4), Mesh.RHIPipeline.Desc.PushConstantSize);
      AssertTrue('UnlitMesh DepthTestEnable must be True when RenderContext.DepthTest is True',
        Mesh.RHIPipeline.Desc.DepthStencil.DepthTestEnable);
      AssertTrue('UnlitMesh DepthWriteEnable must be True when UseColor is True',
        Mesh.RHIPipeline.Desc.DepthStencil.DepthWriteEnable);
      AssertEquals('UnlitMesh ColorWriteMask must be $0F when UseColor is True',
        $0F, Mesh.RHIPipeline.Desc.BlendState.ColorWriteMask);

      { 2. Render with DepthTest = False (e.g. skybox background pass) }
      TestCtx.DepthTest := False;
      Mesh.Render(pmTriangles);
      AssertFalse('UnlitMesh DepthTestEnable must follow RenderContext.DepthTest = False',
        Mesh.RHIPipeline.Desc.DepthStencil.DepthTestEnable);
      AssertFalse('UnlitMesh DepthWriteEnable must be False when DepthTest is False',
        Mesh.RHIPipeline.Desc.DepthStencil.DepthWriteEnable);

      { 3. Render with UseColor = False (e.g. shadow volume / depth-stencil-only pass) }
      TestCtx.DepthTest := True;
      Mesh.UseColor := False;
      Mesh.Render(pmTriangles);
      AssertTrue('UnlitMesh DepthTestEnable must be True',
        Mesh.RHIPipeline.Desc.DepthStencil.DepthTestEnable);
      AssertFalse('UnlitMesh DepthWriteEnable must be False when UseColor is False',
        Mesh.RHIPipeline.Desc.DepthStencil.DepthWriteEnable);
      AssertEquals('UnlitMesh ColorWriteMask must be 0 when UseColor is False',
        0, Mesh.RHIPipeline.Desc.BlendState.ColorWriteMask);
    finally
      FreeAndNil(Mesh);
    end;

    CmdList.EndRecording;
  finally
    SetActiveCommandList(SavedCmdList);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedDevice);
    FreeAndNil(TestCtx);
    FreeAndNil(CmdList);
    FreeAndNil(VkDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportMainSceneScreenEffectRHIPipelineAndRenderRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  SeNode: TScreenEffectNode;
  ShaderNode: TComposedShaderNode;
  FragPart: TShaderPartNode;
  SePipe: TRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6803)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.Viewport := Rectangle(0, 0, 256, 256);
  Container := nil;
  try
    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := False;
    Viewport.Width := 256;
    Viewport.Height := 256;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 10.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;

    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    SeNode := TScreenEffectNode.Create;
    ShaderNode := TComposedShaderNode.Create;
    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.SetUrl(['data:text/plain,' +
      'void main() {' + LineEnding +
      '  gl_FragColor = screen_get_color(screen_position());' + LineEnding +
      '}']);
    ShaderNode.SetParts([FragPart]);
    SeNode.SetShaders([ShaderNode]);
    Root.AddChildren(SeNode);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}

    Viewport.EnsureRHIScreenResources(256, 256, False);
    SePipe := Viewport.GetScreenEffectRHIPipeline(0);
    AssertTrue('Viewport.GetScreenEffectRHIPipeline(0) must resolve MainScene ScreenEffect RHI pipeline',
      SePipe <> nil);
    AssertTrue('Resolved MainScene ScreenEffect RHI pipeline must match Scene.InternalScreenEffectRHIPipeline(0)',
      SePipe = Scene.InternalScreenEffectRHIPipeline(0));

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    AssertEquals('Viewport must execute 1 RHI screen effect pass from MainScene',
      1, Viewport.RHIScreenPassCount);
    AssertEquals('Viewport must record 1 RHI screen effect fullscreen quad draw from MainScene',
      1, Viewport.RHIScreenDrawCount);
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewport3DSkyboxAndImageBackgroundRotationOnlyViewMatrixRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  VkCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Bg: TCastleBackground;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Block: TCastleSceneUniformBlock;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6901)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.Viewport := Rectangle(0, 0, 256, 256);
  Container := nil;
  Renderer := nil;
  Cam := nil;
  try
    { 1. Verify TRenderer.BuildSceneUniformBlock honors RenderingCamera.RotationOnly }
    Renderer := TRenderer.Create(nil);
    Cam := TRenderingCamera.Create;
    Cam.Target := rtScreen;
    Cam.FromViewVectors(
      Vector3(100.0, 200.0, 300.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0),
      TMatrix4.Identity);
    Cam.RotationOnly := True;
    FillChar(Stats, SizeOf(Stats), 0);
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
    try
      Renderer.BuildSceneUniformBlock(Block);
      AssertTrue('RotationOnly ViewMatrix must have zero translation X',
        SameValue(Block.ViewMatrix.Rows[0].W, 0.0, 1e-4));
      AssertTrue('RotationOnly ViewMatrix must have zero translation Y',
        SameValue(Block.ViewMatrix.Rows[1].W, 0.0, 1e-4));
      AssertTrue('RotationOnly ViewMatrix must have zero translation Z',
        SameValue(Block.ViewMatrix.Rows[2].W, 0.0, 1e-4));
      AssertTrue('RotationOnly CameraPosition must be (0,0,0,0)',
        SameValue(Block.CameraPosition.Length, 0.0, 1e-4));
    finally
      Renderer.RenderEnd;
    end;

    { 2. Render TCastleViewport with TCastleBackground skybox/sphere in headless Vulkan RHI mode }
    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(50.0, 25.0, 75.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Bg := TCastleBackground.Create(Viewport);
    Bg.SkyEquatorColor := Vector3(0.5, 0.7, 1.0);
    Bg.GroundEquatorColor := Vector3(0.3, 0.25, 0.2);
    Viewport.Background := Bg;
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
      VkCmd := Cmd as TVulkanRHICommandList;
      AssertTrue('TCastleBackground must have an initialized InternalBackgroundRenderer',
        Bg.InternalBackgroundRenderer <> nil);
      AssertTrue('TCastleBackground InternalBackgroundRenderer must record >= 1 RHI render pass',
        Bg.InternalBackgroundRenderer.RHIRenderCount >= 1);
      AssertTrue('Viewport with skybox background must bind a graphics pipeline',
        VkCmd.PipelineBindCount >= 1);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportStencilShadowVolumesEndToEndMultiPassAndMeshPSORHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  LightNode: TPointLightNode;
  CasterShape, ReceiverShape: TShapeNode;
  CasterBox, ReceiverBox: TBoxNode;
  CasterApp, ReceiverApp: TAppearanceNode;
  CasterMat, ReceiverMat: TPhysicalMaterialNode;
  SvRenderer: TGLShadowVolumeRenderer;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  RShape: TX3DRendererShape;
  LitDesc: TRHIGraphicsPipelineDesc;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6902)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  TestCtx.Viewport := Rectangle(0, 0, 256, 256);
  Container := nil;
  Renderer := nil;
  Cam := nil;
  try
    Container := TTestHeadlessVulkanContainer.Create(nil);
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.ShadowVolumes := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 2.0, 10.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;

    LightNode := TPointLightNode.Create;
    LightNode.Location := Vector3(0.0, 8.0, 2.0);
    LightNode.FdShadowVolumes.Value := True;
    LightNode.FdShadowVolumesMain.Value := True;
    Root.AddChildren(LightNode);

    CasterShape := TShapeNode.Create;
    CasterBox := TBoxNode.Create;
    CasterBox.Size := Vector3(1.5, 1.5, 1.5);
    CasterShape.Geometry := CasterBox;
    CasterApp := TAppearanceNode.Create;
    CasterMat := TPhysicalMaterialNode.Create;
    CasterMat.BaseColor := Vector3(0.8, 0.2, 0.2);
    CasterApp.Material := CasterMat;
    CasterShape.Appearance := CasterApp;
    Root.AddChildren(CasterShape);

    ReceiverShape := TShapeNode.Create;
    ReceiverBox := TBoxNode.Create;
    ReceiverBox.Size := Vector3(6.0, 0.5, 6.0);
    ReceiverShape.Geometry := ReceiverBox;
    ReceiverApp := TAppearanceNode.Create;
    ReceiverMat := TPhysicalMaterialNode.Create;
    ReceiverMat.BaseColor := Vector3(0.7, 0.7, 0.7);
    ReceiverApp.Material := ReceiverMat;
    ReceiverShape.Appearance := ReceiverApp;
    Root.AddChildren(ReceiverShape);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    SvRenderer := Viewport.InternalShadowVolumeRenderer;
    AssertTrue('Viewport.InternalShadowVolumeRenderer must be allocated', SvRenderer <> nil);
    AssertTrue('ShadowVolumeRenderer must execute >= 4 RHI passes during Viewport render',
      SvRenderer.RHIRenderPassCount >= 4);
    AssertTrue('ShadowVolumeRenderer.Mesh must record >= 1 RHI draw call for silhouette quads',
      SvRenderer.Mesh.RHIDrawCallCount >= 1);
    AssertTrue('ShadowVolumeRenderer.Mesh must bind a stencil shadow volume RHI PSO',
      SvRenderer.Mesh.RHIPipeline <> nil);
    AssertTrue('ShadowVolumeRenderer.Mesh PSO must have StencilTestEnable = True',
      (SvRenderer.Mesh.RHIPipeline as TVulkanRHIPipeline).Desc.DepthStencil.StencilTestEnable);

    { Verify TRenderer.BuildShapePipelineDesc in FInternalPass = 1 produces DefaultStencilLitPass }
    Renderer := TRenderer.Create(nil);
    Cam := TRenderingCamera.Create;
    Cam.Target := rtScreen;
    Cam.Matrix := TMatrix4.Identity;
    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    FillChar(Stats, SizeOf(Stats), 0);
    Renderer.RenderBegin(nil, Cam, nil, 1 { InternalPass = 1 }, 0, 0, @Stats);
    try
      Renderer.BuildShapePipelineDesc(RShape, Scene.RenderOptions, LitDesc);
      AssertTrue('InternalPass = 1 opaque shape PSO must have StencilTestEnable = True',
        LitDesc.DepthStencil.StencilTestEnable);
      AssertEquals('InternalPass = 1 opaque shape PSO must use DepthCompareOp = coLessOrEqual',
        Ord(coLessOrEqual), Ord(LitDesc.DepthStencil.DepthCompareOp));
      AssertEquals('InternalPass = 1 opaque shape PSO must use FrontStencil.CompareOp = coEqual',
        Ord(coEqual), Ord(LitDesc.DepthStencil.FrontStencil.CompareOp));
    finally
      Renderer.RenderEnd;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSceneUpdateGeneratedTexturesRenderedTextureAndShadowMapRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Options: TCastleRenderOptions;
  RtNode: TRenderedTextureNode;
  RtRes: TRenderedTextureResource;
  SmNode: TGeneratedShadowMapNode;
  SmRes: TGeneratedShadowMapResource;
  CamView: TViewVectors;
  InitialProj: TMatrix4;
  InitialVp: TRectangle;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($6903)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  InitialVp := Rectangle(10, 20, 800, 600);
  InitialProj := OrthoProjectionMatrix(FloatRectangle(0, 0, 800, 600), -1, 1);
  TestCtx.Viewport := InitialVp;
  TestCtx.ProjectionMatrix := InitialProj;
  Options := TCastleRenderOptions.Create(nil);
  RtNode := TRenderedTextureNode.Create;
  SmNode := TGeneratedShadowMapNode.Create;
  try
    RtNode.SetDimensions([128, 64, 4, 1, 1]);
    TTextureResources.Prepare(Options, RtNode);
    RtRes := TRenderedTextureResource(RtNode.InternalRendererResource);
    SmNode.Size := 256;
    TTextureResources.Prepare(Options, SmNode);
    SmRes := TGeneratedShadowMapResource(SmNode.InternalRendererResource);

    FillChar(CamView, SizeOf(CamView), 0);
    CamView.Direction := Vector3(0, 0, -1);
    CamView.Up := Vector3(0, 1, 0);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      FRenderFromViewpointCalls := 0;
      RtRes.Update(@DummyRenderFromViewpointCallback, 0.1, 100.0, nil, True, CamView, nil);
      AssertEquals('RenderedTexture.Update must invoke callback once', 1, FRenderFromViewpointCalls);
      AssertEquals('RenderedTexture.Update must increment RHIUpdateCount', 1, RtRes.RHIUpdateCount);
      AssertTrue('RenderedTexture.Update must restore RenderContext.Viewport',
        TestCtx.Viewport.Equals(InitialVp));
      AssertTrue('RenderedTexture.Update must restore RenderContext.ProjectionMatrix',
        TMatrix4.PerfectlyEquals(TestCtx.ProjectionMatrix, InitialProj));

      SmRes.Update(@DummyRenderFromViewpointCallback, 0.1, 100.0, nil);
      AssertEquals('GeneratedShadowMap.Update must invoke callback once', 2, FRenderFromViewpointCalls);
      AssertEquals('GeneratedShadowMap.Update must increment RHIUpdateCount', 1, SmRes.RHIUpdateCount);
      AssertTrue('GeneratedShadowMap.Update must restore RenderContext.Viewport',
        TestCtx.Viewport.Equals(InitialVp));
      AssertTrue('GeneratedShadowMap.Update must restore RenderContext.ProjectionMatrix',
        TMatrix4.PerfectlyEquals(TestCtx.ProjectionMatrix, InitialProj));
    finally
      Device.EndFrameAndPresent;
    end;
    TTextureResources.Unprepare(RtNode);
    TTextureResources.Unprepare(SmNode);
  finally
    FreeAndNil(SmNode);
    FreeAndNil(RtNode);
    FreeAndNil(Options);
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportOcclusionCullingEndToEndAndBoxUnlitMeshPSORHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  SceneFront, SceneBack: TCastleScene;
  Root1, Root2: TX3DRootNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  Box1, Box2: TBoxNode;
  OccRenderer: TOcclusionCullingRenderer;
  Pool0: TVulkanRHIQueryPool;
  BoxPso: TRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7001)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.OcclusionCulling := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 10.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    SceneFront := TCastleScene.Create(Viewport);
    Root1 := TX3DRootNode.Create;
    ShapeNode1 := TShapeNode.Create;
    Box1 := TBoxNode.Create;
    Box1.Size := Vector3(4.0, 4.0, 1.0);
    ShapeNode1.Geometry := Box1;
    Root1.AddChildren(ShapeNode1);
    SceneFront.Load(Root1, True);
    SceneFront.Translation := Vector3(0.0, 0.0, 2.0);
    Viewport.Items.Add(SceneFront);

    SceneBack := TCastleScene.Create(Viewport);
    Root2 := TX3DRootNode.Create;
    ShapeNode2 := TShapeNode.Create;
    Box2 := TBoxNode.Create;
    Box2.Size := Vector3(1.0, 1.0, 1.0);
    ShapeNode2.Geometry := Box2;
    Root2.AddChildren(ShapeNode2);
    SceneBack.Load(Root2, True);
    SceneBack.Translation := Vector3(0.0, 0.0, -5.0);
    Viewport.Items.Add(SceneBack);

    OccRenderer := Viewport.InternalShapesRenderer.InternalOcclusionCullingRenderer;
    AssertTrue('OccRenderer must exist on Viewport.InternalShapesRenderer', OccRenderer <> nil);

    { Frame 1: Both shapes render and issue occlusion queries }
    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
      AssertEquals('Frame 1 must issue 2 occlusion queries', 2, OccRenderer.RHIQueriesIssuedCount);
      AssertEquals('Frame 1 must allocate 2 query slots', 2, OccRenderer.AllocatedRHIQuerySlots);
      AssertEquals('Frame 1 must render both shapes', 2, Viewport.Statistics.ShapesRendered);
    finally
      Device.EndFrameAndPresent;
    end;

    { Simulate Frame 1 query results: slot 0 visible (400 samples), slot 1 occluded (0 samples) }
    Pool0 := OccRenderer.GetRHIQueryPool(0) as TVulkanRHIQueryPool;
    AssertTrue('QueryPool page 0 must be created', Pool0 <> nil);
    Pool0.SetSimulatedResult(0, 400);
    Pool0.SetSimulatedResult(1, 0);

    { Frame 2: Occluded shape is skipped and its bounding box is drawn with RenderBoxMesh RHI PSO }
    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
      AssertEquals('Frame 2 must render only 1 visible shape', 1, Viewport.Statistics.ShapesRendered);
      AssertEquals('Frame 2 must occlusion-query 1 bounding box for the occluded shape',
        1, Viewport.Statistics.BoxesOcclusionQueriedCount);
      AssertTrue('OccRenderer.Utils.RenderBoxMesh must be created',
        OccRenderer.Utils.RenderBoxMesh <> nil);
      BoxPso := OccRenderer.Utils.RenderBoxMesh.RHIPipeline as TRHIPipeline;
      AssertTrue('OccRenderer.Utils.RenderBoxMesh.RHIPipeline must be compiled and bound',
        BoxPso <> nil);
      AssertFalse('Occlusion box PSO must disable depth writes (DepthWriteEnable = False)',
        BoxPso.Desc.DepthStencil.DepthWriteEnable);
      AssertEquals('Occlusion box PSO must disable color writes (ColorWriteMask = 0)',
        0, BoxPso.Desc.BlendState.ColorWriteMask);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportDynamicBatchingMergesShapesAndUploadsRHIBuffersRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene1, Scene2: TCastleScene;
  Root1, Root2: TX3DRootNode;
  ShapeNode1, ShapeNode2: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1, Mat2: TPhysicalMaterialNode;
  Ifs1, Ifs2: TIndexedFaceSetNode;
  Coord1, Coord2: TCoordinateNode;
  Batching: TBatchShapes;
  MergedShape: TGLShape;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7002)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.DynamicBatching := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 10.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene1 := TCastleScene.Create(Viewport);
    Root1 := TX3DRootNode.Create;
    ShapeNode1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TPhysicalMaterialNode.Create;
    Mat1.BaseColor := Vector3(0.8, 0.4, 0.2);
    App1.Material := Mat1;
    ShapeNode1.Appearance := App1;
    Ifs1 := TIndexedFaceSetNode.Create;
    Coord1 := TCoordinateNode.Create;
    Coord1.SetPoint([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]);
    Ifs1.Coord := Coord1;
    Ifs1.SetCoordIndex([0, 1, 2, -1, 0, 2, 3, -1]);
    ShapeNode1.Geometry := Ifs1;
    Root1.AddChildren(ShapeNode1);
    Scene1.Load(Root1, True);
    Scene1.Translation := Vector3(-2.0, 0.0, 0.0);
    Viewport.Items.Add(Scene1);

    Scene2 := TCastleScene.Create(Viewport);
    Root2 := TX3DRootNode.Create;
    ShapeNode2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Mat2 := TPhysicalMaterialNode.Create;
    Mat2.BaseColor := Vector3(0.8, 0.4, 0.2);
    App2.Material := Mat2;
    ShapeNode2.Appearance := App2;
    Ifs2 := TIndexedFaceSetNode.Create;
    Coord2 := TCoordinateNode.Create;
    Coord2.SetPoint([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]);
    Ifs2.Coord := Coord2;
    Ifs2.SetCoordIndex([0, 1, 2, -1, 0, 2, 3, -1]);
    ShapeNode2.Geometry := Ifs2;
    Root2.AddChildren(ShapeNode2);
    Scene2.Load(Root2, True);
    Scene2.Translation := Vector3(2.0, 0.0, 0.0);
    Viewport.Items.Add(Scene2);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      Batching := Viewport.InternalShapesRenderer.InternalBatching;
      AssertTrue('Batching must exist on Viewport.InternalShapesRenderer', Batching <> nil);
      AssertEquals('RHICommitBatchCount must be 1 after merging Scene1 and Scene2',
        1, Batching.RHICommitBatchCount);
      MergedShape := Batching.RHILastMergedShape;
      AssertTrue('RHILastMergedShape must be assigned', MergedShape <> nil);
      AssertTrue('MergedShape.Cache must be allocated', MergedShape.Cache <> nil);
      AssertTrue('MergedShape.Cache.RHICoordinateBuffer must be uploaded',
        MergedShape.Cache.RHICoordinateBuffer <> nil);
      AssertEquals('MergedShape.Cache.RHICoordinateBuffer.Desc.Size must be 288 (12 vertices * 24 bytes)',
        12 * 24, Integer(MergedShape.Cache.RHICoordinateBuffer.Desc.Size));
      AssertTrue('MergedShape.Cache.RHIMaterialDescriptorSet must be bound for merged appearance',
        MergedShape.Cache.RHIMaterialDescriptorSet <> nil);
      AssertEquals('DynamicBatching must reduce ShapesRendered from 2 to 1 merged shape',
        1, Viewport.Statistics.ShapesRendered);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapeExtractRHIMaterialTexturesAllResourceTypesAndOnDemandPrepareRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  BoxNode: TBoxNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  MultiTex: TMultiTextureNode;
  PixTex2D: TPixelTextureNode;
  RenderedTex: TRenderedTextureNode;
  GenCubeTex: TGeneratedCubeMapTextureNode;
  PixTex3D: TPixelTexture3DNode;
  GenShadowTex: TGeneratedShadowMapNode;
  RShape: TX3DRendererShape;
  BaseRHI, NormRHI, MRRHI, EmissiveRHI, OccRHI: TRHITexture;
  TexCount: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7003)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  Scene := TCastleScene.Create(nil);
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;

    { 1. MultiTexture wrapping an unprepared PixelTexture2D }
    MultiTex := TMultiTextureNode.Create;
    PixTex2D := TPixelTextureNode.Create;
    PixTex2D.FdImage.Value := TRGBImage.Create(4, 4);
    MultiTex.FdTexture.Add(PixTex2D);
    PhysMat.FdBaseTexture.Value := MultiTex;

    { 2. Unprepared RenderedTextureNode }
    RenderedTex := TRenderedTextureNode.Create;
    RenderedTex.SetDimensions([64, 32, 4, 1, 1]);
    PhysMat.FdNormalTexture.Value := RenderedTex;

    { 3. Unprepared GeneratedCubeMapTextureNode }
    GenCubeTex := TGeneratedCubeMapTextureNode.Create;
    GenCubeTex.Size := 32;
    PhysMat.MetallicRoughnessTexture := GenCubeTex;

    { 4. Unprepared PixelTexture3DNode (Components=1, Width=2, Height=2, Depth=2 + 8 voxel values) }
    PixTex3D := TPixelTexture3DNode.Create;
    PixTex3D.SetImage([1, 2, 2, 2, 255, 255, 255, 255, 255, 255, 255, 255]);
    PhysMat.EmissiveTexture := PixTex3D;

    { 5. Unprepared GeneratedShadowMapNode }
    GenShadowTex := TGeneratedShadowMapNode.Create;
    GenShadowTex.Size := 128;
    PhysMat.OcclusionTexture := GenShadowTex;

    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    Root.AddChildren(ShapeNode);
    Scene.Load(Root, True);

    { Notice: we do NOT call PrepareResources beforehand; ExtractRHIMaterialTextures must prepare on demand! }
    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    TexCount := RShape.ExtractRHIMaterialTextures(BaseRHI, NormRHI, MRRHI, EmissiveRHI, OccRHI);

    AssertEquals('ExtractRHIMaterialTextures must resolve all 5 texture slots on demand', 5, TexCount);
    AssertTrue('BaseRHI (MultiTexture -> PixelTexture2D) must be resolved', BaseRHI <> nil);
    AssertEquals('BaseRHI dimension must be td2D', Ord(td2D), Ord(BaseRHI.Desc.Dimension));
    AssertTrue('NormRHI (RenderedTexture) must be resolved', NormRHI <> nil);
    AssertEquals('NormRHI width must be 64', 64, NormRHI.Desc.Width);
    AssertTrue('MRRHI (GeneratedCubeMapTexture) must be resolved', MRRHI <> nil);
    AssertEquals('MRRHI dimension must be tdCube', Ord(tdCube), Ord(MRRHI.Desc.Dimension));
    AssertTrue('EmissiveRHI (PixelTexture3D) must be resolved', EmissiveRHI <> nil);
    AssertEquals('EmissiveRHI dimension must be td3D', Ord(td3D), Ord(EmissiveRHI.Desc.Dimension));
    AssertTrue('OccRHI (GeneratedShadowMap) must be resolved', OccRHI <> nil);
    AssertEquals('OccRHI format must be pfD32_Float', Ord(pfD32_Float), Ord(OccRHI.Desc.Format));
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportSkinNodeGPUSkinningEndToEndAndJointUploadRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SkinNode: TSkinNode;
  Joint0, Joint1: TTransformNode;
  ShapeNode: TShapeNode;
  TriSet: TIndexedTriangleSetNode;
  CoordNode: TCoordinateNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  RShape: TX3DRendererShape;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7101)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Viewport);
    Root := TX3DRootNode.Create;

    Joint0 := TTransformNode.Create;
    Joint0.X3DName := 'Joint0';
    Joint1 := TTransformNode.Create;
    Joint1.X3DName := 'Joint1';
    Joint1.Translation := Vector3(0, 1, 0);
    Joint0.AddChildren(Joint1);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(0.8, 0.4, 0.2);
    App.Material := Mat;
    ShapeNode.Appearance := App;

    TriSet := TIndexedTriangleSetNode.Create;
    CoordNode := TCoordinateNode.Create;
    CoordNode.SetPoint([
      Vector3(-1, 0, -3),
      Vector3( 1, 0, -3),
      Vector3( 0, 2, -3)
    ]);
    TriSet.Coord := CoordNode;
    TriSet.SetIndex([0, 1, 2]);
    TriSet.SetSkinJoints0([
      0, 1, 0, 0,
      0, 1, 0, 0,
      1, 0, 0, 0
    ]);
    TriSet.SetSkinWeights0([
      Vector4(1.0, 0.0, 0.0, 0.0),
      Vector4(0.5, 0.5, 0.0, 0.0),
      Vector4(1.0, 0.0, 0.0, 0.0)
    ]);
    ShapeNode.Geometry := TriSet;

    SkinNode := TSkinNode.Create('', '');
    SkinNode.Skeleton := Joint0;
    SkinNode.SetJoints([Joint0, Joint1]);
    SkinNode.SetInverseBindMatrices([TMatrix4.Identity, TMatrix4.Identity]);
    SkinNode.FdShapes.Add(ShapeNode);
    Root.AddChildren(SkinNode);

    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
    Viewport.Camera.SetView(
      Vector3(0, 0, 5),
      Vector3(0, 0, -1),
      Vector3(0, 1, 0)
    );

    AssertTrue('TSkinNode.InternalMeshCalculation must select GPU skinning in pure Vulkan RHI mode',
      SkinNode.InternalMeshCalculation <> TSkinNode.TInternalMeshCalculation.mcCpu);

    { Trigger joint animation update }
    Joint1.Translation := Vector3(1.5, 2.0, -0.5);
    SkinNode.InternalUpdateSkin;
    AssertTrue('SkinNode.InternalJointMatrix must be populated', SkinNode.InternalJointMatrix <> nil);
    AssertEquals('SkinNode.InternalJointMatrix count must match 2 joints', 2, SkinNode.InternalJointMatrix.Count);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;
    finally
      Device.EndFrameAndPresent;
    end;

    RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
    AssertTrue('Skinned RShape.Cache must be allocated', RShape.Cache <> nil);
    AssertTrue('Skinned RShape.Cache.RHIJointBuffer must be allocated and uploaded',
      RShape.Cache.RHIJointBuffer <> nil);
    AssertEquals('RHIJointBuffer size must equal 2 * SizeOf(TMatrix4) (128 bytes)',
      2 * SizeOf(TMatrix4), Integer(RShape.Cache.RHIJointBuffer.Desc.Size));
    AssertTrue('Skinned RShape.Cache.RHISkinningDescriptorSet (Set 2) must be allocated',
      RShape.Cache.RHISkinningDescriptorSet <> nil);
    AssertTrue('Skinned RShape.Cache.RHIShaderPermutationMask bit 0 (AHasSkinning) must be set',
      (RShape.Cache.RHIShaderPermutationMask and $01) <> 0);
    AssertTrue('Specialized vertex shader must include CastleSkinningBlock',
      Pos('CastleSkinningBlock', RShape.Cache.RHIVertexShaderSource) > 0);
  finally
    FreeAndNil(Container);
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleMask2DAnd3DStencilMaskingEndToEndRHI;
var
  Device: TVulkanRHIDevice;
  Cmd: TRHICommandList;
  Batcher: TCastleBatch2DRenderer;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx, TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  MaskControl: TCastleMask;
  MaskRect, ChildRect: TCastleRectangleControl;
  ChildImg: TCastleImageControl;
  MaskWritePipe, MaskedChildPipe: TRHIPipeline;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7102)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SetRHIDevice(Device);
  ApplicationProperties.RenderBackend := backendVulkan;
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  RenderContext.Viewport := Rectangle(0, 0, 400, 300);
  Batcher := EnsureBatch2DRenderer(Device);
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    MaskControl := TCastleMask.Create(Container);
    MaskControl.FullSize := True;
    MaskControl.MaskRendering := mrChildrenWhereMask;
    Container.Controls.InsertFront(MaskControl);

    MaskRect := TCastleRectangleControl.Create(MaskControl);
    MaskRect.Width := 200;
    MaskRect.Height := 150;
    MaskControl.Mask.InsertFront(MaskRect);

    ChildRect := TCastleRectangleControl.Create(MaskControl);
    ChildRect.Width := 300;
    ChildRect.Height := 200;
    ChildRect.Color := Vector4(0.2, 0.8, 0.4, 1.0);
    MaskControl.InsertFront(ChildRect);

    ChildImg := TCastleImageControl.Create(MaskControl);
    ChildImg.Content.Image := TRGBAlphaImage.Create(16, 16);
    ChildImg.Content.OwnsImage := True;
    MaskControl.InsertFront(ChildImg);

    Cmd := Device.BeginFrame;
    SetActiveCommandList(Cmd);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      { Verify that TCastleMask restored RenderContext state after rendering }
      AssertFalse('RenderContext.StencilTest must be restored to False after TCastleMask',
        RenderContext.StencilTest);
      AssertTrue('RenderContext.ColorChannels must be restored to AllColorChannels after TCastleMask',
        RenderContext.ColorChannels = AllColorChannels);
      AssertTrue('Batcher.LastPipeline from masked child image must have StencilTestEnable = True and coEqual',
        (Batcher.LastPipeline <> nil) and
        Batcher.LastPipeline.Desc.DepthStencil.StencilTestEnable and
        (Batcher.LastPipeline.Desc.DepthStencil.FrontStencil.CompareOp = coEqual) and
        (Batcher.LastPipeline.Desc.DepthStencil.FrontStencil.PassOp = soKeep) and
        (Batcher.LastPipeline.Desc.DepthStencil.FrontStencil.Reference = 1) and
        (Batcher.LastPipeline.Desc.BlendState.ColorWriteMask = $0F));

      { Also directly verify the mask-write PSO state (ColorChannels = [], coAlways, soReplace) }
      RenderContext.StencilTest := True;
      RenderContext.ColorChannels := [];
      RenderContext.StencilFunc(coAlways, 1, 0);
      RenderContext.StencilOp(soKeep, soKeep, soReplace, $FF);
      DrawRectangle(Rectangle(10, 10, 100, 100), Vector4(1, 1, 1, 1), bsSrcAlpha, bdOneMinusSrcAlpha, False);
      MaskWritePipe := TRHIPipeline(RHIPrimitive2DPipeline);
      AssertTrue('MaskWritePipe must be created', MaskWritePipe <> nil);
      AssertEquals('MaskWritePipe ColorWriteMask must be 0', 0, MaskWritePipe.Desc.BlendState.ColorWriteMask);
      AssertTrue('MaskWritePipe StencilTestEnable must be True', MaskWritePipe.Desc.DepthStencil.StencilTestEnable);
      AssertEquals('MaskWritePipe CompareOp must be coAlways',
        Ord(coAlways), Ord(MaskWritePipe.Desc.DepthStencil.FrontStencil.CompareOp));
      AssertEquals('MaskWritePipe PassOp must be soReplace',
        Ord(soReplace), Ord(MaskWritePipe.Desc.DepthStencil.FrontStencil.PassOp));

      { And verify mrChildrenWhereNoMask PSO state (coNotEqual) }
      RenderContext.ColorChannels := AllColorChannels;
      RenderContext.StencilFunc(coNotEqual, 1, 1);
      RenderContext.StencilOp(soKeep, soKeep, soKeep, 0);
      DrawRectangle(Rectangle(10, 10, 100, 100), Vector4(1, 0, 0, 1), bsSrcAlpha, bdOneMinusSrcAlpha, False);
      MaskedChildPipe := TRHIPipeline(RHIPrimitive2DPipeline);
      AssertEquals('MaskedChildPipe ColorWriteMask must be $0F', $0F, MaskedChildPipe.Desc.BlendState.ColorWriteMask);
      AssertEquals('MaskedChildPipe CompareOp must be coNotEqual',
        Ord(coNotEqual), Ord(MaskedChildPipe.Desc.DepthStencil.FrontStencil.CompareOp));
      RenderContext.StencilTest := False;
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureSizingHelpersNilSafeInPureRHIModeRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  ImgCube: TRGBImage;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7103)));
  SavedRHI := RHIDevice;
  SetRHIDevice(Device);
  ImgCube := TRGBImage.Create(16, 16);
  try
    AssertEquals('ResizeToTextureSize(300, tsAny) must preserve NPOT size in RHI mode',
      300, Integer(ResizeToTextureSize(300, tsAny)));
    AssertEquals('ResizeToTextureSize(300, tsScalablePowerOf2) must round up to 512',
      512, Integer(ResizeToTextureSize(300, tsScalablePowerOf2)));
    AssertTrue('IsTextureSized(300, 200, tsAny) must be True in RHI mode',
      IsTextureSized(300, 200, tsAny));
    AssertFalse('IsTextureSized(300, 200, tsScalablePowerOf2) must be False',
      IsTextureSized(300, 200, tsScalablePowerOf2));
    AssertTrue('IsTextureSized(ImgCube, tsAny) must be True in RHI mode',
      IsTextureSized(ImgCube, tsAny));
    AssertTrue('IsCubeMapTextureSized(64) must be True in RHI mode',
      IsCubeMapTextureSized(64));
    AssertTrue('IsCubeMapTextureSized(128) must be True in RHI mode',
      IsCubeMapTextureSized(128));
    AssertEquals('ResizeToCubeMapTextureSize(100) must round up to 128 in RHI mode',
      128, Integer(ResizeToCubeMapTextureSize(100)));
  finally
    FreeAndNil(ImgCube);
    SetRHIDevice(SavedRHI);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestCastleTextAndPrimitivesHeadlessVulkanRenderRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  CastleText: TCastleText;
  CastleBox: TCastleBox;
  CastleSphere: TCastleSphere;
  CastleImgTransform: TCastleImageTransform;
  TextScene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  TextNode: TTextNode;
  RShape: TX3DRendererShape;
  BaseColorTex, NormalTex, MRTex, EmissiveTex, OcclusionTex: TRHITexture;
  TexCount: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7201)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 10.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    CastleText := TCastleText.Create(Viewport);
    CastleText.Caption := 'Vulkan RHI 3D Text';
    CastleText.Color := Vector4(1.0, 0.85, 0.2, 1.0);
    CastleText.Size := 1.0;
    Viewport.Items.Add(CastleText);

    CastleBox := TCastleBox.Create(Viewport);
    CastleBox.Size := Vector3(1.5, 1.5, 1.5);
    CastleBox.Translation := Vector3(-3.0, 0.0, 0.0);
    Viewport.Items.Add(CastleBox);

    CastleSphere := TCastleSphere.Create(Viewport);
    CastleSphere.Radius := 0.8;
    CastleSphere.Translation := Vector3(3.0, 0.0, 0.0);
    Viewport.Items.Add(CastleSphere);

    CastleImgTransform := TCastleImageTransform.Create(Viewport);
    CastleImgTransform.LoadFromImage(TRGBAlphaImage.Create(8, 8), True);
    CastleImgTransform.Translation := Vector3(0.0, -2.5, 0.0);
    Viewport.Items.Add(CastleImgTransform);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    TextNode := TTextNode.Create;
    TextNode.SetText(['Direct X3D TextNode']);
    ShapeNode.Geometry := TextNode;
    Root.AddChildren(ShapeNode);

    TextScene := TCastleScene.Create(Viewport);
    TextScene.Load(Root, True);
    TextScene.Translation := Vector3(0.0, 2.5, 0.0);
    Viewport.Items.Add(TextScene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      AssertTrue('Viewport must render at least 5 shapes (CastleText, Box, Sphere, ImageTransform, TextScene)',
        Viewport.Statistics.ShapesRendered >= 5);
      AssertTrue('Viewport must bind graphics pipelines for rendered shapes',
        CmdList.PipelineBindCount >= 5);
      AssertTrue('TextScene must have at least 1 shape', TextScene.Shapes.TraverseList(True).Count >= 1);
      RShape := TX3DRendererShape(TextScene.Shapes.TraverseList(True)[0]);
      AssertTrue('TextNode OriginalGeometry.FontTextureNode must be non-nil',
        (RShape.OriginalGeometry <> nil) and (RShape.OriginalGeometry.FontTextureNode <> nil));
      TexCount := RShape.ExtractRHIMaterialTextures(
        BaseColorTex, NormalTex, MRTex, EmissiveTex, OcclusionTex);
      AssertEquals('TextNode ExtractRHIMaterialTextures must resolve 1 font atlas texture',
        1, Integer(TexCount));
      AssertTrue('TextNode BaseColorTex must be resolved from FontTextureNode',
        BaseColorTex <> nil);
      AssertTrue('TextNode shape shader permutation mask must include $04 (HasBaseColorTex)',
        (RShape.Cache <> nil) and ((RShape.Cache.RHIShaderPermutationMask and $04) <> 0));
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestPointSetLineSetForceUnlitAndPerVertexColorSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  PointScene, LineScene, ColorFaceScene: TCastleScene;
  Root1, Root2, Root3: TX3DRootNode;
  Shape1, Shape2, Shape3: TShapeNode;
  App1, App2: TAppearanceNode;
  PointSet: TPointSetNode;
  LineSet: TLineSetNode;
  FaceSet: TIndexedFaceSetNode;
  Coord1, Coord2, Coord3: TCoordinateNode;
  Color1, Color3: TColorNode;
  PhysMat1, PhysMat2: TPhysicalMaterialNode;
  RPointShape, RLineShape, RFaceShape: TX3DRendererShape;
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7202)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    { 1. TPointSetNode with TPhysicalMaterialNode and per-vertex TColorNode }
    Root1 := TX3DRootNode.Create;
    Shape1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    PhysMat1 := TPhysicalMaterialNode.Create;
    PhysMat1.BaseColor := Vector3(0.2, 0.9, 0.4);
    App1.Material := PhysMat1;
    Shape1.Appearance := App1;
    PointSet := TPointSetNode.Create;
    Coord1 := TCoordinateNode.Create;
    Coord1.SetPoint([Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0)]);
    Color1 := TColorNode.Create;
    Color1.SetColor([Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)]);
    PointSet.Coord := Coord1;
    PointSet.Color := Color1;
    Shape1.Geometry := PointSet;
    Root1.AddChildren(Shape1);
    PointScene := TCastleScene.Create(Viewport);
    PointScene.Load(Root1, True);
    Viewport.Items.Add(PointScene);

    { 2. TLineSetNode with TPhysicalMaterialNode }
    Root2 := TX3DRootNode.Create;
    Shape2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    PhysMat2 := TPhysicalMaterialNode.Create;
    PhysMat2.BaseColor := Vector3(0.9, 0.3, 0.1);
    App2.Material := PhysMat2;
    Shape2.Appearance := App2;
    LineSet := TLineSetNode.Create;
    Coord2 := TCoordinateNode.Create;
    Coord2.SetPoint([Vector3(-1.0, -1.0, 0.0), Vector3(1.0, -1.0, 0.0)]);
    LineSet.Coord := Coord2;
    LineSet.SetVertexCount([2]);
    Shape2.Geometry := LineSet;
    Root2.AddChildren(Shape2);
    LineScene := TCastleScene.Create(Viewport);
    LineScene.Load(Root2, True);
    Viewport.Items.Add(LineScene);

    { 3. TIndexedFaceSetNode with per-vertex TColorNode }
    Root3 := TX3DRootNode.Create;
    Shape3 := TShapeNode.Create;
    FaceSet := TIndexedFaceSetNode.Create;
    Coord3 := TCoordinateNode.Create;
    Coord3.SetPoint([
      Vector3(-1.0, 0.0, 0.0),
      Vector3( 1.0, 0.0, 0.0),
      Vector3( 0.0, 1.0, 0.0)]);
    Color3 := TColorNode.Create;
    Color3.Mode := cmModulate;
    Color3.SetColor([
      Vector3(1.0, 0.0, 0.0),
      Vector3(0.0, 1.0, 0.0),
      Vector3(0.0, 0.0, 1.0)]);
    FaceSet.Coord := Coord3;
    FaceSet.Color := Color3;
    FaceSet.SetCoordIndex([0, 1, 2, -1]);
    Shape3.Geometry := FaceSet;
    Root3.AddChildren(Shape3);
    ColorFaceScene := TCastleScene.Create(Viewport);
    ColorFaceScene.Load(Root3, True);
    Viewport.Items.Add(ColorFaceScene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      AssertEquals('3 scenes must render 3 shapes', 3, Integer(Viewport.Statistics.ShapesRendered));

      RPointShape := TX3DRendererShape(PointScene.Shapes.TraverseList(True)[0]);
      AssertTrue('TPointSetNode ExtractRHIMaterialBlock must succeed',
        RPointShape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
      AssertEquals('TPointSetNode ShadingModel must be smUnlit (via Arrays.ForceUnlit)',
        Ord(smUnlit), Ord(ShadingModel));
      AssertTrue('TPointSetNode SpecularColor.W must be < 0.0 (unlit)',
        MatBlock.SpecularColor.W < 0.0);
      AssertTrue('TPointSetNode vertex shader must write gl_PointSize = 1.0',
        Pos('gl_PointSize = 1.0;', RPointShape.Cache.RHIVertexShaderSource) > 0);
      AssertTrue('TPointSetNode with TColorNode must include $100 (HasColorPerVertex) in permutation mask',
        (RPointShape.Cache.RHIShaderPermutationMask and $100) <> 0);

      RLineShape := TX3DRendererShape(LineScene.Shapes.TraverseList(True)[0]);
      AssertTrue('TLineSetNode ExtractRHIMaterialBlock must return smUnlit (via Arrays.ForceUnlit)',
        RLineShape.ExtractRHIMaterialBlock(MatBlock, ShadingModel) and (ShadingModel = smUnlit));

      RFaceShape := TX3DRendererShape(ColorFaceScene.Shapes.TraverseList(True)[0]);
      AssertTrue('ColorFaceScene permutation mask must include $100 (HasColorPerVertex)',
        (RFaceShape.Cache <> nil) and ((RFaceShape.Cache.RHIShaderPermutationMask and $100) <> 0));
      AssertTrue('ColorFaceScene fragment shader must multiply baseColor by castle_color_per_vertex',
        (Pos('vec4 baseColor = castle_MaterialBaseColor * castle_color_per_vertex;',
          RFaceShape.Cache.RHIFragmentShaderSource) > 0) or
        (Pos('vec4 baseColor = vec4(castle_MaterialBaseColor.rgb * castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);',
          RFaceShape.Cache.RHIFragmentShaderSource) > 0));
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSolidWireframeSilhouettePolygonOffsetAndFogShaderRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  BoxNode: TBoxNode;
  PhysMat: TPhysicalMaterialNode;
  FogNode: TFogNode;
  RShape: TX3DRendererShape;
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
  BaseColorTex, NormalTex, MRTex, EmissiveTex, OcclusionTex: TRHITexture;
  PSODesc: TRHIGraphicsPipelineDesc;
  InitialDepthBiasCount: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7203)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.2, 0.6, 1.0);
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    FogNode := TFogNode.Create;
    FogNode.Color := Vector3(0.5, 0.6, 0.7);
    FogNode.VisibilityRange := 25.0;
    Root.AddChildren(ShapeNode);
    Root.AddChildren(FogNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Scene.RenderOptions.WireframeEffect := weSolidWireframe;
    Scene.RenderOptions.WireframeColor := Vector3(1.0, 0.25, 0.0);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      { weSolidWireframe renders 2 passes: solid fill with PolygonOffset + wireframe overlay with rmSolidColor }
      AssertTrue('weSolidWireframe must bind at least 2 graphics pipelines', CmdList.PipelineBindCount >= 2);
      AssertTrue('weSolidWireframe must update PolygonOffset depth bias on RenderContext',
        TestCtx.RHIDepthBiasUpdateCount >= 2);

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('Fragment shader must include CastleScene.u_FogParams fog evaluation',
        (RShape.Cache <> nil) and
        (Pos('CastleScene.u_FogParams.z > 0.5', RShape.Cache.RHIFragmentShaderSource) > 0));

      { Verify PolygonOffset maps to DepthBiasEnable in BuildShapePipelineDesc and increments RHIDepthBiasUpdateCount }
      InitialDepthBiasCount := TestCtx.RHIDepthBiasUpdateCount;
      RenderContext.PolygonOffsetEnable(1.5, 2.5);
      Viewport.InternalShapesRenderer.Renderer.BuildShapePipelineDesc(
        RShape, Scene.RenderOptions, PSODesc);
      AssertTrue('PSODesc.Rasterizer.DepthBiasEnable must be True when PolygonOffset is enabled',
        PSODesc.Rasterizer.DepthBiasEnable);
      AssertEquals('PolygonOffsetEnable must increment RHIDepthBiasUpdateCount',
        Integer(InitialDepthBiasCount + 1), Integer(TestCtx.RHIDepthBiasUpdateCount));
      RenderContext.PolygonOffsetDisable;

      { Verify rmSolidColor overrides material to unlit WireframeColor and disables textures }
      Scene.RenderOptions.Mode := rmSolidColor;
      Scene.RenderOptions.SolidColor := Scene.RenderOptions.WireframeColor;
      AssertTrue('ExtractRHIMaterialBlock in rmSolidColor must succeed',
        RShape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
      AssertEquals('rmSolidColor must set ShadingModel to smUnlit',
        Ord(smUnlit), Ord(ShadingModel));
      AssertSameValue(1.0, MatBlock.BaseColor.X, 1e-5);
      AssertSameValue(0.25, MatBlock.BaseColor.Y, 1e-5);
      AssertSameValue(0.0, MatBlock.BaseColor.Z, 1e-5);
      AssertEquals('rmSolidColor must return 0 textures',
        0, Integer(RShape.ExtractRHIMaterialTextures(BaseColorTex, NormalTex, MRTex, EmissiveTex, OcclusionTex)));

      { Verify RenderOptions.Lighting = False forces smUnlit while preserving material BaseColor }
      Scene.RenderOptions.Mode := rmFull;
      Scene.RenderOptions.Lighting := False;
      AssertTrue('ExtractRHIMaterialBlock with Lighting = False must succeed',
        RShape.ExtractRHIMaterialBlock(MatBlock, ShadingModel));
      AssertEquals('Lighting = False must force ShadingModel to smUnlit',
        Ord(smUnlit), Ord(ShadingModel));
      AssertTrue('Lighting = False must set SpecularColor.W < 0.0',
        MatBlock.SpecularColor.W < 0.0);
      AssertSameValue(0.2, MatBlock.BaseColor.X, 1e-5);
      AssertSameValue(0.6, MatBlock.BaseColor.Y, 1e-5);
      AssertSameValue(1.0, MatBlock.BaseColor.Z, 1e-5);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureResourceRHISamplerFilterWrapAndAnisotropyRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  RenderOptions: TCastleRenderOptions;
  PixTex: TPixelTextureNode;
  TexProps: TTexturePropertiesNode;
  RtNode: TRenderedTextureNode;
  Tex3D: TPixelTexture3DNode;
  ResImg, ResRt, Res3D: TTextureResource;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7301)));
  SavedRHI := RHIDevice;
  SetRHIDevice(Device);
  RenderOptions := TCastleRenderOptions.Create(nil);
  PixTex := TPixelTextureNode.Create;
  RtNode := TRenderedTextureNode.Create;
  Tex3D := TPixelTexture3DNode.Create;
  try
    PixTex.FdImage.Value := TRGBImage.Create(16, 16);
    TexProps := TTexturePropertiesNode.Create;
    TexProps.MinificationFilter := minNearestMipmapLinear;
    TexProps.MagnificationFilter := magNearest;
    TexProps.BoundaryModeS := bmMirroredRepeat;
    TexProps.BoundaryModeT := bmClampToEdge;
    TexProps.AnisotropicDegree := 8.0;
    PixTex.TextureProperties := TexProps;

    TTextureResources.Prepare(RenderOptions, PixTex);
    ResImg := TTextureResources.Get(PixTex);
    AssertTrue('TImageTextureResource must be prepared', ResImg <> nil);
    AssertTrue('TImageTextureResource.RHISampler must be created', ResImg.RHISampler <> nil);
    AssertEquals('RHISampler.Desc.MinFilter must be sfNearest',
      Ord(sfNearest), Ord(ResImg.RHISampler.Desc.MinFilter));
    AssertEquals('RHISampler.Desc.MagFilter must be sfNearest',
      Ord(sfNearest), Ord(ResImg.RHISampler.Desc.MagFilter));
    AssertEquals('RHISampler.Desc.MipFilter must be sfLinear',
      Ord(sfLinear), Ord(ResImg.RHISampler.Desc.MipFilter));
    AssertEquals('RHISampler.Desc.AddressModeU must be amMirroredRepeat',
      Ord(amMirroredRepeat), Ord(ResImg.RHISampler.Desc.AddressModeU));
    AssertEquals('RHISampler.Desc.AddressModeV must be amClampToEdge',
      Ord(amClampToEdge), Ord(ResImg.RHISampler.Desc.AddressModeV));
    AssertSameValue(8.0, ResImg.RHISampler.Desc.MaxAnisotropy, 1e-5);
    AssertTrue('RHISampler.Desc.MaxLod must be > 0 for 16x16 mipmapped texture',
      ResImg.RHISampler.Desc.MaxLod >= 4.0);

    RtNode.FdDimensions.Items.Clear;
    RtNode.FdDimensions.Items.Add(64);
    RtNode.FdDimensions.Items.Add(64);
    RtNode.FdRepeatS.Value := True;
    RtNode.FdRepeatT.Value := False;
    TTextureResources.Prepare(RenderOptions, RtNode);
    ResRt := TTextureResources.Get(RtNode);
    AssertTrue('TRenderedTextureResource.RHISampler must be created',
      (ResRt <> nil) and (ResRt.RHISampler <> nil));
    AssertEquals('TRenderedTextureResource RepeatS=True must map to amRepeat',
      Ord(amRepeat), Ord(ResRt.RHISampler.Desc.AddressModeU));
    AssertEquals('TRenderedTextureResource RepeatT=False must map to amClampToEdge',
      Ord(amClampToEdge), Ord(ResRt.RHISampler.Desc.AddressModeV));

    Tex3D.FdImage.Items.Clear;
    Tex3D.FdImage.Items.Add(2);
    Tex3D.FdImage.Items.Add(2);
    Tex3D.FdImage.Items.Add(2);
    Tex3D.FdImage.Items.Add(1);
    while Tex3D.FdImage.Items.Count < 4 + 8 do
      Tex3D.FdImage.Items.Add(255);
    Tex3D.FdRepeatS.Value := False;
    Tex3D.FdRepeatT.Value := True;
    Tex3D.FdRepeatR.Value := False;
    TTextureResources.Prepare(RenderOptions, Tex3D);
    Res3D := TTextureResources.Get(Tex3D);
    AssertTrue('T3DTextureResource.RHISampler must be created',
      (Res3D <> nil) and (Res3D.RHISampler <> nil));
    AssertEquals('T3DTextureResource RepeatS=False must map to amClampToEdge',
      Ord(amClampToEdge), Ord(Res3D.RHISampler.Desc.AddressModeU));
    AssertEquals('T3DTextureResource RepeatT=True must map to amRepeat',
      Ord(amRepeat), Ord(Res3D.RHISampler.Desc.AddressModeV));
    AssertEquals('T3DTextureResource RepeatR=False must map to amClampToEdge',
      Ord(amClampToEdge), Ord(Res3D.RHISampler.Desc.AddressModeW));

    TTextureResources.Unprepare(PixTex);
    TTextureResources.Unprepare(RtNode);
    TTextureResources.Unprepare(Tex3D);
  finally
    FreeAndNil(Tex3D);
    FreeAndNil(RtNode);
    FreeAndNil(PixTex);
    FreeAndNil(RenderOptions);
    SetRHIDevice(SavedRHI);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShapeMaterialDescriptorSetBindsRHISamplersRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BaseTex, NormalTex: TPixelTextureNode;
  NormalProps: TTexturePropertiesNode;
  BoxNode: TBoxNode;
  RShape: TX3DRendererShape;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7302)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;

    BaseTex := TPixelTextureNode.Create;
    BaseTex.FdImage.Value := TRGBImage.Create(8, 8);
    BaseTex.RepeatS := True;
    BaseTex.RepeatT := False;
    PhysMat.BaseTexture := BaseTex;

    NormalTex := TPixelTextureNode.Create;
    NormalTex.FdImage.Value := TRGBImage.Create(8, 8);
    NormalProps := TTexturePropertiesNode.Create;
    NormalProps.MinificationFilter := minNearest;
    NormalProps.MagnificationFilter := magNearest;
    NormalProps.BoundaryModeS := bmMirroredRepeat;
    NormalProps.AnisotropicDegree := 4.0;
    NormalTex.TextureProperties := NormalProps;
    PhysMat.NormalTexture := NormalTex;

    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('RShape.Cache must be allocated', RShape.Cache <> nil);
      AssertTrue('RShape.Cache.RHIBaseColorSampler must be bound',
        RShape.Cache.RHIBaseColorSampler <> nil);
      AssertEquals('BaseColorSampler AddressModeU must be amRepeat',
        Ord(amRepeat), Ord(RShape.Cache.RHIBaseColorSampler.Desc.AddressModeU));
      AssertEquals('BaseColorSampler AddressModeV must be amClampToEdge',
        Ord(amClampToEdge), Ord(RShape.Cache.RHIBaseColorSampler.Desc.AddressModeV));

      AssertTrue('RShape.Cache.RHINormalSampler must be bound',
        RShape.Cache.RHINormalSampler <> nil);
      AssertEquals('NormalSampler MinFilter must be sfNearest',
        Ord(sfNearest), Ord(RShape.Cache.RHINormalSampler.Desc.MinFilter));
      AssertEquals('NormalSampler AddressModeU must be amMirroredRepeat',
        Ord(amMirroredRepeat), Ord(RShape.Cache.RHINormalSampler.Desc.AddressModeU));
      AssertSameValue(4.0, RShape.Cache.RHINormalSampler.Desc.MaxAnisotropy, 1e-5);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureTransformAndImageTransformRepeatShiftSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  ImgTransform: TCastleImageTransform;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BaseTex: TPixelTextureNode;
  TexTransform: TTextureTransformNode;
  BoxNode: TBoxNode;
  RShape: TX3DRendererShape;
  ExtractedMat: TMatrix4;
  ShadingModel: TCastleShadingModelRHI;
  OldVertSource: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7303)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    BaseTex := TPixelTextureNode.Create;
    BaseTex.FdImage.Value := TRGBImage.Create(8, 8);
    PhysMat.BaseTexture := BaseTex;
    App.Material := PhysMat;

    TexTransform := TTextureTransformNode.Create;
    TexTransform.Scale := Vector2(3.0, 2.0);
    TexTransform.Translation := Vector2(0.25, 0.5);
    App.TextureTransform := TexTransform;

    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    ImgTransform := TCastleImageTransform.Create(Viewport);
    ImgTransform.LoadFromImage(TRGBAlphaImage.Create(8, 8), True);
    ImgTransform.SmoothScaling := False;
    ImgTransform.RepeatImage := Vector2(4.0, 4.0);
    Viewport.Items.Add(ImgTransform);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ExtractRHITextureTransform must return True for non-identity TextureTransform',
        RShape.ExtractRHITextureTransform(ExtractedMat));
      AssertTrue('RShape.Cache.RHIHasTextureTransform must be True',
        (RShape.Cache <> nil) and RShape.Cache.RHIHasTextureTransform);
      AssertTrue('Permutation mask must include $200 (AHasTextureTransform)',
        (RShape.Cache.RHIShaderPermutationMask and $200) <> 0);
      AssertTrue('Vertex shader source must transform castle_MultiTexCoord0 by mat4',
        Pos('* vec4(castle_MultiTexCoord0, 0.0, 1.0)).xy;', RShape.Cache.RHIVertexShaderSource) > 0);

      { Updating TexTransform.Scale at runtime must re-specialize the vertex shader }
      OldVertSource := RShape.Cache.RHIVertexShaderSource;
      TexTransform.Scale := Vector2(7.0, 9.0);
      RShape.UploadRHIMaterialToCache(ShadingModel);
      AssertTrue('Updated TexTransform.Scale must update RHIVertexShaderSource',
        RShape.Cache.RHIVertexShaderSource <> OldVertSource);
      AssertTrue('Updated RHIVertexShaderSource must contain new scale factor 7',
        Pos('vec4(7,', RShape.Cache.RHIVertexShaderSource) > 0);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestClipPlaneNodeSlicingAndDiscardSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  TransNode: TTransformNode;
  ClipNode: TClipPlaneNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BoxNode: TBoxNode;
  RShape: TX3DRendererShape;
  ExtractedPlane: TVector4;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7401)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    TransNode := TTransformNode.Create;
    TransNode.Translation := Vector3(0.0, 2.0, 0.0);

    ClipNode := TClipPlaneNode.Create;
    ClipNode.Enabled := True;
    ClipNode.Plane := Vector4(0.0, 1.0, 0.0, -0.5);
    TransNode.AddChildren(ClipNode);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    TransNode.AddChildren(ShapeNode);
    Root.AddChildren(TransNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ExtractRHIClipPlane must return True when ClipPlane.Enabled = True',
        RShape.ExtractRHIClipPlane(ExtractedPlane));
      { Plane (0, 1, 0, -0.5) translated by (0, +2, 0) becomes y - 2.5 >= 0 -> (0, 1, 0, -2.5) }
      AssertSameValue(0.0, ExtractedPlane.X, 1e-4);
      AssertSameValue(1.0, ExtractedPlane.Y, 1e-4);
      AssertSameValue(0.0, ExtractedPlane.Z, 1e-4);
      AssertSameValue(-2.5, ExtractedPlane.W, 1e-4);

      AssertTrue('RShape.Cache.RHIHasClipPlane must be True',
        (RShape.Cache <> nil) and RShape.Cache.RHIHasClipPlane);
      AssertTrue('Permutation mask must include $400 (AHasClipPlane)',
        (RShape.Cache.RHIShaderPermutationMask and $400) <> 0);
      AssertTrue('Fragment shader source must contain clip plane discard check',
        Pos('castle_ViewMatrixInverse * vec4(castle_vertex_eye.xyz, 1.0)) < 0.0) discard;',
          RShape.Cache.RHIFragmentShaderSource) > 0);

      { Disabling ClipNode must clear bit $400 upon material re-upload }
      ClipNode.Enabled := False;
      RShape.UploadRHIMaterialToCache(ShadingModel);
      AssertFalse('RShape.Cache.RHIHasClipPlane must be False when ClipPlane.Enabled = False',
        RShape.Cache.RHIHasClipPlane);
      AssertEquals('Permutation mask $400 must be cleared when ClipPlane is disabled',
        Cardinal(0), RShape.Cache.RHIShaderPermutationMask and $400);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestEnvironmentLightIBLCubemapAndBrdfLutSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  EnvLight: TEnvironmentLightNode;
  CubeMap: TComposedCubeMapTextureNode;
  FaceTex: TPixelTextureNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BoxNode: TBoxNode;
  RShape: TX3DRendererShape;
  ExtractedEnvTex: TRHITexture;
  ExtractedEnvSampler: TRHISampler;
  Side: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7402)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    EnvLight := TEnvironmentLightNode.Create;
    EnvLight.Global := True;
    EnvLight.IsOn := True;

    CubeMap := TComposedCubeMapTextureNode.Create;
    for Side := 0 to 5 do
    begin
      FaceTex := TPixelTextureNode.Create;
      FaceTex.FdImage.Value := TRGBImage.Create(8, 8);
      case Side of
        0: CubeMap.Back := FaceTex;
        1: CubeMap.Front := FaceTex;
        2: CubeMap.Bottom := FaceTex;
        3: CubeMap.Top := FaceTex;
        4: CubeMap.Left := FaceTex;
        5: CubeMap.Right := FaceTex;
      end;
    end;
    EnvLight.SpecularTexture := CubeMap;
    Root.AddChildren(EnvLight);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.Metallic := 0.8;
    PhysMat.Roughness := 0.2;
    App.Material := PhysMat;
    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ExtractRHIEnvironmentLightTexture must resolve TEnvironmentLightNode SpecularTexture cubemap',
        RShape.ExtractRHIEnvironmentLightTexture(ExtractedEnvTex, ExtractedEnvSampler));
      AssertTrue('ExtractedEnvTex must be non-nil', ExtractedEnvTex <> nil);
      AssertTrue('ExtractedEnvSampler must be non-nil', ExtractedEnvSampler <> nil);
      AssertEquals('ExtractedEnvTex dimension must be tdCube',
        Ord(tdCube), Ord(ExtractedEnvTex.Desc.Dimension));

      AssertTrue('RShape.Cache.RHIEnvSpecularTexture must be bound to Set 1 Binding 7',
        (RShape.Cache <> nil) and (RShape.Cache.RHIEnvSpecularTexture = ExtractedEnvTex));
      AssertTrue('RShape.Cache.RHIBrdfLutTexture must be auto-created and bound to Set 1 Binding 6',
        RShape.Cache.RHIBrdfLutTexture <> nil);
      AssertTrue('Permutation mask must include $800 (AHasIBL)',
        (RShape.Cache.RHIShaderPermutationMask and $800) <> 0);
      AssertTrue('Fragment shader source must call EvaluateIBLCookTorranceGGX',
        Pos('EvaluateIBLCookTorranceGGX(', RShape.Cache.RHIFragmentShaderSource) > 0);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShadowMapReceiverProjectorMatrixAndSceneDescriptorBindingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx, TestCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SpotLight: TSpotLightNode;
  ReceiverShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  BoxNode: TBoxNode;
  RShape: TX3DRendererShape;
  ExtractedShadowTex: TRHITexture;
  ExtractedShadowSampler: TRHISampler;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7403)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    SpotLight := TSpotLightNode.Create;
    SpotLight.Location := Vector3(0.0, 5.0, 5.0);
    SpotLight.Direction := Vector3(0.0, -1.0, -1.0);
    SpotLight.Shadows := True;
    Root.AddChildren(SpotLight);

    ReceiverShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    App.Material := PhysMat;
    ReceiverShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ReceiverShapeNode.Geometry := BoxNode;
    Root.AddChildren(ReceiverShapeNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ProcessShadowMapsReceivers must populate RShape.InternalShadowMaps',
        (RShape.InternalShadowMaps <> nil) and (RShape.InternalShadowMaps.Count > 0));
      AssertTrue('ExtractRHIShadowMap must resolve TGeneratedShadowMapResource texture and comparison sampler',
        RShape.ExtractRHIShadowMap(ExtractedShadowTex, ExtractedShadowSampler));
      AssertTrue('ExtractedShadowTex must be non-nil', ExtractedShadowTex <> nil);
      AssertTrue('ExtractedShadowSampler must be non-nil and have CompareEnable = True',
        (ExtractedShadowSampler <> nil) and ExtractedShadowSampler.Desc.CompareEnable);
      AssertTrue('Permutation mask must include $1000 (AHasShadowMap)',
        (RShape.Cache <> nil) and ((RShape.Cache.RHIShaderPermutationMask and $1000) <> 0));
      AssertTrue('Fragment shader source must sample castle_shadow_map_0 using light.ProjectorMatrix',
        (Pos('light.ProjectorMatrix * vec4(castle_vertex_eye.xyz, 1.0)', RShape.Cache.RHIFragmentShaderSource) > 0) and
        (Pos('texture(castle_shadow_map_0, vec3(shadowProj.xy', RShape.Cache.RHIFragmentShaderSource) > 0));
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTextureCoordinateGeneratorAndBounds2DSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeBounds, ShapeSphere: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1, Mat2: TPhysicalMaterialNode;
  PixTex1, PixTex2: TPixelTextureNode;
  TexTransform: TTextureTransformNode;
  IFS1, IFS2: TIndexedFaceSetNode;
  Coord1, Coord2: TCoordinateNode;
  TexGen: TTextureCoordinateGeneratorNode;
  RShape1, RShape2: TX3DRendererShape;
  ExtractedGen: TTextureCoordinateGeneration;
  BoundsS, BoundsT: TVector4;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7501)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;

    { Shape 1: IndexedFaceSet with texture and NO explicit TexCoord -> implicit tgBounds2d }
    ShapeBounds := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TPhysicalMaterialNode.Create;
    PixTex1 := TPixelTextureNode.Create;
    PixTex1.FdImage.Value := TRGBImage.Create(2, 2);
    App1.Texture := PixTex1;
    App1.Material := Mat1;
    ShapeBounds.Appearance := App1;
    IFS1 := TIndexedFaceSetNode.Create;
    Coord1 := TCoordinateNode.Create;
    Coord1.SetPoint([
      Vector3(-1.0, -1.0, 0.0),
      Vector3( 1.0, -1.0, 0.0),
      Vector3( 1.0,  1.0, 0.0),
      Vector3(-1.0,  1.0, 0.0)]);
    IFS1.Coord := Coord1;
    IFS1.SetCoordIndex([0, 1, 2, 0, 2, 3]);
    ShapeBounds.Geometry := IFS1;
    Root.AddChildren(ShapeBounds);

    { Shape 2: IndexedFaceSet with TTextureCoordinateGeneratorNode(SPHERE) + TTextureTransformNode }
    ShapeSphere := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Mat2 := TPhysicalMaterialNode.Create;
    PixTex2 := TPixelTextureNode.Create;
    PixTex2.FdImage.Value := TRGBImage.Create(2, 2);
    App2.Texture := PixTex2;
    App2.Material := Mat2;
    TexTransform := TTextureTransformNode.Create;
    TexTransform.Scale := Vector2(2.0, 3.0);
    App2.TextureTransform := TexTransform;
    ShapeSphere.Appearance := App2;
    IFS2 := TIndexedFaceSetNode.Create;
    Coord2 := TCoordinateNode.Create;
    Coord2.SetPoint([
      Vector3(-1.0, -1.0, -1.0),
      Vector3( 1.0, -1.0, -1.0),
      Vector3( 0.0,  1.0, -1.0)]);
    IFS2.Coord := Coord2;
    TexGen := TTextureCoordinateGeneratorNode.Create;
    TexGen.FdMode.Value := 'SPHERE';
    IFS2.TexCoord := TexGen;
    IFS2.SetCoordIndex([0, 1, 2]);
    ShapeSphere.Geometry := IFS2;
    Root.AddChildren(ShapeSphere);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape1 := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      RShape2 := TX3DRendererShape(Scene.Shapes.TraverseList(True)[1]);

      AssertTrue('Shape 1 ExtractRHITexCoordGen must return True (tgBounds2d)',
        RShape1.ExtractRHITexCoordGen(ExtractedGen, BoundsS, BoundsT));
      AssertTrue('Shape 1 generation mode must be tgBounds2d', ExtractedGen = tgBounds2d);
      AssertTrue('Shape 1 permutation mask must include $2000 (AHasTexCoordGen)',
        (RShape1.Cache <> nil) and ((RShape1.Cache.RHIShaderPermutationMask and $2000) <> 0));
      AssertTrue('Shape 1 vertex shader must compute object-linear bounds dot products',
        Pos('vec2 rawTexCoord0 = vec2(dot(localPos, vec4(', RShape1.Cache.RHIVertexShaderSource) > 0);

      AssertTrue('Shape 2 ExtractRHITexCoordGen must return True (tgSphereMap)',
        RShape2.ExtractRHITexCoordGen(ExtractedGen, BoundsS, BoundsT));
      AssertTrue('Shape 2 generation mode must be tgSphereMap', ExtractedGen = tgSphereMap);
      AssertTrue('Shape 2 permutation mask must include both $2000 (TexCoordGen) and $200 (TextureTransform)',
        (RShape2.Cache <> nil) and ((RShape2.Cache.RHIShaderPermutationMask and $2200) = $2200));
      AssertTrue('Shape 2 vertex shader must compute sphere reflection rawTexCoord0 and multiply by TextureTransform matrix',
        (Pos('vec3 rSphere = reflect(normalize(castle_vertex_eye.xyz), castle_normal_eye);', RShape2.Cache.RHIVertexShaderSource) > 0) and
        (Pos('* vec4(rawTexCoord0, 0.0, 1.0)).xy;', RShape2.Cache.RHIVertexShaderSource) > 0));
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestEffectNodePlugFunctionsAndPointPropertiesSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  PP: TPointPropertiesNode;
  Effect: TEffectNode;
  VertPart, FragPart: TEffectPartNode;
  BoxNode: TBoxNode;
  RShape: TX3DRendererShape;
  ExtractedPointSize: Single;
  VertCode, FragCode: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7502)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    App.Material := PhysMat;

    PP := TPointPropertiesNode.Create;
    PP.PointSizeScaleFactor := 4.5;
    PP.PointSizeMinValue := 1.0;
    PP.PointSizeMaxValue := 8.0;
    App.PointProperties := PP;

    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;
    Effect.Enabled := True;
    VertPart := TEffectPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.Contents := 'void PLUG_vertex_eye_space(inout vec4 vertex_eye, inout vec3 normal_eye) { vertex_eye.y += 0.25; }';
    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents := 'void PLUG_fragment_modify(inout vec4 fragment_color) { fragment_color.rgb *= vec3(0.5, 1.0, 0.5); }';
    Effect.SetParts([VertPart, FragPart]);
    App.SetEffects([Effect]);

    ShapeNode.Appearance := App;
    BoxNode := TBoxNode.Create;
    ShapeNode.Geometry := BoxNode;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ExtractRHIPointSize must return True for PointSizeScaleFactor = 4.5',
        RShape.ExtractRHIPointSize(ExtractedPointSize));
      AssertSameValue(4.5, ExtractedPointSize, 1e-4);
      AssertTrue('ExtractRHIShaderEffects must extract both vertex and fragment EffectParts',
        RShape.ExtractRHIShaderEffects(VertCode, FragCode));
      AssertTrue('Permutation mask must include $4000 (AHasShaderEffects / PointSize)',
        (RShape.Cache <> nil) and ((RShape.Cache.RHIShaderPermutationMask and $4000) <> 0));
      AssertTrue('Vertex shader source must invoke PLUG_vertex_eye_space and set gl_PointSize = 4.5',
        (Pos('PLUG_vertex_eye_space(castle_vertex_eye, castle_normal_eye);', RShape.Cache.RHIVertexShaderSource) > 0) and
        (Pos('gl_PointSize = 4.5;', RShape.Cache.RHIVertexShaderSource) > 0));
      AssertTrue('Fragment shader source must invoke PLUG_fragment_modify(castle_FragColor)',
        Pos('PLUG_fragment_modify(castle_FragColor);', RShape.Cache.RHIFragmentShaderSource) > 0);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestViewportUpdateGeneratedTexturesOffscreenSceneRenderRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SpotLight: TSpotLightNode;
  ShadowMapNode: TGeneratedShadowMapNode;
  RenderedTexNode: TRenderedTextureNode;
  CubeMapTexNode: TGeneratedCubeMapTextureNode;
  Shape1, Shape2: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1, Mat2: TPhysicalMaterialNode;
  Box1, Box2: TBoxNode;
  ShadowRes: TGeneratedShadowMapResource;
  RenderedRes: TRenderedTextureResource;
  CubeRes: TGeneratedCubeMapTextureResource;
  HandleInput: Boolean;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7503)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    SpotLight := TSpotLightNode.Create;
    SpotLight.Location := Vector3(0.0, 5.0, 5.0);
    SpotLight.Direction := Vector3(0.0, -1.0, -1.0);
    SpotLight.Shadows := True;
    ShadowMapNode := TGeneratedShadowMapNode.Create;
    ShadowMapNode.Update := upAlways;
    ShadowMapNode.Size := 64;
    ShadowMapNode.FdLight.Value := SpotLight;
    SpotLight.FdDefaultShadowMap.Value := ShadowMapNode;
    Root.AddChildren(SpotLight);

    Shape1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TPhysicalMaterialNode.Create;
    RenderedTexNode := TRenderedTextureNode.Create;
    RenderedTexNode.Update := upAlways;
    RenderedTexNode.SetDimensions([64, 64, 4, 1, 1]);
    App1.Texture := RenderedTexNode;
    App1.Material := Mat1;
    Shape1.Appearance := App1;
    Box1 := TBoxNode.Create;
    Shape1.Geometry := Box1;
    Root.AddChildren(Shape1);

    Shape2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Mat2 := TPhysicalMaterialNode.Create;
    CubeMapTexNode := TGeneratedCubeMapTextureNode.Create;
    CubeMapTexNode.Update := upAlways;
    CubeMapTexNode.Size := 32;
    App2.Texture := CubeMapTexNode;
    App2.Material := Mat2;
    Shape2.Appearance := App2;
    Box2 := TBoxNode.Create;
    Shape2.Geometry := Box2;
    Root.AddChildren(Shape2);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      { Trigger full Viewport.Update -> Scene.Update -> UpdateGeneratedTextures
        which executes offscreen scene rendering into TGeneratedShadowMapNode,
        TRenderedTextureNode, and TGeneratedCubeMapTextureNode via
        World.InternalRenderEverythingEvent in pure Vulkan RHI mode }
      HandleInput := True;
      Viewport.Update(0.016, HandleInput);

      ShadowRes := TGeneratedShadowMapResource(TTextureResources.Get(ShadowMapNode));
      RenderedRes := TRenderedTextureResource(TTextureResources.Get(RenderedTexNode));
      CubeRes := TGeneratedCubeMapTextureResource(TTextureResources.Get(CubeMapTexNode));
      AssertTrue('On-demand Prepare in UpdateOneGeneratedTexture must create ShadowRes',
        (ShadowRes <> nil) and (ShadowRes.RHITexture <> nil));
      AssertEquals('ShadowRes.RHIUpdateCount must be 1 after Viewport.Update',
        Cardinal(1), ShadowRes.RHIUpdateCount);
      AssertTrue('On-demand Prepare in UpdateOneGeneratedTexture must create RenderedRes',
        (RenderedRes <> nil) and (RenderedRes.RHITexture <> nil));
      AssertEquals('RenderedRes.RHIUpdateCount must be 1 after Viewport.Update',
        Cardinal(1), RenderedRes.RHIUpdateCount);
      AssertTrue('On-demand Prepare in UpdateOneGeneratedTexture must create CubeRes',
        (CubeRes <> nil) and (CubeRes.RHITexture <> nil));
      AssertEquals('CubeRes.RHIUpdateCount must be 1 after Viewport.Update',
        Cardinal(1), CubeRes.RHIUpdateCount);

      { Also verify full Container.EventBeforeRender + EventRender renders shapes into viewport }
      Container.EventBeforeRender;
      Container.EventRender;
      AssertTrue('Command list must bind graphics pipelines for offscreen and main passes',
        CmdList.PipelineBindCount >= 8);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestComposedShaderNodeFullCustomShaderAndLegacyUpgradeRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedCtx: TRenderContext;
  SavedBackend: TRenderBackend;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  ComposedShader: TComposedShaderNode;
  VertPart, FragPart: TShaderPartNode;
  RShape: TX3DRendererShape;
  CustomVert, CustomFrag: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7601)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedCtx := RenderContext;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;

    ComposedShader := TComposedShaderNode.Create;
    ComposedShader.Language := slGLSL;

    VertPart := TShaderPartNode.Create;
    VertPart.ShaderType := stVertex;
    VertPart.SetUrl(['data:text/plain,' +
      'void main(void) {' + LineEnding +
      '  gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;' + LineEnding +
      '}']);

    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.SetUrl(['data:text/plain,' +
      'uniform float myCustomGain;' + LineEnding +
      'void main(void) {' + LineEnding +
      '  gl_FragColor = vec4(myCustomGain, 0.5, 1.0, 1.0);' + LineEnding +
      '}']);

    ComposedShader.FdParts.Add(VertPart);
    ComposedShader.FdParts.Add(FragPart);
    App.FdShaders.Add(ComposedShader);

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      AssertTrue('ExtractRHIComposedShader must return True for valid TComposedShaderNode',
        RShape.ExtractRHIComposedShader(CustomVert, CustomFrag));
      AssertTrue('RHIShaderPermutationMask must include ComposedShader bit ($8000)',
        (RShape.Cache.RHIShaderPermutationMask and $8000) <> 0);
      AssertTrue('RHIVertexShaderSource must contain legacy gl_ModelViewProjectionMatrix upgrade',
        Pos('#define gl_ModelViewProjectionMatrix', RShape.Cache.RHIVertexShaderSource) > 0);
      AssertTrue('RHIVertexShaderSource must contain Vulkan half-Z post-processing',
        Pos('gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;', RShape.Cache.RHIVertexShaderSource) > 0);
      AssertTrue('RHIFragmentShaderSource must upgrade custom uniform into CastleUserEffectBlock UBO',
        Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock',
          RShape.Cache.RHIFragmentShaderSource) > 0);
      AssertTrue('RHIFragmentShaderSource must contain legacy gl_FragColor upgrade',
        Pos('#define gl_FragColor castle_FragColor', RShape.Cache.RHIFragmentShaderSource) > 0);
      AssertTrue('RHIVertexShader and RHIFragmentShader must be compiled',
        (RShape.Cache.RHIVertexShader <> nil) and (RShape.Cache.RHIFragmentShader <> nil));
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    SetActiveCommandList(SavedCmd);
    RenderContext := SavedCtx;
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(TestCtx);
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestPhongMaterialOcclusionSpecularPureEmissiveAndCommonSurfaceShaderRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene1, Scene2, Scene3: TCastleScene;
  Root1, Root2, Root3: TX3DRootNode;
  Shape1, Shape2, Shape3: TShapeNode;
  App1, App2, App3: TAppearanceNode;
  PhongMat, PureEmissiveMat: TMaterialNode;
  CommonSurf: TCommonSurfaceShaderNode;
  OccTex, SpecTex, DiffTex, NormTex: TPixelTextureNode;
  Box1, Box2, Box3: TBoxNode;
  RShape1, RShape2, RShape3: TX3DRendererShape;
  MatBlock: TCastleMaterialUniformBlock;
  ShadingModel: TCastleShadingModelRHI;
  BaseTex, NormalTexOut, MetRoughTex, EmissiveTex, OcclusionTexOut: TRHITexture;
  BaseSamp, NormalSamp, MetRoughSamp, EmissiveSamp, OcclusionSamp: TRHISampler;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7602)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene1 := TCastleScene.Create(nil);
  Scene2 := TCastleScene.Create(nil);
  Scene3 := TCastleScene.Create(nil);
  try
    { 1. TMaterialNode with OcclusionTexture + OcclusionStrength + SpecularTexture }
    Root1 := TX3DRootNode.Create;
    Shape1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    PhongMat := TMaterialNode.Create;
    PhongMat.DiffuseColor := Vector3(0.7, 0.3, 0.2);
    PhongMat.SpecularColor := Vector3(0.9, 0.9, 0.9);
    PhongMat.OcclusionStrength := 0.65;
    OccTex := TPixelTextureNode.Create;
    OccTex.FdImage.Value := TRGBImage.Create(2, 2);
    PhongMat.OcclusionTexture := OccTex;
    SpecTex := TPixelTextureNode.Create;
    SpecTex.FdImage.Value := TRGBImage.Create(2, 2);
    PhongMat.SpecularTexture := SpecTex;
    App1.Material := PhongMat;
    Shape1.Appearance := App1;
    Box1 := TBoxNode.Create;
    Shape1.Geometry := Box1;
    Root1.AddChildren(Shape1);
    Scene1.Load(Root1, True);

    RShape1 := TX3DRendererShape(Scene1.Shapes.TraverseList(True)[0]);
    RShape1.ExtractRHIMaterialBlock(MatBlock, ShadingModel);
    AssertEquals('Phong material must use smPhong', Ord(smPhong), Ord(ShadingModel));
    AssertSameValue(0.65, MatBlock.PBRParams.Z, 0.001);
    RShape1.ExtractRHIMaterialTextures(BaseTex, NormalTexOut, MetRoughTex, EmissiveTex, OcclusionTexOut,
      BaseSamp, NormalSamp, MetRoughSamp, EmissiveSamp, OcclusionSamp);
    AssertTrue('PhongMat.OcclusionTexture must resolve OcclusionTexOut', OcclusionTexOut <> nil);
    AssertTrue('PhongMat.SpecularTexture must resolve MetRoughTex', MetRoughTex <> nil);

    { 2. PureEmissive TMaterialNode -> smUnlit optimization }
    Root2 := TX3DRootNode.Create;
    Shape2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    PureEmissiveMat := TMaterialNode.Create;
    PureEmissiveMat.DiffuseColor := TVector3.Zero;
    PureEmissiveMat.SpecularColor := TVector3.Zero;
    PureEmissiveMat.AmbientIntensity := 0.0;
    PureEmissiveMat.EmissiveColor := Vector3(0.2, 0.8, 0.4);
    App2.Material := PureEmissiveMat;
    Shape2.Appearance := App2;
    Box2 := TBoxNode.Create;
    Shape2.Geometry := Box2;
    Root2.AddChildren(Shape2);
    Scene2.Load(Root2, True);

    RShape2 := TX3DRendererShape(Scene2.Shapes.TraverseList(True)[0]);
    RShape2.ExtractRHIMaterialBlock(MatBlock, ShadingModel);
    AssertEquals('PureEmissive TMaterialNode must optimize to smUnlit', Ord(smUnlit), Ord(ShadingModel));
    AssertSameValue(0.2, MatBlock.BaseColor.X, 0.001);
    AssertSameValue(0.8, MatBlock.BaseColor.Y, 0.001);
    AssertSameValue(0.4, MatBlock.BaseColor.Z, 0.001);
    AssertSameValue(-1.0, MatBlock.SpecularColor.W, 0.001);

    { 3. TCommonSurfaceShaderNode material & texture extraction }
    Root3 := TX3DRootNode.Create;
    Shape3 := TShapeNode.Create;
    App3 := TAppearanceNode.Create;
    CommonSurf := TCommonSurfaceShaderNode.Create;
    CommonSurf.DiffuseFactor := Vector3(0.4, 0.5, 0.6);
    CommonSurf.AlphaFactor := 0.85;
    CommonSurf.SpecularFactor := Vector3(0.3, 0.3, 0.3);
    CommonSurf.ShininessFactor := 0.5;
    CommonSurf.EmissiveFactor := Vector3(0.1, 0.2, 0.3);
    DiffTex := TPixelTextureNode.Create;
    DiffTex.FdImage.Value := TRGBImage.Create(2, 2);
    CommonSurf.DiffuseTexture := DiffTex;
    NormTex := TPixelTextureNode.Create;
    NormTex.FdImage.Value := TRGBImage.Create(2, 2);
    CommonSurf.NormalTexture := NormTex;
    App3.FdShaders.Add(CommonSurf);
    Shape3.Appearance := App3;
    Box3 := TBoxNode.Create;
    Shape3.Geometry := Box3;
    Root3.AddChildren(Shape3);
    Scene3.Load(Root3, True);

    RShape3 := TX3DRendererShape(Scene3.Shapes.TraverseList(True)[0]);
    RShape3.ExtractRHIMaterialBlock(MatBlock, ShadingModel);
    AssertEquals('TCommonSurfaceShaderNode must extract as smPhong', Ord(smPhong), Ord(ShadingModel));
    AssertSameValue(0.4, MatBlock.BaseColor.X, 0.001);
    AssertSameValue(0.85, MatBlock.BaseColor.W, 0.001);
    AssertSameValue(64.0, MatBlock.SpecularColor.W, 0.01);
    RShape3.ExtractRHIMaterialTextures(BaseTex, NormalTexOut, MetRoughTex, EmissiveTex, OcclusionTexOut,
      BaseSamp, NormalSamp, MetRoughSamp, EmissiveSamp, OcclusionSamp);
    AssertTrue('CommonSurfaceShader.DiffuseTexture must resolve BaseTex', BaseTex <> nil);
    AssertTrue('CommonSurfaceShader.NormalTexture must resolve NormalTexOut', NormalTexOut <> nil);

    TTextureResources.Unprepare(OccTex);
    TTextureResources.Unprepare(SpecTex);
    TTextureResources.Unprepare(DiffTex);
    TTextureResources.Unprepare(NormTex);
  finally
    FreeAndNil(Scene3);
    FreeAndNil(Scene2);
    FreeAndNil(Scene1);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTwoSidedGeometryFrontFacingNormalFlipAndNegativeScaleWindingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  Viewport: TCastleViewport;
  Scene1, Scene2: TCastleScene;
  Root1, Root2: TX3DRootNode;
  Shape1, Shape2: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1, Mat2: TPhysicalMaterialNode;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  NegTransform: TTransformNode;
  Box2: TBoxNode;
  RShape1, RShape2: TX3DRendererShape;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Desc1, Desc2: TRHIGraphicsPipelineDesc;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7603)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Viewport := TCastleViewport.Create(nil);
  Scene1 := TCastleScene.Create(nil);
  Scene2 := TCastleScene.Create(nil);
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    { 1. Two-sided IndexedFaceSet (Solid := False) }
    Root1 := TX3DRootNode.Create;
    Shape1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TPhysicalMaterialNode.Create;
    App1.Material := Mat1;
    Shape1.Appearance := App1;
    IFS := TIndexedFaceSetNode.Create;
    IFS.Solid := False;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, -1, 0),
      Vector3( 1, -1, 0),
      Vector3( 0,  1, 0)]);
    IFS.Coord := Coord;
    IFS.SetCoordIndex([0, 1, 2, -1]);
    Shape1.Geometry := IFS;
    Root1.AddChildren(Shape1);
    Scene1.Load(Root1, True);
    Viewport.Items.Add(Scene1);

    { 2. Solid Box under negative X scale (Determinant < 0) }
    Root2 := TX3DRootNode.Create;
    NegTransform := TTransformNode.Create;
    NegTransform.Scale := Vector3(-1.0, 1.0, 1.0);
    Shape2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Mat2 := TPhysicalMaterialNode.Create;
    App2.Material := Mat2;
    Shape2.Appearance := App2;
    Box2 := TBoxNode.Create;
    Shape2.Geometry := Box2;
    NegTransform.AddChildren(Shape2);
    Root2.AddChildren(NegTransform);
    Scene2.Load(Root2, True);
    Scene2.RenderOptions.RobustNegativeScale := True;
    Viewport.Items.Add(Scene2);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      RShape1 := TX3DRendererShape(Scene1.Shapes.TraverseList(True)[0]);
      RShape1.PrepareRHIBuffers(Scene1.RenderOptions, 1);
      RShape1.UploadRHIMaterialToCache(ShadingModel);

      RShape2 := TX3DRendererShape(Scene2.Shapes.TraverseList(True)[0]);
      RShape2.PrepareRHIBuffers(Scene2.RenderOptions, 1);
      RShape2.UploadRHIMaterialToCache(ShadingModel);

      Cam.Target := rtScreen;
      Cam.Matrix := TMatrix4.Identity;
      FillChar(Stats, SizeOf(Stats), 0);
      Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
      try
        Renderer.BuildShapePipelineDesc(RShape1, Scene1.RenderOptions, Desc1);
        AssertEquals('Two-sided shape (Solid=False) must have CullMode = cmNone',
          Ord(cmNone), Ord(Desc1.Rasterizer.CullMode));
        AssertTrue('Two-sided shape fragment shader must flip back-face normals using gl_FrontFacing',
          Pos('gl_FrontFacing ? 1.0 : -1.0', RShape1.Cache.RHIFragmentShaderSource) > 0);

        Renderer.BuildShapePipelineDesc(RShape2, Scene2.RenderOptions, Desc2);
        AssertEquals('Solid shape must have CullMode = cmBack',
          Ord(cmBack), Ord(Desc2.Rasterizer.CullMode));
        AssertEquals('Negatively scaled shape with RobustNegativeScale=True must flip FrontFace to ffClockwise',
          Ord(ffClockwise), Ord(Desc2.Rasterizer.FrontFace));
      finally
        Renderer.RenderEnd;
      end;
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Scene2);
    FreeAndNil(Scene1);
    FreeAndNil(Viewport);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestEffectAndComposedShaderCustomUniformUBOAndTextureBindingRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  Scene1, Scene2: TCastleScene;
  Root1, Root2: TX3DRootNode;
  Shape1, Shape2: TShapeNode;
  App1, App2: TAppearanceNode;
  Mat1: TPhysicalMaterialNode;
  Box1, Box2: TBoxNode;
  Effect1: TEffectNode;
  FragPart1: TEffectPartNode;
  CustomTex1: TPixelTextureNode;
  Composed2: TComposedShaderNode;
  VertPart2, FragPart2: TShaderPartNode;
  RShape1, RShape2: TX3DRendererShape;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Desc1, Desc2: TRHIGraphicsPipelineDesc;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7701)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene1 := TCastleScene.Create(nil);
  Scene2 := TCastleScene.Create(nil);
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    { 1. TEffectNode with custom float, vec3, and texture node fields }
    Root1 := TX3DRootNode.Create;
    Shape1 := TShapeNode.Create;
    App1 := TAppearanceNode.Create;
    Mat1 := TPhysicalMaterialNode.Create;
    App1.Material := Mat1;

    CustomTex1 := TPixelTextureNode.Create;
    CustomTex1.FdImage.Value := TRGBAlphaImage.Create(4, 4);
    TTextureResources.Prepare(Scene1.RenderOptions, CustomTex1);

    Effect1 := TEffectNode.Create;
    Effect1.Language := slGLSL;
    Effect1.Enabled := True;
    Effect1.AddCustomField(TSFFloat.Create(Effect1, True, 'uGain', 2.5));
    Effect1.AddCustomField(TSFVec3f.Create(Effect1, True, 'uTint', Vector3(0.2, 0.4, 0.8)));
    Effect1.AddCustomField(TSFNode.Create(Effect1, True, 'uNoiseTex', [TAbstractTextureNode], CustomTex1));

    FragPart1 := TEffectPartNode.Create;
    FragPart1.ShaderType := stFragment;
    FragPart1.Contents :=
      'uniform float uGain;' + LineEnding +
      'uniform vec3 uTint;' + LineEnding +
      'uniform sampler2D uNoiseTex;' + LineEnding +
      'void PLUG_fragment_modify(inout vec4 fragment_color)' + LineEnding +
      '{' + LineEnding +
      '  vec4 n = texture2D(uNoiseTex, vec2(0.5, 0.5));' + LineEnding +
      '  fragment_color.rgb = fragment_color.rgb * uTint * uGain + n.rgb * 0.01;' + LineEnding +
      '}';
    Effect1.SetParts([FragPart1]);
    App1.SetEffects([Effect1]);
    Shape1.Appearance := App1;
    Box1 := TBoxNode.Create;
    Shape1.Geometry := Box1;
    Root1.AddChildren(Shape1);
    Scene1.Load(Root1, True);

    { 2. TComposedShaderNode with custom float and vec4 fields }
    Root2 := TX3DRootNode.Create;
    Shape2 := TShapeNode.Create;
    App2 := TAppearanceNode.Create;
    Composed2 := TComposedShaderNode.Create;
    Composed2.Language := slGLSL;
    Composed2.AddCustomField(TSFFloat.Create(Composed2, True, 'uWaveScale', 1.75));
    Composed2.AddCustomField(TSFVec4f.Create(Composed2, True, 'uCustomColor', Vector4(0.9, 0.1, 0.3, 1.0)));

    VertPart2 := TShaderPartNode.Create;
    VertPart2.ShaderType := stVertex;
    VertPart2.Contents :=
      'uniform mat4 castle_ModelViewMatrix;' + LineEnding +
      'uniform mat4 castle_ProjectionMatrix;' + LineEnding +
      'attribute vec4 castle_Vertex;' + LineEnding +
      'uniform float uWaveScale;' + LineEnding +
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  gl_Position = castle_ProjectionMatrix * (castle_ModelViewMatrix * (castle_Vertex * uWaveScale));' + LineEnding +
      '}';

    FragPart2 := TShaderPartNode.Create;
    FragPart2.ShaderType := stFragment;
    FragPart2.Contents :=
      'uniform vec4 uCustomColor;' + LineEnding +
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  gl_FragColor = uCustomColor;' + LineEnding +
      '}';
    Composed2.SetParts([VertPart2, FragPart2]);
    App2.SetShaders([Composed2]);
    Shape2.Appearance := App2;
    Box2 := TBoxNode.Create;
    Shape2.Geometry := Box2;
    Root2.AddChildren(Shape2);
    Scene2.Load(Root2, True);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      RShape1 := TX3DRendererShape(Scene1.Shapes.TraverseList(True)[0]);
      RShape1.PrepareRHIBuffers(Scene1.RenderOptions, 1);
      RShape1.UploadRHIMaterialToCache(ShadingModel);

      AssertEquals('Effect1 must extract 3 custom user effect uniforms (2 scalar/vector + 1 texture)',
        3, RShape1.ExtractRHIUserEffectUniforms);
      AssertTrue('RShape1.Cache.RHIUserEffectBuffer must be allocated',
        RShape1.Cache.RHIUserEffectBuffer <> nil);
      AssertTrue('RShape1.Cache.RHIUserEffectUploadCount must be >= 1',
        RShape1.Cache.RHIUserEffectUploadCount >= 1);
      AssertTrue('RShape1.Cache.RHIUserEffectTexture[0] must be bound from CustomTex1',
        RShape1.Cache.RHIUserEffectTexture[0] <> nil);
      AssertTrue('RShape1.Cache.RHIUserEffectSampler[0] must be bound from CustomTex1',
        RShape1.Cache.RHIUserEffectSampler[0] <> nil);
      AssertTrue('RShape1.Cache.RHISkinningDescriptorSet (Set 2) must be allocated when custom uniforms exist',
        RShape1.Cache.RHISkinningDescriptorSet <> nil);

      RShape2 := TX3DRendererShape(Scene2.Shapes.TraverseList(True)[0]);
      RShape2.PrepareRHIBuffers(Scene2.RenderOptions, 1);
      RShape2.UploadRHIMaterialToCache(ShadingModel);

      AssertEquals('Composed2 must extract 2 custom user effect uniforms',
        2, RShape2.ExtractRHIUserEffectUniforms);
      AssertTrue('RShape2.Cache.RHIUserEffectBuffer must be allocated',
        RShape2.Cache.RHIUserEffectBuffer <> nil);

      Cam.Target := rtScreen;
      Cam.Matrix := TMatrix4.Identity;
      FillChar(Stats, SizeOf(Stats), 0);
      Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
      try
        Renderer.BuildShapePipelineDesc(RShape1, Scene1.RenderOptions, Desc1);
        AssertEquals('Pipeline descriptor layout count must be 3 (Set 0 + Set 1 + Set 2) when UserEffect uniforms are present',
          3, Length(Desc1.DescriptorSetLayouts));
        AssertTrue('Fragment shader must upgrade custom uniforms to CastleUserEffectBlock (set=2, binding=1)',
          Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', RShape1.Cache.RHIFragmentShaderSource) > 0);
        AssertTrue('Fragment shader must upgrade uNoiseTex to CASTLE_SAMPLER(2, 2) uniform sampler2D uNoiseTex',
          Pos('CASTLE_SAMPLER(2, 2) uniform sampler2D uNoiseTex;', RShape1.Cache.RHIFragmentShaderSource) > 0);

        Renderer.BuildShapePipelineDesc(RShape2, Scene2.RenderOptions, Desc2);
        AssertEquals('ComposedShader pipeline descriptor layout count must be 3 when custom uniforms are present',
          3, Length(Desc2.DescriptorSetLayouts));
        AssertTrue('ComposedShader vertex shader must upgrade uWaveScale into CastleUserEffectBlock',
          Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', RShape2.Cache.RHIVertexShaderSource) > 0);
        AssertTrue('ComposedShader fragment shader must upgrade uCustomColor into CastleUserEffectBlock',
          Pos('CASTLE_UBO(2, 1) uniform CastleUserEffectBlock', RShape2.Cache.RHIFragmentShaderSource) > 0);
      finally
        Renderer.RenderEnd;
      end;
    finally
      Device.EndFrameAndPresent;
    end;

    TTextureResources.Unprepare(CustomTex1);
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Scene2);
    FreeAndNil(Scene1);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestEffectShaderLibrariesEyeWorldSpaceAndCameraMatrixAliasesRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  Effect: TEffectNode;
  FragPart: TEffectPartNode;
  RShape: TX3DRendererShape;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  Stats: TRenderStatistics;
  Desc: TRHIGraphicsPipelineDesc;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7702)));
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := TCastleScene.Create(nil);
  Renderer := TRenderer.Create(nil);
  Cam := TRenderingCamera.Create;
  try
    Root := TX3DRootNode.Create;
    Shape := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;

    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;
    Effect.Enabled := True;
    Effect.SetShaderLibraries(['castle-shader:/EyeWorldSpace.glsl']);

    FragPart := TEffectPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents :=
      'uniform mat4 castle_CameraInverseMatrix;' + LineEnding +
      'void PLUG_fragment_eye_space(const vec4 vertex_eye, inout vec3 normal_eye)' + LineEnding +
      '{' + LineEnding +
      '  vec4 vertex_world = position_eye_to_world_space(vertex_eye);' + LineEnding +
      '  vec3 normal_world = direction_eye_to_world_space(normal_eye);' + LineEnding +
      '  if (vertex_world.y < -1000.0) normal_eye = normal_world;' + LineEnding +
      '}';
    Effect.SetParts([FragPart]);
    App.SetEffects([Effect]);
    Shape.Appearance := App;
    Box := TBoxNode.Create;
    Shape.Geometry := Box;
    Root.AddChildren(Shape);
    Scene.Load(Root, True);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      RShape := TX3DRendererShape(Scene.Shapes.TraverseList(True)[0]);
      RShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
      RShape.UploadRHIMaterialToCache(ShadingModel);

      Cam.Target := rtScreen;
      Cam.Matrix := TMatrix4.Identity;
      FillChar(Stats, SizeOf(Stats), 0);
      Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, @Stats);
      try
        Renderer.BuildShapePipelineDesc(RShape, Scene.RenderOptions, Desc);
        AssertTrue('Fragment shader must include EyeWorldSpace helper position_eye_to_world_space',
          Pos('vec4 position_eye_to_world_space(vec4 position_eye)', RShape.Cache.RHIFragmentShaderSource) > 0);
        AssertTrue('Fragment shader must include EyeWorldSpace helper direction_eye_to_world_space',
          Pos('vec3 direction_eye_to_world_space(vec3 direction_eye)', RShape.Cache.RHIFragmentShaderSource) > 0);
        AssertTrue('Fragment shader must define castle_CameraInverseMatrix alias to CastleScene.u_ViewMatrixInverse',
          Pos('#define castle_CameraInverseMatrix CastleScene.u_ViewMatrixInverse', RShape.Cache.RHIFragmentShaderSource) > 0);
        AssertTrue('Fragment shader must define castle_CameraRotationInverseMatrix alias to mat3(CastleScene.u_ViewMatrixInverse)',
          Pos('#define castle_CameraRotationInverseMatrix mat3(CastleScene.u_ViewMatrixInverse)', RShape.Cache.RHIFragmentShaderSource) > 0);
        AssertTrue('uniform mat4 castle_CameraInverseMatrix; declaration must be sanitized from shader body',
          Pos('// [Vulkan RHI UBO]: uniform mat4 castle_CameraInverseMatrix;', RShape.Cache.RHIFragmentShaderSource) > 0);
      finally
        Renderer.RenderEnd;
      end;
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Cam);
    FreeAndNil(Renderer);
    FreeAndNil(Scene);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestLinePropertiesNodeAndRenderContextDynamicLineWidthRHI;
var
  Device: TVulkanRHIDevice;
  CmdList: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  TestCtx: TRenderContext;
  Container: TTestHeadlessVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  LineProps: TLinePropertiesNode;
  ILS: TIndexedLineSetNode;
  Coord: TCoordinateNode;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7703)));
  Device.ResizeSwapchain(256, 256);
  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  TestCtx := TRenderContext.Create(nil);
  RenderContext := TestCtx;
  Container := TTestHeadlessVulkanContainer.Create(nil);
  try
    Viewport := TCastleViewport.Create(Container);
    Viewport.FullSize := True;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Viewport.GLContextOpen;
    Container.Controls.InsertFront(Viewport);

    Root := TX3DRootNode.Create;
    Shape := TShapeNode.Create;
    App := TAppearanceNode.Create;
    LineProps := TLinePropertiesNode.Create;
    LineProps.Applied := True;
    LineProps.LineWidthScaleFactor := 3.5;
    App.LineProperties := LineProps;
    Shape.Appearance := App;

    ILS := TIndexedLineSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, 0, 0),
      Vector3( 1, 0, 0)]);
    ILS.Coord := Coord;
    ILS.SetCoordIndex([0, 1, -1]);
    Shape.Geometry := ILS;
    Root.AddChildren(Shape);

    Scene := TCastleScene.Create(Viewport);
    Scene.Load(Root, True);
    Scene.RenderOptions.LineWidth := 2.0;
    Viewport.Items.Add(Scene);

    CmdList := Device.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(CmdList);
    try
      Container.EventBeforeRender;
      Container.EventRender;

      { During RenderShape:
        1) InitializeFromRenderOptions sets LineWidth := 2.0
        2) RenderShapeLineProperties sets LineWidth := 2.0 * 3.5 = 7.0
        3) ClassRenderEnd resets LineWidth := 1.0 }
      AssertTrue('RenderContext.RHILineWidthUpdateCount must be >= 3 (2.0 -> 7.0 -> 1.0)',
        TestCtx.RHILineWidthUpdateCount >= 3);
      AssertTrue('TVulkanRHICommandList.LineWidthUpdateCount must be >= 3',
        CmdList.LineWidthUpdateCount >= 3);
      AssertSameValue(1.0, TestCtx.RHILastLineWidth, 0.001);
      AssertSameValue(1.0, CmdList.DynamicLineWidth, 0.001);

      { Directly invoke RenderContext.LineWidth := 2.0 * 3.5 to verify active 7.0 state }
      TestCtx.LineWidth := Scene.RenderOptions.LineWidth * LineProps.LineWidthScaleFactor;
      AssertSameValue(7.0, TestCtx.RHILastLineWidth, 0.001);
      AssertSameValue(7.0, CmdList.DynamicLineWidth, 0.001);
    finally
      Device.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Container);
    FreeGlobalBatch2DRenderer;
    RenderContext := SavedCtx;
    FreeAndNil(TestCtx);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestTangentSpaceNormalMappingAndParallaxBumpMappingSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BaseTex, NormalTex: TPixelTextureNode;
  BaseImg, NormImg: TRGBAlphaImage;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  TexCoord: TTextureCoordinateNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7801)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;

    BaseTex := TPixelTextureNode.Create;
    BaseImg := TRGBAlphaImage.Create(2, 2);
    BaseImg.Clear(Vector4Byte(200, 180, 160, 255));
    BaseTex.FdImage.Value := BaseImg;
    Mat.BaseTexture := BaseTex;

    NormalTex := TPixelTextureNode.Create;
    NormImg := TRGBAlphaImage.Create(2, 2);
    NormImg.Clear(Vector4Byte(128, 128, 255, 128)); // Alpha = 128 height map channel
    NormalTex.FdImage.Value := NormImg;
    Mat.NormalTexture := NormalTex;
    App.Material := Mat;
    ShapeNode.Appearance := App;

    IFS := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, -1, 0),
      Vector3( 1, -1, 0),
      Vector3( 0,  1, 0)]);
    IFS.Coord := Coord;
    TexCoord := TTextureCoordinateNode.Create;
    TexCoord.SetPoint([
      Vector2(0, 0),
      Vector2(1, 0),
      Vector2(0.5, 1)]);
    IFS.TexCoord := TexCoord;
    IFS.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode.Geometry := IFS;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    Scene.RenderOptions.BumpMapping := bmBasic;

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList( False, False )[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    AssertTrue('PrepareRHIBuffers must auto-generate tangents when normal map is present',
      (RendererShape.Cache <> nil) and (RendererShape.Cache.GeometryArrays <> nil) and
      RendererShape.Cache.GeometryArrays.HasTangent);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Basic normal mapping with tangents must use PerturbNormalTBN',
      Pos('PerturbNormalTBN(castle_tangent_to_eye_space, tangentNormal, castle_MaterialNormalScale)',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertFalse('Basic normal mapping must not enable parallax',
      RendererShape.Cache.RHIHasParallaxBumpMapping);

    { Classic Parallax Bump Mapping }
    Scene.RenderOptions.BumpMapping := bmParallax;
    Scene.RenderOptions.BumpMappingParallaxHeight := 0.04;
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('bmParallax must enable RHIHasParallaxBumpMapping',
      RendererShape.Cache.RHIHasParallaxBumpMapping);
    AssertFalse('bmParallax must not set RHISteepParallaxBumpMapping',
      RendererShape.Cache.RHISteepParallaxBumpMapping);
    AssertTrue('Mask must include $10000 for parallax bump mapping',
      (RendererShape.Cache.RHIShaderPermutationMask and $10000) <> 0);
    AssertTrue('Classic parallax shader must compute castle_parallax_uv',
      Pos('vec2 castle_parallax_uv = castle_tex_coord0 + castle_parallax_h',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('Base color texture must sample at castle_parallax_uv',
      Pos('texture(castle_base_color_texture, castle_parallax_uv)',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);

    { Steep Parallax Bump Mapping }
    Scene.RenderOptions.BumpMapping := bmSteepParallax;
    Scene.RenderOptions.BumpMappingParallaxHeight := 0.05;
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('bmSteepParallax must set RHISteepParallaxBumpMapping',
      RendererShape.Cache.RHISteepParallaxBumpMapping);
    AssertTrue('Mask must include $10000 and $80000 for steep parallax',
      (RendererShape.Cache.RHIShaderPermutationMask and ($10000 or $80000)) = ($10000 or $80000));
    AssertTrue('Steep parallax shader must emit raymarching loop',
      Pos('for (int castle_step = 0; castle_step < 32; ++castle_step)',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestFogCoordinateVolumetricFogAndCustomShaderVertexAttributesRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  FogCoord: TFogCoordinateNode;
  FloatAttr: TFloatVertexAttributeNode;
  Mat3Attr: TMatrix3VertexAttributeNode;
  RendererShape: TX3DRendererShape;
  Renderer: TRenderer;
  RenderOptions: TCastleRenderOptions;
  PipeDesc: TRHIGraphicsPipelineDesc;
  ShadingModel: TCastleShadingModelRHI;
  FoundFogAttr, FoundFloatAttr, FoundMat3Col0, FoundMat3Col2: Boolean;
  I: Integer;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7802)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  Renderer := nil;
  RenderOptions := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;

    IFS := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, -1, 0),
      Vector3( 1, -1, 0),
      Vector3( 0,  1, 0)]);
    IFS.Coord := Coord;

    FogCoord := TFogCoordinateNode.Create;
    FogCoord.SetDepth([0.1, 0.5, 0.9]);
    IFS.FogCoord := FogCoord;

    FloatAttr := TFloatVertexAttributeNode.Create;
    FloatAttr.NameField := 'customWeight';
    FloatAttr.NumComponents := 1;
    FloatAttr.SetValue([0.25, 0.5, 0.75]);

    Mat3Attr := TMatrix3VertexAttributeNode.Create;
    Mat3Attr.NameField := 'customBasis';
    Mat3Attr.SetValue([TMatrix3.Identity, TMatrix3.Identity, TMatrix3.Identity]);
    IFS.SetAttrib([FloatAttr, Mat3Attr]);

    IFS.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode.Geometry := IFS;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    AssertTrue('Arrays.HasFogCoord must be True when TFogCoordinateNode is present',
      RendererShape.Cache.GeometryArrays.HasFogCoord);
    AssertTrue('Arrays.FogDirectValues must be True for TFogCoordinateNode',
      RendererShape.Cache.GeometryArrays.FogDirectValues);
    AssertEquals('Arrays.Attribs.Count must be 2', 2, RendererShape.Cache.GeometryArrays.Attribs.Count);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Mask must include $20000 for per-vertex fog/custom attributes',
      (RendererShape.Cache.RHIShaderPermutationMask and $20000) <> 0);
    AssertTrue('Vertex shader must declare CASTLE_LOCATION(8) in float castle_FogCoord;',
      Pos('CASTLE_LOCATION(8) in float castle_FogCoord;',
        RendererShape.Cache.RHIVertexShaderSource) > 0);
    AssertTrue('Vertex shader must declare CASTLE_LOCATION(9) in float customWeight;',
      Pos('CASTLE_LOCATION(9) in float customWeight;',
        RendererShape.Cache.RHIVertexShaderSource) > 0);
    AssertTrue('Vertex shader must declare CASTLE_LOCATION(10) in mat3 customBasis;',
      Pos('CASTLE_LOCATION(10) in mat3 customBasis;',
        RendererShape.Cache.RHIVertexShaderSource) > 0);
    AssertTrue('Fragment shader must use direct per-vertex fog coordinate',
      Pos('float fogFactor = clamp(castle_fog_frag_coord, 0.0, 1.0);',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);

    RenderOptions := TCastleRenderOptions.Create(nil);
    Renderer := TRenderer.Create(RenderOptions);
    Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, PipeDesc);

    FoundFogAttr := False;
    FoundFloatAttr := False;
    FoundMat3Col0 := False;
    FoundMat3Col2 := False;
    for I := 0 to High(PipeDesc.VertexInput.Attributes) do
    begin
      if (PipeDesc.VertexInput.Attributes[I].Location = 8) and
         (PipeDesc.VertexInput.Attributes[I].AttributeName = 'castle_FogCoord') and
         (PipeDesc.VertexInput.Attributes[I].Format = vafFloat) then
        FoundFogAttr := True;
      if (PipeDesc.VertexInput.Attributes[I].Location = 9) and
         (PipeDesc.VertexInput.Attributes[I].AttributeName = 'customWeight') and
         (PipeDesc.VertexInput.Attributes[I].Format = vafFloat) then
        FoundFloatAttr := True;
      if (PipeDesc.VertexInput.Attributes[I].Location = 10) and
         (PipeDesc.VertexInput.Attributes[I].AttributeName = 'customBasis') and
         (PipeDesc.VertexInput.Attributes[I].Format = vafVector3) then
        FoundMat3Col0 := True;
      if (PipeDesc.VertexInput.Attributes[I].Location = 12) and
         (PipeDesc.VertexInput.Attributes[I].AttributeName = 'customBasis_col2') and
         (PipeDesc.VertexInput.Attributes[I].Format = vafVector3) then
        FoundMat3Col2 := True;
    end;
    AssertTrue('Pipeline must bind castle_FogCoord at Location 8', FoundFogAttr);
    AssertTrue('Pipeline must bind customWeight at Location 9', FoundFloatAttr);
    AssertTrue('Pipeline must bind customBasis col0 at Location 10', FoundMat3Col0);
    AssertTrue('Pipeline must bind customBasis col2 at Location 12', FoundMat3Col2);
  finally
    FreeAndNil(Renderer);
    FreeAndNil(RenderOptions);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestColorSpaceLinearGammaCorrectionAndFilmicToneMappingSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedColorSpace: TColorSpace;
  SavedToneMapping: TToneMapping;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BaseTex: TPixelTextureNode;
  BaseImg: TRGBAlphaImage;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7803)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedColorSpace := CastleRenderOptions.ColorSpace;
  SavedToneMapping := CastleRenderOptions.ToneMapping;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;

    BaseTex := TPixelTextureNode.Create;
    BaseImg := TRGBAlphaImage.Create(2, 2);
    BaseImg.Clear(Vector4Byte(220, 120, 60, 255));
    BaseTex.FdImage.Value := BaseImg;
    Mat.BaseTexture := BaseTex;
    App.Material := Mat;
    ShapeNode.Appearance := App;

    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    CastleRenderOptions.ColorSpace := csLinear;
    CastleRenderOptions.ToneMapping := tmUncharted;

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('Mask must include $40000 for ColorSpace/ToneMapping specialization',
      (RendererShape.Cache.RHIShaderPermutationMask and $40000) <> 0);
    AssertTrue('Linear color space must linearize baseColor.rgb with pow(..., vec3(2.2))',
      Pos('baseColor.rgb = pow(max(baseColor.rgb, vec3(0.0)), vec3(2.2));',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('Linear color space must convert final color via LINEARtoSRGB',
      Pos('castle_FragColor.rgb = LINEARtoSRGB(castle_FragColor.rgb);',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('tmUncharted must apply toneMapUncharted',
      Pos('castle_FragColor.rgb = toneMapUncharted(castle_FragColor.rgb);',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);

    CastleRenderOptions.ToneMapping := tmHejlRichard;
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('tmHejlRichard must apply toneMapHejlRichard',
      Pos('castle_FragColor.rgb = toneMapHejlRichard(castle_FragColor.rgb);',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);

    CastleRenderOptions.ToneMapping := tmACES;
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('tmACES must apply toneMapACES',
      Pos('castle_FragColor.rgb = toneMapACES(castle_FragColor.rgb);',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
  finally
    CastleRenderOptions.ColorSpace := SavedColorSpace;
    CastleRenderOptions.ToneMapping := SavedToneMapping;
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestBlendModeNodeRenderOptionsBlendFactorsAndDepthFuncPipelineRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  SavedContext: TRenderContext;
  Ctx: TRenderContext;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  BlendMode: TBlendModeNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  Renderer: TRenderer;
  RenderOptions: TCastleRenderOptions;
  PipeDesc: TRHIGraphicsPipelineDesc;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7901)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedContext := RenderContext;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Ctx := nil;
  Scene := nil;
  Renderer := nil;
  RenderOptions := nil;
  try
    Ctx := TRenderContext.Create(nil);
    RenderContext := Ctx;
    Ctx.DepthTest := True;
    Ctx.DepthFunc := dfLessEqual;

    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    Mat.Transparency := 0.5;
    App.Material := Mat;
    BlendMode := TBlendModeNode.Create;
    BlendMode.SrcFactor := bsSrcAlpha;
    BlendMode.DestFactor := bdOne;
    App.BlendMode := BlendMode;
    ShapeNode.Appearance := App;

    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    RenderOptions := TCastleRenderOptions.Create(nil);
    Renderer := TRenderer.Create(RenderOptions);
    Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, PipeDesc);

    AssertTrue('TBlendModeNode must enable blending in pipeline desc', PipeDesc.BlendState.BlendEnable);
    AssertEquals('TBlendModeNode SrcFactor=bsSrcAlpha maps to bfSrcAlpha',
      Ord(bfSrcAlpha), Ord(PipeDesc.BlendState.SrcColorBlendFactor));
    AssertEquals('TBlendModeNode DestFactor=bdOne maps to bfOne (additive blending)',
      Ord(bfOne), Ord(PipeDesc.BlendState.DstColorBlendFactor));
    AssertEquals('RenderContext.DepthFunc=dfLessEqual maps to coLessOrEqual',
      Ord(coLessOrEqual), Ord(PipeDesc.DepthStencil.DepthCompareOp));

    { Now test RenderOptions.BlendingSourceFactor / BlendingDestinationFactor when BlendMode is nil }
    App.BlendMode := nil;
    Scene.ChangedAll;
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    Scene.RenderOptions.BlendingSourceFactor := bsDstColor;
    Scene.RenderOptions.BlendingDestinationFactor := bdZero;
    Ctx.DepthFunc := dfGreater;

    Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, PipeDesc);
    AssertTrue('RenderOptions custom blend factors must enable blending', PipeDesc.BlendState.BlendEnable);
    AssertEquals('RenderOptions.BlendingSourceFactor=bsDstColor maps to bfDstColor',
      Ord(bfDstColor), Ord(PipeDesc.BlendState.SrcColorBlendFactor));
    AssertEquals('RenderOptions.BlendingDestinationFactor=bdZero maps to bfZero',
      Ord(bfZero), Ord(PipeDesc.BlendState.DstColorBlendFactor));
    AssertEquals('RenderContext.DepthFunc=dfGreater maps to coGreater',
      Ord(coGreater), Ord(PipeDesc.DepthStencil.DepthCompareOp));
  finally
    RenderContext := SavedContext;
    FreeAndNil(Ctx);
    FreeAndNil(Renderer);
    FreeAndNil(RenderOptions);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestColorNodeReplaceModeAndRenderOptionsLightingDisabledUnlitRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  ColorNode: TColorNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7902)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    Mat.DiffuseColor := Vector3(0.8, 0.2, 0.1);
    Mat.SpecularColor := Vector3(1.0, 1.0, 1.0);
    Mat.EmissiveColor := Vector3(0.1, 0.1, 0.1);
    Mat.Transparency := 0.25;
    App.Material := Mat;
    ShapeNode.Appearance := App;

    IFS := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, -1, 0),
      Vector3( 1, -1, 0),
      Vector3( 0,  1, 0)]);
    IFS.Coord := Coord;
    ColorNode := TColorNode.Create;
    ColorNode.Mode := cmReplace;
    ColorNode.SetColor([
      Vector3(1, 0, 0),
      Vector3(0, 1, 0),
      Vector3(0, 0, 1)]);
    IFS.Color := ColorNode;
    IFS.SetCoordIndex([0, 1, 2, -1]);
    ShapeNode.Geometry := IFS;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('Mask must include $100000 for ColorNode.Mode = cmReplace',
      (RendererShape.Cache.RHIShaderPermutationMask and $100000) <> 0);
    AssertTrue('cmReplace with TColorNode (RGB) must replace RGB and keep material alpha',
      Pos('vec4 baseColor = vec4(castle_color_per_vertex.rgb, castle_MaterialBaseColor.a);',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertEquals('Lit material must default to smPhong', Ord(smPhong), Ord(ShadingModel));

    { Now disable RenderOptions.Lighting -> must force smUnlit with MainColor & Opacity }
    Scene.RenderOptions.Lighting := False;
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RenderOptions.Lighting=False must force smUnlit', Ord(smUnlit), Ord(ShadingModel));
    AssertSameValue(0.8, RendererShape.Cache.RHIMaterialBlock.BaseColor.X, 1e-4);
    AssertSameValue(0.75, RendererShape.Cache.RHIMaterialBlock.BaseColor.W, 1e-4);
    AssertSameValue(-1.0, RendererShape.Cache.RHIMaterialBlock.SpecularColor.W, 1e-4);
    AssertSameValue(0.0, RendererShape.Cache.RHIMaterialBlock.EmissiveColor.X, 1e-4);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestProjectedTextureCoordinateAndMirrorPlaneTexGenSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TMaterialNode;
  Tex: TPixelTextureNode;
  Img: TRGBAlphaImage;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  ProjTexCoord: TProjectedTextureCoordinateNode;
  SpotLight: TSpotLightNode;
  TexGenNode: TTextureCoordinateGeneratorNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7903)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    SpotLight := TSpotLightNode.Create;
    SpotLight.Location := Vector3(0, 5, 5);
    SpotLight.Direction := Vector3(0, -1, -1);
    Root.AddChildren(SpotLight);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    App.Material := Mat;
    Tex := TPixelTextureNode.Create;
    Img := TRGBAlphaImage.Create(2, 2);
    Img.Clear(Vector4Byte(255, 255, 255, 255));
    Tex.FdImage.Value := Img;
    App.Texture := Tex;
    ShapeNode.Appearance := App;

    IFS := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, 0, -1),
      Vector3( 1, 0, -1),
      Vector3( 1, 0,  1),
      Vector3(-1, 0,  1)]);
    IFS.Coord := Coord;
    ProjTexCoord := TProjectedTextureCoordinateNode.Create;
    ProjTexCoord.FdProjector.Value := SpotLight;
    IFS.TexCoord := ProjTexCoord;
    IFS.SetCoordIndex([0, 1, 2, 3, -1]);
    ShapeNode.Geometry := IFS;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('TProjectedTextureCoordinateNode must resolve to tgProjection',
      Ord(tgProjection), Ord(RendererShape.Cache.RHITexCoordGen));
    AssertTrue('Mask must include $400000 for tgProjection',
      (RendererShape.Cache.RHIShaderPermutationMask and $400000) <> 0);
    AssertTrue('Vertex shader must compute projective texture coordinates via projClip.xy / max(projClip.w, 1e-5)',
      Pos('vec2 rawTexCoord0 = projClip.xy / max(projClip.w, 1e-5);',
        RendererShape.Cache.RHIVertexShaderSource) > 0);

    { Now switch to TTextureCoordinateGeneratorNode with mode="MIRROR-PLANE" }
    TexGenNode := TTextureCoordinateGeneratorNode.Create;
    TexGenNode.FdMode.Value := 'MIRROR-PLANE';
    IFS.TexCoord := TexGenNode;
    Scene.ChangedAll;

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('mode="MIRROR-PLANE" must resolve to tgMirrorPlane',
      Ord(tgMirrorPlane), Ord(RendererShape.Cache.RHITexCoordGen));
    AssertTrue('Mask must include $800000 for tgMirrorPlane',
      (RendererShape.Cache.RHIShaderPermutationMask and $800000) <> 0);
    AssertTrue('Vertex shader must compute mirror-plane texture coordinates from castle_ProjectionMatrix * castle_vertex_eye',
      Pos('vec4 mirrorClip = castle_ProjectionMatrix * castle_vertex_eye;',
        RendererShape.Cache.RHIVertexShaderSource) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestShadowSamplingModesPCFAndVSMSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  SpotLight: TSpotLightNode;
  ShadowMapNode: TGeneratedShadowMapNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8001)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    SpotLight := TSpotLightNode.Create;
    SpotLight.Location := Vector3(0, 10, 10);
    SpotLight.Direction := Vector3(0, -1, -1);
    SpotLight.Shadows := True;
    ShadowMapNode := TGeneratedShadowMapNode.Create;
    ShadowMapNode.Size := 512;
    ShadowMapNode.Update := upAlways;
    SpotLight.DefaultShadowMap := ShadowMapNode;
    Root.AddChildren(SpotLight);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    { 1. ssSimple }
    Scene.RenderOptions.ShadowSampling := ssSimple;
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RHIShadowSampling must be ssSimple', Ord(ssSimple), Ord(RendererShape.Cache.RHIShadowSampling));
    AssertEquals('RHIShadowMapSize must be 512', 512, Integer(RendererShape.Cache.RHIShadowMapSize));
    AssertTrue('ssSimple must use single depth comparison lookup',
      Pos('texture(castle_shadow_map_0, vec3(shadowProj.xy, shadowProj.z - 0.002))',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);

    { 2. ssPCF4 }
    Scene.RenderOptions.ShadowSampling := ssPCF4;
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RHIShadowSampling must be ssPCF4', Ord(ssPCF4), Ord(RendererShape.Cache.RHIShadowSampling));
    AssertTrue('ssPCF4 must emit 4-tap 0.25 kernel with offset 1.0 / 1024',
      (Pos('shadowVis = 0.25 * (', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('float shadowOff = 1.0 / 1024;', RendererShape.Cache.RHIFragmentShaderSource) > 0));

    { 3. ssPCF4Bilinear }
    Scene.RenderOptions.ShadowSampling := ssPCF4Bilinear;
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RHIShadowSampling must be ssPCF4Bilinear', Ord(ssPCF4Bilinear), Ord(RendererShape.Cache.RHIShadowSampling));
    AssertTrue('ssPCF4Bilinear must emit bilinear fract(tc_full) interpolation',
      (Pos('vec2 tc_full = shadowSize * shadowProj.xy;', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('* f1.x * f1.y +', RendererShape.Cache.RHIFragmentShaderSource) > 0));

    { 4. ssPCF16 }
    Scene.RenderOptions.ShadowSampling := ssPCF16;
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RHIShadowSampling must be ssPCF16', Ord(ssPCF16), Ord(RendererShape.Cache.RHIShadowSampling));
    AssertTrue('ssPCF16 must emit 4x4 16-tap PCF loop',
      (Pos('for (int sy = 0; sy < 4; ++sy)', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('shadowVis = shadowSum * (1.0 / 16.0);', RendererShape.Cache.RHIFragmentShaderSource) > 0));

    { 5. ssVarianceShadowMaps (triggers ReleaseCachedResources -> GLContextClose, so re-prepare Cache) }
    Scene.RenderOptions.ShadowSampling := ssVarianceShadowMaps;
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RHIShadowSampling must be ssVarianceShadowMaps', Ord(ssVarianceShadowMaps), Ord(RendererShape.Cache.RHIShadowSampling));
    AssertTrue('ssVarianceShadowMaps must declare sampler2D castle_shadow_map_0 and Chebyshev inequality',
      (Pos('sampler2D castle_shadow_map_0;', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('castle_sample_vsm_slot(light.SpotParams.w, shadowProj.xy)', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('vsmVariance / (vsmVariance + vsmDelta * vsmDelta)', RendererShape.Cache.RHIFragmentShaderSource) > 0));
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiClipPlanesExtractionAndSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Clip1, Clip2, Clip3: TClipPlaneNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  ExtractedPlanes: array[0..3] of TVector4;
  ExtractedCount: Cardinal;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8002)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;

    Clip1 := TClipPlaneNode.Create;
    Clip1.FdEnabled.Value := True;
    Clip1.FdPlane.Value := Vector4(1, 0, 0, -0.5);
    Root.AddChildren(Clip1);

    Clip2 := TClipPlaneNode.Create;
    Clip2.FdEnabled.Value := True;
    Clip2.FdPlane.Value := Vector4(0, 1, 0, 0.25);
    Root.AddChildren(Clip2);

    Clip3 := TClipPlaneNode.Create;
    Clip3.FdEnabled.Value := True;
    Clip3.FdPlane.Value := Vector4(0, 0, 1, -0.75);
    Root.AddChildren(Clip3);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    ExtractedCount := RendererShape.ExtractRHIClipPlanes(ExtractedPlanes);
    AssertEquals('Must extract 3 enabled TClipPlaneNodes', 3, Integer(ExtractedCount));

    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('Cache.RHIClipPlaneCount must be 3', 3, Integer(RendererShape.Cache.RHIClipPlaneCount));
    AssertSameValue(-0.5, RendererShape.Cache.RHIClipPlanes[0].W, 1e-4);
    AssertSameValue(0.25, RendererShape.Cache.RHIClipPlanes[1].W, 1e-4);
    AssertSameValue(-0.75, RendererShape.Cache.RHIClipPlanes[2].W, 1e-4);
    AssertTrue('Fragment shader must contain discard check for Clip1',
      Pos('if (dot(vec4(1, 0, 0, -0.5), castle_ViewMatrixInverse * vec4(castle_vertex_eye.xyz, 1.0)) < 0.0) discard;',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('Fragment shader must contain discard check for Clip2',
      Pos('if (dot(vec4(0, 1, 0, 0.25), castle_ViewMatrixInverse * vec4(castle_vertex_eye.xyz, 1.0)) < 0.0) discard;',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('Fragment shader must contain discard check for Clip3',
      Pos('if (dot(vec4(0, 0, 1, -0.75), castle_ViewMatrixInverse * vec4(castle_vertex_eye.xyz, 1.0)) < 0.0) discard;',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestSecondaryUVChannelAndMaterialTextureMappingSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  BaseTex, OcclusionTex, EmissiveTex: TPixelTextureNode;
  Img1, Img2, Img3: TRGBAlphaImage;
  IFS: TIndexedFaceSetNode;
  Coord: TCoordinateNode;
  MultiTexCoord: TMultiTextureCoordinateNode;
  TexCoord0, TexCoord1: TTextureCoordinateNode;
  RendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8003)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;

    BaseTex := TPixelTextureNode.Create;
    Img1 := TRGBAlphaImage.Create(2, 2);
    Img1.Clear(Vector4Byte(255, 255, 255, 255));
    BaseTex.FdImage.Value := Img1;
    Mat.BaseTexture := BaseTex;
    Mat.BaseTextureMapping := 'UV0';

    OcclusionTex := TPixelTextureNode.Create;
    Img2 := TRGBAlphaImage.Create(2, 2);
    Img2.Clear(Vector4Byte(200, 200, 200, 255));
    OcclusionTex.FdImage.Value := Img2;
    Mat.OcclusionTexture := OcclusionTex;
    Mat.OcclusionTextureMapping := 'LIGHTMAP_UV1';

    EmissiveTex := TPixelTextureNode.Create;
    Img3 := TRGBAlphaImage.Create(2, 2);
    Img3.Clear(Vector4Byte(128, 64, 0, 255));
    EmissiveTex.FdImage.Value := Img3;
    Mat.EmissiveTexture := EmissiveTex;
    Mat.EmissiveTextureMapping := 'LIGHTMAP_UV1';

    App.Material := Mat;
    ShapeNode.Appearance := App;

    IFS := TIndexedFaceSetNode.Create;
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([
      Vector3(-1, -1, 0),
      Vector3( 1, -1, 0),
      Vector3( 1,  1, 0),
      Vector3(-1,  1, 0)]);
    IFS.Coord := Coord;

    TexCoord0 := TTextureCoordinateNode.Create;
    TexCoord0.Mapping := 'UV0';
    TexCoord0.SetPoint([
      Vector2(0, 0),
      Vector2(1, 0),
      Vector2(1, 1),
      Vector2(0, 1)]);

    TexCoord1 := TTextureCoordinateNode.Create;
    TexCoord1.Mapping := 'LIGHTMAP_UV1';
    TexCoord1.SetPoint([
      Vector2(0.1, 0.1),
      Vector2(0.9, 0.1),
      Vector2(0.9, 0.9),
      Vector2(0.1, 0.9)]);

    MultiTexCoord := TMultiTextureCoordinateNode.Create;
    MultiTexCoord.FdTexCoord.Add(TexCoord0);
    MultiTexCoord.FdTexCoord.Add(TexCoord1);
    IFS.TexCoord := MultiTexCoord;
    IFS.SetCoordIndex([0, 1, 2, 3, -1]);
    ShapeNode.Geometry := IFS;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 1);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertEquals('Arrays.TexCoords.Count must be 2 for MultiTextureCoordinate',
      2, RendererShape.Cache.GeometryArrays.TexCoords.Count);
    AssertEquals('RHIBaseColorTexCoordIndex must be 0 (UV0)',
      0, Integer(RendererShape.Cache.RHIBaseColorTexCoordIndex));
    AssertEquals('RHIOcclusionTexCoordIndex must be 1 (LIGHTMAP_UV1)',
      1, Integer(RendererShape.Cache.RHIOcclusionTexCoordIndex));
    AssertEquals('RHIEmissiveTexCoordIndex must be 1 (LIGHTMAP_UV1)',
      1, Integer(RendererShape.Cache.RHIEmissiveTexCoordIndex));
    AssertTrue('BaseColor texture must sample castle_tex_coord0',
      Pos('texture(castle_base_color_texture, castle_tex_coord0)',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('Occlusion texture must sample castle_tex_coord1',
      Pos('texture(castle_occlusion_texture, castle_tex_coord1)',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
    AssertTrue('Emissive texture must sample castle_tex_coord1',
      Pos('texture(castle_emissive_texture, castle_tex_coord1)',
        RendererShape.Cache.RHIFragmentShaderSource) > 0);
  finally
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiShadowMapLightsSlotRoutingAndSceneDescriptorSetRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Spot1, Spot2: TSpotLightNode;
  ShadowMap1, ShadowMap2: TGeneratedShadowMapNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  ExtractedTextures: array[0..3] of TRHITexture;
  ExtractedSamplers: array[0..3] of TRHISampler;
  ExtractedCount: Cardinal;
  ShadingModel: TCastleShadingModelRHI;
  Renderer: TRenderer;
  LightsRen: TLightsRenderer;
  Cam: TRenderingCamera;
  LightsBlock: TCastleLightsUniformBlock;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8101)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  Renderer := nil;
  LightsRen := nil;
  Cam := nil;
  try
    Root := TX3DRootNode.Create;

    Spot1 := TSpotLightNode.Create;
    Spot1.FdOn.Value := True;
    Spot1.FdLocation.Value := Vector3(-4, 6, 4);
    Spot1.FdDirection.Value := Vector3(1, -1.5, -1).Normalize;
    Spot1.Shadows := True;
    ShadowMap1 := TGeneratedShadowMapNode.Create;
    ShadowMap1.Update := upAlways;
    ShadowMap1.FdSize.Value := 256;
    Spot1.FdDefaultShadowMap.Value := ShadowMap1;
    Root.AddChildren(Spot1);

    Spot2 := TSpotLightNode.Create;
    Spot2.FdOn.Value := True;
    Spot2.FdLocation.Value := Vector3(4, 6, 4);
    Spot2.FdDirection.Value := Vector3(-1, -1.5, -1).Normalize;
    Spot2.Shadows := True;
    ShadowMap2 := TGeneratedShadowMapNode.Create;
    ShadowMap2.Update := upAlways;
    ShadowMap2.FdSize.Value := 256;
    Spot2.FdDefaultShadowMap.Value := ShadowMap2;
    Root.AddChildren(Spot2);

    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);

    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    ExtractedCount := RendererShape.ExtractRHIShadowMaps(ExtractedTextures, ExtractedSamplers);
    AssertEquals('Must extract 2 prepared shadow map textures from Spot1 & Spot2', 2, Integer(ExtractedCount));
    AssertTrue('Slot 0 shadow map texture must be non-nil', ExtractedTextures[0] <> nil);
    AssertTrue('Slot 1 shadow map texture must be non-nil', ExtractedTextures[1] <> nil);
    AssertTrue('Slot 0 and Slot 1 shadow map textures must be distinct', ExtractedTextures[0] <> ExtractedTextures[1]);

    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertTrue('Fragment shader must include castle_sample_shadow_slot dispatching castle_shadow_map_0..3',
      (Pos('float castle_sample_shadow_slot(float slot, vec3 coord)', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('if (slot < 1.5) return texture(castle_shadow_map_0, coord);', RendererShape.Cache.RHIFragmentShaderSource) > 0) and
      (Pos('if (slot < 2.5) return texture(castle_shadow_map_1, coord);', RendererShape.Cache.RHIFragmentShaderSource) > 0));

    Cam := TRenderingCamera.Create;
    Cam.Matrix := TMatrix4.Identity;
    LightsRen := TLightsRenderer.Create;
    LightsRen.RenderingCamera := Cam;
    LightsRen.BuildLightsUniformBlock(RendererShape, nil, RendererShape.State.Lights, nil, LightsBlock);
    AssertEquals('LightsBlock must contain 2 spot lights', 2, Integer(LightsBlock.Count));
    AssertSameValue(1.0, LightsBlock.Lights[0].SpotParams.W, 1e-4);
    AssertSameValue(2.0, LightsBlock.Lights[1].SpotParams.W, 1e-4);

    Renderer := TRenderer.Create(nil);
    Renderer.BindShadowMapToSceneDescriptorSet(0, ExtractedTextures[0], ExtractedSamplers[0]);
    Renderer.BindShadowMapToSceneDescriptorSet(1, ExtractedTextures[1], ExtractedSamplers[1]);
    AssertTrue('Renderer.RHIShadowMapTexture[0] must match ExtractedTextures[0]',
      Renderer.RHIShadowMapTexture[0] = ExtractedTextures[0]);
    AssertTrue('Renderer.RHIShadowMapTexture[1] must match ExtractedTextures[1]',
      Renderer.RHIShadowMapTexture[1] = ExtractedTextures[1]);
  finally
    FreeAndNil(Renderer);
    FreeAndNil(LightsRen);
    FreeAndNil(Cam);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestRenderOptionsColorChannelsWriteMaskPipelineRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  Renderer: TRenderer;
  DescFull, DescRedOnly, DescCyanOnly: TRHIGraphicsPipelineDesc;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8102)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  Renderer := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    Renderer := TRenderer.Create(nil);

    { 1. Default AllColorChannels ([0..3]) -> $0F }
    Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, DescFull);
    AssertEquals('Default InternalColorChannels [0..3] must produce ColorWriteMask $0F',
      $0F, Integer(DescFull.BlendState.ColorWriteMask));

    { 2. Left-eye anaglyph Red-only ([0]) -> $01 }
    Scene.RenderOptions.InternalColorChannels := [0];
    Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, DescRedOnly);
    AssertEquals('InternalColorChannels [0] must produce ColorWriteMask $01 (Red only)',
      $01, Integer(DescRedOnly.BlendState.ColorWriteMask));

    { 3. Right-eye anaglyph Green+Blue ([1, 2]) -> $06 }
    Scene.RenderOptions.InternalColorChannels := [1, 2];
    Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, DescCyanOnly);
    AssertEquals('InternalColorChannels [1, 2] must produce ColorWriteMask $06 (Green + Blue)',
      $06, Integer(DescCyanOnly.BlendState.ColorWriteMask));
  finally
    FreeAndNil(Renderer);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestVarianceShadowMapCasterPassMomentShaderAndPipelineRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  Box: TBoxNode;
  RendererShape: TX3DRendererShape;
  Renderer: TRenderer;
  Cam: TRenderingCamera;
  DescVSM: TRHIGraphicsPipelineDesc;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8103)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  Renderer := nil;
  Cam := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    App.Material := Mat;
    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);

    Cam := TRenderingCamera.Create;
    Cam.Target := rtVarianceShadowMap;
    Cam.Matrix := TMatrix4.Identity;

    Renderer := TRenderer.Create(nil);
    Renderer.RenderBegin(nil, Cam, nil, 0, 0, 0, nil);
    try
      Renderer.BuildShapePipelineDesc(RendererShape, Scene.RenderOptions, DescVSM);
      AssertTrue('RHIVSMCasterFragmentShader must be created', Renderer.RHIVSMCasterFragmentShader <> nil);
      AssertTrue('rtVarianceShadowMap pipeline must bind RHIVSMCasterFragmentShader',
        DescVSM.FragmentShader = Renderer.RHIVSMCasterFragmentShader);
      AssertEquals('rtVarianceShadowMap pipeline must have 1 color attachment',
        1, Length(DescVSM.ColorAttachmentFormats));
      AssertEquals('rtVarianceShadowMap color attachment must be pfRGBA32_Float',
        Ord(pfRGBA32_Float), Ord(DescVSM.ColorAttachmentFormats[0]));
      AssertTrue('rtVarianceShadowMap pipeline must enable DepthBiasEnable',
        DescVSM.Rasterizer.DepthBiasEnable);
      AssertFalse('rtVarianceShadowMap pipeline must disable blending',
        DescVSM.BlendState.BlendEnable);
      AssertEquals('CastleShapeVSMPSO', DescVSM.DebugName);
    finally
      Renderer.RenderEnd;
    end;
  finally
    FreeAndNil(Renderer);
    FreeAndNil(Cam);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

procedure TTestCastleVulkanRHI.TestMultiTextureCombineModesAndTextured3DTextSpecializationRHI;
var
  Device: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedBackend: TRenderBackend;
  Scene, TextScene: TCastleScene;
  Root, TextRoot: TX3DRootNode;
  ShapeNode, TextShapeNode: TShapeNode;
  App, TextApp: TAppearanceNode;
  Mat, TextMat: TMaterialNode;
  MultiTex: TMultiTextureNode;
  Tex0, Tex1, TextExtraTex: TPixelTextureNode;
  Img0, Img1, ImgText: TRGBAlphaImage;
  Box: TBoxNode;
  TextNode: TTextNode;
  RendererShape, TextRendererShape: TX3DRendererShape;
  ShadingModel: TCastleShadingModelRHI;
  FragAdd, FragBlend, FragText: String;
begin
  Device := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($8201)));
  SavedRHI := RHIDevice;
  SavedBackend := ApplicationProperties.RenderBackend;
  ApplicationProperties.RenderBackend := backendVulkan;
  SetRHIDevice(Device);
  Scene := nil;
  TextScene := nil;
  try
    Root := TX3DRootNode.Create;
    ShapeNode := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TMaterialNode.Create;
    App.Material := Mat;

    MultiTex := TMultiTextureNode.Create;
    MultiTex.Color := Vector3(0.5, 0.5, 0.5);
    MultiTex.Alpha := 0.35;

    Tex0 := TPixelTextureNode.Create;
    Img0 := TRGBAlphaImage.Create(4, 4);
    Img0.Clear(Vector4Byte(255, 0, 0, 255));
    Tex0.FdImage.Value := Img0;

    Tex1 := TPixelTextureNode.Create;
    Img1 := TRGBAlphaImage.Create(4, 4);
    Img1.Clear(Vector4Byte(0, 255, 0, 255));
    Tex1.FdImage.Value := Img1;

    MultiTex.FdTexture.Add(Tex0);
    MultiTex.FdTexture.Add(Tex1);
    MultiTex.FdMode.Items.Add('MODULATE');
    MultiTex.FdMode.Items.Add('ADD');
    App.Texture := MultiTex;

    ShapeNode.Appearance := App;
    Box := TBoxNode.Create;
    ShapeNode.Geometry := Box;
    Root.AddChildren(ShapeNode);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    RendererShape := TX3DRendererShape(Scene.Shapes.TraverseList(False, False)[0]);
    RendererShape.PrepareRHIBuffers(Scene.RenderOptions, 0);
    RendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('RHIHasSecondTexture must be True for MultiTexture with 2 children',
      RendererShape.Cache.RHIHasSecondTexture);
    AssertEquals('RHISecondTextureCombineRGB must be coAdd',
      Ord(coAdd), Ord(RendererShape.Cache.RHISecondTextureCombineRGB));
    AssertTrue('RHIUserEffectTexture[0] must be bound for castle_multi_texture_1',
      RendererShape.Cache.RHIUserEffectTexture[0] <> nil);
    FragAdd := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('MultiTexture ADD shader must declare castle_multi_texture_1 at Set 2 Binding 2',
      Pos('CASTLE_DESCRIPTOR_SET(2, 2) uniform sampler2D castle_multi_texture_1;', FragAdd) > 0);
    AssertTrue('MultiTexture ADD shader must add multiTex1.rgb',
      Pos('baseColor.rgb += multiTex1.rgb;', FragAdd) > 0);

    { Switch MultiTexture slot 1 mode to BLENDFACTORALPHA (coBlend) }
    MultiTex.FdMode.Items[1] := 'BLENDFACTORALPHA';
    RendererShape.UploadRHIMaterialToCache(ShadingModel);
    AssertEquals('RHISecondTextureCombineRGB must be coBlend',
      Ord(coBlend), Ord(RendererShape.Cache.RHISecondTextureCombineRGB));
    FragBlend := RendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('MultiTexture BLENDFACTORALPHA shader must mix with MultiTexture.Alpha (0.3500)',
      Pos('baseColor.rgb = mix(baseColor.rgb, multiTex1.rgb, 0.3500);', FragBlend) > 0);

    { Textured 3D Text: TTextNode with FontTextureNode + Appearance.Texture }
    TextRoot := TX3DRootNode.Create;
    TextShapeNode := TShapeNode.Create;
    TextApp := TAppearanceNode.Create;
    TextMat := TMaterialNode.Create;
    TextApp.Material := TextMat;
    TextExtraTex := TPixelTextureNode.Create;
    ImgText := TRGBAlphaImage.Create(4, 4);
    ImgText.Clear(Vector4Byte(255, 200, 50, 255));
    TextExtraTex.FdImage.Value := ImgText;
    TextApp.Texture := TextExtraTex;
    TextShapeNode.Appearance := TextApp;

    TextNode := TTextNode.Create;
    TextNode.SetText(['Vulkan']);
    TextShapeNode.Geometry := TextNode;
    TextRoot.AddChildren(TextShapeNode);

    TextScene := TCastleScene.Create(nil);
    TextScene.Load(TextRoot, True);
    TextRendererShape := TX3DRendererShape(TextScene.Shapes.TraverseList(False, False)[0]);
    TextRendererShape.PrepareRHIBuffers(TextScene.RenderOptions, 0);
    TextRendererShape.UploadRHIMaterialToCache(ShadingModel);

    AssertTrue('Textured 3D Text must enable RHIHasSecondTexture (FontTextureNode + Appearance.Texture)',
      TextRendererShape.Cache.RHIHasSecondTexture);
    AssertEquals('Textured 3D Text must combine second texture with coModulate',
      Ord(coModulate), Ord(TextRendererShape.Cache.RHISecondTextureCombineRGB));
    FragText := TextRendererShape.Cache.RHIFragmentShaderSource;
    AssertTrue('Textured 3D Text fragment shader must sample castle_multi_texture_1 at castle_tex_coord1',
      Pos('vec4 multiTex1 = texture(castle_multi_texture_1, castle_tex_coord1);', FragText) > 0);
    AssertTrue('Textured 3D Text fragment shader must modulate baseColor.rgb *= multiTex1.rgb',
      Pos('baseColor.rgb *= multiTex1.rgb;', FragText) > 0);
  finally
    FreeAndNil(TextScene);
    FreeAndNil(Scene);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(Device);
  end;
end;

{$endif read_implementation}
