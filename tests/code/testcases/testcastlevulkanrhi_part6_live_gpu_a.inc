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

procedure TTestCastleVulkanRHI.TestBuiltInSPIRVCoreShadersAndRealLavapipeDrawPrimitive2DRHI;
var
  SPIRV: TSPIRVBytecode;
  Refl: TSPIRVReflectionInfo;
  FoundBinding: TSPIRVReflectedBinding;
  FoundIO: TSPIRVReflectedStageIO;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  RectCtrl: TCastleRectangleControl;
  ColorTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Readback: TRGBAlphaImage;
begin
  { Part 1: Verify built-in SPIR-V 1.0 core shaders & pure-Pascal SPIR-V reflection }
  AssertTrue('TryGetBuiltInSPIRV must resolve Primitive2D_VS',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, '', 'Primitive2D_VS', SPIRV));
  AssertTrue('InspectSPIRVBytecode must validate Primitive2D_VS',
    InspectSPIRVBytecode(SPIRV, Refl) and Refl.IsValid);
  AssertEquals(Ord(ssVertex), Ord(Refl.Stage));
  AssertTrue(Refl.HasPushConstants);
  AssertEquals('Primitive2D_VS push constants size must be 32 bytes', 32, Integer(Refl.PushConstantSize));
  AssertTrue('Primitive2D_VS must declare location 0 input vec2',
    Refl.FindStageInput(0, FoundIO) and (FoundIO.ComponentCount = 2));

  AssertTrue('TryGetBuiltInSPIRV must resolve Primitive2D_FS',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'Primitive2D_FS', SPIRV));
  AssertTrue('InspectSPIRVBytecode must validate Primitive2D_FS',
    InspectSPIRVBytecode(SPIRV, Refl) and Refl.IsValid);
  AssertEquals(Ord(ssFragment), Ord(Refl.Stage));
  AssertTrue(Refl.HasPushConstants);
  AssertEquals('Primitive2D_FS push constants size must be 32 bytes', 32, Integer(Refl.PushConstantSize));
  AssertTrue('Primitive2D_FS must declare location 0 output vec4',
    Refl.FindStageOutput(0, FoundIO) and (FoundIO.ComponentCount = 4));

  AssertTrue('TryGetBuiltInSPIRV must resolve UnlitMesh_VS',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, '', 'UnlitMesh_VS', SPIRV));
  AssertTrue('InspectSPIRVBytecode must validate UnlitMesh_VS',
    InspectSPIRVBytecode(SPIRV, Refl) and Refl.IsValid);
  AssertEquals('UnlitMesh_VS push constants size must be 80 bytes (mat4 + vec4)',
    80, Integer(Refl.PushConstantSize));
  AssertTrue('UnlitMesh_VS must declare location 0 input vec4',
    Refl.FindStageInput(0, FoundIO) and (FoundIO.ComponentCount = 4));

  AssertTrue('TryGetBuiltInSPIRV must resolve UnlitMesh_FS',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'UnlitMesh_FS', SPIRV));
  AssertTrue('InspectSPIRVBytecode must validate UnlitMesh_FS',
    InspectSPIRVBytecode(SPIRV, Refl) and Refl.IsValid);
  AssertEquals('UnlitMesh_FS push constants size must be 80 bytes',
    80, Integer(Refl.PushConstantSize));

  AssertTrue('TryGetBuiltInSPIRV must resolve CastleBatch2D.vert',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, '', 'CastleBatch2D.vert', SPIRV));
  AssertTrue('InspectSPIRVBytecode must validate CastleBatch2D.vert',
    InspectSPIRVBytecode(SPIRV, Refl) and Refl.IsValid);
  AssertEquals('CastleBatch2D.vert push constants size must be 64 bytes (4 x vec4)',
    64, Integer(Refl.PushConstantSize));
  AssertTrue('CastleBatch2D.vert must declare location 0, 2, 4 inputs',
    Refl.FindStageInput(0, FoundIO) and
    Refl.FindStageInput(2, FoundIO) and
    Refl.FindStageInput(4, FoundIO));

  AssertTrue('TryGetBuiltInSPIRV must resolve CastleBatch2D.frag',
    TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'CastleBatch2D.frag', SPIRV));
  AssertTrue('InspectSPIRVBytecode must validate CastleBatch2D.frag',
    InspectSPIRVBytecode(SPIRV, Refl) and Refl.IsValid);
  AssertEquals('CastleBatch2D.frag push constants size must be 64 bytes',
    64, Integer(Refl.PushConstantSize));
  AssertTrue('CastleBatch2D.frag must declare set=0, binding=0 dtCombinedImageSampler',
    Refl.FindBinding(0, 0, FoundBinding) and
    (FoundBinding.DescriptorType = dtCombinedImageSampler));

  { Also verify GetMinimalValidSPIRVFallback for all 4 shader stages }
  SPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssVertex);
  AssertTrue(InspectSPIRVBytecode(SPIRV, Refl) and (Refl.Stage = ssVertex));
  SPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssFragment);
  AssertTrue(InspectSPIRVBytecode(SPIRV, Refl) and (Refl.Stage = ssFragment));
  SPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssGeometry);
  AssertTrue(InspectSPIRVBytecode(SPIRV, Refl) and (Refl.Stage = ssGeometry));
  SPIRV := TCastleShaderCompiler.Instance.GetMinimalValidSPIRVFallback(ssCompute);
  AssertTrue(InspectSPIRVBytecode(SPIRV, Refl) and (Refl.Stage = ssCompute));

  { Part 2: Live Offscreen Vulkan GPU (Mesa Lavapipe) multi-draw in-frame DrawPrimitive2D,
    DrawRectangle, DrawCircle, and TCastleRectangleControl execution }
  if TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
  begin
    SavedRHI := RHIDevice;
    SavedCmd := ActiveCommandList;
    SavedBackend := ApplicationProperties.RenderBackend;
    SavedCtx := RenderContext;
    SavedGLFeatures := GLFeatures;
    Container := TTestSizedVulkanContainer.Create(nil);
    RectCtrl := nil;
    ColorTex := nil;
    Readback := nil;
    try
      GLFeatures := nil;
      ApplicationProperties.RenderBackend := backendVulkan;
      SetRHIDevice(RealDev);
      RHIPrimitive2DResetStats;

      Container.TestWidth := 64;
      Container.TestHeight := 64;
      RenderContext := Container.Context;
      RenderContext.Viewport := Rectangle(0, 0, 64, 64);

      ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
        [tuColorAttachment, tuTransferSrc]));
      RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
      SetActiveCommandList(RealCmd);

      PassInfo := TRHIRenderingInfo.CreateColorDepth(
        Rectangle(0, 0, 64, 64),
        ColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
        nil, loDontCare, 1.0);
      RealCmd.BeginRendering(PassInfo);

      { Draw 1: Opaque Red rectangle at bottom-left [4..28] x [4..28] }
      DrawRectangle(Rectangle(4, 4, 24, 24), Vector4(1.0, 0.0, 0.0, 1.0));

      { Draw 2: Opaque Green rectangle at bottom-right [36..60] x [4..28]
        (Tests that in-frame multi-draw vertex streaming in DrawPrimitive2D does NOT overwrite Draw 1!) }
      DrawRectangle(Rectangle(36, 4, 24, 24), Vector4(0.0, 1.0, 0.0, 1.0));

      { Draw 3: Alpha-blended 50% Blue rectangle over the right half of Green [48..60] x [4..28] }
      DrawRectangle(Rectangle(48, 4, 12, 24), Vector4(0.0, 0.0, 1.0, 0.5));

      { Draw 4: Filled Yellow circle centered at (16, 48) with radius 10 }
      DrawCircle(Vector2Integer(16, 48), 10, 10, Vector4(1.0, 1.0, 0.0, 1.0));

      { Draw 5: TCastleRectangleControl at top-right [36..60] x [36..60] with Magenta fill }
      RectCtrl := TCastleRectangleControl.Create(nil);
      RectCtrl.Translation := Vector2(36, 36);
      RectCtrl.Width := 24;
      RectCtrl.Height := 24;
      RectCtrl.Color := Vector4(1.0, 0.0, 1.0, 1.0);
      Container.Controls.InsertFront(RectCtrl);
      Container.RenderControl(RectCtrl, Rectangle(0, 0, 64, 64));

      RealCmd.EndRendering;
      RealDev.EndFrameAndPresent;

      Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

      { Verify Draw 1 (bottom-left Red at (16, 16)) was NOT overwritten by subsequent draws }
      AssertEquals('Draw 1 Red (16,16) R must be 255', 255, Integer(Readback.PixelPtr(16, 16)^.X));
      AssertEquals('Draw 1 Red (16,16) G must be 0', 0, Integer(Readback.PixelPtr(16, 16)^.Y));
      AssertEquals('Draw 1 Red (16,16) B must be 0', 0, Integer(Readback.PixelPtr(16, 16)^.Z));

      { Verify Draw 2 (unblended Green at (42, 16)) }
      AssertEquals('Draw 2 Green (42,16) R must be 0', 0, Integer(Readback.PixelPtr(42, 16)^.X));
      AssertEquals('Draw 2 Green (42,16) G must be 255', 255, Integer(Readback.PixelPtr(42, 16)^.Y));
      AssertEquals('Draw 2 Green (42,16) B must be 0', 0, Integer(Readback.PixelPtr(42, 16)^.Z));

      { Verify Draw 3 (50% Blue blended over Green at (54, 16) -> (0, ~127, ~128)) }
      AssertEquals('Draw 3 Blended (54,16) R must be 0', 0, Integer(Readback.PixelPtr(54, 16)^.X));
      AssertTrue('Draw 3 Blended (54,16) G must be ~127', Abs(Integer(Readback.PixelPtr(54, 16)^.Y) - 127) <= 3);
      AssertTrue('Draw 3 Blended (54,16) B must be ~128', Abs(Integer(Readback.PixelPtr(54, 16)^.Z) - 128) <= 3);

      { Verify Draw 4 (Yellow Circle center at (16, 48)) }
      AssertEquals('Draw 4 Yellow Circle (16,48) R must be 255', 255, Integer(Readback.PixelPtr(16, 48)^.X));
      AssertEquals('Draw 4 Yellow Circle (16,48) G must be 255', 255, Integer(Readback.PixelPtr(16, 48)^.Y));
      AssertEquals('Draw 4 Yellow Circle (16,48) B must be 0', 0, Integer(Readback.PixelPtr(16, 48)^.Z));

      { Verify Draw 5 (TCastleRectangleControl Magenta at (48, 48)) }
      AssertEquals('Draw 5 TCastleRectangleControl (48,48) R must be 255', 255, Integer(Readback.PixelPtr(48, 48)^.X));
      AssertEquals('Draw 5 TCastleRectangleControl (48,48) G must be 0', 0, Integer(Readback.PixelPtr(48, 48)^.Y));
      AssertEquals('Draw 5 TCastleRectangleControl (48,48) B must be 255', 255, Integer(Readback.PixelPtr(48, 48)^.Z));
    finally
      RHIPrimitive2DResetStats;
      FreeAndNil(Readback);
      FreeAndNil(ColorTex);
      FreeAndNil(RectCtrl);
      FreeAndNil(Container);
      GLFeatures := SavedGLFeatures;
      RenderContext := SavedCtx;
      SetActiveCommandList(SavedCmd);
      SetRHIDevice(SavedRHI);
      ApplicationProperties.RenderBackend := SavedBackend;
      FreeAndNil(RealDev);
    end;
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeBatch2DDrawableImageFontAlphaClipAndMultiPassRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  ColorTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  SrcImg, FontAlphaImg, Readback: TRGBAlphaImage;
  DrawImg, FontDrawImg: TDrawableImage;
  Batch2D: TCastleBatch2DRenderer;
  SR, IR: TFloatRectangle;
  X, Y: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := TTestSizedVulkanContainer.Create(nil);
  ColorTex := nil;
  DrawImg := nil;
  FontDrawImg := nil;
  Readback := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);
    FreeGlobalBatch2DRenderer;

    Container.TestWidth := 64;
    Container.TestHeight := 64;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 64, 64);

    { Create 16x16 sprite image:
      - Left half (X < 8): Opaque Red (255, 0, 0, 255)
      - Right half (X >= 8): Low-alpha Green (0, 255, 0, 64) }
    SrcImg := TRGBAlphaImage.Create(16, 16);
    for Y := 0 to 15 do
      for X := 0 to 15 do
        if X < 8 then
          SrcImg.PixelPtr(X, Y)^ := Vector4Byte(255, 0, 0, 255)
        else
          SrcImg.PixelPtr(X, Y)^ := Vector4Byte(0, 255, 0, 64);
    DrawImg := TDrawableImage.Create(SrcImg, False, True);

    { Create 16x16 font-glyph alpha image:
      - Left half (X < 8): Alpha = 255 (RGB = 0 to prove TextureHasOnlyAlpha uses vertex RGB!)
      - Right half (X >= 8): Alpha = 0 }
    FontAlphaImg := TRGBAlphaImage.Create(16, 16);
    for Y := 0 to 15 do
      for X := 0 to 15 do
        if X < 8 then
          FontAlphaImg.PixelPtr(X, Y)^ := Vector4Byte(0, 0, 0, 255)
        else
          FontAlphaImg.PixelPtr(X, Y)^ := Vector4Byte(0, 0, 0, 0);
    FontDrawImg := TDrawableImage.Create(FontAlphaImg, False, True);

    ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuTransferSrc]));
    RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.0, 0.0, 0.5, 1.0), { Clear to Navy Blue (0, 0, 128) }
      nil, loDontCare, 1.0);
    RealCmd.BeginRendering(PassInfo);

    { Pass 1 (standalone DrawNoBatch -> Begin2DPass..End2DPass #1 at FFramePassBaseQuad = 0):
      Opaque sprite at (4, 4, 16, 16) with Alpha = acNone -> Left = Red (255,0,0), Right = Green (0,255,0) }
    DrawImg.Alpha := acNone;
    DrawImg.Color := Vector4(1.0, 1.0, 1.0, 1.0);
    DrawImg.Clip := False;
    DrawImg.Draw(4, 4, 16, 16, 0, 0, 16, 16);

    { Pass 2 (standalone DrawNoBatch -> Begin2DPass..End2DPass #2 at FFramePassBaseQuad = 1):
      Alpha-tested sprite at (24, 4, 16, 16) with Alpha = acTest (cutoff = 0.5):
      Left half (alpha = 1.0 >= 0.5) draws Red; Right half (alpha = 64/255 < 0.5) is discarded (remains Navy Blue)! }
    DrawImg.Alpha := acTest;
    DrawImg.Draw(24, 4, 16, 16, 0, 0, 16, 16);

    { Pass 3 (standalone DrawNoBatch -> Begin2DPass..End2DPass #3 at FFramePassBaseQuad = 2):
      Clipped sprite at (44, 4, 16, 16) with Clip = True and ClipLine = (1.0, 0.0, -0.5):
      dot((1,0), UV) - 0.5 = U - 0.5 < 0 is discarded -> Left half (U < 0.5) is discarded (Navy Blue),
      Right half (U > 0.5) is kept (Green)! }
    DrawImg.Alpha := acNone;
    DrawImg.Clip := True;
    DrawImg.ClipLine := Vector3(1.0, 0.0, -0.5);
    DrawImg.Draw(44, 4, 16, 16, 0, 0, 16, 16);
    DrawImg.Clip := False;

    { Pass 4 (explicit Begin2DPass..End2DPass #4 at FFramePassBaseQuad = 3):
      Font glyph mode (ATextureHasOnlyAlpha = True) at (4, 28, 16, 16) with Yellow ColorTint (1, 1, 0, 1):
      Even though FontAlphaImg has RGB=(0,0,0), TextureHasOnlyAlpha outputs vec4(ColorTint.rgb, ColorTint.a * tex.a)! }
    FontDrawImg.PrepareResources;
    Batch2D := EnsureBatch2DRenderer(RealDev);
    AssertEquals('After 3 single-quad 2D passes in same frame, FrameWriteQuadOffset must be 3',
      3, Integer(Batch2D.FrameWriteQuadOffset));
    Batch2D.Begin2DPass(RealCmd, 64, 64);
    SR := FloatRectangle(4, 28, 16, 16);
    IR := FloatRectangle(0, 0, 16, 16);
    Batch2D.DrawQuads(
      FontDrawImg.RHITexture, FontDrawImg.RHIDescriptorSet,
      @SR, @IR, 1,
      Vector4(1.0, 1.0, 0.0, 1.0),
      CastleInternalBatch2DRHI.bmAlphaBlend,
      False,
      Rectangle(0, 0, 64, 64),
      0.0, TVector2.Zero, False,
      False, TVector3.Zero, 0.0,
      False, bfSrcAlpha, bfOneMinusSrcAlpha,
      True, nil, TVector4.Zero);
    Batch2D.End2DPass;

    RealCmd.EndRendering;
    RealDev.EndFrameAndPresent;

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { 1. Verify Pass 1 at (4..20, 4..20): Left (6,10) = Red, Right (16,10) = Green }
    AssertEquals('Pass 1 Left (6,10) R must be 255', 255, Integer(Readback.PixelPtr(6, 10)^.X));
    AssertEquals('Pass 1 Left (6,10) G must be 0', 0, Integer(Readback.PixelPtr(6, 10)^.Y));
    AssertEquals('Pass 1 Right (16,10) R must be 0', 0, Integer(Readback.PixelPtr(16, 10)^.X));
    AssertEquals('Pass 1 Right (16,10) G must be 255', 255, Integer(Readback.PixelPtr(16, 10)^.Y));

    { 2. Verify Pass 2 (AlphaTest) at (24..40, 4..20): Left (26,10) = Red, Right (36,10) = Discarded (Navy Blue) }
    AssertEquals('Pass 2 AlphaTest Left (26,10) R must be 255', 255, Integer(Readback.PixelPtr(26, 10)^.X));
    AssertEquals('Pass 2 AlphaTest Right (36,10) G must be 0 (discarded)', 0, Integer(Readback.PixelPtr(36, 10)^.Y));
    AssertTrue('Pass 2 AlphaTest Right (36,10) B must remain Navy ~128',
      Abs(Integer(Readback.PixelPtr(36, 10)^.Z) - 128) <= 2);

    { 3. Verify Pass 3 (ClipLine U >= 0.5) at (44..60, 4..20): Left (46,10) = Discarded (Navy), Right (56,10) = Green }
    AssertEquals('Pass 3 ClipLine Left (46,10) R must be 0 (discarded)', 0, Integer(Readback.PixelPtr(46, 10)^.X));
    AssertTrue('Pass 3 ClipLine Left (46,10) B must remain Navy ~128',
      Abs(Integer(Readback.PixelPtr(46, 10)^.Z) - 128) <= 2);
    AssertEquals('Pass 3 ClipLine Right (56,10) G must be 255 (kept)', 255, Integer(Readback.PixelPtr(56, 10)^.Y));

    { 4. Verify Pass 4 (Font TextureHasOnlyAlpha) at (4..20, 28..44): Left (6,34) = Yellow (255,255,0), Right (16,34) = Navy }
    AssertEquals('Pass 4 Font Glyph Left (6,34) R must be 255', 255, Integer(Readback.PixelPtr(6, 34)^.X));
    AssertEquals('Pass 4 Font Glyph Left (6,34) G must be 255', 255, Integer(Readback.PixelPtr(6, 34)^.Y));
    AssertEquals('Pass 4 Font Glyph Left (6,34) B must be 0', 0, Integer(Readback.PixelPtr(6, 34)^.Z));
    AssertEquals('Pass 4 Font Glyph Right (16,34) R must be 0 (alpha 0)', 0, Integer(Readback.PixelPtr(16, 34)^.X));
    AssertTrue('Pass 4 Font Glyph Right (16,34) B must remain Navy ~128',
      Abs(Integer(Readback.PixelPtr(16, 34)^.Z) - 128) <= 2);
  finally
    FreeAndNil(Readback);
    FreeAndNil(FontDrawImg);
    FreeAndNil(DrawImg);
    FreeAndNil(ColorTex);
    FreeGlobalBatch2DRenderer;
    FreeAndNil(Container);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeRenderUnlitMeshDepthAndOcclusionCullingRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  ColorTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  UnlitMesh: TCastleRenderUnlitMesh;
  OccUtils: TOcclusionCullingUtilsRenderer;
  QueryPool: TRHIQueryPool;
  Samples: array[0..1] of UInt64;
  OrthoMVP: TMatrix4;
  Readback: TRGBAlphaImage;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := TTestSizedVulkanContainer.Create(nil);
  ColorTex := nil;
  DepthTex := nil;
  UnlitMesh := nil;
  OccUtils := nil;
  QueryPool := nil;
  Readback := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    Container.TestWidth := 64;
    Container.TestHeight := 64;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 64, 64);
    RenderContext.DepthTest := True;

    ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD32_Float,
      [tuDepthStencil]));
    QueryPool := RealDev.CreateQueryPool(TRHIQueryPoolDesc.Create(qtOcclusion, 2, 'UnlitOccPool'));

    OrthoMVP := OrthoProjection(FloatRectangle(0, 0, 64, 64), -10.0, 10.0);

    UnlitMesh := TCastleRenderUnlitMesh.Create(True);
    UnlitMesh.ModelViewProjection := OrthoMVP;
    UnlitMesh.SetIndexes([0, 1, 2, 0, 2, 3]);

    OccUtils := TOcclusionCullingUtilsRenderer.Create;
    OccUtils.ProjectionMatrix := OrthoMVP;
    OccUtils.CameraMatrix := TMatrix4.Identity;
    OccUtils.SceneMatrix := TMatrix4.Identity;

    RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    RealCmd.ResetQueryPool(QueryPool, 0, 2);

    { Draw 1 on UnlitMesh: Near Red quad at Z = -2.0 covering [8..40] x [8..40] }
    UnlitMesh.Color := Vector4(1.0, 0.0, 0.0, 1.0);
    UnlitMesh.SetVertexes([
      Vector4( 8,  8, -2.0, 1.0),
      Vector4(40,  8, -2.0, 1.0),
      Vector4(40, 40, -2.0, 1.0),
      Vector4( 8, 40, -2.0, 1.0)
    ], True);
    UnlitMesh.Render(pmTriangles);

    { Draw 2 on the SAME UnlitMesh in the SAME frame: Far Green quad at Z = -5.0 covering [24..56] x [8..40]
      - Proves dynamic vertex streaming on TCastleRenderUnlitMesh does NOT overwrite Draw 1's vertices!
      - Proves 3D depth test (with Vulkan [0,1] depth remap): overlap [24..40] stays Red, [40..56] is Green! }
    UnlitMesh.Color := Vector4(0.0, 1.0, 0.0, 1.0);
    UnlitMesh.SetVertexes([
      Vector4(24,  8, -5.0, 1.0),
      Vector4(56,  8, -5.0, 1.0),
      Vector4(56, 40, -5.0, 1.0),
      Vector4(24, 40, -5.0, 1.0)
    ], True);
    UnlitMesh.Render(pmTriangles);

    { Occlusion Query 0: Quad in front of Red quad (Z = -1.0 > -2.0, closer to camera) -> visible (Samples[0] > 0) }
    RenderContext.ColorChannels := [];
    RenderContext.DepthBufferUpdate := False;
    RealCmd.BeginQuery(QueryPool, 0, True);
    UnlitMesh.SetVertexes([
      Vector4(12, 12, -1.0, 1.0),
      Vector4(28, 12, -1.0, 1.0),
      Vector4(28, 28, -1.0, 1.0),
      Vector4(12, 28, -1.0, 1.0)
    ], True);
    UnlitMesh.Render(pmTriangles);
    RealCmd.EndQuery(QueryPool, 0);

    { Occlusion Query 1: Quad behind Red quad (Z = -8.0 < -2.0, further from camera) -> occluded (Samples[1] = 0) }
    RealCmd.BeginQuery(QueryPool, 1, True);
    UnlitMesh.SetVertexes([
      Vector4(12, 12, -8.0, 1.0),
      Vector4(28, 12, -8.0, 1.0),
      Vector4(28, 28, -8.0, 1.0),
      Vector4(12, 28, -8.0, 1.0)
    ], True);
    UnlitMesh.Render(pmTriangles);
    RealCmd.EndQuery(QueryPool, 1);

    RenderContext.ColorChannels := [0..3];
    RenderContext.DepthBufferUpdate := True;

    RealCmd.EndRendering;
    RealDev.EndFrameAndPresent;

    Samples[0] := 0;
    Samples[1] := High(UInt64);
    AssertTrue('Occlusion query GetResults must succeed',
      QueryPool.GetResults(0, 2, Samples, True));
    if RealDev.SupportsOcclusionQueryPrecise then
      AssertEquals('Front 16x16 unlit mesh precise occlusion query must pass 256 samples',
        256, Integer(Samples[0]))
    else
      AssertTrue('Front 16x16 unlit mesh boolean occlusion query must pass >= 1 sample',
        Samples[0] >= 1);
    AssertEquals('Occluded 16x16 unlit mesh behind Z=-2.0 quad must pass 0 samples',
      0, Integer(Samples[1]));

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Non-overlapping left part of Red quad (16, 24) -> Red (255, 0, 0) }
    AssertEquals('Left Red quad (16,24) R must be 255', 255, Integer(Readback.PixelPtr(16, 24)^.X));
    AssertEquals('Left Red quad (16,24) G must be 0', 0, Integer(Readback.PixelPtr(16, 24)^.Y));

    { Overlapping region [24..40] at (32, 24): Near Red (Z=-2) must occlude Far Green (Z=-5)! }
    AssertEquals('Overlap (32,24) R must remain 255 (Near Red occludes Far Green)',
      255, Integer(Readback.PixelPtr(32, 24)^.X));
    AssertEquals('Overlap (32,24) G must be 0',
      0, Integer(Readback.PixelPtr(32, 24)^.Y));

    { Non-overlapping right part of Green quad (48, 24) -> Green (0, 255, 0) }
    AssertEquals('Right Green quad (48,24) R must be 0', 0, Integer(Readback.PixelPtr(48, 24)^.X));
    AssertEquals('Right Green quad (48,24) G must be 255', 255, Integer(Readback.PixelPtr(48, 24)^.Y));
  finally
    FreeAndNil(Readback);
    FreeAndNil(OccUtils);
    FreeAndNil(UnlitMesh);
    FreeAndNil(QueryPool);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipe3DViewportUnlitAndLitMeshSceneRHI;
var
  Compiler: TCastleShaderCompiler;
  Spv3DVS, Spv3DFS, Spv3DTexFS, SpvVSMFS, SpvScreenVS, SpvScreenFS, SpvScreenInvFS: TSPIRVBytecode;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  ColorTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Viewport: TCastleViewport;
  SceneNearUnlit, SceneFarLit: TCastleScene;
  RootNear, RootFar: TX3DRootNode;
  TransNear, TransFar: TTransformNode;
  ShapeNear, ShapeFar: TShapeNode;
  BoxNear, BoxFar: TBoxNode;
  AppNear, AppFar: TAppearanceNode;
  UnlitMat: TUnlitMaterialNode;
  PhysMat: TPhysicalMaterialNode;
  DirLight: TDirectionalLightNode;
  Readback: TRGBAlphaImage;
begin
  { 1. Verify built-in SPIR-V compilation for 3D forward, textured, VSM & screen-effect shaders }
  Compiler := TCastleShaderCompiler.Create;
  try
    AssertTrue('TryGetBuiltInSPIRV CastleDefault3DVert',
      Compiler.TryGetBuiltInSPIRV(ssVertex, 'uniform CastleSceneBlock { mat4 u_ProjectionMatrix; };', 'CastleDefault3DVert', Spv3DVS));
    AssertTrue('TryGetBuiltInSPIRV CastleDefault3DFrag',
      Compiler.TryGetBuiltInSPIRV(ssFragment, 'uniform CastleMaterialBlock { vec4 u_BaseColor; };', 'CastleDefault3DFrag', Spv3DFS));
    AssertTrue('TryGetBuiltInSPIRV CastleShapeFrag_1 textured',
      Compiler.TryGetBuiltInSPIRV(ssFragment,
        'uniform CastleMaterialBlock { vec4 u_BaseColor; }; void main() { vec4 c = texture(castle_base_color_texture, uv); }',
        'CastleShapeFrag_1', Spv3DTexFS));
    AssertTrue('TryGetBuiltInSPIRV CastleVSMCasterFrag',
      Compiler.TryGetBuiltInSPIRV(ssFragment, 'void main() { out_Moments = vec4(depth, moment2, 0.0, 1.0); }', 'CastleVSMCasterFrag', SpvVSMFS));
    AssertTrue('TryGetBuiltInSPIRV ScreenDefaultVS',
      Compiler.TryGetBuiltInSPIRV(ssVertex, 'void main() { v_tex_coord = tex_coord; }', 'ScreenDefaultVS', SpvScreenVS));
    AssertTrue('TryGetBuiltInSPIRV ScreenDefaultFS',
      Compiler.TryGetBuiltInSPIRV(ssFragment, 'uniform sampler2D screen;', 'ScreenDefaultFS', SpvScreenFS));
    AssertTrue('TryGetBuiltInSPIRV ScreenEffectFS invert',
      Compiler.TryGetBuiltInSPIRV(ssFragment, 'uniform sampler2D screen; void main() { c = 1.0 - c; }', 'ScreenEffectFS', SpvScreenInvFS));

    AssertTrue('BuiltIn3DPosNormUVVertSPIRV must be > 400 bytes', Length(Spv3DVS) > 400);
    AssertTrue('BuiltIn3DForwardFragSPIRV must be > 500 bytes', Length(Spv3DFS) > 500);
    AssertTrue('BuiltIn3DForwardTexturedFragSPIRV must be > 500 bytes', Length(Spv3DTexFS) > 500);
    AssertTrue('BuiltInVSMCasterFragSPIRV must be > 80 bytes', Length(SpvVSMFS) > 80);
    AssertTrue('BuiltInScreenEffectVertSPIRV must be > 100 bytes', Length(SpvScreenVS) > 100);
    AssertTrue('BuiltInScreenEffectPassthroughFragSPIRV must be > 100 bytes', Length(SpvScreenFS) > 100);
    AssertTrue('BuiltInScreenEffectInvertFragSPIRV must be > 120 bytes', Length(SpvScreenInvFS) > 120);
  finally
    FreeAndNil(Compiler);
  end;

  { 2. Live 3D TCastleViewport / TCastleScene execution on Mesa Lavapipe }
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;

  Container := TTestSizedVulkanContainer.Create(nil);
  ColorTex := nil;
  DepthTex := nil;
  Viewport := nil;
  SceneNearUnlit := nil;
  SceneFarLit := nil;
  Readback := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    Container.TestWidth := 64;
    Container.TestHeight := 64;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 64, 64);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.Transparent := True;
    Viewport.Camera.ProjectionType := ptOrthographic;
    Viewport.Camera.Orthographic.Width := 4.0;
    Viewport.Camera.Orthographic.Height := 4.0;
    Viewport.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    { Scene 1: Near Unlit Red Box at X = -0.6, Z = 0.0 (covers X in [-1.35, +0.15]) }
    RootNear := TX3DRootNode.Create;
    TransNear := TTransformNode.Create;
    TransNear.Translation := Vector3(-0.6, 0.0, 0.0);
    ShapeNear := TShapeNode.Create;
    BoxNear := TBoxNode.Create;
    BoxNear.Size := Vector3(1.5, 1.5, 0.2);
    ShapeNear.Geometry := BoxNear;
    AppNear := TAppearanceNode.Create;
    UnlitMat := TUnlitMaterialNode.Create;
    UnlitMat.EmissiveColor := Vector3(1.0, 0.0, 0.0);
    AppNear.Material := UnlitMat;
    ShapeNear.Appearance := AppNear;
    TransNear.AddChildren(ShapeNear);
    RootNear.AddChildren(TransNear);
    SceneNearUnlit := TCastleScene.Create(nil);
    SceneNearUnlit.Load(RootNear, True);
    Viewport.Items.Add(SceneNearUnlit);

    { Scene 2: Far Lit Green Box at X = +0.6, Z = -2.0 (covers X in [-0.15, +1.35]) + DirectionalLight }
    RootFar := TX3DRootNode.Create;
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(0.0, 0.0, -1.0);
    DirLight.Color := Vector3(1.0, 1.0, 1.0);
    DirLight.Intensity := 1.0;
    DirLight.Global := True;
    RootFar.AddChildren(DirLight);

    TransFar := TTransformNode.Create;
    TransFar.Translation := Vector3(0.6, 0.0, -2.0);
    ShapeFar := TShapeNode.Create;
    BoxFar := TBoxNode.Create;
    BoxFar.Size := Vector3(1.5, 1.5, 0.2);
    ShapeFar.Geometry := BoxFar;
    AppFar := TAppearanceNode.Create;
    PhysMat := TPhysicalMaterialNode.Create;
    PhysMat.BaseColor := Vector3(0.0, 1.0, 0.0);
    AppFar.Material := PhysMat;
    ShapeFar.Appearance := AppFar;
    TransFar.AddChildren(ShapeFar);
    RootFar.AddChildren(TransFar);
    SceneFarLit := TCastleScene.Create(nil);
    SceneFarLit.Load(RootFar, True);
    {$warnings off}
    Viewport.Items.MainScene := SceneFarLit;
    {$warnings on}
    Viewport.Items.Add(SceneFarLit);

    ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD32_Float,
      [tuDepthStencil]));

    RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);

    Viewport.BeforeRender;

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(10 / 255.0, 20 / 255.0, 30 / 255.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);

    Viewport.Render;
    Viewport.RenderOverChildren;

    RealCmd.EndRendering;
    RealDev.EndFrameAndPresent;

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Corner (2, 2): Cleared background (10, 20, 30, 255) }
    AssertEquals('Corner (2,2) R must be 10', 10, Integer(Readback.PixelPtr(2, 2)^.X));
    AssertEquals('Corner (2,2) G must be 20', 20, Integer(Readback.PixelPtr(2, 2)^.Y));
    AssertEquals('Corner (2,2) B must be 30', 30, Integer(Readback.PixelPtr(2, 2)^.Z));

    { Left box (16, 32): Near Unlit Red box (255, 0, 0) }
    AssertEquals('Left Near Unlit Box (16,32) R must be 255', 255, Integer(Readback.PixelPtr(16, 32)^.X));
    AssertEquals('Left Near Unlit Box (16,32) G must be 0', 0, Integer(Readback.PixelPtr(16, 32)^.Y));
    AssertEquals('Left Near Unlit Box (16,32) B must be 0', 0, Integer(Readback.PixelPtr(16, 32)^.Z));

    { Center overlap (32, 32): Near Red box (Z=0) occludes Far Green box (Z=-2) via hardware depth buffer }
    AssertEquals('Center Overlap (32,32) R must be 255 (Near Red occludes Far Green)',
      255, Integer(Readback.PixelPtr(32, 32)^.X));
    AssertEquals('Center Overlap (32,32) G must be 0',
      0, Integer(Readback.PixelPtr(32, 32)^.Y));

    { Right box (48, 32): Far Lit Green PBR box illuminated by DirectionalLight (default Metallic=1, Roughness=1 GGX conductor: R=0, G>70, B=0) }
    AssertEquals('Right Far Lit Box (48,32) R must be 0', 0, Integer(Readback.PixelPtr(48, 32)^.X));
    AssertTrue('Right Far Lit PBR Box (48,32) G must be > 70', Readback.PixelPtr(48, 32)^.Y > 70);
    AssertEquals('Right Far Lit Box (48,32) B must be 0', 0, Integer(Readback.PixelPtr(48, 32)^.Z));
  finally
    FreeAndNil(Readback);
    FreeAndNil(SceneFarLit);
    FreeAndNil(SceneNearUnlit);
    FreeAndNil(Viewport);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipe3DViewportTexturedMeshAndAlphaCutoffRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  ColorTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Viewport: TCastleViewport;
  SceneBackBlue, SceneFrontMask: TCastleScene;
  RootBack, RootFront: TX3DRootNode;
  TransBack, TransFront: TTransformNode;
  ShapeBack, ShapeFront: TShapeNode;
  BoxBack, BoxFront: TBoxNode;
  AppBack, AppFront: TAppearanceNode;
  MatBack, MatFront: TUnlitMaterialNode;
  PixTex: TPixelTextureNode;
  TexImg: TRGBAlphaImage;
  X, Y: Integer;
  Readback: TRGBAlphaImage;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;

  Container := TTestSizedVulkanContainer.Create(nil);
  ColorTex := nil;
  DepthTex := nil;
  Viewport := nil;
  SceneBackBlue := nil;
  SceneFrontMask := nil;
  Readback := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    Container.TestWidth := 64;
    Container.TestHeight := 64;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 64, 64);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.Transparent := True;
    Viewport.Camera.ProjectionType := ptOrthographic;
    Viewport.Camera.Orthographic.Width := 4.0;
    Viewport.Camera.Orthographic.Height := 4.0;
    Viewport.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    { Far background scene at Z = -2.0: Solid Blue box }
    RootBack := TX3DRootNode.Create;
    TransBack := TTransformNode.Create;
    TransBack.Translation := Vector3(0.0, 0.0, -2.0);
    ShapeBack := TShapeNode.Create;
    BoxBack := TBoxNode.Create;
    BoxBack.Size := Vector3(3.0, 3.0, 0.2);
    ShapeBack.Geometry := BoxBack;
    AppBack := TAppearanceNode.Create;
    MatBack := TUnlitMaterialNode.Create;
    MatBack.EmissiveColor := Vector3(0.0, 0.0, 1.0);
    AppBack.Material := MatBack;
    ShapeBack.Appearance := AppBack;
    TransBack.AddChildren(ShapeBack);
    RootBack.AddChildren(TransBack);
    SceneBackBlue := TCastleScene.Create(nil);
    SceneBackBlue.Load(RootBack, True);
    Viewport.Items.Add(SceneBackBlue);

    { Near foreground scene at Z = 0.0: Textured Alpha-Cutoff box (left half opaque yellow, right half alpha=0) }
    RootFront := TX3DRootNode.Create;
    TransFront := TTransformNode.Create;
    TransFront.Translation := Vector3(0.0, 0.0, 0.0);
    ShapeFront := TShapeNode.Create;
    BoxFront := TBoxNode.Create;
    BoxFront.Size := Vector3(2.0, 2.0, 0.2);
    ShapeFront.Geometry := BoxFront;
    AppFront := TAppearanceNode.Create;
    AppFront.AlphaMode := amMask;
    AppFront.AlphaCutoff := 0.5;
    MatFront := TUnlitMaterialNode.Create;
    MatFront.EmissiveColor := Vector3(1.0, 1.0, 1.0);

    PixTex := TPixelTextureNode.Create;
    PixTex.RepeatS := False;
    PixTex.RepeatT := False;
    TexImg := TRGBAlphaImage.Create(64, 64);
    for Y := 0 to 63 do
      for X := 0 to 63 do
        if X < 32 then
          TexImg.PixelPtr(X, Y)^ := Vector4Byte(255, 255, 0, 255) { Opaque Yellow }
        else
          TexImg.PixelPtr(X, Y)^ := Vector4Byte(255, 0, 255, 0);  { Transparent (Alpha=0 < 0.5 -> OpKill) }
    PixTex.FdImage.Value := TexImg;
    MatFront.EmissiveTexture := PixTex;
    AppFront.Material := MatFront;
    ShapeFront.Appearance := AppFront;
    TransFront.AddChildren(ShapeFront);
    RootFront.AddChildren(TransFront);
    SceneFrontMask := TCastleScene.Create(nil);
    SceneFrontMask.Load(RootFront, True);
    Viewport.Items.Add(SceneFrontMask);

    ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD32_Float,
      [tuDepthStencil]));

    RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);

    Viewport.Render;

    RealCmd.EndRendering;
    RealDev.EndFrameAndPresent;

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Left half of front box at (24, 32): Opaque Yellow from texture (255, 255, 0) }
    AssertEquals('Left textured box (24,32) R must be 255', 255, Integer(Readback.PixelPtr(24, 32)^.X));
    AssertEquals('Left textured box (24,32) G must be 255', 255, Integer(Readback.PixelPtr(24, 32)^.Y));
    AssertEquals('Left textured box (24,32) B must be 0', 0, Integer(Readback.PixelPtr(24, 32)^.Z));

    { Right half of front box at (40, 32): Discarded by OpKill (alpha=0 < 0.5), revealing Far Blue box (0, 0, 255) }
    AssertEquals('Right alpha-discarded region (40,32) R must be 0', 0, Integer(Readback.PixelPtr(40, 32)^.X));
    AssertEquals('Right alpha-discarded region (40,32) G must be 0', 0, Integer(Readback.PixelPtr(40, 32)^.Y));
    AssertEquals('Right alpha-discarded region (40,32) B must be 255 (Far Blue box visible)',
      255, Integer(Readback.PixelPtr(40, 32)^.Z));
  finally
    FreeAndNil(Readback);
    FreeAndNil(SceneFrontMask);
    FreeAndNil(SceneBackBlue);
    FreeAndNil(Viewport);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeViewportScreenEffectPostProcessingRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  ColorTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  Box: TBoxNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  ScreenEffect: TScreenEffectNode;
  CompShader: TComposedShaderNode;
  FragPart: TShaderPartNode;
  DirectColorTex: TRHITexture;
  Readback, SrcReadback, DirectReadback: TRGBAlphaImage;
  DiagExtra: String;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;

  Container := TTestSizedVulkanContainer.Create(nil);
  ColorTex := nil;
  DepthTex := nil;
  DirectColorTex := nil;
  Viewport := nil;
  Scene := nil;
  Readback := nil;
  SrcReadback := nil;
  DirectReadback := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    Container.TestWidth := 64;
    Container.TestHeight := 64;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 64, 64);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(1.0, 0.0, 0.0, 1.0); { Red background -> inverted to Cyan (0, 255, 255) }
    Viewport.Camera.ProjectionType := ptOrthographic;
    Viewport.Camera.Orthographic.Width := 4.0;
    Viewport.Camera.Orthographic.Height := 4.0;
    Viewport.Camera.Orthographic.Origin := Vector2(0.5, 0.5);
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    { Scene with Blue Unlit Box in center (inverted to Yellow (255, 255, 0)) + TScreenEffectNode color inversion }
    Root := TX3DRootNode.Create;
    Shape := TShapeNode.Create;
    Box := TBoxNode.Create;
    Box.Size := Vector3(2.0, 2.0, 0.2);
    Shape.Geometry := Box;
    App := TAppearanceNode.Create;
    Mat := TUnlitMaterialNode.Create;
    Mat.EmissiveColor := Vector3(0.0, 0.0, 1.0); { Blue -> inverted to Yellow (255, 255, 0) }
    App.Material := Mat;
    Shape.Appearance := App;
    Root.AddChildren(Shape);

    ScreenEffect := TScreenEffectNode.Create;
    CompShader := TComposedShaderNode.Create;
    FragPart := TShaderPartNode.Create;
    FragPart.ShaderType := stFragment;
    FragPart.Contents := 'void main() { gl_FragColor = vec4(1.0 - screen_get_color(screen_position()).rgb, 1.0); }';
    CompShader.SetParts([FragPart]);
    ScreenEffect.SetShaders([CompShader]);
    Root.AddChildren(ScreenEffect);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}
    Viewport.Items.Add(Scene);

    ColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfD32_Float,
      [tuDepthStencil]));

    RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);

    Viewport.BeforeRender;

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.2, 0.0, 0.2, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);

    Viewport.Render;
    Viewport.RenderOverChildren;

    RealCmd.EndRendering;
    RealDev.EndFrameAndPresent;

    AssertEquals('ScreenEffect must execute 1 RHI post-processing pass',
      1, Integer(Viewport.RHIScreenPassCount));
    AssertTrue('Viewport.RHIScreenTextureSrc must be allocated',
      Viewport.RHIScreenTextureSrc <> nil);
    SrcReadback := RealDev.GrabTextureImage(Viewport.RHIScreenTextureSrc, Rectangle(0, 0, 64, 64));
    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Offscreen pre-effect SrcReadback: Red background (255,0,0) at (4,4), Blue box (0,0,255) at (32,32) }
    AssertEquals(Format('Offscreen ScreenEffect Src (4,4) R must be 255 [src=(%d,%d,%d,%d), srcCenter=(%d,%d,%d,%d)]', [
      SrcReadback.PixelPtr(4, 4)^.X, SrcReadback.PixelPtr(4, 4)^.Y, SrcReadback.PixelPtr(4, 4)^.Z, SrcReadback.PixelPtr(4, 4)^.W,
      SrcReadback.PixelPtr(32, 32)^.X, SrcReadback.PixelPtr(32, 32)^.Y, SrcReadback.PixelPtr(32, 32)^.Z, SrcReadback.PixelPtr(32, 32)^.W]),
      255, Integer(SrcReadback.PixelPtr(4, 4)^.X));
    AssertEquals('Offscreen ScreenEffect Src (32,32) B must be 255',
      255, Integer(SrcReadback.PixelPtr(32, 32)^.Z));

    DiagExtra := '';
    if Readback.PixelPtr(4, 4)^.Y <> 255 then
    begin
      DirectColorTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
        [tuColorAttachment, tuSampled, tuTransferSrc]));
      RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
      SetActiveCommandList(RealCmd);
      Viewport.ExecuteRHIScreenEffectPasses(
        [Viewport.GetScreenEffectRHIPipeline(0)], 64, 64, False, DirectColorTex, 0.1, 100.0);
      RealDev.EndFrameAndPresent;
      DirectReadback := RealDev.GrabTextureImage(DirectColorTex, Rectangle(0, 0, 64, 64));
      DiagExtra := Format(', direct=(%d,%d,%d,%d), pipeOk=%d', [
        DirectReadback.PixelPtr(4, 4)^.X, DirectReadback.PixelPtr(4, 4)^.Y,
        DirectReadback.PixelPtr(4, 4)^.Z, DirectReadback.PixelPtr(4, 4)^.W,
        Ord(Viewport.GetScreenEffectRHIPipeline(0) <> nil)]);
      FreeAndNil(DirectReadback);
      RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
      SetActiveCommandList(RealCmd);
      Viewport.ExecuteRHIScreenEffectPasses(
        [nil], 64, 64, False, DirectColorTex, 0.1, 100.0);
      RealDev.EndFrameAndPresent;
      DirectReadback := RealDev.GrabTextureImage(DirectColorTex, Rectangle(0, 0, 64, 64));
      DiagExtra := DiagExtra + Format(', defBuiltin=(%d,%d,%d,%d)', [
        DirectReadback.PixelPtr(4, 4)^.X, DirectReadback.PixelPtr(4, 4)^.Y,
        DirectReadback.PixelPtr(4, 4)^.Z, DirectReadback.PixelPtr(4, 4)^.W]);
    end;

    { Corner (4, 4): Viewport Red background (1, 0, 0) inverted by TScreenEffectNode -> Cyan (0, 255, 255) }
    AssertEquals(Format('Inverted background (4,4) R must be 0 [got RGBA=(%d,%d,%d,%d), center=(%d,%d,%d,%d), src=(%d,%d,%d,%d)%s]', [
      Readback.PixelPtr(4, 4)^.X, Readback.PixelPtr(4, 4)^.Y, Readback.PixelPtr(4, 4)^.Z, Readback.PixelPtr(4, 4)^.W,
      Readback.PixelPtr(32, 32)^.X, Readback.PixelPtr(32, 32)^.Y, Readback.PixelPtr(32, 32)^.Z, Readback.PixelPtr(32, 32)^.W,
      SrcReadback.PixelPtr(4, 4)^.X, SrcReadback.PixelPtr(4, 4)^.Y, SrcReadback.PixelPtr(4, 4)^.Z, SrcReadback.PixelPtr(4, 4)^.W,
      DiagExtra]),
      0, Integer(Readback.PixelPtr(4, 4)^.X));
    AssertEquals(Format('Inverted background (4,4) G must be 255 [got RGBA=(%d,%d,%d,%d), center=(%d,%d,%d,%d), src=(%d,%d,%d,%d)%s]', [
      Readback.PixelPtr(4, 4)^.X, Readback.PixelPtr(4, 4)^.Y, Readback.PixelPtr(4, 4)^.Z, Readback.PixelPtr(4, 4)^.W,
      Readback.PixelPtr(32, 32)^.X, Readback.PixelPtr(32, 32)^.Y, Readback.PixelPtr(32, 32)^.Z, Readback.PixelPtr(32, 32)^.W,
      SrcReadback.PixelPtr(4, 4)^.X, SrcReadback.PixelPtr(4, 4)^.Y, SrcReadback.PixelPtr(4, 4)^.Z, SrcReadback.PixelPtr(4, 4)^.W,
      DiagExtra]),
      255, Integer(Readback.PixelPtr(4, 4)^.Y));
    AssertEquals('Inverted background (4,4) B must be 255', 255, Integer(Readback.PixelPtr(4, 4)^.Z));

    { Center (32, 32): Blue 3D box (0, 0, 1) inverted by TScreenEffectNode -> Yellow (255, 255, 0) }
    AssertEquals('Inverted 3D Blue box (32,32) R must be 255', 255, Integer(Readback.PixelPtr(32, 32)^.X));
    AssertEquals('Inverted 3D Blue box (32,32) G must be 255', 255, Integer(Readback.PixelPtr(32, 32)^.Y));
    AssertEquals('Inverted 3D Blue box (32,32) B must be 0', 0, Integer(Readback.PixelPtr(32, 32)^.Z));
  finally
    FreeAndNil(DirectReadback);
    FreeAndNil(DirectColorTex);
    FreeAndNil(SrcReadback);
    FreeAndNil(Readback);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(Container);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

function TTestCastleVulkanRHI.CreateHeadlessSurfaceForTest(const AInstance: VkInstance): VkSurfaceKHR;
begin
  Result := CreateVulkanHeadlessSurface(AInstance);
end;

procedure TTestCastleVulkanRHI.TestVulkanSwapchainCompositeAlphaAndWSIExtensionDiscoveryRHI;
var
  HeadlessDesc: TVulkanNativeSurfaceDesc;
  HeadlessExts, FilteredExts: TAnsiStringArray;
  EnablePortability: Boolean;
  Dev: TVulkanRHIDevice;
  Cmd: TRHICommandList;
begin
  { 1. SelectVulkanCompositeAlpha preference chain }
  AssertEquals('Empty mask defaults to OPAQUE_BIT_KHR',
    VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    SelectVulkanCompositeAlpha(0));
  AssertEquals('OPAQUE + INHERIT prefers OPAQUE_BIT_KHR',
    VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    SelectVulkanCompositeAlpha(VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR or VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR));
  AssertEquals('PRE_MULTIPLIED + INHERIT prefers PRE_MULTIPLIED_BIT_KHR',
    VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
    SelectVulkanCompositeAlpha(VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR or VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR));
  AssertEquals('POST_MULTIPLIED + INHERIT prefers POST_MULTIPLIED_BIT_KHR',
    VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
    SelectVulkanCompositeAlpha(VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR or VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR));
  AssertEquals('INHERIT-only surface (e.g. Android/Wayland) selects INHERIT_BIT_KHR',
    VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    SelectVulkanCompositeAlpha(VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR));

  { 2. VK_EXT_headless_surface descriptor & extension table }
  HeadlessDesc := TVulkanNativeSurfaceDesc.CreateHeadless;
  AssertEquals('Headless WSI platform enum', Ord(vwsiHeadless), Ord(HeadlessDesc.Platform));
  AssertTrue('Headless surface descriptor must validate without OS window handles',
    ValidateVulkanNativeSurfaceDesc(HeadlessDesc));
  HeadlessExts := GetRequiredVulkanInstanceExtensionsForPlatform(vwsiHeadless);
  AssertEquals('vwsiHeadless requires 2 instance extensions', 2, Length(HeadlessExts));
  AssertEquals('vwsiHeadless ext[0] = VK_KHR_surface',
    String(VK_KHR_SURFACE_EXTENSION_NAME), String(HeadlessExts[0]));
  AssertEquals('vwsiHeadless ext[1] = VK_EXT_headless_surface',
    String(VK_EXT_HEADLESS_SURFACE_EXTENSION_NAME), String(HeadlessExts[1]));

  { 3. Loader-aware WSI extension filtering + VK_KHR_portability_enumeration }
  FilteredExts := BuildAvailableVulkanWSIInstanceExtensions(
    ['VK_KHR_surface', 'VK_EXT_headless_surface', 'VK_KHR_xlib_surface', 'VK_EXT_debug_utils'],
    EnablePortability);
  AssertFalse('Linux/Windows WSI list without portability extension keeps EnablePortability=False',
    EnablePortability);
  AssertEquals('Filtered WSI extensions count', 3, Length(FilteredExts));
  AssertEquals('FilteredExts[0]', 'VK_KHR_surface', String(FilteredExts[0]));
  AssertEquals('FilteredExts[1]', 'VK_KHR_xlib_surface', String(FilteredExts[1]));
  AssertEquals('FilteredExts[2]', 'VK_EXT_headless_surface', String(FilteredExts[2]));

  FilteredExts := BuildAvailableVulkanWSIInstanceExtensions(
    ['VK_KHR_surface', 'VK_EXT_metal_surface', 'VK_KHR_portability_enumeration'],
    EnablePortability);
  AssertTrue('MoltenVK portability enumeration enables VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR',
    EnablePortability);
  AssertEquals('MoltenVK filtered WSI extensions count', 3, Length(FilteredExts));

  FilteredExts := BuildAvailableVulkanWSIInstanceExtensions(
    ['VK_EXT_debug_utils'],
    EnablePortability);
  AssertFalse('Non-WSI loader keeps EnablePortability=False', EnablePortability);
  AssertEquals('Non-WSI loader returns 0 WSI extensions', 0, Length(FilteredExts));

  { 4. Minimized (0x0) swapchain lifecycle pause and unminimize recovery }
  Dev := TVulkanRHIDevice.CreateHeadless(nil);
  try
    Dev.SimulateSwapchainForTesting(128, 96, 3, pfBGRA8_UNorm, pfD24_UNorm_S8_UInt);
    AssertEquals('Initial simulated swapchain image count = 3', Cardinal(3), Dev.SwapchainImageCount);
    AssertFalse('Initial swapchain is not minimized', Dev.SwapchainMinimized);

    Dev.ResizeSwapchain(0, 0);
    AssertTrue('ResizeSwapchain(0, 0) marks swapchain minimized', Dev.SwapchainMinimized);
    Cmd := Dev.BeginFrame;
    AssertTrue('BeginFrame returns nil cleanly while swapchain is minimized', Cmd = nil);
    AssertFalse('Minimized BeginFrame leaves DeferResourceDestruction=False', Dev.DeferResourceDestruction);

    Dev.ResizeSwapchain(160, 120);
    AssertFalse('ResizeSwapchain(160, 120) clears minimized state', Dev.SwapchainMinimized);
    AssertEquals('Unminimized swapchain width', Cardinal(160), Dev.SwapchainExtent.width);
    AssertEquals('Unminimized swapchain height', Cardinal(120), Dev.SwapchainExtent.height);
    Cmd := Dev.BeginFrame;
    AssertTrue('BeginFrame succeeds after unminimize', Cmd <> nil);
    Dev.EndFrameAndPresent;
  finally
    FreeAndNil(Dev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealVulkanHeadlessSurfaceLiveSwapchainPresentAndResizeRHI;
var
  RealDev: TVulkanRHIDevice;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  Box: TBoxNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  RealCmd: TVulkanRHICommandList;
  ColorTex, DepthTex: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Readback1, Readback2: TRGBAlphaImage;
  FrameIdx: Integer;
begin
  try
    LoadVulkan;
  except
    on Exception do
      Exit;
  end;
  if not IsVulkanInstanceExtensionSupported(VK_EXT_HEADLESS_SURFACE_EXTENSION_NAME) then
    Exit;

  RealDev := nil;
  try
    RealDev := TVulkanRHIDevice.Create(
      {$ifdef FPC}@{$endif}CreateHeadlessSurfaceForTest, 128, 96, False);
  except
    on Exception do
    begin
      FreeAndNil(RealDev);
      Exit;
    end;
  end;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;
  Container := nil;
  Viewport := nil;
  Scene := nil;
  Readback1 := nil;
  Readback2 := nil;
  try
    AssertTrue('Live VK_EXT_headless_surface handle must be non-null',
      RealDev.SurfaceHandle <> VK_NULL_HANDLE);
    AssertTrue('Live VkSwapchainKHR handle must be non-null',
      RealDev.SwapchainHandle <> VK_NULL_HANDLE);
    AssertTrue('Live VkSwapchainKHR must allocate >= 2 swapchain images',
      RealDev.SwapchainImageCount >= 2);
    AssertEquals('Initial live swapchain width = 128', Cardinal(128), RealDev.SwapchainExtent.width);
    AssertEquals('Initial live swapchain height = 96', Cardinal(96), RealDev.SwapchainExtent.height);

    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);
    GLFeatures := nil;

    Container := TTestSizedVulkanContainer.Create(nil);
    Container.TestWidth := 128;
    Container.TestHeight := 96;
    RenderContext := Container.Context;

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.0, 0.0, 0.5, 1.0);
    Container.Controls.InsertFront(Viewport);
    Viewport.Camera.SetWorldView(
      Vector3(0.0, 0.0, 5.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    Root := TX3DRootNode.Create;
    Shape := TShapeNode.Create;
    Box := TBoxNode.Create;
    Box.Size := Vector3(2.5, 2.5, 0.5);
    Shape.Geometry := Box;
    App := TAppearanceNode.Create;
    Mat := TUnlitMaterialNode.Create;
    Mat.EmissiveColor := Vector3(0.0, 1.0, 0.0);
    App.Material := Mat;
    Shape.Appearance := App;
    Root.AddChildren(Shape);

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}
    Viewport.Items.Add(Scene);

    { Present 4 consecutive frames (exceeding MaxFramesInFlight=2 and cycling per-image semaphores) }
    for FrameIdx := 0 to 3 do
    begin
      RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
      AssertTrue('BeginFrame must acquire live swapchain image', RealCmd <> nil);
      SetActiveCommandList(RealCmd);

      Viewport.BeforeRender;
      ColorTex := RealDev.GetSwapchainColorTexture;
      DepthTex := RealDev.GetSwapchainDepthTexture;
      AssertTrue('Swapchain color texture must be non-nil', ColorTex <> nil);
      AssertTrue('Swapchain depth texture must be non-nil', DepthTex <> nil);

      PassInfo := RealDev.BuildSwapchainRenderingInfo(
        Rectangle(0, 0, 128, 96), ColorTex, DepthTex,
        Vector4(0.0, 0.0, 0.5, 1.0), loClear, loClear, 1.0);
      RealCmd.BeginRendering(PassInfo);
      RealCmd.SetViewport(FloatRectangle(0, 0, 128, 96), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(0, 0, 128, 96));

      Viewport.Render;
      Viewport.RenderOverChildren;
      RealCmd.EndRendering;

      if FrameIdx = 2 then
      begin
        { Read back frame 2 swapchain image before EndFrameAndPresent transitions it to PRESENT_SRC_KHR }
        RealDev.EndFrameAndPresent;
        Readback1 := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 128, 96));
      end else
        RealDev.EndFrameAndPresent;
    end;

    AssertEquals('4 frames presented before resize', Cardinal(4), RealDev.TotalFramesPresented);
    AssertTrue('Swapchain readback1 must succeed', Readback1 <> nil);
    AssertTrue('Center (64,48) green 3D box G > 200', Readback1.PixelPtr(64, 48)^.Y > 200);
    AssertEquals('Center (64,48) green 3D box R = 0', 0, Integer(Readback1.PixelPtr(64, 48)^.X));
    AssertTrue('Corner (4,4) navy background B > 100', Readback1.PixelPtr(4, 4)^.Z > 100);
    AssertEquals('Corner (4,4) navy background G = 0', 0, Integer(Readback1.PixelPtr(4, 4)^.Y));

    { Live swapchain resize (128x96 -> 192x144) exercising CreateInfo.oldSwapchain handoff }
    RealDev.ResizeSwapchain(192, 144);
    Container.TestWidth := 192;
    Container.TestHeight := 144;
    AssertTrue('Resized SwapchainHandle must remain valid', RealDev.SwapchainHandle <> VK_NULL_HANDLE);
    AssertEquals('Resized swapchain width = 192', Cardinal(192), RealDev.SwapchainExtent.width);
    AssertEquals('Resized swapchain height = 144', Cardinal(144), RealDev.SwapchainExtent.height);

    for FrameIdx := 0 to 1 do
    begin
      RealCmd := RealDev.BeginFrame as TVulkanRHICommandList;
      AssertTrue('Post-resize BeginFrame must acquire swapchain image', RealCmd <> nil);
      SetActiveCommandList(RealCmd);

      Viewport.BeforeRender;
      ColorTex := RealDev.GetSwapchainColorTexture;
      DepthTex := RealDev.GetSwapchainDepthTexture;
      PassInfo := RealDev.BuildSwapchainRenderingInfo(
        Rectangle(0, 0, 192, 144), ColorTex, DepthTex,
        Vector4(0.0, 0.0, 0.5, 1.0), loClear, loClear, 1.0);
      RealCmd.BeginRendering(PassInfo);
      RealCmd.SetViewport(FloatRectangle(0, 0, 192, 144), 0.0, 1.0);
      RealCmd.SetScissor(Rectangle(0, 0, 192, 144));

      Viewport.Render;
      Viewport.RenderOverChildren;
      RealCmd.EndRendering;
      RealDev.EndFrameAndPresent;
      if FrameIdx = 1 then
        Readback2 := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 192, 144));
    end;

    AssertEquals('6 total frames presented after resize', Cardinal(6), RealDev.TotalFramesPresented);
    AssertTrue('Post-resize readback2 must succeed', Readback2 <> nil);
    AssertEquals('Post-resize readback2 width = 192', 192, Readback2.Width);
    AssertEquals('Post-resize readback2 height = 144', 144, Readback2.Height);
    AssertTrue('Post-resize center (96,72) green 3D box G > 200', Readback2.PixelPtr(96, 72)^.Y > 200);
    AssertTrue('Post-resize corner (8,8) navy background B > 100', Readback2.PixelPtr(8, 8)^.Z > 100);
  finally
    FreeAndNil(Readback2);
    FreeAndNil(Readback1);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    GLFeatures := SavedGLFeatures;
    RenderContext := SavedCtx;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealCastleWindowPureVulkanOpenRenderResizeSaveScreenRHI;
var
  Window: TCastleWindow;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  Box: TBoxNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  DirLight: TDirectionalLightNode;
  VkDev: TVulkanRHIDevice;
  ShotRgb: TRGBImage;
  ShotRgba, ShotResized: TRGBAlphaImage;
  { defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {}
  I: Integer;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
  if not HasDisplay then
    Exit;
  {$endif}

  try
    LoadVulkan;
  except
    on Exception do
      Exit;
  end;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  Window := nil;
  ShotRgb := nil;
  ShotRgba := nil;
  ShotResized := nil;
  try
    SetActiveCommandList(nil);
    SetRHIDevice(nil);
    ApplicationProperties.RenderBackend := backendVulkan;
    Application.OnInitialize := nil;
    Application.Initialize;

    Window := CreateWindowForTest;
    Window.ResizeAllowed := raAllowed;
    Window.Width := 160;
    Window.Height := 120;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.0, 0.0, 0.6, 1.0);
    Window.Controls.InsertFront(Viewport);
    Viewport.Camera.SetWorldView(
      Vector3(0.0, 0.0, 4.5),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    Root := TX3DRootNode.Create;
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(0.0, 0.0, -1.0);
    DirLight.Intensity := 2.0;
    Root.AddChildren(DirLight);

    Shape := TShapeNode.Create;
    Box := TBoxNode.Create;
    Box.Size := Vector3(2.2, 2.2, 0.5);
    Shape.Geometry := Box;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(1.0, 0.25, 0.0);
    Mat.Roughness := 0.5;
    Mat.Metallic := 0.0;
    App.Material := Mat;
    Shape.Appearance := App;
    Root.AddChildren(Shape);

    Scene := TCastleScene.Create(Window);
    Scene.Load(Root, True);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}
    Viewport.Items.Add(Scene);

    Window.Open;
    if not (RHIDevice is TVulkanRHIDevice) then
    begin
      Window.Close(False);
      Exit;
    end;

    VkDev := TVulkanRHIDevice(RHIDevice);
    AssertTrue('Pure-Vulkan TCastleWindow must NOT initialize GLFeatures', GLFeatures = nil);
    AssertTrue('Pure-Vulkan TCastleWindow must NOT initialize GLVersion', GLVersion = nil);
    AssertTrue('Window.VulkanSurfaceHandle must be non-null',
      Window.VulkanSurfaceHandle <> VK_NULL_HANDLE);
    AssertTrue('TVulkanRHIDevice.SwapchainHandle must be non-null',
      VkDev.SwapchainHandle <> VK_NULL_HANDLE);

    for I := 0 to 2 do
    begin
      Window.Invalidate;
      Application.ProcessAllMessages;
    end;
    AssertTrue('Window must render >= 2 Vulkan frames (loading + ProcessAllMessages)',
      Window.VulkanFramesRenderedCount >= 2);

    { Test both TWindowContainer.SaveScreen (TRGBImage) and SaveScreenRgba }
    ShotRgb := Window.SaveScreen;
    AssertTrue('Window.SaveScreen must return non-nil TRGBImage', ShotRgb <> nil);
    AssertTrue(Format('Center lit PBR box R channel must dominate B channel in Window.SaveScreen [size=%dx%d, center=(%d,%d,%d), corner=(%d,%d,%d)]', [
      ShotRgb.Width, ShotRgb.Height,
      ShotRgb.PixelPtr(ShotRgb.Width div 2, ShotRgb.Height div 2)^.X,
      ShotRgb.PixelPtr(ShotRgb.Width div 2, ShotRgb.Height div 2)^.Y,
      ShotRgb.PixelPtr(ShotRgb.Width div 2, ShotRgb.Height div 2)^.Z,
      ShotRgb.PixelPtr(4, 4)^.X, ShotRgb.PixelPtr(4, 4)^.Y, ShotRgb.PixelPtr(4, 4)^.Z]),
      ShotRgb.PixelPtr(ShotRgb.Width div 2, ShotRgb.Height div 2)^.X >
      ShotRgb.PixelPtr(ShotRgb.Width div 2, ShotRgb.Height div 2)^.Z + 50);
    AssertTrue('Corner (4,4) blue viewport background B > 80 in Window.SaveScreen',
      ShotRgb.PixelPtr(4, 4)^.Z > 80);

    ShotRgba := Window.Container.SaveScreenRgba;
    AssertTrue('Container.SaveScreenRgba must return non-nil TRGBAlphaImage', ShotRgba <> nil);
    AssertTrue('Center lit PBR box R > 120 in SaveScreenRgba',
      ShotRgba.PixelPtr(ShotRgba.Width div 2, ShotRgba.Height div 2)^.X > 120);

    { Trigger live swapchain resize + ProcessAllMessages redraw + SaveScreenRgba }
    VkDev.ResizeSwapchain(200, 150);
    Window.Invalidate;
    Application.ProcessAllMessages;
    ShotResized := Window.Container.SaveScreenRgba;
    AssertTrue('Post-resize SaveScreenRgba must succeed', ShotResized <> nil);
    AssertTrue('Post-resize center lit PBR box R > 120',
      ShotResized.PixelPtr(ShotResized.Width div 2, ShotResized.Height div 2)^.X > 120);

    Window.Close(False);
    AssertTrue('Window.Close must release owned TVulkanRHIDevice', RHIDevice = nil);
    AssertTrue('Window.Close must clear VulkanSurfaceHandle',
      Window.VulkanSurfaceHandle = VK_NULL_HANDLE);
  finally
    FreeAndNil(ShotResized);
    FreeAndNil(ShotRgba);
    FreeAndNil(ShotRgb);
    if Window <> nil then
    begin
      if not Window.Closed then
        Window.Close(False);
      DestroyWindowForTest(Window);
    end;
    Application.OnInitialize := SavedOnInit;
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
  end;
end;

procedure TTestCastleVulkanRHI.ParallelQuadWorkerCallback(
  const AWorkerIndex: Cardinal; const ACommandList: TVulkanRHICommandList);
type
  TTestPrim2DPush = packed record
    ViewportSize: TVector2;
    PointSize: Single;
    Padding: Single;
    Color: TVector4;
  end;
var
  PushData: TTestPrim2DPush;
begin
  if ACommandList = nil then
    Exit;
  ACommandList.BeginSecondaryRecording(
    FParallelTestPassInfo,
    FloatRectangle(0, 0, 64, 64),
    Rectangle(0, 0, 64, 64),
    0.0, 1.0);
  if FParallelTestPipeline <> nil then
    ACommandList.BindPipeline(FParallelTestPipeline);
  if not FParallelTestHeadlessMode then
  begin
    if (AWorkerIndex <= High(FParallelTestQuadVBOs)) and
       (FParallelTestQuadVBOs[AWorkerIndex] <> nil) then
      ACommandList.BindVertexBuffers(0, [FParallelTestQuadVBOs[AWorkerIndex]], [0]);
    PushData.ViewportSize := Vector2(64.0, 64.0);
    PushData.PointSize := 1.0;
    PushData.Padding := 0.0;
    case AWorkerIndex of
      0: PushData.Color := Vector4(1.0, 0.0, 0.0, 1.0); { Bottom-Left: Red }
      1: PushData.Color := Vector4(0.0, 1.0, 0.0, 1.0); { Bottom-Right: Green }
      2: PushData.Color := Vector4(0.0, 0.0, 1.0, 1.0); { Top-Left: Blue }
    else
      PushData.Color := Vector4(1.0, 1.0, 0.0, 1.0);    { Top-Right: Yellow }
    end;
    ACommandList.PushConstants([ssVertex, ssFragment], 0, SizeOf(PushData), PushData);
    ACommandList.Draw(6, 1, 0, 0);
  end else
    ACommandList.Draw(3, 1, 0, 0);
  ACommandList.EndRecording;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeSecondaryCommandBuffersAndWorkerCommandPoolParallelDrawRHI;
type
  TTestPrim2DPush = packed record
    ViewportSize: TVector2;
    PointSize: Single;
    Padding: Single;
    Color: TVector4;
  end;
var
  HeadlessDev, RealDev: TVulkanRHIDevice;
  HeadlessCmd, RealCmd, ReusedSec0: TVulkanRHICommandList;
  HeadlessColor, HeadlessDepth: TRHITexture;
  ColorTex, DepthTex: TRHITexture;
  SecLists: TVulkanCommandListArray;
  VertSPIRV, FragSPIRV: TSPIRVBytecode;
  VS, FS: TRHIShaderModule;
  PipeDesc: TRHIGraphicsPipelineDesc;
  QuadVerts: array[0..5] of TVector2;
  CenterVBO: TRHIBuffer;
  CenterPush: TTestPrim2DPush;
  PassInfo: TRHIRenderingInfo;
  Readback: TRGBAlphaImage;
  DispatchedCount: Cardinal;
  MainTid: TThreadID;
  W: Integer;

  procedure FillQuadVerts(const X0, Y0, X1, Y1: Single);
  begin
    QuadVerts[0] := Vector2(X0, Y0);
    QuadVerts[1] := Vector2(X1, Y0);
    QuadVerts[2] := Vector2(X1, Y1);
    QuadVerts[3] := Vector2(X0, Y0);
    QuadVerts[4] := Vector2(X1, Y1);
    QuadVerts[5] := Vector2(X0, Y1);
  end;

begin
  { Part 1: Headless per-worker VkCommandPool manager & secondary command list lifecycle }
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(nil);
  HeadlessDev.SimulateSwapchainForTesting(64, 64, 2, pfBGRA8_UNorm, pfD24_UNorm_S8_UInt);
  HeadlessColor := nil;
  HeadlessDepth := nil;
  FParallelTestPipeline := nil;
  for W := 0 to 3 do
    FParallelTestQuadVBOs[W] := nil;
  try
    HeadlessDev.WorkerCommandPoolManager.WorkerCount := 4;
    AssertEquals('WorkerCount must be 4', 4, Integer(HeadlessDev.WorkerCommandPoolManager.WorkerCount));

    HeadlessColor := HeadlessDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment]));
    HeadlessDepth := HeadlessDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil]));

    HeadlessCmd := HeadlessDev.BeginFrame as TVulkanRHICommandList;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      HeadlessColor, loClear, Vector4(0.1, 0.1, 0.1, 1.0),
      HeadlessDepth, loClear, 1.0);
    HeadlessCmd.BeginRendering(PassInfo);

    FParallelTestPassInfo := PassInfo;
    FParallelTestPassInfo.ColorAttachments := Copy(PassInfo.ColorAttachments);
    FParallelTestPassInfo.ColorAttachments[0].LoadOp := loLoad;
    FParallelTestPassInfo.DepthAttachment.LoadOp := loLoad;
    FParallelTestPassInfo.ContentsSecondaryCommandBuffers := True;
    FParallelTestHeadlessMode := True;

    DispatchedCount := HeadlessDev.WorkerCommandPoolManager.ExecuteParallelRecording(
      4, @ParallelQuadWorkerCallback, SecLists);
    AssertEquals('ExecuteParallelRecording must return 4 secondary command lists',
      4, Integer(DispatchedCount));
    AssertEquals('Length(SecLists) must be 4', 4, Length(SecLists));
    for W := 0 to 3 do
    begin
      AssertTrue('Secondary list must be non-nil', SecLists[W] <> nil);
      AssertEquals('Secondary list level must be cllSecondary',
        Ord(cllSecondary), Ord(SecLists[W].Level));
    end;
    ReusedSec0 := SecLists[0] as TVulkanRHICommandList;

    HeadlessCmd.ExecuteSecondaryCommandsInPass(SecLists);
    AssertEquals('Primary SecondaryExecuteCount must be 4',
      4, Integer(HeadlessCmd.SecondaryExecuteCount));
    AssertTrue('Primary command list must resume active rendering pass after ExecuteSecondaryCommandsInPass',
      HeadlessCmd.IsRendering);
    HeadlessCmd.EndRendering;
    HeadlessDev.EndFrameAndPresent;

    { Cycle 1 intermediate frame (slot 1), then begin frame on slot 0 to verify O(1) pool reset reuse }
    HeadlessCmd := HeadlessDev.BeginFrame as TVulkanRHICommandList;
    HeadlessDev.EndFrameAndPresent;
    HeadlessCmd := HeadlessDev.BeginFrame as TVulkanRHICommandList;
    AssertEquals('Wrapped back to FrameIndex 0', 0, Integer(HeadlessDev.FrameIndex));
    AssertTrue('WorkerCommandPoolManager.TotalPoolResets must advance on BeginFrame',
      HeadlessDev.WorkerCommandPoolManager.TotalPoolResets >= 2);
    AssertTrue('Frame slot 0 secondary command list instance must be recycled without reallocation',
      HeadlessDev.WorkerCommandPoolManager.AcquireWorkerSecondaryCommandList(0) = ReusedSec0);
    HeadlessDev.EndFrameAndPresent;
  finally
    FreeAndNil(HeadlessDepth);
    FreeAndNil(HeadlessColor);
    FreeAndNil(HeadlessDev);
  end;

  { Part 2: Live Mesa Lavapipe Vulkan 1.4 multi-threaded secondary command buffer recording }
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  ColorTex := nil;
  DepthTex := nil;
  VS := nil;
  FS := nil;
  FParallelTestPipeline := nil;
  CenterVBO := nil;
  Readback := nil;
  for W := 0 to 3 do
    FParallelTestQuadVBOs[W] := nil;
  try
    AssertTrue('TryGetBuiltInSPIRV Primitive2D_VS',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, '', 'Primitive2D_VS', VertSPIRV));
    AssertTrue('TryGetBuiltInSPIRV Primitive2D_FS',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'Primitive2D_FS', FragSPIRV));

    VS := RealDev.CreateShaderModuleFromSPIRV(ssVertex, @VertSPIRV[0], Length(VertSPIRV), 'SecPrimVS');
    FS := RealDev.CreateShaderModuleFromSPIRV(ssFragment, @FragSPIRV[0], Length(FragSPIRV), 'SecPrimFS');

    FillChar(PipeDesc, SizeOf(PipeDesc), 0);
    PipeDesc.VertexShader := VS;
    PipeDesc.FragmentShader := FS;
    PipeDesc.Topology := ptTriangleList;
    SetLength(PipeDesc.VertexInput.Bindings, 1);
    PipeDesc.VertexInput.Bindings[0].Binding := 0;
    PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector2);
    PipeDesc.VertexInput.Bindings[0].PerInstance := False;
    SetLength(PipeDesc.VertexInput.Attributes, 1);
    PipeDesc.VertexInput.Attributes[0].Location := 0;
    PipeDesc.VertexInput.Attributes[0].Binding := 0;
    PipeDesc.VertexInput.Attributes[0].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[0].Offset := 0;
    PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    PipeDesc.Rasterizer.CullMode := cmNone;
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDepthTestWrite;
    PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    PipeDesc.PushConstantSize := SizeOf(TTestPrim2DPush);
    PipeDesc.PushConstantStages := [ssVertex, ssFragment];
    SetLength(PipeDesc.ColorAttachmentFormats, 1);
    PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
    PipeDesc.DepthAttachmentFormat := pfD32_Float;
    PipeDesc.SampleCount := 1;
    PipeDesc.DebugName := 'SecondaryWorkerQuadPSO';
    FParallelTestPipeline := RealDev.GetOrCreatePipeline(PipeDesc);

    { Allocate 4 quadrant VBOs + 1 center post-pass VBO }
    FillQuadVerts(4, 4, 28, 28);
    FParallelTestQuadVBOs[0] := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(QuadVerts), [buVertex], muCpuToGpu, 'QuadBL'), @QuadVerts[0]);
    FillQuadVerts(36, 4, 60, 28);
    FParallelTestQuadVBOs[1] := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(QuadVerts), [buVertex], muCpuToGpu, 'QuadBR'), @QuadVerts[0]);
    FillQuadVerts(4, 36, 28, 60);
    FParallelTestQuadVBOs[2] := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(QuadVerts), [buVertex], muCpuToGpu, 'QuadTL'), @QuadVerts[0]);
    FillQuadVerts(36, 36, 60, 60);
    FParallelTestQuadVBOs[3] := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(QuadVerts), [buVertex], muCpuToGpu, 'QuadTR'), @QuadVerts[0]);
    FillQuadVerts(28, 28, 36, 36);
    CenterVBO := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(QuadVerts), [buVertex], muCpuToGpu, 'QuadCenter'), @QuadVerts[0]);

    ColorTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil]));

    RealDev.WorkerCommandPoolManager.WorkerCount := 4;
    RealDev.WorkerCommandPoolManager.UseWorkerThreads := True;
    MainTid := GetCurrentThreadId;

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.1, 0.1, 0.1, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);

    FParallelTestPassInfo := PassInfo;
    FParallelTestPassInfo.ColorAttachments := Copy(PassInfo.ColorAttachments);
    FParallelTestPassInfo.ColorAttachments[0].LoadOp := loLoad;
    FParallelTestPassInfo.DepthAttachment.LoadOp := loLoad;
    FParallelTestPassInfo.ContentsSecondaryCommandBuffers := True;
    FParallelTestHeadlessMode := False;

    DispatchedCount := RealDev.WorkerCommandPoolManager.ExecuteParallelRecording(
      4, @ParallelQuadWorkerCallback, SecLists);
    AssertEquals('Real Lavapipe ExecuteParallelRecording must record 4 secondary lists',
      4, Integer(DispatchedCount));

    for W := 0 to 3 do
    begin
      AssertTrue('Each worker must own a non-null VkCommandPool',
        RealDev.WorkerCommandPoolManager.GetWorkerCommandPool(Cardinal(W), RealDev.FrameIndex) <> VK_NULL_HANDLE);
      if W > 0 then
        AssertTrue('Each worker must own a distinct VkCommandPool from worker 0',
          RealDev.WorkerCommandPoolManager.GetWorkerCommandPool(Cardinal(W), RealDev.FrameIndex) <>
          RealDev.WorkerCommandPoolManager.GetWorkerCommandPool(0, RealDev.FrameIndex));
      {$ifndef CASTLE_DISABLE_THREADS}
      if RealDev.WorkerCommandPoolManager.ThreadsSpawned then
        AssertTrue('Worker secondary command buffer must be recorded on OS worker thread <> MainThread',
          RealDev.WorkerCommandPoolManager.GetWorkerLastThreadId(Cardinal(W)) <> MainTid);
      {$endif}
    end;

    { Execute all 4 secondary command buffers inside VK_RENDERING_CONTENTS_SECONDARY_COMMAND_BUFFERS_BIT }
    RealCmd.ExecuteSecondaryCommandsInPass(SecLists);

    { Draw a small White quad inline in the resumed primary rendering pass }
    RealCmd.BindPipeline(FParallelTestPipeline);
    RealCmd.BindVertexBuffers(0, [CenterVBO], [0]);
    CenterPush.ViewportSize := Vector2(64.0, 64.0);
    CenterPush.PointSize := 1.0;
    CenterPush.Padding := 0.0;
    CenterPush.Color := Vector4(1.0, 1.0, 1.0, 1.0);
    RealCmd.PushConstants([ssVertex, ssFragment], 0, SizeOf(CenterPush), CenterPush);
    RealCmd.Draw(6, 1, 0, 0);

    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Worker 0 Bottom-Left (16, 16) = Red (255, 0, 0) }
    AssertEquals('Worker 0 BL (16,16) R', 255, Integer(Readback.PixelPtr(16, 16)^.X));
    AssertEquals('Worker 0 BL (16,16) G', 0, Integer(Readback.PixelPtr(16, 16)^.Y));
    AssertEquals('Worker 0 BL (16,16) B', 0, Integer(Readback.PixelPtr(16, 16)^.Z));

    { Worker 1 Bottom-Right (48, 16) = Green (0, 255, 0) }
    AssertEquals('Worker 1 BR (48,16) R', 0, Integer(Readback.PixelPtr(48, 16)^.X));
    AssertEquals('Worker 1 BR (48,16) G', 255, Integer(Readback.PixelPtr(48, 16)^.Y));
    AssertEquals('Worker 1 BR (48,16) B', 0, Integer(Readback.PixelPtr(48, 16)^.Z));

    { Worker 2 Top-Left (16, 48) = Blue (0, 0, 255) }
    AssertEquals('Worker 2 TL (16,48) R', 0, Integer(Readback.PixelPtr(16, 48)^.X));
    AssertEquals('Worker 2 TL (16,48) G', 0, Integer(Readback.PixelPtr(16, 48)^.Y));
    AssertEquals('Worker 2 TL (16,48) B', 255, Integer(Readback.PixelPtr(16, 48)^.Z));

    { Worker 3 Top-Right (48, 48) = Yellow (255, 255, 0) }
    AssertEquals('Worker 3 TR (48,48) R', 255, Integer(Readback.PixelPtr(48, 48)^.X));
    AssertEquals('Worker 3 TR (48,48) G', 255, Integer(Readback.PixelPtr(48, 48)^.Y));
    AssertEquals('Worker 3 TR (48,48) B', 0, Integer(Readback.PixelPtr(48, 48)^.Z));

    { Resumed Primary Inline Center (32, 32) = White (255, 255, 255) }
    AssertEquals('Resumed inline center (32,32) R', 255, Integer(Readback.PixelPtr(32, 32)^.X));
    AssertEquals('Resumed inline center (32,32) G', 255, Integer(Readback.PixelPtr(32, 32)^.Y));
    AssertEquals('Resumed inline center (32,32) B', 255, Integer(Readback.PixelPtr(32, 32)^.Z));

    { Preserved initial clear background at (2, 32) ~ (25, 25, 25) }
    AssertTrue('Initial clear background (2,32) must remain dark gray',
      (Readback.PixelPtr(2, 32)^.X >= 20) and (Readback.PixelPtr(2, 32)^.X <= 30) and
      (Readback.PixelPtr(2, 32)^.Y >= 20) and (Readback.PixelPtr(2, 32)^.Y <= 30));
  finally
    FreeAndNil(Readback);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(CenterVBO);
    for W := 0 to 3 do
      FreeAndNil(FParallelTestQuadVBOs[W]);
    FParallelTestPipeline := nil;
    FreeAndNil(FS);
    FreeAndNil(VS);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeViewportParallelCommandRecording3DSceneParityRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedCtx: TRenderContext;
  SavedGLFeatures: TGLFeatures;
  Container: TTestSizedVulkanContainer;
  ColorTexSerial, DepthTexSerial: TRHITexture;
  ColorTexParallel, DepthTexParallel: TRHITexture;
  PassInfo: TRHIRenderingInfo;
  Viewport: TCastleViewport;
  Scene: TCastleScene;
  Root: TX3DRootNode;
  DirLight: TDirectionalLightNode;
  Trans: TTransformNode;
  Shape: TShapeNode;
  Box: TBoxNode;
  Sphere: TSphereNode;
  App: TAppearanceNode;
  PhysMat: TPhysicalMaterialNode;
  UnlitMat: TUnlitMaterialNode;
  ImgSerial, ImgParallel: TRGBAlphaImage;
  DiffRMSE: Single;
  I, FrameIter: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedCtx := RenderContext;
  SavedGLFeatures := GLFeatures;

  Container := TTestSizedVulkanContainer.Create(nil);
  ColorTexSerial := nil;
  DepthTexSerial := nil;
  ColorTexParallel := nil;
  DepthTexParallel := nil;
  Viewport := nil;
  Scene := nil;
  ImgSerial := nil;
  ImgParallel := nil;
  try
    GLFeatures := nil;
    ApplicationProperties.RenderBackend := backendVulkan;
    SetRHIDevice(RealDev);

    Container.TestWidth := 128;
    Container.TestHeight := 128;
    RenderContext := Container.Context;
    RenderContext.Viewport := Rectangle(0, 0, 128, 128);

    Viewport := TCastleViewport.Create(nil);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.05, 0.08, 0.16, 1.0);
    Viewport.Camera.ProjectionType := ptPerspective;
    Viewport.Camera.Perspective.FieldOfView := Pi / 3.0;
    Viewport.Camera.SetView(
      Vector3(0.0, 0.0, 9.5),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));
    Container.Controls.InsertFront(Viewport);

    { Build a 3D scene with 12 distinct shapes (4x3 grid of lit PBR boxes & spheres + unlit accents) }
    Root := TX3DRootNode.Create;
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(-0.35, -0.5, -0.8).Normalize;
    DirLight.Intensity := 1.4;
    DirLight.Global := True;
    Root.AddChildren(DirLight);

    for I := 0 to 11 do
    begin
      Trans := TTransformNode.Create;
      Trans.Translation := Vector3(
        ((I mod 4) - 1.5) * 2.1,
        ((I div 4) - 1.0) * 2.1,
        -0.3 * Single(I mod 3));
      Shape := TShapeNode.Create;
      if (I mod 2) = 0 then
      begin
        Box := TBoxNode.Create;
        Box.Size := Vector3(1.3, 1.3, 1.3);
        Shape.Geometry := Box;
      end else
      begin
        Sphere := TSphereNode.Create;
        Sphere.Radius := 0.72;
        Shape.Geometry := Sphere;
      end;

      App := TAppearanceNode.Create;
      if (I mod 4) = 3 then
      begin
        UnlitMat := TUnlitMaterialNode.Create;
        UnlitMat.EmissiveColor := Vector3(
          0.2 + 0.06 * Single(I),
          0.85 - 0.05 * Single(I),
          0.4 + 0.04 * Single(I));
        App.Material := UnlitMat;
      end else
      begin
        PhysMat := TPhysicalMaterialNode.Create;
        PhysMat.BaseColor := Vector3(
          0.15 + 0.07 * Single(I),
          0.25 + 0.05 * Single(11 - I),
          0.35 + 0.05 * Single((I * 3) mod 11));
        PhysMat.Roughness := 0.35 + 0.04 * Single(I mod 5);
        PhysMat.Metallic := 0.1 * Single(I mod 3);
        App.Material := PhysMat;
      end;
      Shape.Appearance := App;
      Trans.AddChildren(Shape);
      Root.AddChildren(Trans);
    end;

    Scene := TCastleScene.Create(nil);
    Scene.Load(Root, True);
    {$warnings off}
    Viewport.Items.MainScene := Scene;
    {$warnings on}
    Viewport.Items.Add(Scene);

    ColorTexSerial := RealDev.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm,
      [tuColorAttachment, tuTransferSrc]));
    DepthTexSerial := RealDev.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfD32_Float,
      [tuDepthStencil]));
    ColorTexParallel := RealDev.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfRGBA8_UNorm,
      [tuColorAttachment, tuTransferSrc]));
    DepthTexParallel := RealDev.CreateTexture(TRHITextureDesc.Create2D(128, 128, pfD32_Float,
      [tuDepthStencil]));

    { 1. Render Serial Baseline (ParallelCommandRecording = False) }
    Viewport.ParallelCommandRecording := False;
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    SetActiveCommandList(RealCmd);
    Viewport.BeforeRender;
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 128, 128),
      ColorTexSerial, loClear, Viewport.BackgroundColor,
      DepthTexSerial, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Viewport.Render;
    Viewport.RenderOverChildren;
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    AssertEquals('Serial render must have TotalParallelPassCount = 0',
      0, Integer(Viewport.InternalShapesRenderer.TotalParallelPassCount));
    ImgSerial := RealDev.GrabTextureImage(ColorTexSerial, Rectangle(0, 0, 128, 128));

    { 2. Render Multi-Threaded Parallel Secondary Command Recording across 4 workers (2 frames for slot wrap) }
    Viewport.ParallelCommandRecording := True;
    Viewport.ParallelCommandRecordingMinShapes := 4;
    Viewport.ParallelCommandRecordingWorkerCount := 4;

    for FrameIter := 0 to 1 do
    begin
      RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
      SetActiveCommandList(RealCmd);
      Viewport.BeforeRender;
      PassInfo := TRHIRenderingInfo.CreateColorDepth(
        Rectangle(0, 0, 128, 128),
        ColorTexParallel, loClear, Viewport.BackgroundColor,
        DepthTexParallel, loClear, 1.0);
      RealCmd.BeginRendering(PassInfo);
      Viewport.Render;
      Viewport.RenderOverChildren;
      RealCmd.EndRendering;
      RealDev.EndOffscreenFrame;
    end;

    AssertTrue('TotalParallelPassCount must be >= 2 after 2 parallel frames',
      Viewport.InternalShapesRenderer.TotalParallelPassCount >= 2);
    AssertEquals('LastParallelRecordedShapes must equal 12 collected shapes',
      12, Integer(Viewport.InternalShapesRenderer.LastParallelRecordedShapes));
    AssertEquals('LastParallelWorkerCount must equal 4 workers',
      4, Integer(Viewport.InternalShapesRenderer.LastParallelWorkerCount));

    ImgParallel := RealDev.GrabTextureImage(ColorTexParallel, Rectangle(0, 0, 128, 128));
    AssertTrue('Parallel 4-worker secondary command buffer 3D scene render must match serial render (RMSE <= 0.001)',
      CompareImagesPerceptualDiff(ImgSerial, ImgParallel, 0.001, DiffRMSE));
  finally
    FreeAndNil(ImgParallel);
    FreeAndNil(ImgSerial);
    FreeAndNil(DepthTexParallel);
    FreeAndNil(ColorTexParallel);
    FreeAndNil(DepthTexSerial);
    FreeAndNil(ColorTexSerial);
    FreeAndNil(Scene);
    FreeAndNil(Viewport);
    FreeAndNil(Container);
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    RenderContext := SavedCtx;
    GLFeatures := SavedGLFeatures;
    ApplicationProperties.RenderBackend := SavedBackend;
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeAsyncTransferQueueTimelineSemaphoreUploadAndRenderRHI;
var
  HeadlessDev, RealDev: TVulkanRHIDevice;
  HeadlessCmd, RealCmd: TVulkanRHICommandList;
  HeadlessBuf: TVulkanRHIBuffer;
  HeadlessTex: TVulkanRHITexture;
  DummyVerts: array[0..5] of TVector2;
  DummyPixels: array[0..15] of TVector4Byte;
  SubmittedVal: UInt64;
  GpuVBO: TVulkanRHIBuffer;
  GpuTex: TVulkanRHITexture;
  ColorTex, DepthTex: TRHITexture;
  Sampler: TRHISampler;
  SamplerDesc: TRHISamplerDesc;
  VertSPIRV, FragSPIRV: TSPIRVBytecode;
  VS, FS: TRHIShaderModule;
  SetLayout: TRHIDescriptorSetLayout;
  BindingDesc: TRHIDescriptorBindingDesc;
  DescSet: TRHIDescriptorSet;
  PipeDesc: TRHIGraphicsPipelineDesc;
  Pipe: TRHIPipeline;
  Quad2DVerts: array[0..5] of TCastle2DVertex;
  Push2D: TCastle2DPushConstants;
  PassInfo: TRHIRenderingInfo;
  SrcPixels: array[0 .. 32 * 32 - 1] of TVector4Byte;
  Readback: TRGBAlphaImage;
  I: Integer;
begin
  { Part 1: Headless dedicated DMA transfer queue ownership release + graphics acquire accounting }
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(nil);
  HeadlessDev.SimulateSwapchainForTesting(64, 64, 2, pfBGRA8_UNorm, pfD24_UNorm_S8_UInt);
  HeadlessBuf := nil;
  HeadlessTex := nil;
  try
    HeadlessDev.StagingUploader.ConfigureTransferQueue(0, 2, True);
    AssertTrue('UseDedicatedTransferQueue must be True',
      HeadlessDev.StagingUploader.UseDedicatedTransferQueue);

    for I := 0 to High(DummyVerts) do
      DummyVerts[I] := Vector2(Single(I), Single(I * 2));
    for I := 0 to High(DummyPixels) do
      DummyPixels[I] := Vector4Byte(0, 220, 80, 255);

    HeadlessBuf := HeadlessDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(DummyVerts), [buVertex, buTransferDst], muGpuOnly, 'AsyncBuf')) as TVulkanRHIBuffer;
    HeadlessTex := HeadlessDev.CreateTexture(
      TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst])) as TVulkanRHITexture;

    HeadlessDev.StagingUploader.EnqueueBufferUpload(HeadlessBuf, DummyVerts[0], SizeOf(DummyVerts), 0);
    HeadlessDev.StagingUploader.EnqueueImageUpload(HeadlessTex, @DummyPixels[0], SizeOf(DummyPixels), 4, 4, 0, 0, False);
    AssertEquals('PendingBufferCopyCount must be 1', 1, Integer(HeadlessDev.StagingUploader.PendingBufferCopyCount));
    AssertEquals('PendingImageCopyCount must be 1', 1, Integer(HeadlessDev.StagingUploader.PendingImageCopyCount));

    SubmittedVal := HeadlessDev.StagingUploader.SubmitAsyncUploads;
    AssertEquals('First SubmitAsyncUploads must signal timeline value 1', Int64(1), Int64(SubmittedVal));
    AssertEquals('TotalAsyncSubmissions must be 1', 1, Integer(HeadlessDev.StagingUploader.TotalAsyncSubmissions));
    AssertEquals('PendingGraphicsWaitTimelineValue must be 1',
      Int64(1), Int64(HeadlessDev.StagingUploader.PendingGraphicsWaitTimelineValue));
    AssertEquals('Release barriers on dedicated transfer queue must increment QueueOwnershipTransferCount by 2',
      2, Integer(HeadlessDev.StagingUploader.QueueOwnershipTransferCount));

    HeadlessCmd := HeadlessDev.BeginFrame as TVulkanRHICommandList;
    AssertTrue('BeginFrame must automatically record the 2 pending acquire barriers onto HeadlessCmd',
      HeadlessCmd.BarrierCount >= 2);
    AssertEquals('BeginFrame acquire barriers must increment QueueOwnershipTransferCount from 2 to 4',
      4, Integer(HeadlessDev.StagingUploader.QueueOwnershipTransferCount));
    AssertEquals('Subsequent ApplyPendingGraphicsAcquireBarriers must apply 0 duplicate barriers',
      0, Integer(HeadlessDev.StagingUploader.ApplyPendingGraphicsAcquireBarriers(HeadlessCmd)));
    HeadlessDev.EndFrameAndPresent;
    AssertEquals('EndFrameAndPresent must consume PendingGraphicsWaitTimelineValue',
      Int64(0), Int64(HeadlessDev.StagingUploader.PendingGraphicsWaitTimelineValue));
  finally
    FreeAndNil(HeadlessTex);
    FreeAndNil(HeadlessBuf);
    FreeAndNil(HeadlessDev);
  end;

  { Part 2: Live Mesa Lavapipe Vulkan 1.4 async TransferQueue submit + VkTimelineSemaphoreSubmitInfo graphics wait }
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  GpuVBO := nil;
  GpuTex := nil;
  ColorTex := nil;
  DepthTex := nil;
  Sampler := nil;
  VS := nil;
  FS := nil;
  SetLayout := nil;
  DescSet := nil;
  Readback := nil;
  try
    { Prepare emerald green (16, 224, 96, 255) 32x32 texture & full-screen NDC+UV quad }
    for I := 0 to High(SrcPixels) do
      SrcPixels[I] := Vector4Byte(16, 224, 96, 255);

    Quad2DVerts[0].Position := Vector2(8.0, 8.0);   Quad2DVerts[0].TexCoord := Vector2(0.0, 0.0); Quad2DVerts[0].ColorRgba8 := $FFFFFFFF;
    Quad2DVerts[1].Position := Vector2(56.0, 8.0);  Quad2DVerts[1].TexCoord := Vector2(1.0, 0.0); Quad2DVerts[1].ColorRgba8 := $FFFFFFFF;
    Quad2DVerts[2].Position := Vector2(56.0, 56.0); Quad2DVerts[2].TexCoord := Vector2(1.0, 1.0); Quad2DVerts[2].ColorRgba8 := $FFFFFFFF;
    Quad2DVerts[3].Position := Vector2(8.0, 8.0);   Quad2DVerts[3].TexCoord := Vector2(0.0, 0.0); Quad2DVerts[3].ColorRgba8 := $FFFFFFFF;
    Quad2DVerts[4].Position := Vector2(56.0, 56.0); Quad2DVerts[4].TexCoord := Vector2(1.0, 1.0); Quad2DVerts[4].ColorRgba8 := $FFFFFFFF;
    Quad2DVerts[5].Position := Vector2(8.0, 56.0);  Quad2DVerts[5].TexCoord := Vector2(0.0, 1.0); Quad2DVerts[5].ColorRgba8 := $FFFFFFFF;

    { Allocate uninitialized muGpuOnly buffer & texture }
    GpuVBO := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(SizeOf(Quad2DVerts), [buVertex, buTransferDst], muGpuOnly, 'LiveAsyncVBO')) as TVulkanRHIBuffer;
    GpuTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuSampled, tuTransferDst])) as TVulkanRHITexture;

    { Build zero-dependency built-in CastleBatch2D SPIR-V textured quad pipeline to sample GpuTex using GpuVBO }
    AssertTrue('TryGetBuiltInSPIRV CastleBatch2D.vert',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssVertex, '', 'CastleBatch2D.vert', VertSPIRV));
    AssertTrue('TryGetBuiltInSPIRV CastleBatch2D.frag',
      TCastleShaderCompiler.Instance.TryGetBuiltInSPIRV(ssFragment, '', 'CastleBatch2D.frag', FragSPIRV));
    VS := RealDev.CreateShaderModuleFromSPIRV(ssVertex, @VertSPIRV[0], Length(VertSPIRV), 'CastleBatch2D.vert');
    FS := RealDev.CreateShaderModuleFromSPIRV(ssFragment, @FragSPIRV[0], Length(FragSPIRV), 'CastleBatch2D.frag');

    FillChar(BindingDesc, SizeOf(BindingDesc), 0);
    BindingDesc.Binding := 0;
    BindingDesc.DescriptorType := dtCombinedImageSampler;
    BindingDesc.Count := 1;
    BindingDesc.StageFlags := [ssFragment];
    SetLayout := RealDev.CreateDescriptorSetLayout([BindingDesc]);

    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfLinear;
    SamplerDesc.MagFilter := sfLinear;
    SamplerDesc.MipFilter := sfNearest;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxLod := 1000.0;
    Sampler := RealDev.CreateSampler(SamplerDesc);

    DescSet := RealDev.CreateDescriptorSet(SetLayout);
    DescSet.BindTexture(0, GpuTex, Sampler);
    DescSet.Update;

    FillChar(PipeDesc, SizeOf(PipeDesc), 0);
    PipeDesc.VertexShader := VS;
    PipeDesc.FragmentShader := FS;
    PipeDesc.Topology := ptTriangleList;
    SetLength(PipeDesc.VertexInput.Bindings, 1);
    PipeDesc.VertexInput.Bindings[0].Binding := 0;
    PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TCastle2DVertex);
    PipeDesc.VertexInput.Bindings[0].PerInstance := False;
    SetLength(PipeDesc.VertexInput.Attributes, 3);
    PipeDesc.VertexInput.Attributes[0].Location := 0;
    PipeDesc.VertexInput.Attributes[0].Binding := 0;
    PipeDesc.VertexInput.Attributes[0].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[0].Offset := 0;
    PipeDesc.VertexInput.Attributes[1].Location := 2;
    PipeDesc.VertexInput.Attributes[1].Binding := 0;
    PipeDesc.VertexInput.Attributes[1].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[1].Offset := 8;
    PipeDesc.VertexInput.Attributes[2].Location := 4;
    PipeDesc.VertexInput.Attributes[2].Binding := 0;
    PipeDesc.VertexInput.Attributes[2].Format := vafUByte4Normalized;
    PipeDesc.VertexInput.Attributes[2].Offset := 16;
    PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    PipeDesc.Rasterizer.CullMode := cmNone;
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
    PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    SetLength(PipeDesc.DescriptorSetLayouts, 1);
    PipeDesc.DescriptorSetLayouts[0] := SetLayout;
    PipeDesc.PushConstantSize := SizeOf(TCastle2DPushConstants);
    PipeDesc.PushConstantStages := [ssVertex, ssFragment];
    SetLength(PipeDesc.ColorAttachmentFormats, 1);
    PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
    PipeDesc.DepthAttachmentFormat := pfD32_Float;
    PipeDesc.SampleCount := 1;
    PipeDesc.DebugName := 'AsyncTexQuadPSO';
    Pipe := RealDev.GetOrCreatePipeline(PipeDesc);

    ColorTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil]));

    { Begin offscreen frame, then stage & submit async TransferQueue uploads concurrently with CPU command recording }
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;

    RealDev.StagingUploader.EnqueueBufferUpload(GpuVBO, Quad2DVerts[0], SizeOf(Quad2DVerts), 0);
    RealDev.StagingUploader.EnqueueImageUpload(GpuTex, @SrcPixels[0], SizeOf(SrcPixels), 32, 32, 0, 0, False);

    SubmittedVal := RealDev.StagingUploader.SubmitAsyncUploads;
    AssertTrue('Live SubmitAsyncUploads must return timeline value >= 1', SubmittedVal >= 1);
    AssertEquals('TotalAsyncSubmissions must be 1', 1, Integer(RealDev.StagingUploader.TotalAsyncSubmissions));
    if RealDev.StagingUploader.TransferTimelineSemaphore.Handle <> VK_NULL_HANDLE then
      AssertEquals('PendingGraphicsWaitTimelineValue must equal SubmittedVal before graphics submit',
        Int64(SubmittedVal), Int64(RealDev.StagingUploader.PendingGraphicsWaitTimelineValue));

    { Record & submit Graphics frame immediately — EndOffscreenFrame synchronizes on GPU via VkTimelineSemaphoreSubmitInfo }
    RealDev.StagingUploader.ApplyPendingGraphicsAcquireBarriers(RealCmd);
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.2, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    FillChar(Push2D, SizeOf(Push2D), 0);
    Push2D.ViewportScaleBias := Vector4(2.0 / 64.0, 2.0 / 64.0, -1.0, -1.0);
    RealCmd.BeginRendering(PassInfo);
    RealCmd.BindPipeline(Pipe);
    RealCmd.BindDescriptorSet(0, DescSet, []);
    RealCmd.PushConstants([ssVertex, ssFragment], 0, SizeOf(Push2D), Push2D);
    RealCmd.BindVertexBuffers(0, [GpuVBO], [0]);
    RealCmd.Draw(6, 1, 0, 0);
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    AssertEquals('EndOffscreenFrame must consume PendingGraphicsWaitTimelineValue via VkTimelineSemaphoreSubmitInfo',
      Int64(0), Int64(RealDev.StagingUploader.PendingGraphicsWaitTimelineValue));

    RealDev.StagingUploader.WaitForAsyncUploads;
    AssertTrue('Timeline semaphore counter must reach >= SubmittedVal',
      RealDev.StagingUploader.TransferTimelineSemaphore.GetCounterValue >= SubmittedVal);

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));
    { Center (32, 32): Async-uploaded emerald green texture (16, 224, 96) }
    AssertTrue('Center (32,32) R must match emerald green (~16)',
      Abs(Integer(Readback.PixelPtr(32, 32)^.X) - 16) <= 4);
    AssertTrue('Center (32,32) G must match emerald green (~224)',
      Abs(Integer(Readback.PixelPtr(32, 32)^.Y) - 224) <= 4);
    AssertTrue('Center (32,32) B must match emerald green (~96)',
      Abs(Integer(Readback.PixelPtr(32, 32)^.Z) - 96) <= 4);
    { Corner (2, 2): Dark red clear background (~51, 0, 0) }
    AssertTrue('Corner (2,2) must retain dark red clear background',
      (Readback.PixelPtr(2, 2)^.X >= 45) and (Readback.PixelPtr(2, 2)^.Y <= 5));
  finally
    FreeAndNil(Readback);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(DescSet);
    FreeAndNil(Sampler);
    FreeAndNil(SetLayout);
    FreeAndNil(FS);
    FreeAndNil(VS);
    FreeAndNil(GpuTex);
    FreeAndNil(GpuVBO);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeBindlessTextureAndMaterialSSBOMultiDrawRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  BindlessMgr: TCastleVulkanBindlessTextureManager;
  Batch: TCastleVulkanBindlessIndirectBatch;
  SamplerDesc: TRHISamplerDesc;
  Sampler: TRHISampler;
  TexRed, TexGreen, TexBlue, TexAlphaMask, TempTex: TRHITexture;
  ImgRed, ImgGreen, ImgBlue, ImgAlphaMask, Readback: TRGBAlphaImage;
  ColorTex, DepthTex: TRHITexture;
  SlotRed, SlotRedDup, SlotTemp, SlotGreen, SlotBlue, SlotAlpha: Cardinal;
  Mat0, Mat1, Mat2, Mat3: TCastleBindlessMaterialEntry;
  MatIdx0, MatIdx1, MatIdx2, MatIdx3: Cardinal;
  Already0, Already1, Already2, Already3: Boolean;
  QuadVerts: array[0..3] of TCastleBindlessIndirectVertex;
  QuadIndices: array[0..5] of UInt32;
  Insts: array[0..3] of TCastleBindlessIndirectInstanceDesc;
  PassInfo: TRHIRenderingInfo;
  DrawnCount: Cardinal;
  X, Y: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  Sampler := nil;
  TexRed := nil;
  TexGreen := nil;
  TexBlue := nil;
  TexAlphaMask := nil;
  TempTex := nil;
  ImgRed := nil;
  ImgGreen := nil;
  ImgBlue := nil;
  ImgAlphaMask := nil;
  ColorTex := nil;
  DepthTex := nil;
  Readback := nil;
  try
    if not RealDev.SupportsBindlessTextures then
      Exit;

    BindlessMgr := RealDev.BindlessTextureManager;
    Batch := RealDev.BindlessIndirectBatch;
    AssertTrue('BindlessTextureManager must exist on live Vulkan device', BindlessMgr <> nil);
    AssertTrue('BindlessIndirectBatch must exist on live Vulkan device', Batch <> nil);

    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfNearest;
    SamplerDesc.MagFilter := sfNearest;
    SamplerDesc.MipFilter := sfNearest;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    SamplerDesc.MaxLod := 1000.0;
    Sampler := RealDev.CreateSampler(SamplerDesc);

    ImgRed := TRGBAlphaImage.Create(4, 4);
    ImgRed.Clear(Vector4Byte(255, 255, 255, 255));
    for Y := 0 to 3 do
      for X := 0 to 3 do
        ImgRed.PixelPtr(X, Y)^ := Vector4Byte(255, 128, 255, 255);

    ImgGreen := TRGBAlphaImage.Create(4, 4);
    ImgGreen.Clear(Vector4Byte(0, 255, 0, 255));

    ImgBlue := TRGBAlphaImage.Create(4, 4);
    ImgBlue.Clear(Vector4Byte(32, 64, 255, 255));

    ImgAlphaMask := TRGBAlphaImage.Create(4, 4);
    for Y := 0 to 3 do
      for X := 0 to 3 do
        if X < 2 then
          ImgAlphaMask.PixelPtr(X, Y)^ := Vector4Byte(0, 220, 220, 255)
        else
          ImgAlphaMask.PixelPtr(X, Y)^ := Vector4Byte(0, 220, 220, 0);

    TexRed := RealDev.CreateTexture(TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst]));
    TexRed.UploadImage(ImgRed);
    TexGreen := RealDev.CreateTexture(TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst]));
    TexGreen.UploadImage(ImgGreen);
    TexBlue := RealDev.CreateTexture(TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst]));
    TexBlue.UploadImage(ImgBlue);
    TexAlphaMask := RealDev.CreateTexture(TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst]));
    TexAlphaMask.UploadImage(ImgAlphaMask);
    TempTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst]));
    TempTex.UploadImage(ImgGreen);

    { Verify deduplication and O(1) slot recycling on live bindless VkDescriptorPool }
    SlotRed := BindlessMgr.RegisterTexture(TexRed, Sampler);
    SlotRedDup := BindlessMgr.RegisterTexture(TexRed, Sampler);
    AssertEquals('Duplicate bindless registration must return identical slot',
      Integer(SlotRed), Integer(SlotRedDup));
    SlotTemp := BindlessMgr.RegisterTexture(TempTex, Sampler);
    BindlessMgr.UnregisterSlot(SlotTemp);
    SlotGreen := BindlessMgr.RegisterTexture(TexGreen, Sampler);
    AssertEquals('Recycled bindless slot must be reused immediately',
      Integer(SlotTemp), Integer(SlotGreen));
    SlotBlue := BindlessMgr.RegisterTexture(TexBlue, Sampler);
    SlotAlpha := BindlessMgr.RegisterTexture(TexAlphaMask, Sampler);

    { Register 4 distinct materials in Set 1 Binding 1 Material SSBO:
      - Mat 0 (top-left): TexRed (255, 128, 255) * BaseColor (1.0, 1.0, 0.25, 1.0) -> (255, 128, 64)
      - Mat 1 (top-right): TexGreen (0, 255, 0) + Emissive (0.0, 0.0, 0.5, 0.0) -> (0, 255, 128)
      - Mat 2 (bottom-left): TexBlue (32, 64, 255) * BaseColor (1,1,1,1) -> (32, 64, 255)
      - Mat 3 (bottom-right): TexAlphaMask left half (0, 220, 220, 255) kept, right half alpha=0 OpKill discarded }
    FillChar(Mat0, SizeOf(Mat0), 0);
    Mat0.BaseColor := Vector4(1.0, 1.0, 0.25, 1.0);
    Mat0.PBRParams := Vector4(0.5, 1.0, 1.0, 0.0);
    Mat0.BaseColorTexIndex := SlotRed;
    MatIdx0 := 0;
    Already0 := False;
    BindlessMgr.RegisterOrUpdateMaterial(MatIdx0, Already0, Mat0);

    FillChar(Mat1, SizeOf(Mat1), 0);
    Mat1.BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
    Mat1.EmissiveColor := Vector4(0.0, 0.0, 0.5, 0.0);
    Mat1.PBRParams := Vector4(0.5, 1.0, 1.0, 0.0);
    Mat1.BaseColorTexIndex := SlotGreen;
    MatIdx1 := 0;
    Already1 := False;
    BindlessMgr.RegisterOrUpdateMaterial(MatIdx1, Already1, Mat1);

    FillChar(Mat2, SizeOf(Mat2), 0);
    Mat2.BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
    Mat2.PBRParams := Vector4(0.5, 1.0, 1.0, 0.0);
    Mat2.BaseColorTexIndex := SlotBlue;
    MatIdx2 := 0;
    Already2 := False;
    BindlessMgr.RegisterOrUpdateMaterial(MatIdx2, Already2, Mat2);

    FillChar(Mat3, SizeOf(Mat3), 0);
    Mat3.BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
    Mat3.PBRParams := Vector4(0.5, 1.0, 1.0, 0.5); { AlphaCutoff = 0.5 }
    Mat3.BaseColorTexIndex := SlotAlpha;
    MatIdx3 := 0;
    Already3 := False;
    BindlessMgr.RegisterOrUpdateMaterial(MatIdx3, Already3, Mat3);

    { Upload shared unit quad [-0.35..+0.35]^2 in XY plane }
    QuadVerts[0].Position := Vector3(-0.35, -0.35, 0.0);
    QuadVerts[0].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[0].TexCoord := Vector2(0.0, 0.0);
    QuadVerts[1].Position := Vector3( 0.35, -0.35, 0.0);
    QuadVerts[1].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[1].TexCoord := Vector2(1.0, 0.0);
    QuadVerts[2].Position := Vector3( 0.35,  0.35, 0.0);
    QuadVerts[2].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[2].TexCoord := Vector2(1.0, 1.0);
    QuadVerts[3].Position := Vector3(-0.35,  0.35, 0.0);
    QuadVerts[3].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[3].TexCoord := Vector2(0.0, 1.0);
    QuadIndices[0] := 0; QuadIndices[1] := 1; QuadIndices[2] := 2;
    QuadIndices[3] := 0; QuadIndices[4] := 2; QuadIndices[5] := 3;
    Batch.UploadSharedMesh(QuadVerts, QuadIndices);
    Batch.SetCamera(TMatrix4.Identity, Vector3(0.0, 0.0, 1.0), 0.25);

    { Place 4 instances in the 4 NDC quadrants:
      (-0.5, +0.5) top-left, (+0.5, +0.5) top-right, (-0.5, -0.5) bottom-left, (+0.5, -0.5) bottom-right }
    Insts[0] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(-0.5, 0.5, 0.0), Vector4(-0.5, 0.5, 0.0, 0.6),
      MatIdx0, BINDLESS_INSTANCE_FLAG_TEXTURED, 6);
    Insts[1] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(0.5, 0.5, 0.0), Vector4(0.5, 0.5, 0.0, 0.6),
      MatIdx1, BINDLESS_INSTANCE_FLAG_TEXTURED, 6);
    Insts[2] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(-0.5, -0.5, 0.0), Vector4(-0.5, -0.5, 0.0, 0.6),
      MatIdx2, BINDLESS_INSTANCE_FLAG_TEXTURED, 6);
    Insts[3] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(0.5, -0.5, 0.0), Vector4(0.5, -0.5, 0.0, 0.6),
      MatIdx3, BINDLESS_INSTANCE_FLAG_TEXTURED or BINDLESS_INSTANCE_FLAG_ALPHA_CUTOFF, 6);
    Batch.UploadInstances(Insts, False);

    ColorTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil]));

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    AssertTrue('Dedicated BindlessPool must be allocated on live Vulkan device',
      BindlessMgr.BindlessPool <> VK_NULL_HANDLE);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(20.0 / 255.0, 20.0 / 255.0, 30.0 / 255.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    DrawnCount := Batch.RecordBindlessIndirectDraws(RealCmd, pfRGBA8_UNorm, pfD32_Float, 1, False);
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    AssertEquals('Single multi-draw indirect batch must issue 4 sub-draws', 4, Integer(DrawnCount));
    AssertEquals('RealCmd.IndirectDrawCallCount must be 1 (zero per-object descriptor rebinds)',
      1, Integer(RealCmd.IndirectDrawCallCount));

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Top-left (16, 48) -> Mat0: (255, 128, 64) }
    AssertTrue('Top-left R (~255)', Abs(Integer(Readback.PixelPtr(16, 48)^.X) - 255) <= 4);
    AssertTrue('Top-left G (~128)', Abs(Integer(Readback.PixelPtr(16, 48)^.Y) - 128) <= 4);
    AssertTrue('Top-left B (~64)',  Abs(Integer(Readback.PixelPtr(16, 48)^.Z) - 64) <= 4);

    { Top-right (48, 48) -> Mat1: (0, 255, 128) }
    AssertTrue('Top-right R (~0)',   Abs(Integer(Readback.PixelPtr(48, 48)^.X) - 0) <= 4);
    AssertTrue('Top-right G (~255)', Abs(Integer(Readback.PixelPtr(48, 48)^.Y) - 255) <= 4);
    AssertTrue('Top-right B (~128)', Abs(Integer(Readback.PixelPtr(48, 48)^.Z) - 128) <= 4);

    { Bottom-left (16, 16) -> Mat2: (32, 64, 255) }
    AssertTrue('Bottom-left R (~32)',  Abs(Integer(Readback.PixelPtr(16, 16)^.X) - 32) <= 4);
    AssertTrue('Bottom-left G (~64)',  Abs(Integer(Readback.PixelPtr(16, 16)^.Y) - 64) <= 4);
    AssertTrue('Bottom-left B (~255)', Abs(Integer(Readback.PixelPtr(16, 16)^.Z) - 255) <= 4);

    { Bottom-right left half (40, 16) -> Mat3 opaque cyan (0, 220, 220) }
    AssertTrue('Bottom-right kept half R (~0)',   Abs(Integer(Readback.PixelPtr(40, 16)^.X) - 0) <= 4);
    AssertTrue('Bottom-right kept half G (~220)', Abs(Integer(Readback.PixelPtr(40, 16)^.Y) - 220) <= 4);
    AssertTrue('Bottom-right kept half B (~220)', Abs(Integer(Readback.PixelPtr(40, 16)^.Z) - 220) <= 4);

    { Bottom-right right half (55, 16) -> Mat3 alpha=0 OpKill discarded, preserving clear (20, 20, 30) }
    AssertTrue('Bottom-right discarded half R (~20)', Abs(Integer(Readback.PixelPtr(55, 16)^.X) - 20) <= 4);
    AssertTrue('Bottom-right discarded half G (~20)', Abs(Integer(Readback.PixelPtr(55, 16)^.Y) - 20) <= 4);
    AssertTrue('Bottom-right discarded half B (~30)', Abs(Integer(Readback.PixelPtr(55, 16)^.Z) - 30) <= 4);
  finally
    FreeAndNil(Readback);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(ImgAlphaMask);
    FreeAndNil(ImgBlue);
    FreeAndNil(ImgGreen);
    FreeAndNil(ImgRed);
    FreeAndNil(TempTex);
    FreeAndNil(TexAlphaMask);
    FreeAndNil(TexBlue);
    FreeAndNil(TexGreen);
    FreeAndNil(TexRed);
    FreeAndNil(Sampler);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeComputeCullerAndDrawIndexedIndirectCountRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  BindlessMgr: TCastleVulkanBindlessTextureManager;
  Batch: TCastleVulkanBindlessIndirectBatch;
  ColorTex, DepthTex: TRHITexture;
  Readback: TRGBAlphaImage;
  OrthoViewProj: TMatrix4;
  Planes: array[0..5] of TVector4;
  Mats: array[0..4] of TCastleBindlessMaterialEntry;
  MatIdxs: array[0..4] of Cardinal;
  AlreadyReg: Boolean;
  QuadVerts: array[0..3] of TCastleBindlessIndirectVertex;
  QuadIndices: array[0..5] of UInt32;
  Insts: array[0..7] of TCastleBindlessIndirectInstanceDesc;
  PassInfo: TRHIRenderingInfo;
  CmdOut: TRHIDrawIndexedIndirectCommand;
  SeenMask: Cardinal;
  I: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  ColorTex := nil;
  DepthTex := nil;
  Readback := nil;
  try
    if not RealDev.SupportsBindlessTextures then
      Exit;

    if (RealDev.VendorKind = vvMesa) and (RealDev.DeviceApiVersion >= VK_API_VERSION_1_4) then
    begin
      AssertTrue('Mesa Lavapipe Vulkan 1.4 must support MultiDrawIndirect',
        RealDev.Capabilities.SupportsMultiDrawIndirect);
      AssertTrue('Mesa Lavapipe Vulkan 1.4 must support DrawIndirectCount (Vulkan 1.2 feature)',
        RealDev.Capabilities.SupportsDrawIndirectCount);
    end;

    BindlessMgr := RealDev.BindlessTextureManager;
    Batch := RealDev.BindlessIndirectBatch;

    { Register 5 solid bindless materials:
      0: Coral Red (240, 64, 48)
      1: Lime Green (64, 240, 80)
      2: Sky Blue (48, 144, 250)
      3: Gold Yellow (250, 208, 32)
      4: Sentinel Magenta (255, 0, 255) — assigned ONLY to culled instances! }
    for I := 0 to 4 do
      FillChar(Mats[I], SizeOf(TCastleBindlessMaterialEntry), 0);
    Mats[0].BaseColor := Vector4(240.0 / 255.0, 64.0 / 255.0, 48.0 / 255.0, 1.0);
    Mats[1].BaseColor := Vector4(64.0 / 255.0, 240.0 / 255.0, 80.0 / 255.0, 1.0);
    Mats[2].BaseColor := Vector4(48.0 / 255.0, 144.0 / 255.0, 250.0 / 255.0, 1.0);
    Mats[3].BaseColor := Vector4(250.0 / 255.0, 208.0 / 255.0, 32.0 / 255.0, 1.0);
    Mats[4].BaseColor := Vector4(1.0, 0.0, 1.0, 1.0);

    for I := 0 to 4 do
    begin
      MatIdxs[I] := 0;
      AlreadyReg := False;
      BindlessMgr.RegisterOrUpdateMaterial(MatIdxs[I], AlreadyReg, Mats[I]);
    end;

    { Unit quad of half-size 3.0 in world space (within [-10..10] ortho frustum) }
    QuadVerts[0].Position := Vector3(-3.0, -3.0, 0.0);
    QuadVerts[0].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[0].TexCoord := Vector2(0.0, 0.0);
    QuadVerts[1].Position := Vector3( 3.0, -3.0, 0.0);
    QuadVerts[1].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[1].TexCoord := Vector2(1.0, 0.0);
    QuadVerts[2].Position := Vector3( 3.0,  3.0, 0.0);
    QuadVerts[2].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[2].TexCoord := Vector2(1.0, 1.0);
    QuadVerts[3].Position := Vector3(-3.0,  3.0, 0.0);
    QuadVerts[3].Normal := Vector3(0.0, 0.0, 1.0);
    QuadVerts[3].TexCoord := Vector2(0.0, 1.0);
    QuadIndices[0] := 0; QuadIndices[1] := 1; QuadIndices[2] := 2;
    QuadIndices[3] := 0; QuadIndices[4] := 2; QuadIndices[5] := 3;
    Batch.UploadSharedMesh(QuadVerts, QuadIndices);

    { Orthographic frustum [-10..10] x [-10..10], ZNear=1, ZFar=50 looking down -Z }
    OrthoViewProj := OrthoProjectionMatrix(FloatRectangle(-10.0, -10.0, 20.0, 20.0), 1.0, 50.0);
    Batch.SetCamera(OrthoViewProj, Vector3(0.0, 0.0, 1.0), 0.25);

    Planes[0] := Vector4( 1.0,  0.0,  0.0, 10.0); { x >= -10 }
    Planes[1] := Vector4(-1.0,  0.0,  0.0, 10.0); { x <= +10 }
    Planes[2] := Vector4( 0.0,  1.0,  0.0, 10.0); { y >= -10 }
    Planes[3] := Vector4( 0.0, -1.0,  0.0, 10.0); { y <= +10 }
    Planes[4] := Vector4( 0.0,  0.0, -1.0, -1.0); { z <= -1 }
    Planes[5] := Vector4( 0.0,  0.0,  1.0, 50.0); { z >= -50 }
    { MaxDistance = 30.0: culls objects beyond distance 30 even if inside ZFar=50! }
    RealDev.ComputeCuller.SetFrustumPlanes(Planes, Vector3(0.0, 0.0, 0.0), 30.0);

    { 8 candidate instances:
      - Even indices 0, 2, 4, 6: VISIBLE in the 4 quadrants at Z = -10 (dist ~12.2 <= 30)
      - Indices 1, 3: OUTSIDE frustum X/Y (X = -45, Y = +45) with Sentinel Magenta
      - Indices 5, 7: INSIDE frustum X/Y/Z at screen center (0, 0, -42), Z in [-50..-1],
        rejected EXCLUSIVELY by GPU distance culling (42 - 4.5 = 37.5 > 30.0)! }
    Insts[0] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(-5.5,  5.5, -10.0), Vector4(-5.5,  5.5, -10.0, 4.5), MatIdxs[0], 0, 6);
    Insts[1] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(-45.0, 0.0, -10.0), Vector4(-45.0, 0.0, -10.0, 4.5), MatIdxs[4], 0, 6);
    Insts[2] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix( 5.5,  5.5, -10.0), Vector4( 5.5,  5.5, -10.0, 4.5), MatIdxs[1], 0, 6);
    Insts[3] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix( 0.0, 45.0, -10.0), Vector4( 0.0, 45.0, -10.0, 4.5), MatIdxs[4], 0, 6);
    Insts[4] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(-5.5, -5.5, -10.0), Vector4(-5.5, -5.5, -10.0, 4.5), MatIdxs[2], 0, 6);
    Insts[5] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix( 0.0,  0.0, -42.0), Vector4( 0.0,  0.0, -42.0, 4.5), MatIdxs[4], 0, 6);
    Insts[6] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix( 5.5, -5.5, -10.0), Vector4( 5.5, -5.5, -10.0, 4.5), MatIdxs[3], 0, 6);
    Insts[7] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix( 0.0,  0.0, -44.0), Vector4( 0.0,  0.0, -44.0, 4.5), MatIdxs[4], 0, 6);
    Batch.UploadInstances(Insts, True);

    ColorTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil]));

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    { 1. Dispatch GpuCullingCS on GPU + emit rsUnorderedAccess -> rsIndirectRead barriers }
    Batch.RecordComputeCullingPass(RealCmd, True);

    { 2. Render compacted survivors via single vkCmdDrawIndexedIndirectCount }
    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(12.0 / 255.0, 16.0 / 255.0, 24.0 / 255.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Batch.RecordBindlessIndirectDraws(RealCmd, pfRGBA8_UNorm, pfD32_Float, 1, True);
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    AssertEquals('vkCmdDrawIndexedIndirectCount must be recorded once',
      1, Integer(RealCmd.IndirectCountDrawCallCount));

    { Verify GPU-written atomic counter, per-instance visibility flags, and compacted indirect commands }
    AssertEquals('GPU GpuCullingCS OpAtomicIAdd visible count must be 4',
      4, Integer(RealDev.ComputeCuller.ReadBackVisibleCount));
    for I := 0 to 7 do
      if (I mod 2) = 0 then
        AssertEquals(Format('Instance %d visibility flag must be 1', [I]),
          1, Integer(RealDev.ComputeCuller.ReadBackVisibilityFlag(Cardinal(I))))
      else
        AssertEquals(Format('Instance %d visibility flag must be 0 (culled on GPU)', [I]),
          0, Integer(RealDev.ComputeCuller.ReadBackVisibilityFlag(Cardinal(I))));

    SeenMask := 0;
    for I := 0 to 3 do
    begin
      CmdOut := RealDev.ComputeCuller.ReadBackIndirectCommand(Cardinal(I));
      AssertEquals('Compacted command IndexCount must be 6', 6, Integer(CmdOut.IndexCount));
      AssertEquals('Compacted command InstanceCount must be 1', 1, Integer(CmdOut.InstanceCount));
      AssertTrue('Compacted FirstInstance must be in {0, 2, 4, 6}',
        (CmdOut.FirstInstance <= 6) and ((CmdOut.FirstInstance mod 2) = 0));
      SeenMask := SeenMask or (Cardinal(1) shl CmdOut.FirstInstance);
    end;
    AssertEquals('Compacted indirect stream must contain exact set {0, 2, 4, 6}',
      Integer((1 shl 0) or (1 shl 2) or (1 shl 4) or (1 shl 6)), Integer(SeenMask));

    { Verify rendered pixels: 4 quadrants match visible materials and center (32, 32) is untouched clear color! }
    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Top-left (-5.5, +5.5) -> pixel (14, 50): Coral Red (240, 64, 48) }
    AssertTrue('Top-left Coral Red R', Abs(Integer(Readback.PixelPtr(14, 50)^.X) - 240) <= 5);
    AssertTrue('Top-left Coral Red G', Abs(Integer(Readback.PixelPtr(14, 50)^.Y) - 64) <= 5);
    AssertTrue('Top-left Coral Red B', Abs(Integer(Readback.PixelPtr(14, 50)^.Z) - 48) <= 5);

    { Top-right (+5.5, +5.5) -> pixel (50, 50): Lime Green (64, 240, 80) }
    AssertTrue('Top-right Lime Green R', Abs(Integer(Readback.PixelPtr(50, 50)^.X) - 64) <= 5);
    AssertTrue('Top-right Lime Green G', Abs(Integer(Readback.PixelPtr(50, 50)^.Y) - 240) <= 5);
    AssertTrue('Top-right Lime Green B', Abs(Integer(Readback.PixelPtr(50, 50)^.Z) - 80) <= 5);

    { Bottom-left (-5.5, -5.5) -> pixel (14, 14): Sky Blue (48, 144, 250) }
    AssertTrue('Bottom-left Sky Blue R', Abs(Integer(Readback.PixelPtr(14, 14)^.X) - 48) <= 5);
    AssertTrue('Bottom-left Sky Blue G', Abs(Integer(Readback.PixelPtr(14, 14)^.Y) - 144) <= 5);
    AssertTrue('Bottom-left Sky Blue B', Abs(Integer(Readback.PixelPtr(14, 14)^.Z) - 250) <= 5);

    { Bottom-right (+5.5, -5.5) -> pixel (50, 14): Gold Yellow (250, 208, 32) }
    AssertTrue('Bottom-right Gold Yellow R', Abs(Integer(Readback.PixelPtr(50, 14)^.X) - 250) <= 5);
    AssertTrue('Bottom-right Gold Yellow G', Abs(Integer(Readback.PixelPtr(50, 14)^.Y) - 208) <= 5);
    AssertTrue('Bottom-right Gold Yellow B', Abs(Integer(Readback.PixelPtr(50, 14)^.Z) - 32) <= 5);

    { Center (32, 32): Distance-culled Sentinel Magenta instances 5 & 7 must NOT be drawn! }
    AssertTrue('Center R must remain dark clear (~12), not Magenta (255)',
      Abs(Integer(Readback.PixelPtr(32, 32)^.X) - 12) <= 4);
    AssertTrue('Center G must remain dark clear (~16)',
      Abs(Integer(Readback.PixelPtr(32, 32)^.Y) - 16) <= 4);
    AssertTrue('Center B must remain dark clear (~24), not Magenta (255)',
      Abs(Integer(Readback.PixelPtr(32, 32)^.Z) - 24) <= 4);
  finally
    FreeAndNil(Readback);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeMaterialBinnerAndBindlessGpuDrivenPipelineRHI;
const
  StreamMatIDs: array[0..15] of Cardinal = (
    3, 0, 2, 3, 1, 0, 3, 5, 2, 0, 7, 3, 1, 2, 0, 5
  );
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  Binner: TCastleVulkanMaterialBinner;
  BindlessMgr: TCastleVulkanBindlessTextureManager;
  Batch: TCastleVulkanBindlessIndirectBatch;
  SamplerDesc: TRHISamplerDesc;
  Sampler: TRHISampler;
  WhiteTex: TRHITexture;
  WhiteImg, Readback: TRGBAlphaImage;
  ColorTex, DepthTex: TRHITexture;
  CpuCounts, CpuOffsets, GpuCounts, GpuOffsets: TCardinalDynamicArray;
  SlotWhite, MatIdxLit: Cardinal;
  AlreadyReg: Boolean;
  MatLit: TCastleBindlessMaterialEntry;
  Verts: array[0..7] of TCastleBindlessIndirectVertex;
  Indices: array[0..11] of UInt32;
  Insts: array[0..1] of TCastleBindlessIndirectInstanceDesc;
  Planes: array[0..5] of TVector4;
  PassInfo: TRHIRenderingInfo;
  I: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  Sampler := nil;
  WhiteTex := nil;
  WhiteImg := nil;
  ColorTex := nil;
  DepthTex := nil;
  Readback := nil;
  try
    if not RealDev.SupportsBindlessTextures then
      Exit;

    Binner := RealDev.MaterialBinner;
    BindlessMgr := RealDev.BindlessTextureManager;
    Batch := RealDev.BindlessIndirectBatch;

    { 1. Upload 16-element material ID stream to TCastleVulkanMaterialBinner }
    TCastleVulkanMaterialBinner.EvaluateMaterialBinRanges(StreamMatIDs, 8, CpuCounts, CpuOffsets);
    Binner.UploadMaterialIDs(StreamMatIDs);

    { 2. Setup directional-lit bindless GPU-driven batch with two sub-meshes in shared VB/IB:
         - Sub-mesh 0 (FirstIndex=0, VertexOffset=0): normal (0, 0, +1) facing light (0, 0, +1) -> shade = 1.0
         - Sub-mesh 1 (FirstIndex=6, VertexOffset=4): normal (0, +1, 0) perpendicular to light  -> shade = ambient (0.25) }
    FillChar(SamplerDesc, SizeOf(SamplerDesc), 0);
    SamplerDesc.MinFilter := sfNearest;
    SamplerDesc.MagFilter := sfNearest;
    SamplerDesc.MipFilter := sfNearest;
    SamplerDesc.AddressModeU := amClampToEdge;
    SamplerDesc.AddressModeV := amClampToEdge;
    SamplerDesc.AddressModeW := amClampToEdge;
    SamplerDesc.MaxAnisotropy := 1.0;
    SamplerDesc.MaxLod := 1000.0;
    Sampler := RealDev.CreateSampler(SamplerDesc);

    WhiteImg := TRGBAlphaImage.Create(4, 4);
    WhiteImg.Clear(Vector4Byte(200, 160, 80, 255));
    WhiteTex := RealDev.CreateTexture(TRHITextureDesc.Create2D(4, 4, pfRGBA8_UNorm, [tuSampled, tuTransferDst]));
    WhiteTex.UploadImage(WhiteImg);
    SlotWhite := BindlessMgr.RegisterTexture(WhiteTex, Sampler);

    FillChar(MatLit, SizeOf(MatLit), 0);
    MatLit.BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
    MatLit.PBRParams := Vector4(0.5, 1.0, 1.0, 0.0);
    MatLit.BaseColorTexIndex := SlotWhite;
    MatIdxLit := 0;
    AlreadyReg := False;
    BindlessMgr.RegisterOrUpdateMaterial(MatIdxLit, AlreadyReg, MatLit);

    { Sub-mesh 0: vertices 0..3 with Normal = (0, 0, 1) }
    Verts[0].Position := Vector3(-0.35, -0.6, 0.0); Verts[0].Normal := Vector3(0, 0, 1); Verts[0].TexCoord := Vector2(0, 0);
    Verts[1].Position := Vector3( 0.35, -0.6, 0.0); Verts[1].Normal := Vector3(0, 0, 1); Verts[1].TexCoord := Vector2(1, 0);
    Verts[2].Position := Vector3( 0.35,  0.6, 0.0); Verts[2].Normal := Vector3(0, 0, 1); Verts[2].TexCoord := Vector2(1, 1);
    Verts[3].Position := Vector3(-0.35,  0.6, 0.0); Verts[3].Normal := Vector3(0, 0, 1); Verts[3].TexCoord := Vector2(0, 1);
    { Sub-mesh 1: vertices 4..7 with Normal = (0, 1, 0) -> N dot L = 0 -> ambient = 0.25 }
    Verts[4].Position := Vector3(-0.35, -0.6, 0.0); Verts[4].Normal := Vector3(0, 1, 0); Verts[4].TexCoord := Vector2(0, 0);
    Verts[5].Position := Vector3( 0.35, -0.6, 0.0); Verts[5].Normal := Vector3(0, 1, 0); Verts[5].TexCoord := Vector2(1, 0);
    Verts[6].Position := Vector3( 0.35,  0.6, 0.0); Verts[6].Normal := Vector3(0, 1, 0); Verts[6].TexCoord := Vector2(1, 1);
    Verts[7].Position := Vector3(-0.35,  0.6, 0.0); Verts[7].Normal := Vector3(0, 1, 0); Verts[7].TexCoord := Vector2(0, 1);

    { Indices 0..5 local (0,1,2, 0,2,3) used with VertexOffset=0 and Indices 6..11 local (0,1,2, 0,2,3) used with VertexOffset=4 }
    Indices[0] := 0; Indices[1] := 1; Indices[2] := 2;
    Indices[3] := 0; Indices[4] := 2; Indices[5] := 3;
    Indices[6] := 0; Indices[7] := 1; Indices[8] := 2;
    Indices[9] := 0; Indices[10] := 2; Indices[11] := 3;

    Batch.UploadSharedMesh(Verts, Indices);
    Batch.SetCamera(TMatrix4.Identity, Vector3(0.0, 0.0, 1.0), 0.25);

    for I := 0 to 5 do
      Planes[I] := Vector4(0.0, 0.0, 0.0, 10.0);
    RealDev.ComputeCuller.SetFrustumPlanes(Planes, Vector3(0.0, 0.0, 0.0), 0.0);

    { Left half (-0.5, 0): fully lit (N dot L = 1.0 -> shade = 1.0 -> (200, 160, 80))
      Right half (+0.5, 0): ambient-only (N dot L = 0.0 -> shade = 0.25 -> (50, 40, 20)) }
    Insts[0] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix(-0.5, 0.0, 0.0), Vector4(-0.5, 0.0, 0.0, 1.0),
      MatIdxLit, BINDLESS_INSTANCE_FLAG_TEXTURED or BINDLESS_INSTANCE_FLAG_LIT, 6, 0, 0);
    Insts[1] := TCastleBindlessIndirectInstanceDesc.CreateSimple(
      TranslationMatrix( 0.5, 0.0, 0.0), Vector4( 0.5, 0.0, 0.0, 1.0),
      MatIdxLit, BINDLESS_INSTANCE_FLAG_TEXTURED or BINDLESS_INSTANCE_FLAG_LIT, 6, 6, 4);
    Batch.UploadInstances(Insts, True);

    ColorTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    DepthTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil]));

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    { Execute GPU MaterialBinHistogramCS + UAV barrier + MaterialBinPrefixSumCS }
    AssertEquals('DispatchStreamBinning must return 8 bins',
      8, Integer(Binner.DispatchStreamBinning(RealCmd, 8)));
    { Execute GPU GpuCullingCS + bindless indirect lit multi-draw }
    Batch.RecordComputeCullingPass(RealCmd, True);

    PassInfo := TRHIRenderingInfo.CreateColorDepth(
      Rectangle(0, 0, 64, 64),
      ColorTex, loClear, Vector4(0.0, 0.0, 0.0, 1.0),
      DepthTex, loClear, 1.0);
    RealCmd.BeginRendering(PassInfo);
    Batch.RecordBindlessIndirectDraws(RealCmd, pfRGBA8_UNorm, pfD32_Float, 1, True);
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    { Verify GPU MaterialBinHistogramCS & MaterialBinPrefixSumCS output matches CPU reference }
    Binner.ReadBackBinRanges(8, GpuCounts, GpuOffsets);
    for I := 0 to 7 do
    begin
      AssertEquals(Format('GPU MaterialBin Count[%d] must match CPU reference', [I]),
        Integer(CpuCounts[I]), Integer(GpuCounts[I]));
      AssertEquals(Format('GPU MaterialBin ExclusiveOffset[%d] must match CPU reference', [I]),
        Integer(CpuOffsets[I]), Integer(GpuOffsets[I]));
    end;

    { Verify VertexOffset + directional Lambertian + ambient shading on rendered pixels }
    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 64, 64));

    { Left quad (16, 32): N=(0,0,1), L=(0,0,1) -> shade=1.0 -> (200, 160, 80) }
    AssertTrue('Fully-lit quad R (~200)', Abs(Integer(Readback.PixelPtr(16, 32)^.X) - 200) <= 5);
    AssertTrue('Fully-lit quad G (~160)', Abs(Integer(Readback.PixelPtr(16, 32)^.Y) - 160) <= 5);
    AssertTrue('Fully-lit quad B (~80)',  Abs(Integer(Readback.PixelPtr(16, 32)^.Z) - 80) <= 5);

    { Right quad (48, 32): N=(0,1,0), L=(0,0,1), VertexOffset=4 -> shade=0.25 -> (50, 40, 20) }
    AssertTrue('Ambient-shaded quad R (~50)', Abs(Integer(Readback.PixelPtr(48, 32)^.X) - 50) <= 5);
    AssertTrue('Ambient-shaded quad G (~40)', Abs(Integer(Readback.PixelPtr(48, 32)^.Y) - 40) <= 5);
    AssertTrue('Ambient-shaded quad B (~20)', Abs(Integer(Readback.PixelPtr(48, 32)^.Z) - 20) <= 5);
  finally
    FreeAndNil(Readback);
    FreeAndNil(DepthTex);
    FreeAndNil(ColorTex);
    FreeAndNil(WhiteImg);
    FreeAndNil(WhiteTex);
    FreeAndNil(Sampler);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.Phase111AliasPass0Callback(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
begin
  if (AGraph = nil) and (APass = nil) then ;
  Inc(FRenderGraphPassExecCount);
  if ACmd <> nil then
    ACmd.ClearAttachments(True, Vector4(0.8, 0.2, 0.1, 1.0), False, 1.0, False, 0);
end;

procedure TTestCastleVulkanRHI.Phase111AliasPass5Callback(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
begin
  if (AGraph = nil) and (APass = nil) then ;
  Inc(FRenderGraphPassExecCount);
  if ACmd <> nil then
    ACmd.ClearAttachments(True, Vector4(0.25, 0.55, 0.85, 1.0), False, 1.0, False, 0);
end;

procedure TTestCastleVulkanRHI.Phase111ForwardSceneCallback(
  const AGraph: TRHIRenderGraph; const APass: TRHIRenderGraphPass; const ACmd: TRHICommandList);
begin
  if (AGraph = nil) and (APass = nil) then ;
  Inc(FPhase111ForwardSubPassCounter);
  if ACmd = nil then
    Exit;

  { Render deterministic HDR + Depth scene into the RenderGraph's active dynamic rendering pass:
    - Base clear already wrote background HDR=(0,0,0,1), Depth=1.0 (sky)
    - Left & center foreground surface [4..60 x 4..60]: mid-HDR (0.65, 0.50, 0.35), Depth = 0.50
    - Bright HDR emissive core [26..38 x 26..38]: HDR (6.0, 3.0, 1.2), Depth = 0.32 (creates depth crease + bloom!) }
  ACmd.SetScissor(Rectangle(4, 4, 56, 56));
  ACmd.ClearAttachments(True, Vector4(0.65, 0.50, 0.35, 1.0), True, 0.50, False, 0);

  ACmd.SetScissor(Rectangle(26, 26, 12, 12));
  ACmd.ClearAttachments(True, Vector4(6.0, 3.0, 1.2, 1.0), True, 0.32, False, 0);

  ACmd.SetScissor(Rectangle(0, 0, 64, 64));
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeRenderGraphPhysicalMemoryAliasingAndDeadPassCullingRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  Graph: TRHIRenderGraph;
  FinalLDR: TRHITexture;
  DescT1, DescT2, DescT3, DescT4, DescDead, FinalDesc: TRHITextureDesc;
  HT1, HT2, HT3, HT4, HDead, HFinal: TRHIRenderGraphResourceHandle;
  P0, P1, P2, P3, P4, P5, PDead: TRHIRenderGraphPass;
  VkT1, VkT3, VkT4: TVulkanRHITexture;
  PoolCountFrame1: Integer;
  Readback, ExpectedImg: TRGBAlphaImage;
  RMSE: Single;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  Graph := nil;
  FinalLDR := nil;
  Readback := nil;
  ExpectedImg := nil;
  try
    FinalDesc := TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled, tuTransferSrc], 1, 1);
    FinalDesc.DebugName := 'Phase111_AliasFinalLDR';
    FinalLDR := RealDev.CreateTexture(FinalDesc);

    DescT1 := TRHITextureDesc.Create2D(64, 64, pfRGBA16_Float,
      [tuColorAttachment, tuSampled], 1, 1);
    DescT2 := TRHITextureDesc.Create2D(64, 64, pfRGBA16_Float,
      [tuColorAttachment, tuSampled], 1, 1);
    { Heterogeneous format (pfR16_Float) + usage (tuStorage) non-overlapping with T1 }
    DescT3 := TRHITextureDesc.Create2D(64, 64, pfR16_Float,
      [tuSampled, tuStorage], 1, 1);
    { Heterogeneous resolution (32x32) + format (pfRGBA8_UNorm) non-overlapping with T3 }
    DescT4 := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm,
      [tuColorAttachment, tuSampled], 1, 1);
    DescDead := TRHITextureDesc.Create2D(128, 128, pfRGBA16_Float,
      [tuColorAttachment, tuSampled], 1, 1);

    Graph := TRHIRenderGraph.Create(RealDev);

    { Build Frame 1 }
    HT1 := Graph.DeclareTransientTexture('Alias_T1_HDR64', DescT1);
    HT2 := Graph.DeclareTransientTexture('Alias_T2_HDR64', DescT2);
    HT3 := Graph.DeclareTransientTexture('Alias_T3_R16F64', DescT3);
    HT4 := Graph.DeclareTransientTexture('Alias_T4_RGBA8_32', DescT4);
    HDead := Graph.DeclareTransientTexture('Alias_Dead_128', DescDead);
    HFinal := Graph.ImportExternalTexture('Alias_FinalLDR', FinalLDR, rsUndefined, rsShaderRead);

    FRenderGraphPassExecCount := 0;

    P0 := Graph.AddPass('Pass0_ProduceT1', rgptGraphics);
    P0.WriteColorAttachment(HT1, loClear, Vector4(0.8, 0.2, 0.1, 1.0), soStore);
    P0.OnExecute := @Phase111AliasPass0Callback;

    P1 := Graph.AddPass('Pass1_ConsumeT1_ProduceT2', rgptGraphics);
    P1.ReadTexture(HT1, rsShaderRead);
    P1.WriteColorAttachment(HT2, loClear, Vector4(0.1, 0.7, 0.3, 1.0), soStore);
    P1.OnExecute := @DummyRenderGraphPassCallback;

    { T1 lifetime ended at Pass1 (order 1); Pass2 reads T2 (forcing order 2 > 1) and produces T3 -> aliases T1's VkDeviceMemory! }
    P2 := Graph.AddPass('Pass2_ProduceT3Storage', rgptCompute);
    P2.ReadTexture(HT2, rsShaderRead);
    P2.WriteStorageTexture(HT3, rsUnorderedAccess);
    P2.OnExecute := @DummyRenderGraphPassCallback;

    { T2 lifetime ended at Pass2 (order 2); Pass3 reads T3 (forcing order 3 > 2) and produces T4 -> aliases T2's VkDeviceMemory! }
    P3 := Graph.AddPass('Pass3_ConsumeT3_ProduceT4', rgptGraphics);
    P3.ReadTexture(HT3, rsShaderRead);
    P3.WriteColorAttachment(HT4, loClear, Vector4(0.9, 0.8, 0.2, 1.0), soStore);
    P3.OnExecute := @DummyRenderGraphPassCallback;

    P4 := Graph.AddPass('Pass4_ConsumeT4', rgptCompute);
    P4.ReadTexture(HT4, rsShaderRead);
    P4.HasSideEffects := True;
    P4.OnExecute := @DummyRenderGraphPassCallback;

    P5 := Graph.AddPass('Pass5_CompositeFinal', rgptGraphics);
    P5.ReadTexture(HT4, rsShaderRead);
    P5.WriteColorAttachment(HFinal, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
    P5.OnExecute := @Phase111AliasPass5Callback;

    PDead := Graph.AddPass('PassDead_Unreferenced', rgptGraphics);
    PDead.WriteColorAttachment(HDead, loClear, Vector4(1.0, 0.0, 1.0, 1.0), soStore);
    PDead.OnExecute := @DummyRenderGraphPassCallback;

    Graph.Compile;

    AssertEquals('Dead-pass culling must cull 1 pass', 1, Graph.CulledPassCount);
    AssertEquals('Compiled pass count must be 6', 6, Graph.CompiledPassCount);
    AssertTrue('Unreferenced dead transient texture must not allocate VRAM',
      Graph.ResolvePhysicalTexture(HDead) = nil);

    VkT1 := Graph.ResolvePhysicalTexture(HT1) as TVulkanRHITexture;
    VkT3 := Graph.ResolvePhysicalTexture(HT3) as TVulkanRHITexture;
    VkT4 := Graph.ResolvePhysicalTexture(HT4) as TVulkanRHITexture;
    AssertTrue('Resolved T1, T3, T4 must be non-nil', (VkT1 <> nil) and (VkT3 <> nil) and (VkT4 <> nil));

    { Verify distinct VkImage handles sharing the exact same physical VkDeviceMemory & MemoryOffset
      when the Vulkan driver permits non-dedicated sub-allocated optimal image aliasing! }
    AssertTrue('Cross-format T3 must have a distinct VkImage handle from T1',
      VkT3.Image <> VkT1.Image);
    if RealDev.VendorKind = vvMesa then
      AssertTrue('Mesa Lavapipe must support non-dedicated VkImage physical memory aliasing',
        VkT3.IsMemoryAliased);
    PoolCountFrame1 := Graph.PhysicalTransientTextureCount;
    if VkT3.IsMemoryAliased then
    begin
      AssertTrue('Cross-format aliased T3 must bind to the exact same VkDeviceMemory as carrier T1',
        VkT3.DeviceMemory = VkT1.DeviceMemory);
      AssertEquals('Cross-format aliased T3 must bind at the carrier MemoryOffset',
        Int64(VkT1.MemoryOffset), Int64(VkT3.MemoryOffset));
      AssertTrue('T3 must report IsMemoryAliased = True and not own the carrier allocation',
        VkT3.IsMemoryAliased and (not VkT3.OwnsAllocation));
      AssertTrue('Graph must report MemoryAliasedTextureCount >= 1', Graph.MemoryAliasedTextureCount >= 1);
      AssertTrue('Graph must report AliasedMemorySavedBytes > 0', Graph.AliasedMemorySavedBytes > 0);
      AssertTrue('Graph must hoist explicit aliasing barriers (>= 1)', Graph.AliasingBarrierCount >= 1);
      AssertEquals('4 live transients with non-overlapping chains must fit in 2 physical carrier slots',
        2, PoolCountFrame1);
    end else
      AssertTrue('Dedicated-allocation driver fallback must allocate <= 4 pooled transient textures',
        (PoolCountFrame1 >= 2) and (PoolCountFrame1 <= 4));

    { Execute Frame 1 on live GPU }
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    Graph.Execute(RealCmd);
    if VkT3.IsMemoryAliased then
      AssertTrue('Command list must record explicit VkMemoryBarrier2 / VkMemoryBarrier aliasing barriers',
        RealCmd.AliasingBarrierCount >= 1);
    RealDev.EndOffscreenFrame;

    AssertEquals('All 6 live passes must execute (DeadPass skipped)', 6, FRenderGraphPassExecCount);

    { Verify Frame 2 Reset + Re-Compile reuses cached carrier & aliased VkImage wrappers with zero new slots }
    Graph.Reset;
    HT1 := Graph.DeclareTransientTexture('Alias_T1_HDR64', DescT1);
    HT3 := Graph.DeclareTransientTexture('Alias_T3_R16F64', DescT3);
    HFinal := Graph.ImportExternalTexture('Alias_FinalLDR', FinalLDR, rsShaderRead, rsShaderRead);

    P0 := Graph.AddPass('Frame2_P0', rgptGraphics);
    P0.WriteColorAttachment(HT1, loClear, Vector4(0.4, 0.4, 0.4, 1.0), soStore);
    P2 := Graph.AddPass('Frame2_P1', rgptCompute);
    P2.ReadTexture(HT1, rsShaderRead);
    P2.WriteStorageTexture(HT3, rsUnorderedAccess);
    P5 := Graph.AddPass('Frame2_P2', rgptGraphics);
    P5.ReadTexture(HT3, rsShaderRead);
    P5.WriteColorAttachment(HFinal, loClear, Vector4(0.0, 0.0, 0.0, 1.0), soStore);
    P5.OnExecute := @Phase111AliasPass5Callback;

    Graph.Compile;
    AssertEquals('Second frame must reuse pooled carrier slots without growing pool',
      PoolCountFrame1, Graph.PhysicalTransientTextureCount);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    Graph.Execute(RealCmd);
    RealDev.EndOffscreenFrame;

    Readback := RealDev.GrabTextureImage(FinalLDR, Rectangle(0, 0, 64, 64));
    ExpectedImg := TRGBAlphaImage.Create(64, 64);
    ExpectedImg.Clear(Vector4Byte(Round(0.25 * 255), Round(0.55 * 255), Round(0.85 * 255), 255));
    AssertTrue('Perceptual diff on FinalLDR after multi-frame aliased RenderGraph execution must match (< 0.01 RMSE)',
      CompareImagesPerceptualDiff(Readback, ExpectedImg, 0.01, RMSE));
  finally
    FreeAndNil(ExpectedImg);
    FreeAndNil(Readback);
    FreeAndNil(Graph);
    FreeAndNil(FinalLDR);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeHDRBloomLuminanceHistogramAndTonemapPerceptualDiffRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  HDRPost: TCastleVulkanHDRPostProcessor;
  LDRTarget: TRHITexture;
  HDRUpload, HDRReadback, BloomReadback: TRGBAlphaFloatImage;
  LDRReadbackACES, LDRReadbackAgX, LDRNoBloom, LDRWithBloom, RefImg: TRGBAlphaImage;
  GpuBins: array[0..CASTLE_LUMINANCE_HISTOGRAM_BINS - 1] of Cardinal;
  BinSum, ExpectedBin: Cardinal;
  Lum, LogLumNorm, RMSE: Single;
  ExpColor: TVector3;
  X, Y: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  LDRTarget := nil;
  HDRUpload := nil;
  HDRReadback := nil;
  BloomReadback := nil;
  LDRReadbackACES := nil;
  LDRReadbackAgX := nil;
  LDRNoBloom := nil;
  LDRWithBloom := nil;
  RefImg := nil;
  try
    HDRPost := RealDev.HDRPostProcessor;
    HDRPost.EnsureHDRTargets(64, 64);
    LDRTarget := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuSampled, tuTransferSrc]));

    { 1. Upload linear HDR color (2.4, 0.8, 0.25, 1.0) into pfRGBA16_Float and verify float readback }
    HDRUpload := TRGBAlphaFloatImage.Create(64, 64);
    for Y := 0 to 63 do
      for X := 0 to 63 do
        HDRUpload.PixelPtr(X, Y)^ := Vector4(2.4, 0.8, 0.25, 1.0);
    HDRPost.HDRSceneTexture.UploadImage(HDRUpload);

    HDRReadback := RealDev.GrabTextureFloatImage(HDRPost.HDRSceneTexture, Rectangle(0, 0, 64, 64));
    AssertSameValue(2.4, HDRReadback.PixelPtr(32, 32)^.X, 0.01);
    AssertSameValue(0.8, HDRReadback.PixelPtr(32, 32)^.Y, 0.01);
    AssertSameValue(0.25, HDRReadback.PixelPtr(32, 32)^.Z, 0.01);

    { 2. Dispatch GPU LuminanceHistogramCS & verify atomic histogram bin counts on live Lavapipe }
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    HDRPost.DispatchLuminanceHistogramOnGPU(RealCmd, HDRPost.HDRSceneTexture);
    RealDev.EndOffscreenFrame;

    BinSum := HDRPost.ReadBackGpuHistogramBins(GpuBins);
    AssertEquals('GPU LuminanceHistogramCS must count all 64*64 = 4096 texels', 4096, Integer(BinSum));

    Lum := 2.4 * 0.2126 + 0.8 * 0.7152 + 0.25 * 0.0722;
    LogLumNorm := EnsureRange((Log2(Lum) - (-8.0)) / 12.0, 0.0, 1.0);
    ExpectedBin := Cardinal(EnsureRange(Trunc(LogLumNorm * 254.0 + 1.0), 1, 255));
    AssertEquals('Uniform HDR scene must accumulate all 4096 texels in ExpectedBin',
      4096, Integer(GpuBins[ExpectedBin]));

    { 3. Verify ACES Filmic & AgX Fullscreen Composite on live GPU against CPU reference via Perceptual Diff }
    HDRPost.Exposure := 1.15;
    HDRPost.Gamma := 2.2;
    HDRPost.Saturation := 1.12;
    HDRPost.Contrast := 1.06;
    HDRPost.EnableBloom := False;
    HDRPost.EnableAutoExposure := False;

    HDRPost.TonemapOperator := tmoACESFilmic;
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    HDRPost.ExecuteCompositePass(RealCmd, LDRTarget);
    RealDev.EndOffscreenFrame;
    LDRReadbackACES := RealDev.GrabTextureImage(LDRTarget, Rectangle(0, 0, 64, 64));

    ExpColor := HDRPost.EvaluateCompositeColor(Vector3(2.4, 0.8, 0.25), Vector3(0.0, 0.0, 0.0));
    RefImg := TRGBAlphaImage.Create(64, 64);
    RefImg.Clear(Vector4Byte(
      Byte(Round(ExpColor.X * 255.0)),
      Byte(Round(ExpColor.Y * 255.0)),
      Byte(Round(ExpColor.Z * 255.0)), 255));
    AssertTrue('GPU ACES Filmic + Color Grading + sRGB must match CPU reference (RMSE <= 0.015)',
      CompareImagesPerceptualDiff(LDRReadbackACES, RefImg, 0.015, RMSE));

    HDRPost.TonemapOperator := tmoAgX;
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    HDRPost.ExecuteCompositePass(RealCmd, LDRTarget);
    RealDev.EndOffscreenFrame;
    LDRReadbackAgX := RealDev.GrabTextureImage(LDRTarget, Rectangle(0, 0, 64, 64));

    ExpColor := HDRPost.EvaluateCompositeColor(Vector3(2.4, 0.8, 0.25), Vector3(0.0, 0.0, 0.0));
    RefImg.Clear(Vector4Byte(
      Byte(Round(ExpColor.X * 255.0)),
      Byte(Round(ExpColor.Y * 255.0)),
      Byte(Round(ExpColor.Z * 255.0)), 255));
    AssertTrue('GPU AgX Filmic + Color Grading + sRGB must match CPU reference (RMSE <= 0.015)',
      CompareImagesPerceptualDiff(LDRReadbackAgX, RefImg, 0.015, RMSE));

    { 4. Verify live GPU 13-tap Karis Bloom Downsample + 9-tap Tent Upsample halo spread }
    for Y := 0 to 63 do
      for X := 0 to 63 do
        if (X >= 28) and (X < 36) and (Y >= 28) and (Y < 36) then
          HDRUpload.PixelPtr(X, Y)^ := Vector4(12.0, 6.0, 2.0, 1.0)
        else
          HDRUpload.PixelPtr(X, Y)^ := Vector4(0.05, 0.05, 0.05, 1.0);
    HDRPost.HDRSceneTexture.UploadImage(HDRUpload);

    HDRPost.TonemapOperator := tmoACESFilmic;
    HDRPost.Exposure := 1.0;
    HDRPost.Saturation := 1.0;
    HDRPost.Contrast := 1.0;
    HDRPost.BloomThreshold := 1.0;
    HDRPost.BloomKnee := 0.5;
    HDRPost.BloomIntensity := 0.45;

    HDRPost.EnableBloom := False;
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    HDRPost.ExecuteCompositePass(RealCmd, LDRTarget);
    RealDev.EndOffscreenFrame;
    LDRNoBloom := RealDev.GrabTextureImage(LDRTarget, Rectangle(0, 0, 64, 64));

    HDRPost.EnableBloom := True;
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    HDRPost.DispatchBloomPyramid(RealCmd);
    HDRPost.ExecuteCompositePass(RealCmd, LDRTarget);
    RealDev.EndOffscreenFrame;

    BloomReadback := RealDev.GrabTextureFloatImage(HDRPost.BloomMipTextures[0],
      Rectangle(0, 0, HDRPost.BloomMipTextures[0].Desc.Width, HDRPost.BloomMipTextures[0].Desc.Height));
    LDRWithBloom := RealDev.GrabTextureImage(LDRTarget, Rectangle(0, 0, 64, 64));

    { Center of half-res BloomMip0 (16, 16) must be bright; halo at (11, 16) > 0; far corner (1, 1) near 0 }
    AssertTrue(Format('BloomMip0 center (16,16)=%.4f, (15,15)=%.4f, (11,16)=%.4f must have strong HDR energy (> 1.0)',
      [BloomReadback.PixelPtr(16, 16)^.X, BloomReadback.PixelPtr(15, 15)^.X, BloomReadback.PixelPtr(11, 16)^.X]),
      BloomReadback.PixelPtr(16, 16)^.X > 1.0);
    AssertTrue(Format('BloomMip0 halo (11,16)=%.4f outside 4x4 half-res core must spread positive glow (> 0.02)',
      [BloomReadback.PixelPtr(11, 16)^.X]),
      BloomReadback.PixelPtr(11, 16)^.X > 0.02);
    AssertTrue(Format('BloomMip0 far corner (1,1)=%.4f must remain small (< 0.25)',
      [BloomReadback.PixelPtr(1, 1)^.X]),
      BloomReadback.PixelPtr(1, 1)^.X < 0.25);
    AssertTrue(Format('Composited LDR pixel at halo (22, 32) WithBloom=%d vs NoBloom=%d',
      [LDRWithBloom.PixelPtr(22, 32)^.X, LDRNoBloom.PixelPtr(22, 32)^.X]),
      LDRWithBloom.PixelPtr(22, 32)^.X > LDRNoBloom.PixelPtr(22, 32)^.X + 8);
  finally
    FreeAndNil(RefImg);
    FreeAndNil(LDRWithBloom);
    FreeAndNil(LDRNoBloom);
    FreeAndNil(LDRReadbackAgX);
    FreeAndNil(LDRReadbackACES);
    FreeAndNil(BloomReadback);
    FreeAndNil(HDRReadback);
    FreeAndNil(HDRUpload);
    FreeAndNil(LDRTarget);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealLavapipeFullRenderGraphGTAOSSRAndPostProcessPipelineRHI;
var
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  HDRPost: TCastleVulkanHDRPostProcessor;
  Graph: TRHIRenderGraph;
  DepthTex, FinalLDRTex, RefLDRTex: TRHITexture;
  DepthUpload, GTAOReadback, LitHDRReadback, BloomMip0Readback: TRGBAlphaFloatImage;
  GraphLDRReadback, DirectRefReadback: TRGBAlphaImage;
  VkGTAORaw, VkSSR, VkHDRLit, VkBloomMip0: TVulkanRHITexture;
  GpuBins: array[0..CASTLE_LUMINANCE_HISTOGRAM_BINS - 1] of Cardinal;
  FlatAO, CreaseAO, SkyAO, RMSE: Single;
  X, Y: Integer;
begin
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    Exit;

  Graph := nil;
  DepthTex := nil;
  FinalLDRTex := nil;
  RefLDRTex := nil;
  DepthUpload := nil;
  GTAOReadback := nil;
  LitHDRReadback := nil;
  BloomMip0Readback := nil;
  GraphLDRReadback := nil;
  DirectRefReadback := nil;
  try
    { Part A: Direct GPU GTAO Horizon + Cross-Bilateral Denoise verification on synthetic depth step }
    DepthTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfD32_Float, [tuDepthStencil, tuSampled, tuTransferDst]));
    DepthUpload := TRGBAlphaFloatImage.Create(64, 64);
    for Y := 0 to 63 do
      for X := 0 to 63 do
      begin
        if Y >= 56 then
          DepthUpload.PixelPtr(X, Y)^ := Vector4(1.0, 0.0, 0.0, 1.0)   { Sky }
        else if (X >= 36) and (X <= 48) and (Y >= 16) and (Y <= 44) then
          DepthUpload.PixelPtr(X, Y)^ := Vector4(0.20, 0.0, 0.0, 1.0)  { Protruding occluder wall }
        else
          DepthUpload.PixelPtr(X, Y)^ := Vector4(0.50, 0.0, 0.0, 1.0); { Flat background plane }
      end;
    DepthTex.UploadImage(DepthUpload);

    RealDev.GTAO.ZNear := 0.1;
    RealDev.GTAO.ZFar := 10.0;
    RealDev.GTAO.EffectRadius := 1.5;
    RealDev.GTAO.Power := 1.5;
    RealDev.GTAO.EnsureGTAOTargets(64, 64, False);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    AssertEquals('DispatchGTAO must record 2 dispatches (Horizon + Denoise)',
      2, Integer(RealDev.GTAO.DispatchGTAO(RealCmd, DepthTex)));
    RealDev.EndOffscreenFrame;

    GTAOReadback := RealDev.GrabTextureFloatImage(RealDev.GTAO.DenoisedGTAOTexture, Rectangle(0, 0, 64, 64));
    SkyAO := GTAOReadback.PixelPtr(16, 60)^.X;
    FlatAO := GTAOReadback.PixelPtr(10, 30)^.X;
    CreaseAO := GTAOReadback.PixelPtr(34, 30)^.X; { Immediately adjacent to protruding z=0.20 wall }
    AssertSameValue(1.0, SkyAO, 0.01);
    AssertTrue(Format('Unoccluded flat plane FlatAO=%.4f must have high GTAO visibility (> 0.90)', [FlatAO]),
      FlatAO > 0.90);
    AssertTrue(Format('Depth crease CreaseAO=%.4f vs FlatAO=%.4f must exhibit GTAO darkening', [CreaseAO, FlatAO]),
      CreaseAO < FlatAO - 0.04);

    { Part B: Full 9-Pass BuildNextGenPostProcessRenderGraph Live Execution + Physical Aliasing + Perceptual Diff }
    FinalLDRTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuSampled, tuTransferSrc]));
    RefLDRTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(64, 64, pfRGBA8_UNorm, [tuColorAttachment, tuSampled, tuTransferSrc]));

    HDRPost := RealDev.HDRPostProcessor;
    HDRPost.Exposure := 1.05;
    HDRPost.Gamma := 2.2;
    HDRPost.Saturation := 1.05;
    HDRPost.Contrast := 1.02;
    HDRPost.TonemapOperator := tmoACESFilmic;
    HDRPost.EnableBloom := True;
    HDRPost.BloomIntensity := 0.25;
    HDRPost.AOStrength := 1.0;
    HDRPost.SSRStrength := 0.8;

    RealDev.SSR.ZNear := 0.1;
    RealDev.SSR.ZFar := 10.0;
    RealDev.SSR.Thickness := 0.35;
    RealDev.SSR.Intensity := 1.0;

    Graph := TRHIRenderGraph.Create(RealDev);
    FPhase111ForwardSubPassCounter := 0;
    HDRPost.BuildNextGenPostProcessRenderGraph(
      Graph, 64, 64, FinalLDRTex, @Phase111ForwardSceneCallback, True { IncludeDeadDebugPass });
    Graph.Compile;

    AssertEquals('Next-Gen graph with dead debug pass must register 10 passes', 10, Graph.PassCount);
    AssertEquals('Dead-pass culling must cull the unreferenced debug pass', 1, Graph.CulledPassCount);
    AssertEquals('Compiled active pass count must be 9', 9, Graph.CompiledPassCount);
    AssertTrue('Next-Gen graph must alias transient physical memory (>= 2 aliased textures)',
      Graph.MemoryAliasedTextureCount >= 2);
    AssertTrue('Next-Gen graph must save transient VRAM bytes (> 0)',
      Graph.AliasedMemorySavedBytes > 0);
    AssertTrue('Next-Gen graph must hoist explicit memory aliasing barriers (>= 2)',
      Graph.AliasingBarrierCount >= 2);

    VkGTAORaw := Graph.ResolvePhysicalTexture(HDRPost.RGGTAORawHandle) as TVulkanRHITexture;
    VkSSR := Graph.ResolvePhysicalTexture(HDRPost.RGSSRReflectionHandle) as TVulkanRHITexture;
    VkHDRLit := Graph.ResolvePhysicalTexture(HDRPost.RGSceneHDRLitHandle) as TVulkanRHITexture;
    VkBloomMip0 := Graph.ResolvePhysicalTexture(HDRPost.RGBloomMip0Handle) as TVulkanRHITexture;
    AssertTrue('All active transient RenderGraph handles must resolve to physical textures',
      (VkGTAORaw <> nil) and (VkSSR <> nil) and (VkHDRLit <> nil) and (VkBloomMip0 <> nil));
    { GTAORaw (passes 2..3) and SSRReflection (passes 4..5) have non-overlapping lifetimes -> share VkDeviceMemory! }
    AssertTrue('GTAORaw and SSRReflection must have distinct VkImage handles',
      VkGTAORaw.Image <> VkSSR.Image);
    AssertTrue('Non-overlapping transient targets must share physical VkDeviceMemory',
      (VkGTAORaw.DeviceMemory = VkSSR.DeviceMemory) or
      (VkGTAORaw.DeviceMemory = VkHDRLit.DeviceMemory) or
      (VkSSR.DeviceMemory = VkBloomMip0.DeviceMemory));

    { Execute all 9 compiled passes on live Mesa Lavapipe! }
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    Graph.Execute(RealCmd);
    RealDev.EndOffscreenFrame;

    AssertEquals('Forward3DHDRPass callback must execute once', 1, FPhase111ForwardSubPassCounter);
    AssertEquals('GPU LuminanceHistogramCS inside RenderGraph must count all 4096 pixels',
      4096, Integer(HDRPost.ReadBackGpuHistogramBins(GpuBins)));

    GraphLDRReadback := RealDev.GrabTextureImage(FinalLDRTex, Rectangle(0, 0, 64, 64));

    { Build independent reference composite from the resolved LitHDR + BloomMip0 textures and verify Perceptual Diff }
    LitHDRReadback := RealDev.GrabTextureFloatImage(VkHDRLit, Rectangle(0, 0, 64, 64));
    BloomMip0Readback := RealDev.GrabTextureFloatImage(VkBloomMip0, Rectangle(0, 0, 32, 32));
    AssertTrue('LitHDR center emissive core (32,32) must retain bright HDR radiance (> 4.0)',
      LitHDRReadback.PixelPtr(32, 32)^.X > 4.0);
    AssertTrue('BloomMip0 center (16,16) must contain downsampled/upsampled bloom energy (> 0.5)',
      BloomMip0Readback.PixelPtr(16, 16)^.X > 0.5);

    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    HDRPost.ExecuteCompositeFromTextures(RealCmd, VkHDRLit, VkBloomMip0, RefLDRTex, False);
    RealDev.EndOffscreenFrame;
    DirectRefReadback := RealDev.GrabTextureImage(RefLDRTex, Rectangle(0, 0, 64, 64));

    AssertTrue('RenderGraph TonemapCompositePass output must perceptually match reference composite (RMSE <= 0.01)',
      CompareImagesPerceptualDiff(GraphLDRReadback, DirectRefReadback, 0.01, RMSE));
    { Also verify spatial structure of final tonemapped LDR frame: sky border dark, mid plane lit, emissive core brightest }
    AssertTrue(Format('Sky border pixel (1,1)=%d must remain dark (< 75)', [GraphLDRReadback.PixelPtr(1, 1)^.X]),
      GraphLDRReadback.PixelPtr(1, 1)^.X < 75);
    AssertTrue(Format('Foreground lit surface (14,14)=%d must be much brighter than sky border (%d)',
      [GraphLDRReadback.PixelPtr(14, 14)^.X, GraphLDRReadback.PixelPtr(1, 1)^.X]),
      Integer(GraphLDRReadback.PixelPtr(14, 14)^.X) > Integer(GraphLDRReadback.PixelPtr(1, 1)^.X) + 80);
    AssertTrue(Format('Emissive core (32,32)=%d must be brightest (> 235)', [GraphLDRReadback.PixelPtr(32, 32)^.X]),
      GraphLDRReadback.PixelPtr(32, 32)^.X > 235);
  finally
    FreeAndNil(DirectRefReadback);
    FreeAndNil(GraphLDRReadback);
    FreeAndNil(BloomMip0Readback);
    FreeAndNil(LitHDRReadback);
    FreeAndNil(GTAOReadback);
    FreeAndNil(DepthUpload);
    FreeAndNil(RefLDRTex);
    FreeAndNil(FinalLDRTex);
    FreeAndNil(DepthTex);
    FreeAndNil(Graph);
    FreeAndNil(RealDev);
  end;
end;

type
  TPhase112VisualParity2DControl = class(TCastleUserInterface)
  private
    FSprite: TDrawableImage;
    procedure EnsureSprite;
  public
    destructor Destroy; override;
    procedure GLContextClose; override;
    procedure Render; override;
  end;

procedure TPhase112VisualParity2DControl.EnsureSprite;
var
  Img: TRGBAlphaImage;
  X, Y: Integer;
begin
  if FSprite <> nil then Exit;
  Img := TRGBAlphaImage.Create(32, 32);
  for Y := 0 to 31 do
    for X := 0 to 31 do
    begin
      if ((X div 8) + (Y div 8)) mod 2 = 0 then
        Img.PixelPtr(X, Y)^ := Vector4Byte(245, 210, 40, 255)
      else
        Img.PixelPtr(X, Y)^ := Vector4Byte(40, 185, 240, 255);
    end;
  FSprite := TDrawableImage.Create(Img, False { SmoothScaling }, True { OwnsImage });
end;

procedure TPhase112VisualParity2DControl.GLContextClose;
begin
  FreeAndNil(FSprite);
  inherited;
end;

destructor TPhase112VisualParity2DControl.Destroy;
begin
  FreeAndNil(FSprite);
  inherited;
end;

procedure TPhase112VisualParity2DControl.Render;
begin
  inherited;
  DrawRectangle(FloatRectangle(0, 0, 160, 120), Vector4(0.10, 0.12, 0.18, 1.0));
  DrawRectangle(FloatRectangle(12, 14, 62, 92), Vector4(0.88, 0.22, 0.20, 1.0));
  DrawRectangle(FloatRectangle(48, 28, 66, 64), Vector4(0.18, 0.76, 0.36, 1.0));
  EnsureSprite;
  FSprite.Draw(FloatRectangle(92, 28, 56, 56));
end;

procedure TTestCastleVulkanRHI.TestVulkanValidationLayerDebugMessengerAndZeroErrorGateRHI;
var
  Layers: TAnsiStringArray;
  HasDebugUtils: Boolean;
  RealDev: TVulkanRHIDevice;
  RealCmd: TVulkanRHICommandList;
  ColorTex: TRHITexture;
  Readback: TRGBAlphaImage;
  PassInfo: TRHIRenderingInfo;
  RoutedViaLoader, CaughtGateError: Boolean;
  GateErrMsg, ReportStr, InfoStr: String;
begin
  try
    if not LoadVulkan then
      Exit;
  except
    on Exception do
      Exit;
  end;

  Layers := QuerySupportedVulkanInstanceLayers;
  AssertTrue('vkEnumerateInstanceLayerProperties must be bound when Vulkan loader is present',
    Assigned(vkEnumerateInstanceLayerProperties));
  { Layers may be 0 or >= 1 depending on installed OS layers; verify IsVulkanInstanceLayerSupported consistency }
  if Length(Layers) > 0 then
    AssertTrue('First enumerated Vulkan layer must report supported',
      IsVulkanInstanceLayerSupported(Layers[0]));
  HasDebugUtils := IsVulkanInstanceExtensionSupported(VK_EXT_debug_utils);

  RealDev := nil;
  try
    RealDev := TVulkanRHIDevice.CreateOffscreen(True { EnableValidation });
  except
    on Exception do
    begin
      FreeAndNil(RealDev);
      Exit;
    end;
  end;

  ColorTex := nil;
  Readback := nil;
  try
    if HasDebugUtils then
    begin
      AssertTrue('DebugUtilsActive must be True when VK_EXT_debug_utils is supported and EnableValidation=True',
        RealDev.DebugUtilsActive);
      AssertTrue('FDebugMessenger handle must be created via vkCreateDebugUtilsMessengerEXT',
        RealDev.DebugMessengerHandle <> VK_NULL_HANDLE);
    end;

    { 1. Clean device startup must produce 0 validation errors }
    AssertEquals('Fresh TVulkanRHIDevice startup must emit 0 validation errors',
      0, Integer(RealDev.ValidationErrorCount));
    RealDev.AssertZeroValidationErrors('OffscreenDeviceStartup');

    InfoStr := RealDev.GetInformationString;
    AssertTrue('GetInformationString must report validation layer & messenger diagnostics',
      Pos('Validation layer (VK_LAYER_KHRONOS_validation):', InfoStr) > 0);

    { 2. Live round-trip through vkSubmitDebugUtilsMessageEXT -> Vulkan Loader -> C Callback -> TVulkanRHIDevice }
    RealDev.ResetValidationCounters;
    RealDev.StrictValidationGate := False;

    RoutedViaLoader := RealDev.SubmitDebugUtilsMessage(
      VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
      VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
      'VUID-CastleTest-PerfWarning-001',
      'Synthetic performance warning routed through debug messenger');
    if HasDebugUtils and (RealDev.DebugMessengerHandle <> VK_NULL_HANDLE) and
       Assigned(vkSubmitDebugUtilsMessageEXT) then
      AssertTrue('SubmitDebugUtilsMessage must route through live vkSubmitDebugUtilsMessageEXT',
        RoutedViaLoader);

    AssertEquals('ValidationWarningCount must increment to 1', 1, Integer(RealDev.ValidationWarningCount));
    AssertEquals('ValidationErrorCount must remain 0 on warning', 0, Integer(RealDev.ValidationErrorCount));
    { Non-strict gate allows warnings while blocking errors }
    RealDev.AssertZeroValidationErrors('NonStrictWarningAllowed');

    { Strict CI gate rejects warnings too }
    RealDev.StrictValidationGate := True;
    CaughtGateError := False;
    GateErrMsg := '';
    try
      RealDev.AssertZeroValidationErrors('StrictGateCheck');
    except
      on E: ERHIError do
      begin
        CaughtGateError := True;
        GateErrMsg := E.Message;
      end;
    end;
    AssertTrue('StrictValidationGate=True must raise ERHIError when ValidationWarningCount > 0', CaughtGateError);
    AssertTrue('Strict gate exception must include VUID identifier',
      Pos('VUID-CastleTest-PerfWarning-001', GateErrMsg) > 0);

    { 3. Validation error always trips AssertZeroValidationErrors even when StrictValidationGate=False }
    RealDev.StrictValidationGate := False;
    RealDev.SubmitDebugUtilsMessage(
      VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
      VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
      'VUID-vkCmdDraw-None-08600',
      'Synthetic validation error routed through debug messenger');
    AssertEquals('ValidationErrorCount must increment to 1', 1, Integer(RealDev.ValidationErrorCount));
    AssertEquals('ValidationMessageCount must equal 2', 2, RealDev.ValidationMessageCount);
    ReportStr := RealDev.GetValidationMessagesReport;
    AssertTrue('Validation report must include warning VUID',
      Pos('VUID-CastleTest-PerfWarning-001', ReportStr) > 0);
    AssertTrue('Validation report must include error VUID',
      Pos('VUID-vkCmdDraw-None-08600', ReportStr) > 0);

    CaughtGateError := False;
    try
      RealDev.AssertZeroValidationErrors('DefaultErrorGateCheck');
    except
      on E: ERHIError do
        CaughtGateError := True;
    end;
    AssertTrue('ValidationErrorCount > 0 must raise ERHIError in AssertZeroValidationErrors', CaughtGateError);

    { 4. Reset counters and execute a real Lavapipe render pass + image readback with 0 validation errors }
    RealDev.ResetValidationCounters;
    AssertEquals(0, Integer(RealDev.ValidationErrorCount));
    AssertEquals(0, Integer(RealDev.ValidationWarningCount));
    AssertEquals(0, RealDev.ValidationMessageCount);

    ColorTex := RealDev.CreateTexture(
      TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuTransferSrc]));
    RealCmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    RealCmd.TransitionTexture(ColorTex, rsColorAttachment);
    FillChar(PassInfo, SizeOf(PassInfo), 0);
    PassInfo.RenderArea := Rectangle(0, 0, 32, 32);
    SetLength(PassInfo.ColorAttachments, 1);
    PassInfo.ColorAttachments[0].Texture := ColorTex;
    PassInfo.ColorAttachments[0].LoadOp := loClear;
    PassInfo.ColorAttachments[0].StoreOp := soStore;
    PassInfo.ColorAttachments[0].ClearColor := Vector4(0.2, 0.6, 0.9, 1.0);
    RealCmd.BeginRendering(PassInfo);
    RealCmd.EndRendering;
    RealDev.EndOffscreenFrame;

    Readback := RealDev.GrabTextureImage(ColorTex, Rectangle(0, 0, 32, 32));
    AssertTrue('Cleared blue channel must read back > 200', Readback.PixelPtr(16, 16)^.Z > 200);
    RealDev.AssertZeroValidationErrors('LiveOffscreenRenderAndReadback');
  finally
    FreeAndNil(Readback);
    FreeAndNil(ColorTex);
    FreeAndNil(RealDev);
  end;
end;

procedure TTestCastleVulkanRHI.TestRealOpenGLVsVulkanSideBySideVisualRegressionSuiteRHI;

  procedure Populate3DLitOccludedBoxesScene(const AWindow: TCastleWindow);
  var
    Viewport: TCastleViewport;
    Scene: TCastleScene;
    Root: TX3DRootNode;
    DirLight: TDirectionalLightNode;
    FrontTrans, BackTrans: TTransformNode;
    FrontShape, BackShape: TShapeNode;
    FrontBox, BackBox: TBoxNode;
    FrontApp, BackApp: TAppearanceNode;
    FrontMat, BackMat: TMaterialNode;
  begin
    Viewport := TCastleViewport.Create(AWindow);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.05, 0.07, 0.22, 1.0);
    AWindow.Controls.InsertFront(Viewport);
    Viewport.Camera.ProjectionType := ptPerspective;
    Viewport.Camera.SetWorldView(
      Vector3(0.0, 0.0, 4.5),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    Root := TX3DRootNode.Create;
    DirLight := TDirectionalLightNode.Create;
    DirLight.Direction := Vector3(-0.25, -0.35, -1.0).Normalize;
    DirLight.Intensity := 1.0;
    DirLight.AmbientIntensity := 0.2;
    Root.AddChildren(DirLight);

    { Rear box at Z = -1.2 shifted up-right — partially occluded by front box! }
    BackTrans := TTransformNode.Create;
    BackTrans.Translation := Vector3(0.85, 0.65, -1.2);
    BackShape := TShapeNode.Create;
    BackBox := TBoxNode.Create;
    BackBox.Size := Vector3(1.8, 1.5, 0.6);
    BackShape.Geometry := BackBox;
    BackApp := TAppearanceNode.Create;
    BackMat := TMaterialNode.Create;
    BackMat.DiffuseColor := Vector3(0.15, 0.85, 0.55);
    BackMat.AmbientIntensity := 0.25;
    BackMat.SpecularColor := Vector3(0.0, 0.0, 0.0);
    BackApp.Material := BackMat;
    BackShape.Appearance := BackApp;
    BackTrans.AddChildren(BackShape);
    Root.AddChildren(BackTrans);

    { Front occluder box at Z = 0.2 shifted down-left }
    FrontTrans := TTransformNode.Create;
    FrontTrans.Translation := Vector3(-0.35, -0.25, 0.2);
    FrontShape := TShapeNode.Create;
    FrontBox := TBoxNode.Create;
    FrontBox.Size := Vector3(1.7, 1.5, 0.6);
    FrontShape.Geometry := FrontBox;
    FrontApp := TAppearanceNode.Create;
    FrontMat := TMaterialNode.Create;
    FrontMat.DiffuseColor := Vector3(0.92, 0.30, 0.12);
    FrontMat.AmbientIntensity := 0.25;
    FrontMat.SpecularColor := Vector3(0.0, 0.0, 0.0);
    FrontApp.Material := FrontMat;
    FrontShape.Appearance := FrontApp;
    FrontTrans.AddChildren(FrontShape);
    Root.AddChildren(FrontTrans);

    Scene := TCastleScene.Create(AWindow);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
  end;

  procedure Populate3DTexturedAlphaMaskScene(const AWindow: TCastleWindow);
  var
    Viewport: TCastleViewport;
    Scene: TCastleScene;
    Root: TX3DRootNode;
    BackTrans, FrontTrans: TTransformNode;
    BackShape, FrontShape: TShapeNode;
    BackBox, FrontBox: TBoxNode;
    BackApp, FrontApp: TAppearanceNode;
    BackMat, FrontMat: TUnlitMaterialNode;
    PixTex: TPixelTextureNode;
    TexProps: TTexturePropertiesNode;
    MaskImg: TRGBAlphaImage;
    X, Y: Integer;
  begin
    Viewport := TCastleViewport.Create(AWindow);
    Viewport.FullSize := True;
    Viewport.BackgroundColor := Vector4(0.08, 0.08, 0.12, 1.0);
    AWindow.Controls.InsertFront(Viewport);
    Viewport.Camera.ProjectionType := ptPerspective;
    Viewport.Camera.SetWorldView(
      Vector3(0.0, 0.0, 4.0),
      Vector3(0.0, 0.0, -1.0),
      Vector3(0.0, 1.0, 0.0));

    Root := TX3DRootNode.Create;

    { Solid magenta/purple backdrop plate visible through alpha-masked cutout }
    BackTrans := TTransformNode.Create;
    BackTrans.Translation := Vector3(0.0, 0.0, -0.8);
    BackShape := TShapeNode.Create;
    BackBox := TBoxNode.Create;
    BackBox.Size := Vector3(2.8, 2.0, 0.2);
    BackShape.Geometry := BackBox;
    BackApp := TAppearanceNode.Create;
    BackMat := TUnlitMaterialNode.Create;
    BackMat.EmissiveColor := Vector3(0.75, 0.18, 0.68);
    BackApp.Material := BackMat;
    BackShape.Appearance := BackApp;
    BackTrans.AddChildren(BackShape);
    Root.AddChildren(BackTrans);

    { Foreground unlit textured plate with alpha-cutoff hole in center }
    FrontTrans := TTransformNode.Create;
    FrontTrans.Translation := Vector3(0.0, 0.0, 0.3);
    FrontShape := TShapeNode.Create;
    FrontBox := TBoxNode.Create;
    FrontBox.Size := Vector3(2.0, 1.6, 0.1);
    FrontShape.Geometry := FrontBox;
    FrontApp := TAppearanceNode.Create;
    BackApp.AlphaMode := amOpaque;
    FrontApp.AlphaMode := amMask;
    FrontApp.AlphaCutoff := 0.5;

    MaskImg := TRGBAlphaImage.Create(16, 16);
    for Y := 0 to 15 do
      for X := 0 to 15 do
      begin
        { Cutout window in center [5..10, 5..10] with alpha = 0 }
        if (X >= 5) and (X <= 10) and (Y >= 5) and (Y <= 10) then
          MaskImg.PixelPtr(X, Y)^ := Vector4Byte(0, 0, 0, 0)
        else if ((X div 4) + (Y div 4)) mod 2 = 0 then
          MaskImg.PixelPtr(X, Y)^ := Vector4Byte(240, 220, 50, 255)
        else
          MaskImg.PixelPtr(X, Y)^ := Vector4Byte(45, 205, 95, 255);
      end;

    PixTex := TPixelTextureNode.Create;
    PixTex.FdImage.Value := MaskImg;
    TexProps := TTexturePropertiesNode.Create;
    TexProps.MagnificationFilter := magNearest;
    TexProps.MinificationFilter := minNearest;
    PixTex.TextureProperties := TexProps;

    FrontMat := TUnlitMaterialNode.Create;
    FrontMat.EmissiveColor := Vector3(1.0, 1.0, 1.0);
    FrontMat.EmissiveTexture := PixTex;
    FrontApp.Material := FrontMat;
    FrontShape.Appearance := FrontApp;
    FrontTrans.AddChildren(FrontShape);
    Root.AddChildren(FrontTrans);

    Scene := TCastleScene.Create(AWindow);
    Scene.Load(Root, True);
    Viewport.Items.Add(Scene);
  end;

  function CaptureBackendScenarios(const ABackend: TRenderBackend;
    out AShot2D, AShot3DLit, AShot3DMask: TRGBAlphaImage;
    out AVkValidationErrors: Cardinal): Boolean;
  var
    Win: TCastleWindow;
    UI2D: TPhase112VisualParity2DControl;
    I: Integer;
  begin
    Result := False;
    AShot2D := nil;
    AShot3DLit := nil;
    AShot3DMask := nil;
    AVkValidationErrors := 0;

    SetActiveCommandList(nil);
    SetRHIDevice(nil);
    ApplicationProperties.RenderBackend := ABackend;
    Application.OnInitialize := nil;
    Application.Initialize;

    Win := CreateWindowForTest;
    try
      Win.Width := 160;
      Win.Height := 120;
      Win.AntiAliasing := aaNone;
      try
        Win.Open;
      except
        on Exception do
        begin
          if not Win.Closed then
            Win.Close(False);
          Exit(False);
        end;
      end;

      if ABackend = backendVulkan then
      begin
        if not (RHIDevice is TVulkanRHIDevice) then
        begin
          Win.Close(False);
          Exit(False);
        end;
        TVulkanRHIDevice(RHIDevice).ResetValidationCounters;
      end else
      begin
        if RHIDevice <> nil then
        begin
          Win.Close(False);
          Exit(False);
        end;
      end;

      { Scenario 1: 2D UI rectangles + textured sprite }
      UI2D := TPhase112VisualParity2DControl.Create(Win);
      UI2D.FullSize := True;
      Win.Controls.InsertFront(UI2D);
      for I := 0 to 1 do
      begin
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      AShot2D := Win.Container.SaveScreenRgba;
      Win.Controls.Remove(UI2D);
      FreeAndNil(UI2D);

      { Scenario 2: 3D directional-lit depth-occluded boxes }
      Populate3DLitOccludedBoxesScene(Win);
      for I := 0 to 1 do
      begin
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      AShot3DLit := Win.Container.SaveScreenRgba;
      while Win.Controls.Count > 0 do
        Win.Controls[0].Free;

      { Scenario 3: 3D unlit procedural texture + amMask alpha-cutoff hole }
      Populate3DTexturedAlphaMaskScene(Win);
      for I := 0 to 1 do
      begin
        Win.Invalidate;
        Application.ProcessAllMessages;
      end;
      AShot3DMask := Win.Container.SaveScreenRgba;
      while Win.Controls.Count > 0 do
        Win.Controls[0].Free;

      if (ABackend = backendVulkan) and (RHIDevice is TVulkanRHIDevice) then
        AVkValidationErrors := TVulkanRHIDevice(RHIDevice).ValidationErrorCount;

      Win.Close(False);
      Result := (AShot2D <> nil) and (AShot3DLit <> nil) and (AShot3DMask <> nil);
    finally
      DestroyWindowForTest(Win);
    end;
  end;

var
  SyntheticRef, SyntheticCand: TRGBAlphaImage;
  DiffStats: TRHIVisualDiffMetrics;
  UnitSuite, LiveSuite: TRHIVisualRegressionSuite;
  VkShot2D, VkShot3DLit, VkShot3DMask: TRGBAlphaImage;
  GlShot2D, GlShot3DLit, GlShot3DMask: TRGBAlphaImage;
  SavedRHI: TRHIDevice;
  SavedCmd: TRHICommandList;
  SavedBackend: TRenderBackend;
  SavedOnInit: TProcedure;
  VkValErrors, DummyGlErrors: Cardinal;
  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay: Boolean;
  {$endif}
begin
  { Part A: Deterministic unit verification of CompareImagesDetailedDiff & TRHIVisualRegressionSuite }
  SyntheticRef := TRGBAlphaImage.Create(16, 16);
  SyntheticCand := TRGBAlphaImage.Create(16, 16);
  UnitSuite := TRHIVisualRegressionSuite.Create(2);
  try
    SyntheticRef.Clear(Vector4Byte(60, 120, 200, 255));
    SyntheticCand.Clear(Vector4Byte(60, 120, 200, 255));
    AssertTrue('Identical images must pass with 0 RMSE',
      CompareImagesDetailedDiff(SyntheticRef, SyntheticCand, 0.001, DiffStats, 2));
    AssertSameValue(0.0, DiffStats.NormalizedRMSE, 1e-6);
    AssertSameValue(99.0, DiffStats.PSNRdB, 1e-3);
    AssertEquals(0, Integer(DiffStats.MaxChannelDelta));
    AssertEquals(0, Integer(DiffStats.DiffPixelCount));

    { Perturb 1 pixel by +20 on red channel -> MaxChannelDelta=20, DiffPixelCount=1 }
    SyntheticCand.PixelPtr(8, 8)^ := Vector4Byte(80, 120, 200, 255);
    UnitSuite.RecordComparison('Synthetic_NearExact', SyntheticRef, SyntheticCand, 0.02);
    AssertEquals(1, UnitSuite.CaseCount);
    AssertEquals(1, UnitSuite.PassedCount);
    AssertEquals(0, UnitSuite.FailedCount);
    AssertTrue(UnitSuite.AllPassed);
    AssertEquals(20, Integer(UnitSuite.GetCaseResult(0).Metrics.MaxChannelDelta));
    AssertEquals(1, Integer(UnitSuite.GetCaseResult(0).Metrics.DiffPixelCount));
    AssertTrue('Summary report must list PASS status',
      Pos('[PASS] Synthetic_NearExact', UnitSuite.BuildSummaryReport) > 0);
  finally
    FreeAndNil(UnitSuite);
    FreeAndNil(SyntheticCand);
    FreeAndNil(SyntheticRef);
  end;

  { Part B: Live side-by-side backendVulkan vs backendOpenGL TCastleWindow visual regression suite }
  if not CanCreateWindowForTest then
    Exit;

  {$if defined(UNIX) and not defined(DARWIN) and not defined(ANDROID)}
  HasDisplay := (GetEnvironmentVariable('DISPLAY') <> '') or
                (GetEnvironmentVariable('WAYLAND_DISPLAY') <> '');
  if not HasDisplay then
    Exit;
  {$endif}

  try
    if not LoadVulkan then
      Exit;
  except
    on Exception do
      Exit;
  end;

  SavedRHI := RHIDevice;
  SavedCmd := ActiveCommandList;
  SavedBackend := ApplicationProperties.RenderBackend;
  SavedOnInit := Application.OnInitialize;
  VkShot2D := nil;
  VkShot3DLit := nil;
  VkShot3DMask := nil;
  GlShot2D := nil;
  GlShot3DLit := nil;
  GlShot3DMask := nil;
  LiveSuite := TRHIVisualRegressionSuite.Create(4);
  try
    { 1. Render all 3 scenarios on pure-Vulkan TCastleWindow first }
    if not CaptureBackendScenarios(backendVulkan, VkShot2D, VkShot3DLit, VkShot3DMask, VkValErrors) then
      Exit;
    AssertEquals('Vulkan visual regression capture must produce 0 validation errors',
      0, Integer(VkValErrors));

    { 2. Render the exact same 3 scenarios on real OpenGL TCastleWindow }
    if not CaptureBackendScenarios(backendOpenGL, GlShot2D, GlShot3DLit, GlShot3DMask, DummyGlErrors) then
      Exit;

    { 3. Run side-by-side perceptual RMSE comparison across all 3 scenarios }
    LiveSuite.RecordComparison('2D_UI_Rectangles_And_TexturedSprite', GlShot2D, VkShot2D, 0.04);
    LiveSuite.RecordComparison('3D_Viewport_DirectionalLit_DepthOccluded_Boxes', GlShot3DLit, VkShot3DLit, 0.08);
    LiveSuite.RecordComparison('3D_Viewport_Unlit_ProceduralTextured_AlphaMask_Quad', GlShot3DMask, VkShot3DMask, 0.06);

    AssertEquals('Live regression suite must record 3 scenarios', 3, LiveSuite.CaseCount);
    AssertTrue('All side-by-side rbOpenGL vs rbVulkan visual regression cases must pass: ' +
      LineEnding + LiveSuite.BuildSummaryReport,
      LiveSuite.AllPassed);
  finally
    SetActiveCommandList(SavedCmd);
    SetRHIDevice(SavedRHI);
    ApplicationProperties.RenderBackend := SavedBackend;
    Application.OnInitialize := SavedOnInit;
    FreeAndNil(LiveSuite);
    FreeAndNil(GlShot3DMask);
    FreeAndNil(GlShot3DLit);
    FreeAndNil(GlShot2D);
    FreeAndNil(VkShot3DMask);
    FreeAndNil(VkShot3DLit);
    FreeAndNil(VkShot2D);
  end;
end;

procedure TTestCastleVulkanRHI.TestShaderAndPipelineCachePackageBundlingAndDataSeedRHI;
var
  Compiler: TCastleShaderCompiler;
  SavedDiskBaseUrl, SavedBundledBaseUrl: String;
  TempRootDir, TempProjectDir, TempManifestFile: String;
  TempBuildCacheDir, TempPackagedDataDir, TempEmptyUserConfigDir: String;
  TempSrcPipelineCacheFile, TempBundledPipelineCacheFile, TempMissingUserPipelineCacheUrl: String;
  ManifestText: TStringList;
  Manifest: TCastleManifest;
  RealDev: TVulkanRHIDevice;
  BundledSpvCount: Cardinal;
  Gen: TCastleShaderGeneratorRHI;
  CoreForwardVS: String;
  LoadedSPIRV: TSPIRVBytecode;
  Reflected: TSPIRVReflectionInfo;
begin
  Compiler := TCastleShaderCompiler.Instance;
  SavedDiskBaseUrl := Compiler.DiskCacheBaseUrl;
  SavedBundledBaseUrl := Compiler.BundledCacheBaseUrl;

  TempRootDir := InclPathDelim(GetTempDir(False)) +
    'cge_phase112_bundle_' + IntToStr(Random(1000000));
  TempProjectDir := InclPathDelim(TempRootDir) + 'proj';
  TempBuildCacheDir := InclPathDelim(TempRootDir) + 'build_config_cache';
  TempPackagedDataDir := InclPathDelim(TempProjectDir) + 'data';
  TempEmptyUserConfigDir := InclPathDelim(TempRootDir) + 'fresh_user_config';
  CheckForceDirectories(TempPackagedDataDir);
  CheckForceDirectories(TempBuildCacheDir);
  CheckForceDirectories(TempEmptyUserConfigDir);

  ManifestText := TStringList.Create;
  Manifest := nil;
  RealDev := nil;
  Gen := nil;
  try
    { 1. Verify TCastleManifest ShouldBundleVulkanCaches parsing }
    TempManifestFile := InclPathDelim(TempProjectDir) + 'CastleEngineManifest.xml';
    ManifestText.Text :=
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<project name="phase112_pkg_test" standalone_source="phase112_pkg_test.dpr" render_backend="vulkan">' + LineEnding +
      '</project>';
    ManifestText.SaveToFile(TempManifestFile);

    Manifest := TCastleManifest.CreateFromUrl(FilenameToUriSafe(TempManifestFile));
    AssertTrue('render_backend="vulkan" must enable ShouldPrewarmVulkanShaders',
      Manifest.ShouldPrewarmVulkanShaders);
    AssertTrue('render_backend="vulkan" must enable ShouldBundleVulkanCaches by default',
      Manifest.ShouldBundleVulkanCaches);
    FreeAndNil(Manifest);

    ManifestText.Text :=
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<project name="phase112_pkg_test" standalone_source="phase112_pkg_test.dpr" render_backend="vulkan" bundle_vulkan_caches="false">' + LineEnding +
      '</project>';
    ManifestText.SaveToFile(TempManifestFile);
    Manifest := TCastleManifest.CreateFromUrl(FilenameToUriSafe(TempManifestFile));
    AssertFalse('bundle_vulkan_caches="false" must disable ShouldBundleVulkanCaches',
      Manifest.ShouldBundleVulkanCaches);
    FreeAndNil(Manifest);

    ManifestText.Text :=
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<project name="phase112_pkg_test" standalone_source="phase112_pkg_test.dpr" render_backend="opengl">' + LineEnding +
      '</project>';
    ManifestText.SaveToFile(TempManifestFile);
    Manifest := TCastleManifest.CreateFromUrl(FilenameToUriSafe(TempManifestFile));
    AssertFalse('render_backend="opengl" must disable ShouldBundleVulkanCaches',
      Manifest.ShouldBundleVulkanCaches);
    FreeAndNil(Manifest);

    { 2. Point compiler disk cache to isolated TempBuildCacheDir and bundle into TempPackagedDataDir }
    Compiler.DiskCacheBaseUrl := FilenameToUriSafe(InclPathDelim(TempBuildCacheDir));
    Compiler.BundledCacheBaseUrl := '';
    Compiler.ClearCache(False);

    TempSrcPipelineCacheFile := InclPathDelim(TempRootDir) + 'prebaked_pipeline_cache.bin';
    if TVulkanRHIDevice.TryCreateOffscreen(RealDev) then
    begin
      RealDev.PrewarmStandardPipelines(True, True, FilenameToUriSafe(TempSrcPipelineCacheFile));
      RealDev.SavePipelineCache(FilenameToUriSafe(TempSrcPipelineCacheFile));
    end;

    BundledSpvCount := Compiler.BundleCoreAndCachedShadersToDataDirectory(
      TempPackagedDataDir, FilenameToUriSafe(TempSrcPipelineCacheFile));
    AssertTrue(Format('BundleCoreAndCachedShadersToDataDirectory must write >= 4 .spv files (got %d)',
      [BundledSpvCount]), BundledSpvCount >= 4);
    AssertTrue('Packaged shader_cache directory must exist',
      DirectoryExists(InclPathDelim(TempPackagedDataDir) + 'shader_cache'));

    TempBundledPipelineCacheFile := InclPathDelim(TempPackagedDataDir) + 'vulkan_pipeline_cache.bin';
    if RegularFileExists(TempSrcPipelineCacheFile) then
      AssertTrue('Pre-baked vulkan_pipeline_cache.bin must be bundled into packaged data/',
        RegularFileExists(TempBundledPipelineCacheFile));

    { 3. Simulate cold first boot on a fresh machine: empty DiskCacheBaseUrl + read-only BundledCacheBaseUrl }
    Compiler.DiskCacheBaseUrl := FilenameToUriSafe(InclPathDelim(TempEmptyUserConfigDir));
    Compiler.BundledCacheBaseUrl := FilenameToUriSafe(
      InclPathDelim(InclPathDelim(TempPackagedDataDir) + 'shader_cache'));
    Compiler.ClearCache(False);

    Gen := TCastleShaderGeneratorRHI.Create(rbVulkan);
    CoreForwardVS := Gen.FinalizeVertexShaderSource(
      Gen.GeneratePreamble(ssVertex) +
      'void main() {' + LineEnding +
      '  castle_vertex_eye = castle_ModelViewMatrix * castle_Vertex;' + LineEnding +
      '  castle_normal_eye = normalize(castle_NormalMatrix * castle_Normal);' + LineEnding +
      '  castle_tex_coord0 = castle_MultiTexCoord0;' + LineEnding +
      '  gl_Position = castle_ProjectionMatrix * castle_vertex_eye;' + LineEnding +
      '}');

    LoadedSPIRV := Compiler.GetOrCompileSPIRV(ssVertex, CoreForwardVS, 'cold_boot_from_bundle_vs');
    AssertTrue('Cold boot must load valid SPIR-V from bundled castle-data:/shader_cache/',
      InspectSPIRVBytecode(LoadedSPIRV, Reflected) and Reflected.IsValid and (Reflected.Stage = ssVertex));

    { 4. Verify TVulkanRHIDevice.LoadPipelineCache seeds VkPipelineCache from bundled data fallback when user config cache is absent }
    if (RealDev <> nil) and RegularFileExists(TempBundledPipelineCacheFile) then
    begin
      TempMissingUserPipelineCacheUrl := FilenameToUriSafe(
        InclPathDelim(TempEmptyUserConfigDir) + 'missing_user_pipeline_cache.bin');
      RealDev.BundledPipelineCacheFallbackUrl := FilenameToUriSafe(TempBundledPipelineCacheFile);
      RealDev.LoadPipelineCache(TempMissingUserPipelineCacheUrl);
      AssertTrue('LoadPipelineCache must seed from BundledPipelineCacheFallbackUrl when user config cache is absent',
        RealDev.PipelineCacheSeededFromBundle);
      AssertTrue('Seeded VkPipelineCache handle must be valid',
        RealDev.PipelineCache <> VK_NULL_HANDLE);
    end;
  finally
    Compiler.DiskCacheBaseUrl := SavedDiskBaseUrl;
    Compiler.BundledCacheBaseUrl := SavedBundledBaseUrl;
    Compiler.ClearCache(False);
    FreeAndNil(Gen);
    FreeAndNil(RealDev);
    FreeAndNil(Manifest);
    FreeAndNil(ManifestText);
    if DirectoryExists(TempRootDir) then
      RemoveNonEmptyDir(TempRootDir, True);
  end;
end;

procedure TTestCastleVulkanRHI.TestVulkanDebugUtilsObjectNamingLabelsAndRenderGraphScopesRHI;
var
  HeadlessDev, RealDev: TVulkanRHIDevice;
  Buf: TRHIBuffer;
  Tex, ExportTex: TRHITexture;
  VS, FS: TRHIShaderModule;
  Pipe: TRHIPipeline;
  QueryPool: TRHIQueryPool;
  PipeDesc: TRHIGraphicsPipelineDesc;
  TexDesc: TRHITextureDesc;
  QueryDesc: TRHIQueryPoolDesc;
  Graph: TRHIRenderGraph;
  Cmd: TVulkanRHICommandList;
  RGTempHandle, RGExportHandle: TRHIRenderGraphResourceHandle;
  Pass0, Pass1: TRHIRenderGraphPass;
  NamedBefore: Cardinal;
begin
  { Part A: Headless deterministic verification of object naming, markers & TRHIRenderGraph debug scopes }
  HeadlessDev := TVulkanRHIDevice.CreateHeadless(VkPhysicalDevice(PtrUInt($7513)));
  Buf := nil;
  Tex := nil;
  ExportTex := nil;
  VS := nil;
  FS := nil;
  Pipe := nil;
  QueryPool := nil;
  Graph := nil;
  try
    HeadlessDev.ResizeSwapchain(64, 64);
    NamedBefore := HeadlessDev.DebugObjectsNamedCount;
    Buf := HeadlessDev.CreateBuffer(
      TRHIBufferDesc.Create(256, [buVertex], muCpuToGpu, 'Phase113_DebugVBO'), nil);
    AssertTrue('Named buffer must increment DebugObjectsNamedCount',
      HeadlessDev.DebugObjectsNamedCount > NamedBefore);
    AssertEquals('LastNamedDebugObject must match buffer DebugName',
      'Phase113_DebugVBO', HeadlessDev.LastNamedDebugObject);

    TexDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuSampled], 1, 1);
    TexDesc.DebugName := 'Phase113_DebugTex';
    Tex := HeadlessDev.CreateTexture(TexDesc);
    AssertEquals('LastNamedDebugObject must match texture View DebugName',
      'Phase113_DebugTex.View', HeadlessDev.LastNamedDebugObject);

    VS := HeadlessDev.CreateShaderModuleFromGLSL(ssVertex,
      'void main() { viewport_size; point_size; }', 'Primitive2D_VS');
    FS := HeadlessDev.CreateShaderModuleFromGLSL(ssFragment,
      'void main() { viewport_size; out_Color = pc.color; }', 'Primitive2D_FS');

    PipeDesc := Default(TRHIGraphicsPipelineDesc);
    PipeDesc.VertexShader := VS;
    PipeDesc.FragmentShader := FS;
    SetLength(PipeDesc.VertexInput.Bindings, 1);
    PipeDesc.VertexInput.Bindings[0].Binding := 0;
    PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector2);
    PipeDesc.VertexInput.Bindings[0].PerInstance := False;
    SetLength(PipeDesc.VertexInput.Attributes, 1);
    PipeDesc.VertexInput.Attributes[0].Location := 0;
    PipeDesc.VertexInput.Attributes[0].Binding := 0;
    PipeDesc.VertexInput.Attributes[0].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[0].Offset := 0;
    PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    PipeDesc.Rasterizer.CullMode := cmNone;
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
    PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    PipeDesc.PushConstantSize := 32;
    PipeDesc.PushConstantStages := [ssVertex, ssFragment];
    SetLength(PipeDesc.ColorAttachmentFormats, 1);
    PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
    PipeDesc.DebugName := 'Phase113_DebugPSO';
    Pipe := HeadlessDev.GetOrCreatePipeline(PipeDesc);
    AssertTrue('Pipeline must be created', Pipe <> nil);

    FillChar(QueryDesc, SizeOf(QueryDesc), 0);
    QueryDesc.QueryType := qtTimestamp;
    QueryDesc.QueryCount := 4;
    QueryPool := HeadlessDev.CreateQueryPool(QueryDesc);
    AssertTrue('QueryPool must be created', QueryPool <> nil);

    TexDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuSampled], 1, 1);
    TexDesc.DebugName := 'Phase113_RGExport';
    ExportTex := HeadlessDev.CreateTexture(TexDesc);

    Graph := TRHIRenderGraph.Create(HeadlessDev);
    RGTempHandle := Graph.DeclareTransientTexture(
      'RG_TempColor', TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));
    RGExportHandle := Graph.ImportExternalTexture('RG_FinalColor', ExportTex, rsUndefined, rsShaderRead);

    FRenderGraphPassExecCount := 0;
    Pass0 := Graph.AddPass('Phase113_GBuffer_Pass');
    Pass0.OnExecute := @DummyRenderGraphPassCallback;
    Pass0.WriteColorAttachment(RGTempHandle);
    Pass1 := Graph.AddPass('Phase113_Composite_Pass');
    Pass1.OnExecute := @DummyRenderGraphPassCallback;
    Pass1.ReadTexture(RGTempHandle);
    Pass1.WriteColorAttachment(RGExportHandle);
    Graph.Compile;

    Cmd := HeadlessDev.BeginFrame as TVulkanRHICommandList;
    try
      Cmd.PushDebugGroup('Phase113_OuterFrameScope', Vector4(0.2, 0.6, 1.0, 1.0));
      Cmd.InsertDebugMarker('Phase113_MidFrameMarker', Vector4(1.0, 0.9, 0.1, 1.0));
      Graph.Execute(Cmd);
      Cmd.PopDebugGroup;

      AssertEquals('TRHIRenderGraph.Execute must emit 2 automatic pass debug scopes',
        2, Integer(Graph.DebugScopesEmittedCount));
      AssertEquals('CommandList must record 1 outer + 2 graph = 3 PushDebugGroup calls',
        3, Integer(Cmd.DebugGroupPushCount));
      AssertEquals('CommandList must record 3 matching PopDebugGroup calls',
        3, Integer(Cmd.DebugGroupPopCount));
      AssertEquals('CommandList must record 1 InsertDebugMarker call',
        1, Integer(Cmd.DebugMarkerCount));
    finally
      HeadlessDev.EndFrameAndPresent;
    end;
  finally
    FreeAndNil(Graph);
    FreeAndNil(ExportTex);
    FreeAndNil(QueryPool);
    Pipe := nil;
    FreeAndNil(FS);
    FreeAndNil(VS);
    FreeAndNil(Tex);
    FreeAndNil(Buf);
    FreeAndNil(HeadlessDev);
  end;

  { Part B: Live Mesa Lavapipe 1.4 VK_EXT_debug_utils object naming, command/queue labels & validation gate }
  RealDev := nil;
  if not TVulkanRHIDevice.TryCreateOffscreen(RealDev, True) then
    Exit;
  Buf := nil;
  Tex := nil;
  ExportTex := nil;
  VS := nil;
  FS := nil;
  QueryPool := nil;
  Graph := nil;
  try
    RealDev.ResetValidationCounters;
    AssertTrue('Device/queue/pipeline-cache creation must already name >= 2 Vulkan objects',
      RealDev.DebugObjectsNamedCount >= 2);

    Buf := RealDev.CreateBuffer(
      TRHIBufferDesc.Create(256, [buUniform], muCpuToGpu, 'Phase113_LiveUBO'), nil);
    TexDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuSampled], 1, 1);
    TexDesc.DebugName := 'Phase113_LiveTex';
    Tex := RealDev.CreateTexture(TexDesc);
    VS := RealDev.CreateShaderModuleFromGLSL(ssVertex,
      'void main() { viewport_size; point_size; }', 'Primitive2D_VS');
    FS := RealDev.CreateShaderModuleFromGLSL(ssFragment,
      'void main() { viewport_size; out_Color = pc.color; }', 'Primitive2D_FS');

    PipeDesc := Default(TRHIGraphicsPipelineDesc);
    PipeDesc.VertexShader := VS;
    PipeDesc.FragmentShader := FS;
    SetLength(PipeDesc.VertexInput.Bindings, 1);
    PipeDesc.VertexInput.Bindings[0].Binding := 0;
    PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector2);
    PipeDesc.VertexInput.Bindings[0].PerInstance := False;
    SetLength(PipeDesc.VertexInput.Attributes, 1);
    PipeDesc.VertexInput.Attributes[0].Location := 0;
    PipeDesc.VertexInput.Attributes[0].Binding := 0;
    PipeDesc.VertexInput.Attributes[0].Format := vafVector2;
    PipeDesc.VertexInput.Attributes[0].Offset := 0;
    PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
    PipeDesc.Rasterizer.CullMode := cmNone;
    PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
    PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
    PipeDesc.PushConstantSize := 32;
    PipeDesc.PushConstantStages := [ssVertex, ssFragment];
    SetLength(PipeDesc.ColorAttachmentFormats, 1);
    PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
    PipeDesc.DebugName := 'Phase113_LivePSO';
    Pipe := RealDev.GetOrCreatePipeline(PipeDesc);
    AssertTrue('Live Vulkan pipeline must be created and named', Pipe <> nil);

    if RealDev.DebugUtilsActive and Assigned(vkSetDebugUtilsObjectNameEXT) then
      AssertTrue('Explicit SetDebugObjectName on live VkBuffer must return VK_SUCCESS',
        RealDev.SetDebugObjectName(VK_OBJECT_TYPE_BUFFER,
          (Buf as TVulkanRHIBuffer).Handle, 'Phase113_ExplicitRenamedUBO'));

    FillChar(QueryDesc, SizeOf(QueryDesc), 0);
    QueryDesc.QueryType := qtTimestamp;
    QueryDesc.QueryCount := 2;
    QueryPool := RealDev.CreateQueryPool(QueryDesc);

    TexDesc := TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuSampled], 1, 1);
    TexDesc.DebugName := 'Phase113_LiveRGExport';
    ExportTex := RealDev.CreateTexture(TexDesc);
    Graph := TRHIRenderGraph.Create(RealDev);
    RGTempHandle := Graph.DeclareTransientTexture(
      'LiveRG_Temp', TRHITextureDesc.Create2D(32, 32, pfRGBA8_UNorm, [tuColorAttachment, tuSampled]));
    RGExportHandle := Graph.ImportExternalTexture('LiveRG_Out', ExportTex, rsUndefined, rsShaderRead);
    Pass0 := Graph.AddPass('LiveRG_PassA');
    Pass0.OnExecute := @DummyRenderGraphPassCallback;
    Pass0.WriteColorAttachment(RGTempHandle);
    Pass1 := Graph.AddPass('LiveRG_PassB');
    Pass1.OnExecute := @DummyRenderGraphPassCallback;
    Pass1.ReadTexture(RGTempHandle);
    Pass1.WriteColorAttachment(RGExportHandle);
    Graph.Compile;

    RealDev.BeginQueueDebugLabel('Phase113_LiveQueueScope', Vector4(0.1, 0.8, 0.4, 1.0));
    RealDev.InsertQueueDebugLabel('Phase113_LiveQueueMarker', Vector4(1.0, 0.5, 0.1, 1.0));
    Cmd := RealDev.BeginOffscreenFrame as TVulkanRHICommandList;
    Cmd.PushDebugGroup('Phase113_LiveCmdScope', Vector4(0.3, 0.5, 0.9, 1.0));
    Cmd.InsertDebugMarker('Phase113_LiveCmdMarker', Vector4(0.9, 0.9, 0.2, 1.0));
    Graph.Execute(Cmd);
    Cmd.PopDebugGroup;
    RealDev.EndOffscreenFrame;
    RealDev.EndQueueDebugLabel;

    AssertEquals('Live TRHIRenderGraph.Execute must emit 2 pass debug scopes',
      2, Integer(Graph.DebugScopesEmittedCount));
    RealDev.AssertZeroValidationErrors('Phase113.DebugUtilsAndRenderGraphScopes');
  finally
    FreeAndNil(Graph);
    FreeAndNil(ExportTex);
    FreeAndNil(QueryPool);
    FreeAndNil(FS);
    FreeAndNil(VS);
    FreeAndNil(Tex);
    FreeAndNil(Buf);
    FreeAndNil(RealDev);
  end;
end;

{$endif read_implementation}
